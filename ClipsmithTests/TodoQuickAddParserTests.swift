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
