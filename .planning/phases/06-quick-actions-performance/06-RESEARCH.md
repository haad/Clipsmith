# Phase 6: Quick Actions & Performance - Research

**Researched:** 2026-03-12
**Domain:** Swift 6 / SwiftUI / AppKit — text transforms, NSMenu context actions in NSPanel, RTF generation, JSON codable export/import, adaptive timer polling, SwiftData export
**Confidence:** HIGH

## Summary

Phase 6 adds five distinct capabilities to an already-complete, production-quality Swift 6 + SwiftUI codebase:

1. **Quick action menu** on bezel items (right-click or hotkey) with text transform, format, and share sub-actions
2. **Text transforms**: UPPERCASE, lowercase, Title Case, trim whitespace, URL encode/decode (QACT-01)
3. **Text formatters**: wrap in quotes, markdown code block, JSON pretty-print (QACT-02)
4. **Share actions**: create GitHub Gist (already implemented in GistService), copy as RTF (QACT-03)
5. **History export/import**: serialize all Clipping records to/from JSON (PERF-01)
6. **Adaptive clipboard polling**: vary the timer interval based on user activity to cut idle CPU (PERF-02)

The codebase already has every dependency in place: `GistService.createGist()`, `ClipboardStore`, `ClipboardMonitor` (fixed-interval Timer), `BezelController`/`BezelView`/`BezelViewModel`, and the `ClippingInfo` Sendable bridge. Phase 6 is fundamentally additive — no schema migration is needed, no new SPM packages are required, and the core architecture is unchanged.

**Primary recommendation:** Implement quick actions as an `NSMenu` triggered from `BezelController`, surface text transforms as pure-Swift functions in a new `TextTransformer` value type, reuse `GistService` for Gist sharing, generate RTF with `NSAttributedString`, export/import via `JSONEncoder`/`JSONDecoder` + `NSSavePanel`/`NSOpenPanel`, and implement adaptive polling by replacing `ClipboardMonitor`'s fixed `Timer` with a dual-interval approach driven by `NSEvent` global activity monitoring.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QACT-01 | Right-click or secondary action on bezel item reveals transform actions: UPPERCASE, lowercase, Title Case, trim whitespace, URL encode/decode | NSMenu from BezelController on right-click; TextTransformer pure functions; apply result via ClipboardStore + BezelViewModel |
| QACT-02 | Format actions: wrap in quotes, markdown code block, JSON pretty-print | Same TextTransformer + NSMenu pattern; JSONSerialization for pretty-print; no external deps |
| QACT-03 | Share actions: create Gist (existing GistService), copy as RTF (NSAttributedString) | GistService.createGist() already wired in AppDelegate; RTF via NSAttributedString(string:attributes:).rtf(from:documentAttributes:) |
| PERF-01 | Export clipboard history as JSON; import back | JSONEncoder/Decoder on a Codable struct; NSSavePanel + NSOpenPanel; SchemaV3 migration NOT needed — export is out-of-band |
| PERF-02 | Adaptive clipboard polling: faster when active, slower when idle | Replace fixed Timer in ClipboardMonitor with dual-interval; NSEvent.addGlobalMonitorForEvents to track activity |
</phase_requirements>

---

## Standard Stack

### Core (all already in project — no new SPM packages needed)

| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| Swift standard library | Swift 6 | String transforms (uppercased, lowercased, URL encoding) | Built-in; zero dep |
| Foundation | macOS 15 SDK | CharacterSet, JSONEncoder/Decoder, NSAttributedString, NSSavePanel/NSOpenPanel | Built-in platform framework |
| AppKit | macOS 15 SDK | NSMenu, NSMenuItem, NSEvent monitor, NSSavePanel | Required for non-SwiftUI panel interactions |
| SwiftData | macOS 15 SDK | ClipboardStore actor, Clipping model, export fetch | Already integrated |
| GistService | Phase 4 (internal) | GitHub Gist creation | Already implemented, tested, wired |

### Supporting

