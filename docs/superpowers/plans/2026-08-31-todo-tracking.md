# Todo Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keyboard-first todo tracking backed by a plain-text TaskPaper file: parser/serializer with byte-fidelity round-trip, a `TodoStore` with debounced atomic saves and file watching, a tabbed todo window, and a quick-add bezel — all behind the `todoTrackingEnabled` feature flag.

**Architecture:** Plain-text file is the single source of truth (no SwiftData). `TaskPaperParser`/`TaskPaperSerializer` convert between text and value types; `TodoStore` (`@MainActor @Observable`) owns the document and file I/O; SwiftUI window + NSPanel bezel follow the existing snippets-window and launcher-bezel patterns.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (NSPanel), XCTest, KeyboardShortcuts (existing SPM dep). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-31-todo-tracking-design.md`

## Global Constraints

- Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`, macOS deployment target 15.0.
- `@MainActor` on all UI-facing classes; `Sendable` on all model/data types.
- Feature flag `todoTrackingEnabled`, default `false`, guarded at invocation site (not registration).
- File location default: `~/Library/Application Support/Clipsmith/todos.taskpaper`, user-overridable via `AppSettingsKeys.todoFilePath`.
- Done handling: `@done(YYYY-MM-DD)` tag in place.
- Round-trip invariant: parse → serialize with no edits reproduces input byte-for-byte.
- Out of scope for v1: priorities, subtask fold/collapse, recurrence, reminders, multiple files, sync conflict resolution beyond last-write-wins.
- `project.pbxproj` is manually managed. This plan allocates IDs: file refs `AF0103`–`AF0114`, build files `AA0103`–`AA0114`, group `GG0017` (Views/Todos). App sources build phase = `BB0002`, test sources build phase = `BB0005`, Services group = `GG0004`, Views group = `GG0005`, Views/Settings group = `GG0009`, tests group = `GG0010`.
- Build: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`. Tests: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/<SuiteName>`.
- Test classes: `@MainActor final class XxxTests: XCTestCase` (project convention).

**Deviation from spec (flagged during planning):** the spec mentions security-scoped bookmarks for paths outside the container. The app is NOT sandboxed (`ENABLE_APP_SANDBOX = NO`), so security-scoped bookmarks are inert — a plain path string in UserDefaults is sufficient and is what this plan implements. The spec's "stale bookmark → fall back to default" case becomes "unreadable path → error surfaced in store, memory state kept".

### pbxproj registration recipe (referenced by tasks below)

To register a new source file `<Name>.swift` with file-ref ID `AFxxxx` and build-file ID `AAxxxx`:

1. In `/* Begin PBXBuildFile section */` add (keep numeric order):
   `\t\tAAxxxx /* <Name>.swift in Sources */ = {isa = PBXBuildFile; fileRef = AFxxxx /* <Name>.swift */; };`
2. In `/* Begin PBXFileReference section */` add:
   `\t\tAFxxxx /* <Name>.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = <Name>.swift; sourceTree = "<group>"; };`
3. Add `AFxxxx /* <Name>.swift */,` to the `children` of the owning group (`GG0004` Services, `GG0017` Views/Todos, `GG0009` Views/Settings, `GG0010` ClipsmithTests).
4. Add `AAxxxx /* <Name>.swift in Sources */,` to the `files` list of `BB0002 /* Sources */` (app files) or `BB0005 /* Sources */` (test files).

---

### Task 1: TaskPaper models, parser, serializer

**Files:**
- Create: `Clipsmith/Services/TaskPaperParser.swift` (pbxproj: AF0103/AA0103, group GG0004, phase BB0002)
- Test: `ClipsmithTests/TaskPaperParserTests.swift` (pbxproj: AF0104/AA0104, group GG0010, phase BB0005)
- Modify: `Clipsmith.xcodeproj/project.pbxproj` (registration recipe above)

**Interfaces:**
- Consumes: nothing (foundation task).
- Produces (all `Sendable`, defined in `TaskPaperParser.swift`):
  - `struct TodoTag: Sendable, Equatable, Hashable { let name: String; let value: String? }`
  - `struct TodoItem: Sendable, Equatable, Identifiable` — `init(rawLine: String, id: UUID = UUID())`, stored `id: UUID`, `rawLine: String`, `indentLevel: Int`, `title: String`, `tags: [TodoTag]`; computed `isDone: Bool`, `doneDate: String?`, `isToday: Bool`, `dueDateString: String?`, `dueDate: Date?`, `func tag(named: String) -> TodoTag?`
  - `enum TodoNode: Sendable, Equatable { case task(TodoItem); case note(String) }`
  - `struct TodoProject: Sendable, Equatable, Identifiable` — `init(name: String, rawLine: String?, nodes: [TodoNode], id: UUID = UUID())`, `var tasks: [TodoItem]`, `var isInbox: Bool` (true when `rawLine == nil`)
  - `struct TaskPaperDocument: Sendable, Equatable { var projects: [TodoProject]; var endsWithNewline: Bool }` + `static let empty` + `var allTasks: [TodoItem]`
  - `enum TaskPaperParser { static func parse(_ text: String) -> TaskPaperDocument; static func tags(in line: String) -> [TodoTag]; static func strippingTags(_ line: String) -> String }`
  - `enum TaskPaperSerializer { static func serialize(_ document: TaskPaperDocument) -> String }`
  - `enum TodoDates { static func dateString(from date: Date = .now) -> String }` → `"YYYY-MM-DD"` in the current calendar
- Note: two `parse` calls of the same text are NOT `==` (fresh UUIDs). Round-trip tests compare serialized strings, never documents.

- [ ] **Step 1: Write the failing tests**

Create `ClipsmithTests/TaskPaperParserTests.swift`:

```swift
import XCTest
@testable import Clipsmith

@MainActor
final class TaskPaperParserTests: XCTestCase {

    // MARK: - Line classification

    func testParsesProjectLine() {
        let doc = TaskPaperParser.parse("Home:\n- buy milk\n")
        // projects[0] is always the synthetic Inbox
        XCTAssertEqual(doc.projects.count, 2)
        XCTAssertTrue(doc.projects[0].isInbox)
        XCTAssertEqual(doc.projects[1].name, "Home")
        XCTAssertEqual(doc.projects[1].tasks.count, 1)
        XCTAssertEqual(doc.projects[1].tasks[0].title, "buy milk")
    }

    func testProjectLineWithTrailingTagIsAProject() {
        let doc = TaskPaperParser.parse("Work: @flagged\n- ship it\n")
        XCTAssertEqual(doc.projects[1].name, "Work")
    }

    func testInboxHoldsLeadingTasksAndNotes() {
        let doc = TaskPaperParser.parse("- loose task\nsome note\nHome:\n- chore\n")
        XCTAssertTrue(doc.projects[0].isInbox)
        XCTAssertEqual(doc.projects[0].name, "Inbox")
        XCTAssertEqual(doc.projects[0].tasks.count, 1)
        XCTAssertEqual(doc.projects[0].nodes.count, 2) // task + note
    }

    func testNoteLinesPreservedVerbatim() {
        let doc = TaskPaperParser.parse("Home:\n  a note with   spaces\n\n- task\n")
        guard case .note(let n1) = doc.projects[1].nodes[0],
              case .note(let n2) = doc.projects[1].nodes[1] else {
            return XCTFail("expected notes")
        }
        XCTAssertEqual(n1, "  a note with   spaces")
        XCTAssertEqual(n2, "")
    }

    func testTaskLineWithColonIsATaskNotAProject() {
        let doc = TaskPaperParser.parse("- remember: call mom\n")
        XCTAssertEqual(doc.projects[0].tasks.count, 1)
    }

    // MARK: - Tags

    func testTagParsingWithAndWithoutValues() {
        let tags = TaskPaperParser.tags(in: "- fix bug @today @due(2026-09-05) @p-1")
        XCTAssertEqual(tags, [
            TodoTag(name: "today", value: nil),
            TodoTag(name: "due", value: "2026-09-05"),
            TodoTag(name: "p-1", value: nil),
        ])
    }

    func testEmailIsNotATag() {
        XCTAssertTrue(TaskPaperParser.tags(in: "- mail adam@lablabs.io today").isEmpty)
    }

    func testTitleExcludesTagsAndDashPrefix() {
        let item = TodoItem(rawLine: "\t- fix @p-1 the pricing page @due(2026-09-05)")
        XCTAssertEqual(item.title, "fix the pricing page")
    }

    // MARK: - Derived properties

    func testDerivedProperties() {
        let item = TodoItem(rawLine: "- x @done(2026-08-30) @today @due(2026-09-05)")
        XCTAssertTrue(item.isDone)
        XCTAssertEqual(item.doneDate, "2026-08-30")
        XCTAssertTrue(item.isToday)
        XCTAssertEqual(item.dueDateString, "2026-09-05")
        XCTAssertNotNil(item.dueDate)
    }

    func testIndentLevelCountsLeadingTabs() {
        XCTAssertEqual(TodoItem(rawLine: "- top").indentLevel, 0)
        XCTAssertEqual(TodoItem(rawLine: "\t\t- nested").indentLevel, 2)
    }

    // MARK: - Round trip (byte fidelity)

    func testRoundTripByteFidelity() {
        let input = """
        - inbox task @today
        random preamble note

        Home: @flagged
        \t- buy milk @done(2026-08-30)
        \t\t- nested item
        \tnote under home
        - malformed? not really, still a task

        Work:
        - ship @due(2026-09-05)
        trailing junk line @weird(
        """
        + "\n"
        XCTAssertEqual(TaskPaperSerializer.serialize(TaskPaperParser.parse(input)), input)
    }

    func testRoundTripWithoutTrailingNewline() {
        let input = "Home:\n- task"
        XCTAssertEqual(TaskPaperSerializer.serialize(TaskPaperParser.parse(input)), input)
    }

    func testRoundTripEmptyString() {
        XCTAssertEqual(TaskPaperSerializer.serialize(TaskPaperParser.parse("")), "")
    }

    func testRoundTripOnlyNewline() {
        XCTAssertEqual(TaskPaperSerializer.serialize(TaskPaperParser.parse("\n")), "\n")
    }

    // MARK: - TodoDates

    func testDateStringFormat() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        XCTAssertEqual(TodoDates.dateString(from: date), "2026-08-31")
    }
}
```

