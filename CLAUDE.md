# CLAUDE.md — Project Guide for Clipsmith

## What is this?

Clipsmith is a keyboard-first clipboard manager, code snippet organizer, prompt library, and documentation browser for macOS. Built natively in Swift 6 with SwiftUI and SwiftData, targeting macOS 15+.

## Build & Test

```bash
# Build
xcodebuild build -scheme Clipsmith -destination 'platform=macOS'

# Run all tests
xcodebuild test -scheme Clipsmith -destination 'platform=macOS'

# Run specific test suite
xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/DocsetSearchServiceTests
```

No `Package.swift` — dependencies are managed via Xcode SPM integration in the `.xcodeproj`.

## Architecture

### App Lifecycle
- `ClipsmithApp.swift` — SwiftUI App entry point, MenuBarExtra, Settings window
- `AppDelegate.swift` — owns all services and controllers, registers global hotkeys, wires notifications from MenuBarView

### Bezel Pattern (used 3 times)
The app uses a consistent NSPanel-based overlay pattern for clipboard, prompts, and docs:
- **Controller** (`BezelController`, `PromptBezelController`, `DocBezelController`) — NSPanel subclass, keyboard routing, show/hide, event monitors
- **ViewModel** (`BezelViewModel`, `PromptBezelViewModel`, `DocBezelViewModel`) — `@Observable @MainActor`, search/filter, navigation state
- **View** (`BezelView`, `PromptBezelView`, `DocBezelView`) — SwiftUI view hosted in `NSHostingView`

Clipboard and prompt bezels use `.nonactivatingPanel` (don't steal focus). Doc bezel uses `.titled` (activates for resize/move interaction).

### Services
- `ClipboardMonitor` — adaptive polling of `NSPasteboard.general` (no accessibility-based monitoring)
- `ClipboardStore` — SwiftData CRUD for clippings
- `PasteService` — synthesizes Cmd-V via CGEvent after hiding the bezel
- `AppTracker` — tracks the frontmost app so paste goes to the right target
- `FuzzyMatcher` — character-subsequence matching with consecutive-bonus scoring
- `TextTransformer` — text transformations (uppercase, trim, sort lines, etc.)
- `GistService` — GitHub Gist creation via personal access token
- `PromptLibraryStore` / `PromptSyncService` — SwiftData prompts + JSON sync from remote URL
- `DocsetSearchService` — fuzzy search across DevDocs index.json entries
- `DocsetManagerService` — downloads index.json + db.json from devdocs.io, manages catalog
- `SelectedTextService` — reads selected text via AXUIElement with Cmd-C fallback

### Data Storage
- **Clippings & Prompts** — SwiftData (`ClipsmithSchemaV1`, `ClipsmithSchemaV2`)
- **Snippets** — SwiftData
- **DevDocs metadata** — JSON in `~/Library/Application Support/Clipsmith/devdocs-meta.json`
- **DevDocs content** — `index.json` + `db.json` per doc in `~/Library/Application Support/Clipsmith/DevDocs/{slug}/`
- **Settings** — UserDefaults via `@AppStorage` (keys in `AppSettingsKeys`)
- **Hotkeys** — KeyboardShortcuts library (stored in UserDefaults)

### External Dependencies (SPM)
- `KeyboardShortcuts` — global hotkey registration and recording UI
- `HighlightSwift` — syntax highlighting in snippet editor

## Key Conventions

- **Swift 6** with `SWIFT_STRICT_CONCURRENCY = complete`
- `@MainActor` on all UI-facing classes (ViewModels, Controllers, Services that touch UI state)
- `Sendable` on all model/data types
- No app sandbox (`ENABLE_APP_SANDBOX = NO`) — required for accessibility, global hotkeys, WKWebView
- Hardened runtime enabled
- Bundle ID: `com.github.haad.clipsmith`
- Menu bar only app (`.accessory` activation policy), switches to `.regular` temporarily when showing Settings or Snippet windows

## Common Patterns

### Adding a new hotkey
1. Add name in `KeyboardShortcutNames.swift`
2. Add recorder in `HotkeySettingsTab.swift`
3. Register handler in `AppDelegate.applicationDidFinishLaunching`

### Adding a menu bar item
1. Add `Notification.Name` in `MenuBarView.swift`
2. Add Button in MenuBarView body
3. Add `NotificationCenter.default.addObserver` + `@objc` handler in AppDelegate

### Feature flags
Use `AppSettingsKeys` + `@AppStorage` with default `false`, guard at invocation site (not registration).

## Documentation Browser (Phase 8)

Behind feature flag `docLookupEnabled` (Settings > Features). Uses devdocs.io as documentation source:
- Catalog fetched from `https://devdocs.io/docs.json` (~789 docs)
- Per-doc download: `index.json` (search entries) + `db.json` (HTML content)
- Search supports doc prefix filter: `python:map`, `go:fmt`
- HTML rendered in WKWebView with custom dark/light CSS
- WKWebView WebContent process logs sandbox errors — these are harmless noise

## Files to Watch

- `AppDelegate.swift` — the wiring hub, gets large with each new feature
- `Clipsmith.xcodeproj/project.pbxproj` — manually managed PBX IDs (AA/AF/BB/GG/SP prefix scheme)
- `MenuBarView.swift` — all menu bar items and their notification dispatching
