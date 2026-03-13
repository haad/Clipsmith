import AppKit
import SwiftUI

/// An `NSTextView`-backed text editor with basic syntax highlighting.
///
/// Highlights keywords, strings, comments, and numbers based on the selected
/// language. Falls back to plain monospaced text when `language` is `nil`.
struct HighlightedTextEditor: NSViewRepresentable {

    @Binding var text: String
    var language: String?

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isEditable = true
        textView.isSelectable = true
        context.coordinator.language = language
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        context.coordinator.language = language

        if textView.string != text {
            let sel = textView.selectedRange()
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.isUpdating = false
            textView.setSelectedRange(sel)
        }

        context.coordinator.applyHighlighting(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextEditor
        var isUpdating = false
        var language: String?

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let source = storage.string
            let fullRange = NSRange(location: 0, length: (source as NSString).length)

            storage.beginEditing()

            // Reset to default
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ], range: fullRange)

            guard let lang = language, !lang.isEmpty else {
                storage.endEditing()
                return
            }

            let rules = SyntaxRules.rules(for: lang)

            for rule in rules {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
                let matches = regex.matches(in: source, range: fullRange)
                for match in matches {
                    storage.addAttribute(.foregroundColor, value: rule.color, range: match.range)
                }
            }

            storage.endEditing()
        }
    }
}

// MARK: - Syntax Rules

private struct SyntaxRule {
    let pattern: String
    let color: NSColor
    var options: NSRegularExpression.Options = [.anchorsMatchLines]
}

private enum SyntaxRules {

    // Shared patterns
    private static let singleLineComment = SyntaxRule(pattern: "//.*$", color: .commentGreen)
    private static let hashComment = SyntaxRule(pattern: "#.*$", color: .commentGreen)
    private static let sqlComment = SyntaxRule(pattern: "--.*$", color: .commentGreen)
    private static let multiLineComment = SyntaxRule(
        pattern: "/\\*[\\s\\S]*?\\*/",
        color: .commentGreen,
        options: [.dotMatchesLineSeparators]
    )
    private static let doubleString = SyntaxRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", color: .stringRed)
    private static let singleString = SyntaxRule(pattern: "'(?:[^'\\\\]|\\\\.)*'", color: .stringRed)
    private static let backtickString = SyntaxRule(pattern: "`(?:[^`\\\\]|\\\\.)*`", color: .stringRed)
    private static let numbers = SyntaxRule(pattern: "\\b(?:0x[0-9a-fA-F]+|\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)\\b", color: .numberPurple)

    static func rules(for language: String) -> [SyntaxRule] {
        switch language {
        case "swift":
            return cStyleBase + [keywords(swiftKeywords)]
        case "javascript", "typescript":
            return cStyleBase + [backtickString, keywords(jsKeywords)]
        case "go":
            return cStyleBase + [backtickString, keywords(goKeywords)]
        case "rust":
            return cStyleBase + [keywords(rustKeywords)]
        case "java":
            return cStyleBase + [keywords(javaKeywords)]
        case "kotlin":
            return cStyleBase + [keywords(kotlinKeywords)]
        case "c", "cpp":
            return cStyleBase + [keywords(cKeywords)]
        case "python":
            return pythonBase + [keywords(pythonKeywords)]
        case "ruby":
            return rubyBase + [keywords(rubyKeywords)]
        case "bash":
            return [hashComment, doubleString, singleString, numbers, keywords(bashKeywords)]
        case "sql":
            return [sqlComment, multiLineComment, doubleString, singleString, numbers, keywords(sqlKeywords)]
        case "json":
            return [doubleString, numbers]
        case "yaml":
            return [hashComment, doubleString, singleString, numbers, keywords(yamlKeywords)]
        case "html":
            return htmlRules
        case "css":
            return cssRules
        case "markdown":
            return markdownRules
        default:
            return cStyleBase
        }
    }

    // Base rule sets
    private static var cStyleBase: [SyntaxRule] {
        [singleLineComment, multiLineComment, doubleString, singleString, numbers]
    }