| API | Purpose | When to Use |
|-----|---------|-------------|
| `NSMenu` + `NSMenuItem` | Context menu in NSPanel (non-activating) | Quick action popup on right-click in bezel |
| `NSAttributedString` + `.rtf` | RTF generation from plain text | QACT-03 copy-as-RTF |
| `NSPasteboard.writeObjects([NSAttributedString])` | Write RTF to pasteboard | After RTF generation |
| `NSEvent.addGlobalMonitorForEvents(matching:)` | Detect user activity for adaptive polling | PERF-02 activity detection |
| `NSSavePanel` / `NSOpenPanel` | File save/open for export/import | PERF-01 history file dialogs |
| `JSONEncoder` / `JSONDecoder` | History serialization | PERF-01 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pure-Swift TextTransformer struct | An SPM text library | No benefit — all transforms are 1-3 lines of Swift stdlib |
| NSMenu (AppKit) | SwiftUI .contextMenu | `.contextMenu` is NOT available on NSPanel NSHostingView root; NSMenu is the only reliable option |
| NSEvent global monitor for activity | Combine timer publisher | NSEvent.addGlobalMonitorForEvents already used in codebase (flagsMonitor, clickOutsideMonitor) — consistent pattern |
| JSONEncoder with custom Codable struct | CoreData exporters | JSONEncoder is simple, self-documenting, human-readable output; matches "developer tool" audience |

**Installation:** No new packages required. All APIs are in the macOS 15 SDK.

---

## Architecture Patterns

### Recommended Project Structure

```
FlycutSwift/
├── Services/
│   ├── ClipboardMonitor.swift      # MODIFIED: adaptive polling (PERF-02)
│   ├── ClipboardExportService.swift # NEW: JSON export/import (PERF-01)
│   └── TextTransformer.swift        # NEW: pure transform functions (QACT-01, QACT-02)
├── Views/
│   ├── BezelController.swift        # MODIFIED: rightMouseDown -> showQuickActionMenu (QACT-01,02,03)
│   └── BezelView.swift              # MINOR: optional selection highlight on right-click
FlycutTests/
│   ├── TextTransformerTests.swift   # NEW: unit tests for all transforms
│   └── ClipboardExportServiceTests.swift # NEW: export/import round-trip tests
```

### Pattern 1: TextTransformer — Pure Value Type

**What:** A namespace enum (no cases, static functions only) containing all text transforms. Zero dependencies, fully testable without SwiftData or UI.

**When to use:** Any operation that takes a String and returns a String transformation.

**Example:**
```swift
// Source: Swift stdlib — verified against Swift 6 docs
enum TextTransformer {
    // QACT-01 transforms
    static func uppercase(_ s: String) -> String { s.uppercased() }
    static func lowercase(_ s: String) -> String { s.lowercased() }
    static func titleCase(_ s: String) -> String {
        s.capitalized  // Note: Swift's .capitalized is word-by-word
    }
    static func trimWhitespace(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
    static func urlDecode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    // QACT-02 formatters
    static func wrapInQuotes(_ s: String) -> String { "\"\(s)\"" }
    static func markdownCodeBlock(_ s: String) -> String { "```\n\(s)\n```" }
    static func jsonPrettyPrint(_ s: String) -> String {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8)
        else { return s }  // Return unchanged if not valid JSON
        return result
    }
}
```

**Swift 6 note:** This enum has no stored state and all functions are `nonisolated` by default — no actor isolation issues.

### Pattern 2: Quick Action Menu via NSMenu in BezelController

**What:** Override `rightMouseDown(with:)` in `BezelController` to build and pop an `NSMenu`. The menu items call transform/format/share functions and then update `BezelViewModel` and `ClipboardStore`.

**When to use:** Any secondary action triggered by right-click or a dedicated hotkey on a bezel item.

**Critical constraint:** `SwiftUI .contextMenu` does NOT work reliably on `NSHostingView` inside a non-activating `NSPanel`. Use `NSMenu` directly from the controller.

