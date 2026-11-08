import SwiftUI
import SwiftData

/// Prompts section of the browser window.
///
/// Left: search (with `#category` / `#my` syntax), category chips, prompt
/// list. Right: editable title and content with variables caption and the
/// Save to My Snippets / Revert / Paste actions in the footer.
struct PromptsSectionView: View {

    // MARK: - Environment

    @Environment(PasteService.self) private var pasteService
    @Environment(AppTracker.self) private var appTracker
    @Environment(\.modelContext) private var modelContext

    // MARK: - Query

    @Query(sort: \ClipsmithSchemaV2.PromptLibraryItem.title)
    private var allPrompts: [ClipsmithSchemaV2.PromptLibraryItem]

    // MARK: - State

    @State private var searchText: String = ""
    @State private var selectedPromptID: PersistentIdentifier?
    @State private var chipID: String?
    @State private var promptStore: PromptLibraryStore?
    @State private var snippetStore: SnippetStore?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isListFocused: Bool

    // Edit state for the selected prompt
    @State private var editedTitle: String = ""
    @State private var editedContent: String = ""
    @State private var saveTask: Task<Void, Never>?

    // MARK: - Computed

    private var filteredPrompts: [ClipsmithSchemaV2.PromptLibraryItem] {
        PromptFilter.apply(allPrompts, query: searchText, chip: chipID.flatMap(PromptFilter.Chip.init(id:)))
    }

    private var selectedPrompt: ClipsmithSchemaV2.PromptLibraryItem? {
        guard let id = selectedPromptID else { return nil }
        return allPrompts.first { $0.persistentModelID == id }
    }

    private var mineCount: Int { allPrompts.filter(\.isUserCreated).count }

    // MARK: - Body

