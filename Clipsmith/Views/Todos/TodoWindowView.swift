import SwiftUI

/// Root view for the todos WindowGroup: tab strip (Today first, then one tab
/// per project, Inbox when non-empty, "+" to add a project) above the task list.
///
/// ## Keyboard Shortcuts
///
/// | Shortcut  | Action                          |
/// |-----------|---------------------------------|
/// | ⌘1…⌘9     | Switch tabs                     |
/// | ⌘N        | New task (inline edit row)      |
/// | Space     | Toggle done on selection        |
/// | ⌘⌫        | Delete selected task            |
/// | ⌘F        | Focus search                    |
/// | ⇧⌘H       | Toggle show-completed           |
/// | ↑↓        | Navigate list                   |
/// | ⎋         | Close window                    |
struct TodoWindowView: View {
    @Environment(TodoStore.self) private var store
    @State private var viewModel = TodoWindowViewModel()
    @State private var isAddingProject = false
    @State private var newProjectName = ""

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            TodoListView(viewModel: viewModel)
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(6)
            }
        }
        .task {
            store.loadIfNeeded()
        }
        .onChange(of: tabs) { _, newTabs in
            // Keep selection valid when a project disappears (external edit).
            if !newTabs.contains(viewModel.selectedTab) {
                viewModel.selectedTab = .today
            }
        }
        // ⎋ closes the window (yields to focused text fields)
        .onExitCommand {
            NSApp.keyWindow?.close()
        }
        .background { tabShortcutButtons }
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
        .onDisappear {
            // Restore accessory policy when the todo window closes,
            // but only if no other regular windows remain visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let visibleRegularWindows = NSApp.windows.filter {
                    $0.isVisible && !($0 is NSPanel) && $0.level == .normal
                }
                if visibleRegularWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private var tabs: [TodoWindowViewModel.Tab] {
        viewModel.tabs(for: store.document)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
            }
            Spacer(minLength: 4)
            Button {
                isAddingProject = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add project")
        }
        .padding(8)
    }

    private func tabButton(_ tab: TodoWindowViewModel.Tab) -> some View {
        Button {
            viewModel.selectedTab = tab
        } label: {
            Text(tab.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    viewModel.selectedTab == tab
                        ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                        : AnyShapeStyle(.clear),
                    in: Capsule())
        }
        .buttonStyle(.borderless)
    }

    /// Hidden ⌘1…⌘9 buttons — same pattern as SnippetWindowView.
    private var tabShortcutButtons: some View {
        Group {
            ForEach(Array(tabs.prefix(9).enumerated()), id: \.offset) { index, tab in
                Button("") { viewModel.selectedTab = tab }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
