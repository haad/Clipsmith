import XCTest
@testable import Clipsmith

final class MarkdownRendererTests: XCTestCase {

    func testHeadingListEmphasis() {
        let html = MarkdownRenderer.bodyHTML(from: "# Title\n\n- one\n- **two**\n")
        XCTAssertTrue(html.contains("<h1>Title</h1>"), html)
        XCTAssertTrue(html.contains("<li>one</li>"), html)
        XCTAssertTrue(html.contains("<strong>two</strong>"), html)
    }

    func testFencedCodeKeepsLanguageClassAndEscapes() {
        let html = MarkdownRenderer.bodyHTML(from: "```swift\nlet a = 1 < 2\n```\n")
        XCTAssertTrue(html.contains(#"class="language-swift""#), html)
        XCTAssertTrue(html.contains("1 &lt; 2"), html)
    }

    func testTable() {
        let html = MarkdownRenderer.bodyHTML(from: "| a | b |\n|---|---|\n| 1 | 2 |\n")
        XCTAssertTrue(html.contains("<table>"), html)
        XCTAssertTrue(html.contains("<td>1</td>"), html)
    }

    func testLink() {
        let html = MarkdownRenderer.bodyHTML(from: "[x](https://example.com)")
        XCTAssertTrue(html.contains(#"<a href="https://example.com">x</a>"#), html)
    }

    func testTextAndInlineCodeAreEscaped() {
        let html = MarkdownRenderer.bodyHTML(from: "a & b < c and `<div>`\n")
        XCTAssertTrue(html.contains("a &amp; b &lt; c"), html)
        XCTAssertTrue(html.contains("<code>&lt;div&gt;</code>"), html)
    }

    func testRawHTMLIsShownAsText() {
        let html = MarkdownRenderer.bodyHTML(from: "<script>alert(1)</script>\n")
        XCTAssertFalse(html.contains("<script>"), html)
        XCTAssertTrue(html.contains("&lt;script&gt;"), html)
    }

    func testTaskListAndQuote() {
        let html = MarkdownRenderer.bodyHTML(from: "- [x] done\n- [ ] open\n\n> quoted\n")
        XCTAssertTrue(html.contains(#"<input type="checkbox" disabled checked>"#), html)
        XCTAssertTrue(html.contains("<blockquote>"), html)
    }

    func testSnippetReferencesBecomeLinks() {
        let html = MarkdownRenderer.bodyHTML(from: "See [[Blog notes]] & *[[a<b]]*\n")
        XCTAssertTrue(html.contains(#"<a class="snippet-link" href="clipsmith-snippet:Blog%20notes">Blog notes</a> &amp; "#), html)
        XCTAssertTrue(html.contains(#"<em><a class="snippet-link" href="clipsmith-snippet:a%3Cb">a&lt;b</a></em>"#), html)
    }

    func testSnippetReferencesInCodeStayText() {
        let html = MarkdownRenderer.bodyHTML(from: "`[[x]]`\n\n```\n[[y]]\n```\n")
        XCTAssertFalse(html.contains("snippet-link"), html)
        XCTAssertTrue(html.contains("<code>[[x]]</code>"), html)
    }

    func testSnippetNameFromURL() throws {
        let url = try XCTUnwrap(URL(string: "clipsmith-snippet:Blog%20notes"))
        XCTAssertEqual(MarkdownRenderer.snippetName(from: url), "Blog notes")
        XCTAssertNil(MarkdownRenderer.snippetName(from: try XCTUnwrap(URL(string: "https://x.dev"))))
    }
}
