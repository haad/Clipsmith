---
phase: 05-prompt-library
plan: "04"
subsystem: ui
tags: [swiftui, swiftdata, prompt-library, master-detail, template-substitution]

# Dependency graph
requires:
  - phase: 05-prompt-library/05-01
    provides: "PromptLibraryStore @ModelActor, PromptInfo Sendable struct, TemplateSubstitutor, FlycutSchemaV2.PromptLibraryItem"
  - phase: 05-prompt-library/05-02
    provides: "PromptSyncService, AppSettingsKeys.promptLibraryVariables"

provides:
  - "PromptLibraryView master-detail SwiftUI view with flat searchable list and detail editor"
  - "SnippetWindowView updated with 3-tab layout: Snippets (cmd+1), Prompts (cmd+2), Gists (cmd+3)"
  - "#category search syntax in Prompts tab (mirrors bezel behavior)"
  - "In-place prompt editing with debounced auto-save (0.75s), setting isUserCustomized for library prompts"
  - "Save to My Snippets action creating independent Snippet copy with [prompt, category] tags"
  - "Revert to Original action with NSAlert confirmation, clearing isUserCustomized flag"
  - "User prompt creation via + button (cmd+N) in My Prompts category"
  - "Visual distinction: book.fill icon for library prompts, person.fill for user-created"
  - "Category badges: coding=blue, writing=green, analysis=purple, creative=orange, My Prompts=gray"
  - "{{variable}} detection note in detail view with {{clipboard}} security warning"
  - "Template substitution on paste via TemplateSubstitutor + UserDefaults variables"

affects:
  - "05-05: Settings wiring (PromptLibraryView is now the management UI)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Debounced auto-save via Task.sleep(nanoseconds:) with saveTask?.cancel() on selection change — 0.75s debounce"
    - "NSAlert for confirmation dialogs in SwiftUI context — mirrors GistService/MenuBarView patterns"
    - "Variable substitution on paste reads UserDefaults.standard for promptLibraryVariables key — consistent with stickyBezel/pasteMovesToTop pattern"
    - "NSWindow.isPanel extension for identifying NSPanel windows without forced cast"

key-files:
  created:
    - "FlycutSwift/Views/Prompts/PromptLibraryView.swift"
  modified:
    - "FlycutSwift/Views/Snippets/SnippetWindowView.swift"
    - "FlycutSwift.xcodeproj/project.pbxproj"

key-decisions:
  - "[Phase 05-04]: Debounced auto-save uses Task.sleep + saveTask?.cancel() — avoids per-keystroke SwiftData writes while ensuring edits persist on selection change; 0.75s balances responsiveness with write frequency"
  - "[Phase 05-04]: Revert confirmation via NSAlert — consistent with Clear All confirmation in MenuBarView (same pattern for destructive actions in menu bar app context)"
  - "[Phase 05-04]: pastePrompt reads NSPasteboard.general at paste time — ensures {{clipboard}} reflects current clipboard at the moment of use, not at view load time"
  - "[Phase 05-04]: Save to My Snippets tags array [\"prompt\", category] — enables filtering by prompt category in Snippets tab"

patterns-established:
  - "PromptLibraryView mirrors SnippetListView pattern: @Query + HSplitView + left list + right detail + setupStores()"
  - "Debounced save via Task.sleep + saveTask cancel on selection change — reusable for other auto-save UIs"

requirements-completed: [PMPT-02, PMPT-04]

# Metrics
duration: 4min
completed: 2026-03-11
---

# Phase 5 Plan 04: Prompts Management Tab Summary

**SwiftUI master-detail PromptLibraryView with flat searchable list, in-place editing with debounced auto-save, Save to My Snippets, Revert to Original, and 3-tab SnippetWindowView (Snippets/Prompts/Gists)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-11T13:09:06Z
- **Completed:** 2026-03-11T13:13:31Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- PromptLibraryView with flat searchable list: book.fill (library) vs person.fill (user-created) icons, color-coded category badges (coding=blue, writing=green, analysis=purple, creative=orange, My Prompts=gray), orange circle "edited" indicator for customized library prompts
- #category search syntax: "#coding Python" filters to coding category and searches for "Python"; "#my" matches user-created prompts; falls through to standard title/content/category search without "#"
- Editable detail view with debounced auto-save (0.75s) calling promptStore.update() — sets isUserCustomized=true for library prompts
- {{variable}} tokens detected below editor with security warning when {{clipboard}} is present
- Save to My Snippets: creates Snippet via snippetStore.insert() with tags=["prompt", category]
- Revert to Original: NSAlert confirmation, then promptStore.revertToOriginal() clears isUserCustomized
- + button creates user prompt in "My Prompts" category (cmd+N)
- Double-click or Enter pastes prompt with TemplateSubstitutor variable substitution (reads UserDefaults promptLibraryVariables)
- SnippetWindowView updated: 3-tab segmented Picker (Snippets/Prompts/Gists), cmd+1/2/3 shortcuts, Prompts tab shows PromptLibraryView
- Build succeeded, all 26 PromptLibraryStoreTests + TemplateSubstitutorTests pass, TEST SUCCEEDED

## Task Commits

Each task was committed atomically:

1. **Task 1: PromptLibraryView — flat list + detail view + editing + save/revert** - `23486d6` (feat)
2. **Task 2: SnippetWindowView — add Prompts tab (cmd+2), reorder Gists to cmd+3** - `516db95` (feat)

## Files Created/Modified

- `FlycutSwift/Views/Prompts/PromptLibraryView.swift` - NEW: master-detail prompt browser with searchable list, editable detail view, save/revert actions, paste with template substitution
- `FlycutSwift/Views/Snippets/SnippetWindowView.swift` - MODIFIED: 3-tab layout (Snippets cmd+1, Prompts cmd+2, Gists cmd+3); PromptLibraryView added as tab 1
- `FlycutSwift.xcodeproj/project.pbxproj` - MODIFIED: GG0014 Prompts group, AF0057 file reference, AA0056 build file added to Sources phase

## Decisions Made

- **Debounced auto-save (0.75s):** Avoids per-keystroke SwiftData writes. `saveTask?.cancel()` on selection change ensures no stale save fires after switching prompts. Pattern: `Task.sleep(nanoseconds: 750_000_000)` with cancellation check.
- **Revert uses NSAlert:** Consistent with Clear All in MenuBarView (pre-established pattern for destructive confirmations in menu bar app). SwiftUI `.confirmationDialog` is unreliable in non-standard window contexts.
- **pastePrompt reads clipboard at paste time:** Ensures `{{clipboard}}` reflects current clipboard state when user presses Return/double-clicks, not when the view appeared.
- **Save to My Snippets tags:** `["prompt", category]` allows Snippets tab to filter by prompt source and category without a separate type field.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- PromptLibraryView is fully functional as the Prompts tab management UI
- Template substitution on paste uses AppSettingsKeys.promptLibraryVariables — aligns with Plan 05-02 settings UI
- Ready for Plan 05-05: Settings wiring and final phase integration

## Self-Check: PASSED

- FOUND: FlycutSwift/Views/Prompts/PromptLibraryView.swift
- FOUND: FlycutSwift/Views/Snippets/SnippetWindowView.swift
- FOUND commits: 23486d6, 516db95
- BUILD SUCCEEDED
- TEST SUCCEEDED (all tests green)

---
*Phase: 05-prompt-library*
*Completed: 2026-03-11*
