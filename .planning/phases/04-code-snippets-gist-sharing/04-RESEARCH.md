# Phase 4: Code Snippets & Gist Sharing - Research

**Researched:** 2026-03-09
**Domain:** SwiftUI/SwiftData snippet management, syntax highlighting (HighlightSwift), GitHub Gist REST API v3, macOS Keychain, activation-policy window management
**Confidence:** HIGH (stack fully verified via GitHub source and official docs)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SNIP-01 | User can create named code snippets with a dedicated editor | SnippetStore @ModelActor + WindowGroup snippet editor |
| SNIP-02 | Snippet editor provides syntax highlighting for common languages | HighlightSwift 1.1.0 — CodeText SwiftUI view, 50+ languages |
| SNIP-03 | User can organize snippets by category/language | Snippet @Model has language + category fields; #Predicate filter |
| SNIP-04 | User can search snippets by name, content, or category | #Predicate with localizedStandardContains across three fields |
| SNIP-05 | User can paste a snippet into frontmost app via same paste mechanism | Existing PasteService.paste() reused directly |
| GIST-01 | User can share any clipping or snippet as a GitHub Gist | GistService actor — POST https://api.github.com/gists |
| GIST-02 | User can authenticate with GitHub via Personal Access Token stored in Keychain | TokenStore wrapper — SecItemAdd / SecItemCopyMatching |
| GIST-03 | User can choose public or private gist when sharing | `"public": Bool` field in Gist API request body |
| GIST-04 | Gist URL is copied to clipboard after creation | response.html_url → NSPasteboard.general |
| GIST-05 | User can view history of previously created gists | GistRecord @Model + @Query in GistHistoryView |
</phase_requirements>

---

## Summary

Phase 4 adds two closely related features to the existing SwiftUI/SwiftData app: a code snippet editor with syntax highlighting, and GitHub Gist sharing for both clippings and snippets. The data models (Snippet, GistRecord) are already defined in FlycutSchemaV1. The paste mechanism (PasteService) is fully reusable. The primary new work is (a) UI — a dedicated WindowGroup snippet editor, (b) syntax highlighting via HighlightSwift, (c) a GistService actor wrapping the GitHub REST API, and (d) Keychain storage for the Personal Access Token.

HighlightSwift 1.1.0 is the correct choice: it explicitly declares Swift 6 full concurrency support, offers a native SwiftUI `CodeText` view, and requires macOS 13+. The original Highlightr library is no longer maintained (as of 2026); HighlighterSwift 3.0.0 is an option but does not explicitly declare Swift 6 language mode. HighlightSwift's `enableExperimentalFeature("StrictConcurrency")` matches this project's Swift 6 mode.

The GitHub Gist API is simple REST: one `POST /gists` call with a JSON body, returning `id` and `html_url`. No OAuth dance is needed — a Personal Access Token in the `Authorization: Bearer` header is sufficient. Token storage uses raw Security framework calls (no SPM dependency needed) because the app is not sandboxed and the keychain queries are straightforward.

Opening the snippet editor from a menu bar app requires a temporary activation-policy switch (.accessory → .regular → .accessory) with a ~100 ms delay, following the same pattern already established for the Settings scene.

