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

    // MARK: - State

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var language: String? = nil
    @State private var tagsText: String = ""

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
}
