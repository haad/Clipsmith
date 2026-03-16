# Roadmap: Flycut Swift

## Overview

A full rewrite of Flycut from Objective-C/AppKit to Swift 6 + SwiftUI + SwiftData, targeting macOS 15+. The work proceeds in dependency-ordered phases: foundation infrastructure first, then the core clipboard engine (the entire product), then the visible UI surfaces, then extended features (favorites, snippets, Gist sharing, prompt library), and finally documentation lookup. Nothing in a later phase can be built until the prior phase is stable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - App scaffolding, SwiftData schema, settings, permissions, and launch infrastructure (completed 2026-03-05)
- [x] **Phase 2: Core Engine** - Clipboard capture, paste injection, hotkeys, and persistence — the entire product behavior (completed 2026-03-05)
- [x] **Phase 3: UI Layer** - Bezel HUD, menu bar dropdown, search, and full preferences window (completed 2026-03-05)
- [x] **Phase 3.1: ObjC Parity Bug Fixes** - 30+ behavioural fixes across clipboard capture, hotkey UX, bezel interaction, settings, menu bar, and polish (INSERTED, completed 2026-03-09)
- [x] **Phase 4: Code Snippets & Gist Sharing** - Code snippet editor with syntax highlighting and GitHub Gist sharing (completed 2026-03-09)
- [x] **Phase 5: Prompt Library** - HTTP-synced prompt library with bundled defaults, searchable prompt bezel, categories, template variables, and user customization (completed 2026-03-11)
- [x] **Phase 6: Quick Actions & Performance** - Quick actions on clips (transform, format, share), adaptive polling, history export/import, and reliability improvements (completed 2026-03-12)
- [x] **Phase 7: Intelligent Search & AI** - Fuzzy matching, source app and date filtering, on-device AI integration via Apple Foundation Models (completed 2026-03-12)
- [x] **Phase 8: Documentation Lookup** - Quick documentation search via hotkey with downloaded docsets (completed 2026-03-16)
- [ ] **Phase 9: Favorites** - Pin clippings as favorites with dedicated view and hotkey; favorites survive history clearing

## Phase Details

### Phase 1: Foundation
**Goal**: A running macOS app with correct activation policy, SwiftData schema, settings storage, accessibility permission monitoring, and launch-at-login — no user-visible features except a menu bar icon
**Depends on**: Nothing (first phase)
**Requirements**: SHELL-01, SHELL-03, SHELL-04, SETT-01, SETT-02, SETT-03, SETT-04, SETT-05
**Success Criteria** (what must be TRUE):
  1. App appears in menu bar with a status icon and no dock icon
  2. App can be configured to launch at login via the preferences toggle
  3. App displays Accessibility permission status and prompts user to grant it if missing
  4. Preferences window opens and accepts changes to hotkeys, history size, and display settings
  5. All user settings persist across app restarts
**Plans:** 2/2 plans complete

Plans:
- [x] 01-01-PLAN.md — Xcode project, app shell, SwiftData schema, accessibility monitor
- [x] 01-02-PLAN.md — Settings infrastructure, preferences UI, launch-at-login, hotkey recorders

### Phase 2: Core Engine
**Goal**: Clipboard history is captured, deduplicated, password-filtered, and persisted — and a selected clipping can be pasted into the previously frontmost app via keyboard hotkey with correct timing
**Depends on**: Phase 1
**Requirements**: CLIP-01, CLIP-02, CLIP-03, CLIP-04, CLIP-05, CLIP-06, CLIP-07, CLIP-08, INTR-01, INTR-03, INTR-05
**Success Criteria** (what must be TRUE):
  1. Copying any text in any app adds it to clipboard history automatically; copying the same text twice does not create a duplicate
  2. Password manager entries and transient pasteboard types never appear in clipboard history
  3. Clipboard history survives an app restart and respects the configured maximum history size
  4. Pressing the global hotkey and then Enter pastes the selected clipping as plain text into the previously active app
  5. Pressing the search hotkey opens a search interface where typing filters the clipping list
**Plans:** 3/3 plans complete