**Primary recommendation:** Use HighlightSwift for syntax highlighting, a dedicated WindowGroup for the snippet editor, raw Keychain APIs for PAT storage, and a GistService @MainActor for the Gist REST calls. All five Snippet and five Gist requirements are achievable in two to three plans.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| HighlightSwift | 1.1.0 | Syntax highlighting in SwiftUI | Swift 6 compatible, native `CodeText` SwiftUI view, 50+ languages, 30 themes, highlight.js 11.9 |
| SwiftData (built-in) | macOS 14+ | Snippet + GistRecord persistence | Already in use; Snippet and GistRecord @Models already defined in FlycutSchemaV1 |
| Security.framework (built-in) | macOS system | Keychain PAT storage | No external dependency; non-sandboxed app can use SecItem APIs directly |
| Foundation.URLSession (built-in) | macOS system | GitHub Gist REST calls | async/await `data(for:)` API is Swift 6 clean; no networking library needed |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| KeyboardShortcuts | 2.4.0 | Already pinned | Only if a new hotkey is added for snippet access |
| AppKit.NSTextView | system | Editable code input in snippet editor | HighlightSwift's `CodeText` is read-only display; the editor input field is a plain SwiftUI TextEditor or thin NSViewRepresentable |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| HighlightSwift | HighlighterSwift 3.0.0 | HighlighterSwift does not explicitly declare swift language mode .v6; its Package.swift specifies tools 5.9 with no swiftLanguageVersions. HighlightSwift enables StrictConcurrency experimental feature — better fit. |
| HighlightSwift | raspu/Highlightr | Abandoned (no longer maintained per maintainer note 2026); uses highlight.js 9.13 (outdated, security concerns). Do not use. |
| HighlightSwift | CodeEditorView (mchakravarty) | Requires macOS 14, is pre-release quality with known bugs. Overkill for a read-only code preview + separate editable field. |
| Raw Security.framework | KeychainAccess SPM | KeychainAccess Package.swift targets Swift 5.0 tools, no Swift 6 mode, adds a linker flag `-no_application_extension`. Unnecessary complexity for storing one string. |
| URLSession direct | Alamofire / Moya | No HTTP library needed for one API endpoint. Adding a large networking framework for a single POST call is over-engineering. |

**Installation:**
```bash
# Add HighlightSwift via Xcode: File > Add Package Dependencies
# URL: https://github.com/appstefan/highlightswift
# Version: 1.1.0 (exact) or Up to Next Minor
```

---

## Architecture Patterns

### Recommended Project Structure

```
FlycutSwift/
├── Models/
│   └── Schema/
│       └── FlycutSchemaV1.swift        # EXISTING — Snippet + GistRecord already here
├── Services/
│   ├── SnippetStore.swift              # NEW — @ModelActor CRUD for Snippet
│   ├── GistService.swift               # NEW — @MainActor, URLSession, Keychain
│   └── TokenStore.swift                # NEW — thin Keychain wrapper (save/load/delete PAT)
└── Views/
    ├── Snippets/
    │   ├── SnippetListView.swift        # NEW — list + search, opens editor sheet
    │   ├── SnippetEditorView.swift      # NEW — name, language, category, TextEditor, CodeText preview
    │   └── SnippetRowView.swift         # NEW — single row with paste + gist buttons
    ├── Gists/
    │   ├── GistShareSheet.swift         # NEW — public/private toggle, confirm share
    │   └── GistHistoryView.swift        # NEW — @Query GistRecord list
    └── Settings/
        └── GistSettingsSection.swift    # NEW — PAT entry field (SecureField), save/clear
```

### Pattern 1: SnippetStore as @ModelActor

**What:** Mirror the ClipboardStore pattern. @ModelActor provides background Swift Data access for insert, fetch, delete, update operations on `FlycutSchemaV1.Snippet`.

**When to use:** All SwiftData writes for Snippet. @Query in SwiftUI views handles reads reactively.

**Example:**
```swift
// Source: established ClipboardStore pattern in this codebase
@ModelActor
actor SnippetStore {
    func insert(name: String, content: String, language: String?, category: String?) throws {
        let snippet = FlycutSchemaV1.Snippet(
            name: name, content: content, language: language, category: category
        )
        modelContext.insert(snippet)
        try modelContext.save()
    }

    func delete(id: PersistentIdentifier) throws {
        guard let snippet = modelContext.model(for: id) as? FlycutSchemaV1.Snippet else { return }
        modelContext.delete(snippet)
        try modelContext.save()
    }

    func update(id: PersistentIdentifier, name: String, content: String,
                language: String?, category: String?) throws {
        guard let snippet = modelContext.model(for: id) as? FlycutSchemaV1.Snippet else { return }
        snippet.name = name
        snippet.content = content
        snippet.language = language
        snippet.category = category
        snippet.updatedAt = .now
        try modelContext.save()
    }
}
```

### Pattern 2: GistService as @MainActor

**What:** @MainActor service (not @ModelActor) because it writes to both the Keychain (synchronous) and GistRecord (needs modelContext). URLSession async/await for the Gist API call, Codable structs for request/response.

**When to use:** All GitHub Gist API interactions and GistRecord persistence.

