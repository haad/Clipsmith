# Unified Browser Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Snippets window, the Claude Toolkit window and the floating documentation panel with one `WindowGroup(id: "browser")` that has four toolbar sections (Snippets, Prompts, Docs, Toolkit) in the Claude Toolkit visual style, and delete GitHub Gist sharing entirely.

**Architecture:** A `BrowserWindowView` owns the section picker in the toolbar and swaps in one section view. Snippets, Prompts and Toolkit share extracted list/detail pane components (search field, filter chip row, counts footer, header/body/footer detail). Docs is three columns: docset sidebar, results, WKWebView page, driven by the existing doc view model renamed and extended with docset scoping and a prefill entry point. All entry points funnel through one `.clipsmithOpenBrowser` notification carrying a section and an optional query. Gist removal lands first and includes a SwiftData schema V3 that drops `GistRecord`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, AppKit, WebKit, KeyboardShortcuts (SPM), XCTest. Xcode project with hand-managed PBX IDs.

**Spec:** `docs/superpowers/specs/2026-11-01-unified-browser-window-design.md`

Deviation from the spec's file list: the shared pane components live in one file, `BrowserPanes.swift`, instead of three; they are small and always change together.

## Global Constraints

- Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`. `@MainActor` on every view model and UI-facing class, `Sendable` on data types. Follow `CLAUDE.md`.
- Build: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS' 2>&1 | grep -E "error:|warning: unre|BUILD"`. Expected last line `** BUILD SUCCEEDED **`.
- Test one suite: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/<Suite> 2>&1 | grep -E "error:|Executed|TEST"`.
- **Never run the full suite without** `-skip-testing:ClipsmithTests/SnippetPasteTests -skip-testing:ClipsmithTests/PasteServiceTests`. Those two post real Cmd-V keystrokes into the frontmost app on this machine (test host is Accessibility-trusted). Full-suite command used in this plan: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -skip-testing:ClipsmithTests/SnippetPasteTests -skip-testing:ClipsmithTests/PasteServiceTests 2>&1 | grep -E "error:|Executed .* tests|TEST"`.
- **Xcode project file** `Clipsmith.xcodeproj/project.pbxproj` is hand-edited. Every source file has four entries: a `PBXBuildFile` (`AAxxxx`), a `PBXFileReference` (`AFxxxx`), a child line in its `PBXGroup`, and a line in the right `Sources` build phase (app target list around line 640–700, test target list around line 705–740). Groups are `GGxxxx`. Copy the `TodoWindowView.swift` entries (grep `AF0111`) as the template. Highest IDs in use at plan time: `AA0114`, `AF0114`, `GG0017`. Each task below states the IDs it allocates; keep AA and AF numbers equal for the same file. Deleting a file means deleting all four entries.
- Keyboard: ⌘1–⌘4 switch sections, ⌘F focuses the active search field, ⌘N new (Snippets, Prompts), ⌘⌫ delete, ↩ paste-and-close (Snippets, Prompts), ⎋ closes the window, ⌥↑/⌥↓ moves the docset selection (Docs).
- Window: `WindowGroup(id: "browser")`, `.frame(minWidth: 760, minHeight: 500)`, `.windowResizability(.contentSize)`, `.navigationTitle("Clipsmith")`. Frame autosave name `"BrowserWindowFrame"`.
- Section order and titles: `Snippets`, `Prompts`, `Docs`, `Toolkit`. Docs hidden when `AppSettingsKeys.docLookupEnabled` is false.
- List pane: `minWidth: 240, idealWidth: 290, maxWidth: 380`. Docset sidebar: `minWidth: 160, idealWidth: 190, maxWidth: 240`.
- Commits: conventional prefix as in `git log` (`feat(browser): …`, `refactor(gist): …`, `docs: …`), body optional, end every message with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Do not touch: `BezelController` beyond the Gist menu item, `PromptBezelController`, `TodoWindowView`, `TodoQuickAddController`, `ExpressionEvaluator`, paste code.

## Review Focus

Inputs the spec implies but no section-level test covers, most likely to bite first. Each has a pinned test in the owning task.

1. **Docs hotkey with an empty or whitespace selection** must open Docs with an empty, focused search field and must not search. Pinned in Task 8 (`testOpenWithQueryWhitespaceClearsSearch`).
2. **Prefix syntax whose docset is not installed** (`rust:vec` with no Rust docset) must leave the sidebar selection unchanged and produce zero results, not crash or select the wrong docset. Pinned in Task 8 (`testPrefixWithNoMatchKeepsSelection`).
3. **Reopening the window after `docLookupEnabled` is switched off while Docs was the last-used section** must fall back to Snippets, never show a hidden segment. Pinned in Task 5 (`testApplyFallsBackWhenDocsDisabled`).
4. **A snippet whose language is nil or empty** must still appear under the "All" chip and must not create an empty chip. Pinned in Task 6 (`testLanguagesIgnoreNilAndEmpty`).
5. **Migrating a store that contains Gist records** must open under V3 and keep clippings, snippets and prompts. Pinned in Task 2 (`testV2StoreWithGistRecordsMigratesToV3`).

---

### Task 1: Delete Gist sharing (UI, service, settings, wiring, docs)

Leaves `GistRecord` in the schema; Task 2 drops it.

**Files:**
- Delete: `Clipsmith/Services/GistService.swift`, `Clipsmith/Services/TokenStore.swift`, `Clipsmith/Views/Gists/GistHistoryView.swift`, `Clipsmith/Views/Settings/GistSettingsSection.swift`, `ClipsmithTests/GistServiceTests.swift`, `ClipsmithTests/TokenStoreTests.swift`
- Modify: `Clipsmith.xcodeproj/project.pbxproj` (entries `AA0030–AA0033`, `AA0041`, `AA0042`, `AF0032–AF0035`, `AF0042`, `AF0043`, group `GG0012` and its child line in `GG0005`)
- Modify: `Clipsmith/App/AppDelegate.swift` (`gistService` property and init, `handleShareAsGist`, `sendGistNotification`, `showGistNoTokenAlert`, `showGistErrorAlert`, the `.clipsmithShareAsGist` observer, the `UNUserNotificationCenter` delegate assignment + `requestAuthorization`, the `UNUserNotificationCenterDelegate` extension, `import UserNotifications`, `gistDefaultPublic` registered default)
- Modify: `Clipsmith/App/ClipsmithApp.swift` (remove `.environment(appDelegate.gistService)`)
- Modify: `Clipsmith/Views/MenuBarView.swift` (remove the three Gist `Notification.Name`s, the "Share as Gist..." context-menu button, the `.clipsmithOpenGistSettings` `onReceive`)
- Modify: `Clipsmith/Views/BezelController.swift` (remove `gistItem` lines in the Share submenu and `actionShareAsGist`)
- Modify: `Clipsmith/Views/Snippets/SnippetEditorView.swift` (remove `GistService` environment, `gistDefaultPublic`, the `.onReceive(.clipsmithShareSnippetAsGist)`, `shareAsGist`, both alert helpers)
- Modify: `Clipsmith/Views/Snippets/SnippetWindowView.swift` (remove the "Share as Gist" button and the Gists tab; keep tags 0 and 1; remove ⌘3 hidden button and ⇧⌘G line in the doc comment)
- Modify: `Clipsmith/Views/SettingsView.swift` (remove the `GistSettingsSection()` tab; keep `case gist = 3` in `SettingsTab` with a comment `// retired; raw value reserved so stored selections stay valid`)
- Modify: `Clipsmith/Settings/AppSettingsKeys.swift` (remove `gistDefaultPublic`)
- Modify: `README.md` (delete "### GitHub Gist Sharing" section lines 48–52, the "**Gists**" settings bullet line 117, and the Keychain sentence in line 130), `site/index.html` (lines 381, 493–494, 577), `CHANGELOG.md` (add `### Removed` under `[Unreleased]`)

