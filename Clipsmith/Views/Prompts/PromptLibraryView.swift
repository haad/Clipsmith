import SwiftUI
import SwiftData

/// Master-detail prompt browser for the Prompts tab.
///
/// Left panel: searchable flat list of all prompts with category badges, a "+" button
/// to create user prompts, and visual distinction between library vs user-created prompts.
/// Right panel: editable detail view with {{variable}} highlighting, Save to My Snippets,
/// and Revert to Original actions.
///
/// Supports #category search syntax: "#coding Python" filters to coding category and
/// searches for "Python". "#my" or "#My Prompts" filters to user-created prompts.
///
/// See ``SnippetWindowView`` for the full keyboard shortcuts reference.
struct PromptLibraryView: View {

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
        guard !searchText.isEmpty else { return allPrompts }

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            let withoutHash = String(trimmed.dropFirst())
            let parts = withoutHash.split(separator: " ", maxSplits: 1)
            let categoryFilter = parts.isEmpty ? "" : String(parts[0]).lowercased()
            let textSearch = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            // Match "my" or partial category name
            let isMyPrompts = categoryFilter == "my" || "my prompts".hasPrefix(categoryFilter)

            return allPrompts.filter { prompt in
                let categoryMatches: Bool
                if isMyPrompts {
                    categoryMatches = prompt.isUserCreated
                } else {
                    categoryMatches = prompt.category.lowercased().hasPrefix(categoryFilter)
                }
                guard categoryMatches else { return false }
                if textSearch.isEmpty { return true }
                return prompt.title.localizedCaseInsensitiveContains(textSearch)
                    || prompt.content.localizedCaseInsensitiveContains(textSearch)
            }
        }

        return allPrompts.filter { prompt in
            prompt.title.localizedCaseInsensitiveContains(trimmed)
            || prompt.content.localizedCaseInsensitiveContains(trimmed)
            || prompt.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var selectedPrompt: ClipsmithSchemaV2.PromptLibraryItem? {
        guard let id = selectedPromptID else { return nil }
        return allPrompts.first { $0.persistentModelID == id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search prompts... (#coding, #writing)", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onKeyPress(.tab) {
                        isSearchFocused = false
                        isListFocused = true
                        return .handled
                    }
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
                // Left: prompt list
                leftPanel

                // Right: detail view
                rightPanel
            }
        }
        // Hidden keyboard shortcuts
        .background {
            Group {
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
            // Cancel pending save when switching selection
            saveTask?.cancel()
            saveTask = nil
            // Populate edit fields from newly selected prompt
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

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Toolbar: "+" button
            HStack {
                Spacer()
                Button {
                    createNewPrompt()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .padding(8)
                .help("New Prompt (⌘N)")
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if filteredPrompts.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? "No prompts" : "No results")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredPrompts, selection: $selectedPromptID) { prompt in
                    promptRow(prompt)
                        .tag(prompt.persistentModelID)
                }
                .listStyle(.plain)
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
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var rightPanel: some View {
        if let prompt = selectedPrompt {
            detailView(for: prompt)
        } else {
            VStack {
                Spacer()
                Text("Select a prompt")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Prompt Row

    @ViewBuilder
    private func promptRow(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) -> some View {
        HStack(spacing: 6) {
            // Icon: book.fill for library, person.fill for user-created
            Image(systemName: prompt.isUserCreated ? "person.fill" : "book.fill")
                .foregroundStyle(prompt.isUserCreated ? Color.accentColor : Color.secondary)
                .font(.caption)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(prompt.title.isEmpty ? "Untitled" : prompt.title)
                        .lineLimit(1)
                    // Orange "edited" indicator for customized library prompts
                    if prompt.isUserCustomized && !prompt.isUserCreated {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .help("Customized — edited from original")
                    }
                }
                // Category badge
                categoryBadge(for: prompt)
            }

            Spacer()
        }
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

    // MARK: - Detail View

    private func detailView(for prompt: ClipsmithSchemaV2.PromptLibraryItem) -> some View {
        let variables = TemplateSubstitutor.extractVariables(from: editedContent)

        return VStack(alignment: .leading, spacing: 0) {
            // Header: title + category badge
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content editor
            TextEditor(text: $editedContent)
                .font(.body)
                .padding(8)
                .onChange(of: editedContent) { _, _ in
                    scheduleSave(for: prompt)
                }

            Divider()

            // Variables note (shown when {{variables}} are detected)
            if !variables.isEmpty {
                HStack {
                    Image(systemName: "curlybraces")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Variables: \(variables.map { "{{\($0)}}" }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()
            }

            // Action buttons
            HStack(spacing: 8) {
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

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                // Select the new prompt (it will appear at top of filtered list after @Query refresh)
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

    /// Schedules a debounced save of the current edit state.
    ///
    /// Auto-saves title + content 0.75s after the last keystroke.
    /// For library prompts, this sets isUserCustomized = true.
    /// Skips save if values haven't actually changed from the model (avoids
    /// marking prompts as edited on selection change).
    private func scheduleSave(for prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        guard editedTitle != prompt.title || editedContent != prompt.content else { return }
        saveTask?.cancel()
        let id = prompt.persistentModelID
        let title = editedTitle
        let content = editedContent
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 750_000_000) // 0.75s debounce
            guard !Task.isCancelled else { return }
            try? await promptStore?.update(id: id, title: title, content: content)
        }
    }

    private func revertPrompt(_ prompt: ClipsmithSchemaV2.PromptLibraryItem) {
        guard prompt.isUserCustomized && !prompt.isUserCreated else { return }
        setupStores()

        // Show NSAlert confirmation
        let alert = NSAlert()
        alert.messageText = "Revert to Original?"
        alert.informativeText = "Your edits to \"\(prompt.title)\" will be discarded. The prompt will be restored to the upstream version on next sync."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

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

        // Read clipboard for {{clipboard}} substitution
        let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""

        // Build variables from UserDefaults (user-defined) + built-in clipboard
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
            // Close snippet window
            for window in NSApp.windows where !window.isPanel {
                if window.isVisible && window.level == .normal {
                    window.close()
                }
            }
            NSApp.setActivationPolicy(.accessory)
            pasteService.paste(content: substituted, into: previousApp)
        }
    }
}

// MARK: - NSWindow Extension

private extension NSWindow {
    var isPanel: Bool { self is NSPanel }
}
