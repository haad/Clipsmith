import Foundation
import Markdown

/// Markdown snippet content → HTML fragment for the rendered snippet view.
///
/// Parsing is swift-markdown's (CommonMark + GFM tables, task lists,
/// strikethrough). Rendering is our own: swift-markdown's `HTMLFormatter`
/// escapes nothing, so `a < b` or `<div>` in a code block would become
/// markup. Here all text is escaped and raw HTML in the note is shown as
/// text. Fenced code blocks come out as `<pre><code class="language-<lang>">`.
enum MarkdownRenderer {
    static func bodyHTML(from markdown: String) -> String {
        var renderer = EscapingHTMLRenderer()
        renderer.visit(Document(parsing: markdown))
        return renderer.result
    }
}

private struct EscapingHTMLRenderer: MarkupWalker {
    var result = ""

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private mutating func wrap(_ tag: String, _ markup: Markup, newline: Bool = true) {
        result += "<\(tag)>"
        descendInto(markup)
        result += "</\(tag)>" + (newline ? "\n" : "")
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) { wrap("h\(heading.level)", heading) }
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) { wrap("blockquote", blockQuote) }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) { result += "<hr>\n" }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { result += "<p>\(Self.escape(html.rawHTML))</p>\n" }

    /// A list item holding a single paragraph renders it inline (tight list),
    /// so items read `<li>one</li>`, not `<li><p>one</p></li>`.
    mutating func visitParagraph(_ paragraph: Paragraph) {
        if paragraph.parent is ListItem, paragraph.parent?.childCount == 1 {
            descendInto(paragraph)
        } else {
            wrap("p", paragraph)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = codeBlock.language.map { " class=\"language-\(Self.escape($0))\"" } ?? ""
        result += "<pre><code\(lang)>\(Self.escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) { wrap("ul", list) }

    mutating func visitOrderedList(_ list: OrderedList) {
        result += list.startIndex == 1 ? "<ol>" : "<ol start=\"\(list.startIndex)\">"
        descendInto(list)
        result += "</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) {
        result += "<li>"
        if let checkbox = item.checkbox {
            result += checkbox == .checked
                ? "<input type=\"checkbox\" disabled checked> "
                : "<input type=\"checkbox\" disabled> "
        }
        descendInto(item)
        result += "</li>\n"
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) { wrap("table", table) }
    mutating func visitTableHead(_ head: Table.Head) {
        result += "<thead><tr>"
        descendInto(head)
        result += "</tr></thead>\n"
    }
    mutating func visitTableBody(_ body: Table.Body) { wrap("tbody", body) }
    mutating func visitTableRow(_ row: Table.Row) { wrap("tr", row) }
    mutating func visitTableCell(_ cell: Table.Cell) {
        wrap(cell.parent is Table.Head ? "th" : "td", cell, newline: false)
    }

    // MARK: Inlines

    mutating func visitText(_ text: Markdown.Text) { result += Self.escape(text.string) }
    mutating func visitInlineHTML(_ html: InlineHTML) { result += Self.escape(html.rawHTML) }
    mutating func visitInlineCode(_ code: InlineCode) { result += "<code>\(Self.escape(code.code))</code>" }
    mutating func visitEmphasis(_ emphasis: Emphasis) { wrap("em", emphasis, newline: false) }
    mutating func visitStrong(_ strong: Strong) { wrap("strong", strong, newline: false) }
    mutating func visitStrikethrough(_ s: Strikethrough) { wrap("del", s, newline: false) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "<br>\n" }

    mutating func visitLink(_ link: Markdown.Link) {
        result += "<a href=\"\(Self.escape(link.destination ?? ""))\">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) {
        result += "<img src=\"\(Self.escape(image.source ?? ""))\" alt=\"\(Self.escape(image.plainText))\">"
    }
}