**Interfaces:**
- Consumes: nothing new.
- Produces: a tree with zero references to `Gist`, `TokenStore`, `UNUserNotificationCenter` outside `ClipsmithSchemaV1.GistRecord` and `ClipsmithSchemaV2`.

- [ ] **Step 1: Verify nothing else posts local notifications**

Run: `grep -rn "UNUserNotificationCenter\|UNMutableNotificationContent" Clipsmith`
Expected: hits only in `AppDelegate.swift`. If anything else appears, keep the `requestAuthorization` call and delegate, delete only `sendGistNotification`.

- [ ] **Step 2: Delete the six Gist files and their project entries**

`git rm` the six files. In `project.pbxproj` remove the four entries for each (`AA0030/AF0032` TokenStore, `AA0031/AF0033` TokenStoreTests, `AA0032/AF0034` GistService, `AA0033/AF0035` GistServiceTests, `AA0041/AF0042` GistHistoryView, `AA0042/AF0043` GistSettingsSection), delete group `GG0012 /* Gists */` and its child line inside `GG0005 /* Views */`.

- [ ] **Step 3: Remove Gist code from the modify list above**

Follow the per-file lists. In `BezelController` the Share submenu keeps only "Copy as RTF". In `SnippetWindowView` the picker becomes `Snippets` (0) / `Prompts` (1).

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`, and `grep -rni "gist" Clipsmith ClipsmithTests --include=*.swift -l` lists only the two schema files.

- [ ] **Step 5: Docs**

Apply the README, `site/index.html` and `CHANGELOG.md` edits. CHANGELOG entry under `[Unreleased]`:

```markdown
### Removed

- GitHub Gist sharing (menu item, bezel Share action, snippet share, Gist history tab,
  Settings > Gist, Keychain token). Unused; removed in favour of the unified browser window.
```

- [ ] **Step 6: Run the suite (skipping paste tests)**

Run the full-suite command. Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(gist): remove GitHub Gist sharing end to end

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Schema V3 drops `GistRecord`

**Files:**
- Create: `Clipsmith/Models/Schema/ClipsmithSchemaV3.swift` (IDs `AA0115`/`AF0115`, group `GG0006 /* Schema */`)
- Modify: `Clipsmith/Models/Schema/ClipsmithMigrationPlan.swift`, `Clipsmith/App/ClipsmithApp.swift:15` (`Schema(ClipsmithSchemaV3.models)`), `ClipsmithTests/TestModelContainer.swift` (V3), `ClipsmithTests/SchemaMigrationTests.swift`
- Note: `ClipsmithSchemaV2` still lists `GistRecord` (history must stay intact for migration).

**Interfaces:**
- Produces: `enum ClipsmithSchemaV3: VersionedSchema` with `static var versionIdentifier = Schema.Version(3, 0, 0)`, `static var models: [any PersistentModel.Type]` = `[Clipping, Snippet, PromptLibraryItem]`, typealiases `Clipping = ClipsmithSchemaV1.Clipping`, `Snippet = ClipsmithSchemaV1.Snippet`, `PromptLibraryItem = ClipsmithSchemaV2.PromptLibraryItem`. `ClipsmithMigrationPlan.schemas` = `[V1, V2, V3]`, `stages` = `[migrateV1toV2, migrateV2toV3]`.

- [ ] **Step 1: Write the failing tests** in `SchemaMigrationTests.swift`

Change `testV2SchemaIncludesAllFourModels` expectation text only if it fails (V2 keeps 4). Add:

```swift
func testV3SchemaHasThreeModels() {
    XCTAssertEqual(ClipsmithSchemaV3.models.count, 3)
    XCTAssertFalse(ClipsmithSchemaV3.models.contains { $0 == ClipsmithSchemaV1.GistRecord.self })
}

func testMigrationPlanEndsAtV3() {
    XCTAssertTrue(ClipsmithMigrationPlan.schemas.last == ClipsmithSchemaV3.self)
    XCTAssertEqual(ClipsmithMigrationPlan.stages.count, 2)
}

/// Review Focus 5.
func testV2StoreWithGistRecordsMigratesToV3() async throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "migration-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }

    // Seed a V2 store.
    do {
        let v2 = try ModelContainer(for: Schema(ClipsmithSchemaV2.models),
                                    configurations: [ModelConfiguration(schema: Schema(ClipsmithSchemaV2.models), url: url)])
        try await MainActor.run {
            let ctx = v2.mainContext
            ctx.insert(ClipsmithSchemaV1.GistRecord(gistID: "g1", gistURL: "https://gist.github.com/g1", filename: "a.txt"))
            ctx.insert(ClipsmithSchemaV1.Snippet(name: "keep", content: "x"))
            ctx.insert(ClipsmithSchemaV2.PromptLibraryItem(id: "p", title: "P", content: "c", category: "coding", version: 1))
            try ctx.save()
        }
    }

    // Reopen with the migration plan at V3.
    let v3 = try ModelContainer(for: Schema(ClipsmithSchemaV3.models),
                                migrationPlan: ClipsmithMigrationPlan.self,
                                configurations: [ModelConfiguration(schema: Schema(ClipsmithSchemaV3.models), url: url)])
    try await MainActor.run {
        let ctx = v3.mainContext
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ClipsmithSchemaV3.Snippet>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ClipsmithSchemaV3.PromptLibraryItem>()), 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run suite `SchemaMigrationTests`. Expected: compile error `cannot find 'ClipsmithSchemaV3'`.

- [ ] **Step 3: Implement `ClipsmithSchemaV3` and the stage**