    private static var pythonBase: [SyntaxRule] {
        [
            hashComment,
            SyntaxRule(pattern: "\"\"\"[\\s\\S]*?\"\"\"", color: .stringRed, options: [.dotMatchesLineSeparators]),
            SyntaxRule(pattern: "'''[\\s\\S]*?'''", color: .stringRed, options: [.dotMatchesLineSeparators]),
            doubleString, singleString, numbers,
        ]
    }

    private static var rubyBase: [SyntaxRule] {
        [hashComment, doubleString, singleString, numbers]
    }

    private static var htmlRules: [SyntaxRule] {
        [
            SyntaxRule(pattern: "<!--[\\s\\S]*?-->", color: .commentGreen, options: [.dotMatchesLineSeparators]),
            SyntaxRule(pattern: "</?\\w[^>]*>", color: .keywordBlue),
            doubleString, singleString,
        ]
    }

    private static var cssRules: [SyntaxRule] {
        [
            multiLineComment, doubleString, singleString, numbers,
            SyntaxRule(pattern: "\\b(?:color|background|margin|padding|border|font|display|position|width|height|top|left|right|bottom|flex|grid|opacity|transition|transform|z-index)\\b", color: .keywordBlue),
            SyntaxRule(pattern: "#[0-9a-fA-F]{3,8}\\b", color: .numberPurple),
        ]
    }

    private static var markdownRules: [SyntaxRule] {
        [
            SyntaxRule(pattern: "^#{1,6}\\s.*$", color: .keywordBlue),
            SyntaxRule(pattern: "\\*\\*[^*]+\\*\\*", color: .keywordBlue),
            SyntaxRule(pattern: "\\*[^*]+\\*", color: .commentGreen),
            SyntaxRule(pattern: "`[^`]+`", color: .stringRed),
            SyntaxRule(pattern: "^```[\\s\\S]*?^```", color: .stringRed, options: [.anchorsMatchLines, .dotMatchesLineSeparators]),
        ]
    }

    // Keyword helper
    private static func keywords(_ words: [String]) -> SyntaxRule {
        let joined = words.joined(separator: "|")
        return SyntaxRule(pattern: "\\b(?:\(joined))\\b", color: .keywordBlue)
    }

    // Language-specific keyword lists
    private static let swiftKeywords = [
        "import", "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
        "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat", "return",
        "break", "continue", "throw", "throws", "try", "catch", "do", "async", "await",
        "self", "Self", "super", "init", "deinit", "nil", "true", "false",
        "public", "private", "internal", "fileprivate", "open", "static", "final", "override",
        "weak", "unowned", "lazy", "mutating", "typealias", "associatedtype", "where",
        "some", "any", "in", "is", "as", "inout", "@MainActor", "@State", "@Binding",
    ]

    private static let jsKeywords = [
        "import", "export", "from", "default", "function", "class", "extends", "const", "let", "var",
        "if", "else", "switch", "case", "for", "while", "do", "return", "break", "continue",
        "try", "catch", "finally", "throw", "new", "delete", "typeof", "instanceof",
        "this", "super", "null", "undefined", "true", "false", "async", "await", "yield",
        "of", "in", "interface", "type", "enum", "implements", "abstract", "readonly",
    ]

    private static let goKeywords = [
        "package", "import", "func", "type", "struct", "interface", "map", "chan",
        "if", "else", "switch", "case", "default", "for", "range", "return", "break", "continue",
        "go", "select", "defer", "fallthrough", "goto", "var", "const",
        "nil", "true", "false", "iota", "make", "new", "len", "cap", "append", "delete",
    ]

    private static let rustKeywords = [
        "use", "mod", "pub", "crate", "fn", "struct", "enum", "trait", "impl", "type",
        "let", "mut", "const", "static", "ref", "self", "Self", "super",
        "if", "else", "match", "loop", "while", "for", "in", "return", "break", "continue",
        "async", "await", "move", "unsafe", "where", "true", "false", "None", "Some", "Ok", "Err",
    ]

