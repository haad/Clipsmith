# Phase 11: App Launcher - Research

**Researched:** 2026-05-25
**Domain:** macOS app discovery (FileManager), NSWorkspace launch API, Swift 6 / non-activating NSPanel bezel pattern
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Scan all user-visible app locations: `/Applications`, `~/Applications`, `/System/Applications`, `/Applications/Utilities`, `/System/Applications/Utilities`. This covers both user-installed and MAS system apps without relying on deprecated Launch Services C APIs.
- **D-02:** Cache the app list on Clipsmith startup. Refresh the cache asynchronously each time the launcher bezel is opened. Apps installed/removed since last open appear on the next bezel open.
- **D-03:** Bezel opens in instant search mode — typing immediately filters the app list. Search field has focus as soon as the bezel appears.
- **D-04:** When no text is typed, show the 5 most recently launched apps (tracked in UserDefaults by bundle ID).
- **D-05:** Results ranked by `FuzzyMatcher` score first; when scores are close (within ~0.1), recently-launched apps get a recency boost.
- **D-06:** Rows display app icon (`NSWorkspace.icon(forFile:)`) + app name. Icons ~24pt square, consistent row height.
- **D-07:** No default hotkey binding. User must configure their own binding.
- **D-08:** Non-activating NSPanel (`.nonactivatingPanel` + `canBecomeKey = true`) — same pattern as `BezelController` and `PromptBezelController`.
- **D-09:** On Enter: close the bezel immediately, then call `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` which activates the launched app.
- **D-10:** Behind `AppSettingsKeys.appLauncherEnabled` (`@AppStorage`, default `false`). Hotkey registration guarded at the invocation site in AppDelegate, matching the `docLookupEnabled` pattern.

### Claude's Discretion

None — all areas had explicit user decisions.

### Deferred Ideas (OUT OF SCOPE)

- Inline launcher calculations / currency / unit conversions — deferred to a future phase.
- File search, process management, web search, unit conversions.
</user_constraints>

---

## Summary

Phase 11 implements a fourth bezel in the app: a keyboard-driven app launcher that scans macOS application directories, filters them by name using `FuzzyMatcher`, and launches the selected app via `NSWorkspace`. The implementation is a near-exact structural clone of `PromptBezelController` / `PromptBezelViewModel` / `PromptBezelView` with two novel elements: the `AppScannerService` (file-system scan + cache) and the recency-boost ranking in `AppLaunchViewModel`.

The technical foundation is completely established in the existing codebase. Every API, pattern, and idiom needed already exists in a prior phase. The planner can map each decision directly to a concrete code change.

**Primary recommendation:** Copy the `PromptBezel*` trio as the structural template, strip SwiftData dependencies entirely (no `@Query`, no model container needed), add `AppScannerService` for file-system scanning, and wire into AppDelegate following the `docLookupEnabled` guard pattern exactly.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| App discovery & caching | Service (`AppScannerService`) | — | Pure filesystem scan with no UI dependency; background-async safe |
| Search & ranking | ViewModel (`AppLaunchViewModel`) | — | `FuzzyMatcher` + recency boost is pure logic; no AppKit dependency |
| Hotkey registration | AppDelegate | — | All global hotkeys are registered in AppDelegate (existing pattern) |
| Feature flag guard | AppDelegate (hotkey handler) | GeneralSettingsTab | Guard at invocation site, not registration site |
| Icon loading | ViewModel (lazy, cached) | `NSWorkspace` | `icon(forFile:)` is slow; must cache per URL; load on background thread and update `@Observable` state |
| Recent-app tracking | `AppScannerService` | UserDefaults | Persist last 5 bundle IDs; update on every successful launch |
| Panel display | `AppLaunchController` (NSPanel) | — | Non-activating pattern identical to PromptBezelController |
| SwiftUI content | `AppLaunchView` | — | Hosted in `NSHostingView` with `sizingOptions = []` |
| Settings toggle | `GeneralSettingsTab` | — | Feature flag toggle added to existing Features section |
| Hotkey recorder | `HotkeySettingsTab` | — | New `KeyboardShortcuts.Recorder` row |

---

## Standard Stack

This phase uses **only APIs and libraries already in the project**. No new SPM dependencies are introduced.

