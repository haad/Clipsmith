import SwiftUI

/// Task list for the selected tab: inline new-task row, task rows with
/// checkbox, title, tag chips, and due date (overdue in red). The search
/// field lives in `TodosSectionView`; `searchFocused` says whether it has
/// focus so Space does not toggle a task while typing.
struct TodoListView: View {
    @Environment(TodoStore.self) private var store
    @Bindable var viewModel: TodoWindowViewModel
    let searchFocused: Bool

    @State private var isAddingTask = false
    @State private var draftText = ""
    @FocusState private var draftFocused: Bool
    @State private var editingID: UUID?
    @State private var editText = ""
    @FocusState private var editFocused: Bool
    @State private var isMovePickerShown = false

    private var today: String { TodoDates.dateString() }

    private var items: [TodoItem] {
        viewModel.visibleItems(in: store.document)
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $viewModel.selectedItemID) {
                if isAddingTask {
                    TextField("New task — tags like @today welcome", text: $draftText)
                        .textFieldStyle(.plain)
                        .focused($draftFocused)
                        .onSubmit { commitDraft() }
                        .onExitCommand { cancelDraft() }
                }
                ForEach(items) { item in
                    Group {
                        if item.id == editingID {
                            TextField("Task", text: $editText)
                                .textFieldStyle(.plain)
                                .focused($editFocused)
                                .onSubmit { commitEdit() }
                                .onExitCommand { cancelEdit() }
                                // Clicking away saves, like a Finder rename.
                                .onChange(of: editFocused) { _, focused in
                                    if !focused { commitEdit() }
                                }
                                .padding(.leading, CGFloat(item.indentLevel) * 16)
                        } else {
                            TodoRowView(
                                item: item,
                                today: today,
                                onToggle: { store.toggleDone(id: item.id) },
                                onOpenReference: openSnippetReference
                            )
                            // Drop on a project chip to move it there.
                            .draggable(item.id.uuidString) {
                                Text(item.title)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: Capsule())
                            }
                        }
                    }
                    .tag(item.id)
                }
            }
            // Return / double-click edits; right-click offers Edit and Move to.
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button("Edit") { startEdit(id: id) }
                    Menu("Move to") {
                        ForEach(projectNames, id: \.self) { name in
                            Button(Self.moveLabel(name)) { move(id: id, to: name) }
                                .disabled(name == projectName(ofTask: id))
                        }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first { startEdit(id: id) }
            }
            .onKeyPress(.space) {
                guard !searchFocused && !draftFocused && editingID == nil,
                      let id = viewModel.selectedItemID else { return .ignored }
                store.toggleDone(id: id)
                return .handled
            }
            .popover(isPresented: $isMovePickerShown) {
                if let id = viewModel.selectedItemID {
                    MoveToProjectPicker(
                        names: projectNames,
                        current: projectName(ofTask: id)
                    ) { name in
                        isMovePickerShown = false
                        move(id: id, to: name)
                    }
                }
            }

            if items.isEmpty && !isAddingTask {
                // List renders empty; give keyboard users a hint.
                Text("No tasks — ⌘N to add one")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .background { hiddenShortcuts }
    }

    private var hiddenShortcuts: some View {
        Group {
            Button("") { startDraft() }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(editingID != nil)
            Button("") {
                if viewModel.selectedItemID != nil { isMovePickerShown = true }
            }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(editingID != nil)
            Button("") { viewModel.showCompleted.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("") { openSelectedReference() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(editingID != nil)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func startDraft() {
        cancelEdit()
        isAddingTask = true
        draftText = ""
        draftFocused = true
    }

    private func cancelDraft() {
        isAddingTask = false
        draftText = ""
    }

    /// New tasks go to the current project; on the Today tab they land in
    /// Inbox tagged @today so they show up where the user just created them.
    private func commitDraft() {
        let text = draftText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { cancelDraft(); return }
        var tags: [TodoTag] = []
        if viewModel.selectedTab == .today,
           !TaskPaperParser.tags(in: text).contains(where: { $0.name == "today" }) {
            tags.append(TodoTag(name: "today", value: nil))
        }
        store.addTask(text: text, projectName: viewModel.currentProjectName(), tags: tags)
        cancelDraft()
    }

    // MARK: - Edit

    /// The field holds the whole line minus the "- " marker, tags included,
    /// so tags are edited as text.
    private func startEdit(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        cancelDraft()
        let line = item.rawLine.trimmingCharacters(in: .whitespaces)
        editText = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
        editingID = id
        viewModel.selectedItemID = id
        editFocused = true
    }

    private func commitEdit() {
        if let id = editingID { store.editTask(id: id, text: editText) } // blank = no-op
        cancelEdit()
    }

    private func cancelEdit() {
        editingID = nil
        editText = ""
    }

    // MARK: - Move

    /// Inbox first, then each project name once, in file order.
    private var projectNames: [String] {
        var seen = Set<String>()
        return store.document.projects.map(\.name).filter { seen.insert($0).inserted }
    }

    /// Inbox has no chip any more; as a move target it reads "No project".
    static func moveLabel(_ name: String) -> String {
        name == "Inbox" ? "No project" : name
    }

    private func projectName(ofTask id: UUID) -> String? {
        store.document.projects.first { $0.tasks.contains { $0.id == id } }?.name
    }

    private func move(id: UUID, to name: String) {
        guard name != projectName(ofTask: id) else { return }
        // On a project tab the task leaves the list; on Today it stays.
        if case .project = viewModel.selectedTab { selectNeighbor(of: id) }
        store.moveTask(id: id, toProject: name)
    }

    // MARK: - Snippet references

    /// ⌘O: open the selected task's first `[[snippet]]` reference, if any.
    private func openSelectedReference() {
        guard let id = viewModel.selectedItemID,
              let item = items.first(where: { $0.id == id }),
              let name = SnippetReference.names(in: item.rawLine).first
        else { return }
        openSnippetReference(name)
    }

    // MARK: - Delete

    private func deleteSelected() {
        guard let id = viewModel.selectedItemID else { return }
        selectNeighbor(of: id)
        store.deleteTask(id: id)
    }

    /// Moves selection to the neighbor of a task that is about to leave the list.
    private func selectNeighbor(of id: UUID) {
        let current = items
        guard let idx = current.firstIndex(where: { $0.id == id }) else { return }
        let remaining = current.enumerated().filter { $0.offset != idx }.map(\.element)
        viewModel.selectedItemID = remaining.isEmpty
            ? nil
            : remaining[min(idx, remaining.count - 1)].id
    }
}

/// ⇧⌘M popover: arrow keys pick a project, Return moves, Esc closes.
private struct MoveToProjectPicker: View {
    let names: [String]
    let current: String?
    let onPick: (String) -> Void

    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Move to")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.top, .horizontal], 8)
            List(names, id: \.self, selection: $selection) { name in
                Text(TodoListView.moveLabel(name))
                    .foregroundStyle(name == current ? .secondary : .primary)
            }
            .focused($focused)
            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { picked in
                if let name = picked.first, name != current { onPick(name) }
            }
        }
        .frame(width: 220, height: min(CGFloat(names.count) * 24 + 40, 320))
        .onAppear {
            selection = names.first { $0 != current }
            focused = true
        }
    }
}

/// Opens the browser on Snippets with the named snippet (created there if
/// missing). Goes through the same request path as the hotkeys.
@MainActor
func openSnippetReference(_ name: String) {
    NotificationCenter.default.post(
        name: .clipsmithRequestBrowser,
        object: nil,
        userInfo: BrowserOpenRequest(section: .snippets, query: name).userInfo
    )
}

/// One task row: checkbox, title (with `[[snippet]]` references as link
/// chips), tag chips, due date (red when overdue).
struct TodoRowView: View {
    let item: TodoItem
    let today: String
    let onToggle: () -> Void
    let onOpenReference: (String) -> Void

    private var isOverdue: Bool {
        !item.isDone && (item.dueDateString.map { $0 <= today } ?? false)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.borderless)

            HStack(spacing: 0) {
                ForEach(Array(SnippetReference.segments(in: item.title).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(text)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? .secondary : .primary)
                    case .reference(let name):
                        Button { onOpenReference(name) } label: {
                            Label(name, systemImage: "doc.text")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help("Open snippet “\(name)” (⌘O)")
                    }
                }
            }
            .lineLimit(1)

            ForEach(chipTags, id: \.self) { tag in
                Text(tag.value.map { "@\(tag.name)(\($0))" } ?? "@\(tag.name)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let due = item.dueDateString {
                Text(due)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
        }
        .padding(.leading, CGFloat(item.indentLevel) * 16)
        .padding(.vertical, 2)
    }

    /// due and done render dedicated affordances; everything else is a chip.
    private var chipTags: [TodoTag] {
        item.tags.filter { $0.name != "due" && $0.name != "done" }
    }
}