**Example:**
```swift
// Source: GitHub REST API docs + URLSession async/await pattern
@MainActor
final class GistService {
    private let modelContext: ModelContext
    private let tokenStore = TokenStore()

    struct CreateGistRequest: Encodable {
        let description: String
        let `public`: Bool
        let files: [String: FileContent]

        struct FileContent: Encodable {
            let content: String
        }
    }

    struct GistResponse: Decodable {
        let id: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case id
            case htmlURL = "html_url"
        }
    }

    func createGist(
        filename: String,
        content: String,
        description: String,
        isPublic: Bool
    ) async throws -> GistResponse {
        guard let token = tokenStore.loadToken() else {
            throw GistError.noToken
        }
        let body = CreateGistRequest(
            description: description,
            public: isPublic,
            files: [filename: .init(content: content)]
        )
        var request = URLRequest(url: URL(string: "https://api.github.com/gists")!)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw GistError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(GistResponse.self, from: data)
    }
}
```

### Pattern 3: TokenStore — Raw Keychain

**What:** A non-actor struct (all methods are synchronous) that wraps SecItemAdd / SecItemCopyMatching / SecItemDelete for storing the GitHub PAT. No SPM dependency.

**When to use:** Save token on settings save, load token before Gist API call, delete on clear.

**Example:**
```swift
// Source: Apple Security framework — SecItemAdd / SecItemCopyMatching
struct TokenStore {
    private let service = "com.generalarcade.flycut.github-pat"
    private let account = "github-personal-access-token"

    func saveToken(_ token: String) {
        deleteToken() // Remove existing before adding
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: Data(token.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    func deleteToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### Pattern 4: HighlightSwift CodeText for Read-Only Preview

**What:** Use `CodeText` for the syntax-highlighted preview pane. The editable input is a standard SwiftUI `TextEditor` (or a thin NSTextView wrapper). Two-pane layout: TextEditor on left/top, CodeText preview on right/bottom.

**When to use:** Snippet editor view, snippet list row preview.

**Example:**
```swift
// Source: HighlightSwift README — https://github.com/appstefan/HighlightSwift
import HighlightSwift

struct SnippetEditorView: View {
    @State var code: String = ""
    @State var language: String = "swift"

    var body: some View {
        HSplitView {
            // Editable side
            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 300)

            // Read-only highlighted preview
            ScrollView {
                CodeText(code)
                    .highlightLanguage(.init(rawValue: language) ?? .swift)
                    .codeTextColors(.github)
                    .padding()
            }
            .frame(minWidth: 300)
        }
    }
}
```

### Pattern 5: Snippet Search with #Predicate

**What:** Multi-field search using `localizedStandardContains()` across name, content, and category. The predicate is constructed as a Swift variable from the search string (not a compile-time constant), so must use a predicate builder closure that captures the search string.

**When to use:** SnippetListView search bar.

**Example:**
```swift
// Source: Apple SwiftData docs — #Predicate macro
// "localizedStandardContains performs locale-aware, case-insensitive search"
let searchText = "swift"
let predicate = #Predicate<FlycutSchemaV1.Snippet> { snippet in
    searchText.isEmpty
        ? true
        : snippet.name.localizedStandardContains(searchText)
          || snippet.content.localizedStandardContains(searchText)
          || (snippet.category ?? "").localizedStandardContains(searchText)
}
```

### Pattern 6: Window Activation for Snippet Editor

**What:** A menu bar app running as `.accessory` cannot bring a WindowGroup window to front without temporarily switching to `.regular`. Use the same timing pattern documented for the Settings scene.

**When to use:** "Open Snippet Editor" menu item, "Share as Gist" window trigger.

**Example:**
```swift
// Source: steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
// (same timing issue applies to any WindowGroup in a .accessory app)
@Environment(\.openWindow) private var openWindow

