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
}
