# Unified Browser Window — Design Spec

**Date:** 2026-11-01
**Status:** Approved design (2026-11-01), pending implementation plan

## Problem

Clipsmith has grown one window per feature. The Snippets window (hand-rolled segmented control: Snippets / Prompts / Gists), the Claude Toolkit window (native toolbar, list + detail), the Todos window (capsule tab strip), and the Documentation browser (a floating `NSPanel` with its own chrome) each look and behave differently. The user wants one window with one visual language, and the Claude Toolkit window is the design to keep.

At the same time, GitHub Gist sharing has never been used and is removed outright rather than carried into the new window.

## Decisions (made with user)

| Decision | Choice |
|---|---|
| Scope of merge | Snippets, Prompts, Docs and Claude Toolkit become sections of **one window**. Todos stays its own window. *Amended 2026-11-02: Todos joins as the fifth section (⌘5, behind `todoTrackingEnabled`); project tabs become the chip row with Today leading, tab switching moves to ⇧⌘[ / ⇧⌘].* |
| Design template | The existing Claude Toolkit window: native toolbar, list pane with search on top and counts footer, detail pane with header / body / action footer. |
| Section switcher | Segmented picker in the toolbar's principal slot: **Snippets · Prompts · Docs · Toolkit** (order is the builder-facing default, see "My calls"). |
| Per-section filter | Always-visible **filter row** of chips directly under the search field (Snippets: languages; Prompts: All / My Prompts / categories; Toolkit: All / Commands / Agents / Skills). Not a popup. |
| Docs layout | Three columns, Docs only: **docset sidebar** on the left, results list with search in the middle, rendered page on the right. Selecting a docset scopes the search. |
| Docs hotkey | The `activateDocLookup` hotkey opens the unified window on Docs with search focused and "All docsets" selected. **Selected-text prefill is kept**: the selection in the frontmost app becomes the query. The floating `DocBezelController` panel is **removed**. Hold-to-show and always-on-top are knowingly given up. |
| Gist sharing | **Removed entirely**: UI, service, settings tab, menu items, keychain token store, notifications, SwiftData model, tests, docs. |

Explicitly out of scope: Todos window redesign, the clipboard bezel (except deleting its Gist menu item, see Gist removal), the prompt bezel (quick picker), the todo quick-add panel, Settings window layout, any change to search algorithms or data storage for snippets / prompts / docsets.

## Target design

### Window

