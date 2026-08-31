import Foundation

/// Result of parsing the quick-add bezel's inline syntax.
struct TodoQuickAddResult: Sendable, Equatable {
    let title: String
    /// nil → Inbox. Matching against existing projects (case-insensitive)
    /// and creating unmatched ones is TodoStore.addTask's job.
    let projectName: String?
    let tags: [TodoTag]
}

/// Todoist-style inline syntax:
/// `Fix pricing page #lara @due(2026-09-05) @today`
/// → project "lara", tags [due(2026-09-05), today], title "Fix pricing page".
enum TodoQuickAddParser {
    static func parse(_ input: String) -> TodoQuickAddResult {
        var projectName: String?
        var tags: [TodoTag] = []
        var titleParts: [String] = []

        for tokenSub in input.split(whereSeparator: \.isWhitespace) {
            let token = String(tokenSub)
            if token.hasPrefix("#"), token.count > 1, projectName == nil {
                projectName = String(token.dropFirst())
            } else if token.hasPrefix("@"), token.count > 1,
                      let match = try? TaskPaperParser.tagRegex.wholeMatch(in: token) {
                tags.append(TodoTag(
                    name: String(match.output.1),
                    value: match.output.2.map(String.init)))
            } else {
                titleParts.append(token)
            }
        }
        return TodoQuickAddResult(
            title: titleParts.joined(separator: " "),
            projectName: projectName,
            tags: tags)
    }
}
