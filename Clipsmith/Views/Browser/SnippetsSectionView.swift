import SwiftUI
import SwiftData

/// Snippets section of the browser window.
///
/// Left: search, language chips, snippet list. Right: `SnippetEditorView`
/// under a read-only header, with a Paste action in the footer.
///
/// Double-click or ↩ on a row pastes the snippet into the previous app and
/// closes the window.
struct SnippetsSectionView: View {

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
    @State private var languageFilter: String?
    @State private var snippetStore: SnippetStore?
    @FocusState private var isSearchFocused: Bool

    // MARK: - Computed

    private var filteredSnippets: [ClipsmithSchemaV1.Snippet] {
        SnippetFilter.apply(allSnippets, query: searchText, language: languageFilter)
    }

    private var selectedSnippet: ClipsmithSchemaV1.Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return allSnippets.first { $0.persistentModelID == id }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            listPane
            detailPane
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    createNewSnippet()
                } label: {
                    Image(systemName: "plus")
                }
                // ⌘N lives in the hidden buttons below, not here: a toolbar
                // item's shortcut can outlive the section and swallow ⌘N in
                // other sections (Todos).
                .help("New Snippet (⌘N)")
            }
        }
        // Hidden buttons for keyboard shortcuts
        .background {
            Group {
                Button("") { createNewSnippet() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { deleteSelectedSnippet() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            setupSnippetStore()
            if selectedSnippetID == nil, let first = filteredSnippets.first {
                selectedSnippetID = first.persistentModelID
            }
        }
        .onChange(of: filteredSnippets.count) { _, _ in
            if let id = selectedSnippetID,
               !allSnippets.contains(where: { $0.persistentModelID == id }) {
                selectedSnippetID = filteredSnippets.first?.persistentModelID
            }
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        BrowserListPane {
            BrowserSearchField(
                text: $searchText,
                placeholder: "Search snippets…",
                isFocused: $isSearchFocused
            )
        } filter: {
            BrowserFilterRow(
                options: SnippetFilter.languages(in: allSnippets),
                selection: $languageFilter
            )
        } content: {
            if filteredSnippets.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty && languageFilter == nil ? "No snippets" : "No results")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredSnippets, selection: $selectedSnippetID) { snippet in
                    snippetRow(snippet)
                        .tag(snippet.persistentModelID)
                }
                .listStyle(.sidebar)
                .onKeyPress(.return) {
                    if let snippet = selectedSnippet {
                        pasteSnippet(snippet)
                        return .handled
                    }
                    return .ignored
                }
            }
        } footer: {
            BrowserCountsFooter(leading: "\(filteredSnippets.count) snippets", trailing: "")
        }
    }

    @ViewBuilder
    private func snippetRow(_ snippet: ClipsmithSchemaV1.Snippet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                .lineLimit(1)
            if let lang = snippet.language, !lang.isEmpty {
                Text(lang)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let snippet = selectedSnippet {
            BrowserDetailPane {
                HStack(spacing: 8) {
                    Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let lang = snippet.language, !lang.isEmpty {
                        Text(lang)
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            } body: {
                SnippetEditorView(snippet: snippet, snippetStore: snippetStoreInstance)
            } footerLeading: {
                Text("Edited \(snippet.updatedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footerTrailing: {
                Button("Paste ↩") {
                    pasteSnippet(snippet)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            BrowserEmptyDetail(systemImage: "curlybraces", message: "Select a snippet")
        }
    }

    // MARK: - Actions

    private func setupSnippetStore() {
        guard snippetStore == nil else { return }
        snippetStore = SnippetStore(modelContainer: modelContext.container)
    }

    private var snippetStoreInstance: SnippetStore {
        if let store = snippetStore { return store }
        return SnippetStore(modelContainer: modelContext.container)
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
            // New snippet sorts first (updatedAt descending).
            await MainActor.run {
                languageFilter = nil
                selectedSnippetID = allSnippets.first?.persistentModelID
            }
        }
    }

    private func deleteSnippet(_ snippet: ClipsmithSchemaV1.Snippet) {
        setupSnippetStore()
        let id = snippet.persistentModelID
        if selectedSnippetID == id {
            selectedSnippetID = nil
        }
        Task {
            try? await snippetStore?.delete(id: id)
        }
    }

    private func deleteSelectedSnippet() {
        guard let snippet = selectedSnippet else { return }
        deleteSnippet(snippet)
    }

    /// Closes the browser window, drops back to accessory and pastes into the previous app.
    private func pasteSnippet(_ snippet: ClipsmithSchemaV1.Snippet) {
        let content = snippet.content
        let previousApp = appTracker.previousApp
        Task { @MainActor in
            for window in NSApp.windows
            where window.identifier?.rawValue.hasPrefix("browser") == true
                || (window.isVisible && !(window is NSPanel) && window.level == .normal) {
                if window.isVisible { window.close() }
            }
            NSApp.setActivationPolicy(.accessory)
            pasteService.paste(content: content, into: previousApp)
        }
    }
}