### Core APIs

| API | Where used | Notes |
|-----|-----------|-------|
| `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options:)` | `AppScannerService` | Enumerate `.app` bundles one level deep in each search path [VERIFIED: Apple header macOS 15.4 SDK] |
| `NSWorkspace.shared.icon(forFile:)` | `AppScannerService` / `AppLaunchViewModel` | Returns `NSImage` icon for a file path; slow on first call per app; must be called on a background thread and result cached [VERIFIED: Apple header macOS 15.4 SDK] |
| `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` | `AppLaunchController` | Preferred async launch API, available macOS 10.15+; `configuration.activates = true` (default) brings target app to front [VERIFIED: Apple header macOS 15.4 SDK] |
| `NSWorkspaceOpenConfiguration` | `AppLaunchController` | `activates` property defaults to `true` — no extra configuration needed for standard "launch and activate" [VERIFIED: Apple header macOS 15.4 SDK] |
| `KeyboardShortcuts` | `KeyboardShortcutNames.swift`, `AppDelegate` | Already integrated SPM dependency; add `.appLauncher` name [ASSUMED — version confirmed working in prior phases] |
| `FuzzyMatcher` | `AppLaunchViewModel` | Existing service; character-subsequence matching with consecutive-bonus scoring [VERIFIED: codebase grep] |
| `UserDefaults` | Recent-app tracking | Store `[String]` (bundle IDs) under `AppSettingsKeys.recentAppBundleIDs` [VERIFIED: codebase pattern] |

### No New Dependencies

This phase introduces zero new SPM packages. All required functionality is available via:
- AppKit (`NSWorkspace`, `NSPanel`, `NSWorkspaceOpenConfiguration`, `FileManager`)
- Foundation (`UserDefaults`, `URL`)
- SwiftUI (`@Observable`, `NSHostingView`, `TextField`, `FocusState`)
- Existing project code (`FuzzyMatcher`, `KeyboardShortcuts`)

**Installation:** No `npm install` / `swift package add` needed.

---

## Package Legitimacy Audit

> Not applicable — this phase introduces no new external packages.

---

## Architecture Patterns

### System Architecture Diagram

```
User presses hotkey
        │
        ▼
AppDelegate.onKeyDown(.appLauncher)
        │  checks: appLauncherEnabled flag
        ▼
AppLaunchController.show()
        │
        ├── AppScannerService.refreshIfNeeded()  ──async──►  FileManager scan
        │                                                      /Applications + subdirs
        │                                                      /System/Applications + subdirs
        │                                                      ~/Applications
        │                                                      ◄── [AppEntry] returned on MainActor
        ▼
AppLaunchViewModel.apps = [AppEntry]
        │  (searchText == "") → show recentApps (top 5 by UserDefaults)
        │  (searchText != "") → FuzzyMatcher.score(app.name, query:)
        │                       + recency boost when |delta| < 0.1
        ▼
AppLaunchView (SwiftUI in NSHostingView)
        │  TextField (always focused, first responder)
        │  List of AppEntry rows: icon + name, selection highlight
        ▼
User presses Enter
        │
        ▼
AppLaunchController.launchSelected()
        │  hide() immediately
        │  AppScannerService.recordLaunch(bundleID:)  → UserDefaults update
        ▼
NSWorkspace.shared.openApplication(at: url, configuration: config)
        │  config.activates = true (default)
        ▼
Target app comes to front
```

### Recommended Project Structure

New files to create:

```
Clipsmith/
├── Services/
│   └── AppScannerService.swift        # App discovery, icon loading, recency tracking
├── Views/
│   ├── AppLaunchController.swift      # NSPanel subclass (bezel 4)
│   ├── AppLaunchViewModel.swift       # @Observable @MainActor — search, ranking, state
│   └── AppLaunchView.swift            # SwiftUI content view
```

Modified files:

```
Clipsmith/
├── App/
│   └── AppDelegate.swift              # Add appLaunchController, hotkey registration
├── Settings/
│   ├── AppSettingsKeys.swift          # Add appLauncherEnabled, recentAppBundleIDs
│   └── KeyboardShortcutNames.swift    # Add .appLauncher Name
├── Views/
│   ├── MenuBarView.swift              # Add "App Launcher..." button + Notification.Name
│   └── Settings/
│       ├── HotkeySettingsTab.swift    # Add KeyboardShortcuts.Recorder for .appLauncher
│       └── GeneralSettingsTab.swift   # Add appLauncherEnabled toggle to Features section
```