`static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: ClipsmithSchemaV2.self, toVersion: ClipsmithSchemaV3.self)`. Switch `ClipsmithApp.sharedModelContainer` and `makeTestContainer()` to `ClipsmithSchemaV3.models`. Add the pbxproj entries.

- [ ] **Step 4: Run to verify pass**

Run suite `SchemaMigrationTests`. Expected: PASS, 0 failures. Then the full-suite command: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(schema): V3 drops GistRecord with lightweight migration

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `BrowserSection`, open request, and shared pane components

**Files:**
- Create: `Clipsmith/Views/Browser/BrowserSection.swift` (`AA0116`/`AF0116`), `Clipsmith/Views/Browser/BrowserPanes.swift` (`AA0117`/`AF0117`), new group `GG0018 /* Browser */` (path `Browser`, child of `GG0005`)
- Create: `ClipsmithTests/BrowserSectionTests.swift` (`AA0118`/`AF0118`, test target)

**Interfaces:**
- Produces (`BrowserSection.swift`):
  - `enum BrowserSection: String, CaseIterable, Identifiable, Sendable { case snippets, prompts, docs, toolkit }` with `var id: String { rawValue }`, `var title: String` ("Snippets", "Prompts", "Docs", "Toolkit"), `var keyboardIndex: Int` (1…4 in declaration order), `static func available(docLookupEnabled: Bool) -> [BrowserSection]` (all four, or without `.docs`).
  - `struct BrowserOpenRequest: Sendable { var section: BrowserSection?; var query: String? }` with `init(section:query:)`, `init?(userInfo: [AnyHashable: Any]?)` (returns nil when neither key present), `var userInfo: [String: Any]` using keys `"section"` (raw value) and `"query"`.
  - `extension Notification.Name { static let clipsmithRequestBrowser = Notification.Name("clipsmithRequestBrowser"); static let clipsmithOpenBrowser = Notification.Name("clipsmithOpenBrowser") }`. Two-hop flow used everywhere: any caller (hotkey, menu, AppDelegate) posts `.clipsmithRequestBrowser` with `request.userInfo`; `MenuBarView` observes it, does the activation dance and `openWindow(id: "browser")`, then posts `.clipsmithOpenBrowser` with the same `userInfo`; `BrowserWindowView` observes that and applies the request.
  - `extension AppSettingsKeys { static let browserLastSection = "browserLastSection" }` (put in `AppSettingsKeys.swift` instead if that file groups keys; either is fine).
- Produces (`BrowserPanes.swift`), all `struct … : View`:
  - `BrowserSearchField(text: Binding<String>, placeholder: String, isFocused: FocusState<Bool>.Binding, trailing: () -> Trailing = { EmptyView() })` — magnifying glass, `.plain` text field, clear button when non-empty, `Color(NSColor.controlBackgroundColor)` background, same paddings as `ClaudeToolkitWindowView.listPane` search bar.
  - `struct BrowserFilterOption: Identifiable, Hashable, Sendable { let id: String; let label: String }`.
  - `BrowserFilterRow(options: [BrowserFilterOption], selection: Binding<String?>)` — leading "All" chip bound to `nil`, then one chip per option, wrapping `HStack`s via a flow layout (use `LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))])` or a simple wrapping `Layout`), capsule chips, selected = `Color.accentColor.opacity(0.25)` fill (same look as `TodoWindowView.tabButton`).
  - `BrowserListPane<Search: View, Filter: View, Content: View, Footer: View>(search:filter:content:footer:)` — `VStack(spacing: 0)` of search, `Divider`, filter (may be `EmptyView`), content, `Divider`, footer; applies the list-pane frame constants.
  - `BrowserCountsFooter(leading: String, trailing: String)` — two captions in `.secondary`, same paddings as the toolkit footer.
  - `BrowserDetailPane<Header: View, Body: View, FooterLeading: View, FooterTrailing: View>(header:body:footerLeading:footerTrailing:)` — header row (`padding(.horizontal, 12).padding(.vertical, 10)`, `controlBackgroundColor`), `Divider`, body fills, `Divider`, footer row with leading on the left and trailing buttons on the right, `controlBackgroundColor`. If both footer views are `EmptyView`, omit the footer and its divider.
  - `BrowserEmptyDetail(systemImage: String, message: String)` — the toolkit empty state (48 pt `.quaternary` symbol + secondary text).

- [ ] **Step 1: Write the failing tests** (`BrowserSectionTests.swift`)

