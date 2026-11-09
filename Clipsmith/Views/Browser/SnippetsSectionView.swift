import SwiftUI

/// Snippets section of the browser window.
///
/// Left: search, language chips, snippet list. Right: `SnippetEditorView`
/// under a read-only header, with a Paste action in the footer.
///
/// Double-click or ↩ on a row pastes the snippet into the previous app and
/// closes the window.
struct SnippetsSectionView: View {

    let windowViewModel: BrowserWindowViewModel

    // MARK: - Environment

    @Environment(PasteService.self) private var pasteService
    @Environment(AppTracker.self) private var appTracker
    @Environment(SnippetStore.self) private var snippetStore
    @Environment(TodoStore.self) private var todoStore
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled = false

    private var allSnippets: [Snippet] { snippetStore.snippets }

    // MARK: - State

    @State private var searchText: String = ""
    @State private var selectedSnippetID: UUID?
    @State private var languageFilter: String?
    @FocusState private var isSearchFocused: Bool
    /// Markdown snippets open rendered; ⌘E / Edit switches to the raw editor.
    @State private var isEditingMarkdown = false
    /// Snippet that should open in edit mode once selected (a freshly
    /// created `[[reference]]` target). Consumed by the selection change,
    /// which otherwise resets edit mode.
    @State private var openInEditFor: UUID?
    @State private var selection = SnippetSelection()

    // MARK: - Computed

    private var filteredSnippets: [Snippet] {
        SnippetFilter.apply(allSnippets, query: searchText, language: languageFilter)
    }

    private var selectedSnippet: Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return allSnippets.first { $0.id == id }
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
                Button("") {
                    if selectedSnippet?.language == "markdown" { isEditingMarkdown.toggle() }
                }
                    .keyboardShortcut("e", modifiers: .command)
                Button("") {
                    if let snippet = selectedSnippet { pasteSnippet(snippet) }
                }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("") { deleteSelectedSnippet() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            if todoTrackingEnabled { todoStore.loadIfNeeded() }
            consumePendingSnippetName()
            if selectedSnippetID == nil, let first = filteredSnippets.first {
                selectedSnippetID = first.id
            }
        }
        .onChange(of: selectedSnippetID) { _, newID in
            isEditingMarkdown = newID != nil && newID == openInEditFor
            openInEditFor = nil
        }
        .onChange(of: windowViewModel.pendingSnippetName) { _, _ in
            consumePendingSnippetName()
        }
        .onChange(of: filteredSnippets.count) { _, _ in
            if let id = selectedSnippetID,
               !allSnippets.contains(where: { $0.id == id }) {
                selectedSnippetID = filteredSnippets.first?.id
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
                let duplicates = SnippetFilter.duplicateNames(allSnippets.map(\.name))
                List(filteredSnippets, selection: $selectedSnippetID) { snippet in
                    snippetRow(snippet, isDuplicate: duplicates.contains(snippet.name.lowercased()))
                        .tag(snippet.id)
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
    private func snippetRow(_ snippet: Snippet, isDuplicate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                    .lineLimit(1)
                if isDuplicate {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Another snippet has the same name — rename one so [[links]] stay unambiguous")
                }
            }
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
            selectedSnippetID = snippet.id
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
                    if snippet.language == "markdown" {
                        Spacer()
                        Button(isEditingMarkdown ? "Done" : "Edit") { isEditingMarkdown.toggle() }
                            .help(isEditingMarkdown ? "Show formatted (⌘E)" : "Edit markdown (⌘E)")
                    }
                }
            } body: {
                SnippetEditorView(
                    snippet: snippet,
                    isEditing: $isEditingMarkdown,
                    selection: selection
                )
            } footerLeading: {
                HStack(spacing: 12) {
                    Text("Edited \(snippet.updatedAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    backlinksMenu(for: snippet)
                }
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

    // MARK: - Backlinks

    private var backlinkTasks: [TodoItem] {
        guard todoTrackingEnabled, let snippet = selectedSnippet else { return [] }
        return todoStore.document.allTasks.filter { SnippetReference.mentions($0.rawLine, name: snippet.name) }
    }

    private var backlinkSnippets: [Snippet] {
        guard let snippet = selectedSnippet else { return [] }
        return allSnippets.filter { $0.id != snippet.id && SnippetReference.mentions($0.content, name: snippet.name) }
    }

    /// Todos and snippets whose text links here with `[[name]]`.
    @ViewBuilder
    private func backlinksMenu(for snippet: Snippet) -> some View {
        let tasks = backlinkTasks
        let notes = backlinkSnippets
        if !tasks.isEmpty || !notes.isEmpty {
            Menu("Referenced by \(tasks.count + notes.count)") {
                ForEach(tasks) { task in
                    Button { openTodo(task.id) } label: {
                        Label(task.title, systemImage: task.isDone ? "checkmark.circle" : "circle")
                    }
                }
                if !tasks.isEmpty && !notes.isEmpty { Divider() }
                ForEach(notes) { note in
                    Button { selectedSnippetID = note.id } label: {
                        Label(note.name, systemImage: "doc.text")
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
            .help("Todos and snippets that link here with [[\(snippet.name)]]")
        }
    }

    // MARK: - Actions

    private func createNewSnippet() {
        guard let id = snippetStore.insert(base: "Untitled Snippet", content: "", language: nil, tags: [])
        else { return }
        languageFilter = nil
        selectedSnippetID = id
    }

    /// A todo `[[name]]` was opened: select that snippet, or create an empty
    /// markdown one and open it for editing.
    private func consumePendingSnippetName() {
        guard let name = windowViewModel.pendingSnippetName else { return }
        windowViewModel.pendingSnippetName = nil
        searchText = ""
        languageFilter = nil
        guard let (id, created) = snippetStore.findOrCreate(name: name, language: "markdown") else { return }
        if created { openInEditFor = id }
        selectedSnippetID = id
    }

    private func deleteSnippet(_ snippet: Snippet) {
        if selectedSnippetID == snippet.id {
            selectedSnippetID = nil
        }
        snippetStore.delete(id: snippet.id)
    }

    private func deleteSelectedSnippet() {
        guard let snippet = selectedSnippet else { return }
        deleteSnippet(snippet)
    }

    /// Closes the browser window, drops back to accessory and pastes into the previous app.
    /// Markdown snippets paste only the selected text when there is a selection.
    private func pasteSnippet(_ snippet: Snippet) {
        let full = snippet.content
        let language = snippet.language
        let previousApp = appTracker.previousApp
        Task { @MainActor in
            // Read the selection before the window (and its views) close.
            let selected = language == "markdown" ? await selection.selectedText() : nil
            let content = SnippetPaste.content(full: full, language: language, selection: selected)
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
