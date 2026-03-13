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