- One `WindowGroup(id: "browser")` in `ClipsmithApp.swift` replaces `WindowGroup(id: "snippets")` and `WindowGroup(id: "claude-toolkit")`. Environment injection (`pasteService`, `appTracker`, `modelContainer`, docset services) moves to it.
- Minimum size 800 × 500. Resizable. Frame autosaved under a single name so all sections share one remembered size and position.
- Activation policy dance is unchanged: `MenuBarView.activateAsRegularApp()` then `openWindow`, and `onDisappear` restores `.accessory` when no regular windows remain (the existing pattern in `SnippetWindowView` / `TodoWindowView`).
- Root view `BrowserWindowView` (new, `Clipsmith/Views/Browser/`) owns `selectedSection: BrowserSection` and renders the toolbar plus the active section's content. `BrowserSection` is an enum: `snippets, prompts, docs, toolkit`.
- Deep-link: a single notification `.clipsmithOpenBrowser` with `userInfo["section"]` replaces `.clipsmithOpenSnippets`, `.clipsmithOpenPrompts`, `.clipsmithOpenDocLookup`, and the toolkit open path. `MenuBarView` observes it, does the activation dance, opens the window, then sets the section (same 150 ms delay trick as today's `openSnippetWindowOnPromptsTab`). The last-used section is remembered in `@AppStorage` and used when the window is opened without an explicit section.

### Toolbar

- `.toolbar` with `ToolbarItem(placement: .principal)` holding the section `Picker` (`.segmented`, max width ~420).
- `ToolbarItemGroup(placement: .automatic)` holds the active section's actions:
  - Snippets: **New** (`plus`, ⌘N).
  - Prompts: **New** (`plus`, ⌘N).
  - Docs: **Manage Docsets** (`arrow.down.circle`) → opens Settings on the Docsets tab (existing `selectedSettingsTab` + `showSettingsWindow:` pattern).
  - Toolkit: **Configure Path** (`folder`) → existing `ToolkitPathSheet`.
- `.navigationTitle("Clipsmith")`.

### Shared skeleton (Snippets, Prompts, Toolkit)

Extracted from `ClaudeToolkitWindowView` into reusable pieces so the three two-column sections share one implementation:

- `BrowserListPane<Row, Footer>`: `BrowserSearchField` on top (magnifying glass, plain text field, clear button, `controlBackgroundColor`), `Divider`, optional `BrowserFilterRow` (horizontal wrapping chips, single selection, "All" first), the `List(... selection:)` with `.listStyle(.sidebar)`, `Divider`, footer `HStack` of two captions (left: item count, right: section-specific count). Width `minWidth: 240, idealWidth: 290, maxWidth: 380`.
- `BrowserDetailPane`: header `HStack` (title, trailing badge), `Divider`, body (section-provided view, fills), `Divider`, footer `HStack` (leading secondary text or warning, trailing action buttons). Empty state: large SF Symbol in `.quaternary` and "Select an item to preview", as today.
- `HSplitView { listPane; detailPane }` as in the toolkit today.

Section mapping:

| Section | Filter row | Row (title / caption / trailing) | Detail body | Detail footer | Counts footer |
|---|---|---|---|---|---|
| Snippets | All + distinct `language` values present | name / language / — | existing `SnippetEditorView` (minus Gist code) | "Edited <relative date>" · **Paste ↩** | "N snippets" · "" |
| Prompts | All · My Prompts · categories present | title / category / category badge; user prompts get a distinct icon | existing prompt editor from `PromptLibraryView` (title, `{{variable}}` highlighted content) | variables summary + clipboard warning · **Save to My Snippets**, **Paste ↩** | "N prompts" · "M mine" |
| Toolkit | All · Commands · Agents · Skills | unchanged `ClaudeToolkitRowView` | unchanged `ClaudeToolkitDetailView` (Install / Uninstall stays in its header) | none | "N items" · "M installed" |

Existing behaviour carried over unchanged: snippet CRUD via `SnippetStore`, prompt `#category` search syntax, debounced autosave of prompt edits, Revert to Original, Save to My Snippets, paste-and-close on Return, toolkit install / uninstall.

### Docs section (three columns)

- `HSplitView { docsetSidebar; resultsPane; pagePane }`.
- **Docset sidebar** (`minWidth 160, idealWidth 190, maxWidth 240`): section header "Docsets", then a `List` with "All docsets" (count of enabled docsets) followed by one row per downloaded and enabled `DocsetInfo` (display name, trailing entry count in `.secondary`). Footer button "Add docset…" opens Settings on the Docsets tab. Selection is `selectedDocsetID: String?` (nil = all).
- **Results pane**: `BrowserSearchField` with a trailing caption "in <docset name>" when a docset is selected; results `List` of entries (name / type or docset name as caption); footer "N results" · selected docset name. No filter row.
- **Page pane**: existing `DocWebView` (WKWebView with the dark / light CSS). Header: entry name + docset badge. Footer: source path on the left, **Open in Browser** and **Copy Link** on the right.
- **Search scoping**: `DocBezelViewModel` is renamed `DocsBrowserViewModel` and gains `selectedDocsetID`. When set, `performSearch` calls `DocsetSearchService.searchAll` with `docsets: [selectedDocset]` and `docFilter: nil`. Do **not** pass the id as `docFilter`: `docsetMatchesFilter` is a substring match, so "go" would also scope to django, mongoose and gorm. `docFilter` stays reserved for the typed `prefix:` syntax, which keeps working: typing `go:fmt` sets `selectedDocsetID` to the first result of `matchingDocsets` and searches `fmt`. Clearing the field does not clear the sidebar selection.
- **Entry counts**: `DocsetInfo` has no count field. The sidebar loads counts lazily per enabled docset via `DocsetSearchService.loadIndex` (already cached) and shows nothing until loaded.
- **Metadata freshness**: `DocsetSettingsSection` owns its own `DocsetManagerService` instance. The Docs section must call `managerService.loadMetadata()` on appear and whenever the window becomes key (the bezel did this on every `show()`), otherwise docsets added in Settings do not appear.
- **Keyboard**: ↑↓ move through results while the search field keeps focus (existing bezel behaviour, reused); ⌥↑ / ⌥↓ move the docset selection; ⌘F focuses search.
- **Selected-text prefill**: the `activateDocLookup` handler in `AppDelegate` calls `SelectedTextService.selectedText(from: appTracker.previousApp)` **before** anything activates Clipsmith (activation changes the frontmost app), then posts `.clipsmithOpenBrowser` with `userInfo["section"] = docs` and `userInfo["query"] = <text>`. `DocsBrowserViewModel` gets `open(withQuery:)`: sets `searchText`, keeps the current docset selection, focuses the field. If the window is already open on Docs, the query is replaced. Empty or whitespace selection → open with the field empty and focused. The menu item "Documentation Lookup…" does the same (today it also prefills). `SelectedTextService`'s Cmd-C fallback stays as it is.
- Feature flag `docLookupEnabled` still gates the hotkey and the Docs segment. When the flag is off, the Docs segment is hidden and ⌘3 is unassigned.

### Keyboard (whole window)

| Shortcut | Action |
|---|---|
| ⌘1 … ⌘4 | Switch section (Snippets, Prompts, Docs, Toolkit; hidden-button pattern already used in `SnippetWindowView`) |
| ⌘F | Focus the active section's search field |
| ⌘N | New snippet / new prompt (Snippets, Prompts only) |
| ⌘⌫ | Delete selected snippet / user prompt |
| ↩ | Paste selected item and close (Snippets, Prompts) |
| ↑↓ | Navigate list |
| ⎋ | Close window (yields to focused text fields) |

### Entry points after the change

| Today | After |
|---|---|
| Menu: Snippets… | opens browser on Snippets |
| Menu: Browse Prompts… | opens browser on Prompts |
| Menu: Documentation Lookup… | opens browser on Docs (*amended 2026-11-02: all per-section menu entries collapsed into one "Browser..." item opening the last-used section*) |
| Menu: Claude Toolkit… | opens browser on Toolkit |
| Hotkey `activateSnippets` | opens browser on Snippets |
| Hotkey `activateDocLookup` | opens browser on Docs, query prefilled from the frontmost app's selection, search focused |
| Hotkey `activatePrompts` | unchanged (prompt quick-pick bezel) |
| Hotkey `saveClipboardAsSnippet` | unchanged |

### Gist removal

Delete:

- `Clipsmith/Services/GistService.swift`, `Clipsmith/Services/TokenStore.swift` (only used by Gist), `Clipsmith/Views/Gists/GistHistoryView.swift`, `Clipsmith/Views/Settings/GistSettingsSection.swift`, `ClipsmithTests/GistServiceTests.swift`, `ClipsmithTests/TokenStoreTests.swift`.
- `SettingsTab.gist` and its tab in `SettingsView`. Keep the other raw values as they are so stored `selectedSettingsTab` values stay valid.
- `AppSettingsKeys.gistDefaultPublic` and its registered default.
- Menu bar: "Share as Gist…" in the clipping context menu; notifications `.clipsmithShareAsGist`, `.clipsmithOpenGistSettings`, `.clipsmithShareSnippetAsGist`.
- Clipboard bezel (`BezelController.swift`): the Share > "Create Gist…" menu item and `actionShareAsGist`. The Share submenu stays with "Copy as RTF" as its only item. No other bezel change.
- `AppDelegate`: `gistService`, `handleShareAsGist`, `sendGistNotification`, the `UNUserNotificationCenter` authorization request and delegate conformance (Gist was the only user of local notifications; verify with a grep for `UNUserNotificationCenter` before deleting).
- `SnippetEditorView`: `shareAsGist()` and the two Gist alerts, the `GistService` environment.
- README "GitHub Gist Sharing" section, the Gist settings bullet and the Keychain sentence in the privacy paragraph; `site/index.html` four Gist lines (highlight item, feature card title + description, requirements bullet); `CHANGELOG.md` gets a `### Removed` entry under `[Unreleased]`.
- Xcode project: remove the file references (manual PBX IDs, see CLAUDE.md).

SwiftData: `GistRecord` is removed from the schema via a new `ClipsmithSchemaV3` that lists only `Clipping`, `Snippet`, `PromptLibraryItem`, plus a lightweight `MigrationStage` V2 → V3 in `ClipsmithMigrationPlan`. Dropping an entity is a lightweight migration in SwiftData. Add a migration test alongside the existing `SchemaMigrationTests` that opens a V2 store containing a `GistRecord` and verifies the V3 container opens and the other entities survive.

### Files

New: `Views/Browser/BrowserWindowView.swift`, `Views/Browser/BrowserSection.swift`, `Views/Browser/BrowserListPane.swift`, `Views/Browser/BrowserDetailPane.swift`, `Views/Browser/BrowserFilterRow.swift`, `Views/Browser/SnippetsSectionView.swift`, `Views/Browser/PromptsSectionView.swift`, `Views/Browser/DocsSectionView.swift`, `Views/Browser/DocsBrowserViewModel.swift` (moved from `DocBezelViewModel`), `Models/Schema/ClipsmithSchemaV3.swift`.

Removed: `Views/Snippets/SnippetWindowView.swift`, `Views/DocBezelController.swift`, `Views/DocBezelView.swift` (its `DocWebView` moves to `Views/Browser/DocWebView.swift`), `Views/DocBezelViewModel.swift` (moved), the Gist files listed above.

Reworked: `ClaudeToolkitWindowView.swift` becomes `ToolkitSectionView.swift` using the shared panes; `SnippetListView.swift` and `PromptLibraryView.swift` are split into list rows + detail editors consumed by the section views; `AppDelegate.swift`, `MenuBarView.swift`, `ClipsmithApp.swift` for wiring; `CLAUDE.md` architecture section updated (Bezel pattern is now used twice, not three times; new Browser window section).

### Tests

- Existing `DocBezelViewModelTests` (if present) move with the view model; add tests for docset scoping (`selectedDocsetID` limits results; `go:fmt` selects Go and searches `fmt`; clearing the query keeps the selection).
- `BrowserSection` deep-link: notification with `section` opens that section; without it, the last-used section. With `query`, the Docs view model's `searchText` is set and the docset selection is untouched.
- Schema V3 migration test (above).
- All existing snippet / prompt / toolkit unit tests keep passing. UI behaviour (paste, toolbar actions) is verified manually; see "Builder notes".

## My calls (not discussed with the user; change freely if they object)

- Section order Snippets · Prompts · Docs · Toolkit (paste things first, reference second, admin last).
- "Add docset…" and the Docs toolbar button open Settings on the Docsets tab rather than a new sheet. The docset manager UI already exists there.
- ⌥↑ / ⌥↓ for moving the docset selection.
- Last-used section remembered across opens.
- Docs segment hidden (not disabled) when `docLookupEnabled` is off.
- `GistRecord` dropped from the schema via V3 rather than left as a dead entity.
- `UNUserNotificationCenter` wiring removed with Gist, pending a grep confirming nothing else posts notifications.

## Builder notes

- Running the full test suite on the developer's Mac posts real Cmd-V keystrokes from `SnippetPasteTests` and `PasteServiceTests` because the test host is Accessibility-trusted. Run those suites only after fixing that, or exclude them (`-skip-testing`). This is pre-existing and not part of this work.
- `NSExpression`, bezel, and paste code are untouched.
- WKWebView WebContent sandbox log noise is expected (CLAUDE.md).
