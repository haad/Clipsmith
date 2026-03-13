import Foundation

// MARK: - TemplateSubstitutor

/// Pure value type for {{variable}} template substitution.
///
/// Replaces `{{variable}}` tokens in a string with values from a dictionary.
/// Variable names are whitespace-trimmed before lookup. Unknown variables
/// (no matching key in the dictionary) are left as-is in the output string.
struct TemplateSubstitutor {

    // Regex matches {{variable}} and {{ spaced }} patterns.
    // Braces must be escaped: \{\{ and \}\}
    // Named capture group "variable" captures the variable name (may contain whitespace).
    // Computed property (not stored static) avoids Swift 6 Sendable error on Regex type.
    private static var pattern: Regex<(Substring, variable: Substring)> { /\{\{(?<variable>[^}]+)\}\}/ }

    // MARK: - substitute

    /// Replaces all `{{variable}}` tokens in `content` with values from `variables`.
    ///
    /// - Parameters:
    ///   - content: The template string containing `{{variable}}` tokens.
    ///   - variables: A dictionary of variable names to replacement values.
    ///     Variable name lookup is done after trimming whitespace.
    /// - Returns: The content with all known variables substituted.
    ///   Unknown variables are left unchanged as `{{variable}}` in the output.
    static func substitute(in content: String, variables: [String: String]) -> String {
        content.replacing(Self.pattern) { match in
            let key = String(match.variable).trimmingCharacters(in: .whitespaces)
            return variables[key] ?? String(match.0)
        }
    }

    // MARK: - extractVariables

    /// Returns all unique variable names found in the content string.
    ///
    /// Variable names are whitespace-trimmed. Duplicates are removed.
    /// Order reflects first occurrence in the string.
    ///
    /// - Parameter content: The template string to scan.
    /// - Returns: Unique variable names in order of first occurrence.
    static func extractVariables(from content: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for match in content.matches(of: Self.pattern) {
            let key = String(match.variable).trimmingCharacters(in: .whitespaces)
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }
}