### Pattern 1: AppEntry Value Type

The `AppScannerService` produces `AppEntry` structs — the same Sendable value-type pattern used for `ClippingInfo` and `PromptInfo`:

```swift
// Source: mirrors ClippingInfo (BezelViewModel.swift) and PromptInfo (PromptBezelViewModel.swift)
struct AppEntry: Sendable, Identifiable {
    var id: URL { url }          // app bundle URL is unique
    let name: String             // CFBundleName from bundle, fallback to filename sans .app
    let url: URL                 // absolute URL to .app bundle
    let bundleID: String?        // CFBundleIdentifier (nil for malformed bundles)
    var icon: NSImage?           // nil until loaded asynchronously; triggers @Observable update
}
```

### Pattern 2: AppScannerService

`AppScannerService` is `@MainActor @Observable`, matching `GistService` and `PromptSyncService`:

```swift
// Source: codebase pattern from GistService.swift and PromptSyncService.swift
@MainActor
@Observable
final class AppScannerService {
    private(set) var apps: [AppEntry] = []
    private(set) var recentBundleIDs: [String] = []   // last 5 launched, in order

    /// Call once at app startup to warm the cache.
    func loadInitially() async { ... }

    /// Call each time the launcher bezel opens. Rescans and updates apps.
    func refresh() async { ... }

    /// Records a launch. Prepends bundleID to recentBundleIDs (max 5), saves to UserDefaults.
    func recordLaunch(bundleID: String) { ... }
}
```

**Scan implementation** — do NOT use `FileManager.enumerator` for deep traversal because `.app` bundles themselves contain a directory tree that would be enumerated. Instead, use `contentsOfDirectory` at depth=1 for the top-level application directories, plus depth=1 within `Utilities` subdirectories:

```swift
// Source: [ASSUMED] — derived from CONTEXT.md D-01 and FileManager API knowledge
// Search paths (CONTEXT.md D-01):
let searchPaths: [URL] = [
    URL(fileURLWithPath: "/Applications"),
    URL(fileURLWithPath: "/Applications/Utilities"),
    URL(fileURLWithPath: "/System/Applications"),
    URL(fileURLWithPath: "/System/Applications/Utilities"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
]

// Enumerate each path: one level only, filter for .app extension
for path in searchPaths {
    let contents = try? FileManager.default.contentsOfDirectory(
        at: path,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    let apps = contents?.filter { $0.pathExtension == "app" } ?? []
    // ...
}
```

### Pattern 3: Icon Loading Strategy

`NSWorkspace.shared.icon(forFile:)` performs disk I/O (reads resource forks, app bundle metadata). It is fast for most apps (~0.01s) but can be slow for complex bundles. [CITED: cocoadev.github.io/SomethingFasterThanWorkspacesIconForFile]

**Strategy:** Load icons asynchronously after the app list is computed. Store `icon: NSImage?` in `AppEntry`. The view shows a placeholder icon (`NSImage(systemSymbolName: "app.dashed")` or similar) until the real icon loads.

```swift
// Source: [ASSUMED] — standard async icon loading pattern for macOS launchers
Task.detached(priority: .userInitiated) {
    var loadedEntries = entries
    for i in loadedEntries.indices {
        let icon = NSWorkspace.shared.icon(forFile: loadedEntries[i].url.path)
        loadedEntries[i].icon = icon
    }
    await MainActor.run {
        self.apps = loadedEntries
    }
}
```

Alternative (simpler for this scale): since there are only ~60-130 `.app` bundles across all search paths, load icons synchronously after scanning on a `Task.detached` background task. The total time is typically < 2 seconds and the bezel only appears after the cache is warm.

### Pattern 4: AppLaunchController Init — No SwiftData

Unlike `BezelController` (which injects a `ModelContainer`) and `PromptBezelController`, `AppLaunchController` has **no SwiftData dependency**. The init is simpler:

```swift
// Source: mirrors PromptBezelController.swift minus modelContainer injection
init() {
    super.init(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false

    let hostingView = NSHostingView(rootView: AppLaunchView(viewModel: viewModel))
    hostingView.sizingOptions = []   // CRITICAL: prevents infinite constraint loop crash
    contentView = hostingView
}
```

### Pattern 5: Launch via NSWorkspace (macOS 10.15+ API)

```swift
// Source: [VERIFIED: Apple NSWorkspace.h macOS 15.4 SDK]
// openApplication(at:configuration:completionHandler:) available macOS 10.15+
// config.activates defaults to true — target app comes to front automatically
func launchSelected() {
    guard let entry = viewModel.currentApp else {
        hide()
        return
    }
    hide()   // dismiss bezel FIRST, then launch
    if let bundleID = entry.bundleID {
        appScannerService?.recordLaunch(bundleID: bundleID)
    }
    let config = NSWorkspaceOpenConfiguration()
    // config.activates = true by default — no override needed
    NSWorkspace.shared.openApplication(
        at: entry.url,
        configuration: config,
        completionHandler: { _, error in
            if let error {
                // Log only — never crash on launch failure
                logger.error("Failed to launch app: \(error.localizedDescription)")
            }
        }
    )
}
```

### Pattern 6: sendEvent Intercept — Always-search Mode

Because the launcher is always in search mode (D-03), the `sendEvent` override is simpler than `BezelController`. All printable characters flow to the TextField; only navigation keys and Return/Escape are intercepted:

```swift
// Source: mirrors PromptBezelController.swift sendEvent, simplified for search-always mode
override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown {
        switch event.keyCode {
        case 53:            // Escape
            hide(); return
        case 36, 76:        // Return, Enter
            launchSelected(); return
        case 125, 126, 123, 124, 121, 116, 119, 115:   // Arrow keys, Page/Home/End
            keyDown(with: event); return
        default:
            break
        }
    }
    super.sendEvent(event)
}
```

### Pattern 7: Recency Boost Ranking

The ranking combines fuzzy score with a recency boost when scores are close:

```swift
// Source: [ASSUMED] — derived from CONTEXT.md D-05 ("within ~0.1")
func rankedApps(for query: String) -> [AppEntry] {
    guard !query.isEmpty else { return recentApps() }

    let recentIDs = Set(appScannerService.recentBundleIDs)
    let scored: [(AppEntry, Double)] = apps.compactMap { app in
        guard var score = FuzzyMatcher.score(app.name, query: query) else { return nil }
        if let bid = app.bundleID, recentIDs.contains(bid) {
            score += 0.1   // recency boost — small enough not to override strong matches
        }
        return (app, score)
    }
    return scored.sorted { $0.1 > $1.1 }.map(\.0)
}

func recentApps() -> [AppEntry] {
    let recentIDs = appScannerService.recentBundleIDs   // already ordered [most recent first]
    // Map IDs back to AppEntry objects (preserve recency order)
    var result: [AppEntry] = []
    for id in recentIDs {
        if let app = apps.first(where: { $0.bundleID == id }) {
            result.append(app)
        }
    }
    return result
}
```

### Pattern 8: Feature Flag Guard (docLookupEnabled model)

```swift
// Source: AppDelegate.swift — existing docLookupEnabled guard pattern [VERIFIED: codebase]
KeyboardShortcuts.onKeyDown(for: .appLauncher) { [weak self] in
    Task { @MainActor in
        guard let self else { return }
        guard UserDefaults.standard.bool(forKey: AppSettingsKeys.appLauncherEnabled) else { return }
        if self.appLaunchController.isVisible {
            self.appLaunchController.viewModel.navigateDown()
        } else {
            self.appLaunchController.show()
        }
    }
}
```

### Anti-Patterns to Avoid