**Example:**
```swift
// Source: AppKit NSMenu docs (macOS 15 SDK)
// In BezelController:
override func rightMouseDown(with event: NSEvent) {
    guard let content = viewModel.currentClipping else { return }
    let menu = NSMenu(title: "Quick Actions")

    // Transform submenu
    let transformMenu = NSMenu(title: "Transform")
    transformMenu.addItem(withTitle: "UPPERCASE", action: #selector(actionUppercase), keyEquivalent: "")
    transformMenu.addItem(withTitle: "lowercase", action: #selector(actionLowercase), keyEquivalent: "")
    // ... etc
    let transformItem = NSMenuItem(title: "Transform", action: nil, keyEquivalent: "")
    transformItem.submenu = transformMenu
    menu.addItem(transformItem)

    // Format submenu
    // ...

    // Share submenu
    // ...

    NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? self)
}

@objc private func actionUppercase() {
    applyTransform(TextTransformer.uppercase)
}

private func applyTransform(_ transform: (String) -> String) {
    guard let info = viewModel.currentClippingInfo else { return }
    let transformed = transform(info.content)
    // Write to pasteboard immediately (user can paste the transformed version)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transformed, forType: .string)
    // Optionally insert into ClipboardStore as new entry at top
    Task { @MainActor in
        let rememberNum = UserDefaults.standard.integer(forKey: AppSettingsKeys.rememberNum)
        try? await clipboardStore?.insert(
            content: transformed,
            sourceAppName: "Flycut (transformed)",
            rememberNum: rememberNum
        )
    }
}
```

**Key insight:** After applying a transform, write the result to `NSPasteboard.general` immediately AND insert into `ClipboardStore`. This gives the user the transformed content in both the history AND ready to paste.

### Pattern 3: RTF Generation (QACT-03)

**What:** Use `NSAttributedString` to generate RTF data from plain text and write it to the pasteboard with `.rtf` type.

**Example:**
```swift
// Source: Foundation + AppKit docs
static func copyAsRTF(_ content: String) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    ]
    let attrString = NSAttributedString(string: content, attributes: attrs)
    let range = NSRange(location: 0, length: attrString.length)

    if let rtfData = attrString.rtf(from: range, documentAttributes: [:]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
    }
}
```

**Confidence:** HIGH — `NSAttributedString.rtf(from:documentAttributes:)` is a stable AppKit API since macOS 10.0.

### Pattern 4: Gist Sharing from Quick Action Menu (QACT-03)

**What:** The quick action menu's "Create Gist" item posts `.flycutShareAsGist` — the same notification already handled in `AppDelegate.handleShareAsGist(_:)`. Zero new wiring needed.

**Example:**
```swift
// Reuse existing notification bridge — no new code in AppDelegate needed
@objc private func actionShareAsGist() {
    guard let content = viewModel.currentClipping else { return }
    NotificationCenter.default.post(
        name: .flycutShareAsGist,
        object: nil,
        userInfo: ["content": content]
    )
    hide()
}
```

### Pattern 5: History Export/Import (PERF-01)

**What:** A `ClipboardExportService` that fetches all `Clipping` records, encodes them to JSON, and saves via `NSSavePanel`. Import reads JSON, decodes, and batch-inserts via `ClipboardStore.insert()`.

**Codable export struct:**
```swift
struct ClippingExport: Codable {
    let version: Int            // = 1
    let exportedAt: Date
    let clippings: [ClippingRecord]

    struct ClippingRecord: Codable {
        let content: String
        let sourceAppName: String?
        let sourceAppBundleURL: String?
        let timestamp: Date
    }
}
```

**Export flow:**
```swift
// Source: Foundation docs — verified pattern
@MainActor
func exportHistory(from store: ClipboardStore) async throws -> Data {
    let ids = try await store.fetchAll()
    var records: [ClippingExport.ClippingRecord] = []
    for id in ids {
        let content = await store.content(for: id) ?? ""
        let name = await store.sourceAppName(for: id)
        let url = await store.sourceAppBundleURL(for: id)
        let ts = await store.timestamp(for: id) ?? .now
        records.append(.init(content: content, sourceAppName: name, sourceAppBundleURL: url, timestamp: ts))
    }
    let export = ClippingExport(version: 1, exportedAt: .now, clippings: records)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(export)
}
```

**NSSavePanel (must run on main thread):**
```swift
// Source: AppKit docs
@MainActor
func showExportPanel(data: Data) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "flycut-history-\(Date.now.formatted(.iso8601)).json"
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}
```

**Import flow:** `NSOpenPanel` → `JSONDecoder` → for each record, call `ClipboardStore.insert()` with original timestamp preserved (needs a new `insertWithTimestamp()` method or timestamp-aware variant of `insert()`).