```swift
import XCTest
@testable import Clipsmith

final class BrowserSectionTests: XCTestCase {
    func testOrderAndKeyboardIndex() {
        XCTAssertEqual(BrowserSection.allCases, [.snippets, .prompts, .docs, .toolkit])
        XCTAssertEqual(BrowserSection.docs.keyboardIndex, 3)
        XCTAssertEqual(BrowserSection.toolkit.title, "Toolkit")
    }

    func testAvailableHidesDocsWhenFlagOff() {
        XCTAssertEqual(BrowserSection.available(docLookupEnabled: false), [.snippets, .prompts, .toolkit])
        XCTAssertEqual(BrowserSection.available(docLookupEnabled: true), BrowserSection.allCases)
    }

    func testOpenRequestRoundTripsThroughUserInfo() {
        let req = BrowserOpenRequest(section: .docs, query: "map")
        let parsed = BrowserOpenRequest(userInfo: req.userInfo)
        XCTAssertEqual(parsed?.section, .docs)
        XCTAssertEqual(parsed?.query, "map")
    }

    func testOpenRequestNilWhenEmpty() {
        XCTAssertNil(BrowserOpenRequest(userInfo: nil))
        XCTAssertNil(BrowserOpenRequest(userInfo: ["unrelated": 1]))
        XCTAssertNil(BrowserOpenRequest(userInfo: ["section": "nope"])?.section)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run suite `BrowserSectionTests`. Expected: compile error, `BrowserSection` not found.

- [ ] **Step 3: Implement `BrowserSection.swift` and `BrowserPanes.swift`**, add pbxproj entries and group `GG0018`.

- [ ] **Step 4: Run to verify pass**

Run suite `BrowserSectionTests`. Expected: PASS. Build: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(browser): BrowserSection, open request, shared list/detail panes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Toolkit becomes a section on the shared panes

**Files:**
- Rename: `Clipsmith/Views/ClaudeToolkit/ClaudeToolkitWindowView.swift` → `Clipsmith/Views/Browser/ToolkitSectionView.swift` (`git mv`; update `AF0085` path and move the child line from `GG0016` to `GG0018`; delete group `GG0016` and its line in `GG0005`)
- Modify: that file.

**Interfaces:**
- Produces: `struct ToolkitSectionView: View` with `init()` (no parameters; keeps `@AppStorage(AppSettingsKeys.toolkitPath)` and `@State private var viewModel = ClaudeToolkitViewModel()`). `ClaudeToolkitViewModel`, `ClaudeToolkitRowView`, `ClaudeToolkitDetailView`, `ToolkitPathSheet` unchanged except the view model gains `var kindFilterID: String?` bridging to `selectedKind` (`nil` ↔ `nil`, otherwise `Kind(rawValue:)`).
- Consumes: Task 3 panes.

- [ ] **Step 1: Rework the body**

`HSplitView { BrowserListPane(search: BrowserSearchField(...placeholder: "Search toolkit…"), filter: BrowserFilterRow(options: Kind.allCases.map { .init(id: $0.rawValue, label: $0.label) }, selection: $viewModel.kindFilterID), content: <existing loading / error / List>, footer: BrowserCountsFooter(leading: "\(count) items", trailing: "\(installed) installed")); detailPane }`. Detail: `ClaudeToolkitDetailView` as is, or `BrowserEmptyDetail(systemImage: "shippingbox", message: "Select an item to preview")`. Remove the `.principal` toolbar item (the kind picker). Keep the folder toolbar button as `ToolbarItemGroup(placement: .automatic)`. Remove `.navigationTitle` (the window sets it). Keep `.sheet` and `.onAppear`/`.onChange(of: toolkitPath)`.

- [ ] **Step 2: Build**

Expected: `** BUILD SUCCEEDED **`. `WindowGroup(id: "claude-toolkit")` temporarily hosts `ToolkitSectionView()` so the app still runs; Task 5 removes that group.

- [ ] **Step 3: Manual check**

Run the app, open Claude Toolkit from the menu bar. Expected: kind chips under the search field filter the list; folder button still opens the path sheet.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(toolkit): ToolkitSectionView on shared browser panes, kind filter as chip row

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `BrowserWindowView`, window group, deep link, Toolkit entry point

**Files:**
- Create: `Clipsmith/Views/Browser/BrowserWindowViewModel.swift` (`AA0119`/`AF0119`), `Clipsmith/Views/Browser/BrowserWindowView.swift` (`AA0120`/`AF0120`)
- Create: `ClipsmithTests/BrowserWindowViewModelTests.swift` (`AA0121`/`AF0121`, test target)
- Modify: `Clipsmith/App/ClipsmithApp.swift` (replace `WindowGroup(id: "claude-toolkit")` with `WindowGroup(id: "browser")`), `Clipsmith/Views/MenuBarView.swift` ("Claude Toolkit..." button, new `openBrowser(_ request:)`, `onReceive(.clipsmithOpenBrowser)`), `Clipsmith/App/AppDelegate.swift:windowDidBecomeKey` (frame autosave)

**Interfaces:**
- Produces (`BrowserWindowViewModel`, `@Observable @MainActor final class`):
  - `var selectedSection: BrowserSection` (didSet writes `rawValue` to `UserDefaults` under `AppSettingsKeys.browserLastSection`)
  - `var pendingDocsQuery: String?` — set by `apply`, consumed by the Docs section (Task 9) which sets it back to nil.
  - `init(defaults: UserDefaults = .standard)` — restores last section, falling back to `.snippets` if missing or unavailable.
  - `func apply(_ request: BrowserOpenRequest, docLookupEnabled: Bool)` — selects `request.section` if available, else keeps current (or falls back to `.snippets` if current is unavailable); stores `request.query` in `pendingDocsQuery` only when the resolved section is `.docs`.
  - `func sections(docLookupEnabled: Bool) -> [BrowserSection]` = `BrowserSection.available(...)`.
- Produces (`BrowserWindowView`): root view; `init(docsetSearchService: DocsetSearchService, docsetManagerService: DocsetManagerService)` stored as `let`s and handed to `DocsSectionView` in Task 9 (`DocsetSearchService` is a plain `Sendable` class, not `@Observable`, so it cannot go through `.environment`); `@State private var viewModel = BrowserWindowViewModel()`, `@AppStorage(AppSettingsKeys.docLookupEnabled) docLookupEnabled`; toolbar `ToolbarItem(placement: .principal) { Picker over viewModel.sections(...) , .segmented, .frame(maxWidth: 420) }`; body `switch viewModel.selectedSection` → `SnippetsSectionView()` / `PromptsSectionView()` / `DocsSectionView(viewModel:)` / `ToolkitSectionView()`. Until Tasks 6–9 land, the three missing cases render `Text("Coming in the next task")`. Hidden ⌘1–⌘4 buttons (pattern from `SnippetWindowView`), `.onExitCommand { NSApp.keyWindow?.close() }`, the `onDisappear` accessory-restore block copied from `TodoWindowView`, `.onReceive(NotificationCenter.default.publisher(for: .clipsmithOpenBrowser))` → `viewModel.apply(BrowserOpenRequest(userInfo:), docLookupEnabled:)`, `.navigationTitle("Clipsmith")`.
- Produces (`MenuBarView`): `private func openBrowser(_ request: BrowserOpenRequest)` — `activateAsRegularApp()`, sleep 100 ms, `openWindow(id: "browser")`, sleep 150 ms, `NotificationCenter.default.post(name: .clipsmithOpenBrowser, object: nil, userInfo: request.userInfo)`. Plus `.onReceive(NotificationCenter.default.publisher(for: .clipsmithRequestBrowser)) { openBrowser(BrowserOpenRequest(userInfo: $0.userInfo) ?? BrowserOpenRequest(section: nil, query: nil)) }`. Menu buttons call `openBrowser` directly; hotkeys and `AppDelegate` post `.clipsmithRequestBrowser` (see Task 3 flow).
- Produces (`AppDelegate.windowDidBecomeKey`): when `window.identifier?.rawValue.hasPrefix("browser") == true`, call `window.setFrameAutosaveName("BrowserWindowFrame")` once.

- [ ] **Step 1: Write the failing tests** (`BrowserWindowViewModelTests.swift`)

```swift
import XCTest
@testable import Clipsmith

