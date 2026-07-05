# Bezel Transform Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fuzzy-searchable transform picker inside the Cmd-Shift-V clipboard bezel — Tab opens it, Enter transform-and-pastes in one motion — plus ~16 new text transforms.

**Architecture:** Pure transform functions stay in `TextTransformer` (static, no isolation); a new `TransformRegistry` enumerates them as `TextTransform` descriptors with fuzzy keywords and nil-on-failure semantics. Picker state lives in `BezelViewModel` (`@Observable @MainActor`), keyboard routing in `BezelController` (NSPanel `sendEvent`/`keyDown`), UI as an overlay in `BezelView` mirroring the existing cheat-sheet overlay. Paste reuses `PasteService.paste(content:into:)` via a parameterized `pasteAndHide(content:)`.

**Tech Stack:** Swift 6 (`SWIFT_STRICT_CONCURRENCY = complete`), SwiftUI, AppKit NSPanel, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-05-bezel-transform-picker-design.md`

## Global Constraints

- Swift 6 strict concurrency: all closures crossing isolation must be `@Sendable`; `TextTransform.apply` is `@Sendable (String) -> String?`.
- `@MainActor` on all UI-facing classes (ViewModels, Controllers). Do NOT remove `@MainActor` from `@Observable` classes (see commit `aa4bc26`).
- `Clipsmith.xcodeproj/project.pbxproj` is manually managed. New files MUST be registered by hand (4 places each). Free IDs for this plan: app file `AA0101`/`AF0101`, test file `AA0102`/`AF0102`.
- Never log clipping content (privacy requirement — see `BezelController.pasteAndHide`).
- No JSON↔YAML transform (out of scope — would need Yams dependency).
- Match existing style: `// MARK:` sections, doc comments on public members.
- Build/test commands:
  - All tests: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
  - One suite: append `-only-testing:ClipsmithTests/<SuiteName>`
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## File Structure

- Modify `Clipsmith/Services/TextTransformer.swift` — new pure functions; `jsonPrettyPrint`/`urlDecode` become `String?`.
- Create `Clipsmith/Services/TransformRegistry.swift` — `TextTransform` struct + `TransformRegistry.all`.
- Modify `Clipsmith/Views/BezelViewModel.swift` — picker state + filtering.
- Modify `Clipsmith/Views/BezelController.swift` — routing, `pasteAndHide(content:)`, registry-driven NSMenu.
- Modify `Clipsmith/Views/BezelView.swift` — overlay UI, footer hint, cheat-sheet rows.
- Modify `ClipsmithTests/TextTransformerTests.swift`, `ClipsmithTests/BezelViewModelTests.swift`.
- Create `ClipsmithTests/TransformRegistryTests.swift`.
- Modify `Clipsmith.xcodeproj/project.pbxproj`, `CHANGELOG.md`.

---

### Task 1: Case-conversion transforms

**Files:**
- Modify: `Clipsmith/Services/TextTransformer.swift` (after the `titleCase` function, ~line 28)
- Test: `ClipsmithTests/TextTransformerTests.swift` (append before closing brace)

**Interfaces:**
- Produces: `TextTransformer.camelCase/pascalCase/snakeCase/kebabCase(_ s: String) -> String` (used by Task 4 registry).

- [ ] **Step 1: Write the failing tests**

Append to `ClipsmithTests/TextTransformerTests.swift` before the final `}`:

```swift
    // MARK: - Case conversions (transform picker)

    func testCamelCase() {
        XCTAssertEqual(TextTransformer.camelCase("user name"), "userName")
        XCTAssertEqual(TextTransformer.camelCase("user_id"), "userId")
        XCTAssertEqual(TextTransformer.camelCase("some-long-name"), "someLongName")
        XCTAssertEqual(TextTransformer.camelCase("alreadyCamel"), "alreadyCamel")
    }

    func testPascalCase() {
        XCTAssertEqual(TextTransformer.pascalCase("user name"), "UserName")
        XCTAssertEqual(TextTransformer.pascalCase("user_id"), "UserId")
    }

    func testSnakeCase() {
        XCTAssertEqual(TextTransformer.snakeCase("user name"), "user_name")
        XCTAssertEqual(TextTransformer.snakeCase("userId"), "user_id")
        XCTAssertEqual(TextTransformer.snakeCase("some-long-name"), "some_long_name")
    }

    func testKebabCase() {
        XCTAssertEqual(TextTransformer.kebabCase("user name"), "user-name")
        XCTAssertEqual(TextTransformer.kebabCase("userId"), "user-id")
    }

    func testCaseConversionEmptyAndSymbolsOnly() {
        XCTAssertEqual(TextTransformer.snakeCase(""), "")
        XCTAssertEqual(TextTransformer.camelCase("!!!"), "!!!")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TextTransformerTests 2>&1 | tail -20`
Expected: BUILD FAILS with "Type 'TextTransformer' has no member 'camelCase'" (and the other three).

- [ ] **Step 3: Implement**

In `Clipsmith/Services/TextTransformer.swift`, after `titleCase` (before `// MARK: - Whitespace`):

```swift
    // MARK: - Identifier case conversions

    /// Splits a string into lowercase word tokens on whitespace, punctuation
    /// (`-`, `_`, etc.), and lower→Upper camelCase boundaries.
    ///
    /// Simple boundary rule only: "userId" → ["user", "id"]. Consecutive
    /// capitals are NOT split ("HTTPServer" → ["httpserver"]) — acceptable.
    private static func words(_ s: String) -> [String] {
        var separated = ""
        var prev: Character?
        for c in s {
            if let p = prev, c.isUppercase, (p.isLowercase || p.isNumber) {
                separated.append(" ")
            }
            separated.append(c)
            prev = c
        }
        return separated
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    /// Converts to camelCase. Returns input unchanged if it contains no words.
    static func camelCase(_ s: String) -> String {
        let w = words(s)
        guard let first = w.first else { return s }
        return first + w.dropFirst().map(\.capitalized).joined()
    }

    /// Converts to PascalCase. Returns input unchanged if it contains no words.
    static func pascalCase(_ s: String) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        return w.map(\.capitalized).joined()
    }

    /// Converts to snake_case. Returns input unchanged if it contains no words.
    static func snakeCase(_ s: String) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        return w.joined(separator: "_")
    }

    /// Converts to kebab-case. Returns input unchanged if it contains no words.
    static func kebabCase(_ s: String) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        return w.joined(separator: "-")
    }
```

