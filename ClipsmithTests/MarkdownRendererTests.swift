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
}