func openSnippetEditor() {
    Task { @MainActor in
        NSApp.setActivationPolicy(.regular)
        try? await Task.sleep(for: .milliseconds(100))
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "snippets")
    }
}
```

### Anti-Patterns to Avoid

- **Using raspu/Highlightr:** Officially abandoned. Uses highlight.js 9.13 (outdated, security concerns). Do not add to the project.
- **Storing GitHub PAT in UserDefaults:** Plain-text storage in UserDefaults is visible in ~/Library/Preferences plists. Always use Keychain for credentials.
- **Updating Snippet @Model objects from a non-@MainActor context without PersistentIdentifier:** @Model objects are not Sendable. Always pass PersistentIdentifier across actor boundaries, re-fetch locally.
- **Calling openWindow without activation policy switch:** In an `.accessory` app, the window will open but stay behind other windows — the user cannot interact with it.
- **Using @preconcurrency import Foundation for URLSession:** The correct approach in Swift 6 is `URLSession.shared.data(for:)` which is properly Sendable-clean. The `@preconcurrency` workaround is only needed for older URLSession callback-based APIs.
- **Passing the GitHub PAT in a URL query parameter:** Always pass in the `Authorization` header. Query parameters appear in logs and proxy histories.
- **Optional chaining on category in #Predicate:** `snippet.category?.localizedStandardContains()` does not compile in SwiftData #Predicate. Use `(snippet.category ?? "").localizedStandardContains()` instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syntax highlighting | Custom regex tokenizer | HighlightSwift 1.1.0 | highlight.js covers 190+ languages with robust grammar; hand-rolled regex misses edge cases (strings with escapes, nested templates, multiline comments) |
| Token-based HTTP auth | Custom auth middleware | `Authorization: Bearer` header in URLRequest | GitHub REST API is stateless; no session management needed |
| Keychain wrapper library | KeychainAccess SPM | Raw Security.framework SecItem APIs | Three operations (save/load/delete), ~30 lines; no external dependency justified |
| Gist URL open-in-browser | Custom WebView | `NSWorkspace.shared.open(URL)` | Gist URL opens in default browser — one line |
| Snippet categories dropdown | Custom data source | Array of distinct category strings fetched from SwiftData | `FetchDescriptor` with `.distinct()` or a simple de-duplicated array from @Query results |

**Key insight:** The GitHub Gist API is intentionally simple. A full REST client library would obscure a 15-line URLSession call. Every abstraction added here has a cost in Swift 6 Sendable reasoning — keep the surface small.

---

## Common Pitfalls

### Pitfall 1: HighlightSwift is async — CodeText handles this, Highlight class requires await

**What goes wrong:** Calling `Highlight().attributedText(code)` in a synchronous context causes a compile error. Developers try to use it in a synchronous `body` property.

**Why it happens:** `highlight.attributedText()` returns `async throws` because it runs JavaScript via JavaScriptCore. The `CodeText` view handles this internally with `task {}`.

**How to avoid:** Use the `CodeText(code)` SwiftUI view for all display purposes. Only use the `Highlight` class directly if you need programmatic `AttributedString` output outside a view.

**Warning signs:** "Expression is 'async' but is not marked with 'await'" compiler error.

### Pitfall 2: SwiftData #Predicate does not support optional chaining with method calls

**What goes wrong:** `snippet.category?.localizedStandardContains(searchText)` fails to compile inside `#Predicate`.

**Why it happens:** The `#Predicate` macro translates Swift expressions to SQLite predicates. Optional method chaining on String? is not supported in the macro's translation layer.

**How to avoid:** Use `(snippet.category ?? "").localizedStandardContains(searchText)`.

**Warning signs:** Compiler error "Referencing instance method 'localizedStandardContains' requires the types 'Optional<String>' and 'String' be equivalent".

### Pitfall 3: Updating a @Model from SnippetStore after insert — PersistentIdentifier is temporary

**What goes wrong:** After calling `modelContext.insert(snippet)` and returning `snippet.persistentModelID`, the ID is a temporary placeholder until `modelContext.save()` is called. If you try to use the ID on the main actor before the background save completes, the model may not be found.

**Why it happens:** SwiftData assigns a temporary PersistentIdentifier on insert, replaced by a permanent one after the first save.

**How to avoid:** Call `try modelContext.save()` immediately after insert inside the @ModelActor function before returning the ID.

**Warning signs:** `modelContext.model(for: id)` returns nil on the first access.

### Pitfall 4: WindowGroup window stays behind other windows without activation policy switch