@MainActor
final class BrowserWindowViewModelTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "BrowserWindowViewModelTests-\(UUID().uuidString)")
    }

    func testDefaultsToSnippets() {
        XCTAssertEqual(BrowserWindowViewModel(defaults: defaults).selectedSection, .snippets)
    }

    func testRemembersLastSection() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.selectedSection = .toolkit
        XCTAssertEqual(BrowserWindowViewModel(defaults: defaults).selectedSection, .toolkit)
    }

    func testApplySelectsSectionAndStoresDocsQuery() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.apply(BrowserOpenRequest(section: .docs, query: "map"), docLookupEnabled: true)
        XCTAssertEqual(vm.selectedSection, .docs)
        XCTAssertEqual(vm.pendingDocsQuery, "map")
    }

    func testApplyIgnoresQueryForOtherSections() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.apply(BrowserOpenRequest(section: .prompts, query: "x"), docLookupEnabled: true)
        XCTAssertNil(vm.pendingDocsQuery)
    }

    /// Review Focus 3.
    func testApplyFallsBackWhenDocsDisabled() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.selectedSection = .docs
        vm.apply(BrowserOpenRequest(section: nil, query: nil), docLookupEnabled: false)
        XCTAssertEqual(vm.selectedSection, .snippets)
        vm.apply(BrowserOpenRequest(section: .docs, query: "q"), docLookupEnabled: false)
        XCTAssertEqual(vm.selectedSection, .snippets)
        XCTAssertNil(vm.pendingDocsQuery)
    }
}
```

- [ ] **Step 2: Run to verify failure** — suite `BrowserWindowViewModelTests`. Expected: compile error.

- [ ] **Step 3: Implement the view model**, then `BrowserWindowView`, the `WindowGroup(id: "browser") { BrowserWindowView(docsetSearchService: appDelegate.docsetSearchService, docsetManagerService: appDelegate.docsetManagerService) }` with `.environment(appDelegate.pasteService) .environment(appDelegate.appTracker) .modelContainer(ClipsmithApp.sharedModelContainer) .frame(minWidth: 760, minHeight: 500)` and `.windowResizability(.contentSize)`, the `MenuBarView` changes ("Claude Toolkit..." → `openBrowser(.init(section: .toolkit, query: nil))`, remove `openClaudeToolkitWindow`), the `AppDelegate` autosave hook. Add pbxproj entries.

- [ ] **Step 4: Run to verify pass** — suite `BrowserWindowViewModelTests`: PASS. Build: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

Menu bar → Claude Toolkit… opens the browser window on Toolkit. ⌘1 shows the Snippets placeholder. Close, reopen: lands on the last section. Resize, close, reopen: size kept.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(browser): unified browser window with toolbar section picker and deep-link request

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Snippets section

**Files:**
- Create: `Clipsmith/Views/Browser/SnippetsSectionView.swift` (`AA0122`/`AF0122`), `Clipsmith/Services/SnippetFilter.swift` (`AA0123`/`AF0123`, group `GG0007 /* Services */` or wherever `SnippetStore.swift` sits)
- Create: `ClipsmithTests/SnippetFilterTests.swift` (`AA0124`/`AF0124`, test target)
- Modify: `Clipsmith/Views/Snippets/SnippetEditorView.swift` (no behaviour change; it becomes the detail body), `Clipsmith/Views/Browser/BrowserWindowView.swift` (wire `.snippets`), `Clipsmith/Views/MenuBarView.swift` ("Snippets..." → `openBrowser(.init(section: .snippets, query: nil))`; `.onReceive(.clipsmithOpenSnippets)` → same), `Clipsmith/App/AppDelegate.swift` (`activateSnippets` hotkey posts `.clipsmithRequestBrowser` with section snippets)
- Delete later (Task 7): `SnippetListView.swift`, `SnippetWindowView.swift`.

**Interfaces:**
- Produces (`SnippetFilter`, `nonisolated enum`):
  - `static func languages(in snippets: [ClipsmithSchemaV1.Snippet]) -> [BrowserFilterOption]` — distinct non-nil, non-empty `language` values, sorted case-insensitively, `id == label == language`.
  - `static func apply(_ snippets: [ClipsmithSchemaV1.Snippet], query: String, language: String?) -> [ClipsmithSchemaV1.Snippet]` — same text match as `SnippetListView.filteredSnippets` (name, content, tags, case-insensitive) AND `language == nil || snippet.language == language`.
- Produces (`SnippetsSectionView`): `init()`; `@Query` as in `SnippetListView`; `@State searchText`, `selectedSnippetID`, `languageFilter: String?`, `snippetStore`; `@FocusState isSearchFocused`. Layout: `HSplitView { BrowserListPane(search: BrowserSearchField("Search snippets…"), filter: BrowserFilterRow(options: SnippetFilter.languages(in: allSnippets), selection: $languageFilter), content: List of rows (title + language caption, double-click pastes, context menu Delete) with `.onKeyPress(.return)` paste, footer: BrowserCountsFooter("\(filtered.count) snippets", "")); detail }`. Detail: `BrowserDetailPane(header: Text(name).font(.headline) + language badge, body: SnippetEditorView(snippet:snippetStore:), footerLeading: Text("Edited \(snippet.updatedAt, format: .relative(presentation: .named))"), footerTrailing: Button("Paste ↩") { paste })` or `BrowserEmptyDetail(systemImage: "curlybraces", message: "Select a snippet")`. Toolbar: `ToolbarItemGroup(placement: .automatic) { Button(systemImage: "plus") { createNewSnippet() }.keyboardShortcut("n", modifiers: .command).help("New Snippet (⌘N)") }`. Hidden ⌘F / ⌘⌫ buttons. `createNewSnippet`, `deleteSnippet`, `pasteSnippet` copied from `SnippetListView` (paste closes windows with `identifier == "browser"` prefix or any visible non-panel window, then `.accessory`, then `pasteService.paste`). Remove the old "Name:" row duplication: `SnippetEditorView` keeps its own fields; the detail header shows the name read-only.

- [ ] **Step 1: Write the failing tests** (`SnippetFilterTests.swift`, uses `makeTestContainer()`)

```swift
import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class SnippetFilterTests: XCTestCase {
    private func snippets(in ctx: ModelContext) -> [ClipsmithSchemaV1.Snippet] {
        let a = ClipsmithSchemaV1.Snippet(name: "Config", content: "struct Config {}", language: "swift", tags: ["model"])
        let b = ClipsmithSchemaV1.Snippet(name: "drain", content: "kubectl drain", language: "bash")
        let c = ClipsmithSchemaV1.Snippet(name: "notes", content: "plain", language: nil)
        let d = ClipsmithSchemaV1.Snippet(name: "empty-lang", content: "x", language: "")
        [a, b, c, d].forEach(ctx.insert)
        return [a, b, c, d]
    }

    /// Review Focus 4.
    func testLanguagesIgnoreNilAndEmpty() throws {
        let ctx = try makeTestContainer().mainContext
        let opts = SnippetFilter.languages(in: snippets(in: ctx))
        XCTAssertEqual(opts.map(\.id), ["bash", "swift"])
    }

    func testApplyByLanguage() throws {
        let ctx = try makeTestContainer().mainContext
        let all = snippets(in: ctx)
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: "swift").map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: nil).count, 4)
    }

    func testApplyByQueryMatchesNameContentTags() throws {
        let ctx = try makeTestContainer().mainContext
        let all = snippets(in: ctx)
        XCTAssertEqual(SnippetFilter.apply(all, query: "MODEL", language: nil).map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "kubectl", language: "swift").count, 0)
    }
}
```

- [ ] **Step 2: Run to verify failure** — suite `SnippetFilterTests`. Expected: compile error.

- [ ] **Step 3: Implement `SnippetFilter`**, then `SnippetsSectionView`, wire it into `BrowserWindowView`, reroute menu + hotkey. Add pbxproj entries.

- [ ] **Step 4: Run to verify pass** — suite `SnippetFilterTests`: PASS. Build succeeds.

- [ ] **Step 5: Manual check**

⇧⌘B (default `activateSnippets`) opens the browser on Snippets. Language chips filter. ⌘N creates "Untitled Snippet" and selects it. Double-click a row pastes into the previous app and closes the window. The old Snippets window (menu item) still works until Task 7 removes it.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(browser): Snippets section with language chips, menu and hotkey rerouted

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Prompts section, retire the Snippets window

**Files:**
- Create: `Clipsmith/Views/Browser/PromptsSectionView.swift` (`AA0125`/`AF0125`), `Clipsmith/Services/PromptFilter.swift` (`AA0126`/`AF0126`)
- Create: `ClipsmithTests/PromptFilterTests.swift` (`AA0127`/`AF0127`, test target)
- Delete: `Clipsmith/Views/Snippets/SnippetWindowView.swift` (`AA/AF` for it: grep), `Clipsmith/Views/Snippets/SnippetListView.swift`, `Clipsmith/Views/Prompts/PromptLibraryView.swift` (group `GG0014 /* Prompts */` becomes empty → delete it and its line in `GG0005`)
- Modify: `Clipsmith/App/ClipsmithApp.swift` (remove `WindowGroup(id: "snippets")`), `Clipsmith/Views/MenuBarView.swift` ("Browse Prompts..." → `openBrowser(.init(section: .prompts, query: nil))`; delete `openSnippetWindow`, `openSnippetWindowOnPromptsTab`, `.clipsmithOpenSnippets`, `.clipsmithOpenPrompts` names and their `onReceive`s), `Clipsmith/App/AppDelegate.swift` (any remaining `.clipsmithOpenSnippets` post → `.clipsmithRequestBrowser`), `BrowserWindowView` (wire `.prompts`), `README.md` shortcut table rows "Open Snippets" (keep key, reword to "Open browser (Snippets)")

**Interfaces:**
- Produces (`PromptFilter`, `nonisolated enum`):
  - `enum Chip: Hashable, Sendable { case mine; case category(String) }` with `var id: String` (`"mine"` / the category) and `init?(id: String)`.
  - `static func options(in prompts: [ClipsmithSchemaV2.PromptLibraryItem]) -> [BrowserFilterOption]` — `BrowserFilterOption(id: "mine", label: "My Prompts")` first (only if any `isUserCreated`), then distinct categories of non-user prompts sorted case-insensitively.
  - `static func apply(_ prompts: [PromptLibraryItem], query: String, chip: Chip?) -> [PromptLibraryItem]` — the exact `PromptLibraryView.filteredPrompts` logic for `query` (including `#category text` and `#my`), then AND the chip: `.mine` → `isUserCreated`; `.category(c)` → `!isUserCreated && category == c`.