- [ ] **Step 2: Register both files in project.pbxproj** (recipe: AF0103/AA0103 → GG0004+BB0002 for `TaskPaperParser.swift`; AF0104/AA0104 → GG0010+BB0005 for the test file). Create an empty `Clipsmith/Services/TaskPaperParser.swift` containing only `import Foundation` so the target compiles enough to show test failures.

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TaskPaperParserTests`
Expected: compile FAILURE ("cannot find 'TaskPaperParser' in scope") — that is the failing state for TDD here.

- [ ] **Step 4: Implement `Clipsmith/Services/TaskPaperParser.swift`**

```swift
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
    /// so email addresses are not tags.
    nonisolated(unsafe) static let tagRegex =
        /(?<=\s|^)@([A-Za-z0-9_-]+)(?:\(([^()]*)\))?/

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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TaskPaperParserTests`
Expected: PASS (all tests). If `nonisolated(unsafe)` on the regex draws a warning under strict concurrency, replace the static with a computed `static var tagRegex` returning the literal — behavior identical.

- [ ] **Step 6: Commit**

```bash
git add Clipsmith/Services/TaskPaperParser.swift ClipsmithTests/TaskPaperParserTests.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): TaskPaper model types, parser, serializer with byte-exact round trip"
```

---

### Task 2: TodoStore — document ownership, CRUD, debounced atomic saves, file watcher

**Files:**
- Create: `Clipsmith/Services/TodoStore.swift` (pbxproj: AF0105/AA0105, group GG0004, phase BB0002)
- Modify: `Clipsmith/Settings/AppSettingsKeys.swift` (add three keys)
- Test: `ClipsmithTests/TodoStoreTests.swift` (pbxproj: AF0106/AA0106, group GG0010, phase BB0005)
- Modify: `Clipsmith.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TaskPaperDocument`, `TaskPaperParser.parse(_:)`, `TaskPaperSerializer.serialize(_:)`, `TodoItem`, `TodoTag`, `TodoDates.dateString(from:)` from Task 1.
- Produces: `@MainActor @Observable final class TodoStore` with:
  - `init(fileURL: URL = TodoStore.resolveFileURL(), saveDelay: Duration = .milliseconds(500))` — does NOT touch disk
  - `private(set) var document: TaskPaperDocument`, `private(set) var hasPendingChanges: Bool`, `var lastError: String?`, `private(set) var fileURL: URL`
  - `func load()`, `func loadIfNeeded()`, `func saveNow()`, `func updateFileURL(_ url: URL)`, `func handleFileChanged()`
  - `func addTask(text: String, projectName: String?, tags: [TodoTag])` (nil / unknown "Inbox" → synthetic Inbox; unmatched project name → creates project; project match is case-insensitive)
  - `func toggleDone(id: UUID)`, `func editTask(id: UUID, text: String)`, `func deleteTask(id: UUID)`, `func moveTask(id: UUID, toProject name: String)`
  - `func addProject(name: String)`, `func renameProject(id: UUID, to name: String)`, `func deleteProject(id: UUID)`
  - `static func defaultFileURL() -> URL`, `static func resolveFileURL() -> URL`
- Keys added to `AppSettingsKeys`: `todoTrackingEnabled`, `todoFilePath`, `todoShowCompleted`.

- [ ] **Step 1: Add settings keys**

Append inside the `AppSettingsKeys` enum in `Clipsmith/Settings/AppSettingsKeys.swift`:

```swift
    // Phase 13 additions (Todo Tracking)
    static let todoTrackingEnabled = "todoTrackingEnabled"
    static let todoFilePath = "todoFilePath"
    static let todoShowCompleted = "todoShowCompleted"
```

- [ ] **Step 2: Write the failing tests**

Create `ClipsmithTests/TodoStoreTests.swift`:

```swift
import XCTest
@testable import Clipsmith