**What goes wrong:** Calling `openWindow(id: "snippets")` from a menu bar `.accessory` app opens the window but it stays hidden behind the frontmost application.

**Why it happens:** `.accessory` apps are treated as background processes by the window server; they cannot receive keyboard focus without `.regular` activation.

**How to avoid:** Use the 100 ms activation policy switch pattern (see Pattern 6). Restore `.accessory` after the window is in front.

**Warning signs:** The window appears in Mission Control but cannot be focused; clicking has no effect.

### Pitfall 5: GitHub API rate limit for unauthenticated requests — always use PAT

**What goes wrong:** Calling the Gist API with no token succeeds initially, then hits 60 req/hour rate limit.

**Why it happens:** Unauthenticated GitHub API requests are rate-limited to 60/hour by IP. PAT-authenticated requests get 5000/hour.

**How to avoid:** Always load the token from Keychain before every Gist request. If token is absent, show a configuration error — do not fall back to unauthenticated.

**Warning signs:** `HTTP 403 rate limit exceeded` after several requests.

### Pitfall 6: Gist filename matters — GitHub infers language from file extension

**What goes wrong:** Creating a Gist with filename "snippet" gives no syntax highlighting on the GitHub website.

**Why it happens:** GitHub uses file extension to determine language for Gist display. The Gist API accepts any string key as filename.

**How to avoid:** Use a language-to-extension map to construct the filename. E.g., `swift` → `snippet.swift`, `python` → `snippet.py`, `javascript` → `snippet.js`.

**Warning signs:** Gist displays on GitHub as plain text with no syntax coloring.

### Pitfall 7: SecItemAdd returns errSecDuplicateItem if called without first deleting

**What goes wrong:** Calling `SecItemAdd` on an account that already has a stored item returns `errSecDuplicateItem` (-25299) and the new value is not saved.

**Why it happens:** SecItem is not a dictionary update; it's a store. Adding the same key twice is an error.

**How to avoid:** Always call `SecItemDelete` before `SecItemAdd` in `saveToken()`. The `TokenStore` pattern above handles this correctly.

**Warning signs:** Token appears not to update after re-entering a new PAT in settings.

---

## Code Examples

Verified patterns from official sources and this codebase:

### GitHub Gist API POST Body and Response
```swift
// Source: GitHub REST API documentation — https://docs.github.com/en/rest/gists/gists
// POST https://api.github.com/gists
// Required headers:
//   Accept: application/vnd.github+json
//   Authorization: Bearer {token}
//   X-GitHub-Api-Version: 2022-11-28
//   Content-Type: application/json
//
// Request body (JSON):
{
  "description": "My Swift snippet",
  "public": false,
  "files": {
    "snippet.swift": {
      "content": "let x = 42"
    }
  }
}
//
// Response (HTTP 201 Created):
{
  "id": "aa5a315d61ae9438b18d",
  "html_url": "https://gist.github.com/username/aa5a315d61ae9438b18d",
  "description": "My Swift snippet",
  "public": false,
  "created_at": "2010-04-14T02:15:15Z",
  "updated_at": "2011-06-20T11:34:15Z"
}
```

### GistRecord Persistence After Successful Create
```swift
// Source: ClipboardStore pattern (this codebase) adapted for GistRecord
// Run on @MainActor since GistService owns a ModelContext reference
func recordGist(id: String, url: String, filename: String) throws {
    let record = FlycutSchemaV1.GistRecord(gistID: id, gistURL: url, filename: filename)
    modelContext.insert(record)
    try modelContext.save()
}
```

### HighlightSwift CodeText — Basic Usage
```swift
// Source: HighlightSwift README — https://github.com/appstefan/HighlightSwift
import HighlightSwift

CodeText(snippetContent)
    .highlightLanguage(.swift)          // explicit language
    .codeTextColors(.github)            // built-in theme
    .font(.system(.body, design: .monospaced))
```

### HighlightSwift Language Enum Values (common languages)
```swift
// Source: HighlightSwift 1.1.0 — HighlightLanguage enum
// swift, objectiveC, python, javascript, typescript, bash, ruby,
// json, xml, yaml, markdown, sql, css, html, java, kotlin, go, rust, cpp, c
// Auto-detect: omit .highlightLanguage() modifier
```

