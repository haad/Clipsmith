import SwiftUI

/// Task list for the selected tab: search bar, inline new-task row, task rows
/// with checkbox, title, tag chips, and due date (overdue in red).
struct TodoListView: View {
    @Environment(TodoStore.self) private var store
    @Bindable var viewModel: TodoWindowViewModel

    @State private var isAddingTask = false
    @State private var draftText = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var draftFocused: Bool

    private var today: String { TodoDates.dateString() }

    private var items: [TodoItem] {
        viewModel.visibleItems(in: store.document)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search — @tag terms match tags", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(8)

            Divider()

            List(selection: $viewModel.selectedItemID) {
                if isAddingTask {
                    TextField("New task — tags like @today welcome", text: $draftText)
                        .textFieldStyle(.plain)
                        .focused($draftFocused)
                        .onSubmit { commitDraft() }
                        .onExitCommand { cancelDraft() }
                }
                ForEach(items) { item in
                    TodoRowView(item: item, today: today) {
                        store.toggleDone(id: item.id)
                    }
                    .tag(item.id)
                }
            }
            .onKeyPress(.space) {
                guard !searchFocused && !draftFocused,
                      let id = viewModel.selectedItemID else { return .ignored }
                store.toggleDone(id: id)
                return .handled
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
            Button("") { viewModel.showCompleted.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func startDraft() {
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
        if viewModel.selectedTab == .today && !text.contains("@today") {
            tags.append(TodoTag(name: "today", value: nil))
        }
        store.addTask(text: text, projectName: viewModel.currentProjectName(), tags: tags)
        cancelDraft()
    }

    private func deleteSelected() {
        guard let id = viewModel.selectedItemID else { return }
        let current = items
        // Move selection to the neighbor before deleting.
        if let idx = current.firstIndex(where: { $0.id == id }) {
            let remaining = current.enumerated().filter { $0.offset != idx }.map(\.element)
            viewModel.selectedItemID = remaining.isEmpty
                ? nil
                : remaining[min(idx, remaining.count - 1)].id
        }
        store.deleteTask(id: id)
    }
}

/// One task row: checkbox, title, tag chips, due date (red when overdue).
struct TodoRowView: View {
    let item: TodoItem
    let today: String
    let onToggle: () -> Void

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

            Text(item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
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
