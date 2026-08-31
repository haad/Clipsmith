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
