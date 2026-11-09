import AppKit
import SwiftUI
import WebKit

/// Rendered view of a markdown snippet. Uses the Docs stylesheet; fenced
/// code is highlighted by the highlight.js copy HighlightSwift already ships
/// in the app bundle (offline). If that file is missing, code renders plain.
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let selection: SnippetSelection

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let hljs = Self.highlightJS {
            config.userContentController.addUserScript(WKUserScript(
                source: hljs + "\nhljs.highlightAll();",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        selection.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        selection.webView = webView
        // Reload only when the text changes, so a selection survives
        // unrelated SwiftUI updates.
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        webView.loadHTMLString(Self.page(for: markdown), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func page(for markdown: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="dark light">
        <style>
        \(BrowserWebStyles.docStyles)
        \(highlightStyles)
        </style>
        </head>
        <body>\(MarkdownRenderer.bodyHTML(from: markdown))</body>
        </html>
        """
    }

    /// Loaded once; nil when HighlightSwift's resource bundle isn't found.
    private static let highlightJS: String? = {
        guard let bundleURL = Bundle.main.url(forResource: "HighlightSwift_HighlightSwift", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL),
              let url = bundle.url(forResource: "highlight.min", withExtension: "js")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// highlight.js token colors matching the doc stylesheet (dark default,
    /// light under prefers-color-scheme).
    private static let highlightStyles = """
    .hljs-keyword, .hljs-selector-tag, .hljs-built_in { color: #c586c0; }
    .hljs-string, .hljs-attr-value, .hljs-regexp { color: #ce9178; }
    .hljs-comment, .hljs-quote { color: #6a9955; font-style: italic; }
    .hljs-number, .hljs-literal { color: #b5cea8; }
    .hljs-title, .hljs-title.function_, .hljs-section { color: #dcdcaa; }
    .hljs-type, .hljs-title.class_ { color: #4ec9b0; }
    .hljs-attr, .hljs-variable, .hljs-params { color: #9cdcfe; }
    .hljs-meta { color: #d7ba7d; }
    a.snippet-link { text-decoration: none; border-bottom: 1px dashed currentColor; }
    @media (prefers-color-scheme: light) {
        .hljs-keyword, .hljs-selector-tag, .hljs-built_in { color: #af00db; }
        .hljs-string, .hljs-attr-value, .hljs-regexp { color: #a31515; }
        .hljs-comment, .hljs-quote { color: #008000; }
        .hljs-number, .hljs-literal { color: #098658; }
        .hljs-title, .hljs-title.function_, .hljs-section { color: #795e26; }
        .hljs-type, .hljs-title.class_ { color: #267f99; }
        .hljs-attr, .hljs-variable, .hljs-params { color: #001080; }
        .hljs-meta { color: #795e26; }
    }
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String?

        /// `[[snippet]]` links open in Clipsmith; other links in the default
        /// browser, never inside the snippet view.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if let name = MarkdownRenderer.snippetName(from: url) {
                    openSnippetReference(name)
                } else {
                    NSWorkspace.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }
    }
}
