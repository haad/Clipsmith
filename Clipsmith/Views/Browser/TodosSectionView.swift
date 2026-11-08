import SwiftUI

/// Todos section of the browser window: search, a chip row (Today, All,
/// then one chip per project) and the task list.
///
/// ## Keyboard Shortcuts
///
/// | Shortcut  | Action                          |
/// |-----------|---------------------------------|
/// | ⇧⌘[ / ⇧⌘] | Previous / next tab             |
/// | ⌘N        | New task (inline edit row)      |
/// | Space     | Toggle done on selection        |
/// | ⌘⌫        | Delete selected task            |
/// | ⌘F        | Focus search                    |
/// | ⇧⌘H       | Toggle show-completed           |
/// | ↑↓        | Navigate list                   |
struct TodosSectionView: View {
    @Environment(TodoStore.self) private var store
    @Bindable var viewModel: TodoWindowViewModel
    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            BrowserSearchField(
                text: $viewModel.searchText,
                placeholder: "Search tasks — @tag terms match tags",
                isFocused: $isSearchFocused
            )
            Divider()
            BrowserFilterRow(
                options: projectOptions,
                selection: tabSelection,
                leadingLabel: "Today",
                acceptsDrop: { $0 != Self.allChipID },
                onDrop: dropTasks
            )
            TodoListView(viewModel: viewModel, searchFocused: isSearchFocused)
            Divider()
            footer
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    isAddingProject = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add Project")
            }
        }
        .background {
            Group {
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { viewModel.moveTab(by: -1, in: tabs) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("") { viewModel.moveTab(by: 1, in: tabs) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            store.loadIfNeeded()
        }
        .onChange(of: tabs) { _, newTabs in
            // Keep selection valid when a project disappears (external edit).
            if !newTabs.contains(viewModel.selectedTab) {
                viewModel.selectedTab = .today
            }
        }
        .alert("New Project", isPresented: $isAddingProject) {
            TextField("Project name", text: $newProjectName)
            Button("Add") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    store.addProject(name: name)
                    viewModel.selectedTab = .project(name)
                }
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
    }

    // MARK: - Tabs as chips

    private var tabs: [TodoWindowViewModel.Tab] {
        viewModel.tabs(for: store.document)
    }

    /// Chip id for All. A control character can't appear in a project name
    /// typed into the file, so it never collides with one.
    private static let allChipID = "\u{1}all"

    private var projectOptions: [BrowserFilterOption] {
        tabs.compactMap { tab in
            switch tab {
            case .today: nil
            case .all: BrowserFilterOption(id: Self.allChipID, label: tab.label)
            case .project(let name): BrowserFilterOption(id: name, label: name)
            }
        }
    }

    /// nil ↔ Today, allChipID ↔ All, otherwise the project name.
    private var tabSelection: Binding<String?> {
        Binding(
            get: {
                switch viewModel.selectedTab {
                case .today: nil
                case .all: Self.allChipID
                case .project(let name): name
                }
            },
            set: { id in
                switch id {
                case nil: viewModel.selectedTab = .today
                case Self.allChipID: viewModel.selectedTab = .all
                case let name?: viewModel.selectedTab = .project(name)
                }
            }
        )
    }

    /// Dragged rows carry their task id as a string; dropping them on a
    /// project chip moves them there.
    private func dropTasks(onProject name: String, _ payload: [String]) -> Bool {
        let ids = payload.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return false }
        for id in ids { store.moveTask(id: id, toProject: name) }
        return true
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            let count = viewModel.visibleItems(in: store.document).count
            Text("\(count) \(count == 1 ? "task" : "tasks")")
            if let error = store.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("Show completed", isOn: $viewModel.showCompleted)
                .toggleStyle(.checkbox)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