    private static let javaKeywords = [
        "import", "package", "class", "interface", "enum", "extends", "implements",
        "public", "private", "protected", "static", "final", "abstract", "synchronized",
        "void", "int", "long", "double", "float", "boolean", "char", "byte", "short",
        "if", "else", "switch", "case", "default", "for", "while", "do", "return",
        "break", "continue", "try", "catch", "finally", "throw", "throws", "new",
        "this", "super", "null", "true", "false", "instanceof",
    ]

    private static let kotlinKeywords = [
        "import", "package", "class", "interface", "object", "fun", "val", "var",
        "if", "else", "when", "for", "while", "do", "return", "break", "continue",
        "try", "catch", "finally", "throw", "is", "as", "in", "out",
        "this", "super", "null", "true", "false", "override", "open", "abstract",
        "data", "sealed", "companion", "suspend", "inline", "lateinit", "by", "lazy",
    ]

    private static let cKeywords = [
        "include", "define", "ifdef", "ifndef", "endif", "pragma",
        "int", "long", "short", "char", "float", "double", "void", "unsigned", "signed",
        "const", "static", "extern", "volatile", "register", "auto", "typedef", "struct",
        "union", "enum", "sizeof", "return", "if", "else", "switch", "case", "default",
        "for", "while", "do", "break", "continue", "goto", "NULL", "true", "false",
        "class", "public", "private", "protected", "virtual", "override", "template",
        "namespace", "using", "new", "delete", "try", "catch", "throw",
    ]

    private static let pythonKeywords = [
        "import", "from", "as", "class", "def", "lambda", "return", "yield",
        "if", "elif", "else", "for", "while", "break", "continue", "pass",
        "try", "except", "finally", "raise", "with", "assert",
        "and", "or", "not", "in", "is", "None", "True", "False",
        "global", "nonlocal", "del", "async", "await", "self",
    ]

    private static let rubyKeywords = [
        "require", "include", "module", "class", "def", "end", "do", "begin", "rescue",
        "if", "elsif", "else", "unless", "case", "when", "while", "until", "for",
        "return", "break", "next", "yield", "block_given\\?",
        "self", "super", "nil", "true", "false", "and", "or", "not", "in",
        "attr_reader", "attr_writer", "attr_accessor", "puts", "print",
    ]

    private static let bashKeywords = [
        "if", "then", "elif", "else", "fi", "for", "while", "do", "done", "in",
        "case", "esac", "function", "return", "exit", "echo", "printf",
        "local", "export", "readonly", "unset", "shift", "source",
        "true", "false", "test", "set", "cd", "ls", "grep", "sed", "awk",
    ]

    private static let sqlKeywords = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "BETWEEN", "LIKE",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "DROP", "ALTER",
        "TABLE", "INDEX", "VIEW", "DATABASE", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER",
        "ON", "GROUP", "BY", "ORDER", "ASC", "DESC", "HAVING", "LIMIT", "OFFSET",
        "DISTINCT", "AS", "NULL", "IS", "EXISTS", "UNION", "ALL", "COUNT", "SUM", "AVG",
        "select", "from", "where", "and", "or", "not", "in", "between", "like",
        "insert", "into", "values", "update", "set", "delete", "create", "drop", "alter",
        "table", "index", "view", "join", "inner", "left", "right", "outer",
        "on", "group", "by", "order", "asc", "desc", "having", "limit", "offset",
        "distinct", "as", "null", "is", "exists", "union", "all", "count", "sum", "avg",
    ]

    private static let yamlKeywords = [
        "true", "false", "null", "yes", "no", "on", "off",
    ]
}

// MARK: - Theme Colors

private extension NSColor {
    /// Blue for keywords
    static let keywordBlue = NSColor(srgbRed: 0.16, green: 0.40, blue: 0.82, alpha: 1)
    /// Red-orange for strings
    static let stringRed = NSColor(srgbRed: 0.78, green: 0.24, blue: 0.18, alpha: 1)
    /// Green for comments
    static let commentGreen = NSColor(srgbRed: 0.24, green: 0.56, blue: 0.28, alpha: 1)
    /// Purple for numbers
    static let numberPurple = NSColor(srgbRed: 0.60, green: 0.22, blue: 0.70, alpha: 1)
}