- **Using `NSWorkspace.runningApplications`** — this only lists currently running apps, not all installed apps. Not suitable for an app launcher.
- **Using `LSCopyAllApplicationURLs` / Launch Services C APIs** — deprecated in macOS 12. The CONTEXT.md explicitly rules these out (D-01).
- **Using `FileManager.enumerator` for recursive traversal** — `.app` bundles are directories; recursing into them produces thousands of file hits. Use shallow `contentsOfDirectory` at each search path only.
- **Loading icons synchronously on main thread** — `NSWorkspace.icon(forFile:)` touches disk. Must be done on a background task.
- **Injecting ModelContainer** — the app launcher has no SwiftData dependency. Do not copy the BezelController `init(modelContainer:)` pattern; use a no-arg `init()` instead.
- **Setting `styleMask` after init** — `.nonactivatingPanel` must be in the `super.init` call (established pitfall from prior phases, documented in STATE.md).
- **Forgetting `hostingView.sizingOptions = []`** — this is required to prevent the infinite constraint update loop crash (documented in BezelController.swift comment).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fuzzy name matching | Custom string match | `FuzzyMatcher.score(_:query:)` | Already exists; consecutive-bonus scoring is correct for app name matching |
| Hotkey registration | CGEventTap wrapper | `KeyboardShortcuts.onKeyDown(for:)` | Already integrated; standard pattern for all other hotkeys |
| Icon retrieval | Custom icon extraction | `NSWorkspace.shared.icon(forFile:)` | System API; handles all edge cases including `.icns`, resource fork, and per-file custom icons |
| App launch | Process launch via `Process()` | `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` | System API; handles activation, single-instance reuse, Gatekeeper, sandboxing |
| Recent-app persistence | Custom storage layer | `UserDefaults` with JSON-encoded `[String]` | Same pattern used for `promptLibraryVariables` and other settings |
| Settings toggle | Custom pref UI | `@AppStorage` + `Toggle` in `GeneralSettingsTab` | Established pattern for all feature flags |

**Key insight:** The app launcher is a structural clone of the Prompt Bezel. The only genuinely new code is `AppScannerService` (file-system scan) and the recency boost calculation in `AppLaunchViewModel`. Everything else is a direct copy-and-adapt of existing patterns.

---

## Common Pitfalls

### Pitfall 1: Scanning .app Subdirectories Recursively
**What goes wrong:** Using `FileManager.enumerator(at:includingPropertiesForKeys:)` instead of `contentsOfDirectory` recurses INTO `.app` bundles (which are directories), producing thousands of file system hits and finding `Contents/MacOS/AppName` executables as "apps."
**Why it happens:** `.app` bundles look like directories to FileManager.
**How to avoid:** Use `contentsOfDirectory(at:includingPropertiesForKeys:options:)` at depth=1 on each search path. Filter for `url.pathExtension == "app"` immediately. Only the `Utilities` subdirectory within `/Applications` and `/System/Applications` needs one level of recursion into it; the top-level paths do not recurse further.
**Warning signs:** App list contains items like "Info.plist", "Resources", binary executables.

### Pitfall 2: Icon Loading on Main Thread
**What goes wrong:** Calling `NSWorkspace.shared.icon(forFile:)` synchronously during `AppScannerService.refresh()` on `@MainActor` blocks the main thread for seconds when loading icons for complex bundles (VS Code can take 4-5s per the search results).
**Why it happens:** `icon(forFile:)` reads resource forks and bundle metadata from disk.
**How to avoid:** Run icon loading in a `Task.detached(priority: .userInitiated)` block. Update `apps` on `MainActor` after loading is complete (or stream updates one-by-one if needed).
**Warning signs:** Bezel hangs for 1-5 seconds after opening before responding to keystrokes.

### Pitfall 3: .nonactivatingPanel styleMask After Init
**What goes wrong:** Setting `styleMask` or adding `.nonactivatingPanel` after `super.init()` has no effect. The panel steals keyboard focus from the previously-active app.
**Why it happens:** WindowServer reads the styleMask at panel creation time only.
**How to avoid:** Pass `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]` in the `super.init()` call. (Documented in existing `BezelController.swift` and STATE.md.)
**Warning signs:** Typing in the launcher's TextField causes the previously-active app to lose its cursor/selection.