### Snippet Multi-Field Search Predicate
```swift
// Source: Apple SwiftData documentation
// localizedStandardContains = case-insensitive, locale-aware
let predicate = #Predicate<FlycutSchemaV1.Snippet> { snippet in
    searchText.isEmpty
        ? true
        : snippet.name.localizedStandardContains(searchText)
          || snippet.content.localizedStandardContains(searchText)
          || (snippet.category ?? "").localizedStandardContains(searchText)
}
```

### GistRecord @Query for History View
```swift
// Source: @Query pattern established in Phase 2-3 (this codebase)
@Query(sort: \FlycutSchemaV1.GistRecord.createdAt, order: .reverse)
private var gistHistory: [FlycutSchemaV1.GistRecord]
```

### Language-to-Extension Map (for Gist filename)
```swift
// Source: GitHub Linguist — standard file extensions
static let languageExtensions: [String: String] = [
    "swift": "swift", "python": "py", "javascript": "js",
    "typescript": "ts", "ruby": "rb", "go": "go",
    "rust": "rs", "kotlin": "kt", "java": "java",
    "bash": "sh", "c": "c", "cpp": "cpp",
    "sql": "sql", "html": "html", "css": "css",
    "json": "json", "yaml": "yaml", "xml": "xml",
    "markdown": "md"
]
```