- Produces (`PromptsSectionView`): `init()`; state mirrors `PromptLibraryView` (`searchText`, `selectedPromptID`, `chipID: String?`, `promptStore`, `snippetStore`, `editedTitle`, `editedContent`, `saveTask`, focus states). Layout: `BrowserListPane(search: "Search prompts… (#coding, #my)", filter: BrowserFilterRow(options: PromptFilter.options(in: allPrompts), selection: $chipID), content: List with the existing `promptRow` (icon, title, edited dot, category badge; j/k and ↩ handling), footer: BrowserCountsFooter("\(filtered.count) prompts", "\(mineCount) mine"))`. Detail: `BrowserDetailPane(header: title TextField + category badge + "edited" tag, body: TextEditor(editedContent), footerLeading: variables caption + orange clipboard warning (existing code), footerTrailing: "Save to My Snippets", "Revert to Original" when applicable, "Paste ↩" (`.borderedProminent`))`. Toolbar: `plus` button (⌘N, "New Prompt (⌘N)"). Actions copied verbatim from `PromptLibraryView` (`createNewPrompt`, `deletePrompt`, `navigateList`, `scheduleSave`, `revertPrompt`, `saveToSnippets`, `pastePrompt`).

- [ ] **Step 1: Write the failing tests** (`PromptFilterTests.swift`)

```swift
import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class PromptFilterTests: XCTestCase {
    private func prompts(in ctx: ModelContext) -> [ClipsmithSchemaV2.PromptLibraryItem] {
        let a = ClipsmithSchemaV2.PromptLibraryItem(id: "a", title: "Analyze Logs", content: "logs", category: "analysis", version: 1)
        let b = ClipsmithSchemaV2.PromptLibraryItem(id: "b", title: "Add Error Handling", content: "errors", category: "coding", version: 1)
        let m = ClipsmithSchemaV2.PromptLibraryItem(id: "m", title: "Weekly Review", content: "review", category: "My Prompts", version: 1, isUserCreated: true)
        [a, b, m].forEach(ctx.insert)
        return [a, b, m]
    }

    func testOptionsPutMineFirstThenCategories() throws {
        let ctx = try makeTestContainer().mainContext
        XCTAssertEqual(PromptFilter.options(in: prompts(in: ctx)).map(\.id), ["mine", "analysis", "coding"])
        XCTAssertEqual(PromptFilter.options(in: prompts(in: ctx)).first?.label, "My Prompts")
    }

    func testChipMine() throws {
        let ctx = try makeTestContainer().mainContext
        XCTAssertEqual(PromptFilter.apply(prompts(in: ctx), query: "", chip: .mine).map(\.id), ["m"])
    }

    func testChipAndHashQueryBothApply() throws {
        let ctx = try makeTestContainer().mainContext
        let all = prompts(in: ctx)
        XCTAssertEqual(PromptFilter.apply(all, query: "#coding error", chip: nil).map(\.id), ["b"])
        XCTAssertEqual(PromptFilter.apply(all, query: "#coding", chip: .category("analysis")).count, 0)
        XCTAssertEqual(PromptFilter.apply(all, query: "#my", chip: nil).map(\.id), ["m"])
    }

    func testChipIDRoundTrip() {
        XCTAssertEqual(PromptFilter.Chip(id: "mine"), .mine)
        XCTAssertEqual(PromptFilter.Chip(id: "coding"), .category("coding"))
    }
}
```

`PromptLibraryItem.init(id:title:content:category:version:isUserCustomized:isUserCreated:sourceURL:)` — the labels above are correct.

- [ ] **Step 2: Run to verify failure** — suite `PromptFilterTests`: compile error.

