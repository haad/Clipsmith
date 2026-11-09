import Foundation

/// How a snippet maps to a file: `<name>.<ext>`, extension from language,
/// and an optional three-line tags header:
///
///     ---
///     tags: [work, blog]
///     ---
///
/// Only that exact shape is a header, so a YAML document that starts with
/// `---` stays content.
nonisolated enum SnippetFileFormat {

    private static let extensions: [String: String] = [
        "swift": "swift", "python": "py", "javascript": "js", "typescript": "ts",
        "go": "go", "rust": "rs", "ruby": "rb", "bash": "sh", "sql": "sql",
        "json": "json", "yaml": "yaml", "html": "html", "css": "css",
        "markdown": "md", "c": "c", "cpp": "cpp", "java": "java", "kotlin": "kt",
    ]

    private static let languages: [String: String] = {
        var map = Dictionary(uniqueKeysWithValues: extensions.map { ($1, $0) })
        for (ext, lang) in ["yml": "yaml", "markdown": "markdown", "zsh": "bash",
                            "jsx": "javascript", "tsx": "typescript", "h": "c",
                            "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "kts": "kotlin",
                            "htm": "html"] {
            map[ext] = lang
        }
        return map
    }()

    static let plainExtension = "txt"

    /// `nil`/empty language = plain text.
    static func fileExtension(for language: String?) -> String {
        guard let language, !language.isEmpty else { return plainExtension }
        return extensions[language] ?? plainExtension
    }

    /// `nil` for `txt` and for extensions we don't know.
    static func language(forExtension ext: String) -> String? {
        languages[ext.lowercased()]
    }

    static func isKnownExtension(_ ext: String) -> Bool {
        ext.lowercased() == plainExtension || languages[ext.lowercased()] != nil
    }

    /// The name a file can carry: `/` and `:` become `-`, leading dots
    /// (hidden files) are dropped, whitespace trimmed.
    static func sanitizedName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func encode(content: String, tags: [String]) -> String {
        guard !tags.isEmpty else { return content }
        return "---\ntags: [\(tags.joined(separator: ", "))]\n---\n" + content
    }

    static func decode(_ text: String) -> (content: String, tags: [String]) {
        let lines = text.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
        guard lines.count >= 3,
              lines[0] == "---", lines[2] == "---",
              lines[1].hasPrefix("tags:")
        else { return (text, []) }
        var value = lines[1].dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        let tags = value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (lines.count > 3 ? String(lines[3]) : "", tags)
    }
}