**Important:** Import should preserve original timestamps. This requires adding a `timestamp:` parameter to `ClipboardStore.insert()` — it currently always uses `Date.now` implicitly via `Clipping` init default. The `Clipping` init already accepts `timestamp: Date = .now`, so `ClipboardStore.insert()` needs a new `timestamp` parameter.

### Pattern 6: Adaptive Clipboard Polling (PERF-02)

**What:** Replace `ClipboardMonitor`'s single fixed `Timer` with logic that switches between a fast interval (when user is active) and a slow interval (when idle). Activity is detected via `NSEvent.addGlobalMonitorForEvents`.

**When:** User presses a key, moves mouse, or clicks → reset to fast interval. After N seconds of no events → switch to slow interval.

**Intervals:**
- Active: 0.5s (current default is 1.0s; 0.5s is more responsive)
- Idle: 3.0s (3x reduction in polling frequency)
- Idle threshold: 30 seconds of no activity

**Example:**
```swift
// In ClipboardMonitor — additive change
@Observable @MainActor
final class ClipboardMonitor {
    private var activityMonitor: Any?
    private var lastActivityDate: Date = .now
    private let activeInterval: TimeInterval = 0.5
    private let idleInterval: TimeInterval = 3.0
    private let idleThreshold: TimeInterval = 30.0

    func start() {
        guard !isMonitoring else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        scheduleTimer(interval: activeInterval)
        registerActivityMonitor()
        isMonitoring = true
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkPasteboardAdaptive() }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    private func checkPasteboardAdaptive() {
        // Adapt interval based on activity
        let sinceActivity = Date.now.timeIntervalSince(lastActivityDate)
        let shouldBeIdle = sinceActivity > idleThreshold
        let currentInterval = timer?.timeInterval ?? activeInterval
        let expectedInterval = shouldBeIdle ? idleInterval : activeInterval
        if abs(currentInterval - expectedInterval) > 0.01 {
            scheduleTimer(interval: expectedInterval)
        }
        checkPasteboard()
    }

    private func registerActivityMonitor() {
        activityMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastActivityDate = .now
            }
        }
    }
}
```

**Swift 6 note:** `lastActivityDate` is `@MainActor`-isolated (`ClipboardMonitor` is `@MainActor`). The closure passed to `NSEvent.addGlobalMonitorForEvents` arrives on an arbitrary thread — the `Task { @MainActor }` hop is the correct Swift 6 Sendable-compliant pattern (already used throughout the codebase for the same reason).

**UserDefaults integration:** The existing `clipboardPollingInterval` key stores the active interval. The idle interval should be hardcoded (3× active) or added as a separate setting.

### Anti-Patterns to Avoid

- **SwiftUI `.contextMenu` on NSPanel content:** Not reliably delivered to views inside non-activating `NSPanel`. Use `NSMenu.popUpContextMenu` from `BezelController.rightMouseDown`.
- **Applying transform and immediately calling `pasteAndHide()`:** The user may want to preview the transformed text before pasting. Present a confirmation (or just update the bezel display) rather than auto-pasting.
- **Importing with `ClipboardStore.insert()` in a tight loop without delay:** Multiple rapid inserts may be fine via SwiftData, but the dedup logic can prevent importing duplicate content from the original history — handle carefully (consider skipping dedup on import, or preserving timestamps to prevent false dedup hits).
- **Using `NSSavePanel` from a background actor:** `NSSavePanel.begin()` must be called on the main thread. Always `@MainActor`.
- **Polling with `Timer.scheduledTimer` instead of `RunLoop.current.add(timer, forMode: .common)`:** The codebase already knows this (comment in ClipboardMonitor.swift) — maintain it when adding adaptive scheduling.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| URL encoding | Custom percent-encoding | `String.addingPercentEncoding(withAllowedCharacters:)` | Handles all edge cases per RFC 3986 |
| RTF generation | Custom RTF format string | `NSAttributedString.rtf(from:documentAttributes:)` | AppKit generates spec-compliant RTF |
| JSON pretty-print | Custom indenter | `JSONSerialization.data(withJSONObject:options:.prettyPrinted)` | Handles all JSON edge cases |
| File save dialog | Custom file picker | `NSSavePanel` / `NSOpenPanel` | macOS native; handles sandboxing, bookmarks |
| Activity detection | Custom event loop hook | `NSEvent.addGlobalMonitorForEvents` | Already used in codebase; correct API |
| Title Case | Custom word splitter | `String.capitalized` | Handles Unicode word boundaries |

