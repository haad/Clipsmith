import Foundation

// MARK: - TextTransform

/// Descriptor for one text transform available in the bezel transform picker
/// and the right-click quick-action menu.
///
/// `apply` returns nil when the transform does not apply to the input
/// (invalid JSON, malformed Base64, no URLs found…) — the UI shows
/// `failureMessage` and does NOT paste.
struct TextTransform: Sendable, Identifiable {
    let id: String
    let displayName: String
    /// Extra fuzzy-match terms, space-separated (e.g. "b64" for Base64).
    let keywords: String
    /// Shown inline in the picker when `apply` returns nil.
    let failureMessage: String
    let apply: @Sendable (String) -> String?
}

// MARK: - TransformRegistry

/// Enumerates all text transforms. Pure data — no state, no isolation.
enum TransformRegistry {

    static func transform(withID id: String) -> TextTransform? {
        all.first { $0.id == id }
    }

    static let all: [TextTransform] = [
        // MARK: Case
        TextTransform(id: "case.upper", displayName: "UPPERCASE", keywords: "caps upper case",
                      failureMessage: "", apply: { TextTransformer.uppercase($0) }),
        TextTransform(id: "case.lower", displayName: "lowercase", keywords: "lower case",
                      failureMessage: "", apply: { TextTransformer.lowercase($0) }),
        TextTransform(id: "case.title", displayName: "Title Case", keywords: "capitalize title",
                      failureMessage: "", apply: { TextTransformer.titleCase($0) }),
        TextTransform(id: "case.camel", displayName: "camelCase", keywords: "camel case identifier",
                      failureMessage: "", apply: { TextTransformer.camelCase($0) }),
        TextTransform(id: "case.pascal", displayName: "PascalCase", keywords: "pascal case identifier",
                      failureMessage: "", apply: { TextTransformer.pascalCase($0) }),
        TextTransform(id: "case.snake", displayName: "snake_case", keywords: "snake case underscore identifier",
                      failureMessage: "", apply: { TextTransformer.snakeCase($0) }),
        TextTransform(id: "case.kebab", displayName: "kebab-case", keywords: "kebab dash case identifier",
                      failureMessage: "", apply: { TextTransformer.kebabCase($0) }),

        // MARK: Whitespace & lines
        TextTransform(id: "text.trim", displayName: "Trim Whitespace", keywords: "trim strip whitespace",
                      failureMessage: "", apply: { TextTransformer.trimWhitespace($0) }),
        TextTransform(id: "lines.sort", displayName: "Sort Lines", keywords: "sort lines alphabetical",
                      failureMessage: "", apply: { TextTransformer.sortLines($0) }),
        TextTransform(id: "lines.dedupe", displayName: "Deduplicate Lines", keywords: "dedupe unique lines duplicates",
                      failureMessage: "", apply: { TextTransformer.dedupeLines($0) }),
        TextTransform(id: "lines.reverse", displayName: "Reverse Lines", keywords: "reverse lines flip",
                      failureMessage: "", apply: { TextTransformer.reverseLines($0) }),

        // MARK: Encode / decode
        TextTransform(id: "encode.url", displayName: "URL Encode", keywords: "url percent encode escape",
                      failureMessage: "", apply: { TextTransformer.urlEncode($0) }),
        TextTransform(id: "decode.url", displayName: "URL Decode", keywords: "url percent decode unescape",
                      failureMessage: "Not valid percent-encoding", apply: { TextTransformer.urlDecode($0) }),
        TextTransform(id: "encode.base64", displayName: "Base64 Encode", keywords: "base64 b64 encode",
                      failureMessage: "Cannot encode as UTF-8", apply: { TextTransformer.base64Encode($0) }),
        TextTransform(id: "decode.base64", displayName: "Base64 Decode", keywords: "base64 b64 decode",
                      failureMessage: "Not valid Base64", apply: { TextTransformer.base64Decode($0) }),
        TextTransform(id: "text.escape", displayName: "Escape String", keywords: "escape quotes newlines json c",
                      failureMessage: "", apply: { TextTransformer.escape($0) }),
        TextTransform(id: "text.unescape", displayName: "Unescape String", keywords: "unescape quotes newlines",
                      failureMessage: "", apply: { TextTransformer.unescape($0) }),

        // MARK: Format
        TextTransform(id: "format.quotes", displayName: "Wrap in Quotes", keywords: "quote wrap string",
                      failureMessage: "", apply: { TextTransformer.wrapInQuotes($0) }),
        TextTransform(id: "format.codeblock", displayName: "Markdown Code Block", keywords: "markdown code fence block",
                      failureMessage: "", apply: { TextTransformer.markdownCodeBlock($0) }),
        TextTransform(id: "format.jsonpretty", displayName: "JSON Pretty Print", keywords: "json pretty format indent",
                      failureMessage: "Not valid JSON", apply: { TextTransformer.jsonPrettyPrint($0) }),
        TextTransform(id: "format.slugify", displayName: "Slugify", keywords: "slug url kebab filename",
                      failureMessage: "", apply: { TextTransformer.slugify($0) }),

        // MARK: Dev
        TextTransform(id: "dev.jwt", displayName: "JWT Decode", keywords: "jwt token decode auth",
                      failureMessage: "Not a valid JWT", apply: { TextTransformer.jwtDecode($0) }),
        TextTransform(id: "dev.ts2iso", displayName: "Timestamp → ISO Date", keywords: "unix timestamp epoch date iso",
                      failureMessage: "Not a numeric timestamp", apply: { TextTransformer.timestampToISO($0) }),
        TextTransform(id: "dev.iso2ts", displayName: "ISO Date → Timestamp", keywords: "iso date unix timestamp epoch",
                      failureMessage: "Not an ISO 8601 date", apply: { TextTransformer.isoToTimestamp($0) }),

        // MARK: Extract
        TextTransform(id: "extract.urls", displayName: "Extract URLs", keywords: "extract urls links",
                      failureMessage: "No URLs found", apply: { TextTransformer.extractURLs($0) }),
        TextTransform(id: "extract.emails", displayName: "Extract Emails", keywords: "extract emails addresses",
                      failureMessage: "No email addresses found", apply: { TextTransformer.extractEmails($0) }),
    ]
}