### Pitfall 4: Missing `hostingView.sizingOptions = []`
**What goes wrong:** NSHostingView tries to negotiate min/max content size with the panel, triggering an infinite constraint update loop: `updateWindowContentSizeExtremaIfNecessary → sizeThatFits → graphDidChange → setNeedsUpdateConstraints → repeat` → crash.
**Why it happens:** Default `sizingOptions` tries to size the window to fit the SwiftUI content.
**How to avoid:** Always set `hostingView.sizingOptions = []` immediately after creating the `NSHostingView`.
**Warning signs:** App crashes with an `NSException` involving `updateConstraints`.

### Pitfall 5: Bundle Name vs. Filename
**What goes wrong:** Using `url.deletingPathExtension().lastPathComponent` (the filename without `.app`) instead of the `CFBundleName` from `Info.plist`. Results in display names like "Brave_Browser" instead of "Brave Browser", or UUID-named bundles from MAS.
**Why it happens:** FileManager enumerates filenames, not bundle metadata.
**How to avoid:** Use `Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String` with a fallback to the filename sans `.app` for bundles missing `CFBundleName`.
**Warning signs:** App names contain underscores or cryptic identifiers.

### Pitfall 6: Showing Empty Launcher on First Open
**What goes wrong:** `AppScannerService.loadInitially()` is called asynchronously at startup; if the user opens the launcher within the first second of app launch, `apps` may be empty.
**Why it happens:** The initial scan is async.
**How to avoid:** `AppLaunchController.show()` calls `refresh()` synchronously before presenting, then shows a "Scanning apps..." placeholder if the list is still empty. Alternatively, the initial scan can block the show() until complete (acceptable since it takes < 1s for ~125 apps).

### Pitfall 7: Duplicate Apps Across Scan Paths
**What goes wrong:** The same app appearing in both `/Applications` and `/System/Applications` (or a symlink) shows up twice in the results.
**Why it happens:** Multiple search paths may contain the same bundle via symlinks or if an app is installed in multiple locations.
**How to avoid:** After scanning, deduplicate by bundle ID (`CFBundleIdentifier`). When bundle ID is nil (malformed bundles), fall back to deduplication by resolved URL path.

---

## Code Examples

### AppEntry Struct
```swift
// Source: mirrors ClippingInfo (BezelViewModel.swift) [VERIFIED: codebase]
struct AppEntry: Sendable, Identifiable {
    var id: URL { url }
    let name: String
    let url: URL
    let bundleID: String?
    var icon: NSImage?
}
```

### AppScannerService — Scan and Dedup
```swift
// Source: [ASSUMED] derived from FileManager API and codebase patterns
// Run this on a background Task.detached, then publish results on MainActor
private func scanApps() async -> [AppEntry] {
    let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent("Applications"),
    ]
    var seen: Set<String> = []
    var result: [AppEntry] = []

    for pathStr in searchPaths {
        let dirURL = URL(fileURLWithPath: pathStr)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { continue }

        for url in contents where url.pathExtension == "app" {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            let dedupeKey = bundleID ?? url.resolvingSymlinksInPath().path

            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)

            let name = (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent

            result.append(AppEntry(name: name, url: url, bundleID: bundleID, icon: nil))
        }
    }

    return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
}
```

### NSWorkspace Launch (verified API)
```swift
// Source: [VERIFIED: Apple NSWorkspace.h macOS 15.4 SDK]
// openApplicationAtURL:configuration:completionHandler: — macOS 10.15+
// config.activates defaults to true
let config = NSWorkspaceOpenConfiguration()
NSWorkspace.shared.openApplication(
    at: entry.url,
    configuration: config,
    completionHandler: { _, error in
        if let error { logger.error("App launch failed: \(error.localizedDescription)") }
    }
)
```

### Recent Apps Persistence
```swift
// Source: mirrors promptLibraryVariables JSON storage pattern [VERIFIED: codebase]
// Under AppSettingsKeys.recentAppBundleIDs: stores [String] (max 5 bundle IDs)
func recordLaunch(bundleID: String) {
    var recent = UserDefaults.standard.stringArray(forKey: AppSettingsKeys.recentAppBundleIDs) ?? []
    recent.removeAll { $0 == bundleID }
    recent.insert(bundleID, at: 0)
    if recent.count > 5 { recent = Array(recent.prefix(5)) }
    UserDefaults.standard.set(recent, forKey: AppSettingsKeys.recentAppBundleIDs)
}
```