- [ ] **Step 3: Implement `PromptFilter`**, then `PromptsSectionView`, wire it, delete the three old views and the `snippets` WindowGroup, reroute "Browse Prompts…". Add/remove pbxproj entries.

- [ ] **Step 4: Run to verify pass** — suite `PromptFilterTests`: PASS. Build succeeds. `grep -rn "clipsmithOpenSnippets\|clipsmithOpenPrompts\|SnippetWindowView\|\"snippets\"" Clipsmith` → no hits.

- [ ] **Step 5: Manual check**

Menu → Browse Prompts… opens the browser on Prompts. "My Prompts" chip shows only user prompts. Editing a title autosaves after ~0.75 s and shows the orange dot. "Paste ↩" substitutes `{{clipboard}}` and closes the window. Menu → Snippets… opens on Snippets.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(browser): Prompts section with category chips; retire Snippets window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: `DocsBrowserViewModel` — docset scoping and prefill

**Files:**
- Rename: `Clipsmith/Views/DocBezelViewModel.swift` → `Clipsmith/Views/Browser/DocsBrowserViewModel.swift` (`git mv`; `AF0071` path, move child line from `GG0005` to `GG0018`)
- Rename: `ClipsmithTests/DocBezelViewModelTests.swift` → `ClipsmithTests/DocsBrowserViewModelTests.swift` (`git mv`; update its `AF` path)
- Modify: both files; `Clipsmith/Views/DocBezelController.swift` (type rename only, so it still compiles until Task 9)

**Interfaces:**
- Produces (`@Observable @MainActor final class DocsBrowserViewModel`), everything from `DocBezelViewModel` plus:
  - `var selectedDocsetID: String?` — nil = all docsets. Setting it re-runs `performSearch` for the current query (debounced path not needed; call directly).
  - `var selectedDocset: DocsetInfo?` — lookup in `managerService?.enabledDocsets`.
  - `var entryCounts: [String: Int]` — slug → count, filled by `func loadEntryCounts()` which iterates `managerService?.enabledDocsets`, calls `searchService?.loadIndex(slug:from:)` off the main actor via `Task.detached` and stores `.count`.
  - `func open(withQuery query: String?)` — sets `searchText` to `query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""`; keeps `selectedDocsetID`; resets `selectedIndex = 0`. Whitespace-only becomes `""`.
  - `nonisolated static func targetDocsets(selectedDocsetID: String?, parsedFilter: String?, from docsets: [DocsetInfo], using service: DocsetSearchService) -> (docsets: [DocsetInfo], newSelection: String??)` — returns the docsets to search and `.some(id)` when the prefix should move the sidebar selection, `.some(nil)` never, `nil` (outer) when the selection must not change. Rules: parsedFilter non-nil → `service.matchingDocsets(filter:from:)`; if non-empty, result = `[first]`, newSelection = `.some(first.id)`; if empty, result = `[]`, newSelection = nil. parsedFilter nil and selectedDocsetID non-nil → `[the matching docset]` (or `[]` if it vanished), newSelection nil. Both nil → all `docsets`, newSelection nil.
  - `performSearch(query:)` uses `targetDocsets` and then calls `searchService.searchAll(query: parsed.query, docFilter: nil, docsets: target)`.

- [ ] **Step 1: Write the failing tests** — append to the renamed `DocsBrowserViewModelTests.swift` (update class and type names first)

```swift
private func docset(_ id: String, _ name: String) -> DocsetInfo {
    DocsetInfo(id: id, displayName: name, release: nil, dbSize: 0, homeURL: nil, codeURL: nil,
               docType: nil, isEnabled: true, isDownloaded: true)
}
private var all: [DocsetInfo] { [docset("go", "Go"), docset("django", "Django"), docset("mongoose", "Mongoose")] }

func testSelectedDocsetScopesExactlyOne() {
    let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: "go", parsedFilter: nil, from: all, using: DocsetSearchService())
    XCTAssertEqual(r.docsets.map(\.id), ["go"])
    XCTAssertNil(r.newSelection)
}

func testPrefixPicksFirstMatchAndMovesSelection() {
    let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: nil, parsedFilter: "go", from: all, using: DocsetSearchService())
    XCTAssertEqual(r.docsets.count, 1)
    XCTAssertEqual(r.newSelection, .some(r.docsets.first?.id))
}

/// Review Focus 2.
func testPrefixWithNoMatchKeepsSelection() {
    let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: "go", parsedFilter: "rust", from: all, using: DocsetSearchService())
    XCTAssertTrue(r.docsets.isEmpty)
    XCTAssertNil(r.newSelection)
}

func testNoSelectionNoPrefixSearchesAll() {
    let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: nil, parsedFilter: nil, from: all, using: DocsetSearchService())
    XCTAssertEqual(r.docsets.count, 3)
}

/// Review Focus 1.
func testOpenWithQueryWhitespaceClearsSearch() {
    viewModel.selectedDocsetID = "go"
    viewModel.open(withQuery: "   \n")
    XCTAssertEqual(viewModel.searchText, "")
    XCTAssertEqual(viewModel.selectedDocsetID, "go")
    XCTAssertTrue(viewModel.filteredResults.isEmpty)
}

func testOpenWithQueryTrimsAndKeepsSelection() {
    viewModel.selectedDocsetID = "go"
    viewModel.open(withQuery: "  fmt ")
    XCTAssertEqual(viewModel.searchText, "fmt")
    XCTAssertEqual(viewModel.selectedDocsetID, "go")
}
```

- [ ] **Step 2: Run to verify failure** — suite `DocsBrowserViewModelTests`: compile error.

- [ ] **Step 3: Implement** the rename, the new API, and the `performSearch` change. In `performSearch`, after computing `targetDocsets`, if `newSelection` is `.some(let id)` set `selectedDocsetID = id` **without** re-triggering a search (use a private flag or assign before the search runs). Update `DocBezelController` type references.

- [ ] **Step 4: Run to verify pass** — suite `DocsBrowserViewModelTests`: PASS (existing navigation tests included). Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(docs): DocsBrowserViewModel with docset scoping, prefix selection and prefill entry point

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Docs section (three columns), hotkey prefill, retire the floating panel

**Files:**
- Create: `Clipsmith/Views/Browser/DocsSectionView.swift` (`AA0128`/`AF0128`), `Clipsmith/Views/Browser/DocWebView.swift` (`AA0129`/`AF0129`; move `DocWebView` and `DocResultRow` out of `DocBezelView.swift` unchanged)
- Delete: `Clipsmith/Views/DocBezelController.swift` (`AF0073`), `Clipsmith/Views/DocBezelView.swift` (`AF0074`) and their `AA` entries
- Modify: `Clipsmith/App/AppDelegate.swift` (remove `docBezelController`; `activateDocLookup` handler and `openDocLookupFromMenu` capture selected text then post `.clipsmithRequestBrowser`), `Clipsmith/Views/MenuBarView.swift` ("Documentation Lookup..." posts `.clipsmithOpenDocLookup` as today — keep; `AppDelegate` turns it into the request so prefill works from both paths), `BrowserWindowView` (wire `.docs`, pass `viewModel` and the two stored services), `Clipsmith/Settings/KeyboardShortcutNames.swift` doc comment, `Clipsmith/Views/Settings/HotkeySettingsTab.swift` label if it says "bezel"

