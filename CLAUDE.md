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

### Browser Window (`WindowGroup(id: "browser")`)
One window hosts Snippets, Prompts, Docs, Claude Toolkit and Todos as sections behind a toolbar picker (⌘1–⌘5). Docs and Todos are feature-flagged (`docLookupEnabled`, `todoTrackingEnabled`). Files live in `Views/Browser/`:
- `BrowserWindowView` / `BrowserWindowViewModel` — section picker, last-used section (`browserLastSection`), applies `BrowserOpenRequest`s
- `BrowserSection` — section enum, `BrowserOpenRequest` (section + optional query), the two notifications below
- `BrowserPanes` — shared `BrowserSearchField`, `BrowserFilterRow` (chips), `BrowserListPane`, `BrowserDetailPane`, `BrowserEmptyDetail`
- `SnippetsSectionView`, `PromptsSectionView`, `ToolkitSectionView`, `DocsSectionView`, `TodosSectionView` — one per section; filtering logic in `SnippetFilter` / `PromptFilter`; Todos reuses `TodoListView` / `TodoWindowViewModel` from `Views/Todos/` (project tabs are chips, ⇧⌘[ / ⇧⌘] switch them)
- `DocsBrowserViewModel` — docs search, docset scoping (sidebar), `prefix:` selection, `open(withQuery:)` prefill
- Snippets: markdown snippets render via `MarkdownWebView` (`MarkdownRenderer` escapes everything; highlight.js comes from HighlightSwift's bundle); `pendingSnippetName` opens a snippet from a todo `[[reference]]`; renames rewrite references via `TodoStore.renameSnippetReferences`; names are unique (`SnippetStore.isNameTaken`)

Opening flow (two hops, because `AppDelegate` has no `@Environment(\.openWindow)`): a caller posts `.clipsmithRequestBrowser` with `BrowserOpenRequest.userInfo` → `MenuBarView.openBrowser` puts the request in `BrowserOpenMailbox.shared`, activates the app, calls `openWindow(id: "browser")` and posts `.clipsmithOpenBrowser` → `BrowserWindowView` takes the request from the mailbox in `onAppear` (new window) or on the notification (already open). The docs hotkey captures the selected text in `AppDelegate.requestDocsBrowser()` before activation.

### Bezel Pattern (used 2 times)
The app uses a consistent NSPanel-based overlay pattern for clipboard and prompts:
- **Controller** (`BezelController`, `PromptBezelController`) — NSPanel subclass, keyboard routing, show/hide, event monitors
- **ViewModel** (`BezelViewModel`, `PromptBezelViewModel`) — `@Observable @MainActor`, search/filter, navigation state
- **View** (`BezelView`, `PromptBezelView`) — SwiftUI view hosted in `NSHostingView`

Both bezels use `.nonactivatingPanel` (don't steal focus). Documentation is a section of the browser window, not a bezel.

### Services
- `ClipboardMonitor` — adaptive polling of `NSPasteboard.general` (no accessibility-based monitoring)
- `ClipboardStore` — SwiftData CRUD for clippings
- `PasteService` — synthesizes Cmd-V via CGEvent after hiding the bezel
- `AppTracker` — tracks the frontmost app so paste goes to the right target
- `FuzzyMatcher` — character-subsequence matching with consecutive-bonus scoring
- `TextTransformer` — text transformations (uppercase, trim, sort lines, etc.)
- `PromptLibraryStore` / `PromptSyncService` — SwiftData prompts + JSON sync from remote URL
- `DocsetSearchService` — fuzzy search across DevDocs index.json entries
- `DocsetManagerService` — downloads index.json + db.json from devdocs.io, manages catalog
- `SelectedTextService` — reads selected text via AXUIElement with Cmd-C fallback

### Data Storage
- **Clippings & Prompts** — SwiftData (`ClipsmithSchemaV1` → `V2` → `V3`; V3 dropped `GistRecord`, migrations are lightweight)
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
- Menu bar only app (`.accessory` activation policy), switches to `.regular` temporarily when showing the Settings or browser windows

## Common Patterns

### Adding a new hotkey
1. Add name in `KeyboardShortcutNames.swift`
2. Add recorder in `HotkeySettingsTab.swift`
3. Register handler in `AppDelegate.applicationDidFinishLaunching`

### Adding a menu bar item
1. Add `Notification.Name` in `MenuBarView.swift`
2. Add Button in MenuBarView body
3. Add `NotificationCenter.default.addObserver` + `@objc` handler in AppDelegate

The menu has a single "Browser..." entry that opens the window on the last-used section (⌘1–⌘5 switch). To open it on a specific section from code, post `.clipsmithRequestBrowser` with `BrowserOpenRequest(section:query:).userInfo` (or call `openBrowser` directly from `MenuBarView`).

### Feature flags
Use `AppSettingsKeys` + `@AppStorage` with default `false`, guard at invocation site (not registration).

## Documentation Browser (Phase 8)

Behind feature flag `docLookupEnabled` (Settings > Features). Uses devdocs.io as documentation source:
- Catalog fetched from `https://devdocs.io/docs.json` (~789 docs)
- Per-doc download: `index.json` (search entries) + `db.json` (HTML content)
- Lives in the Docs section of the browser window: docset sidebar (scopes the search), results, rendered page
- Search supports doc prefix filter: `python:map`, `go:fmt` — the prefix also selects the docset in the sidebar
- Hotkey (`activateDocLookup`) opens the window on Docs prefilled with the selected text
- HTML rendered in WKWebView with custom dark/light CSS
- WKWebView WebContent process logs sandbox errors — these are harmless noise

## Website & Changelog

- **Website**: `site/index.html` — static single-page site deployed to GitHub Pages (`haad.github.io/Clipsmith`)
- **Changelog**: `CHANGELOG.md` in repo root — single source of truth, [Keep a Changelog](https://keepachangelog.com/) format
  - During GitHub Pages deploy, `site/scripts/build-changelog.sh` converts CHANGELOG.md to HTML and injects it into the `<!-- CHANGELOG_CONTENT -->` placeholder in `site/index.html`
  - During GitHub Release (tag push), `release.yml` extracts the current version's section from CHANGELOG.md for release notes
  - **When releasing**: update CHANGELOG.md before tagging — move items from `[Unreleased]` to a new version section
- **Prompt Library subsite**: `site/prompts/` — built from `site/prompts/catalog.yaml` by `site/prompts/scripts/build.sh`
- **Deploy trigger**: push to `site/**` or `CHANGELOG.md` on main → `.github/workflows/deploy-site.yml`

## Licensing (Phase 10)

- `LicenseService` — wraps Lemon Squeezy activate/validate/deactivate API (3 POST endpoints, no SDK)
- `LicenseNagController` — activating NSPanel shown every 30 days for unlicensed users
- `LicenseSettingsSection` — Settings > License tab with key entry and validation feedback
- Store ID and Product ID are in `LicenseService.swift` (`expectedStoreId`, `expectedProductId`)
- Purchase URL is in `LicenseNagController.swift`, `LicenseSettingsSection.swift`, and `.github/FUNDING.yml`
- License: MIT (`LICENSE` file); Lemon Squeezy license purchase is voluntary support, not a legal requirement

## Files to Watch

- `AppDelegate.swift` — the wiring hub, gets large with each new feature
- `Clipsmith.xcodeproj/project.pbxproj` — manually managed PBX IDs (AA/AF/BB/GG/SP prefix scheme)
- `MenuBarView.swift` — all menu bar items and their notification dispatching