@MainActor
final class TodoStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "TodoStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore(initialContent: String? = nil,
                           saveDelay: Duration = .milliseconds(10)) -> TodoStore {
        let url = tempDir.appending(path: "todos.taskpaper")
        if let initialContent {
            try? Data(initialContent.utf8).write(to: url)
        }
        let store = TodoStore(fileURL: url, saveDelay: saveDelay)
        store.load()
        return store
    }

    private func fileContent(of store: TodoStore) -> String {
        (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? "<missing>"
    }

    // MARK: - Load

    func testMissingFileLoadsEmptyDocumentWithoutCreatingFile() {
        let store = makeStore()
        XCTAssertEqual(store.document.allTasks.count, 0)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testLoadParsesExistingFile() {
        let store = makeStore(initialContent: "Home:\n- buy milk @today\n")
        XCTAssertEqual(store.document.projects[1].tasks[0].title, "buy milk")
    }

    // MARK: - CRUD + save

    func testAddTaskToInboxAndSaveCreatesFile() {
        let store = makeStore()
        store.addTask(text: "loose task", projectName: nil, tags: [])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- loose task\n")
    }

    func testAddTaskWithTagsAndNewProject() {
        let store = makeStore(initialContent: "")
        store.addTask(text: "Fix pricing page",
                      projectName: "lara",
                      tags: [TodoTag(name: "due", value: "2026-09-05"),
                             TodoTag(name: "today", value: nil)])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store),
                       "lara:\n- Fix pricing page @due(2026-09-05) @today\n")
    }

    func testAddTaskMatchesProjectCaseInsensitively() {
        let store = makeStore(initialContent: "LARA:\n")
        store.addTask(text: "x", projectName: "lara", tags: [])
        XCTAssertEqual(store.document.projects.count, 2) // Inbox + LARA, no new project
        XCTAssertEqual(store.document.projects[1].tasks.count, 1)
    }

    func testToggleDoneAddsAndRemovesDoneTag() {
        let store = makeStore(initialContent: "- task one\n")
        let id = store.document.allTasks[0].id
        store.toggleDone(id: id)
        let today = TodoDates.dateString()
        XCTAssertEqual(store.document.allTasks[0].rawLine, "- task one @done(\(today))")
        store.toggleDone(id: id)
        XCTAssertEqual(store.document.allTasks[0].rawLine, "- task one")
    }

    func testEditTaskPreservesIndent() {
        let store = makeStore(initialContent: "Home:\n\t- old text @today\n")
        let id = store.document.allTasks[0].id
        store.editTask(id: id, text: "new text @today")
        XCTAssertEqual(store.document.allTasks[0].rawLine, "\t- new text @today")
    }

    func testDeleteTask() {
        let store = makeStore(initialContent: "- a\n- b\n")
        store.deleteTask(id: store.document.allTasks[0].id)
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- b\n")
    }

    func testMoveTask() {
        let store = makeStore(initialContent: "- a\nWork:\n")
        store.moveTask(id: store.document.allTasks[0].id, toProject: "Work")
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "Work:\n- a\n")
    }

    func testAddRenameDeleteProject() {
        let store = makeStore(initialContent: "")
        store.addProject(name: "Alpha")
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "Alpha:\n")
        let id = store.document.projects[1].id
        store.renameProject(id: id, to: "Beta")
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "Beta:\n")
        store.deleteProject(id: id)
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "")
    }

    // MARK: - Debounce

    func testDebouncedSaveWritesAfterDelay() async throws {
        let store = makeStore(saveDelay: .milliseconds(20))
        store.addTask(text: "a", projectName: nil, tags: [])
        store.addTask(text: "b", projectName: nil, tags: [])
        XCTAssertTrue(store.hasPendingChanges)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(store.hasPendingChanges)
        XCTAssertEqual(fileContent(of: store), "- a\n- b\n")
    }

    // MARK: - External changes (last-write-wins)

    func testExternalChangeReloadsWhenClean() throws {
        let store = makeStore(initialContent: "- a\n")
        try Data("- edited outside\n".utf8).write(to: store.fileURL)
        store.handleFileChanged()
        XCTAssertEqual(store.document.allTasks[0].title, "edited outside")
    }

    func testExternalChangeIgnoredWhenDirty() throws {
        let store = makeStore(initialContent: "- a\n", saveDelay: .seconds(60))
        store.addTask(text: "in-app", projectName: nil, tags: [])
        try Data("- edited outside\n".utf8).write(to: store.fileURL)
        store.handleFileChanged()
        // In-app state wins; next save overwrites the external edit.
        XCTAssertEqual(store.document.allTasks.map(\.title), ["a", "in-app"])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- a\n- in-app\n")
    }

    func testFileDeletedExternallyRecreatedOnNextSave() throws {
        let store = makeStore(initialContent: "- a\n")
        try FileManager.default.removeItem(at: store.fileURL)
        store.handleFileChanged() // file gone: keep memory state
        XCTAssertEqual(store.document.allTasks.count, 1)
        store.addTask(text: "b", projectName: nil, tags: [])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- a\n- b\n")
    }

    // MARK: - Path switching

    func testUpdateFileURLFlushesThenLoadsNewFile() throws {
        let store = makeStore(initialContent: "- a\n", saveDelay: .seconds(60))
        store.addTask(text: "b", projectName: nil, tags: [])
        let oldURL = store.fileURL
        let newURL = tempDir.appending(path: "other.taskpaper")
        try Data("Other:\n- z\n".utf8).write(to: newURL)
        store.updateFileURL(newURL)
        XCTAssertEqual((try String(contentsOf: oldURL, encoding: .utf8)), "- a\n- b\n")
        XCTAssertEqual(store.document.projects[1].name, "Other")
    }
}
```

- [ ] **Step 3: Register files in pbxproj** (AF0105/AA0105 → GG0004+BB0002; AF0106/AA0106 → GG0010+BB0005), create empty `TodoStore.swift` with `import Foundation`, run the suite:

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TodoStoreTests`
Expected: compile FAILURE ("cannot find 'TodoStore' in scope").

- [ ] **Step 4: Implement `Clipsmith/Services/TodoStore.swift`**

```swift
import Foundation
import Observation

/// Owns the TaskPaper document: CRUD on tasks/projects, debounced atomic
/// persistence, and a DispatchSource watcher that reloads on external edits
/// (last-write-wins — in-app changes win on the next save).
///
/// No SwiftData: the plain-text file is the single source of truth.
@MainActor
@Observable
final class TodoStore {

    private(set) var document: TaskPaperDocument = .empty
    private(set) var hasPendingChanges = false
    private(set) var fileURL: URL
    /// Last I/O error, surfaced as a non-blocking notice in the todo window.
    var lastError: String?

    private let saveDelay: Duration
    private var hasLoaded = false
    private var saveTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?

    init(fileURL: URL = TodoStore.resolveFileURL(),
         saveDelay: Duration = .milliseconds(500)) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
    }

    // MARK: - Path resolution

    static func defaultFileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Clipsmith/todos.taskpaper")
    }

    /// UserDefaults override (AppSettingsKeys.todoFilePath) or the default.
    /// The app is not sandboxed, so a plain path is sufficient — no
    /// security-scoped bookmarks needed.
    static func resolveFileURL() -> URL {
        let path = UserDefaults.standard.string(forKey: AppSettingsKeys.todoFilePath) ?? ""
        guard !path.isEmpty else { return defaultFileURL() }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: - Load / save

    func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                document = TaskPaperParser.parse(text)
                lastError = nil
            } catch {
                // Keep in-memory state; surface the error non-blockingly.
                lastError = "Could not read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            }
        } else {
            document = .empty // missing file: created on first save
            lastError = nil
        }
        hasLoaded = true
        startWatcher()
    }

    func loadIfNeeded() {
        if !hasLoaded { load() }
    }

    /// Flushes any pending debounced save immediately. Called by tests and
    /// applicationWillTerminate.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingChanges else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            var doc = document
            if !doc.endsWithNewline, !TaskPaperSerializer.serialize(doc).isEmpty {
                doc.endsWithNewline = true // new files end with a newline
                document = doc
            }
            try Data(TaskPaperSerializer.serialize(document).utf8)
                .write(to: fileURL, options: .atomic)
            hasPendingChanges = false
            lastError = nil
            // Atomic write = rename: the watched fd points at the old inode.
            startWatcher()
        } catch {
            lastError = "Could not save \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func updateFileURL(_ url: URL) {
        saveNow()
        watcher?.cancel()
        watcher = nil
        fileURL = url
        load()
    }

    private func markDirty() {
        hasPendingChanges = true
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    // MARK: - External change watcher

    private func startWatcher() {
        watcher?.cancel()
        watcher = nil
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return } // file missing — re-armed after first save
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.handleFileChanged() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Reload from disk unless there are unsaved in-app changes
    /// (last-write-wins: dirty in-app state overwrites on next save).
    /// A deleted file keeps memory state and is recreated on next save.
    func handleFileChanged() {
        guard !hasPendingChanges else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            markDirty() // schedule recreation with current memory state
            return
        }
        load()
    }

    // MARK: - Task CRUD

    func addTask(text: String, projectName: String?, tags: [TodoTag] = []) {
        var line = text.hasPrefix("- ") ? text : "- " + text
        for tag in tags {
            line += tag.value.map { " @\(tag.name)(\($0))" } ?? " @\(tag.name)"
        }
        let item = TodoItem(rawLine: line)
        let target = projectName ?? "Inbox"
        if let idx = document.projects.firstIndex(where: {
            $0.name.caseInsensitiveCompare(target) == .orderedSame
        }) {
            document.projects[idx].nodes.append(.task(item))
        } else if let projectName {
            document.projects.append(TodoProject(
                name: projectName, rawLine: "\(projectName):", nodes: [.task(item)]))
        } else {
            document.projects[0].nodes.append(.task(item))
        }
        markDirty()
    }

    func toggleDone(id: UUID) {
        mutateItem(id: id) { item in
            if item.isDone {
                let cleaned = item.rawLine
                    .replacing(/\s*@done(?:\([^()]*\))?/, with: "")
                return TodoItem(rawLine: cleaned, id: item.id)
            } else {
                return TodoItem(
                    rawLine: item.rawLine + " @done(\(TodoDates.dateString()))",
                    id: item.id)
            }
        }
    }

    func editTask(id: UUID, text: String) {
        mutateItem(id: id) { item in
            let tabs = String(repeating: "\t", count: item.indentLevel)
            let body = text.hasPrefix("- ") ? text : "- " + text
            return TodoItem(rawLine: tabs + body, id: item.id)
        }
    }

    func deleteTask(id: UUID) {
        for p in document.projects.indices {
            if let n = document.projects[p].nodes.firstIndex(where: { isTask($0, id: id) }) {
                document.projects[p].nodes.remove(at: n)
                markDirty()
                return
            }
        }
    }

    func moveTask(id: UUID, toProject name: String) {
        guard let item = document.allTasks.first(where: { $0.id == id }) else { return }
        deleteTask(id: id)
        // Re-home at indent 0 in the target project, keeping text and tags.
        let trimmed = item.rawLine.trimmingCharacters(in: .whitespaces)
        var target = document.projects.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        })
        if target == nil {
            document.projects.append(TodoProject(name: name, rawLine: "\(name):", nodes: []))
            target = document.projects.count - 1
        }
        document.projects[target!].nodes.append(.task(TodoItem(rawLine: trimmed, id: item.id)))
        markDirty()
    }

    // MARK: - Project CRUD

    func addProject(name: String) {
        guard !document.projects.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        document.projects.append(TodoProject(name: name, rawLine: "\(name):", nodes: []))
        markDirty()
    }

    func renameProject(id: UUID, to name: String) {
        guard let idx = document.projects.firstIndex(where: { $0.id == id }),
              !document.projects[idx].isInbox else { return }
        document.projects[idx].name = name
        document.projects[idx].rawLine = "\(name):"
        markDirty()
    }

    func deleteProject(id: UUID) {
        guard let idx = document.projects.firstIndex(where: { $0.id == id }),
              !document.projects[idx].isInbox else { return }
        document.projects.remove(at: idx)
        markDirty()
    }

    // MARK: - Private helpers

    private func isTask(_ node: TodoNode, id: UUID) -> Bool {
        if case .task(let item) = node { item.id == id } else { false }
    }

    private func mutateItem(id: UUID, _ transform: (TodoItem) -> TodoItem) {
        for p in document.projects.indices {
            for n in document.projects[p].nodes.indices {
                if case .task(let item) = document.projects[p].nodes[n], item.id == id {
                    document.projects[p].nodes[n] = .task(transform(item))
                    markDirty()
                    return
                }
            }
        }
    }
}
```

