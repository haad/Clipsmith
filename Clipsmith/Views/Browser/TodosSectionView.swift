import SwiftUI

/// Todos section of the browser window: search, a chip row (Today first,
/// then one chip per project, Inbox when non-empty) and the task list.
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
            BrowserFilterRow(options: projectOptions, selection: tabSelection, leadingLabel: "Today")
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

    private var projectOptions: [BrowserFilterOption] {
        tabs.compactMap { tab in
            if case .project(let name) = tab {
                return BrowserFilterOption(id: name, label: name)
            }
            return nil
        }
    }

    /// nil ↔ Today, otherwise the project name.
    private var tabSelection: Binding<String?> {
        Binding(
            get: {
                if case .project(let name) = viewModel.selectedTab { return name }
                return nil
            },
            set: { viewModel.selectedTab = $0.map(TodoWindowViewModel.Tab.project) ?? .today }
        )
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
