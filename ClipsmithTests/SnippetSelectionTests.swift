import XCTest
@testable import Clipsmith

final class SnippetSelectionTests: XCTestCase {

    func testMarkdownUsesSelection() {
        XCTAssertEqual(SnippetPaste.content(full: "# all", language: "markdown", selection: "part"), "part")
    }

    func testEmptySelectionPastesFull() {
        XCTAssertEqual(SnippetPaste.content(full: "# all", language: "markdown", selection: ""), "# all")
        XCTAssertEqual(SnippetPaste.content(full: "# all", language: "markdown", selection: nil), "# all")
    }

    func testCodeSnippetIgnoresSelection() {
        XCTAssertEqual(SnippetPaste.content(full: "let a = 1", language: "swift", selection: "a"), "let a = 1")
    }
}