    var body: some View {
        HSplitView {
            listPane
            detailPane
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    createNewPrompt()
                } label: {
                    Image(systemName: "plus")
                }
                // ⌘N lives in the hidden buttons below, not here: a toolbar
                // item's shortcut can outlive the section and swallow ⌘N in
                // other sections (Todos).
                .help("New Prompt (⌘N)")
            }
        }
        .background {
            Group {
                Button("") { createNewPrompt() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { deleteSelectedPrompt() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            setupStores()
            if selectedPromptID == nil, let first = filteredPrompts.first {
                selectedPromptID = first.persistentModelID
            }
        }
        .onChange(of: filteredPrompts.count) { _, _ in
            if let id = selectedPromptID,
               !allPrompts.contains(where: { $0.persistentModelID == id }) {
                selectedPromptID = filteredPrompts.first?.persistentModelID
            }
        }
        .onChange(of: selectedPromptID) { _, newID in
            saveTask?.cancel()
            saveTask = nil
            if let id = newID,
               let prompt = allPrompts.first(where: { $0.persistentModelID == id }) {
                editedTitle = prompt.title
                editedContent = prompt.content
            } else {
                editedTitle = ""
                editedContent = ""
            }
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        BrowserListPane {
            BrowserSearchField(
                text: $searchText,
                placeholder: "Search prompts… (#coding, #my)",
                isFocused: $isSearchFocused
            )
            .onKeyPress(.tab) {
                isSearchFocused = false
                isListFocused = true
                return .handled
            }
        } filter: {
            BrowserFilterRow(options: PromptFilter.options(in: allPrompts), selection: $chipID)
        } content: {
            if filteredPrompts.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty && chipID == nil ? "No prompts" : "No results")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredPrompts, selection: $selectedPromptID) { prompt in
                    promptRow(prompt)
                        .tag(prompt.persistentModelID)
                }
                .listStyle(.sidebar)
                .focused($isListFocused)
                .onKeyPress(.return) {
                    if let prompt = selectedPrompt {
                        pastePrompt(prompt)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(characters: .init(charactersIn: "jk")) { press in
                    navigateList(direction: press.characters == "j" ? .down : .up)
                    return .handled
                }
            }
        } footer: {
            BrowserCountsFooter(leading: "\(filteredPrompts.count) prompts", trailing: "\(mineCount) mine")
        }
    }

    @ViewBuilder
    private func promptRow(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: prompt.isUserCreated ? "person.fill" : "book.fill")
                .foregroundStyle(prompt.isUserCreated ? Color.accentColor : Color.secondary)
                .font(.caption)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(prompt.title.isEmpty ? "Untitled" : prompt.title)
                        .lineLimit(1)
                    if prompt.isUserCustomized && !prompt.isUserCreated {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .help("Customized — edited from original")
                    }
                }
                categoryBadge(for: prompt)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            pastePrompt(prompt)
        }
        .onTapGesture(count: 1) {
            selectedPromptID = prompt.persistentModelID
        }
        .contextMenu {
            if prompt.isUserCreated {
                Button("Delete", role: .destructive) {
                    deletePrompt(prompt)
                }
            }
            if prompt.isUserCustomized && !prompt.isUserCreated {
                Button("Revert to Original") {
                    revertPrompt(prompt)
                }
            }
        }
    }

    // MARK: - Category Badge

    private func categoryBadge(for prompt: ClipsmithSchemaV2.PromptLibraryItem) -> some View {
        let label = prompt.isUserCreated ? "My Prompts" : prompt.category
        return Text(label)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(badgeColor(for: prompt))
            )
    }

    private func badgeColor(for prompt: ClipsmithSchemaV2.PromptLibraryItem) -> Color {
        if prompt.isUserCreated { return .gray }
        switch prompt.category {
        case "coding":   return .blue
        case "writing":  return .green
        case "analysis": return .purple
        case "creative": return .orange
        default:         return .gray
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let prompt = selectedPrompt {
            detailView(for: prompt)
        } else {
            BrowserEmptyDetail(systemImage: "text.book.closed", message: "Select a prompt")
        }
    }

    private func detailView(for prompt: ClipsmithSchemaV2.PromptLibraryItem) -> some View {
        let variables = TemplateSubstitutor.extractVariables(from: editedContent)

        return BrowserDetailPane {
            HStack {
                TextField("Prompt title", text: $editedTitle)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .onChange(of: editedTitle) { _, _ in
                        scheduleSave(for: prompt)
                    }
                Spacer()
                categoryBadge(for: prompt)
                if prompt.isUserCustomized && !prompt.isUserCreated {
                    Text("edited")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.15))
                        )
                }
            }
        } body: {
            TextEditor(text: $editedContent)
                .font(.body)
                .padding(8)
                .onChange(of: editedContent) { _, _ in
                    scheduleSave(for: prompt)
                }
        } footerLeading: {
            if !variables.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "curlybraces")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Variables: \(variables.map { "{{\($0)}}" }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if variables.contains("clipboard") {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption2)
                            Text("{{clipboard}} will include clipboard content")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
        } footerTrailing: {
            Button("Save to My Snippets") {
                saveToSnippets(prompt)
            }
            .buttonStyle(.bordered)
            .help("Create an independent Snippet copy of this prompt")

            if prompt.isUserCustomized && !prompt.isUserCreated {
                Button("Revert to Original") {
                    revertPrompt(prompt)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.orange)
                .help("Restore this prompt to its original upstream version")
            }

            Button("Paste ↩") {
                pastePrompt(prompt)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func setupStores() {
        guard promptStore == nil else { return }
        promptStore = PromptLibraryStore(modelContainer: modelContext.container)
        snippetStore = SnippetStore(modelContainer: modelContext.container)
    }

    private func createNewPrompt() {
        setupStores()
        let newID = UUID().uuidString
        Task {
            try? await promptStore?.insert(
                id: newID,
                title: "New Prompt",
                content: "",
                category: "My Prompts",
                version: 1,
                isUserCreated: true
            )
            await MainActor.run {
                chipID = nil
                selectedPromptID = allPrompts.first(where: { $0.id == newID })?.persistentModelID
                    ?? filteredPrompts.first?.persistentModelID
            }
        }
    }

    private func deletePrompt(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        guard prompt.isUserCreated else { return }
        setupStores()
        let id = prompt.persistentModelID
        if selectedPromptID == id {
            selectedPromptID = nil
        }
        Task {
            try? await promptStore?.delete(id: id)
        }
    }

    private enum NavigationDirection { case up, down }

    private func navigateList(direction: NavigationDirection) {
        let prompts = filteredPrompts
        guard !prompts.isEmpty else { return }
        guard let currentID = selectedPromptID,
              let currentIndex = prompts.firstIndex(where: { $0.persistentModelID == currentID }) else {
            selectedPromptID = prompts.first?.persistentModelID
            return
        }
        let newIndex: Int
        switch direction {
        case .down: newIndex = min(currentIndex + 1, prompts.count - 1)
        case .up:   newIndex = max(currentIndex - 1, 0)
        }
        selectedPromptID = prompts[newIndex].persistentModelID
    }

    private func deleteSelectedPrompt() {
        guard let prompt = selectedPrompt, prompt.isUserCreated else { return }
        deletePrompt(prompt)
    }

    /// Debounced save of title + content 0.75 s after the last keystroke.
    /// For library prompts this sets `isUserCustomized`. Skips when nothing changed.
    private func scheduleSave(for prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        guard editedTitle != prompt.title || editedContent != prompt.content else { return }
        saveTask?.cancel()
        let id = prompt.persistentModelID
        let title = editedTitle
        let content = editedContent
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            try? await promptStore?.update(id: id, title: title, content: content)
        }
    }

    private func revertPrompt(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        guard prompt.isUserCustomized && !prompt.isUserCreated else { return }
        setupStores()

        let alert = NSAlert()
        alert.messageText = "Revert to Original?"
        alert.informativeText = "Your edits to \"\(prompt.title)\" will be discarded. The prompt will be restored to the upstream version on next sync."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let id = prompt.persistentModelID
        Task {
            try? await promptStore?.revertToOriginal(id: id)
        }
    }

    private func saveToSnippets(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        setupStores()
        let title = editedTitle.isEmpty ? prompt.title : editedTitle
        let content = editedContent.isEmpty ? prompt.content : editedContent
        let category = prompt.isUserCreated ? "My Prompts" : prompt.category
        Task {
            try? await snippetStore?.insert(
                name: title,
                content: content,
                language: nil,
                tags: ["prompt", category]
            )
        }
    }

    private func pastePrompt(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        let content = prompt.content
        let previousApp = appTracker.previousApp

        let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
        var variables: [String: String] = ["clipboard": clipboardContent]
        if let jsonData = UserDefaults.standard.data(forKey: AppSettingsKeys.promptLibraryVariables),
           let kvPairs = try? JSONDecoder().decode([[String: String]].self, from: jsonData) {
            for pair in kvPairs {
                if let key = pair["key"], let value = pair["value"], !key.isEmpty {
                    variables[key] = value
                }
            }
        }

        let substituted = TemplateSubstitutor.substitute(in: content, variables: variables)

        Task { @MainActor in
            for window in NSApp.windows where !(window is NSPanel) {
                if window.isVisible && window.level == .normal {
                    window.close()
                }
            }
            NSApp.setActivationPolicy(.accessory)
            pasteService.paste(content: substituted, into: previousApp)
        }
    }
}