Note: `snakeCase("")` returns `""` because `words("")` is empty → guard returns `s` (`""`). Matches the test.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TextTransformerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, all TextTransformerTests pass.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Services/TextTransformer.swift ClipsmithTests/TextTransformerTests.swift
git commit -m "feat(transforms): add camelCase/PascalCase/snake_case/kebab-case conversions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Line operations, slugify, escape/unescape

**Files:**
- Modify: `Clipsmith/Services/TextTransformer.swift` (new MARK sections before `// MARK: - RTF`)
- Test: `ClipsmithTests/TextTransformerTests.swift`

**Interfaces:**
- Produces: `TextTransformer.sortLines/dedupeLines/reverseLines/slugify/escape/unescape(_ s: String) -> String` (used by Task 4 registry).

- [ ] **Step 1: Write the failing tests**

Append to `ClipsmithTests/TextTransformerTests.swift` before the final `}`:

```swift
    // MARK: - Line operations (transform picker)

    func testSortLines() {
        XCTAssertEqual(TextTransformer.sortLines("banana\napple\ncherry"), "apple\nbanana\ncherry")
    }

    func testDedupeLines() {
        XCTAssertEqual(TextTransformer.dedupeLines("a\nb\na\nc\nb"), "a\nb\nc")
    }

    func testReverseLines() {
        XCTAssertEqual(TextTransformer.reverseLines("1\n2\n3"), "3\n2\n1")
    }

    // MARK: - Slugify

    func testSlugify() {
        XCTAssertEqual(TextTransformer.slugify("Hello World!"), "hello-world")
        XCTAssertEqual(TextTransformer.slugify("Čaučí, díky"), "cauci-diky")
    }

    // MARK: - Escape / Unescape

    func testEscape() {
        XCTAssertEqual(TextTransformer.escape("say \"hi\"\nnew line"), "say \\\"hi\\\"\\nnew line")
    }

    func testUnescapeRoundTrip() {
        let original = "say \"hi\"\nnew\tline \\ backslash"
        XCTAssertEqual(TextTransformer.unescape(TextTransformer.escape(original)), original)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TextTransformerTests 2>&1 | tail -20`
Expected: BUILD FAILS with "has no member 'sortLines'" etc.

- [ ] **Step 3: Implement**

In `TextTransformer.swift`, before `// MARK: - RTF`:

```swift
    // MARK: - Line operations

    /// Sorts lines alphabetically (ascending, case-sensitive).
    static func sortLines(_ s: String) -> String {
        s.components(separatedBy: "\n").sorted().joined(separator: "\n")
    }

    /// Removes duplicate lines, keeping the first occurrence and original order.
    static func dedupeLines(_ s: String) -> String {
        var seen = Set<String>()
        return s.components(separatedBy: "\n")
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }

    /// Reverses line order.
    static func reverseLines(_ s: String) -> String {
        s.components(separatedBy: "\n").reversed().joined(separator: "\n")
    }

    // MARK: - Slugify

    /// Converts to a lowercase URL slug: diacritics folded, non-alphanumerics
    /// collapsed into single hyphens.
    static func slugify(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    // MARK: - Escape / Unescape

    /// Escapes backslashes, double quotes, newlines, and tabs (C/JSON string style).
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Reverses `escape(_:)`. Replacement order matters: backslashes last so
    /// escaped sequences are not double-processed.
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TextTransformerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Services/TextTransformer.swift ClipsmithTests/TextTransformerTests.swift
git commit -m "feat(transforms): add line ops, slugify, escape/unescape

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Failable transforms (nil-on-failure semantics)

**Files:**
- Modify: `Clipsmith/Services/TextTransformer.swift` — `jsonPrettyPrint`/`urlDecode` become `String?`; add base64, JWT, timestamp, extract functions
- Modify: `Clipsmith/Views/BezelController.swift:482-483, 496-498` — temporary compile fix for the two changed signatures (fully replaced in Task 8)
- Test: `ClipsmithTests/TextTransformerTests.swift` — update 3 existing tests, add new ones

**Interfaces:**
- Produces (all used by Task 4 registry): `urlDecode`, `jsonPrettyPrint`, `base64Encode`, `base64Decode`, `jwtDecode`, `timestampToISO`, `isoToTimestamp`, `extractURLs`, `extractEmails` — each `(String) -> String?`.

- [ ] **Step 1: Update existing tests + write new failing tests**

In `ClipsmithTests/TextTransformerTests.swift`, replace `testUrlDecodeNonEncoded` (~line 47-50), `testJsonPrettyPrintValid` (~line 66-72), and `testJsonPrettyPrintInvalid` (~line 77-81) with:

```swift
    func testUrlDecodeNonEncoded() {
        XCTAssertEqual(TextTransformer.urlDecode("hello world"), "hello world")
    }

    func testUrlDecodeMalformedReturnsNil() {
        XCTAssertNil(TextTransformer.urlDecode("bad%zzencoding"))
    }

    func testJsonPrettyPrintValid() {
        let result = TextTransformer.jsonPrettyPrint("{\"key\":\"value\"}")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("\n") ?? false, "Pretty-printed JSON should contain newlines")
        XCTAssertTrue(result?.contains("key") ?? false)
    }

    func testJsonPrettyPrintInvalidReturnsNil() {
        XCTAssertNil(TextTransformer.jsonPrettyPrint("not valid json { at all"))
    }
