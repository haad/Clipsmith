# Phase 11: App Launcher - Context

**Gathered:** 2026-05-25
**Status:** Ready for planning

<domain>
## Phase Boundary

A keyboard-driven app launcher bezel that scans all user-visible installed apps, fuzzy-searches them by name, shows icons, and launches the selected app via NSWorkspace. Serves as a Spotlight alternative for users who only use Spotlight to launch apps. Feature is behind an `appLauncherEnabled` flag in Settings.

This phase delivers:
- `AppLaunchController` — NSPanel (non-activating, 4th bezel in the app)
- `AppLaunchViewModel` — app list, fuzzy search, recency tracking
- `AppLaunchView` — SwiftUI view with icon + name rows, instant search field
- `AppScannerService` — scans installed apps, caches, refreshes on bezel open
- Hotkey recorder in Settings > Hotkeys tab (no default binding)
- Settings toggle in Settings > Features (behind `appLauncherEnabled` flag)

Out of scope: inline calculations, unit conversions, file search, web search, process management.

</domain>

<decisions>
## Implementation Decisions

### App Discovery
- **D-01:** Scan all user-visible app locations: `/Applications`, `~/Applications`, `/System/Applications`, `/Applications/Utilities`. This covers both user-installed and MAS system apps (Calculator, Safari, etc.) without relying on deprecated Launch Services C APIs.
- **D-02:** Cache the app list on Clipsmith startup. Refresh the cache asynchronously each time the launcher bezel is opened (not on every keystroke — the cached list is filtered live). Apps installed/removed since last open will appear on the next bezel open.

### Search Behaviour
- **D-03:** Bezel opens in instant search mode — typing immediately filters the app list. No separate hotkey needed to enter search mode (unlike the clipboard bezel). The search field has focus as soon as the bezel appears.
- **D-04:** When no text is typed, show the 5 most recently launched apps (tracked in UserDefaults by bundle ID). This gives fast access to frequently-used apps without requiring any typing.
- **D-05:** Results ranked by `FuzzyMatcher` score first; when scores are close (within ~0.1), recently-launched apps get a recency boost that can promote them above lower-scored matches.

### Visual Design
- **D-06:** Rows display app icon (via `NSWorkspace.icon(forFile:)`) + app name. This is standard launcher UX and makes visual scanning much faster than text-only. Icons should be ~24pt square, consistent row height.

### Hotkey
- **D-07:** No default hotkey binding. The user must configure their own binding in Settings > Hotkeys. This avoids any system conflicts (Spotlight is Cmd-Space; common third-party launchers already claim Cmd-Shift-Space).

### Panel & Launch Behaviour
- **D-08:** Non-activating NSPanel (`.nonactivatingPanel` + `canBecomeKey = true`) — same pattern as `BezelController` and `PromptBezelController`. Clipsmith stays in background; keyboard input is captured via the panel becoming key without activating the app.
- **D-09:** On Enter: close the bezel immediately, then call `NSWorkspace.shared.open(url)` which activates the launched app and brings it to front.

### Feature Flag
- **D-10:** Behind `AppSettingsKeys.appLauncherEnabled` (`@AppStorage`, default `false`). Hotkey registration guarded at the invocation site in AppDelegate, matching the `docLookupEnabled` pattern.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Bezel Pattern (copy this exactly)
- `Clipsmith/Views/BezelController.swift` — NSPanel subclass pattern: `.nonactivatingPanel`, `canBecomeKey`, `.canJoinAllSpaces + .fullScreenAuxiliary`, global event monitor for click-outside dismiss
- `Clipsmith/Views/BezelViewModel.swift` — `@Observable @MainActor` ViewModel pattern: search state, filtered list, navigation
- `Clipsmith/Views/BezelView.swift` — SwiftUI hosting view pattern for bezel panels

### Feature Flag Pattern
- `Clipsmith/Settings/AppSettingsKeys.swift` — where to add `appLauncherEnabled` key
- `Clipsmith/Views/Settings/HotkeySettingsTab.swift` — where to add hotkey recorder for new bezel
- `Clipsmith/App/AppDelegate.swift` — hotkey registration + feature flag guard pattern (see `docLookupEnabled` block)

