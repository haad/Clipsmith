import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "SnippetStore"
)

/// One snippet = one file in the snippets folder (see `SnippetFileFormat`).
struct Snippet: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var content: String
    var language: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var fileURL: URL
}

/// Outcome of `SnippetStore.save`: what the name was, what it is now, and
/// whether the requested name was refused because another snippet has it.
struct SnippetSaveResult: Equatable, Sendable {
    let previousName: String
    let savedName: String
    let nameRefused: Bool
}

/// Snippets as plain files in a folder the user owns (grepable, git-able).
/// The folder is the source of truth: FSEvents trigger a rescan, so edits
/// made in an editor show up. Ids are in-memory and stable per file path.
@MainActor
@Observable
final class SnippetStore {

    /// Most recently updated first.
    private(set) var snippets: [Snippet] = []
    private(set) var folderURL: URL
    var lastError: String?

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private let watches: Bool

    init(folderURL: URL, watches: Bool = true) {
        self.folderURL = folderURL
        self.watches = watches
    }

    // MARK: - Load

    func load() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            lastError = "Could not create \(folderURL.path): \(error.localizedDescription)"
        }
        if watches {
            watcher = FolderWatcher(url: folderURL) { [weak self] in self?.rescan() }
        }
        rescan()
    }

    func updateFolder(_ url: URL) {
        watcher = nil
        folderURL = url
        snippets = []
        load()
    }

    /// Re-reads files whose modification date changed; keeps the rest.
    func rescan() {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return }
        var byPath = Dictionary(snippets.map { ($0.fileURL.standardizedFileURL.path, $0) },
                                uniquingKeysWith: { a, _ in a })
        var result: [Snippet] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            let modified = values.contentModificationDate ?? .distantPast
            if let known = byPath.removeValue(forKey: path), known.updatedAt == modified {
                result.append(known)
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let (content, tags) = SnippetFileFormat.decode(text)
            let ext = url.pathExtension
            result.append(Snippet(
                id: snippets.first { $0.fileURL.standardizedFileURL.path == path }?.id ?? UUID(),
                name: ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent,
                content: content,
                language: SnippetFileFormat.language(forExtension: ext),
                tags: tags,
                createdAt: values.creationDate ?? modified,
                updatedAt: modified,
                fileURL: url))
        }
        result.sort { $0.updatedAt > $1.updatedAt }
        if result != snippets { snippets = result }
    }

    // MARK: - Lookup

    func snippet(id: UUID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    /// Case-insensitive, like macOS file names; `[[name]]` must be unambiguous.
    func isNameTaken(_ name: String, excluding id: UUID?) -> Bool {
        snippets.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// `base` if free, else "<base> 2", "<base> 3", ...
    func availableName(base: String) -> String {
        guard isNameTaken(base, excluding: nil) else { return base }
        var n = 2
        while isNameTaken("\(base) \(n)", excluding: nil) { n += 1 }
        return "\(base) \(n)"
    }

    /// With duplicates on disk (same stem, two extensions), the most recent.
    func findByName(_ name: String) -> UUID? {
        snippets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }

    // MARK: - Mutations

    /// Always gets a free name derived from `base` (blank → "Untitled Snippet").
    @discardableResult
    func insert(base: String, content: String, language: String?, tags: [String]) -> UUID? {
        var clean = SnippetFileFormat.sanitizedName(base)
        if clean.isEmpty { clean = "Untitled Snippet" }
        let name = availableName(base: clean)
        let url = fileURL(name: name, language: language, keepingExtensionOf: nil)
        guard write(content: content, tags: tags, to: url) else { return nil }
        let id = UUID()
        let dates = fileDates(url)
        snippets.insert(Snippet(id: id, name: name, content: content, language: normalized(language),
                                tags: tags, createdAt: dates.created, updatedAt: dates.modified,
                                fileURL: url), at: 0)
        return id
    }

    /// The snippet a `[[name]]` link opens; created (empty) when missing.
    func findOrCreate(name: String, language: String?) -> (id: UUID, created: Bool)? {
        if let id = findByName(name) { return (id, false) }
        return insert(base: name, content: "", language: language, tags: []).map { ($0, true) }
    }

    /// Writes all fields; a rename or language change renames the file. A
    /// blank or taken name keeps the current one (`nameRefused` only for taken).
    func save(id: UUID, requestedName: String, content: String,
              language: String?, tags: [String]) -> SnippetSaveResult {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else {
            return SnippetSaveResult(previousName: "", savedName: "", nameRefused: false)
        }
        let old = snippets[index]
        let requested = SnippetFileFormat.sanitizedName(requestedName)
        var name = requested.isEmpty ? old.name : requested
        let refused = isNameTaken(name, excluding: id)
        if refused { name = old.name }

        let url = fileURL(name: name, language: language, keepingExtensionOf: old.fileURL)
        if url.lastPathComponent != old.fileURL.lastPathComponent {
            guard move(old.fileURL, to: url) else {
                return SnippetSaveResult(previousName: old.name, savedName: old.name, nameRefused: refused)
            }
        }
        guard write(content: content, tags: tags, to: url) else {
            return SnippetSaveResult(previousName: old.name, savedName: old.name, nameRefused: refused)
        }
        let dates = fileDates(url)
        snippets[index] = Snippet(id: id, name: name, content: content, language: normalized(language),
                                  tags: tags, createdAt: old.createdAt, updatedAt: dates.modified,
                                  fileURL: url)
        snippets.sort { $0.updatedAt > $1.updatedAt }
        return SnippetSaveResult(previousName: old.name, savedName: name, nameRefused: refused)
    }

    /// Moves the file to the Trash, so a deleted note can be recovered.
    func delete(id: UUID) {
        guard let snippet = snippet(id: id) else { return }
        do {
            try FileManager.default.trashItem(at: snippet.fileURL, resultingItemURL: nil)
        } catch {
            try? FileManager.default.removeItem(at: snippet.fileURL)
        }
        snippets.removeAll { $0.id == id }
    }

    /// Migration: keeps the original dates so ordering survives.
    func importSnippet(name: String, content: String, language: String?, tags: [String],
                       createdAt: Date, updatedAt: Date) {
        guard let id = insert(base: name, content: content, language: language, tags: tags),
              let url = snippet(id: id)?.fileURL else { return }
        try? FileManager.default.setAttributes(
            [.creationDate: createdAt, .modificationDate: updatedAt], ofItemAtPath: url.path)
        if let i = snippets.firstIndex(where: { $0.id == id }) {
            snippets[i].createdAt = createdAt
            snippets[i].updatedAt = fileDates(url).modified
            snippets.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: - Files

    private func normalized(_ language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language
    }

    /// Plain text keeps an unknown extension it was loaded with (`.toml`).
    private func fileURL(name: String, language: String?, keepingExtensionOf existing: URL?) -> URL {
        var ext = SnippetFileFormat.fileExtension(for: language)
        if normalized(language) == nil, let existing,
           !SnippetFileFormat.isKnownExtension(existing.pathExtension) {
            ext = existing.pathExtension
        }
        return folderURL.appending(path: ext.isEmpty ? name : "\(name).\(ext)")
    }

    private func write(content: String, tags: [String], to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try Data(SnippetFileFormat.encode(content: content, tags: tags).utf8)
                .write(to: url, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            logger.error("write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Case-only renames go through a temporary name: the volume is
    /// usually case-insensitive, so `foo.md` → `Foo.md` is "already exists".
    private func move(_ from: URL, to: URL) -> Bool {
        let fm = FileManager.default
        do {
            if from.path.caseInsensitiveCompare(to.path) == .orderedSame {
                let temp = folderURL.appending(path: ".rename-\(UUID().uuidString)")
                try fm.moveItem(at: from, to: temp)
                try fm.moveItem(at: temp, to: to)
            } else {
                try fm.moveItem(at: from, to: to)
            }
            return true
        } catch {
            lastError = "Could not rename \(from.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    private func fileDates(_ url: URL) -> (created: Date, modified: Date) {
        var url = url
        url.removeAllCachedResourceValues() // URL caches values; we just wrote the file
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let modified = values?.contentModificationDate ?? .now
        return (values?.creationDate ?? modified, modified)
    }
}
