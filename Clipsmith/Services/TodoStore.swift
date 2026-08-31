import Foundation
import Observation

/// Owns the TaskPaper document: CRUD on tasks/projects, debounced atomic
/// persistence, and a DispatchSource watcher that reloads on external edits
/// (last-write-wins — in-app changes win on the next save).
///
/// No SwiftData: the plain-text file is the single source of truth.
@MainActor
@Observable
final class TodoStore {

    private(set) var document: TaskPaperDocument = .empty
    private(set) var hasPendingChanges = false
    private(set) var fileURL: URL
    /// Last I/O error, surfaced as a non-blocking notice in the todo window.
    var lastError: String?

    private let saveDelay: Duration
    private var hasLoaded = false
    private var saveTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?

    init(fileURL: URL = TodoStore.resolveFileURL(),
         saveDelay: Duration = .milliseconds(500)) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
    }

    isolated deinit {
        // A resumed DispatchSource that is deallocated without an explicit
        // cancel() never runs its cancel handler, leaking the watched fd.
        watcher?.cancel()
    }

    // MARK: - Path resolution

    static func defaultFileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Clipsmith/todos.taskpaper")
    }

    /// UserDefaults override (AppSettingsKeys.todoFilePath) or the default.
    /// The app is not sandboxed, so a plain path is sufficient — no
    /// security-scoped bookmarks needed.
    static func resolveFileURL() -> URL {
        let path = UserDefaults.standard.string(forKey: AppSettingsKeys.todoFilePath) ?? ""
        guard !path.isEmpty else { return defaultFileURL() }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: - Load / save

    func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                document = TaskPaperParser.parse(text)
                lastError = nil
            } catch {
                // Keep in-memory state; surface the error non-blockingly.
                lastError = "Could not read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            }
        } else {
            document = .empty // missing file: created on first save
            lastError = nil
        }
        hasLoaded = true
        startWatcher()
    }

    func loadIfNeeded() {
        if !hasLoaded { load() }
    }

    /// Flushes any pending debounced save immediately. Called by tests and
    /// applicationWillTerminate.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingChanges else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            var doc = document
            if !doc.endsWithNewline, !TaskPaperSerializer.serialize(doc).isEmpty {
                doc.endsWithNewline = true // new files end with a newline
                document = doc
            }
            try Data(TaskPaperSerializer.serialize(document).utf8)
                .write(to: fileURL, options: .atomic)
            hasPendingChanges = false
            lastError = nil
            // Atomic write = rename: the watched fd points at the old inode.
            startWatcher()
        } catch {
            lastError = "Could not save \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func updateFileURL(_ url: URL) {
        saveNow()
        watcher?.cancel()
        watcher = nil
        fileURL = url
        load()
    }

    private func markDirty() {
        hasPendingChanges = true
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    // MARK: - External change watcher

    private func startWatcher() {
        watcher?.cancel()
        watcher = nil
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return } // file missing — re-armed after first save
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.handleFileChanged() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Reload from disk unless there are unsaved in-app changes
    /// (last-write-wins: dirty in-app state overwrites on next save).
    /// A deleted file keeps memory state and is recreated on next save.
    func handleFileChanged() {
        guard !hasPendingChanges else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            markDirty() // schedule recreation with current memory state
            return
        }
        load()
    }

    // MARK: - Task CRUD

    func addTask(text: String, projectName: String?, tags: [TodoTag] = []) {
        var line = text.hasPrefix("- ") ? text : "- " + text
        for tag in tags {
            line += tag.value.map { " @\(tag.name)(\($0))" } ?? " @\(tag.name)"
        }
        let item = TodoItem(rawLine: line)
        let target = projectName ?? "Inbox"
        if let idx = document.projects.firstIndex(where: {
            $0.name.caseInsensitiveCompare(target) == .orderedSame
        }) {
            document.projects[idx].nodes.append(.task(item))
        } else if let projectName {
            // projectName == nil always matches the synthetic Inbox (index 0)
            // above, so reaching here implies projectName is non-nil.
            document.projects.append(TodoProject(
                name: projectName, rawLine: "\(projectName):", nodes: [.task(item)]))
        }
        markDirty()
    }

    func toggleDone(id: UUID) {
        mutateItem(id: id) { item in
            if item.isDone {
                // Anchored to start-of-line/whitespace like
                // TaskPaperParser.tagRegex, so an unrelated substring such as
                // "foo@done.io" in the title is left untouched.
                let cleaned = item.rawLine
                    .replacing(/(?:^|\s)@done(?:\([^()]*\))?/, with: "")
                return TodoItem(rawLine: cleaned, id: item.id)
            } else {
                return TodoItem(
                    rawLine: item.rawLine + " @done(\(TodoDates.dateString()))",
                    id: item.id)
            }
        }
    }

    func editTask(id: UUID, text: String) {
        mutateItem(id: id) { item in
            let tabs = String(repeating: "\t", count: item.indentLevel)
            let body = text.hasPrefix("- ") ? text : "- " + text
            return TodoItem(rawLine: tabs + body, id: item.id)
        }
    }

    func deleteTask(id: UUID) {
        for p in document.projects.indices {
            if let n = document.projects[p].nodes.firstIndex(where: { isTask($0, id: id) }) {
                document.projects[p].nodes.remove(at: n)
                markDirty()
                return
            }
        }
    }

    func moveTask(id: UUID, toProject name: String) {
        guard let item = document.allTasks.first(where: { $0.id == id }) else { return }
        deleteTask(id: id)
        // Re-home at indent 0 in the target project, keeping text and tags.
        let trimmed = item.rawLine.trimmingCharacters(in: .whitespaces)
        var target = document.projects.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        })
        if target == nil {
            document.projects.append(TodoProject(name: name, rawLine: "\(name):", nodes: []))
            target = document.projects.count - 1
        }
        document.projects[target!].nodes.append(.task(TodoItem(rawLine: trimmed, id: item.id)))
        markDirty()
    }

    // MARK: - Project CRUD

    func addProject(name: String) {
        guard !document.projects.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        document.projects.append(TodoProject(name: name, rawLine: "\(name):", nodes: []))
        markDirty()
    }

    func renameProject(id: UUID, to name: String) {
        guard let idx = document.projects.firstIndex(where: { $0.id == id }),
              !document.projects[idx].isInbox else { return }
        document.projects[idx].name = name
        document.projects[idx].rawLine = "\(name):"
        markDirty()
    }

    func deleteProject(id: UUID) {
        guard let idx = document.projects.firstIndex(where: { $0.id == id }),
              !document.projects[idx].isInbox else { return }
        document.projects.remove(at: idx)
        markDirty()
    }

    // MARK: - Private helpers

    private func isTask(_ node: TodoNode, id: UUID) -> Bool {
        if case .task(let item) = node { item.id == id } else { false }
    }

    private func mutateItem(id: UUID, _ transform: (TodoItem) -> TodoItem) {
        for p in document.projects.indices {
            for n in document.projects[p].nodes.indices {
                if case .task(let item) = document.projects[p].nodes[n], item.id == id {
                    document.projects[p].nodes[n] = .task(transform(item))
                    markDirty()
                    return
                }
            }
        }
    }
}
