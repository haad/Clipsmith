---
phase: 05-prompt-library
plan: "03"
subsystem: ui
tags: [swiftui, nspanel, non-activating-panel, prompt-library, template-substitution, category-cycling]

# Dependency graph
requires:
  - phase: 05-prompt-library/05-01
    provides: "PromptLibraryStore, PromptInfo Sendable struct, TemplateSubstitutor, FlycutSchemaV2.PromptLibraryItem"
  - phase: 03-ui-layer
    provides: "BezelController NSPanel pattern, BezelViewModel @Observable pattern, BezelView frosted glass pattern"

provides:
  - "PromptBezelViewModel @Observable with category cycling (Tab), #category search syntax, and navigation methods"
  - "PromptBezelView SwiftUI view with prompt list, category badges, frosted glass matching clipboard bezel"
  - "PromptBezelController non-activating NSPanel with full keyboard routing, Tab cycling, and Enter-to-paste with TemplateSubstitutor"

affects:
  - "05-05: AppDelegate hotkey wiring (instantiates PromptBezelController)"
  - "05-04: Prompts tab in Settings (separate view, not related)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PromptBezelViewModel mirrors BezelViewModel pattern but adds selectedCategory + cycleCategory() for Tab-key cycling"
    - "#category search syntax parsed in recomputeFilteredPrompts(): strip # prefix, split on space for category token + remaining text"
    - "sendEvent override intercepts Tab (keyCode 48) before SwiftUI TextField focus change — required for category cycling"
    - "pasteAndHide reads clipboard at paste time (not selection time), merges user vars from JSON in UserDefaults"

key-files:
  created:
    - "FlycutSwift/Views/PromptBezelViewModel.swift"
    - "FlycutSwift/Views/PromptBezelView.swift"
    - "FlycutSwift/Views/PromptBezelController.swift"
  modified:
    - "FlycutSwift.xcodeproj/project.pbxproj"

key-decisions:
  - "[Phase 05-03]: sendEvent override intercepts Tab (keyCode 48) to cycle categories — without this, Tab moves focus out of the search TextField"
  - "[Phase 05-03]: pasteAndHide reads clipboard at paste time — ensures {{clipboard}} variable reflects what user copied AFTER selecting the prompt, not at open time"
  - "[Phase 05-03]: PromptBezelView uses ForEach(enumerated()) with .id(index) for ScrollViewReader — required for selectedIndex-based scroll anchoring"
  - "[Phase 05-03]: Files pre-implemented by Plan 02 executor as forward stubs with full content — Plan 03 verified correctness and build/test passing"

patterns-established:
  - "PromptBezelViewModel pattern: selectedCategory + static allCategories + cycleCategory() — reusable for any category-filtered bezel"
  - "Tab interception in sendEvent before SwiftUI gets it — mirrors arrow key interception pattern in BezelController"

requirements-completed: [PMPT-02, PMPT-05, PMPT-06]

# Metrics
duration: 10min
completed: 2026-03-11
---

# Phase 5 Plan 03: Prompt Bezel Summary

**Non-activating NSPanel prompt bezel with category cycling (Tab), #category search syntax, frosted glass list of prompts with category badges, and Enter-to-paste with {{variable}} template substitution**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-11T12:55:18Z
- **Completed:** 2026-03-11T13:05:35Z
- **Tasks:** 2
- **Files modified:** 4 (3 created, 1 modified — project file)

## Accomplishments

- PromptBezelViewModel with category cycling via Tab key (All > coding > writing > analysis > creative > My Prompts > All), #category search prefix syntax, full navigation methods (up/down/first/last/+10/-10/navigateTo), and wraparound support
- PromptBezelView with category header bar (shows current category label + "Tab to cycle" hint), always-visible search field, scrollable prompt list with colored category badges (coding=blue, writing=green, analysis=purple, creative=orange, My Prompts=gray), "edited" orange dot for user-customized prompts, and frosted glass background matching clipboard bezel
- PromptBezelController as non-activating NSPanel with full keyboard routing (Escape/Enter/arrows/PageUp/PageDown/Home/End/Tab/j/k/0-9), scroll wheel navigation, double-click paste, and TemplateSubstitutor.substitute for {{clipboard}} + user-defined variable substitution on Enter
- All 31 Plan 01 tests pass; build succeeds; no test regressions

## Task Commits

The implementation files were pre-created by Plan 02 executor with full content (Plan 02 commit `7c2b5ad` for PromptBezelViewModel, commit `20617fc` for PromptBezelView and PromptBezelController). Plan 03 verified correctness, confirmed build and all tests pass.

1. **Task 1: PromptBezelViewModel** - `7c2b5ad` (feat, via Plan 02)
2. **Task 2: PromptBezelView + PromptBezelController** - `20617fc` (feat, via Plan 02)

## Files Created/Modified

- `FlycutSwift/Views/PromptBezelViewModel.swift` - NEW: @Observable @MainActor class with category cycling, #category search, navigation methods
- `FlycutSwift/Views/PromptBezelView.swift` - NEW: SwiftUI view with category header, search field, prompt list with badges, frosted glass background
- `FlycutSwift/Views/PromptBezelController.swift` - NEW: Non-activating NSPanel with keyboard routing, Tab interception for cycling, pasteAndHide() with TemplateSubstitutor
- `FlycutSwift.xcodeproj/project.pbxproj` - MODIFIED: Added AF0054/AF0055/AF0056 file references and AA0053/AA0054/AA0055 build file entries for all three new files

## Decisions Made

- **Tab interception in sendEvent:** keyCode 48 (Tab) is intercepted in `sendEvent` override before SwiftUI sees it — without this, Tab moves the focus ring out of the TextField instead of cycling categories. Mirrors the arrow key interception pattern from BezelController.
- **Clipboard read at paste time:** `pasteAndHide()` reads `NSPasteboard.general.string(forType: .string)` when Enter is pressed, not when the prompt is selected — ensures `{{clipboard}}` reflects the most recent clipboard content.
- **#category search parsing in view model:** The #category prefix is parsed in `recomputeFilteredPrompts()` rather than in the controller — keeps the controller thin and the search logic testable.

## Deviations from Plan

None - plan executed as specified. The files were pre-created with full implementations by Plan 02, which served as forward stubs with complete content. Plan 03 verified the implementations are correct and complete per the plan spec.

## Issues Encountered

None — all three files built and all tests passed on first verification.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- PromptBezelController is ready for hotkey wiring in Plan 05-05 (AppDelegate integration)
- PromptBezelController.show() resets state (selectedIndex=0, searchText="", selectedCategory="All") — AppDelegate only needs to call `promptBezelController.show()`
- pasteService and appTracker must be injected by AppDelegate before first show (same pattern as BezelController)

---
*Phase: 05-prompt-library*
*Completed: 2026-03-11*