**Key insight:** Every operation in this phase maps directly to a stdlib or SDK primitive. The complexity is in composition and UX flow, not in low-level implementation.

---

## Common Pitfalls

### Pitfall 1: NSMenu target/action in non-activating NSPanel

**What goes wrong:** `NSMenuItem` with `action:` selector requires the target to be in the responder chain. In a non-activating `NSPanel`, the responder chain may not include the controller if it isn't the `firstResponder`.

**Why it happens:** `NSMenu` items check `respondsToSelector` against the responder chain. `BezelController` (an NSPanel) may not be the target.

**How to avoid:** Either (a) set `item.target = self` explicitly on each `NSMenuItem` (BezelController is always alive), or (b) use closure-based menu items via `NSMenuItem.action` with a trampoline `@objc` method.

**Warning signs:** Menu items appear greyed out even though the function exists.

### Pitfall 2: Writing to NSPasteboard then immediately triggering ClipboardMonitor self-capture

**What goes wrong:** `applyTransform` writes transformed content to `NSPasteboard.general`. `ClipboardMonitor` may fire on the next tick and capture it — leading to a duplicate entry.

**Why it happens:** `blockedChangeCount` mechanism was designed for `PasteService`, not direct pasteboard writes from the quick action menu.

**How to avoid:** Call `clipboardMonitor?.blockedChangeCount = NSPasteboard.general.changeCount` after writing transformed content to the pasteboard — same pattern as `PasteService.paste()`.

**Warning signs:** Transformed clips appear twice in history.

### Pitfall 3: Import skipping all records due to dedup

**What goes wrong:** When importing a history file, all clips match existing history (same content) and dedup move-to-top causes silent "updates" rather than errors — but ordering gets scrambled.

**Why it happens:** `ClipboardStore.insert()` dedup logic matches on `content` alone, ignoring timestamp and source app.

**How to avoid:** For import, either (a) disable dedup temporarily by passing a flag, or (b) check content uniqueness against existing records before importing, or (c) import only records not already in history. Option (c) is safest and most user-friendly.

### Pitfall 4: NSSavePanel on non-main thread

**What goes wrong:** `NSSavePanel.begin()` crashes or shows nothing when called from a non-main-thread context.

**Why it happens:** AppKit UI operations are main-thread only.

**How to avoid:** Always wrap `NSSavePanel`/`NSOpenPanel` in `@MainActor` or `DispatchQueue.main.async`. `ClipboardExportService` should be `@MainActor`.

### Pitfall 5: Adaptive polling timer recreation on every cycle

**What goes wrong:** If `scheduleTimer` is called on every `checkPasteboardAdaptive()` tick to "re-check" the interval, it invalidates and recreates the timer every 0.5–3s — potential for timer drift and unnecessary overhead.

**Why it happens:** Guard comparison with tolerance (e.g., `abs(current - expected) > 0.01`) prevents unnecessary recreation. Without the guard, recreation happens on every tick.

**How to avoid:** Compare current timer interval against expected interval and only call `scheduleTimer` when a change is needed (see Pattern 6 example above).

### Pitfall 6: String.capitalized vs Title Case

**What goes wrong:** `"HELLO WORLD".capitalized` returns `"Hello World"` in Swift — it first lowercases then capitalizes. This is the desired behavior for Title Case. But `"hELLO".capitalized` → `"Hello"` which is correct. Edge case: `"it's a test".capitalized` → `"It'S A Test"` (apostrophe-boundary issue).

**Why it happens:** `capitalized` follows Unicode word boundary rules which treat `'` as a word separator.

**How to avoid:** Accept `String.capitalized` behavior as-is — it matches user expectation for "Title Case" in nearly all practical clipboard content. Document the limitation in code comments.

---

## Code Examples

Verified patterns from official sources:

### URL Encoding/Decoding
```swift
// Source: Swift stdlib docs — String.addingPercentEncoding
let encoded = "hello world & more".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
// → "hello%20world%20&%20more"  (.urlQueryAllowed keeps & as-is; use .urlHostAllowed to encode &)

// For full URL component encoding (encodes & too):
let fullyEncoded = "hello world & more".addingPercentEncoding(withAllowedCharacters: .alphanumerics)

let decoded = "hello%20world".removingPercentEncoding
// → "hello world"
```

### NSMenu popup from NSPanel
```swift
// Source: AppKit NSMenu docs — NSMenu.popUpContextMenu
// CRITICAL: pass the contentView (not self) as the view argument
NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? NSView())
```

### RTF to Pasteboard
```swift
// Source: Foundation NSAttributedString docs
let attrString = NSAttributedString(string: content, attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
])
if let rtfData = attrString.rtf(from: NSRange(location: 0, length: attrString.length),
                                  documentAttributes: [:]) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setData(rtfData, forType: .rtf)
    // Block self-capture (same pattern as PasteService)
    clipboardMonitor?.blockedChangeCount = NSPasteboard.general.changeCount
}
```

### JSON Export with iso8601 dates
```swift
// Source: Foundation JSONEncoder docs
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
```

### NSSavePanel (main thread only)
```swift
// Source: AppKit NSSavePanel docs
@MainActor
func showSavePanel(defaultName: String, completion: @escaping (URL?) -> Void) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = defaultName
    panel.canCreateDirectories = true
    panel.begin { response in
        completion(response == .OK ? panel.url : nil)
    }
}
```

### NSOpenPanel for import
```swift
// Source: AppKit NSOpenPanel docs
@MainActor
func showOpenPanel(completion: @escaping (URL?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { response in
        completion(response == .OK ? panel.urls.first : nil)
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Fixed-interval NSTimer | Adaptive interval with NSEvent activity monitor | macOS 10.12+ (NSEvent global monitors stable) | Lower idle CPU |
| `NSAttributedString(string:attributes:).rtfFromRange(_:documentAttributes:)` | `NSAttributedString.rtf(from:documentAttributes:)` | Swift 3 (renamed) | Current API |
| `Timer.scheduledTimer` | `RunLoop.current.add(timer, forMode: .common)` | Used since Phase 2 in this project | Fires during menu tracking |
| `NSSavePanel.runModal()` | `NSSavePanel.begin { }` async completion | macOS 10.9+ | Non-blocking, correct for menu bar apps |

**Deprecated/outdated:**
- `NSTimer` (Obj-C) — use `Timer` in Swift
- `NSAttributedString.rtfFromRange(_:documentAttributes:)` — use `.rtf(from:documentAttributes:)` (Swift rename)
- `NSSavePanel.runModal()` — blocks the run loop; use `.begin { }` for accessory-policy apps

---

## Open Questions

1. **Should transform result auto-paste or require a second action?**
   - What we know: The current bezel requires Enter to paste; transforms should be consistent
   - What's unclear: Does the user want to verify the transform result before pasting?
   - Recommendation: Transform → insert transformed content into ClipboardStore AND copy to pasteboard → update bezel selection to the new transformed clip → user presses Enter to paste normally. This matches the "preview before paste" model of the existing bezel.

2. **Should import merge with existing history or replace it?**
   - What we know: ClipboardStore.insert() with dedup will silently skip exact duplicates
   - What's unclear: User expectation — "restore" (clear first) vs "merge" (add to existing)
   - Recommendation: Offer both options in an NSAlert before import: "Merge" (default) and "Replace" (clear all then import).

3. **Where does the export/import UI live?**
   - What we know: MenuBarView already has Clear All; Settings has many panels
   - What's unclear: Whether to add to Settings or to MenuBarView
   - Recommendation: Add to Settings > General or a new "History" tab — keeps MenuBarView uncluttered and co-locates with savePreference setting.

4. **ClipboardStore.insert() timestamp parameter for import**
   - What we know: `Clipping` init accepts `timestamp: Date = .now`; `ClipboardStore.insert()` does not expose timestamp
   - What's unclear: Whether adding a `timestamp:` param breaks any actor isolation contracts
   - Recommendation: Add `timestamp: Date = .now` to `ClipboardStore.insert()` — additive, backward compatible, no actor isolation change needed.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (existing in FlycutTests target) |
| Config file | FlycutSwift.xcodeproj (existing test target) |
| Quick run command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/TextTransformerTests` |
| Full suite command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| QACT-01 | uppercase/lowercase/titleCase/trim/urlEncode/urlDecode transforms produce correct output | unit | `xcodebuild test ... -only-testing FlycutTests/TextTransformerTests` | ❌ Wave 0 |
| QACT-02 | wrapInQuotes/markdownCodeBlock/jsonPrettyPrint produce correct output; invalid JSON unchanged | unit | `xcodebuild test ... -only-testing FlycutTests/TextTransformerTests` | ❌ Wave 0 |
| QACT-03 | RTF generation produces non-nil data from plain text; Gist share posts notification | unit (RTF) + manual (Gist) | `xcodebuild test ... -only-testing FlycutTests/TextTransformerTests` | ❌ Wave 0 |
| PERF-01 | Export encodes all clippings to valid JSON; import round-trip restores all records | unit | `xcodebuild test ... -only-testing FlycutTests/ClipboardExportServiceTests` | ❌ Wave 0 |
| PERF-02 | Timer interval adapts from active to idle after threshold; restores on activity | unit (timer logic) + manual (CPU observation) | `xcodebuild test ... -only-testing FlycutTests/ClipboardMonitorTests` | ✅ exists (will need new test methods) |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/TextTransformerTests -only-testing FlycutTests/ClipboardExportServiceTests`
- **Per wave merge:** `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `FlycutTests/TextTransformerTests.swift` — covers QACT-01, QACT-02, QACT-03 (RTF)
- [ ] `FlycutTests/ClipboardExportServiceTests.swift` — covers PERF-01 export/import round-trip
- [ ] `FlycutSwift/Services/TextTransformer.swift` — new pure-value type
- [ ] `FlycutSwift/Services/ClipboardExportService.swift` — new export/import service
- [ ] New test methods in `FlycutTests/ClipboardMonitorTests.swift` — adaptive polling (PERF-02)

