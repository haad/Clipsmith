import Foundation

/// `[[Snippet name]]` references inside todo text.
///
/// The todo file stores names only; matching is case-insensitive on the
/// trimmed name. `[[` without a closing `]]` and empty `[[ ]]` stay text.
enum SnippetReference {

    enum Segment: Equatable, Sendable {
        case text(String)
        case reference(String)
    }

    nonisolated(unsafe) private static let pattern = /\[\[([^\[\]]*)\]\]/

    static func segments(in text: String) -> [Segment] {
        var result: [Segment] = []
        var pending = ""
        var cursor = text.startIndex
        for match in text.matches(of: pattern) {
            pending += text[cursor..<match.range.lowerBound]
            let name = match.output.1.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                pending += text[match.range]
            } else {
                if !pending.isEmpty { result.append(.text(pending)) }
                pending = ""
                result.append(.reference(name))
            }
            cursor = match.range.upperBound
        }
        pending += text[cursor...]
        if !pending.isEmpty { result.append(.text(pending)) }
        return result
    }

    static func names(in text: String) -> [String] {
        segments(in: text).compactMap {
            if case .reference(let name) = $0 { name } else { nil }
        }
    }

    /// Replaces every reference to `oldName` with `[[newName]]`; all other
    /// characters are left exactly as they were.
    static func rewriting(_ text: String, from oldName: String, to newName: String) -> String {
        text.replacing(pattern) { match in
            let name = match.output.1.trimmingCharacters(in: .whitespaces)
            return name.caseInsensitiveCompare(oldName) == .orderedSame
                ? "[[\(newName)]]"
                : String(text[match.range])
        }
    }
}