### Copy Gist URL to Clipboard (GIST-04)
```swift
// Source: NSPasteboard pattern (this codebase)
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(gistResponse.htmlURL, forType: .string)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| raspu/Highlightr (highlight.js 9.13) | HighlightSwift 1.1.0 (highlight.js 11.9) | 2026 — Highlightr abandoned | Security + language coverage improvements |
| URLSession completion handlers | URLSession async/await `data(for:)` | Swift 5.5 / 2021 | Eliminates capture list complexity; Sendable-clean in Swift 6 |
| GitHub OAuth dance for Gist API | Fine-grained Personal Access Token | GitHub fine-grained PAT GA 2023 | Simpler auth for personal tools; no OAuth app registration needed |
| SecKeychainItem (macOS file keychain) | SecItem (iOS-style keychain) | macOS 10.9 / 2014 | SecItem is cross-platform, not deprecated; SecKeychainItem is deprecated macOS 12+ |

**Deprecated/outdated:**
- `SecKeychainItemAdd` / `SecKeychainFindGenericPassword`: Deprecated in macOS 12. Use `SecItemAdd` / `SecItemCopyMatching`.
- `raspu/Highlightr`: No longer maintained (2026). Do not add.
- `activateIgnoringOtherApps(true)`: Deprecated macOS 14. Use `NSApp.activate(from: NSRunningApplication.current, options: [])` or the simple `NSApp.activate(ignoringOtherApps: true)` — the latter still works despite the deprecation note; the replacement `activate(from:options:)` is the clean path.

---

## Open Questions

1. **HighlightSwift CodeText editability**
   - What we know: `CodeText` is read-only display. The editable input requires `TextEditor` or `NSTextView`.
   - What's unclear: Whether `CodeText` accurately reflects what the user typed in real-time without noticeable lag on macOS (JavaScript via JavaScriptCore has startup cost).
   - Recommendation: Build the editor with TextEditor for input + CodeText for live preview. If CodeText preview lags > 300 ms, debounce the update with a 250 ms delay using `.task(id: code)`.

2. **GistRecord model schema migration**
   - What we know: GistRecord is already in FlycutSchemaV1 with gistID, gistURL, filename, createdAt.
   - What's unclear: Whether to add `snippetDescription` or `isPublic` fields for richer history display.
   - Recommendation: Start with the existing schema fields. If the history view needs more context, add a `MigrationStage` in the plan.

3. **GitHub PAT scope verification**
   - What we know: The `gist` OAuth scope is required to create/read gists.
   - What's unclear: Whether fine-grained PATs require the Gist permission explicitly or if it is on by default.
   - Recommendation: Document in the settings UI that the PAT must have the `gist` scope selected. Link to GitHub's token creation page.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in, target: FlycutTests) |
| Config file | GENERATE_INFOPLIST_FILE=YES (set in Phase 2) |
| Quick run command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -testPlan FlycutTests 2>&1 | grep -E "passed|failed|error"` |
| Full suite command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' 2>&1 | tail -20` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SNIP-01 | SnippetStore.insert saves and can be re-fetched | unit | `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests` | ❌ Wave 0 |
| SNIP-02 | HighlightSwift CodeText renders without crash | unit (smoke) | `xcodebuild test -only-testing:FlycutTests/SnippetEditorViewTests` | ❌ Wave 0 |
| SNIP-03 | Snippet fetch filtered by language returns only matching | unit | `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests/testFetchByLanguage` | ❌ Wave 0 |
| SNIP-04 | Search predicate matches name, content, category | unit | `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests/testSearch` | ❌ Wave 0 |
| SNIP-05 | Snippet content reaches PasteService (reuse existing PasteService) | integration | `xcodebuild test -only-testing:FlycutTests/SnippetPasteTests` | ❌ Wave 0 |
| GIST-02 | TokenStore save/load/delete round-trip | unit | `xcodebuild test -only-testing:FlycutTests/TokenStoreTests` | ❌ Wave 0 |
| GIST-01/03/04 | GistService creates gist and returns html_url (mock URLSession) | unit | `xcodebuild test -only-testing:FlycutTests/GistServiceTests` | ❌ Wave 0 |
| GIST-05 | GistRecord is persisted and @Query returns newest first | unit | `xcodebuild test -only-testing:FlycutTests/GistServiceTests/testGistRecordPersistence` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests` (fastest relevant suite)
- **Per wave merge:** Full suite command above
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `FlycutTests/SnippetStoreTests.swift` — covers SNIP-01, SNIP-03, SNIP-04
- [ ] `FlycutTests/GistServiceTests.swift` — covers GIST-01, GIST-03, GIST-04, GIST-05 (mock URLSession via URLProtocol)
- [ ] `FlycutTests/TokenStoreTests.swift` — covers GIST-02 (Keychain round-trip; non-sandboxed app Keychain accessible in test)
- [ ] `FlycutTests/SnippetPasteTests.swift` — covers SNIP-05

---

## Sources

### Primary (HIGH confidence)
- HighlightSwift GitHub README — https://github.com/appstefan/HighlightSwift — API surface, SwiftUI integration, Swift 6 concurrency declaration
- HighlightSwift Package.swift (raw) — `enableExperimentalFeature("StrictConcurrency")`, macOS 13 minimum, tools 5.10
- FlycutSchemaV1.swift (this codebase) — Snippet and GistRecord models already defined
- ClipboardStore.swift (this codebase) — @ModelActor pattern to mirror for SnippetStore
- AppDelegate.swift (this codebase) — Activation policy, service wiring patterns
- Apple Security Framework documentation — SecItemAdd, SecItemCopyMatching, SecItemDelete for kSecClassGenericPassword
- GitHub REST API documentation — POST /gists request body structure and response fields

### Secondary (MEDIUM confidence)
- steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items — Activation policy switch pattern with 100 ms delay
- Apple SwiftData documentation via community sources — `#Predicate` localizedStandardContains, multi-field OR pattern
- GitHub Gist API response field documentation — id, html_url, created_at, description confirmed via developer.github.com/v3/gists

### Tertiary (LOW confidence)
- HighlighterSwift 3.0.0 (smittytone) — No explicit Swift 6 language mode in Package.swift; deprioritized in favor of HighlightSwift
- Highlightr (raspu) — Confirmed abandoned by maintainer note; single source but consistent with Swift Package Index data

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — HighlightSwift Package.swift verified, Security.framework is system, URLSession is stdlib, SwiftData models already in codebase
- Architecture: HIGH — Mirrors existing @ModelActor/service patterns in this codebase
- Pitfalls: MEDIUM-HIGH — SecItemDuplicate and #Predicate optional chaining verified via Apple docs; activation policy pattern verified via primary blog source with implementation detail
- GitHub API: HIGH — Request/response structure confirmed via GitHub official docs

**Research date:** 2026-03-09
**Valid until:** 2026-06-09 (stable APIs; HighlightSwift minor versions may release)
