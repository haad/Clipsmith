---
phase: 05-prompt-library
verified: 2026-03-11T14:00:00Z
status: human_needed
score: 18/18 automated must-haves verified
re_verification: false
human_verification:
  - test: "First launch: bundled prompts load without network"
    expected: "Opening Prompts tab (cmd+2) shows 11 default prompts across 4 categories (4 coding, 3 writing, 2 analysis, 2 creative)"
    why_human: "Requires running the app from a clean state (no existing SwiftData store) to verify first-launch guard triggers loadBundledPrompts"
  - test: "Prompt bezel opens via hotkey and pastes with variable substitution"
    expected: "Hotkey opens frosted glass NSPanel with prompt list; Tab cycles categories; Enter pastes selected prompt with {{clipboard}} substituted with actual clipboard content"
    why_human: "End-to-end keyboard flow through non-activating NSPanel cannot be tested programmatically; requires visual inspection and real paste"
  - test: "Category cycling via Tab key in bezel"
    expected: "Tab advances: All > coding > writing > analysis > creative > My Prompts > All (wraps)"
    why_human: "NSPanel keyboard event interception is not unit-testable; Tab must not move focus out of search field"
  - test: "#category search syntax in bezel"
    expected: "Typing #coding in bezel shows only coding prompts; typing #coding review filters to coding + title/content contains review"
    why_human: "Requires live @Query + PromptBezelViewModel interaction; not covered by unit tests"
  - test: "Prompts tab editing: in-place edit with auto-save and edited indicator"
    expected: "Editing a library prompt shows orange dot/edited badge; saving calls promptStore.update() (setting isUserCustomized=true); Revert to Original works with NSAlert confirmation"
    why_human: "Debounced 0.75s save + NSAlert + UI state changes require human interaction"
  - test: "Save to My Snippets creates independent copy"
    expected: "Clicking Save to My Snippets creates a Snippet via SnippetStore; switch to Snippets tab (cmd+1) and verify the item appears with tags [prompt, category]"
    why_human: "Cross-store operation (PromptLibraryStore -> SnippetStore) cannot be verified visually without running the app"
  - test: "Settings Prompts tab: Sync Now, last-synced status, template variables"
    expected: "Preferences > Prompts tab shows JSON URL field with default value, Sync Now button, last-synced relative date after sync, user-defined variable add/delete rows, orange clipboard warning"
    why_human: "SwiftUI Form visual layout and interactive sync behavior require visual inspection"
---

# Phase 5: Prompt Library Verification Report

**Phase Goal:** An HTTP-synced prompt library with bundled defaults, a searchable prompt bezel as the primary fast-access interface, a Prompts management tab in the snippet window, {{variable}} template substitution on paste, and user customization via in-place editing and Save to My Snippets
**Verified:** 2026-03-11T14:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can configure a JSON URL in Settings and sync prompts by category | VERIFIED | `PromptLibrarySettingsSection.swift` has `@AppStorage(promptLibraryURL)` with default URL, Sync Now button calling `syncService.syncFromURL()`, `SettingsView.swift` has Prompts tab wired to `PromptLibrarySettingsSection` |
| 2 | User can browse prompts by category in snippet window Prompts tab, library vs user-created visually distinct | VERIFIED | `PromptLibraryView.swift` has `book.fill` (library) vs `person.fill` (user-created) icons with `.secondary`/`.accentColor` styling; `SnippetWindowView.swift` has 3-tab picker with Prompts as tag(1); cmd+2 shortcut wired |
| 3 | Sync respects per-prompt versioning and never overwrites user-customized copies | VERIFIED | `PromptLibraryStore.upsert()` guards: `guard !existing.isUserCustomized` (skips user-edited) then `guard remote.version > existing.version` (skips same/older version); `PromptLibraryStoreTests.testUpsertSkipsWhenUserCustomized` and `testUpsertSkipsWhenRemoteVersionNotNewer` present |
| 4 | User can copy any library prompt to personal snippets via Save to My Snippets | VERIFIED | `PromptLibraryView.saveToSnippets()` calls `snippetStore.insert(name:content:language:tags:)` with `tags: ["prompt", category]`; `snippetStore` initialized from `modelContext.container` |
| 5 | Template variables {{clipboard}} and user-defined substituted on paste | VERIFIED | `TemplateSubstitutor.substitute(in:variables:)` uses Swift Regex `/\{\{(?<variable>[^}]+)\}\}/` with whitespace trimming; both `PromptBezelController.pasteAndHide()` and `PromptLibraryView.pastePrompt()` call it; `TemplateSubstitutorTests` has 11 tests covering all cases |
| 6 | Pressing Enter on a selected prompt in the prompt bezel pastes it with variable substitution | VERIFIED | `PromptBezelController.keyDown()` routes keyCode 36/76 to `Task { await pasteAndHide() }`; `pasteAndHide()` reads clipboard, merges UserDefaults variables, calls `TemplateSubstitutor.substitute`, then `pasteService.paste(content:into:)` |

