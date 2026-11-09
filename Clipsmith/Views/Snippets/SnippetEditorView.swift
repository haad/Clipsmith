import SwiftUI

/// Detail editor pane for a single snippet.
///
/// Top section: name, language picker + tags on one row.
/// Middle: TextEditor for editing content (monospaced).
///
/// Auto-saves via debounced .task(id:) after 500ms idle.
struct SnippetEditorView: View {

    // MARK: - Input

    let snippet: Snippet
    /// Markdown snippets: false shows the rendered view, true the raw editor.
    @Binding var isEditing: Bool
    let selection: SnippetSelection

    // MARK: - State

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var language: String? = nil
    @State private var tagsText: String = ""
    @State private var nameWarning: String?

    @Environment(TodoStore.self) private var todoStore
    @Environment(SnippetStore.self) private var snippetStore

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
                if let nameWarning {
                    Text(nameWarning)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 68)
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
                Text(showsRendered ? "Preview" : "Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                Group {
                    if showsRendered {
                        MarkdownWebView(markdown: content, selection: selection)
                    } else {
                        HighlightedTextEditor(text: $content, language: language, selection: selection)
                    }
                }
                    .frame(minHeight: 120)
                    .border(Color(NSColor.separatorColor), width: 0.5)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .onAppear {
            loadFromSnippet()
        }
        .onChange(of: snippet.id) { _, _ in
            loadFromSnippet()
        }
        // The file changed on disk (an editor, git pull): take the new
        // version unless there are unsaved edits here (those win on save).
        .onChange(of: snippet) { old, new in
            guard old.id == new.id, isUnchanged(from: old) else { return }
            loadFromSnippet()
        }
        // Auto-save with debounce via .task(id:)
        .task(id: saveKey) {
            guard saveKey != initialSaveKey else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveSnippet()
        }
    }

    // MARK: - Helpers

    private var showsRendered: Bool { language == "markdown" && !isEditing }

    /// Combines all editable fields into a single string for change detection.
    private var saveKey: String {
        "\(snippet.id.uuidString)|\(name)|\(content)|\(language ?? "")|\(tagsText)"
    }

    /// The key that represents the initially loaded state — used to skip the first
    /// spurious .task(id: saveKey) fire on appear.
    private var initialSaveKey: String {
        let lang = snippet.language ?? ""
        let tags = snippet.tags.joined(separator: ", ")
        return "\(snippet.id.uuidString)|\(snippet.name)|\(snippet.content)|\(lang)|\(tags)"
    }

    private func isUnchanged(from old: Snippet) -> Bool {
        name == old.name && content == old.content && language == old.language
            && tagsText == old.tags.joined(separator: ", ")
    }

    private func loadFromSnippet() {
        name = snippet.name
        nameWarning = nil
        content = snippet.content
        language = snippet.language
        tagsText = snippet.tags.joined(separator: ", ")
    }

    private func saveSnippet() {
        let requestedName = name
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // One call checks uniqueness and writes. A taken name is refused;
        // other fields still save.
        let result = snippetStore.save(
            id: snippet.id, requestedName: requestedName, content: content, language: language, tags: tags)
        if result.savedName != result.previousName {
            todoStore.renameSnippetReferences(from: result.previousName, to: result.savedName)
        }
        let trimmed = requestedName.trimmingCharacters(in: .whitespaces)
        nameWarning = result.nameRefused ? "Another snippet is already named “\(trimmed)”" : nil
        // "a/b" is stored as "a-b" (it is a file name): show what was saved.
        if !result.nameRefused, !trimmed.isEmpty, result.savedName != trimmed {
            name = result.savedName
        }
    }
}
