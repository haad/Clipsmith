---
phase: 05-prompt-library
plan: "05"
subsystem: integration
tags: [swiftui, swiftdata, appdelegate, keyboard-shortcuts, prompt-library, wiring]

# Dependency graph
requires:
  - phase: 05-prompt-library/05-01
    provides: "PromptLibraryStore @ModelActor, PromptInfo Sendable struct, TemplateSubstitutor, FlycutSchemaV2.PromptLibraryItem"
  - phase: 05-prompt-library/05-02
    provides: "PromptSyncService with loadBundledPrompts + syncFromURL, AppSettingsKeys.promptLibraryVariables"
  - phase: 05-prompt-library/05-03
    provides: "PromptBezelController NSPanel with show/hide/pasteAndHide, PromptBezelViewModel"
  - phase: 05-prompt-library/05-04
    provides: "PromptLibraryView master-detail tab, SnippetWindowView 3-tab layout"

provides:
  - "AppDelegate fully wires PromptLibraryStore, PromptSyncService, PromptBezelController"
  - "Bundled prompts auto-load on first launch (guard: empty store check before loading)"
  - "activatePrompts hotkey registered in AppDelegate with navigateDown-on-repress behavior"
  - "activatePrompts KeyboardShortcuts.Name added to KeyboardShortcutNames.swift"
  - "Prompt Library recorder in HotkeySettingsTab (after Open Snippets recorder)"
  - "Browse Prompts... menu item in MenuBarView opens snippet window on Prompts tab"
  - "flycutOpenPrompts notification: MenuBarView posts, SnippetWindowView observes to switch to tab 1"
  - "promptBezelController.hide() called in applicationWillTerminate"

affects:
  - "Human verification: test bundled prompts, bezel hotkey, prompts tab, editing, save-to-snippets, sync, variables"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Browse Prompts... opens window then posts .flycutOpenPrompts with 150ms delay — same pattern as other window+tab navigation flows"
    - "Empty store guard before loadBundledPrompts: fetchAll().isEmpty check ensures idempotent first-launch behavior"
    - "activatePrompts hotkey handler mirrors activateBezel pattern: navigateDown on repress, isHotkeyHold = !stickyBezel on first press"

key-files:
  created: []
  modified:
    - "FlycutSwift/Settings/KeyboardShortcutNames.swift"
    - "FlycutSwift/App/AppDelegate.swift"
    - "FlycutSwift/Views/MenuBarView.swift"
    - "FlycutSwift/Views/Settings/HotkeySettingsTab.swift"
    - "FlycutSwift/Views/Snippets/SnippetWindowView.swift"

key-decisions:
  - "[Phase 05-05]: Browse Prompts... calls openSnippetWindowOnPromptsTab() directly rather than posting .flycutOpenPrompts from button — avoids observer loop (MenuBarView posting to itself)"
  - "[Phase 05-05]: SnippetWindowView observes .flycutOpenPrompts to switch selectedTab=1 — same onReceive pattern used for flycutOpenGistSettings in MenuBarView"
  - "[Phase 05-05]: openSnippetWindowOnPromptsTab posts notification after 150ms sleep — ensures SnippetWindowView has appeared before tab switch fires (mirrors 100ms policy propagation sleep)"

patterns-established:
  - "Window-then-tab-switch: open window, sleep 150ms, post tab-switch notification — SnippetWindowView observes and switches selectedTab"
  - "Empty store guard for first-launch loading: fetchAll().isEmpty ?? true ensures loadBundledPrompts only runs once"

requirements-completed: [PMPT-01, PMPT-06]

# Metrics
duration: 2min
completed: 2026-03-11
---

# Phase 5 Plan 05: AppDelegate Wiring + Settings Integration Summary

**Full prompt library integration: AppDelegate wires PromptLibraryStore/PromptSyncService/PromptBezelController, registers activatePrompts hotkey, loads bundled prompts on first launch, and adds Browse Prompts... menu item with Prompts tab navigation**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-11T13:16:33Z
- **Completed:** 2026-03-11T13:18:41Z
- **Tasks:** 1 auto + 1 checkpoint (auto-approved)
- **Files modified:** 5

## Accomplishments

- AppDelegate fully wires the prompt library: PromptLibraryStore (shared model container), PromptSyncService, and PromptBezelController all initialized in applicationDidFinishLaunching
- Bundled prompts load on first launch via Task {} guard — empty store check prevents re-loading on subsequent launches
- activatePrompts hotkey registered with same navigateDown-on-repress + isHotkeyHold = !stickyBezel pattern as activateBezel
- promptBezelController.hide() added to applicationWillTerminate alongside existing bezelController.hide()
- Browse Prompts... menu item in MenuBarView calls openSnippetWindowOnPromptsTab() — opens snippet window + posts .flycutOpenPrompts after 150ms delay
- SnippetWindowView observes .flycutOpenPrompts and sets selectedTab = 1 (Prompts tab)
- Prompt Library keyboard recorder added to HotkeySettingsTab after existing Open Snippets recorder
- Build succeeded (BUILD SUCCEEDED)

