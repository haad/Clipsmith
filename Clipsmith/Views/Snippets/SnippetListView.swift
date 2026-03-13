import SwiftUI
import SwiftData

/// Master-detail snippet browser.
///
/// Left panel: searchable list of snippet names with language badges and a "+" button.
/// Right panel: SnippetEditorView for the selected snippet.
///
/// Double-click or Enter on a snippet name pastes the snippet into the frontmost app
/// and closes the window (via PasteService).
///
/// See ``SnippetWindowView`` for the full keyboard shortcuts reference.
struct SnippetListView: View {

    // MARK: - Environment

    @Environment(PasteService.self) private var pasteService
    @Environment(AppTracker.self) private var appTracker
    @Environment(\.modelContext) private var modelContext

    // MARK: - Query

    @Query(sort: \ClipsmithSchemaV1.Snippet.updatedAt, order: .reverse)
    private var allSnippets: [ClipsmithSchemaV1.Snippet]

    // MARK: - State

    @State private var searchText: String = ""
    @State private var selectedSnippetID: PersistentIdentifier?
    @State private var snippetStore: SnippetStore?
    @FocusState private var isSearchFocused: Bool

    // MARK: - Computed

    private var filteredSnippets: [ClipsmithSchemaV1.Snippet] {
        guard !searchText.isEmpty else { return allSnippets }
        return allSnippets.filter { snippet in
            snippet.name.localizedCaseInsensitiveContains(searchText)
            || snippet.content.localizedCaseInsensitiveContains(searchText)
            || snippet.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var selectedSnippet: ClipsmithSchemaV1.Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return allSnippets.first { $0.persistentModelID == id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search snippets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HSplitView {
                // Left: snippet name list
                VStack(spacing: 0) {
                    // Toolbar row: "+" button (⌘N)
                    HStack {
                        Spacer()
                        Button {
                            createNewSnippet()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("n", modifiers: .command)
                        .padding(8)
                        .help("New Snippet (⌘N)")
                    }
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    if filteredSnippets.isEmpty {
                        VStack {
                            Spacer()
                            Text(searchText.isEmpty ? "No snippets" : "No results")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List(filteredSnippets, selection: $selectedSnippetID) { snippet in
                            snippetRow(snippet)
                                .tag(snippet.persistentModelID)
                        }
                        .listStyle(.plain)
                        // ↩ Return pastes selected snippet and closes window
                        .onKeyPress(.return) {
                            if let snippet = selectedSnippet {
                                pasteSnippet(snippet)
                                return .handled
                            }
                            return .ignored
                        }
                    }
                }
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

                // Right: editor
                if let snippet = selectedSnippet {
                    SnippetEditorView(snippet: snippet, snippetStore: snippetStoreInstance)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a snippet to edit")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // Hidden buttons for keyboard shortcuts
        .background {
            Group {
                // ⌘F → focus search field
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                // ⌘⌫ → delete selected snippet
                Button("") { deleteSelectedSnippet() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            setupSnippetStore()
            // Select the first snippet automatically
            if selectedSnippetID == nil, let first = filteredSnippets.first {
                selectedSnippetID = first.persistentModelID
            }
        }
        .onChange(of: filteredSnippets.count) { _, _ in
            // Reselect if current selection disappeared
            if let id = selectedSnippetID,
               !allSnippets.contains(where: { $0.persistentModelID == id }) {
                selectedSnippetID = filteredSnippets.first?.persistentModelID
            }
        }
    }

    // MARK: - Snippet Row

    @ViewBuilder
    private func snippetRow(_ snippet: ClipsmithSchemaV1.Snippet) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                    .lineLimit(1)
                if let lang = snippet.language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            pasteSnippet(snippet)
        }
        .onTapGesture(count: 1) {
            selectedSnippetID = snippet.persistentModelID
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                deleteSnippet(snippet)
            }
        }
    }

    // MARK: - Actions

    private func setupSnippetStore() {
        guard snippetStore == nil else { return }
        snippetStore = SnippetStore(modelContainer: modelContext.container)
    }

    private var snippetStoreInstance: SnippetStore {
        if let store = snippetStore { return store }
        let store = SnippetStore(modelContainer: modelContext.container)
        return store
    }

    private func createNewSnippet() {
        setupSnippetStore()
        Task {
            try? await snippetStore?.insert(
                name: "Untitled Snippet",
                content: "",
                language: nil,
                tags: []
            )
            // Select the newly created snippet (it will appear at top due to updatedAt sort)
            await MainActor.run {
                selectedSnippetID = allSnippets.first?.persistentModelID
            }
        }
    }

    private func deleteSnippet(_ snippet: ClipsmithSchemaV1.Snippet) {
        setupSnippetStore()
        let id = snippet.persistentModelID
        // If this was the selected snippet, deselect first
        if selectedSnippetID == id {
            selectedSnippetID = nil
        }
        Task {
            try? await snippetStore?.delete(id: id)
        }
    }

    /// Deletes the currently selected snippet (triggered by ⌘⌫).
    private func deleteSelectedSnippet() {
        guard let snippet = selectedSnippet else { return }
        deleteSnippet(snippet)
    }

    private func pasteSnippet(_ snippet: ClipsmithSchemaV1.Snippet) {
        let content = snippet.content
        let previousApp = appTracker.previousApp

        // Close the snippet window by switching back to accessory policy
        // The window will lose visibility when the previous app is activated
        Task { @MainActor in
            // Find and close the snippets window
            for window in NSApp.windows where window.title.isEmpty || window.identifier?.rawValue == "snippets" {
                if window.isVisible && !(window is NSPanel) {
                    window.close()
                }
            }
            NSApp.setActivationPolicy(.accessory)
            await pasteService.paste(content: content, into: previousApp)
        }
    }
}
