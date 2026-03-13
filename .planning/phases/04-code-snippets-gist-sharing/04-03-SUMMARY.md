---
phase: 04-code-snippets-gist-sharing
plan: 03
subsystem: ui
tags: [swiftui, swiftdata, highlightswift, syntax-highlighting, snippet-editor, windowgroup]

# Dependency graph
requires:
  - phase: 04-code-snippets-gist-sharing-01
    provides: SnippetStore @ModelActor CRUD actor, SnippetInfo Sendable struct, FlycutSchemaV1.Snippet model

provides:
  - SnippetWindowView — root WindowGroup view with Snippets/Gists tab selector
  - SnippetListView — searchable master list with language badges, +/delete, double-click/Enter paste
  - SnippetEditorView — detail editor with name, language picker, tags, TextEditor, CodeText preview
  - HighlightSwift 1.1.0 SPM dependency with CodeText syntax-highlighted preview
  - WindowGroup(id:snippets) registered in FlycutApp
  - "Snippets..." menu item in MenuBarView with activation policy switch
  - activateSnippets global hotkey (KeyboardShortcuts) configurable in Settings
  - "Share as Gist..." context menu stub on clippings (posts .flycutShareAsGist notification for Plan 04)
  - SnippetPasteTests — 3 smoke tests verifying PasteService callable with snippet content (SNIP-05)

affects: [04-04-gist-sharing, settings, menubar]

# Tech tracking
tech-stack:
  added: [HighlightSwift 1.1.0 (SPM — appstefan/HighlightSwift)]
  patterns:
    - WindowGroup with activation policy switch (.accessory -> .regular -> .accessory on close)
    - Notification bridge for AppDelegate -> MenuBarView openWindow cross-boundary call
    - @Query-based snippet list with in-memory filter for search (consistent with ClipboardStore pattern)
    - SnippetStore injected via modelContext.container in views (avoids explicit environment injection)
    - Auto-save via debounced .task(id: saveKey) with 500ms sleep

key-files:
  created:
    - FlycutSwift/Views/Snippets/SnippetWindowView.swift
    - FlycutSwift/Views/Snippets/SnippetListView.swift
    - FlycutSwift/Views/Snippets/SnippetEditorView.swift
    - FlycutTests/SnippetPasteTests.swift
  modified:
    - FlycutSwift/App/FlycutApp.swift
    - FlycutSwift/App/AppDelegate.swift
    - FlycutSwift/Views/MenuBarView.swift
    - FlycutSwift/Settings/KeyboardShortcutNames.swift
    - FlycutSwift/Views/Settings/HotkeySettingsTab.swift
    - FlycutSwift.xcodeproj/project.pbxproj

key-decisions:
  - "HighlightLanguage uses camelCase enum members in 1.1.0 API — javaScript not javascript, typeScript not typescript, cPlusPlus not cpp; XML not supported"
  - "AppDelegate cannot use @Environment(\.openWindow) — notification bridge via .flycutOpenSnippets dispatches openSnippetWindow() in MenuBarView"
  - "SnippetListView uses @Query + in-memory filter for search — consistent with SnippetStore.search() pattern; @Query auto-refreshes on SwiftData writes"
  - "Activation policy restoration in SnippetWindowView.onDisappear — checks NSApp.windows for visible non-panel windows before switching to .accessory"
  - "PasteServiceTests.testPlainTextOnly intermittently fails in full parallel run due to shared NSPasteboard.general across test processes — pre-existing race condition, not introduced by this plan"

patterns-established:
  - "WindowGroup opening pattern: setActivationPolicy(.regular) + 100ms sleep + activate + openWindow(id:)"
  - "Global notification bridge for cross-boundary window opening: AppDelegate hotkey -> Notification -> MenuBarView.onReceive -> openWindow"

requirements-completed: [SNIP-02, SNIP-05]

# Metrics
duration: 35min
completed: 2026-03-09
---

# Phase 4 Plan 3: Snippet Editor UI Summary

**HighlightSwift-powered snippet editor window with searchable master-detail layout, syntax-highlighted CodeText preview, global hotkey, and paste-to-frontmost-app via double-click/Enter**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-03-09T20:10:00Z
- **Completed:** 2026-03-09T21:16:13Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments

- HighlightSwift 1.1.0 added as SPM dependency and compiling with correct camelCase API
- Snippet editor window opens from menu bar "Snippets..." item with activation policy switch (window appears in front)
- Master-detail layout: searchable list on left with language badges, editable SnippetEditorView on right with CodeText syntax highlighting
- Global hotkey for snippet window registered and configurable in HotkeySettingsTab Settings UI
- "Share as Gist..." context menu stub on clippings prepared for Plan 04 wiring
- SnippetPasteTests: 3 smoke tests pass confirming PasteService callable with single-line, multi-line, and empty snippet content

## Task Commits

1. **Task 1: Add HighlightSwift SPM dependency and create snippet editor views** - `b8b4b33` (feat)
2. **Task 2: Wire snippet window into FlycutApp, MenuBarView, hotkey, and create SnippetPasteTests** - `c010995` (feat)

## Files Created/Modified

- `FlycutSwift/Views/Snippets/SnippetWindowView.swift` - Root WindowGroup view with Snippets/Gists tab picker; restores .accessory policy on close
- `FlycutSwift/Views/Snippets/SnippetListView.swift` - Searchable master list with @Query, language badges, +/delete buttons, double-click/Enter paste flow
- `FlycutSwift/Views/Snippets/SnippetEditorView.swift` - Detail editor: name field, language Picker (19 options), tags field, TextEditor, CodeText preview with HighlightSwift
- `FlycutTests/SnippetPasteTests.swift` - 3 smoke tests for SNIP-05: single-line, multi-line, empty snippet paste paths
- `FlycutSwift/App/FlycutApp.swift` - WindowGroup(id: snippets) with modelContainer and frame constraints
- `FlycutSwift/App/AppDelegate.swift` - snippetStore: SnippetStore init + activateSnippets hotkey registration with notification bridge
- `FlycutSwift/Views/MenuBarView.swift` - "Snippets..." button, "Share as Gist..." context menu, .flycutOpenSnippets observer, openSnippetWindow() helper; Notification.Name.flycutOpenSnippets + .flycutShareAsGist defined
- `FlycutSwift/Settings/KeyboardShortcutNames.swift` - activateSnippets static property added
- `FlycutSwift/Views/Settings/HotkeySettingsTab.swift` - KeyboardShortcuts.Recorder for "Open Snippets" added
- `FlycutSwift.xcodeproj/project.pbxproj` - HighlightSwift XCRemoteSwiftPackageReference, new file references, Snippets group, build phase entries

## Decisions Made

- HighlightSwift 1.1.0 uses camelCase enum names: `javaScript` not `javascript`, `typeScript` not `typescript`, `cPlusPlus` not `cpp`; XML language not available
- AppDelegate cannot use `@Environment(\.openWindow)` — solved with notification bridge: hotkey posts `.flycutOpenSnippets`, MenuBarView observes and calls `openSnippetWindow()`
- Activation policy restoration in `SnippetWindowView.onDisappear` guards on visible non-panel windows to avoid hiding dock icon while Settings is open

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed HighlightLanguage member names for HighlightSwift 1.1.0 API**
- **Found during:** Task 1 (SnippetEditorView implementation)
- **Issue:** Plan specified `javascript`, `typescript`, `cpp`, `xml` — actual HighlightLanguage enum uses `javaScript`, `typeScript`, `cPlusPlus`; `xml` is not supported
- **Fix:** Updated switch cases and removed XML from languageOptions; verified by reading HighlightLanguage.swift from resolved package
- **Files modified:** FlycutSwift/Views/Snippets/SnippetEditorView.swift
- **Verification:** Build succeeded
- **Committed in:** b8b4b33 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — API mismatch)
**Impact on plan:** Necessary for compilation. No scope creep.

## Issues Encountered

- `PasteServiceTests.testPlainTextOnly()` intermittently fails in full parallel test suite due to shared `NSPasteboard.general` across parallel XCTest processes — pre-existing race condition unrelated to this plan's changes. Tests pass when run in isolation or as a subset. Documented but not fixed (out-of-scope pre-existing issue).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Snippet editor window fully functional; ready for Plan 04 to wire Gist sharing UI into the Gists tab
- `.flycutShareAsGist` notification stub ready for Plan 04 to observe and trigger GitHub Gist creation
- HighlightSwift CodeText integrated; Plan 04 can reuse for Gist content preview if needed

---
*Phase: 04-code-snippets-gist-sharing*
*Completed: 2026-03-09*