Implementation note: `testAddRenameDeleteProject` expects an empty file (`""`) to load as a document with `endsWithNewline == false`, then `Alpha:` saved as `"Alpha:\n"` — the `saveNow()` newline normalization handles that. `testRoundTripEmptyString` in Task 1 stays byte-exact because normalization only happens on save of a *dirty* document, never in parse/serialize.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TodoStoreTests`
Expected: PASS. Also re-run `TaskPaperParserTests` (round-trip must still pass).

- [ ] **Step 6: Commit**

```bash
git add Clipsmith/Services/TodoStore.swift Clipsmith/Settings/AppSettingsKeys.swift ClipsmithTests/TodoStoreTests.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): TodoStore with debounced atomic saves, file watcher, CRUD"
```

---

### Task 3: TodoQuickAddParser

**Files:**
- Create: `Clipsmith/Services/TodoQuickAddParser.swift` (pbxproj: AF0107/AA0107, group GG0004, phase BB0002)
- Test: `ClipsmithTests/TodoQuickAddParserTests.swift` (pbxproj: AF0108/AA0108, group GG0010, phase BB0005)
- Modify: `Clipsmith.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TodoTag`, `TaskPaperParser.tagRegex` (Task 1).
- Produces:
  - `struct TodoQuickAddResult: Sendable, Equatable { let title: String; let projectName: String?; let tags: [TodoTag] }`
  - `enum TodoQuickAddParser { static func parse(_ input: String) -> TodoQuickAddResult }`
  - Semantics: first `#name` token → `projectName` (nil when absent → Inbox); `@tag` / `@tag(value)` tokens → tags; everything else joins into `title`. Case-insensitive project matching / creation happens in `TodoStore.addTask`, not here.

- [ ] **Step 1: Write the failing tests**

Create `ClipsmithTests/TodoQuickAddParserTests.swift`:

```swift
import XCTest
@testable import Clipsmith

@MainActor
final class TodoQuickAddParserTests: XCTestCase {

    func testFullSyntax() {
        let r = TodoQuickAddParser.parse("Fix pricing page #lara @due(2026-09-05) @today")
        XCTAssertEqual(r.title, "Fix pricing page")
        XCTAssertEqual(r.projectName, "lara")
        XCTAssertEqual(r.tags, [
            TodoTag(name: "due", value: "2026-09-05"),
            TodoTag(name: "today", value: nil),
        ])
    }

    func testPlainTextGoesToInbox() {
        let r = TodoQuickAddParser.parse("just a task")
        XCTAssertEqual(r.title, "just a task")
        XCTAssertNil(r.projectName)
        XCTAssertTrue(r.tags.isEmpty)
    }

    func testProjectTokenAnywhereInInput() {
        let r = TodoQuickAddParser.parse("#work review the PR")
        XCTAssertEqual(r.projectName, "work")
        XCTAssertEqual(r.title, "review the PR")
    }

    func testOnlyFirstHashTokenIsProject() {
        let r = TodoQuickAddParser.parse("deploy #infra then #staging")
        XCTAssertEqual(r.projectName, "infra")
        XCTAssertEqual(r.title, "deploy then #staging")
    }

    func testBareHashAndBareAtStayInTitle() {
        let r = TodoQuickAddParser.parse("ship # and @ symbols")
        XCTAssertEqual(r.title, "ship # and @ symbols")
        XCTAssertNil(r.projectName)
        XCTAssertTrue(r.tags.isEmpty)
    }

    func testWhitespaceCollapsed() {
        let r = TodoQuickAddParser.parse("  spaced   out   #p  ")
        XCTAssertEqual(r.title, "spaced out")
        XCTAssertEqual(r.projectName, "p")
    }

    func testEmptyInput() {
        let r = TodoQuickAddParser.parse("   ")
        XCTAssertEqual(r.title, "")
        XCTAssertNil(r.projectName)
    }
}
```

- [ ] **Step 2: Register files in pbxproj**, create `TodoQuickAddParser.swift` with only `import Foundation`, run:

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TodoQuickAddParserTests`
Expected: compile FAILURE ("cannot find 'TodoQuickAddParser' in scope").

- [ ] **Step 3: Implement `Clipsmith/Services/TodoQuickAddParser.swift`**

```swift
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
```

Note: `wholeMatch` with a lookbehind `(?<=\s|^)` anchors at the token start, which satisfies the lookbehind (`^`), so `@due(2026-09-05)` matches. If in practice it does not (lookbehind semantics vs. substring start), match against `" " + token` with `firstMatch` and require the match to span the full token — the test suite pins the behavior either way.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TodoQuickAddParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Services/TodoQuickAddParser.swift ClipsmithTests/TodoQuickAddParserTests.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): quick-add inline syntax parser (#project, @tags, title)"
```

---

### Task 4: TodoWindowViewModel

**Files:**
- Create: `Clipsmith/Views/Todos/TodoWindowViewModel.swift` (pbxproj: AF0109/AA0109, NEW group GG0017 "Todos" under GG0005, phase BB0002)
- Test: `ClipsmithTests/TodoWindowViewModelTests.swift` (pbxproj: AF0110/AA0110, group GG0010, phase BB0005)
- Modify: `Clipsmith.xcodeproj/project.pbxproj`

**pbxproj group creation:** add to the `PBXGroup` section (after `GG0016`):

```
		GG0017 /* Todos */ = {
			isa = PBXGroup;
			children = (
				AF0109 /* TodoWindowViewModel.swift */,
			);
			path = Todos;
			sourceTree = "<group>";
		};
```

and add `GG0017 /* Todos */,` to the `children` list of `GG0005 /* Views */` (after `GG0016 /* ClaudeToolkit */,`).

**Interfaces:**
- Consumes: `TaskPaperDocument`, `TodoItem`, `TodoProject`, `TodoDates.dateString`, `FuzzyMatcher.score(_:query:)`, `AppSettingsKeys.todoShowCompleted`.
- Produces: `@MainActor @Observable final class TodoWindowViewModel`:
  - `enum Tab: Hashable { case today; case project(String) }` with `var label: String` ("Today" / project name)
  - `var selectedTab: Tab`, `var searchText: String`, `var showCompleted: Bool` (persisted to UserDefaults on set), `var selectedItemID: UUID?`
  - `func tabs(for document: TaskPaperDocument) -> [Tab]` — Today first, then projects in file order; Inbox only when it has tasks
  - `func visibleItems(in document: TaskPaperDocument, today: String = TodoDates.dateString()) -> [TodoItem]` — tab filter, then show-completed filter, then search filter
  - `func currentProjectName() -> String?` — nil on Today/Inbox tabs (add-task target project)
  - `func selectNext(in items: [TodoItem])`, `func selectPrevious(in items: [TodoItem])`