### HotkeySettingsTab Addition
```swift
// Source: HotkeySettingsTab.swift — existing pattern [VERIFIED: codebase]
KeyboardShortcuts.Recorder(
    "App Launcher",
    name: .appLauncher
)
```

### GeneralSettingsTab — Features Section Addition
```swift
// Source: GeneralSettingsTab.swift — docLookupEnabled pattern [VERIFIED: codebase]
Toggle("App Launcher", isOn: $appLauncherEnabled)
    .help("Enable keyboard-driven app launcher (no default hotkey — configure in Shortcuts tab).")
```

### MenuBarView Notification Name
```swift
// Source: MenuBarView.swift — existing Notification.Name pattern [VERIFIED: codebase]
static let clipsmithOpenAppLauncher = Notification.Name("clipsmithOpenAppLauncher")
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `LSCopyAllApplicationURLs` (Launch Services) | `FileManager.contentsOfDirectory` per path | macOS 12 deprecated | LSCopyAllApplicationURLs is available but deprecated; FileManager approach is correct |
| `launchApplication(at:options:configuration:)` | `openApplication(at:configuration:completionHandler:)` | macOS 11 | Old API deprecated macOS 11; new API is callback-based, clean async/await bridgeable |
| `NSWorkspace.runningApplications` | File system scan for all installed apps | N/A | `runningApplications` lists only currently running apps — not useful for a launcher |

**Deprecated/outdated:**
- `launchApplication(at:options:configuration:error:)` — deprecated macOS 11; replaced by `openApplication(at:configuration:completionHandler:)` [VERIFIED: Apple NSWorkspace.h]
- `LSCopyAllApplicationURLs` — the Launch Services C API; still works but Apple-deprecated. The CONTEXT.md explicitly avoids it (D-01). [ASSUMED — Apple's deprecation of LS APIs is ongoing]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The recency boost magnitude of `+0.1` prevents close-score ties from flipping | Architecture Patterns / Pattern 7 | Easy to tune at implementation time; not a blocking risk |
| A2 | Total icon loading time for ~125 apps is < 2 seconds on typical hardware | Pitfall 2 | If slower, switch to streaming icon updates per-app rather than batch |
| A3 | The `AppScannerService` fits cleanly as `@MainActor @Observable` without requiring a separate `ModelActor` | Architecture Patterns | Service has no SwiftData; if thread safety issues arise, promote to `actor` |
| A4 | `CFBundleName` is present in `Info.plist` for all non-malformed apps | Code Examples | Fallback to filename sans `.app` is already included |
| A5 | No MAS-sandboxed apps prevent `FileManager.contentsOfDirectory` from seeing them | Architecture Patterns | Clipsmith has no sandbox (`ENABLE_APP_SANDBOX = NO`); full filesystem access confirmed |

---

## Open Questions

1. **Panel sizing for the app launcher**
   - What we know: Other bezels use the user-configurable `bezelWidth`/`bezelHeight` from UserDefaults.
   - What's unclear: Should the app launcher respect the same size settings (correct UX), or use a fixed size (simpler)?
   - Recommendation: Reuse `bezelWidth`/`bezelHeight` from `configureAndPresent()` — same as PromptBezelController. No new size settings needed.

2. **Icon size in the row**
   - What we know: CONTEXT.md says ~24pt square icons with consistent row height.
   - What's unclear: Should icons match a standard SwiftUI `Label` size or be explicitly `.frame(width: 24, height: 24)`?
   - Recommendation: Use `.frame(width: 24, height: 24)` with `.resizable()` + `.scaledToFit()` on an `Image` wrapping the NSImage. Set `rowHeight` consistently via a `VStack` with `padding(.vertical, 6)`.

3. **What to show when the app list is still loading at bezel open**
   - What we know: The initial scan is async; a second async refresh fires on each open.
   - What's unclear: How to handle the race where the user opens the launcher before `loadInitially()` completes.
   - Recommendation: Show a brief "Scanning..." placeholder in `AppLaunchView` when `viewModel.apps.isEmpty && viewModel.isLoading`. This is a `ProgressView` + text, dismisses automatically when `apps` populates.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| FileManager | `AppScannerService` | Yes | macOS built-in | — |
| NSWorkspace | App launch + icon | Yes | macOS built-in | — |
| KeyboardShortcuts SPM | Hotkey registration | Yes | Integrated in project | — |
| `/Applications` directory | App scan | Yes (confirmed: 60+ apps) | — | — |
| `/System/Applications` | App scan | Yes (confirmed: 65+ apps) | — | — |
| `~/Applications` | App scan | May be absent | — | Skip silently if directory doesn't exist |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (existing project setup) |
| Config file | `Clipsmith.xcodeproj` (no separate test config) |
| Quick run command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/AppLaunchViewModelTests` |
| Full suite command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |

### Phase Requirements to Test Map

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| Fuzzy filtering of app list | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | No — Wave 0 |
| Recency boost ranking | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | No — Wave 0 |
| Recent apps returned when no query | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | No — Wave 0 |
| Recent launch recording (UserDefaults) | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | No — Wave 0 |
| App scanning deduplication | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | No — Wave 0 |
| Bundle name extraction (CFBundleName fallback) | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | No — Wave 0 |
| AppLaunchController show/hide panel visibility | manual | N/A (NSPanel; no headless) | Manual only |
| Feature flag guard prevents show when disabled | manual | N/A | Manual only |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/AppLaunchViewModelTests -only-testing:ClipsmithTests/AppScannerServiceTests`
- **Per wave merge:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `ClipsmithTests/AppLaunchViewModelTests.swift` — covers fuzzy filter, recency boost, navigation
- [ ] `ClipsmithTests/AppScannerServiceTests.swift` — covers scan dedup, bundle name extraction, recordLaunch

---

## Security Domain

> `security_enforcement` not set in config.json (treated as enabled).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Minimal | Search query is display-only; no injection surface (no SQL, no shell exec) |
| V6 Cryptography | No | — |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via app URL | Tampering | Only URLs enumerated from whitelisted search paths; never accept URL from user input |
| NSWorkspace launching attacker-controlled URL | Elevation of privilege | URLs come exclusively from `AppScannerService` scan results; no user-typed path |
| Recent bundle IDs in UserDefaults | Information disclosure | Bundle IDs are not sensitive; stored as plain strings — acceptable |

**Overall security posture:** Low risk. The phase reads from a fixed list of known macOS app directories and launches using a system API. No user-supplied path is ever passed to `NSWorkspace` or `FileManager`. Input validation is not applicable; the search field is display/filter only.

---

## Sources

### Primary (HIGH confidence)
- Apple `NSWorkspace.h` (macOS 15.4 SDK at `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`) — verified `openApplicationAtURL:configuration:completionHandler:` signature and `NSWorkspaceOpenConfiguration.activates` property
- Clipsmith codebase — `BezelController.swift`, `PromptBezelController.swift`, `PromptBezelViewModel.swift`, `AppDelegate.swift`, `GeneralSettingsTab.swift`, `HotkeySettingsTab.swift`, `KeyboardShortcutNames.swift`, `FuzzyMatcher.swift` — all verified by direct read

### Secondary (MEDIUM confidence)
- [cocoadev.github.io — SomethingFasterThanWorkspacesIconForFile](https://cocoadev.github.io/SomethingFasterThanWorkspacesIconForFile/) — `NSWorkspace.iconForFile:` performance characteristics; warns about slow cases; recommends caching
- [Apple Developer Docs — openApplicationAtURL:configuration:completionHandler:](https://developer.apple.com/documentation/appkit/nsworkspace/3172700-openapplication) — confirms macOS 10.15+ availability
- [Apple Developer Docs — icon(forFile:)](https://developer.apple.com/documentation/appkit/nsworkspace/1528158-icon) — confirms API for icon loading

### Tertiary (LOW confidence)
- None — no claims rest on unverified WebSearch alone

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified in macOS 15.4 SDK headers and existing codebase
- Architecture: HIGH — bezel pattern is established across 3 prior implementations; new elements (AppScannerService, recency boost) are straightforward extensions
- Pitfalls: HIGH — most pitfalls are documented in existing code comments and STATE.md; icon-loading performance is supported by external source

**Research date:** 2026-05-25
**Valid until:** 2026-08-25 (stable macOS APIs; no fast-moving dependencies)
