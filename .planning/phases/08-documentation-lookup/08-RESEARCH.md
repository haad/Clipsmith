# Phase 8: Documentation Lookup - Research

**Researched:** 2026-03-16
**Domain:** macOS offline documentation search, Dash docset format, SQLite querying, selected-text capture via Accessibility API
**Confidence:** HIGH (stack and architecture), MEDIUM (selected-text reliability), HIGH (docset format)

---

## Summary

Phase 8 adds a documentation lookup popup triggered by a global hotkey. When fired, it reads the currently selected text in the frontmost app (via AXUIElement Accessibility API, with a CGEvent Cmd-C fallback), then searches the user's downloaded offline docsets and presents results in a lightweight NSPanel bezel — the same non-activating panel pattern used by the clipboard bezel and the prompt bezel.

The docset format is the well-established Dash/Zeal format: a `.docset` bundle containing HTML documentation and a SQLite index (`docSet.dsidx`) with the `searchIndex(id, name, type, path)` schema. The canonical library for reading this SQLite file in Swift is GRDB.swift v7 (current: 7.10.0), which ships full Swift 6 / Swift concurrency support. Docset downloads are sourced from Kapeli's public CDN via simple `.tgz` URLs, with extraction via the bundled `tar` command-line tool.

The feature is self-contained: no new SwiftData models are needed. Docset metadata (name, local path, download state) is stored in a dedicated `@Observable` service backed by a lightweight JSON file in Application Support. Phase 5 (prompt library / PromptBezelController) provides the exact architectural template for the new `DocBezelController` and `DocBezelViewModel`.