- The VM never touches the store or disk — pure state over a passed-in document, exactly for testability.

- [ ] **Step 1: Write the failing tests**

Create `ClipsmithTests/TodoWindowViewModelTests.swift`:

```swift
import XCTest
@testable import Clipsmith

@MainActor
final class TodoWindowViewModelTests: XCTestCase {

    private var vm: TodoWindowViewModel!

    override func setUp() {
        super.setUp()
        vm = TodoWindowViewModel()
        vm.showCompleted = false
    }

    private let sample = TaskPaperParser.parse("""
    - inbox task @today
    Home:
    - overdue chore @due(2020-01-01)
    - future chore @due(2099-12-31)
    - done chore @done(2026-08-30)
    Work:
    - ship feature @today @done(2026-08-30)
    - review PR @urgent
    """ + "\n")

    private let noInbox = TaskPaperParser.parse("Home:\n- chore\n")

    // MARK: - Tabs

    func testTabsTodayFirstThenProjectsInFileOrder() {
        XCTAssertEqual(vm.tabs(for: sample), [
            .today, .project("Inbox"), .project("Home"), .project("Work"),
        ])
    }

    func testEmptyInboxTabHidden() {
        XCTAssertEqual(vm.tabs(for: noInbox), [.today, .project("Home")])
    }

    // MARK: - Today view

    func testTodayViewIncludesTodayTagAndOverdueDue() {
        vm.selectedTab = .today
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        // @today item + overdue @due item; done @today item hidden; future due hidden
        XCTAssertEqual(titles, ["inbox task", "overdue chore"])
    }

    func testTodayViewIncludesItemsDueExactlyToday() {
        vm.selectedTab = .today
        let doc = TaskPaperParser.parse("- due today @due(2026-08-31)\n")
        XCTAssertEqual(vm.visibleItems(in: doc, today: "2026-08-31").count, 1)
    }

    func testShowCompletedRevealsDoneItemsInToday() {
        vm.selectedTab = .today
        vm.showCompleted = true
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        XCTAssertTrue(titles.contains("ship feature"))
    }

    // MARK: - Project tabs

    func testProjectTabShowsItsTasksHidingDone() {
        vm.selectedTab = .project("Home")
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        XCTAssertEqual(titles, ["overdue chore", "future chore"])
    }

    func testCurrentProjectName() {
        vm.selectedTab = .today
        XCTAssertNil(vm.currentProjectName())
        vm.selectedTab = .project("Inbox")
        XCTAssertNil(vm.currentProjectName())
        vm.selectedTab = .project("Home")
        XCTAssertEqual(vm.currentProjectName(), "Home")
    }

    // MARK: - Search

    func testSearchFuzzyMatchesTitle() {
        vm.selectedTab = .project("Work")
        vm.searchText = "revpr"
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        XCTAssertEqual(titles, ["review PR"])
    }

    func testSearchAtTermMatchesTags() {
        vm.selectedTab = .project("Work")
        vm.searchText = "@urgent"
        XCTAssertEqual(vm.visibleItems(in: sample, today: "2026-08-31").map(\.title),
                       ["review PR"])
        vm.searchText = "@nosuchtag"
        XCTAssertTrue(vm.visibleItems(in: sample, today: "2026-08-31").isEmpty)
    }

    // MARK: - Selection navigation

    func testSelectNextAndPrevious() {
        vm.selectedTab = .project("Home")
        let items = vm.visibleItems(in: sample, today: "2026-08-31")
        vm.selectNext(in: items)
        XCTAssertEqual(vm.selectedItemID, items[0].id)
        vm.selectNext(in: items)
        XCTAssertEqual(vm.selectedItemID, items[1].id)
        vm.selectNext(in: items) // clamps at end
        XCTAssertEqual(vm.selectedItemID, items[1].id)
        vm.selectPrevious(in: items)
        XCTAssertEqual(vm.selectedItemID, items[0].id)
    }
}
```

- [ ] **Step 2: Register files + GG0017 group in pbxproj**, create `TodoWindowViewModel.swift` with only `import Foundation` (directory `Clipsmith/Views/Todos/` is new), run:

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TodoWindowViewModelTests`
Expected: compile FAILURE ("cannot find 'TodoWindowViewModel' in scope").

- [ ] **Step 3: Implement `Clipsmith/Views/Todos/TodoWindowViewModel.swift`**

```swift
import Foundation
import Observation

/// Pure UI state for the todo window: tab selection, search, show-completed,
/// selection. Filtering operates on a passed-in document — no store, no I/O —
/// so every behavior is unit-testable.
@MainActor
@Observable
final class TodoWindowViewModel {

    enum Tab: Hashable {
        case today
        case project(String)

        var label: String {
            switch self {
            case .today: "Today"
            case .project(let name): name
            }
        }
    }

    var selectedTab: Tab = .today
    var searchText = ""
    var selectedItemID: UUID?

    var showCompleted: Bool = UserDefaults.standard.bool(forKey: AppSettingsKeys.todoShowCompleted) {
        didSet {
            UserDefaults.standard.set(showCompleted, forKey: AppSettingsKeys.todoShowCompleted)
        }
    }

    // MARK: - Tabs

    /// Today first, then projects in file order. Inbox only when it has tasks.
    func tabs(for document: TaskPaperDocument) -> [Tab] {
        var tabs: [Tab] = [.today]
        for project in document.projects {
            if project.isInbox && project.tasks.isEmpty { continue }
            tabs.append(.project(project.name))
        }
        return tabs
    }

    /// Target project for a new task: nil (→ Inbox) on Today and Inbox tabs.
    func currentProjectName() -> String? {
        if case .project(let name) = selectedTab, name != "Inbox" { return name }
        return nil
    }

    // MARK: - Filtering

    /// `today` is "YYYY-MM-DD"; due-date comparison is lexicographic, which
    /// is correct for that format.
    func visibleItems(in document: TaskPaperDocument,
                      today: String = TodoDates.dateString()) -> [TodoItem] {
        let base: [TodoItem]
        switch selectedTab {
        case .today:
            base = document.allTasks.filter { item in
                item.isToday || (item.dueDateString.map { $0 <= today } ?? false)
            }
        case .project(let name):
            base = document.projects.first { $0.name == name }?.tasks ?? []
        }
        return base
            .filter { showCompleted || !$0.isDone }
            .filter { matchesSearch($0) }
    }

    private func matchesSearch(_ item: TodoItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        for term in query.split(whereSeparator: \.isWhitespace) {
            if term.hasPrefix("@"), term.count > 1 {
                let name = term.dropFirst().lowercased()
                guard item.tags.contains(where: { $0.name.lowercased().hasPrefix(name) })
                else { return false }
            } else {
                guard FuzzyMatcher.score(item.title, query: String(term)) != nil
                else { return false }
            }
        }
        return true
    }

    // MARK: - Selection navigation

    func selectNext(in items: [TodoItem]) {
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = items[0].id
            return
        }
        selectedItemID = items[min(current + 1, items.count - 1)].id
    }

    func selectPrevious(in items: [TodoItem]) {
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = items[0].id
            return
        }
        selectedItemID = items[max(current - 1, 0)].id
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TodoWindowViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Views/Todos/TodoWindowViewModel.swift ClipsmithTests/TodoWindowViewModelTests.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): window view model — tabs, Today filtering, search, selection"
```

---

### Task 5: Feature flag toggle + Todo settings tab

**Files:**
- Create: `Clipsmith/Views/Settings/TodoSettingsSection.swift` (pbxproj: AF0114/AA0114, group GG0009, phase BB0002)
- Modify: `Clipsmith/Views/Settings/GeneralSettingsTab.swift` (Features section toggle)
- Modify: `Clipsmith/Views/SettingsView.swift` (`SettingsTab` case + tab entry)
- Modify: `Clipsmith/Views/MenuBarView.swift` (add `.clipsmithTodoFilePathChanged` notification name only)
- Modify: `Clipsmith.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AppSettingsKeys.todoTrackingEnabled` / `.todoFilePath` (Task 2), `TodoStore.defaultFileURL()` / `resolveFileURL()` (Task 2).
- Produces: `struct TodoSettingsSection: View`; `Notification.Name.clipsmithTodoFilePathChanged` (observed by AppDelegate in Task 8); `SettingsTab.todos` (= 7).

- [ ] **Step 1: Add the notification name**

In `Clipsmith/Views/MenuBarView.swift`, append inside the existing `extension Notification.Name`:

```swift
    /// Posted by TodoSettingsSection when the todo file path changes;
    /// AppDelegate observes it and re-points TodoStore at the new file.
    static let clipsmithTodoFilePathChanged = Notification.Name("clipsmithTodoFilePathChanged")