**Interfaces:**
- Consumes: Task 8 view model; Task 5 `pendingDocsQuery`.
- Produces (`DocsSectionView`): `init(windowViewModel: BrowserWindowViewModel, searchService: DocsetSearchService, managerService: DocsetManagerService)`; `@State private var docs = DocsBrowserViewModel()`; `@FocusState isSearchFocused`. On appear and on `NSWindow.didBecomeKeyNotification` for the browser window: `managerService.loadMetadata()`, inject services into `docs`, `docs.loadEntryCounts()`. `.onChange(of: windowViewModel.pendingDocsQuery)` and on appear: if non-nil → `docs.open(withQuery:)`, `isSearchFocused = true`, `windowViewModel.pendingDocsQuery = nil`. Layout: `HSplitView { sidebar; results; page }`.
  - Sidebar: `VStack` — `Text("Docsets")` caption header; `List(selection: $docs.selectedDocsetID)` with a `nil`-tagged "All docsets" row (trailing `enabledDocsets.count`) and one row per `managerService.enabledDocsets` (displayName, trailing `docs.entryCounts[id]` if present); footer `Button("Add docset…") { openDocsetSettings() }`. Frame `minWidth: 160, idealWidth: 190, maxWidth: 240`. Hidden ⌥↑/⌥↓ buttons move the selection through `[nil] + enabledDocsets.map(\.id)`.
  - Results: `BrowserListPane(search: BrowserSearchField("Search docs… (prefix: go:fmt)", trailing: docs.selectedDocset.map { Text("in \($0.displayName)").font(.caption).foregroundStyle(.secondary) }), filter: EmptyView(), content: List of DocResultRow bound to docs.selectedIndex with ↑↓ via .onKeyPress(.upArrow/.downArrow) calling navigateUp/Down while search keeps focus, footer: BrowserCountsFooter("\(docs.filteredResults.count) results", docs.selectedDocset?.displayName ?? "All docsets"))`. Empty states as in `DocBezelView`.
  - Page: `BrowserDetailPane(header: entry name + docsetName badge, body: DocWebView(html: docs.currentHTML), footerLeading: Text(sourcePath).font(.caption).foregroundStyle(.secondary), footerTrailing: Button("Open in Browser") { NSWorkspace.shared.open(url) }, Button("Copy Link") { pasteboard set })` where `url = URL(string: "https://devdocs.io/\(result.docsetID)/\(result.entry.path)")`. Empty: `BrowserEmptyDetail(systemImage: "book", message: "Select a result")`.
  - Toolbar: `ToolbarItemGroup(placement: .automatic) { Button(systemImage: "arrow.down.circle") { openDocsetSettings() }.help("Manage Docsets") }`.
  - `private func openDocsetSettings()` — `UserDefaults.standard.set(SettingsTab.docsets.rawValue, forKey: "selectedSettingsTab")`, `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` (same as `AppDelegate.handleOpenLicenseSettings`).
- Produces (`AppDelegate`): `private func requestDocsBrowser()` — guards `docLookupEnabled`; `let text = SelectedTextService.selectedText(from: appTracker.previousApp)`; posts `.clipsmithRequestBrowser` with `BrowserOpenRequest(section: .docs, query: text).userInfo`. Called by the `activateDocLookup` hotkey and by `openDocLookupFromMenu`.

- [ ] **Step 1: Build the section and wiring**, delete the two bezel files and their pbxproj entries, add the new ones.

- [ ] **Step 2: Build** — `** BUILD SUCCEEDED **`. `grep -rn "DocBezel" Clipsmith ClipsmithTests` → no hits.

- [ ] **Step 3: Run** suites `DocsBrowserViewModelTests`, `BrowserWindowViewModelTests` — PASS.

- [ ] **Step 4: Manual check**

Enable Documentation Lookup in Settings > Features. Select a word in another app, press ⇧⌘D: the browser opens on Docs with that word in the search field, field focused, "All docsets" selected. Click a docset in the sidebar: results narrow, footer shows its name. Type `go:fmt`: Go is selected in the sidebar. Press ⌥↓: selection moves. "Add docset…" opens Settings on Docsets; download one, return to the window: it appears in the sidebar. Disable the flag: Docs segment disappears and the hotkey does nothing.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(docs): three-column Docs section with docset sidebar; hotkey prefill; remove floating doc panel

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Documentation, CLAUDE.md, final sweep

**Files:**
- Modify: `CLAUDE.md` (Bezel pattern "used 2 times"; remove `GistService` and `DocBezel*` lines; add a "### Browser Window" subsection listing `BrowserWindowView`, `BrowserWindowViewModel`, `BrowserSection`, `BrowserPanes`, the four section views, `DocsBrowserViewModel`; update "Adding a menu bar item" to mention `.clipsmithRequestBrowser`; schema line `ClipsmithSchemaV3`), `README.md` ("Documentation Lookup" bullets: panel → section of the browser window; "Documentation Browser" key table: add `⌥↑ ⌥↓` docset, `⌘1–⌘4` sections; "Open Snippets" row; Feature flag text "doc browser bezel" → "Docs section"), `site/index.html` (any "panel"/"window" copy for docs and snippets, if present), `CHANGELOG.md` (`### Changed` entry under `[Unreleased]`)

- [ ] **Step 1: CHANGELOG entry**

```markdown
### Changed

- Snippets, Prompts, Documentation and Claude Toolkit now live in one browser window with a
  toolbar section picker (⌘1–⌘4), in the Claude Toolkit layout. Filters are chip rows under the
  search field. Documentation gets a docset sidebar that scopes the search; the floating
  documentation panel is gone, and the hotkey opens the window on Docs with the selected text.
```

- [ ] **Step 2: Apply the CLAUDE.md and README edits.**

- [ ] **Step 3: Full verification**

Run the build command, then the full-suite command. Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`. Then `grep -rni "gist\|DocBezel\|SnippetWindowView\|claude-toolkit\"" Clipsmith ClipsmithTests README.md site/index.html CLAUDE.md` → hits only in `ClipsmithSchemaV1.swift`, `ClipsmithSchemaV2.swift`, `CHANGELOG.md`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: unified browser window in CLAUDE.md, README, site and changelog

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