---

## Sources

### Primary (HIGH confidence)

- Swift stdlib String docs — `uppercased()`, `lowercased()`, `capitalized`, `addingPercentEncoding`, `removingPercentEncoding` — all verified as standard Swift 6 APIs
- Apple Foundation docs — `JSONEncoder`/`JSONDecoder`, `dateEncodingStrategy`, `outputFormatting` — verified stable macOS APIs
- AppKit NSMenu docs — `NSMenu.popUpContextMenu(_:with:for:)`, `NSMenuItem.target` — verified AppKit pattern
- AppKit NSAttributedString docs — `.rtf(from:documentAttributes:)` — verified since macOS 10.0
- AppKit NSSavePanel/NSOpenPanel docs — `.begin { }` async completion variant — verified macOS 10.9+
- Existing codebase (BezelController.swift) — `NSEvent.addGlobalMonitorForEvents` pattern for `flagsMonitor` — confirmed correct approach for global event monitoring in non-activating panels
- Existing codebase (ClipboardMonitor.swift) — `RunLoop.current.add(timer, forMode: .common)` — confirmed correct approach for timer in menu-open RunLoop mode

### Secondary (MEDIUM confidence)

- JSONSerialization.data(withJSONObject:options:.prettyPrinted) for JSON pretty-print — standard API, minor edge case with non-JSON input strings handled by guard+fallback
- `String.capitalized` Title Case behavior — documented behavior with known apostrophe edge case; acceptable for clipboard content

### Tertiary (LOW confidence)

- Idle threshold of 30 seconds and idle interval of 3.0s — reasonable defaults based on common clipboard manager conventions; should be validated by user testing

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are existing macOS SDK; no new SPM dependencies
- Architecture: HIGH — additive patterns consistent with Phases 3–5 conventions (BezelController overrides, notification bridges, @ModelActor store methods)
- Pitfalls: HIGH — self-capture prevention and NSMenu target/action are codebase-specific verified pitfalls; adaptive timer pitfalls are standard Timer patterns

**Research date:** 2026-03-12
**Valid until:** 2026-06-12 (stable macOS APIs; no fast-moving dependencies)