## Task Commits

Each task was committed atomically:

1. **Task 1: AppDelegate wiring + KeyboardShortcutNames + HotkeySettingsTab + MenuBarView** - `248d4f4` (feat)
2. **Task 2: Human verify — full prompt library flow** - auto-approved (checkpoint, auto_advance=true)

## Files Created/Modified

- `FlycutSwift/Settings/KeyboardShortcutNames.swift` - MODIFIED: added activatePrompts hotkey name
- `FlycutSwift/App/AppDelegate.swift` - MODIFIED: promptLibraryStore/promptSyncService/promptBezelController properties, initialization in applicationDidFinishLaunching, activatePrompts hotkey registration, hide on terminate
- `FlycutSwift/Views/MenuBarView.swift` - MODIFIED: flycutOpenPrompts Notification.Name, Browse Prompts... menu item, openSnippetWindowOnPromptsTab() method
- `FlycutSwift/Views/Settings/HotkeySettingsTab.swift` - MODIFIED: Prompt Library recorder added, updated footer text
- `FlycutSwift/Views/Snippets/SnippetWindowView.swift` - MODIFIED: observe .flycutOpenPrompts to switch to tab 1

## Decisions Made

- **Browse Prompts... calls openSnippetWindowOnPromptsTab() directly:** Avoids observer loop. If the button posted `.flycutOpenPrompts` and MenuBarView observed it to call openSnippetWindowOnPromptsTab(), which then posts `.flycutOpenPrompts` again, the loop would fire indefinitely. Direct call breaks the cycle cleanly.
- **SnippetWindowView observes .flycutOpenPrompts for tab switching:** Consistent with the onReceive pattern used for `.flycutOpenGistSettings` in MenuBarView. Notification bridge is the established pattern for cross-component tab/window navigation.
- **150ms sleep before posting .flycutOpenPrompts:** Ensures SnippetWindowView has fully appeared and its onReceive is active before the tab-switch notification fires. Mirrors the existing 100ms sleep for activation policy propagation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added SnippetWindowView .flycutOpenPrompts observer for tab switching**
- **Found during:** Task 1 (MenuBarView Browse Prompts... implementation)
- **Issue:** Plan said "add observer in MenuBarView for .flycutOpenPrompts that opens the snippet window and switches to tab 1" — but this would create an observer loop (MenuBarView posts, MenuBarView observes, calls openSnippetWindowOnPromptsTab, which posts again)
- **Fix:** Moved the tab-switch observer to SnippetWindowView (which observes the notification and sets selectedTab=1). MenuBarView button calls openSnippetWindowOnPromptsTab() directly (no observer in MenuBarView). Clean separation of concerns.
- **Files modified:** FlycutSwift/Views/Snippets/SnippetWindowView.swift, FlycutSwift/Views/MenuBarView.swift
- **Verification:** Build succeeded. No loop possible — MenuBarView never observes .flycutOpenPrompts.
- **Committed in:** 248d4f4 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 - critical correctness: infinite notification loop prevention)
**Impact on plan:** Auto-fix improves architecture — observer moved from MenuBarView to SnippetWindowView which is the appropriate owner. No scope creep.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 5 (Prompt Library) is complete. All 5 plans executed:
  - 05-01: Data model (FlycutSchemaV2, PromptLibraryItem, PromptLibraryStore, TemplateSubstitutor)
  - 05-02: Sync service (PromptSyncService, prompts.json bundle, settings UI)
  - 05-03: Prompt bezel (PromptBezelController, PromptBezelView, PromptBezelViewModel)
  - 05-04: Prompts tab (PromptLibraryView, SnippetWindowView 3-tab layout)
  - 05-05: Integration wiring (AppDelegate, hotkey, menu item) — THIS PLAN
- Human verification recommended: bundled prompts on first launch, hotkey bezel, prompts tab, settings

## Self-Check: PASSED

- FOUND: FlycutSwift/Settings/KeyboardShortcutNames.swift (activatePrompts added)
- FOUND: FlycutSwift/App/AppDelegate.swift (promptLibraryStore/promptSyncService/promptBezelController)
- FOUND: FlycutSwift/Views/MenuBarView.swift (Browse Prompts... + openSnippetWindowOnPromptsTab)
- FOUND: FlycutSwift/Views/Settings/HotkeySettingsTab.swift (Prompt Library recorder)
- FOUND: FlycutSwift/Views/Snippets/SnippetWindowView.swift (flycutOpenPrompts observer)
- FOUND commit: 248d4f4
- BUILD SUCCEEDED

---
*Phase: 05-prompt-library*
*Completed: 2026-03-11*