Plans:
- [ ] 02-01-PLAN.md — XCTest target, ClipboardStore @ModelActor with TDD (persistence, dedup, trim, delete, clear)
- [ ] 02-02-PLAN.md — ClipboardMonitor (pasteboard polling + password/transient filter), PasteService (CGEventPost), AppTracker
- [ ] 02-03-PLAN.md — Integration wiring in AppDelegate, hotkey registration, MenuBarView with real clipping list

### Phase 3: UI Layer
**Goal**: Users can navigate and use clipboard history through the keyboard-driven bezel HUD, menu bar dropdown, and search — the full interaction model is visible and functional
**Depends on**: Phase 2
**Requirements**: BEZL-01, BEZL-02, BEZL-03, BEZL-04, BEZL-05, INTR-02, INTR-04, SHELL-02
**Success Criteria** (what must be TRUE):
  1. Pressing the global hotkey shows a floating bezel HUD centered on the current monitor without stealing focus from the frontmost app
  2. Arrow keys navigate through clipping history, the selected clipping content is visible in the bezel, and pressing Enter pastes it
  3. The bezel works over fullscreen apps and across all Spaces; pressing Escape or clicking outside dismisses it
  4. The menu bar dropdown shows recent clippings with preview text that can be clicked to paste
  5. Typing in the bezel filters visible clippings by content
**Plans:** 2/2 plans complete

Plans:
- [ ] 03-01-PLAN.md — BezelViewModel TDD + BezelController NSPanel + BezelView SwiftUI + unit tests
- [ ] 03-02-PLAN.md — Wire BezelController into AppDelegate hotkeys + human-verify full interaction flow

### Phase 03.1: ObjC Parity Bug Fixes (INSERTED)

**Goal:** Achieve 1:1 functional parity with the original ObjC Flycut — fix 30+ behavioural gaps across clipboard capture (source app metadata, dedup-to-top), hotkey UX (hold-navigate-release), bezel interaction (j/k, scroll, double-click, delete), settings (16 new preferences), menu bar (pause, icons, about), and polish (paste timing, accessibility alert, save-to-file)
**Requirements**: BUG-01, BUG-02, BUG-03, BUG-04, BUG-07, BUG-08, BUG-09, BUG-10, BUG-11, BUG-12, BUG-13, BUG-14, BUG-15, BUG-16, BUG-17, BUG-18, BUG-19, BUG-20, BUG-23, BUG-24, BUG-25, BUG-26, BUG-28, BUG-29, BUG-33
**Depends on:** Phase 3
**Success Criteria** (what must be TRUE):
  1. Clipboard monitor captures source app name and bundle URL on every copy
  2. Re-copying identical text moves the clipping to top instead of dropping it
  3. Hold-navigate-release hotkey flow works: press=open, hold+press=navigate, release=paste
  4. Bezel responds to j/k, 0-9, Delete, scroll wheel, and double-click
  5. All 16 new settings keys are functional with UI controls and registered defaults
  6. Menu bar has pause monitoring, icon choices, and About Flycut
  7. Paste delay matches ObjC timing (500ms), accessibility alert shows on launch
**Plans:** 6/6 plans complete