```

- [ ] **Step 2: Add the Features toggle**

In `Clipsmith/Views/Settings/GeneralSettingsTab.swift`:

Add with the other feature-flag `@AppStorage` properties:

```swift
    // Phase 13: Todo Tracking feature flag
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false
```

Add inside `Section("Features")`, after the App Launcher toggle:

```swift
                Toggle("Todo Tracking", isOn: $todoTrackingEnabled)
                    .help("Keyboard-first todos backed by a plain-text TaskPaper file. Configure the file location in the Todos tab.")
```

- [ ] **Step 3: Create `Clipsmith/Views/Settings/TodoSettingsSection.swift`** (and register AF0114/AA0114 in pbxproj, group GG0009, phase BB0002)

```swift
import AppKit
import SwiftUI

/// Settings > Todos: TaskPaper file location (choose, reveal, reset).
///
/// The path is a plain string in UserDefaults (empty = default location).
/// The app is not sandboxed, so no security-scoped bookmarks are needed.
struct TodoSettingsSection: View {
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false
    @AppStorage(AppSettingsKeys.todoFilePath) private var todoFilePath: String = ""

    private var effectiveURL: URL { TodoStore.resolveFileURL() }

    var body: some View {
        Form {
            Section("Todo File") {
                if !todoTrackingEnabled {
                    Text("Todo Tracking is disabled — enable it in General > Features.")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Location") {
                    Text(effectiveURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Choose…") { chooseFile() }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([effectiveURL])
                    }
                    Button("Reset to Default") {
                        todoFilePath = ""
                        postPathChanged()
                    }
                    .disabled(todoFilePath.isEmpty)
                }

                Text("Plain-text TaskPaper format — the file stays yours; edit it with any editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// NSSavePanel so the user can pick an existing file OR name a new one.
    private func chooseFile() {
        let panel = NSSavePanel()
        panel.title = "Choose Todo File"
        panel.nameFieldStringValue = "todos.taskpaper"
        panel.canCreateDirectories = true
        panel.directoryURL = effectiveURL.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            todoFilePath = url.path
            postPathChanged()
        }
    }

    private func postPathChanged() {
        NotificationCenter.default.post(name: .clipsmithTodoFilePathChanged, object: nil)
    }
}
```

- [ ] **Step 4: Add the Settings tab**

In `Clipsmith/Views/SettingsView.swift`:

Add to the `SettingsTab` enum after `license`:

```swift
    case todos = 7
```

Add to the `TabView` after the `DocsetSettingsSection()` entry:

```swift
            TodoSettingsSection()
                .tabItem {
                    Label("Todos", systemImage: "checklist")
                }
                .tag(SettingsTab.todos.rawValue)
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Clipsmith/Views/Settings/TodoSettingsSection.swift Clipsmith/Views/Settings/GeneralSettingsTab.swift Clipsmith/Views/SettingsView.swift Clipsmith/Views/MenuBarView.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): todoTrackingEnabled flag toggle and Todos settings tab"
```

---

### Task 6: Todo window — views, WindowGroup, menu bar entry

**Files:**
- Create: `Clipsmith/Views/Todos/TodoWindowView.swift` (pbxproj: AF0111/AA0111, group GG0017, phase BB0002)
- Create: `Clipsmith/Views/Todos/TodoListView.swift` (pbxproj: AF0112/AA0112, group GG0017, phase BB0002)
- Modify: `Clipsmith/App/ClipsmithApp.swift` (WindowGroup)
- Modify: `Clipsmith/App/AppDelegate.swift` (store property + creation — minimal slice needed for the window; hotkeys/observers come in Task 8)
- Modify: `Clipsmith/Views/MenuBarView.swift` ("Todos…" button + `.clipsmithOpenTodos` name + observer)
- Modify: `Clipsmith.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TodoStore` (Task 2, via SwiftUI environment), `TodoWindowViewModel` + `Tab` (Task 4), `TodoItem`/`TodoTag`/`TodoDates` (Task 1).
- Produces: `struct TodoWindowView: View`, `struct TodoListView: View`, `struct TodoRowView: View`; `WindowGroup(id: "todos")`; `Notification.Name.clipsmithOpenTodos`; `AppDelegate.todoStore: TodoStore!`.
- Keyboard map: ⌘1…⌘9 tabs, ⌘N new task (inline row), Space toggle done, ⌘⌫ delete, ⌘F focus search, ⇧⌘H show/hide completed, arrows navigate (native List selection), Escape closes window.

- [ ] **Step 1: AppDelegate — create the store**

In `Clipsmith/App/AppDelegate.swift`, after the Phase 12 properties:

```swift
    // Phase 13 — Todo Tracking
    var todoStore: TodoStore!
```

In `applicationDidFinishLaunching`, after the command palette block (step "10."):

```swift
        // 11. Initialize Todo Tracking store (Phase 13). Creation is
        // unconditional (project convention); disk load is deferred until the
        // feature is actually used (flag guarded at invocation sites).
        todoStore = TodoStore()
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.todoTrackingEnabled) {
            todoStore.loadIfNeeded()
        }
```

In `applicationWillTerminate`, after `docBezelController?.hide()`:

```swift
        todoStore?.saveNow()   // flush any pending debounced todo save
```

- [ ] **Step 2: Create `Clipsmith/Views/Todos/TodoWindowView.swift`** (register AF0111/AA0111, group GG0017, phase BB0002)

```swift
import SwiftUI

/// Root view for the todos WindowGroup: tab strip (Today first, then one tab
/// per project, Inbox when non-empty, "+" to add a project) above the task list.
///
/// ## Keyboard Shortcuts
///
/// | Shortcut  | Action                          |
/// |-----------|---------------------------------|
/// | ⌘1…⌘9     | Switch tabs                     |
/// | ⌘N        | New task (inline edit row)      |
/// | Space     | Toggle done on selection        |
/// | ⌘⌫        | Delete selected task            |
/// | ⌘F        | Focus search                    |
/// | ⇧⌘H       | Toggle show-completed           |
/// | ↑↓        | Navigate list                   |
/// | ⎋         | Close window                    |
struct TodoWindowView: View {
    @Environment(TodoStore.self) private var store
    @State private var viewModel = TodoWindowViewModel()
    @State private var isAddingProject = false
    @State private var newProjectName = ""

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            TodoListView(viewModel: viewModel)
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(6)
            }
        }
        .task {
            store.loadIfNeeded()
        }
        .onChange(of: tabs) { _, newTabs in
            // Keep selection valid when a project disappears (external edit).
            if !newTabs.contains(viewModel.selectedTab) {
                viewModel.selectedTab = .today
            }
        }
        // ⎋ closes the window (yields to focused text fields)
        .onExitCommand {
            NSApp.keyWindow?.close()
        }
        .background { tabShortcutButtons }
        .alert("New Project", isPresented: $isAddingProject) {
            TextField("Project name", text: $newProjectName)
            Button("Add") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    store.addProject(name: name)
                    viewModel.selectedTab = .project(name)
                }
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
        .onDisappear {
            // Restore accessory policy when the todo window closes,
            // but only if no other regular windows remain visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let visibleRegularWindows = NSApp.windows.filter {
                    $0.isVisible && !($0 is NSPanel) && $0.level == .normal
                }
                if visibleRegularWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private var tabs: [TodoWindowViewModel.Tab] {
        viewModel.tabs(for: store.document)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
            }
            Spacer(minLength: 4)
            Button {
                isAddingProject = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add project")
        }
        .padding(8)
    }

    private func tabButton(_ tab: TodoWindowViewModel.Tab) -> some View {
        Button {
            viewModel.selectedTab = tab
        } label: {
            Text(tab.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    viewModel.selectedTab == tab
                        ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                        : AnyShapeStyle(.clear),
                    in: Capsule())
        }
        .buttonStyle(.borderless)
    }

    /// Hidden ⌘1…⌘9 buttons — same pattern as SnippetWindowView.
    private var tabShortcutButtons: some View {
        Group {
            ForEach(Array(tabs.prefix(9).enumerated()), id: \.offset) { index, tab in
                Button("") { viewModel.selectedTab = tab }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
```

- [ ] **Step 3: Create `Clipsmith/Views/Todos/TodoListView.swift`** (register AF0112/AA0112, group GG0017, phase BB0002)

```swift
import SwiftUI

/// Task list for the selected tab: search bar, inline new-task row, task rows
/// with checkbox, title, tag chips, and due date (overdue in red).
struct TodoListView: View {
    @Environment(TodoStore.self) private var store
    @Bindable var viewModel: TodoWindowViewModel

    @State private var isAddingTask = false
    @State private var draftText = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var draftFocused: Bool

    private var today: String { TodoDates.dateString() }

    private var items: [TodoItem] {
        viewModel.visibleItems(in: store.document)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search — @tag terms match tags", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(8)

            Divider()

            List(selection: $viewModel.selectedItemID) {
                if isAddingTask {
                    TextField("New task — tags like @today welcome", text: $draftText)
                        .textFieldStyle(.plain)
                        .focused($draftFocused)
                        .onSubmit { commitDraft() }
                        .onExitCommand { cancelDraft() }
                }
                ForEach(items) { item in
                    TodoRowView(item: item, today: today) {
                        store.toggleDone(id: item.id)
                    }
                    .tag(item.id)
                }
            }
            .onKeyPress(.space) {
                guard let id = viewModel.selectedItemID else { return .ignored }
                store.toggleDone(id: id)
                return .handled
            }

            if items.isEmpty && !isAddingTask {
                // List renders empty; give keyboard users a hint.
                Text("No tasks — ⌘N to add one")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .background { hiddenShortcuts }
    }

    private var hiddenShortcuts: some View {
        Group {
            Button("") { startDraft() }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("") { viewModel.showCompleted.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func startDraft() {
        isAddingTask = true
        draftText = ""
        draftFocused = true
    }

    private func cancelDraft() {
        isAddingTask = false
        draftText = ""
    }

    /// New tasks go to the current project; on the Today tab they land in
    /// Inbox tagged @today so they show up where the user just created them.
    private func commitDraft() {
        let text = draftText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { cancelDraft(); return }
        var tags: [TodoTag] = []
        if viewModel.selectedTab == .today && !text.contains("@today") {
            tags.append(TodoTag(name: "today", value: nil))
        }
        store.addTask(text: text, projectName: viewModel.currentProjectName(), tags: tags)
        cancelDraft()
    }

    private func deleteSelected() {
        guard let id = viewModel.selectedItemID else { return }
        let current = items
        // Move selection to the neighbor before deleting.
        if let idx = current.firstIndex(where: { $0.id == id }) {
            let remaining = current.enumerated().filter { $0.offset != idx }.map(\.element)
            viewModel.selectedItemID = remaining.isEmpty
                ? nil
                : remaining[min(idx, remaining.count - 1)].id
        }
        store.deleteTask(id: id)
    }
}

/// One task row: checkbox, title, tag chips, due date (red when overdue).
struct TodoRowView: View {
    let item: TodoItem
    let today: String
    let onToggle: () -> Void

    private var isOverdue: Bool {
        !item.isDone && (item.dueDateString.map { $0 <= today } ?? false)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.borderless)

            Text(item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .lineLimit(1)

            ForEach(chipTags, id: \.self) { tag in
                Text(tag.value.map { "@\(tag.name)(\($0))" } ?? "@\(tag.name)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let due = item.dueDateString {
                Text(due)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
        }
        .padding(.leading, CGFloat(item.indentLevel) * 16)
        .padding(.vertical, 2)
    }

    /// due and done render dedicated affordances; everything else is a chip.
    private var chipTags: [TodoTag] {
        item.tags.filter { $0.name != "due" && $0.name != "done" }
    }
}
```

- [ ] **Step 4: Register the WindowGroup**

In `Clipsmith/App/ClipsmithApp.swift`, after the `claude-toolkit` WindowGroup:

```swift
        WindowGroup(id: "todos") {
            TodoWindowView()
                .environment(appDelegate.todoStore)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentSize)
```

(Same implicitly-unwrapped pattern as `appDelegate.gistService` in the snippets WindowGroup — scene bodies are built after `applicationDidFinishLaunching`.)

- [ ] **Step 5: Menu bar entry**

In `Clipsmith/Views/MenuBarView.swift`:

Append to the `Notification.Name` extension:

```swift
    /// Posted by the .openTodos hotkey (AppDelegate) to open the todo window —
    /// AppDelegate cannot use @Environment(\.openWindow), MenuBarView can.
    static let clipsmithOpenTodos = Notification.Name("clipsmithOpenTodos")
```

Add with the other feature-flag `@AppStorage` properties:

```swift
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false
```

Add after the `appLauncherEnabled` button block:

```swift
        if todoTrackingEnabled {
            Button("Todos...") {
                openTodoWindow()
            }
        }
```

Add after the `.clipsmithOpenSnippets` `.onReceive`:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .clipsmithOpenTodos)) { _ in
            openTodoWindow()
        }
```

Add the method next to `openSnippetWindow()`:

```swift
    /// Opens the todo window with the same activation-policy dance as snippets.
    private func openTodoWindow() {
        Task { @MainActor in
            activateAsRegularApp()
            try? await Task.sleep(for: .milliseconds(100))
            openWindow(id: "todos")
        }
    }
```

- [ ] **Step 6: Verify build + full test suite**

Run: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.
Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
Expected: PASS (no regressions).

- [ ] **Step 7: Manual smoke test** — launch the app, enable Todo Tracking in Settings > General > Features, open menu bar > Todos…, add a project and a task, toggle done, confirm `~/Library/Application Support/Clipsmith/todos.taskpaper` content, edit the file in a text editor and confirm the window updates.

- [ ] **Step 8: Commit**

```bash
git add Clipsmith/Views/Todos/TodoWindowView.swift Clipsmith/Views/Todos/TodoListView.swift Clipsmith/App/ClipsmithApp.swift Clipsmith/App/AppDelegate.swift Clipsmith/Views/MenuBarView.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): tabbed todo window, task list with keyboard shortcuts, menu bar entry"
```

---

### Task 7: Quick-add bezel

**Files:**
- Create: `Clipsmith/Views/Todos/TodoQuickAddController.swift` (controller + small view + observable model in one file; pbxproj: AF0113/AA0113, group GG0017, phase BB0002)
- Modify: `Clipsmith.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TodoQuickAddParser.parse(_:)` (Task 3), `TodoStore.addTask(text:projectName:tags:)` / `loadIfNeeded()` (Task 2).
- Produces: `@MainActor final class TodoQuickAddController: NSPanel` with `var todoStore: TodoStore?`, `func show()`, `func hide()`. Wired by AppDelegate in Task 8.

- [ ] **Step 1: Create `Clipsmith/Views/Todos/TodoQuickAddController.swift`** (register AF0113/AA0113, group GG0017, phase BB0002)

```swift
import AppKit
import SwiftUI
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "TodoQuickAddController"
)

/// Text state shared between the panel (commit/reset) and the SwiftUI field.
@MainActor
@Observable
final class TodoQuickAddModel {
    var text = ""
}

/// Single-field quick-add view hosted inside the panel.
struct TodoQuickAddView: View {
    @Bindable var model: TodoQuickAddModel
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            TextField(
                "Add todo — e.g. Fix pricing #lara @due(2026-09-05) @today",
                text: $model.text
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .onSubmit(onCommit)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Stripped-down non-activating quick-add panel (BezelController pattern):
/// `.nonactivatingPanel` so the frontmost app keeps focus, high window level,
/// Escape and click-outside dismiss, Enter saves via TodoStore.
@MainActor
final class TodoQuickAddController: NSPanel {

    /// Injected by AppDelegate before first show().
    var todoStore: TodoStore?

    private let model = TodoQuickAddModel()
    private var globalMonitor: Any?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    init() {
        // CRITICAL: .nonactivatingPanel MUST be in the init styleMask —
        // WindowServer does not honour setting it afterwards.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 56),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let hostingView = NSHostingView(
            rootView: TodoQuickAddView(model: model) { [weak self] in self?.commit() })
        hostingView.sizingOptions = []   // CRITICAL: prevents constraint-loop crash
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Intercept Escape/Return before the hosted TextField swallows them.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53:            // Escape
                hide()
                return
            case 36, 76:        // Return, Enter (numpad)
                commit()
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    // MARK: - show / hide

    func show() {
        todoStore?.loadIfNeeded()
        model.text = ""
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        registerClickOutsideMonitor()
        logger.info("Todo quick-add shown")
    }

    func hide() {
        orderOut(nil)
        removeClickOutsideMonitor()
        model.text = ""
    }

    // MARK: - Commit

    /// Enter: parse the inline syntax and save. Unmatched #project names
    /// create the project (TodoStore matches case-insensitively); no
    /// #project → Inbox. Empty input just dismisses.
    private func commit() {
        let input = model.text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { hide(); return }
        let result = TodoQuickAddParser.parse(input)
        guard !result.title.isEmpty || !result.tags.isEmpty else { hide(); return }
        todoStore?.addTask(
            text: result.title,
            projectName: result.projectName,
            tags: result.tags)
        hide()
    }

    // MARK: - Placement / dismissal

    /// Upper third of the main screen — quick-add is glanceable, not modal.
    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.minY + screenFrame.height * 0.66
        )
        setFrameOrigin(origin)
    }

    private func registerClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                Task { @MainActor in self.hide() }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Clipsmith/Views/Todos/TodoQuickAddController.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(todos): non-activating quick-add bezel with inline #project/@tag syntax"
```

---

### Task 8: Hotkeys and AppDelegate wiring

**Files:**
- Modify: `Clipsmith/Settings/KeyboardShortcutNames.swift`
- Modify: `Clipsmith/Views/Settings/HotkeySettingsTab.swift`
- Modify: `Clipsmith/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `TodoQuickAddController` (Task 7), `TodoStore` (Task 2), `.clipsmithOpenTodos` (Task 6), `.clipsmithTodoFilePathChanged` (Task 5).
- Produces: `KeyboardShortcuts.Name.openTodos`, `.todoQuickAdd` (no default bindings — user configures in Settings > Shortcuts, like `.appLauncher`); `AppDelegate.todoQuickAddController`.

- [ ] **Step 1: Shortcut names**

Append inside the extension in `Clipsmith/Settings/KeyboardShortcutNames.swift`:

```swift
    /// Hotkey that opens the todo window (Phase 13).
    /// No default binding — user must configure in Settings > Shortcuts.
    static let openTodos = Self("openTodos")

    /// Hotkey that shows the todo quick-add bezel (Phase 13).
    /// No default binding — user must configure in Settings > Shortcuts.
    static let todoQuickAdd = Self("todoQuickAdd")
```

- [ ] **Step 2: Recorders (shown only when the flag is on)**

In `Clipsmith/Views/Settings/HotkeySettingsTab.swift`, add the property:

```swift
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false
```

and inside the `Section`, after the "Save Clipboard as Snippet" recorder:

```swift
                if todoTrackingEnabled {
                    KeyboardShortcuts.Recorder(
                        "Open Todos",
                        name: .openTodos
                    )
                    KeyboardShortcuts.Recorder(
                        "Todo Quick-Add",
                        name: .todoQuickAdd
                    )
                }
```

- [ ] **Step 3: AppDelegate wiring**

In `Clipsmith/App/AppDelegate.swift`:

Add next to `var todoStore: TodoStore!` (from Task 6):

```swift
    var todoQuickAddController: TodoQuickAddController!
```

In `applicationDidFinishLaunching`, extend the register-defaults dictionary (after the Phase 12 entries):

```swift
            // Phase 13 — Todo Tracking feature flag + list preference
            AppSettingsKeys.todoTrackingEnabled: false,
            AppSettingsKeys.todoShowCompleted: false
```

(Remember the trailing comma on the previous `AppSettingsKeys.commandPalettePrefix: "="` line.)

Extend the Phase 13 init block added in Task 6:

```swift
        todoQuickAddController = TodoQuickAddController()
        todoQuickAddController.todoStore = todoStore

        // Re-point TodoStore when Settings changes the todo file path.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTodoFilePathChanged),
            name: .clipsmithTodoFilePathChanged,
            object: nil
        )
```

Register both hotkeys with the other `KeyboardShortcuts.onKeyDown` registrations (always registered, flag checked at invocation time — project convention D-10):

```swift
        // Register global hotkeys for todo tracking (Phase 13).
        // Always registered, feature flag checked at invocation time so
        // toggling the setting works without app restart.
        KeyboardShortcuts.onKeyDown(for: .openTodos) {
            Task { @MainActor in
                guard UserDefaults.standard.bool(forKey: AppSettingsKeys.todoTrackingEnabled) else { return }
                // MenuBarView observes this and performs the activation-policy
                // dance + openWindow (AppDelegate has no openWindow env).
                NotificationCenter.default.post(name: .clipsmithOpenTodos, object: nil)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .todoQuickAdd) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard UserDefaults.standard.bool(forKey: AppSettingsKeys.todoTrackingEnabled) else { return }
                if self.todoQuickAddController.isVisible {
                    self.todoQuickAddController.hide()
                } else {
                    self.todoQuickAddController.show()
                }
            }
        }
```

Add the observer handler near the other `@objc` handlers:

```swift
    // MARK: - Todo Tracking (Phase 13)

    /// Settings changed the todo file path: flush pending changes to the old
    /// file, then load the new one.
    @objc private func handleTodoFilePathChanged() {
        todoStore?.updateFileURL(TodoStore.resolveFileURL())
    }
```

In `applicationWillTerminate`, next to the other `hide()` calls:

```swift
        todoQuickAddController?.hide()
```

- [ ] **Step 4: Verify build + full suite**

Run: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.
Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
Expected: PASS.

- [ ] **Step 5: Manual smoke test** — assign both hotkeys in Settings > Shortcuts (they appear only with the flag on), trigger quick-add over another app, type `Try quick add #scratch @today`, Enter; confirm the frontmost app never lost focus and the task landed in a new `scratch` project; open the todo window via hotkey; change the file path in Settings > Todos and confirm the window follows.

- [ ] **Step 6: Commit**

```bash
git add Clipsmith/Settings/KeyboardShortcutNames.swift Clipsmith/Views/Settings/HotkeySettingsTab.swift Clipsmith/App/AppDelegate.swift
git commit -m "feat(todos): openTodos and todoQuickAdd hotkeys, file-path change wiring"
```

---

### Task 9: CHANGELOG + final verification

**Files:**
- Modify: `CHANGELOG.md` (repo root, Keep-a-Changelog format — `[Unreleased]` section)

- [ ] **Step 1: Update CHANGELOG.md**

Under `## [Unreleased]` → `### Added` (create the heading if absent), add:

```markdown
- Todo Tracking (experimental, Settings > General > Features): keyboard-first todos
  backed by a plain-text TaskPaper file you own (`~/Library/Application
  Support/Clipsmith/todos.taskpaper` by default, changeable in Settings > Todos).
  Tabbed todo window (Today view, per-project tabs, fuzzy search, `@tag` search
  terms, show/hide completed) and a global quick-add bezel with inline
  `#project @tag(value)` syntax. External edits to the file are picked up live.
```

- [ ] **Step 2: Full verification**

Run: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED, no new warnings in the todo files.
Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
Expected: PASS — entire suite, including the four new suites (`TaskPaperParserTests`, `TodoStoreTests`, `TodoQuickAddParserTests`, `TodoWindowViewModelTests`).

- [ ] **Step 3: Round-trip spot check on a real-world file** — create a TaskPaper file by hand with nested items, odd spacing, unknown tags, and no trailing newline; point Settings > Todos at it; toggle one task done and back; `git diff`-style compare (`diff <(cat original) <(cat current)`) must show zero changes.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): todo tracking feature under Unreleased"
```

---

## Self-review notes (spec coverage)

- Parser/model/serializer + round-trip invariant → Task 1. TodoStore CRUD, debounce, atomic write, watcher, missing-file recreation, path override → Task 2. Quick-add parsing semantics → Tasks 3 & 7. Window, tabs, Today view, keyboard map, search via FuzzyMatcher → Tasks 4 & 6. Flag, Settings section, hotkeys, menu bar, pbxproj, CHANGELOG → Tasks 5, 6, 8, 9. Error handling (never-throwing parser, non-blocking `lastError` notice, delete-recreate) → Tasks 1, 2, 6.
- Spec's security-scoped bookmarks intentionally dropped (app is not sandboxed) — flagged in Global Constraints.
- Spec's "AppDelegate observer opens the window": implemented via the existing convention instead (hotkey → notification → MenuBarView `openWindow`), same behavior.
- `moveTask` drops nested indentation when re-homing (v1 treats nesting as flat tasks — consistent with spec scope).