**Score:** 6/6 truths fully verified by code inspection

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FlycutSwift/Models/Schema/FlycutSchemaV2.swift` | PromptLibraryItem @Model definition | VERIFIED | 83 lines; `@Model final class PromptLibraryItem` with 10 fields (id, title, content, category, version, isUserCustomized, isUserCreated, sourceURL, createdAt, updatedAt); `#Index<PromptLibraryItem>([\.category], [\.title])`; typealias re-exports for V1 models |
| `FlycutSwift/Models/Schema/FlycutMigrationPlan.swift` | V1-to-V2 lightweight migration | VERIFIED | 21 lines; `schemas: [FlycutSchemaV1.self, FlycutSchemaV2.self]`; `MigrationStage.lightweight(fromVersion: FlycutSchemaV1.self, toVersion: FlycutSchemaV2.self)` |
| `FlycutSwift/App/FlycutApp.swift` | Uses FlycutSchemaV2.models | VERIFIED | `let schema = Schema(FlycutSchemaV2.models)` confirmed at line 16 |
| `FlycutSwift/Services/PromptLibraryStore.swift` | @ModelActor CRUD + upsert | VERIFIED | 266 lines; full CRUD: insert, fetchAll, fetchByCategory, search (#category syntax), upsert (version-aware), update (isUserCustomized), revertToOriginal, delete, content(for:), prompt(for:); `PromptInfo` Sendable struct, `PromptDTO`, `PromptCatalog` |
| `FlycutSwift/Services/TemplateSubstitutor.swift` | {{variable}} substitution | VERIFIED | 55 lines; `substitute(in:variables:)` with computed var Regex to avoid Swift 6 Sendable issue; `extractVariables(from:)` with deduplication; whitespace trimming; unknown vars left as-is |
| `FlycutSwift/Resources/prompts.json` | Bundled default prompts | VERIFIED | 11 prompts across 4 categories: coding (4), writing (3), analysis (2), creative (2); all use `{{clipboard}}` |
| `FlycutSwift/Services/PromptSyncService.swift` | HTTP fetch + bundled JSON loading | VERIFIED | 167 lines; `@MainActor @Observable`; `loadBundledPrompts(store:)` reads Bundle.main; `syncFromURL(_:store:)` does URLSession HTTP GET; `PromptSyncError` enum with 5 cases and `LocalizedError` descriptions; `isSyncing`/`lastError` observable properties |
| `FlycutSwift/Views/Settings/PromptLibrarySettingsSection.swift` | Settings tab for Prompt Library | VERIFIED | 156 lines; Sync section (URL field + Sync Now button + error display + last-synced relative date), Template Variables section (key-value list editor with JSON persistence), Security section (orange clipboard warning) |
| `FlycutSwift/Views/SettingsView.swift` | Prompts tab in settings TabView | VERIFIED | `PromptLibrarySettingsSection().tabItem { Label("Prompts", systemImage: "text.book.closed") }` present; tab order: General, Shortcuts, Prompts, Gist |
| `FlycutSwift/Views/PromptBezelViewModel.swift` | Observable VM with category cycling | VERIFIED | 214 lines; `@Observable @MainActor`; `static let allCategories = ["All", "coding", "writing", "analysis", "creative", "My Prompts"]`; `cycleCategory()` with wraparound; `recomputeFilteredPrompts()` with #category prefix parsing; full navigation methods; `currentPrompt`, `navigationLabel`, `categoryLabel` computed properties |
| `FlycutSwift/Views/PromptBezelView.swift` | SwiftUI bezel view | VERIFIED | 211 lines; `@Query(sort: \FlycutSchemaV2.PromptLibraryItem.title)`; `@Bindable var viewModel: PromptBezelViewModel`; category header bar with "Tab to cycle" hint; always-visible search field; scrollable prompt list with category badges (coding=blue, writing=green, analysis=purple, creative=orange, My Prompts=gray); orange dot for isUserCustomized; frosted glass background matching clipboard bezel |
| `FlycutSwift/Views/PromptBezelController.swift` | Non-activating NSPanel | VERIFIED | 322 lines; `.nonactivatingPanel` in init styleMask; `sendEvent` intercepts Escape (53), arrows (125/126/123/124/121/116/119/115), and Tab (48) before SwiftUI; `keyDown` routes all keys including j/k and 0-9; `pasteAndHide()` reads clipboard + merges UserDefaults vars + calls `TemplateSubstitutor.substitute` + calls `pasteService.paste` |
| `FlycutSwift/Views/Prompts/PromptLibraryView.swift` | Prompts management tab | VERIFIED | 527 lines; `@Query(sort: \FlycutSchemaV2.PromptLibraryItem.title)`; HSplitView master-detail; `book.fill`/`person.fill` icons; #category search syntax; debounced 0.75s auto-save with `Task.sleep + saveTask?.cancel()`; `detailView` with editable TextEditor + variable detection (TemplateSubstitutor.extractVariables) + {{clipboard}} warning; Save to My Snippets; NSAlert revert confirmation |
| `FlycutSwift/Views/Snippets/SnippetWindowView.swift` | 3-tab layout | VERIFIED | Segmented Picker with Snippets(tag:0), Prompts(tag:1), Gists(tag:2); `PromptLibraryView()` at `selectedTab == 1`; cmd+1/2/3 keyboard shortcuts; `.onReceive(.flycutOpenPrompts)` sets `selectedTab = 1` |
| `FlycutSwift/App/AppDelegate.swift` | Full prompt library wiring | VERIFIED | `promptLibraryStore`, `promptSyncService`, `promptBezelController` properties; all initialized in `applicationDidFinishLaunching`; empty store guard before `loadBundledPrompts`; `promptBezelController.pasteService = pasteService`, `.appTracker = appTracker`; `KeyboardShortcuts.onKeyDown(for: .activatePrompts)` registered; `promptBezelController?.hide()` in `applicationWillTerminate` |
| `FlycutSwift/Settings/KeyboardShortcutNames.swift` | activatePrompts hotkey name | VERIFIED | `static let activatePrompts = Self("activatePrompts")` at line 16 |
| `FlycutSwift/Views/MenuBarView.swift` | Browse Prompts menu item | VERIFIED | `Button("Browse Prompts...")` calls `openSnippetWindowOnPromptsTab()`; `flycutOpenPrompts` Notification.Name defined; `openSnippetWindowOnPromptsTab()` opens window + 150ms delay + posts `.flycutOpenPrompts` |
| `FlycutSwift/Views/Settings/HotkeySettingsTab.swift` | Prompt Library hotkey recorder | VERIFIED | `KeyboardShortcuts.Recorder("Prompt Library", name: .activatePrompts)` present |
| `FlycutTests/SchemaMigrationTests.swift` | Schema migration unit tests | VERIFIED | 5 tests: V2 model count=4, container creation, insert/fetch PromptLibraryItem, field defaults, V1 models work with V2 |
| `FlycutTests/PromptLibraryStoreTests.swift` | Store CRUD + upsert tests | VERIFIED | 12 tests: insert/fetchAll, fetchByCategory, search (title/content), #coding filter, #coding+text filter, upsert inserts new, upsert updates when newer, upsert skips isUserCustomized, upsert skips same/older version, update sets isUserCustomized, revertToOriginal clears flag, delete, prompt(for:), content(for:) |
| `FlycutTests/TemplateSubstitutorTests.swift` | Template substitution tests | VERIFIED | 11 tests: basic, clipboard, unknown left as-is, multiple, adjacent, whitespace trim, no variables, extractVariables, deduplication, empty, partial known+unknown |
| `FlycutTests/TestModelContainer.swift` | Uses FlycutSchemaV2 | VERIFIED | `Schema(FlycutSchemaV2.models)` — updated from V1 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `FlycutMigrationPlan.swift` | `FlycutSchemaV2.swift` | `MigrationStage.lightweight(fromVersion: FlycutSchemaV1.self, toVersion: FlycutSchemaV2.self)` | WIRED | Pattern `migrateV1toV2` + `lightweight` confirmed at lines 17-20 |
| `FlycutApp.swift` | `FlycutSchemaV2.swift` | `Schema(FlycutSchemaV2.models)` | WIRED | Confirmed at line 16 |
| `PromptLibraryStore.swift` | `FlycutSchemaV2.swift` | `FetchDescriptor<FlycutSchemaV2.PromptLibraryItem>` | WIRED | Used in fetchAll, fetchByCategory, search, and upsert methods |
| `PromptSyncService.swift` | `PromptLibraryStore.swift` | `store.upsert(remote:)` calls during sync | WIRED | `loadBundledPrompts` and `syncFromURL` both loop `for prompt in catalog.prompts { try await store.upsert(remote: prompt) }` |
| `PromptLibrarySettingsSection.swift` | `PromptSyncService.swift` | `syncService.syncFromURL()` button action | WIRED | `Button("Sync Now") { Task { try await syncService.syncFromURL(promptLibraryURL, store: store) } }` |
| `SettingsView.swift` | `PromptLibrarySettingsSection.swift` | New Prompts tab in TabView | WIRED | `PromptLibrarySettingsSection().tabItem { Label("Prompts", ...) }` confirmed |
| `PromptBezelController.swift` | `PromptBezelViewModel.swift` | `viewModel.navigate*` / `viewModel.cycleCategory()` calls | WIRED | `viewModel.navigateDown()`, `viewModel.navigateUp()`, `viewModel.cycleCategory()` etc. throughout keyDown |
| `PromptBezelView.swift` | `PromptBezelViewModel.swift` | `@Bindable var viewModel: PromptBezelViewModel` | WIRED | Line 24: `@Bindable var viewModel: PromptBezelViewModel`; `viewModel.searchText`, `viewModel.filteredPrompts`, `viewModel.selectedIndex` etc. used throughout body |
| `PromptBezelController.swift` | `TemplateSubstitutor.swift` | `TemplateSubstitutor.substitute(in:variables:)` before paste | WIRED | `pasteAndHide()` calls `let substituted = TemplateSubstitutor.substitute(in: prompt.content, variables: variables)` |
| `PromptLibraryView.swift` | `PromptLibraryStore.swift` | `promptStore.*` operations | WIRED | `promptStore?.update()`, `promptStore?.revertToOriginal()`, `promptStore?.insert()`, `promptStore?.delete()` all used |
| `PromptLibraryView.swift` | `SnippetStore.swift` | `snippetStore.insert()` for Save to My Snippets | WIRED | `saveToSnippets()` calls `snippetStore?.insert(name:content:language:tags:)` |
| `SnippetWindowView.swift` | `PromptLibraryView.swift` | Prompts tab (tag 1) in Picker | WIRED | `} else if selectedTab == 1 { PromptLibraryView() }` |
| `AppDelegate.swift` | `PromptBezelController.swift` | Creates and wires PromptBezelController | WIRED | `promptBezelController = PromptBezelController(modelContainer:)`; `.pasteService = pasteService`; `.appTracker = appTracker` |
| `AppDelegate.swift` | `PromptSyncService.swift` | Creates PromptSyncService + loads bundled prompts | WIRED | `promptSyncService = PromptSyncService()`; `Task { ... promptSyncService.loadBundledPrompts(store: promptLibraryStore) }` |
| `KeyboardShortcutNames.swift` | `AppDelegate.swift` | `KeyboardShortcuts.onKeyDown(for: .activatePrompts)` | WIRED | `KeyboardShortcuts.onKeyDown(for: .activatePrompts)` block at line 209 of AppDelegate |
| `MenuBarView.swift` | `SnippetWindowView.swift` | `flycutOpenPrompts` notification: MenuBarView posts, SnippetWindowView observes | WIRED | `openSnippetWindowOnPromptsTab()` posts `.flycutOpenPrompts`; `SnippetWindowView.onReceive(.flycutOpenPrompts)` sets `selectedTab = 1` |

### Requirements Coverage

**Note:** PMPT requirements are defined in `05-RESEARCH.md` and `ROADMAP.md`, not in `REQUIREMENTS.md` (which only contains base v1/v2 requirement IDs). REQUIREMENTS.md does not map any PMPT IDs to Phase 5 — there are no orphaned entries.

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PMPT-01 | 05-01, 05-02, 05-05 | Prompts available on first launch organized by category | SATISFIED | `prompts.json` (11 prompts, 4 categories); `PromptSyncService.loadBundledPrompts()` reads Bundle.main; AppDelegate empty-store guard triggers on first launch; `PromptSyncService.syncFromURL()` for subsequent HTTP syncs |
| PMPT-02 | 05-03, 05-04 | User can browse prompts by category in snippet window, library vs user-created visually distinct | SATISFIED | `PromptLibraryView` has `book.fill`/`person.fill` icons, category badges, `SnippetWindowView` 3-tab with Prompts at cmd+2; prompt bezel has category cycling with header badge |
| PMPT-03 | 05-01, 05-02 | User can sync from public URL; versioning prevents overwriting user-customized copies | SATISFIED | `PromptSyncService.syncFromURL()` via URLSession; `PromptLibraryStore.upsert()` guards: `isUserCustomized` check + version comparison; 3 tests in PromptLibraryStoreTests |
| PMPT-04 | 05-01, 05-04 | User can copy library prompt to personal snippets | SATISFIED | `PromptLibraryView.saveToSnippets()` calls `snippetStore.insert(name:content:language:tags: ["prompt", category])`; independent of future syncs (creates Snippet, not PromptLibraryItem) |
| PMPT-05 | 05-01, 05-03 | Template variables substituted with clipboard content on paste | SATISFIED | `TemplateSubstitutor.substitute(in:variables:)` with Swift Regex; both `PromptBezelController.pasteAndHide()` and `PromptLibraryView.pastePrompt()` read clipboard + merge user vars + call substitutor; 11 tests in TemplateSubstitutorTests |
| PMPT-06 | 05-03, 05-05 | Enter on selected prompt in bezel pastes with substitution | SATISFIED | `PromptBezelController.keyDown()` routes Return/Enter (keyCode 36/76) to `pasteAndHide()`; full substitution pipeline confirmed; hotkey registered in AppDelegate |
| PMPT-07 | 05-01 | Sync never overwrites user-customized copies | SATISFIED | `PromptLibraryStore.upsert()` first guard: `guard !existing.isUserCustomized else { return }`; `testUpsertSkipsWhenUserCustomized` test confirms behavior; `update()` sets `isUserCustomized = true` |

**PMPT requirements coverage: 7/7 (100%)**

**Orphaned PMPT requirements:** None. All 7 PMPT IDs are claimed by at least one plan and have implementation evidence.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | No stubs, TODOs, or placeholder returns detected in any Phase 5 files |

Scanned files: FlycutSchemaV2.swift, FlycutMigrationPlan.swift, PromptLibraryStore.swift, TemplateSubstitutor.swift, PromptSyncService.swift, PromptLibrarySettingsSection.swift, PromptBezelViewModel.swift, PromptBezelView.swift, PromptBezelController.swift, PromptLibraryView.swift, SnippetWindowView.swift, AppDelegate.swift (Phase 5 sections), KeyboardShortcutNames.swift, MenuBarView.swift, HotkeySettingsTab.swift, TestModelContainer.swift, SchemaMigrationTests.swift, PromptLibraryStoreTests.swift, TemplateSubstitutorTests.swift.

### Human Verification Required

The automated checks confirm all code exists, is substantive, and is properly wired. The following behaviors require human testing in the running app:

#### 1. First Launch Bundled Prompts

**Test:** Delete or rename the SwiftData store (`~/Library/Application Support/com.generalarcade.flycut/`), build and run the app, open the snippet window (Snippets button in menu bar), switch to Prompts tab (cmd+2).
**Expected:** 11 default prompts are visible organized by category badge: 4 coding (Swift Code Review, Explain Code, Fix Bug, Write Tests), 3 writing (Summarize Text, Rewrite Formally, Fix Grammar), 2 analysis (Analyze Data, Compare Options), 2 creative (Brainstorm Ideas, Write Story).
**Why human:** Requires a clean SwiftData state to trigger the empty-store first-launch guard. Integration of `loadBundledPrompts` + SwiftData @Query cannot be verified without running the app.

#### 2. Prompt Bezel Opens via Hotkey and Pastes

**Test:** Set a hotkey for "Prompt Library" in Preferences > Shortcuts. Copy any text to clipboard. Press the hotkey. Navigate with arrow keys. Press Enter.
**Expected:** Frosted glass NSPanel appears (same visual style as clipboard bezel). The pasted result in the target app has `{{clipboard}}` replaced with the clipboard content at the moment of pressing Enter (not when the bezel opened).
**Why human:** NSPanel non-activating behavior, hotkey registration, and clipboard-at-paste-time semantics require a real macOS session.

#### 3. Tab Key Cycles Categories Without Losing Focus

**Test:** Open the prompt bezel. Press Tab multiple times.
**Expected:** Category header changes: All Prompts > Coding > Writing > Analysis > Creative > My Prompts > All Prompts. The search TextField remains focused (typing still filters). Tab does NOT move focus out of the search field.
**Why human:** sendEvent override intercepting Tab (keyCode 48) before SwiftUI TextField focus change is a critical behavior that only manifests in a real NSPanel session.

#### 4. In-Place Editing with Auto-Save and Edited Indicator

**Test:** In the Prompts tab, select a library prompt (e.g., "Swift Code Review"). Edit its content. Wait 1 second. Check the list row.
**Expected:** An orange circle "edited" dot appears on the list row. The detail view shows an "edited" badge next to the category badge. The edit persists after switching away and back. The sync skip guard (`isUserCustomized=true`) now protects this prompt from being overwritten.
**Why human:** Debounced auto-save (0.75s `Task.sleep` with `saveTask?.cancel()`) requires real timing interaction.

#### 5. Revert to Original with NSAlert Confirmation

**Test:** After editing a library prompt (step 4), click "Revert to Original" in the detail view.
**Expected:** NSAlert appears: "Revert to Original?" with warning that edits will be discarded. Clicking "Revert" clears the edited indicator. Clicking "Cancel" preserves the edits.
**Why human:** NSAlert.runModal() in a SwiftUI context requires real window hierarchy.

#### 6. Save to My Snippets Creates Independent Copy

**Test:** In the Prompts tab, select any library prompt. Click "Save to My Snippets". Switch to Snippets tab (cmd+1).
**Expected:** A new snippet appears with the prompt's title and content, tagged with ["prompt", category]. Editing it in the Snippets tab has no effect on the original library prompt. Future syncs do not affect the snippet copy.
**Why human:** Cross-store operation (PromptLibraryStore to SnippetStore) with @Query refresh requires visual confirmation.

#### 7. Settings Prompts Tab UI and Sync Flow

**Test:** Open Preferences (cmd+comma). Click the Prompts tab.
**Expected:** Three sections visible: Sync (JSON URL field pre-populated with default GitHub URL, "Sync Now" button, last-synced relative date after sync, red error text if sync fails), Template Variables (explanation text, key-value list editor, "{{clipboard}} is built-in" note), Security (orange clipboard warning text). Adding a variable (e.g., name=Claude), creating a prompt with `{{name}}`, and using it from the bezel should substitute "Claude".
**Why human:** SwiftUI Form layout, @AppStorage binding behavior, and live URLSession sync require visual inspection.

### Gaps Summary

No gaps found in automated verification. All 18 required artifacts exist, are substantive (non-stub), and are properly wired to their dependencies. All 7 PMPT requirements are satisfied by verified code. All 6 ROADMAP success criteria are supported by the implementation.

The 7 human verification items cover behaviors that are correct in code but cannot be confirmed without running the app: timing-sensitive first-launch loading, NSPanel keyboard interception, NSAlert modal presentation, debounced auto-save timing, and real URLSession network calls.

---

_Verified: 2026-03-11T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