```

Append new tests before the final `}`:

```swift
    // MARK: - Base64

    func testBase64RoundTrip() {
        XCTAssertEqual(TextTransformer.base64Encode("hello"), "aGVsbG8=")
        XCTAssertEqual(TextTransformer.base64Decode("aGVsbG8="), "hello")
    }

    func testBase64DecodeInvalidReturnsNil() {
        XCTAssertNil(TextTransformer.base64Decode("!!! not base64 !!!"))
    }

    // MARK: - JWT decode

    func testJwtDecode() {
        // {"alg":"HS256","typ":"JWT"} . {"sub":"1234567890","name":"John Doe"} . fake-sig
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0."
            + "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = TextTransformer.jwtDecode(jwt)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("HS256") ?? false, "Decoded JWT should contain header alg")
        XCTAssertTrue(result?.contains("John Doe") ?? false, "Decoded JWT should contain payload claim")
    }

    func testJwtDecodeInvalidReturnsNil() {
        XCTAssertNil(TextTransformer.jwtDecode("not.a-jwt"))
        XCTAssertNil(TextTransformer.jwtDecode("plain text"))
    }

    // MARK: - Timestamp conversions

    func testTimestampToISO() {
        XCTAssertEqual(TextTransformer.timestampToISO("0"), "1970-01-01T00:00:00Z")
        // Milliseconds heuristic: 13-digit values are treated as ms.
        XCTAssertEqual(TextTransformer.timestampToISO("1700000000000"),
                       TextTransformer.timestampToISO("1700000000"))
        XCTAssertNil(TextTransformer.timestampToISO("not a number"))
    }

    func testISOToTimestamp() {
        XCTAssertEqual(TextTransformer.isoToTimestamp("1970-01-01T00:00:00Z"), "0")
        XCTAssertEqual(TextTransformer.isoToTimestamp("2023-11-14T22:13:20Z"), "1700000000")
        XCTAssertNil(TextTransformer.isoToTimestamp("14.11.2023"))
    }

    // MARK: - Extract URLs / emails

    func testExtractURLs() {
        let text = "see https://example.com/docs and http://foo.bar, mail me at a@b.com"
        let result = TextTransformer.extractURLs(text)
        XCTAssertEqual(result, "https://example.com/docs\nhttp://foo.bar")
    }

    func testExtractURLsNoneReturnsNil() {
        XCTAssertNil(TextTransformer.extractURLs("no links here"))
    }

    func testExtractEmails() {
        let text = "contact adam@lablabs.io or support@example.com via https://example.com"
        let result = TextTransformer.extractEmails(text)
        XCTAssertEqual(result, "adam@lablabs.io\nsupport@example.com")
    }

    func testExtractEmailsNoneReturnsNil() {
        XCTAssertNil(TextTransformer.extractEmails("no emails here"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TextTransformerTests 2>&1 | tail -20`
Expected: BUILD FAILS ("has no member 'base64Encode'" etc.).

- [ ] **Step 3: Implement**

In `TextTransformer.swift`, replace `urlDecode` (~line 49-51):

```swift
    /// Decodes percent-encoded characters. Returns nil if the encoding is malformed.
    static func urlDecode(_ s: String) -> String? {
        s.removingPercentEncoding
    }
```

Replace `jsonPrettyPrint` (~line 68-81):

```swift
    /// Pretty-prints a JSON string with 2-space indentation.
    /// Returns nil if the input is not valid JSON.
    static func jsonPrettyPrint(_ s: String) -> String? {
        guard
            let data = s.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let result = String(data: pretty, encoding: .utf8)
        else {
            return nil
        }
        return result
    }
```

Add before `// MARK: - RTF`:

```swift
    // MARK: - Base64

    /// Base64-encodes the UTF-8 bytes of the string. Nil only if UTF-8 encoding fails.
    static func base64Encode(_ s: String) -> String? {
        s.data(using: .utf8)?.base64EncodedString()
    }

    /// Decodes a Base64 string to UTF-8 text. Returns nil for invalid Base64
    /// or non-UTF-8 payloads. Surrounding whitespace is tolerated.
    static func base64Decode(_ s: String) -> String? {
        guard
            let data = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    // MARK: - JWT

    /// Decodes a JWT's header and payload segments (base64url) and pretty-prints
    /// both as JSON, separated by a blank line. Returns nil for malformed tokens.
    /// Does NOT verify the signature — display only.
    static func jwtDecode(_ s: String) -> String? {
        let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        guard parts.count == 3 else { return nil }

        func decodeSegment(_ segment: String) -> String? {
            var b64 = segment
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while b64.count % 4 != 0 { b64 += "=" }
            guard
                let data = Data(base64Encoded: b64),
                let json = String(data: data, encoding: .utf8)
            else { return nil }
            return jsonPrettyPrint(json)
        }

        guard
            let header = decodeSegment(parts[0]),
            let payload = decodeSegment(parts[1])
        else { return nil }
        return header + "\n\n" + payload
    }

    // MARK: - Timestamps

    /// Converts a Unix timestamp (seconds, or milliseconds for 13+ digit values)
    /// to an ISO 8601 UTC string. Returns nil for non-numeric input.
    static func timestampToISO(_ s: String) -> String? {
        guard let value = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let seconds = value >= 1_000_000_000_000 ? value / 1000 : value
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }

    /// Converts an ISO 8601 date string to a Unix timestamp (seconds).
    /// Returns nil if the input does not parse as ISO 8601.
    static func isoToTimestamp(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return String(Int(date.timeIntervalSince1970))
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: trimmed) else { return nil }
        return String(Int(date.timeIntervalSince1970))
    }

    // MARK: - Extraction

    /// Extracts all non-mailto URLs, one per line. Returns nil when none found.
    static func extractURLs(_ s: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: s, range: NSRange(s.startIndex..., in: s))
        let urls = matches
            .compactMap { $0.url }
            .filter { $0.scheme != "mailto" }
            .map(\.absoluteString)
        return urls.isEmpty ? nil : urls.joined(separator: "\n")
    }

    /// Extracts all email addresses, one per line. Returns nil when none found.
    static func extractEmails(_ s: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: s, range: NSRange(s.startIndex..., in: s))
        let emails = matches
            .compactMap { $0.url }
            .filter { $0.scheme == "mailto" }
            .map { $0.absoluteString.replacingOccurrences(of: "mailto:", with: "") }
        return emails.isEmpty ? nil : emails.joined(separator: "\n")
    }
```

**Compile fix in `BezelController.swift`** (the two menu actions still call the old non-optional signatures; they are fully replaced in Task 8 — for now make them compile):

Replace `actionUrlDecode` (~line 482-484):

```swift
    @objc private func actionUrlDecode() {
        applyTransform { TextTransformer.urlDecode($0) ?? $0 }
    }
```

Replace `actionJsonPrettyPrint` (~line 496-498):

```swift
    @objc private func actionJsonPrettyPrint() {
        applyTransform { TextTransformer.jsonPrettyPrint($0) ?? $0 }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TextTransformerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Services/TextTransformer.swift Clipsmith/Views/BezelController.swift ClipsmithTests/TextTransformerTests.swift
git commit -m "feat(transforms): failable transforms — base64, JWT, timestamps, extract; nil-on-failure for jsonPrettyPrint/urlDecode

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: TransformRegistry

**Files:**
- Create: `Clipsmith/Services/TransformRegistry.swift`
- Create: `ClipsmithTests/TransformRegistryTests.swift`
- Modify: `Clipsmith.xcodeproj/project.pbxproj` (8 insertions — 4 per new file)

**Interfaces:**
- Consumes: all `TextTransformer` functions from Tasks 1-3.
- Produces: `struct TextTransform { let id: String; let displayName: String; let keywords: String; let failureMessage: String; let apply: @Sendable (String) -> String? }` (Identifiable, Sendable) and `enum TransformRegistry { static let all: [TextTransform]; static func transform(withID:) -> TextTransform? }`. Used by Tasks 5-9.

- [ ] **Step 1: Register both new files in pbxproj**

In `Clipsmith.xcodeproj/project.pbxproj` make 8 insertions, anchoring on existing lines:

1. After the line containing `AA0096 /* CommandPaletteService.swift in Sources */ = {isa = PBXBuildFile;` add:
```
		AA0101 /* TransformRegistry.swift in Sources */ = {isa = PBXBuildFile; fileRef = AF0101 /* TransformRegistry.swift */; };
		AA0102 /* TransformRegistryTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AF0102 /* TransformRegistryTests.swift */; };
```
2. After the line containing `AF0097 /* CommandPaletteService.swift */ = {isa = PBXFileReference;` add:
```
		AF0101 /* TransformRegistry.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TransformRegistry.swift; sourceTree = "<group>"; };
		AF0102 /* TransformRegistryTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TransformRegistryTests.swift; sourceTree = "<group>"; };
```
3. In the Services group children (find `AF0097 /* CommandPaletteService.swift */,` in a children list) add below it:
```
				AF0101 /* TransformRegistry.swift */,
```
4. In the ClipsmithTests group children (find `AF0059 /* TextTransformerTests.swift */,`) add below it:
```
				AF0102 /* TransformRegistryTests.swift */,
```
5. In the app target Sources build phase (find `AA0096 /* CommandPaletteService.swift in Sources */,`) add below it:
```
				AA0101 /* TransformRegistry.swift in Sources */,
```
6. In the test target Sources build phase (find `AA0058 /* TextTransformerTests.swift in Sources */,`) add below it:
```
				AA0102 /* TransformRegistryTests.swift in Sources */,
```

- [ ] **Step 2: Write the failing tests**

Create `ClipsmithTests/TransformRegistryTests.swift`:

```swift
import XCTest
@testable import Clipsmith

final class TransformRegistryTests: XCTestCase {

    // MARK: - Registry integrity

    func testAllIDsUnique() {
        let ids = TransformRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Transform ids must be unique")
    }

    func testRegistryContainsExpectedCount() {
        // 10 original-era transforms (minus copyAsRTF which is Data, not text,
        // so 9 make it into the registry) + 16 new + extraction = 26 total:
        // 7 case + 4 trim/lines + 6 encode/escape + 4 format + 3 dev + 2 extract.
        XCTAssertEqual(TransformRegistry.all.count, 26)
    }

    func testTransformWithID() {
        XCTAssertNotNil(TransformRegistry.transform(withID: "case.upper"))
        XCTAssertNil(TransformRegistry.transform(withID: "does.not.exist"))
    }

    func testApplyThroughRegistry() {
        let upper = TransformRegistry.transform(withID: "case.upper")
        XCTAssertEqual(upper?.apply("hi"), "HI")

        let json = TransformRegistry.transform(withID: "format.jsonpretty")
        XCTAssertNil(json?.apply("not json"), "Failable transform must surface nil through the registry")
        XCTAssertFalse(json?.failureMessage.isEmpty ?? true, "Failable transforms need a failure message")
    }

    // MARK: - Fuzzy discoverability

    func testKeywordsEnableFuzzyMatch() {
        // "b64" should match the Base64 transforms via keywords.
        let matches = TransformRegistry.all.filter {
            FuzzyMatcher.score($0.displayName + " " + $0.keywords, query: "b64") != nil
        }
        XCTAssertTrue(matches.contains { $0.id == "encode.base64" }, "b64 should match Base64 Encode")
        XCTAssertTrue(matches.contains { $0.id == "decode.base64" }, "b64 should match Base64 Decode")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TransformRegistryTests 2>&1 | tail -15`
Expected: BUILD FAILS ("Cannot find 'TransformRegistry' in scope").

- [ ] **Step 4: Implement**

Create `Clipsmith/Services/TransformRegistry.swift`:

```swift
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
```

Count sanity: 7 case + 4 trim/lines + 6 encode/escape + 4 format + 3 dev + 2 extract = 26, matching the test.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/TransformRegistryTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`, 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Clipsmith/Services/TransformRegistry.swift ClipsmithTests/TransformRegistryTests.swift Clipsmith.xcodeproj/project.pbxproj
git commit -m "feat(transforms): add TransformRegistry with 26 transform descriptors

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: BezelViewModel picker state

**Files:**
- Modify: `Clipsmith/Views/BezelViewModel.swift` (add after the `iconCache` property, ~line 70)
- Test: `ClipsmithTests/BezelViewModelTests.swift` (append)

**Interfaces:**
- Consumes: `TransformRegistry.all`, `TextTransform`, `FuzzyMatcher.score(_:query:)`.
- Produces (used by Tasks 7 and 9): `isShowingTransformPicker: Bool`, `transformFilterText: String`, `transformSelectedIndex: Int`, `transformError: String?`, `filteredTransforms: [TextTransform]`, `currentTransform: TextTransform?`, `transformNavigateUp()`, `transformNavigateDown()`, `resetTransformPicker()`.

- [ ] **Step 1: Write the failing tests**

Append to `ClipsmithTests/BezelViewModelTests.swift` before the final `}` (the file's existing tests are `@MainActor`; match that pattern — if the class is not `@MainActor`, wrap bodies in `await MainActor.run { }` the way neighboring tests do):

```swift
    // MARK: - Transform picker

    @MainActor
    func testTransformFilterFuzzyMatches() {
        let vm = BezelViewModel()
        vm.transformFilterText = "up"
        XCTAssertTrue(vm.filteredTransforms.contains { $0.id == "case.upper" })
        XCTAssertFalse(vm.filteredTransforms.contains { $0.id == "lines.sort" })
    }

    @MainActor
    func testTransformFilterEmptyShowsAll() {
        let vm = BezelViewModel()
        vm.transformFilterText = ""
        XCTAssertEqual(vm.filteredTransforms.count, TransformRegistry.all.count)
    }

    @MainActor
    func testTransformFilterResetsSelectionAndError() {
        let vm = BezelViewModel()
        vm.transformSelectedIndex = 3
        vm.transformError = "Not valid JSON"
        vm.transformFilterText = "case"
        XCTAssertEqual(vm.transformSelectedIndex, 0)
        XCTAssertNil(vm.transformError)
    }

    @MainActor
    func testTransformNavigationClamps() {
        let vm = BezelViewModel()
        vm.transformNavigateUp()
        XCTAssertEqual(vm.transformSelectedIndex, 0, "Up at top must clamp at 0")
        for _ in 0..<1000 { vm.transformNavigateDown() }
        XCTAssertEqual(vm.transformSelectedIndex, vm.filteredTransforms.count - 1, "Down must clamp at last")
    }

    @MainActor
    func testCurrentTransform() {
        let vm = BezelViewModel()
        vm.transformFilterText = "b64"
        XCTAssertNotNil(vm.currentTransform)
        vm.transformFilterText = "zzzzzzqqqq"
        XCTAssertTrue(vm.filteredTransforms.isEmpty)
        XCTAssertNil(vm.currentTransform)
    }

    @MainActor
    func testResetTransformPicker() {
        let vm = BezelViewModel()
        vm.isShowingTransformPicker = true
        vm.transformFilterText = "json"
        vm.transformSelectedIndex = 0
        vm.transformError = "x"
        vm.resetTransformPicker()
        XCTAssertFalse(vm.isShowingTransformPicker)
        XCTAssertEqual(vm.transformFilterText, "")
        XCTAssertEqual(vm.transformSelectedIndex, 0)
        XCTAssertNil(vm.transformError)
        XCTAssertEqual(vm.filteredTransforms.count, TransformRegistry.all.count)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/BezelViewModelTests 2>&1 | tail -15`
Expected: BUILD FAILS ("has no member 'transformFilterText'" etc.).

- [ ] **Step 3: Implement**

In `BezelViewModel.swift`, after the `iconCache` property (~line 70):

```swift
    // MARK: - Transform picker state

    /// Whether the transform picker overlay is visible. Toggled by Tab.
    var isShowingTransformPicker: Bool = false

    /// Filter text typed while the picker is open. Managed by BezelController
    /// key routing (the overlay has no TextField — the non-activating panel
    /// routes raw keys). Setting it resets selection and clears any error.
    var transformFilterText: String = "" {
        didSet {
            transformSelectedIndex = 0
            transformError = nil
            recomputeFilteredTransforms()
        }
    }

    /// Selection index within filteredTransforms.
    var transformSelectedIndex: Int = 0

    /// Failure message shown inline when the selected transform returns nil.
    var transformError: String? = nil

    /// Transforms matching transformFilterText, ranked by fuzzy score.
    private(set) var filteredTransforms: [TextTransform] = TransformRegistry.all

    /// The transform at transformSelectedIndex, or nil when the list is empty.
    var currentTransform: TextTransform? {
        let filtered = filteredTransforms
        guard !filtered.isEmpty, transformSelectedIndex >= 0, transformSelectedIndex < filtered.count else { return nil }
        return filtered[transformSelectedIndex]
    }

    /// Recomputes filteredTransforms — mirrors recomputeFilteredClippings().
    private func recomputeFilteredTransforms() {
        guard !transformFilterText.isEmpty else {
            filteredTransforms = TransformRegistry.all
            return
        }
        let q = transformFilterText
        let scored: [(TextTransform, Double)] = TransformRegistry.all.compactMap { t in
            guard let s = FuzzyMatcher.score(t.displayName + " " + t.keywords, query: q) else { return nil }
            return (t, s)
        }
        filteredTransforms = scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Moves picker selection up one, clamped at 0.
    func transformNavigateUp() {
        transformSelectedIndex = max(0, transformSelectedIndex - 1)
    }

    /// Moves picker selection down one, clamped at the last index.
    func transformNavigateDown() {
        transformSelectedIndex = min(max(0, filteredTransforms.count - 1), transformSelectedIndex + 1)
    }

    /// Closes the picker and resets all its state. Called on hide() and Escape.
    func resetTransformPicker() {
        isShowingTransformPicker = false
        transformFilterText = ""
        transformSelectedIndex = 0
        transformError = nil
        filteredTransforms = TransformRegistry.all
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/BezelViewModelTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **` — all existing + 6 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Views/BezelViewModel.swift ClipsmithTests/BezelViewModelTests.swift
git commit -m "feat(bezel): transform picker state and fuzzy filtering in BezelViewModel

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Parameterize pasteAndHide(content:)

**Files:**
- Modify: `Clipsmith/Views/BezelController.swift:607-635`

**Interfaces:**
- Produces: `func pasteAndHide(content: String?) async` — used by Task 7. Existing `pasteAndHide()` keeps its signature and behavior (all current call sites unchanged).

- [ ] **Step 1: Refactor**

Replace the existing `pasteAndHide()` (~line 607-635) with:

```swift
    func pasteAndHide() async {
        await pasteAndHide(content: viewModel.currentClipping)
    }

    /// Pastes the given content and hides the bezel.
    ///
    /// Follows the original Flycut timing pattern:
    ///   1. Write content to pasteboard immediately
    ///   2. Hide the bezel immediately (so it's gone before Cmd-V fires)
    ///   3. Cmd-V is injected ~0.5s later via performSelector:afterDelay:
    ///
    /// The bezel MUST be hidden before the synthetic Cmd-V is posted — otherwise
    /// the panel (canBecomeKey) can intercept the keystroke.
    func pasteAndHide(content: String?) async {
        // If the bezel was already dismissed (e.g. user pressed Escape after modifier
        // release but before this Task ran), skip the paste entirely.
        logger.info("pasteAndHide() entered — isVisible=\(self.isVisible) isHotkeyHold=\(self.isHotkeyHold)")
        guard isVisible else {
            logger.info("pasteAndHide() skipped — bezel not visible")
            return
        }
        guard let content else {
            hide()
            return
        }
        // NEVER log clipping content — privacy requirement
        logger.info("Pasting selected clipping")

        // 1. Write to pasteboard and schedule delayed Cmd-V (fires in 0.5s).
        pasteService?.paste(content: content, into: appTracker?.previousApp)

        // 2. Hide the bezel IMMEDIATELY — before any await suspension points.
        //    This must happen before moveToTop() because during the await, other
        //    event monitors (click-outside, flags) could fire hide(cancelPaste: true)
        //    and cancel the pending Cmd-V injection.
        hide(cancelPaste: false)

        // 3. Bug #23: move pasted clipping to top of history when pasteMovesToTop is enabled.
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.pasteMovesToTop) {
            try? await clipboardStore?.moveToTop(content: content)
        }
    }
```

(The body is byte-identical to the old one except `viewModel.currentClipping` becomes the `content` parameter.)

- [ ] **Step 2: Run existing controller + view model tests to verify no regression**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/BezelControllerTests -only-testing:ClipsmithTests/BezelViewModelTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Clipsmith/Views/BezelController.swift
git commit -m "refactor(bezel): parameterize pasteAndHide(content:) for transform-and-paste

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Picker keyboard routing in BezelController

**Files:**
- Modify: `Clipsmith/Views/BezelController.swift` — `sendEvent` (~line 137-160), `keyDown` (~line 225), `hide` (~line 207-221), new methods
- Test: `ClipsmithTests/BezelControllerTests.swift` (append)

**Interfaces:**
- Consumes: view model state from Task 5, `pasteAndHide(content:)` from Task 6, `TransformRegistry` from Task 4.
- Produces: `func toggleTransformPicker()`, `func handleTransformPickerKey(_ event: NSEvent)`, `func applyTransformAndPaste(_ transform: TextTransform) async` — all `internal` (not private) so tests and Task 8's menu actions can call them.

- [ ] **Step 1: Write the failing tests**

`ClipsmithTests/BezelControllerTests.swift` is already `@MainActor` at class level and needs SwiftData imports for the helper. Add `import SwiftData` at the top of the file (below `import AppKit`), then append before the final `}`:

```swift
    // MARK: - Transform picker helpers

    /// Builds a controller whose view model holds one real clipping.
    /// ClippingInfo needs a valid PersistentIdentifier — obtained via an
    /// in-memory container (same "Option A" pattern as BezelViewModelTests).
    private func makeControllerWithClipping(_ content: String = "hello world") throws -> BezelController {
        let container = try makeTestContainer()
        let context = container.mainContext
        let clipping = ClipsmithSchemaV1.Clipping(content: content)
        context.insert(clipping)
        try context.save()

        let controller = BezelController()
        controller.viewModel.clippings = [
            ClippingInfo(
                id: clipping.persistentModelID,
                content: content,
                sourceAppName: nil,
                sourceAppBundleURL: nil,
                timestamp: clipping.timestamp
            )
        ]
        return controller
    }

    /// Builds a synthetic keyDown NSEvent for routing tests.
    private func makeKeyEvent(characters: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    // MARK: - Transform picker

    func testTabTogglesTransformPicker() throws {
        let controller = try makeControllerWithClipping()
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
        controller.toggleTransformPicker()
        XCTAssertTrue(controller.viewModel.isShowingTransformPicker)
        controller.toggleTransformPicker()
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
    }

    func testTransformPickerNoOpWithoutClipping() {
        let controller = BezelController()   // no clippings
        controller.toggleTransformPicker()
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
    }

    func testPickerKeyRoutingFilterAndNavigation() throws {
        let controller = try makeControllerWithClipping()
        controller.toggleTransformPicker()

        // j with empty filter navigates down.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "j", keyCode: 38))
        XCTAssertEqual(controller.viewModel.transformSelectedIndex, 1)

        // First typed letter starts the filter and resets selection.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "b", keyCode: 11))
        XCTAssertEqual(controller.viewModel.transformFilterText, "b")
        XCTAssertEqual(controller.viewModel.transformSelectedIndex, 0)

        // With a non-empty filter, j is filter text — not navigation.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "j", keyCode: 38))
        XCTAssertEqual(controller.viewModel.transformFilterText, "bj")

        // Backspace edits the filter.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "\u{7F}", keyCode: 51))
        XCTAssertEqual(controller.viewModel.transformFilterText, "b")
    }

    func testPickerEscapeClosesPickerOnly() throws {
        let controller = try makeControllerWithClipping()
        controller.toggleTransformPicker()
        controller.handleTransformPickerKey(makeKeyEvent(characters: "\u{1B}", keyCode: 53))
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
    }

    func testPickerEnterOnFailableTransformShowsErrorAndStaysOpen() async throws {
        let controller = try makeControllerWithClipping("not valid json { at all")
        controller.toggleTransformPicker()
        // Filter down to JSON Pretty Print deterministically.
        controller.viewModel.transformFilterText = "json pretty"
        guard let transform = controller.viewModel.currentTransform, transform.id == "format.jsonpretty" else {
            return XCTFail("Expected format.jsonpretty as top match")
        }
        // Await the apply path directly (Enter routing spawns the same call in a Task).
        await controller.applyTransformAndPaste(transform)
        XCTAssertEqual(controller.viewModel.transformError, "Not valid JSON")
        XCTAssertTrue(controller.viewModel.isShowingTransformPicker, "Picker stays open on failure")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/BezelControllerTests 2>&1 | tail -15`
Expected: BUILD FAILS ("has no member 'toggleTransformPicker'").

- [ ] **Step 3: Implement routing**

In `BezelController.swift`:

**(a)** In `sendEvent` (~line 137), insert BEFORE the existing `switch event.keyCode`:

```swift
        if event.type == .keyDown {
            // Transform picker intercepts ALL keys — including printable characters
            // that would otherwise reach the search TextField.
            if viewModel.isShowingTransformPicker {
                handleTransformPickerKey(event)
                return
            }
            switch event.keyCode {
            ...
```

**(b)** In the same `switch`, change case 48 (Tab):

```swift
            case 48:                            // Tab — toggle transform picker
                toggleTransformPicker()
                return
```

**(c)** In `hide()` (~line 214, alongside the other viewModel resets) add:

```swift
        viewModel.resetTransformPicker()
```

**(d)** Add new methods after `showQuickActionMenu` (~line 429):

```swift
    // MARK: - Transform picker (Tab)

    /// Toggles the transform picker overlay. No-op when there is no clipping
    /// to transform (same guard as the quick action menu).
    func toggleTransformPicker() {
        guard viewModel.currentClipping != nil else { return }
        if viewModel.isShowingTransformPicker {
            viewModel.resetTransformPicker()
        } else {
            viewModel.isShowingTransformPicker = true
        }
    }

    /// Routes a keyDown event while the picker is open.
    /// Filter text is managed here directly — the overlay has no TextField
    /// (focus juggling in a non-activating panel is unreliable; raw key
    /// routing matches how the rest of the bezel works).
    func handleTransformPickerKey(_ event: NSEvent) {
        switch event.keyCode {
        case 53:                        // Escape — close picker only
            viewModel.resetTransformPicker()
        case 48:                        // Tab — toggle closed
            viewModel.resetTransformPicker()
        case 36, 76:                    // Return, Enter — apply + paste
            if let transform = viewModel.currentTransform {
                Task { @MainActor in await self.applyTransformAndPaste(transform) }
            }
        case 125:                       // Down arrow
            viewModel.transformNavigateDown()
        case 126:                       // Up arrow
            viewModel.transformNavigateUp()
        case 51:                        // Backspace — edit filter
            if !viewModel.transformFilterText.isEmpty {
                viewModel.transformFilterText.removeLast()
            }
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            // j/k navigate only while the filter is empty — once the user types,
            // every letter belongs to the filter.
            if viewModel.transformFilterText.isEmpty, chars == "j" {
                viewModel.transformNavigateDown()
            } else if viewModel.transformFilterText.isEmpty, chars == "k" {
                viewModel.transformNavigateUp()
            } else if let typed = event.characters,
                      !typed.isEmpty,
                      !event.modifierFlags.contains(.command),
                      typed.rangeOfCharacter(from: .controlCharacters) == nil {
                viewModel.transformFilterText += typed
            }
        }
    }

    /// Applies a transform to the current clipping and pastes the result.
    /// On failure (nil result) shows the transform's failure message inline
    /// and keeps the picker open. On success, inserts the transformed content
    /// into history and pastes via the shared paste path.
    func applyTransformAndPaste(_ transform: TextTransform) async {
        guard let content = viewModel.currentClipping else { return }
        guard let result = transform.apply(content) else {
            viewModel.transformError = transform.failureMessage
            return
        }

        // Insert transformed content into history with "Clipsmith (transformed)" source.
        let rememberNum = UserDefaults.standard.integer(forKey: AppSettingsKeys.rememberNum)
        Task {
            try? await clipboardStore?.insert(
                content: result,
                sourceAppName: "Clipsmith (transformed)",
                rememberNum: rememberNum
            )
        }

        await pasteAndHide(content: result)
        logger.info("Applied transform \(transform.id, privacy: .public) and pasted")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/BezelControllerTests -only-testing:ClipsmithTests/BezelViewModelTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Clipsmith/Views/BezelController.swift ClipsmithTests/BezelControllerTests.swift
git commit -m "feat(bezel): Tab opens transform picker; keyboard routing and transform-and-paste

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Rebuild quick-action menu from registry

**Files:**
- Modify: `Clipsmith/Views/BezelController.swift` — `showQuickActionMenu` (~line 351-429), delete `applyTransform` and the 9 `@objc action*` transform/format methods (~line 431-498). Keep `actionCopyAsRTF` and `actionShareAsGist`.

**Interfaces:**
- Consumes: `TransformRegistry.all`, `applyTransformAndPaste(_:)` from Task 7.
- Produces: right-click menu behavior — every transform item now transform-and-pastes.

- [ ] **Step 1: Replace menu construction**

In `showQuickActionMenu`, replace the Transform and Format submenu blocks (from `// MARK: Transform submenu (QACT-01)` through the `menu.addItem(formatParent)` line) with:

```swift
        // MARK: Transform submenu — built from TransformRegistry (QACT-01, QACT-02)
        let transformMenu = NSMenu(title: "Transform")
        for transform in TransformRegistry.all {
            let item = NSMenuItem(title: transform.displayName, action: #selector(actionMenuTransform(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = transform.id
            transformMenu.addItem(item)
        }
        let transformParent = NSMenuItem(title: "Transform", action: nil, keyEquivalent: "")
        transformParent.submenu = transformMenu
        menu.addItem(transformParent)
```

(The Share submenu block stays untouched.)

- [ ] **Step 2: Replace action handlers**

Delete `applyTransform(_:)` and the `@objc` methods `actionUppercase`, `actionLowercase`, `actionTitleCase`, `actionTrimWhitespace`, `actionUrlEncode`, `actionUrlDecode`, `actionWrapInQuotes`, `actionMarkdownCodeBlock`, `actionJsonPrettyPrint` (~line 431-498). Add in their place:

```swift
    // MARK: - Transform menu action

    /// Shared handler for all registry-built menu items. The transform id
    /// travels in representedObject. Applies transform-and-paste — same path
    /// as the picker. On failure, beeps (no overlay is visible from the menu).
    @objc private func actionMenuTransform(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? String,
            let transform = TransformRegistry.transform(withID: id)
        else { return }
        guard let content = viewModel.currentClipping, transform.apply(content) != nil else {
            NSSound.beep()
            return
        }
        Task { @MainActor in await self.applyTransformAndPaste(transform) }
    }
```

- [ ] **Step 3: Build and run full bezel test suites**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/BezelControllerTests -only-testing:ClipsmithTests/BezelViewModelTests -only-testing:ClipsmithTests/TextTransformerTests -only-testing:ClipsmithTests/TransformRegistryTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`. Also confirm the deleted methods have no remaining references: `grep -n "applyTransform(\|actionUppercase\|actionJsonPrettyPrint" Clipsmith/Views/BezelController.swift` → only `applyTransformAndPaste` hits.

- [ ] **Step 4: Commit**

```bash
git add Clipsmith/Views/BezelController.swift
git commit -m "refactor(bezel): build quick-action menu from TransformRegistry; menu items now transform-and-paste

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Overlay UI, footer hint, cheat sheet

**Files:**
- Modify: `Clipsmith/Views/BezelView.swift` — overlay (~line 89-93), footer (~line 66-73), cheat sheet (~line 192-201), new subviews

**Interfaces:**
- Consumes: all view model picker state from Task 5.

- [ ] **Step 1: Add the overlay to the view body**

Replace the `.overlay { ... }` block (~line 89-93) with:

```swift
        .overlay {
            if viewModel.isShowingTransformPicker {
                transformPickerOverlay
            } else if viewModel.isShowingCheatSheet {
                cheatSheetOverlay
            }
        }
```

- [ ] **Step 2: Add the footer hint**

In the footer HStack (~line 66-73), before `Spacer()`:

```swift
                Text("⇥ transform")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 16)
```

- [ ] **Step 3: Update the cheat sheet**

In `cheatSheetOverlay`'s Actions section (~line 196), replace the row `("Tab  or  Right-click", "Quick actions menu"),` with:

```swift
                        ("Tab", "Transform picker"),
                        ("Right-click", "Quick actions menu"),
```

- [ ] **Step 4: Add the overlay subview**

Add after `cheatSheetOverlay` (~line 218):

```swift
    // MARK: - Transform picker overlay

    private var transformPickerOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)

            VStack(spacing: 0) {
                // Filter line — no TextField; BezelController routes raw keys
                // into viewModel.transformFilterText.
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Text(viewModel.transformFilterText.isEmpty
                         ? "Type to filter transforms…"
                         : viewModel.transformFilterText)
                        .foregroundStyle(viewModel.transformFilterText.isEmpty ? .secondary : .primary)
                    Spacer()
                }
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                if let error = viewModel.transformError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    Divider()
                }

                if viewModel.filteredTransforms.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.filteredTransforms.enumerated()), id: \.element.id) { index, transform in
                                    transformRow(transform, isSelected: index == viewModel.transformSelectedIndex)
                                        .id(transform.id)
                                }
                            }
                        }
                        .onChange(of: viewModel.transformSelectedIndex) {
                            if let current = viewModel.currentTransform {
                                proxy.scrollTo(current.id, anchor: .center)
                            }
                        }
                    }
                }

                Divider()

                Text("↑↓ navigate · ⏎ transform & paste · esc close")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func transformRow(_ transform: TextTransform, isSelected: Bool) -> some View {
        HStack {
            Text(transform.displayName)
                .font(.body)
            Spacer()
            Text(transformPreview(transform))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }

    /// One-line preview of the transform applied to (a 200-char sample of)
    /// the current clipping. "—" when the transform does not apply.
    private func transformPreview(_ transform: TextTransform) -> String {
        guard let content = viewModel.currentClipping else { return "" }
        let sample = String(content.prefix(200))
        guard let result = transform.apply(sample) else { return "—" }
        return String(result.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(60))
    }
```

- [ ] **Step 5: Build and verify manually**

Run: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

Manual verification checklist (launch the app, copy some text, press the bezel hotkey):
1. Tab opens the picker; footer shows "⇥ transform".
2. Typing filters the list ("b64" finds Base64); selection highlight follows ↑↓ and j/k.
3. Enter on UPPERCASE pastes the uppercased text into the previous app and closes the bezel.
4. Enter on "JSON Pretty Print" with non-JSON clipping shows "Not valid JSON" inline; picker stays open; Escape closes only the picker.
5. Right-click → Transform → item pastes transformed text.
6. `?` cheat sheet lists Tab = Transform picker.

- [ ] **Step 6: Commit**

```bash
git add Clipsmith/Views/BezelView.swift
git commit -m "feat(bezel): transform picker overlay UI with live previews and inline errors

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Changelog + full suite

**Files:**
- Modify: `CHANGELOG.md` (Unreleased section)

- [ ] **Step 1: Add changelog entries**

Under `## [Unreleased]`, add to the existing `### Changed` section's sibling `### Added` (create `### Added` above `### Changed` if absent):

```markdown
### Added
- **Transform picker in the clipboard bezel** — press Tab in the Cmd-Shift-V bezel to fuzzy-search 26 text transforms and apply-and-paste in one motion; failable transforms (JSON, Base64, JWT…) show an inline error instead of pasting
- 16 new text transforms: camelCase/PascalCase/snake_case/kebab-case, Base64 encode/decode, sort/dedupe/reverse lines, extract URLs/emails, JWT decode, Unix timestamp ↔ ISO 8601, slugify, escape/unescape

### Changed
- Right-click quick-action menu transforms now paste the transformed result immediately (previously required a second Enter)
```

- [ ] **Step 2: Run the FULL test suite**

Run: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' 2>&1 | grep -E "Test Suite '.*' (passed|failed)|TEST" | tail -10`
Expected: `** TEST SUCCEEDED **`, no failed suites.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entries for bezel transform picker

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- Spec coverage: registry (T4), transform pack (T1-3), nil-on-failure (T3/T4), overlay + previews (T9), keyboard routing incl. Escape-closes-picker-only and j/k-when-filter-empty (T7), pasteAndHide(content:) parameterization (T6), menu stays but pastes (T8), history insertion as "Clipsmith (transformed)" (T7), footer hint + cheat sheet (T9), out-of-scope items untouched. ✓
- Type consistency: `TextTransform` fields (`id/displayName/keywords/failureMessage/apply`) used identically in T4/T5/T7/T9; `pasteAndHide(content:)` defined T6, used T7. ✓
- Known judgment calls for the implementer: Task 7's test helper MUST reuse the existing container-based `ClippingInfo` construction from `BezelViewModelTests` (the inline placeholder is marked); Task 4's count test is 26 (the prose earlier in the task walks through why).
