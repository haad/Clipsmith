import XCTest
@testable import Clipsmith

final class SnippetReferenceTests: XCTestCase {

    func testSegmentsSplitTextAndReferences() {
        XCTAssertEqual(SnippetReference.segments(in: "Write a blog about [[xyz]] soon"),
                       [.text("Write a blog about "), .reference("xyz"), .text(" soon")])
    }

    func testTwoReferencesOnOneLine() {
        XCTAssertEqual(SnippetReference.names(in: "[[a]] and [[b]]"), ["a", "b"])
    }

    func testUnclosedAndEmptyAreText() {
        XCTAssertEqual(SnippetReference.segments(in: "x [[open"), [.text("x [[open")])
        XCTAssertEqual(SnippetReference.names(in: "[[]] and [[  ]]"), [])
    }

    func testNameIsTrimmed() {
        XCTAssertEqual(SnippetReference.names(in: "[[ xyz ]]"), ["xyz"])
    }

    func testRewriteIsCaseInsensitiveAndLeavesOthers() {
        XCTAssertEqual(
            SnippetReference.rewriting("- see [[XYZ]] and [[xyzzy]] @today", from: "xyz", to: "Blog notes"),
            "- see [[Blog notes]] and [[xyzzy]] @today")
    }

    func testRewriteMatchesTrimmedName() {
        XCTAssertEqual(SnippetReference.rewriting("[[ xyz ]]", from: "xyz", to: "abc"), "[[abc]]")
    }

    func testMentions() {
        XCTAssertTrue(SnippetReference.mentions("read [[ XYZ ]] now", name: "xyz"))
        XCTAssertFalse(SnippetReference.mentions("read [[xyzw]]", name: "xyz"))
    }

    func testOpenQuery() {
        XCTAssertEqual(SnippetReference.openQuery(in: "write [[Blo"), "Blo")
        XCTAssertEqual(SnippetReference.openQuery(in: "write [["), "")
        XCTAssertNil(SnippetReference.openQuery(in: "write [[Blog]]"))
        XCTAssertNil(SnippetReference.openQuery(in: "write [Blog"))
        XCTAssertNil(SnippetReference.openQuery(in: "plain"))
    }

    func testCompleting() {
        XCTAssertEqual(SnippetReference.completing("write [[blo", with: "Blog notes"), "write [[Blog notes]] ")
        XCTAssertEqual(SnippetReference.completing("[[a]] then [[", with: "b"), "[[a]] then [[b]] ")
        XCTAssertEqual(SnippetReference.completing("no link", with: "b"), "no link")
    }

    func testSuggestions() {
        let names = ["Blog notes", "backlog", "Deploy", "blog ideas"]
        XCTAssertEqual(SnippetReference.suggestions(for: "x [[blo", names: names), ["blog ideas", "Blog notes"])
        XCTAssertEqual(SnippetReference.suggestions(for: "x [[", names: names, limit: 2), ["backlog", "blog ideas"])
        XCTAssertEqual(SnippetReference.suggestions(for: "x [[log", names: names), ["backlog", "blog ideas", "Blog notes"])
        XCTAssertEqual(SnippetReference.suggestions(for: "x [[blog]]", names: names), [])
        XCTAssertEqual(SnippetReference.suggestions(for: "x", names: names), [])
    }
}
