import Foundation
import AppKit

/// Pure text transformation and formatting utilities.
///
/// All functions are static — no actor isolation issues under Swift 6 strict concurrency.
/// Used by quick action menu to transform clipboard text before pasting.
enum TextTransformer {

    // MARK: - Case transforms

    /// Converts text to UPPERCASE.
    static func uppercase(_ s: String) -> String {
        s.uppercased()
    }

    /// Converts text to lowercase.
    static func lowercase(_ s: String) -> String {
        s.lowercased()
    }

    /// Converts text to Title Case.
    ///
    /// Note: Uses `capitalized` which handles most Latin text correctly.
    /// Known edge case: apostrophes (e.g. "don't" → "Don'T") — acceptable per plan RESEARCH.md Pitfall 6.
    static func titleCase(_ s: String) -> String {
        s.capitalized
    }

    // MARK: - Identifier case conversions

    /// Splits a string into lowercase word tokens on whitespace, punctuation
    /// (`-`, `_`, etc.), and lower→Upper camelCase boundaries.
    ///
    /// Simple boundary rule only: "userId" → ["user", "id"]. Consecutive
    /// capitals are NOT split ("HTTPServer" → ["httpserver"]) — acceptable.
    private static func words(_ s: String) -> [String] {
        var separated = ""
        var prev: Character?
        for c in s {
            if let p = prev, c.isUppercase, (p.isLowercase || p.isNumber) {
                separated.append(" ")
            }
            separated.append(c)
            prev = c
        }
        return separated
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    /// Converts to camelCase. Returns input unchanged if it contains no words.
    static func camelCase(_ s: String) -> String {
        let w = words(s)
        guard let first = w.first else { return s }
        return first + w.dropFirst().map(\.capitalized).joined()
    }

    /// Converts to PascalCase. Returns input unchanged if it contains no words.
    static func pascalCase(_ s: String) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        return w.map(\.capitalized).joined()
    }

    /// Converts to snake_case. Returns input unchanged if it contains no words.
    static func snakeCase(_ s: String) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        return w.joined(separator: "_")
    }

    /// Converts to kebab-case. Returns input unchanged if it contains no words.
    static func kebabCase(_ s: String) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        return w.joined(separator: "-")
    }

    // MARK: - Whitespace

    /// Removes leading and trailing whitespace and newlines.
    static func trimWhitespace(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - URL encoding

    /// Percent-encodes the string for use in a URL query.
    ///
    /// Returns the original string unchanged if encoding fails.
    static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    /// Decodes percent-encoded characters in the string.
    ///
    /// Returns the original string unchanged if decoding fails.
    static func urlDecode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    // MARK: - Formatting

    /// Wraps the string in double-quote characters.
    static func wrapInQuotes(_ s: String) -> String {
        "\"\(s)\""
    }

    /// Wraps the string in a Markdown fenced code block.
    static func markdownCodeBlock(_ s: String) -> String {
        "```\n\(s)\n```"
    }

    /// Pretty-prints a JSON string with 2-space indentation.
    ///
    /// Returns the original string unchanged if it is not valid JSON.
    static func jsonPrettyPrint(_ s: String) -> String {
        guard
            let data = s.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let result = String(data: pretty, encoding: .utf8)
        else {
            return s
        }
        return result
    }

    // MARK: - Line operations

    /// Sorts lines alphabetically (ascending, case-sensitive).
    static func sortLines(_ s: String) -> String {
        s.components(separatedBy: "\n").sorted().joined(separator: "\n")
    }

    /// Removes duplicate lines, keeping the first occurrence and original order.
    static func dedupeLines(_ s: String) -> String {
        var seen = Set<String>()
        return s.components(separatedBy: "\n")
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }

    /// Reverses line order.
    static func reverseLines(_ s: String) -> String {
        s.components(separatedBy: "\n").reversed().joined(separator: "\n")
    }

    // MARK: - Slugify

    /// Converts to a lowercase URL slug: diacritics folded, non-alphanumerics
    /// collapsed into single hyphens.
    static func slugify(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    // MARK: - Escape / Unescape

    /// Escapes backslashes, double quotes, newlines, and tabs (C/JSON string style).
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Reverses `escape(_:)`. Replacement order matters: backslashes last so
    /// escaped sequences are not double-processed.
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - RTF

    /// Renders the string as RTF data using a monospaced system font.
    ///
    /// Returns `nil` if RTF encoding fails (should not happen in practice).
    static func copyAsRTF(_ s: String) -> Data? {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: s, attributes: attributes)
        let range = NSRange(location: 0, length: attributed.length)
        return attributed.rtf(from: range, documentAttributes: [:])
    }
}