**Primary recommendation:** Mirror the PromptBezelController architecture exactly — NSPanel + DocBezelController + DocBezelViewModel + DocBezelView — using GRDB.swift for docset SQLite queries, AXUIElement for selected-text capture with a Cmd-C fallback, and Kapeli's CDN `.tgz` URLs for downloads.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOCS-01 | User can trigger a quick documentation search for selected/highlighted text via hotkey | AXUIElement `kAXSelectedTextAttribute` API covers text capture; `KeyboardShortcuts.Name.activateDocLookup` follows existing hotkey pattern; CGEvent Cmd-C fallback handles apps that don't expose selected text via AX |
| DOCS-02 | Lightweight popup shows documentation results from offline docsets | NSPanel bezel (PromptBezelController template) + GRDB.swift query of `searchIndex` SQLite table; WKWebView for result HTML display |
| DOCS-03 | User can download and manage docsets for their preferred languages/frameworks | `DocsetManagerService` + Kapeli CDN `.tgz` URLs + `Process(launchPath: "/usr/bin/tar")` extraction; management UI in a new Settings tab |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| GRDB.swift | 7.10.0 (Feb 2026) | SQLite query of docset `searchIndex` table | Full Swift 6 / Swift concurrency support; struct-based Codable records; `DatabaseQueue` provides safe concurrent access; de-facto standard for Swift SQLite |
| WebKit (WKWebView) | System (macOS 15+) | Render selected HTML documentation page inside popup | Only viable way to display the HTML content from a docset file; `loadFileURL(_:allowingReadAccessTo:)` for local files |
| KeyboardShortcuts | 2.x (already in project) | Global hotkey `activateDocLookup` | Already used throughout; no new dependency |
| Foundation URLSession + Process | System | Download `.tgz` from Kapeli CDN + extract via `/usr/bin/tar` | URLSession async download API for progress; `Process` with `tar` is simpler than any third-party tar library |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Combine / AsyncStream | System | Stream download progress into SwiftUI | URLSessionDownloadDelegate publishes bytes-received to an `@Observable` service |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GRDB.swift | SQLite.swift | GRDB 7 has better Swift 6 sendable support and struct Codable records — prefer GRDB |
| GRDB.swift | Raw `sqlite3` C API | Too verbose; GRDB wraps it cleanly with async/await |
| `/usr/bin/tar` via Process | Third-party Tar library (e.g. SWCompression) | `tar` is already present on all macOS systems; no extra dependency needed |
| AXUIElement selected text | Always Cmd-C to paste then read | AXUIElement is non-destructive (doesn't replace clipboard); use Cmd-C only as fallback |
| WKWebView inline | Open in external browser / Dash | DOCS-02 requires "lightweight popup" — WKWebView panel satisfies this; opening in Dash defeats the point |

**Installation:**
```bash
# GRDB.swift — add via Xcode: File > Add Package Dependencies
# https://github.com/groue/GRDB.swift.git  upToNextMajorVersion: 7.0.0
```

**Version verification:**
```bash
# In Package.resolved after adding, confirm:
# "version": "7.10.0" (or later) for groue/GRDB.swift
```

---

## Architecture Patterns

### Recommended Project Structure
```
Clipsmith/
├── Services/
│   ├── DocsetManagerService.swift   # Download, extract, list, delete docsets
│   └── DocsetSearchService.swift    # GRDB-based searchIndex queries
├── Views/
│   ├── DocBezelController.swift     # NSPanel subclass (mirrors PromptBezelController)
│   ├── DocBezelView.swift           # SwiftUI content (search field + results list + web preview)
│   ├── DocBezelViewModel.swift      # @Observable @MainActor (mirrors PromptBezelViewModel)
│   └── Settings/
│       └── DocsetSettingsSection.swift  # Download + manage docsets UI (new Settings tab)
```

### Pattern 1: NSPanel Non-Activating Popup (mirrors PromptBezelController exactly)

**What:** `DocBezelController` subclasses `NSPanel`, init with `.nonactivatingPanel` in `styleMask`, hosts `DocBezelView` via `NSHostingView`.

**When to use:** Required for a floating HUD that never steals focus from the frontmost app.

**Example:**
```swift
// Source: existing PromptBezelController.swift (project codebase)
init(modelContainer: ModelContainer?) {
    super.init(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
}
override var canBecomeKey: Bool { true }
override var canBecomeMain: Bool { false }
```

**CRITICAL:** `.nonactivatingPanel` MUST be in the `super.init` `styleMask` parameter — setting it post-init does not update the WindowServer tag.

### Pattern 2: Selected Text Capture via AXUIElement

**What:** Before showing the popup, read the selected text from the frontmost app's focused UI element using the Accessibility API.

**When to use:** Always attempt first; fall back to Cmd-C if AX returns empty.

**Example:**
```swift
// Source: Apple Developer Documentation — kAXSelectedTextAttribute
@MainActor
func getSelectedText(from app: NSRunningApplication) -> String? {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var focusedElement: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement
    ) == .success else { return nil }

    var selectedText: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        focusedElement as! AXUIElement,
        kAXSelectedTextAttribute as CFString,
        &selectedText
    ) == .success else { return nil }

    return selectedText as? String
}
```

**Fallback (Cmd-C):** When AX returns nil or empty string, save the current pasteboard changeCount, synthesize Cmd-C via CGEvent (same pattern as PasteService), wait ~0.15s, then read `NSPasteboard.general.string(forType: .string)` and restore the original pasteboard contents.

### Pattern 3: GRDB.swift Docset Search

**What:** Open the docset's `docSet.dsidx` SQLite file via `DatabaseQueue` and query `searchIndex` with a LIKE clause.

**When to use:** For each search query as the user types.

**Example:**
```swift
// Source: GRDB.swift documentation + kapeli.com/docsets SQLite schema
import GRDB

struct DocEntry: Codable, FetchableRecord {
    var id: Int64
    var name: String
    var type: String
    var path: String
}

func search(query: String, in docsetPath: URL) async throws -> [DocEntry] {
    let dbPath = docsetPath
        .appendingPathComponent("Contents/Resources/docSet.dsidx")
    let dbQueue = try DatabaseQueue(path: dbPath.path)
    return try await dbQueue.read { db in
        try DocEntry.fetchAll(db, sql: """
            SELECT id, name, type, path
            FROM searchIndex
            WHERE name LIKE ?
            ORDER BY name
            LIMIT 50
            """, arguments: ["%\(query)%"])
    }
}
```

### Pattern 4: Docset Download + Extraction

**What:** Download `.tgz` from Kapeli CDN; extract with `/usr/bin/tar`; store in Application Support.

**When to use:** User taps "Download" next to a docset name in DocsetSettingsSection.

**Example:**
```swift
// Source: URLSession async download API + Process for tar
func downloadDocset(name: String, progress: @escaping (Double) -> Void) async throws {
    let url = URL(string: "https://sanfrancisco.kapeli.com/feeds/\(name).tgz")!
    let destDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPath("Clipsmith/Docsets/")

    // Download with progress via URLSession.bytes async sequence
    let (localURL, _) = try await URLSession.shared.download(from: url)

    // Extract with /usr/bin/tar
    let process = Process()
    process.launchPath = "/usr/bin/tar"
    process.arguments = ["-xzf", localURL.path, "-C", destDir.path]
    process.launch()
    process.waitUntilExit()
    try FileManager.default.removeItem(at: localURL)
}
```

**For download progress:** Use `URLSession.bytes(from:)` + count bytes received vs. expected content length, or use `URLSessionDownloadDelegate.urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)` with `withCheckedContinuation`.

### Pattern 5: Docset Manifest — Kapeli Feeds

**What:** Parse a hardcoded list of known docset names + CDN URLs, or fetch the Kapeli feeds XML to discover available docsets.

**Feed URL pattern:**
```
https://sanfrancisco.kapeli.com/feeds/{DocsetName}.tgz  // download
https://raw.githubusercontent.com/Kapeli/feeds/master/{DocsetName}.xml  // version info
```

**Known docset names (sample):** `Swift`, `Python_3`, `JavaScript`, `React`, `TypeScript`, `Go`, `Rust`, `Ruby`, `PHP_Manual`, `CSS`, `HTML`, `Java`, `C`, `C++`, `Node.js`, `Django`, `Laravel`, `Vue.js`, `Angular`

**Recommended approach:** Bundle a static JSON manifest of ~30 popular docsets with name, display name, and CDN URL. No network call needed to list options — only to download. The CDN mirrors rotate: `sanfrancisco`, `london`, `newyork`, `tokyo`, `frankfurt`.

### Pattern 6: DocsetManagerService — Local State Storage

**What:** Store downloaded docset metadata (name, local path, version, enabled state) as JSON in Application Support. No SwiftData needed — this is simple key-value metadata.

**When to use:** Phase 8 should NOT add new SwiftData models to avoid schema migration complexity.

```swift
// Store docset metadata as Codable JSON
struct DocsetInfo: Codable, Identifiable {
    var id: String          // e.g. "Swift"
    var displayName: String // e.g. "Swift"
    var localPath: URL?     // nil if not downloaded
    var version: String?
    var isEnabled: Bool
}

// Persist to Application Support/Clipsmith/docsets.json
```

### Anti-Patterns to Avoid

- **Adding SwiftData models for docset entries:** Unnecessary migration complexity; JSON file is sufficient for simple metadata.
- **Embedding Dash app inside Clipsmith:** Out of scope per REQUIREMENTS.md — "Full embedded doc browser ... Quick lookup sufficient; Dash exists for full browsing."
- **Using NSWindowController for the doc popup:** NSPanel subclass is simpler and matches existing PromptBezelController pattern exactly.
- **Reading the entire docset HTML into memory:** Use `WKWebView.loadFileURL(_:allowingReadAccessTo:)` to stream from disk.
- **Running SQLite queries on the main thread:** Use `DatabaseQueue.read { }` which dispatches to a background queue in GRDB.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite queries | Custom sqlite3 C API calls | GRDB.swift DatabaseQueue | Thread-safety, async/await, Codable binding, error handling |
| Tar extraction | Swift tar parser | `/usr/bin/tar` via `Process` | Already on every Mac; handles gzip, symlinks, permissions correctly |
| Selected text from other apps | AppKit/UIKit text reading | `AXUIElementCopyAttributeValue` + `kAXSelectedTextAttribute` | Accessibility API is the only safe cross-app text read |
| HTML rendering | NSAttributedString HTML rendering | WKWebView with `loadFileURL` | Docset HTML uses JS/CSS; WKWebView is the only production-grade renderer |
| Download progress tracking | Custom byte counting | `URLSessionDownloadDelegate` | Provides accurate total-bytes progress reporting |

**Key insight:** The docset format is deliberately simple (SQLite + HTML), so the data layer is lightweight. The hard parts — tab rendering, SQLite thread-safety, tar extraction — are already solved by system tools and GRDB.

---

## Common Pitfalls

### Pitfall 1: AXUIElement Returns Empty String for Many Apps
**What goes wrong:** Many modern Electron, terminal, and browser apps do not expose selected text via `kAXSelectedTextAttribute` even when text is visually selected.
**Why it happens:** AX support is opt-in; many apps do not implement it fully.
**How to avoid:** Always implement the Cmd-C fallback. Strategy:
  1. Try AX first — fast, non-destructive.
  2. If result is nil or empty, save current pasteboard, synthesize Cmd-C (100ms delay), read new pasteboard, restore old value.
  3. If still empty, open popup with empty search field for manual entry.
**Warning signs:** Test against VSCode (Electron) and Safari — both behave differently.

### Pitfall 2: AXUIElement Requires Existing Accessibility Permission
**What goes wrong:** The app already has Accessibility permission from Phase 2 (for paste injection). However, if the user revokes it, AX calls silently fail without error.
**How to avoid:** Check `AXIsProcessTrusted()` before the AX call; fall back to Cmd-C if not trusted (paste injection would also be broken, so this is consistent behavior).

### Pitfall 3: GRDB DatabaseQueue Must Not Be Kept Open Long-Term Across Multiple Docsets
**What goes wrong:** Opening a `DatabaseQueue` for every docset on every keystroke creates file descriptor leaks.
**How to avoid:** Cache one `DatabaseQueue` per docset path in `DocsetSearchService`. Invalidate the cache when a docset is deleted or reinstalled.

### Pitfall 4: Kapeli CDN Uses HTTP Not HTTPS
**What goes wrong:** The feed URLs in kapeli.com docs and XML files use `http://` not `https://`. URLSession on macOS 15 enforces App Transport Security.
**How to avoid:** Use `https://` explicitly in all download URLs (the CDN supports HTTPS):
```
https://sanfrancisco.kapeli.com/feeds/Swift.tgz
```
If the download fails for one mirror, try the next mirror in the rotation.

### Pitfall 5: Docset Extraction Directory Collisions
**What goes wrong:** Multiple downloaded docsets extract to the same destination directory name if two docsets share the same folder name inside the tgz.
**How to avoid:** Extract each docset to its own named subdirectory: `Clipsmith/Docsets/{DocsetName}/`. Pass `-C destDir` to `tar` and verify the resulting `.docset` bundle is present before marking as installed.

### Pitfall 6: WKWebView Navigation in Non-Activating Panel
**What goes wrong:** WKWebView inside a `.nonactivatingPanel` may not handle all link clicks or navigation events correctly.
**How to avoid:** Set a `WKNavigationDelegate` that intercepts link clicks (`.linkActivated` policy) and opens them in the default browser via `NSWorkspace.shared.open(url)`, rather than navigating within the panel. This also prevents deep doc navigation that would lose context.

### Pitfall 7: Swift 6 Sendable with GRDB DatabaseQueue
**What goes wrong:** `DatabaseQueue` is `Sendable` in GRDB 7, but `FetchableRecord` types must also be `Sendable`. Using class-based record types causes Swift 6 errors.
**How to avoid:** Use struct-based `Codable + FetchableRecord` for `DocEntry` (as shown in Pattern 3). GRDB 7 is specifically designed around this pattern.

---

## Code Examples

Verified patterns from official sources:

### Opening a Docset SQLite File (GRDB 7)
```swift
// Source: GRDB.swift README + kapeli.com/docsets SQLite schema
import GRDB

let dbPath = docsetURL
    .appendingPathComponent("Contents/Resources/docSet.dsidx").path
let dbQueue = try DatabaseQueue(path: dbPath)
```

### Querying searchIndex
```swift
// Source: kapeli.com/docsets — schema: searchIndex(id, name, type, path)
struct DocEntry: Codable, FetchableRecord, Sendable {
    let id: Int64
    let name: String
    let type: String
    let path: String
}

let results = try await dbQueue.read { db in
    try DocEntry.fetchAll(db, sql: """
        SELECT id, name, type, path
        FROM searchIndex
        WHERE name LIKE ?
        ORDER BY name LIMIT 50
        """, arguments: ["\(query)%"])
}
```

### Getting Selected Text via AXUIElement
```swift
// Source: Apple Developer Documentation — kAXSelectedTextAttribute
// Requires: Accessibility permission (already granted in Phase 2)
@MainActor
func selectedText(from app: NSRunningApplication) -> String? {
    guard AXIsProcessTrusted() else { return nil }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        axApp,
        kAXFocusedUIElementAttribute as CFString,
        &focusedRef
    ) == .success, let focused = focusedRef else { return nil }

    var textRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        focused as! AXUIElement,
        kAXSelectedTextAttribute as CFString,
        &textRef
    ) == .success else { return nil }

    return textRef as? String
}
```

### Loading Docset HTML in WKWebView
```swift
// Source: Apple Developer Documentation — WKWebView.loadFileURL(_:allowingReadAccessTo:)
import WebKit

let htmlURL = docsetURL
    .appendingPathComponent("Contents/Resources/Documents")
    .appendingPathComponent(entry.path)
// allowingReadAccessTo: the entire Documents directory so CSS/JS resolve
webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
```

### Hotkey Registration (mirrors existing pattern)
```swift
// Source: project Clipsmith/Settings/KeyboardShortcutNames.swift
extension KeyboardShortcuts.Name {
    static let activateDocLookup = Self("activateDocLookup",
        default: .init(.d, modifiers: [.command, .shift]))
}
```

### Docset Download via URLSession
```swift
// Source: URLSession async download API
let tgzURL = URL(string: "https://sanfrancisco.kapeli.com/feeds/\(name).tgz")!
let (localURL, _) = try await URLSession.shared.download(from: tgzURL)
defer { try? FileManager.default.removeItem(at: localURL) }

let destDir = appSupportURL.appendingPathComponent("Docsets")
try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
process.arguments = ["-xzf", localURL.path, "-C", destDir.path]
try process.run()
process.waitUntilExit()
// Verify .docset bundle appeared at destDir/{name}.docset
```

---

## Docset Format Reference

### Directory Structure
```
Swift.docset/
├── Contents/
│   ├── Info.plist         # CFBundleIdentifier, CFBundleName, dashIndexFilePath
│   └── Resources/
│       ├── docSet.dsidx   # SQLite index
│       └── Documents/     # HTML documentation files
│           ├── index.html
│           └── ...
```

### SQLite Schema
```sql
CREATE TABLE searchIndex(
    id   INTEGER PRIMARY KEY,
    name TEXT,    -- e.g. "String.init(_:radix:uppercase:)"
    type TEXT,    -- e.g. "Initializer", "Class", "Function", "Method", "Constant"
    path TEXT     -- relative path from Documents/, e.g. "Types/String.html#..."
);
CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
```

### Info.plist Key Fields
```xml
<key>CFBundleIdentifier</key>  <string>swift</string>
<key>CFBundleName</key>         <string>Swift</string>
<key>dashIndexFilePath</key>    <string>index.html</string>
<key>DashDocSetFamily</key>     <string>dashtoc</string>
```

### Kapeli CDN URL Pattern
```
https://{mirror}.kapeli.com/feeds/{DocsetName}.tgz

Mirrors: sanfrancisco, london, newyork, tokyo, frankfurt
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SQLite.swift for Swift SQLite | GRDB.swift v7 | 2025 | GRDB 7 adds full Swift 6 sendable support, struct records |
| Class-based GRDB Records | Struct + Codable + FetchableRecord | GRDB 7 (2025) | Required for Swift 6 strict concurrency |
| UIWebView / SFSafariViewController | WKWebView with WKNavigationDelegate | macOS 10.15+ | WKWebView is the current standard for embedded HTML |

**Deprecated/outdated:**
- `UIWebView`: Removed. Use `WKWebView` only.
- GRDB class-based Records: Deprecated in GRDB 7. Use struct + Codable.

---

## Open Questions

1. **AX selected text vs. Cmd-C fallback timing**
   - What we know: AX is non-destructive; Cmd-C overwrites clipboard temporarily
   - What's unclear: The 0.15s window for Cmd-C fallback may not be enough in slow apps; restoring the original clipboard adds complexity
   - Recommendation: Implement AX first. For fallback, save/restore clipboard using a change-count guard (same pattern as `ClipboardMonitor.blockedChangeCount`). If restore fails, that is acceptable — the user performed a doc lookup, not a copy.

2. **DocsetSettingsSection layout: separate window or Settings tab?**
   - What we know: Existing large features (Gist, Prompts) use Settings tabs; the snippet editor gets its own `WindowGroup`
   - What's unclear: A docset manager with download progress bars may be awkward in the narrow Settings panel
   - Recommendation: Use a Settings tab for simplicity (consistent with GistSettingsSection pattern). Download progress can be a compact ProgressView inline with each row.

3. **Number of docsets to bundle in the static manifest**
   - What we know: Kapeli has 180+ feeds; listing all would overwhelm the UI
   - What's unclear: What's the right curated set for a developer-focused tool
   - Recommendation: Bundle 25-35 most common (Swift, Python, JavaScript, TypeScript, Go, Rust, React, Vue, Angular, CSS, HTML, Java, C, C++, Node.js, Django, Laravel, PHP, Ruby on Rails, Bash, PostgreSQL, MySQL, Docker, Kubernetes, Git)

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (existing, Swift 6) |
| Config file | Clipsmith.xcodeproj target ClipsmithTests |
| Quick run command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/DocsetSearchServiceTests` |
| Full suite command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOCS-01 | `selectedText(from:)` returns text from an AX-capable mock element | unit | `xcodebuild test ... -only-testing:ClipsmithTests/DocLookupServiceTests` | Wave 0 |
| DOCS-01 | Cmd-C fallback: returns pasteboard string when AX returns nil | unit | `xcodebuild test ... -only-testing:ClipsmithTests/DocLookupServiceTests` | Wave 0 |
| DOCS-02 | `DocsetSearchService.search(query:in:)` returns correct entries from fixture .dsidx | unit | `xcodebuild test ... -only-testing:ClipsmithTests/DocsetSearchServiceTests` | Wave 0 |
| DOCS-02 | `DocBezelViewModel.filteredResults` filters by query string | unit | `xcodebuild test ... -only-testing:ClipsmithTests/DocBezelViewModelTests` | Wave 0 |
| DOCS-03 | `DocsetManagerService` save/load round-trips `DocsetInfo` JSON correctly | unit | `xcodebuild test ... -only-testing:ClipsmithTests/DocsetManagerServiceTests` | Wave 0 |
| DOCS-03 | Download + extraction — integration; download from live CDN | manual-only | N/A — network I/O, OS `tar` process | — |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/DocsetSearchServiceTests -only-testing:ClipsmithTests/DocBezelViewModelTests -only-testing:ClipsmithTests/DocsetManagerServiceTests`
- **Per wave merge:** Full suite: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `ClipsmithTests/DocsetSearchServiceTests.swift` — covers DOCS-02 (GRDB queries against fixture `.dsidx`)
- [ ] `ClipsmithTests/DocBezelViewModelTests.swift` — covers DOCS-02 (filtering, navigation)
- [ ] `ClipsmithTests/DocsetManagerServiceTests.swift` — covers DOCS-03 (JSON persistence round-trip)
- [ ] `ClipsmithTests/DocLookupServiceTests.swift` — covers DOCS-01 (AX + fallback logic with mocked AX responses)
- [ ] Test fixture: `ClipsmithTests/Fixtures/Swift.docset/Contents/Resources/docSet.dsidx` — small SQLite file with 10 sample entries, created in Wave 0 setup task

---

## Sources

### Primary (HIGH confidence)
- kapeli.com/docsets — Docset format specification: folder structure, Info.plist keys, SQLite schema, entry types
- github.com/Kapeli/feeds — XML feed structure verified; CDN URL pattern from `Swift.xml` (confirmed `https://sanfrancisco.kapeli.com/feeds/Swift.tgz`)
- developer.apple.com/documentation/applicationservices/kaxselectedtextattribute — AXUIElement selected text API
- developer.apple.com/documentation/webkit/wkwebview — `loadFileURL(_:allowingReadAccessTo:)` for local HTML
- swiftpackageindex.com/groue/GRDB.swift — GRDB 7.10.0, Swift 6 concurrency documentation

### Secondary (MEDIUM confidence)
- groue/GRDB.swift GRDB7MigrationGuide.md — struct-based Codable records requirement for Swift 6
- groue/GRDB.swift SwiftConcurrency documentation — `DatabaseQueue.read` dispatches to background queue
- Project codebase — PromptBezelController.swift, PasteService.swift patterns confirmed as templates for Phase 8

### Tertiary (LOW confidence)
- WebSearch — AX reliability across Electron/browser apps: community reports of partial AX support; implementation must have Cmd-C fallback

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — GRDB 7.10.0 confirmed at Swift Package Index; WKWebView, URLSession, Process are system frameworks; KeyboardShortcuts already in project
- Architecture: HIGH — Mirrors proven PromptBezelController pattern exactly; docset format is stable (Dash format unchanged for 10+ years)
- Pitfalls: HIGH for NSPanel/concurrency (confirmed from project history); MEDIUM for AX reliability (community-verified, not officially documented edge cases)

**Research date:** 2026-03-16
**Valid until:** 2026-09-16 (docset format is stable; GRDB API evolves slowly)