### Hotkey Registration
- `Clipsmith/Settings/KeyboardShortcutNames.swift` — where to add the new hotkey name constant

### Fuzzy Matching
- `Clipsmith/Services/FuzzyMatcher.swift` — existing fuzzy matcher used by BezelViewModel and PromptBezelViewModel; reuse directly

### MenuBar Notification Pattern
- `Clipsmith/Views/MenuBarView.swift` — `Notification.Name` extension pattern for dispatching bezel show events

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FuzzyMatcher` — character-subsequence matching with consecutive-bonus scoring. Used directly in `AppLaunchViewModel` to filter the app list by name against the typed query.
- `BezelController` init pattern — copy the `.nonactivatingPanel` + `canBecomeKey` + level/collectionBehavior setup from `BezelController`. No clipboard/SwiftData dependencies to skip.
- `KeyboardShortcuts` library (already integrated) — `KeyboardShortcuts.Name` for the new hotkey; `KeyboardShortcuts.Recorder` in `HotkeySettingsTab`.

### Established Patterns
- **Controller/ViewModel/View trio** — `AppLaunchController` (NSPanel), `AppLaunchViewModel` (`@Observable @MainActor`), `AppLaunchView` (SwiftUI in `NSHostingView`). Match naming precisely.
- **Feature flag guard in AppDelegate** — register hotkey unconditionally, check `appLauncherEnabled` inside the handler before showing the bezel (see `docLookupEnabled` pattern).
- **Non-activating panel** — `.nonactivatingPanel` MUST be in the `styleMask` at `init` time; cannot be set after. `canBecomeKey` overridden to return `true`.
- **NSWorkspace.icon(forFile:)** — used elsewhere in the app (lines 647/694 in AppDelegate use `NSWorkspace.shared.open`); icon loading via `NSWorkspace.shared.icon(forFile: appURL.path)`.

### Integration Points
- `AppDelegate.applicationDidFinishLaunching` — create `AppLaunchController`, inject it as `appLaunchController`, register hotkey with `KeyboardShortcuts.onKeyDown`
- `MenuBarView.swift` — add a "Launch App" button (dispatches `Notification` that AppDelegate handles)
- `HotkeySettingsTab.swift` — add `KeyboardShortcuts.Recorder` for the new `.appLauncher` name
- `AppSettingsKeys.swift` — add `appLauncherEnabled` key
- `KeyboardShortcutNames.swift` — add `static let appLauncher: Name` extension

### App Scanning Implementation Note
- Use `FileManager.default` to enumerate `/Applications`, `/Applications/Utilities`, `/System/Applications` recursively looking for `.app` bundles (check `url.pathExtension == "app"`), plus `~/Applications`. Load `NSBundle.bundleURL` → `NSWorkspace.shared.icon(forFile:)` for icons. Store as a lightweight struct `(name: String, url: URL, icon: NSImage)`.
- Recent launches: store last 5 bundle IDs in `UserDefaults` under `AppSettingsKeys.recentAppBundleIDs`. Update on every successful launch.

</code_context>

<specifics>
## Specific Ideas

- The launcher is explicitly a Spotlight replacement for users who only use Spotlight for app launching. The experience should feel as fast and direct as possible — no clicks, just hotkey → type → Enter.
- Deferred capability mentioned during discussion: inline calculator/unit/currency conversions as a future "phase 12" style extension to the launcher. Not in scope here but worth tracking.

</specifics>

<deferred>
## Deferred Ideas

- **Inline launcher calculations / conversions** — User mentioned "simple match questions, currency conversions, unit conversions" as a potential capability in the launcher. This would make it a general-purpose command palette rather than just an app launcher. Defer to a follow-up phase once the base launcher is working.

</deferred>

---

*Phase: 11-App Launcher*
*Context gathered: 2026-05-25*