Plans:
- [ ] 03.1-01-PLAN.md — Core data fixes: source app capture + dedup move-to-top (Bugs #1, #2)
- [ ] 03.1-02-PLAN.md — Hotkey hold-navigate-release + sticky bezel setting (Bugs #3, #4)
- [ ] 03.1-03-PLAN.md — Bezel keyboard/mouse + ClippingInfo model + pasteMovesToTop (Bugs #11, #12, #13, #23)
- [ ] 03.1-04-PLAN.md — Settings expansion + bezel appearance + source display (Bugs #7, #8, #9, #10, #14, #16, #17)
- [ ] 03.1-05-PLAN.md — Menu bar: pause monitoring, icon choices, about panel (Bugs #18, #19, #20)
- [ ] 03.1-06-PLAN.md — Polish: bezel centering, paste delay, accessibility alert, merge, save-to-file (Bugs #15, #24, #25, #26, #28, #29, #33)

### Phase 4: Code Snippets & Gist Sharing
**Goal**: A code snippet editor with syntax highlighting and GitHub Gist sharing from any clipping or snippet
**Depends on**: Phase 3.1
**Requirements**: SNIP-01, SNIP-02, SNIP-03, SNIP-04, SNIP-05, GIST-01, GIST-02, GIST-03, GIST-04, GIST-05
**Success Criteria** (what must be TRUE):
  1. User can create a named code snippet with syntax highlighting, assign it to a category, search for it, and paste it into the frontmost app
  2. User can authenticate with GitHub via Personal Access Token, share any clipping or snippet as a public or private Gist, and have the Gist URL copied to clipboard automatically
  3. User can view a history of previously created Gists within the app
**Plans:** 4/4 plans complete

Plans:
- [ ] 04-01-PLAN.md — SnippetStore @ModelActor with TDD + Snippet tags schema update (SNIP-01, SNIP-03, SNIP-04)
- [ ] 04-02-PLAN.md — TokenStore keychain wrapper + GistService API client with TDD (GIST-01, GIST-02, GIST-03, GIST-04)
- [ ] 04-03-PLAN.md — Snippet editor UI with HighlightSwift, WindowGroup, menu bar + hotkey wiring (SNIP-02, SNIP-05)
- [ ] 04-04-PLAN.md — Gist sharing integration, history view, settings, notifications + human verify (GIST-05)

### Phase 5: Prompt Library
**Goal**: An HTTP-synced prompt library with bundled defaults, a searchable prompt bezel as the primary fast-access interface, a Prompts management tab in the snippet window, {{variable}} template substitution on paste, and user customization via in-place editing and Save to My Snippets
**Depends on**: Phase 4
**Requirements**: PMPT-01, PMPT-02, PMPT-03, PMPT-04, PMPT-05, PMPT-06, PMPT-07
**Success Criteria** (what must be TRUE):
  1. User can configure a JSON URL in Settings and sync prompts organized by category (coding, writing, analysis, creative)
  2. User can browse prompts by category in the snippet window Prompts tab (flat searchable list), with library prompts visually distinct from user-created prompts
  3. User can sync the prompt library from a public URL to get new and updated prompts; sync respects per-prompt versioning and never overwrites user-customized copies
  4. User can copy any library prompt to their personal snippets via Save to My Snippets; the copy is independent and unaffected by future syncs
  5. Template variables (e.g. `{{clipboard}}`) in prompt content are substituted with actual clipboard content when the prompt is pasted; user-defined variables configured in Settings
  6. Pressing Enter on a selected prompt in the prompt bezel pastes it (with variable substitution) into the frontmost app
**Plans:** 5/5 plans complete

Plans:
- [x] 05-01-PLAN.md — FlycutSchemaV2 + PromptLibraryItem + migration + PromptLibraryStore + TemplateSubstitutor + tests (PMPT-01, PMPT-03, PMPT-04, PMPT-05, PMPT-07)
- [x] 05-02-PLAN.md — PromptSyncService HTTP fetch + PromptLibrarySettingsSection + SettingsView integration (PMPT-01, PMPT-03)
- [x] 05-03-PLAN.md — PromptBezelViewModel + PromptBezelView + PromptBezelController with category cycling and paste (PMPT-02, PMPT-05, PMPT-06)
- [x] 05-04-PLAN.md — PromptLibraryView management tab + SnippetWindowView 3-tab integration (PMPT-02, PMPT-04)
- [x] 05-05-PLAN.md — AppDelegate wiring + hotkey registration + bundled prompt loading + human verify (PMPT-01, PMPT-06)

### Phase 6: Quick Actions & Performance
**Goal**: Add quick actions on clips (transform, format, share) via a secondary action menu in the bezel, plus performance and reliability improvements including adaptive polling and history export/import
**Depends on**: Phase 5
**Requirements**: QACT-01, QACT-02, QACT-03, PERF-01, PERF-02
**Success Criteria** (what must be TRUE):
  1. User can right-click or trigger a secondary action on any bezel item to access transform actions (UPPERCASE, lowercase, Title Case, trim whitespace, URL encode/decode)
  2. User can format a clip via quick actions: wrap in quotes, markdown code block, JSON pretty-print
  3. User can share a clip via quick actions: create Gist, copy as RTF
  4. User can export clipboard history as JSON and import it back for backup or migration
  5. Clipboard polling adapts to user activity (faster when active, slower when idle) to reduce CPU usage
**Plans:** 3/3 plans complete

Plans:
- [ ] 06-01-PLAN.md — TextTransformer TDD + ClipboardExportService TDD (QACT-01, QACT-02, PERF-01)
- [ ] 06-02-PLAN.md — Quick Action NSMenu in BezelController + adaptive clipboard polling (QACT-01, QACT-02, QACT-03, PERF-02)
- [ ] 06-03-PLAN.md — Export/Import UI in Settings and MenuBar + human verify (PERF-01)

### Phase 7: Intelligent Search & AI
**Goal**: Upgrade bezel search from exact substring matching to character-subsequence fuzzy matching with scored ranking — typing abbreviated or non-contiguous characters finds matching clips ranked by quality (source app filtering, date filtering, and AI integration descoped per user decision)
**Depends on**: Phase 6
**Requirements**: SRCH-01, SRCH-02, SRCH-03, AINT-01
**Success Criteria** (what must be TRUE):
  1. Search supports fuzzy matching (e.g., typing `jsonpar` finds "JSON.parse(...)")
  2. ~~User can filter clips by source app name~~ — DROPPED per user decision
  3. ~~User can filter clips by date~~ — DROPPED per user decision
  4. ~~User can invoke on-device AI~~ — DROPPED per user decision (not available in Europe)
**Plans:** 1/1 plans complete

Plans:
- [ ] 07-01-PLAN.md — FuzzyMatcher algorithm TDD + BezelViewModel/PromptBezelViewModel integration (SRCH-01)

### Phase 8: Documentation Lookup
**Goal**: Quick documentation search for selected text via hotkey with downloaded docsets displayed in a lightweight popup
**Depends on**: Phase 5
**Requirements**: DOCS-01, DOCS-02, DOCS-03
**Success Criteria** (what must be TRUE):
  1. User can trigger a documentation search for selected text via hotkey and see results in a lightweight popup with downloaded docsets
**Plans:** 3/3 plans complete

Plans:
- [ ] 08-01-PLAN.md — GRDB.swift SPM + DocsetSearchService + DocsetManagerService + SelectedTextService + tests (DOCS-01, DOCS-02, DOCS-03)
- [ ] 08-02-PLAN.md — DocBezelViewModel + DocBezelView + DocBezelController + DocsetSettingsSection (DOCS-01, DOCS-02, DOCS-03)
- [ ] 08-03-PLAN.md — AppDelegate wiring + hotkey registration + Settings tab + human verify (DOCS-01, DOCS-02, DOCS-03)

### Phase 9: Favorites
**Goal**: Pin clippings as favorites for permanent access with a dedicated favorites view and hotkey toggle; favorites survive history clearing
**Depends on**: Phase 3.1
**Requirements**: FAVR-01, FAVR-02, FAVR-03
**Success Criteria** (what must be TRUE):
  1. User can pin a clipping as a favorite and switch to favorites view via hotkey; favorites survive history clearing
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 3.1 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/2 | Complete   | 2026-03-05 |
| 2. Core Engine | 3/3 | Complete   | 2026-03-05 |
| 3. UI Layer | 2/2 | Complete   | 2026-03-05 |
| 3.1 ObjC Parity | 6/6 | Complete   | 2026-03-09 |
| 4. Code Snippets & Gist | 4/4 | Complete   | 2026-03-09 |
| 5. Prompt Library | 5/5 | Complete   | 2026-03-11 |
| 6. Quick Actions & Performance | 3/3 | Complete   | 2026-03-12 |
| 7. Intelligent Search & AI | 1/1 | Complete   | 2026-03-12 |
| 8. Documentation Lookup | 3/3 | Complete   | 2026-03-16 |
| 9. Favorites | 0/TBD | Not started | - |
