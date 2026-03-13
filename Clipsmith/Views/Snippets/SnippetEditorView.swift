import SwiftUI

/// Detail editor pane for a single snippet.
///
/// Top section: name, language picker + tags on one row.
/// Middle: TextEditor for editing content (monospaced).
///
/// Auto-saves via debounced .task(id:) after 500ms idle.
struct SnippetEditorView: View {

    // MARK: - Input

    let snippet: ClipsmithSchemaV1.Snippet
    let snippetStore: SnippetStore

    // MARK: - Environment

    @Environment(GistService.self) private var gistService

    // MARK: - State

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var language: String? = nil
    @State private var tagsText: String = ""
    @AppStorage(AppSettingsKeys.gistDefaultPublic) private var gistDefaultPublic: Bool = false

    // MARK: - Language Options

    private static let languageOptions: [(display: String, value: String?)] = [
        ("Plain Text", nil),
        ("Swift", "swift"),
        ("Python", "python"),
        ("JavaScript", "javascript"),
        ("TypeScript", "typescript"),
        ("Go", "go"),
        ("Rust", "rust"),
        ("Ruby", "ruby"),
        ("Bash", "bash"),
        ("SQL", "sql"),
        ("JSON", "json"),
        ("YAML", "yaml"),
        ("HTML", "html"),
        ("CSS", "css"),
        ("Markdown", "markdown"),
        ("C", "c"),
        ("C++", "cpp"),
        ("Java", "java"),
        ("Kotlin", "kotlin"),
    ]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: name, language picker + tags
            VStack(alignment: .leading, spacing: 8) {
                // Name field
                HStack {
                    Text("Name:")
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("Snippet name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Language picker + Tags on same row
                HStack {
                    Text("Lang:")
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $language) {
                        ForEach(Self.languageOptions, id: \.display) { option in
                            Text(option.display).tag(option.value)
                        }
                    }
                    .frame(maxWidth: 200)

                    Text("Tags:")
                        .foregroundStyle(.secondary)
                    TextField("tag1, tag2, tag3", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Middle: TextEditor (editable)
            VStack(alignment: .leading, spacing: 4) {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                HighlightedTextEditor(text: $content, language: language)
                    .frame(minHeight: 120)
                    .border(Color(NSColor.separatorColor), width: 0.5)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .onAppear {
            loadFromSnippet()
        }
        .onChange(of: snippet.persistentModelID) { _, _ in
            loadFromSnippet()
        }
        // Auto-save with debounce via .task(id:)
        .task(id: saveKey) {
            guard saveKey != initialSaveKey else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await saveSnippet()
        }
        // Observe share-as-gist notification from SnippetWindowView top bar button
        .onReceive(NotificationCenter.default.publisher(for: .flycutShareSnippetAsGist)) { _ in
            Task {
                await shareAsGist()
            }
        }
    }

    // MARK: - Helpers

    /// Combines all editable fields into a single string for change detection.
    private var saveKey: String {
        "\(snippet.persistentModelID.hashValue)|\(name)|\(content)|\(language ?? "")|\(tagsText)"
    }

    /// The key that represents the initially loaded state — used to skip the first
    /// spurious .task(id: saveKey) fire on appear.
    private var initialSaveKey: String {
        let lang = snippet.language ?? ""
        let tags = snippet.tags.joined(separator: ", ")
        return "\(snippet.persistentModelID.hashValue)|\(snippet.name)|\(snippet.content)|\(lang)|\(tags)"
    }

    private func loadFromSnippet() {
        name = snippet.name
        content = snippet.content
        language = snippet.language
        tagsText = snippet.tags.joined(separator: ", ")
    }

    @MainActor
    private func saveSnippet() async {
        let parsedTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        try? await snippetStore.update(
            id: snippet.persistentModelID,
            name: name.isEmpty ? "Untitled Snippet" : name,
            content: content,
            language: language,
            tags: parsedTags
        )
    }

    // MARK: - Share as Gist

    /// Shares the current snippet content as a GitHub Gist.
    ///
    /// One-click share: no confirmation dialog. The Gist URL is automatically
    /// copied to the clipboard by GistService (GIST-04) and a macOS notification
    /// is sent via AppDelegate.sendGistNotification.
    @MainActor
    private func shareAsGist() async {
        guard !content.isEmpty else { return }
        let ext = GistService.languageExtension(for: language)
        let safeName = name.isEmpty ? "snippet" : name.replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeName).\(ext)"
        do {
            let response = try await gistService.createGist(
                filename: filename,
                content: content,
                description: name.isEmpty ? "Snippet from Clipsmith" : name,
                isPublic: gistDefaultPublic
            )
            // Send macOS notification via AppDelegate
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.sendGistNotification(url: response.htmlURL, filename: filename)
            }
        } catch GistError.noToken {
            showNoTokenAlert()
        } catch {
            showShareErrorAlert(error)
        }
    }

    private func showNoTokenAlert() {
        let alert = NSAlert()
        alert.messageText = "No GitHub Token Configured"
        alert.informativeText = "Add your GitHub Personal Access Token in Preferences > Gist to enable Gist sharing."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApp.activate()
            NotificationCenter.default.post(name: .flycutOpenGistSettings, object: nil)
        }
    }

    private func showShareErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Gist Sharing Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
