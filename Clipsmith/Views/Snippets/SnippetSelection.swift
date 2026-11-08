import AppKit
import WebKit

/// What a snippet paste sends: the selection for markdown snippets when
/// there is one, otherwise the whole raw content. Code snippets always paste
/// whole, so a leftover selection never sends a fragment.
enum SnippetPaste {
    static func content(full: String, language: String?, selection: String?) -> String {
        guard language == "markdown", let selection, !selection.isEmpty else { return full }
        return selection
    }
}

/// Reads the current selection from whichever view is showing the snippet:
/// the rendered markdown web view or the raw text editor.
@MainActor
final class SnippetSelection {
    weak var textView: NSTextView?
    weak var webView: WKWebView?

    /// nil when nothing is selected. The web view wins when it is on screen
    /// (rendered mode); otherwise the editor's selection is used.
    func selectedText() async -> String? {
        if let webView, webView.window != nil {
            let value = try? await webView.evaluateJavaScript("window.getSelection().toString()")
            return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let textView, textView.window != nil {
            let range = textView.selectedRange()
            guard range.length > 0 else { return nil }
            return (textView.string as NSString).substring(with: range)
        }
        return nil
    }
}
