import Foundation

// MARK: - TodoTag

/// A TaskPaper tag: `@name` or `@name(value)`.
struct TodoTag: Sendable, Equatable, Hashable {
    let name: String
    let value: String?
}

// MARK: - TodoItem

/// A single task line. `rawLine` is the verbatim source line (including
/// leading tabs) — serialization emits it unchanged, which is what makes
/// the parse → serialize round trip byte-exact for unedited items.
struct TodoItem: Sendable, Equatable, Identifiable {
    /// In-memory identity for UI selection. Never serialized.
    let id: UUID
    let rawLine: String
    let indentLevel: Int
    let title: String
    let tags: [TodoTag]

    init(rawLine: String, id: UUID = UUID()) {
        self.id = id
        self.rawLine = rawLine
        self.indentLevel = rawLine.prefix(while: { $0 == "\t" }).count
        self.tags = TaskPaperParser.tags(in: rawLine)
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
        self.title = TaskPaperParser.strippingTags(body)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func tag(named name: String) -> TodoTag? {
        tags.first { $0.name == name }
    }

    var isDone: Bool { tag(named: "done") != nil }
    var doneDate: String? { tag(named: "done")?.value }
    var isToday: Bool { tag(named: "today") != nil }

    /// The raw `@due(...)` value. YYYY-MM-DD sorts lexicographically, so
    /// overdue checks compare strings — no timezone pitfalls.
    var dueDateString: String? { tag(named: "due")?.value }

    var dueDate: Date? {
        guard let s = dueDateString else { return nil }
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - TodoNode

/// One line inside a project: a task, or any other line kept verbatim.
enum TodoNode: Sendable, Equatable {
    case task(TodoItem)
    case note(String)
}

// MARK: - TodoProject

/// A project and its ordered lines. The synthetic Inbox (rawLine == nil)
/// holds everything that precedes the first project line.
struct TodoProject: Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var rawLine: String?
    var nodes: [TodoNode]

    init(name: String, rawLine: String?, nodes: [TodoNode], id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.rawLine = rawLine
        self.nodes = nodes
    }

    var isInbox: Bool { rawLine == nil }

    var tasks: [TodoItem] {
        nodes.compactMap { if case .task(let item) = $0 { item } else { nil } }
    }
}

// MARK: - TaskPaperDocument

struct TaskPaperDocument: Sendable, Equatable {
    var projects: [TodoProject]
    var endsWithNewline: Bool

    static let empty = TaskPaperDocument(
        projects: [TodoProject(name: "Inbox", rawLine: nil, nodes: [])],
        endsWithNewline: false
    )

    var allTasks: [TodoItem] { projects.flatMap(\.tasks) }
}

// MARK: - TodoDates

enum TodoDates {
    /// "YYYY-MM-DD" in the current calendar — the format used by @done/@due.
    static func dateString(from date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - TaskPaperParser

enum TaskPaperParser {

    /// `@name` or `@name(value)`, preceded by whitespace or line start —
    /// so email addresses are not tags. Swift's regex literals don't support
    /// variable-width lookbehind, so the preceding whitespace/start-of-line
    /// is matched (and consumed) by a non-capturing alternation instead of
    /// `(?<=\s|^)`; being non-capturing, it doesn't shift the name/value
    /// capture group indices used below.
    nonisolated(unsafe) static let tagRegex =
        /(?:^|\s)@([A-Za-z0-9_-]+)(?:\(([^()]*)\))?/

    static func tags(in line: String) -> [TodoTag] {
        line.matches(of: tagRegex).map {
            TodoTag(name: String($0.output.1), value: $0.output.2.map(String.init))
        }
    }

    static func strippingTags(_ line: String) -> String {
        line.replacing(tagRegex, with: "")
    }

    static func parse(_ text: String) -> TaskPaperDocument {
        let endsWithNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        if lines == [""] && !endsWithNewline { lines = [] } // empty input

        var projects = [TodoProject(name: "Inbox", rawLine: nil, nodes: [])]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                projects[projects.count - 1].nodes.append(.task(TodoItem(rawLine: line)))
            } else if isProjectLine(trimmed) {
                projects.append(TodoProject(
                    name: projectName(from: trimmed), rawLine: line, nodes: []))
            } else {
                projects[projects.count - 1].nodes.append(.note(line))
            }
        }
        return TaskPaperDocument(projects: projects, endsWithNewline: endsWithNewline)
    }

    /// A project is a non-task line whose text — ignoring trailing tags —
    /// ends in ":" with a non-empty name.
    private static func isProjectLine(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        let stripped = strippingTags(trimmed).trimmingCharacters(in: .whitespaces)
        return stripped.hasSuffix(":") && stripped.count > 1
    }

    private static func projectName(from trimmed: String) -> String {
        let stripped = strippingTags(trimmed).trimmingCharacters(in: .whitespaces)
        return String(stripped.dropLast())
    }
}

// MARK: - TaskPaperSerializer

enum TaskPaperSerializer {
    static func serialize(_ document: TaskPaperDocument) -> String {
        var lines: [String] = []
        for project in document.projects {
            if let raw = project.rawLine { lines.append(raw) }
            for node in project.nodes {
                switch node {
                case .task(let item): lines.append(item.rawLine)
                case .note(let line): lines.append(line)
                }
            }
        }
        // No lines at all → empty output regardless of endsWithNewline.
        // (Input "\n" parses to ONE empty note line, so it still round-trips.)
        guard !lines.isEmpty else { return "" }
        var out = lines.joined(separator: "\n")
        if document.endsWithNewline { out += "\n" }
        return out
    }
}
