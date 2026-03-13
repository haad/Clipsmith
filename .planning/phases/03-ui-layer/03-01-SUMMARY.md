---
phase: 03-ui-layer
plan: 01
subsystem: ui
tags: [swiftui, nswindow, nspanel, bezel, hud, observable, swiftdata, keyboard-navigation, tdd]

# Dependency graph
requires:
  - phase: 02-core-engine
    provides: PasteService, AppTracker, ClipboardStore, FlycutSchemaV1.Clipping
  - phase: 01-foundation
    provides: AppSettingsKeys, FlycutApp.sharedModelContainer, AppDelegate services
provides:
  - BezelViewModel: pure-Swift @Observable navigation/search state
  - BezelController: @MainActor NSPanel subclass, non-activating, keyboard-routed
  - BezelView: SwiftUI view with @Query clippings, search TextField, navigation counter
  - 28 unit tests (21 BezelViewModelTests + 7 BezelControllerTests)
affects:
  - 03-02-PLAN.md (BezelController wired into AppDelegate hotkeys)
  - Any phase needing the bezel show/hide interface

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@Observable @MainActor final class for pure-Swift UI state (no SwiftUI/SwiftData)"
    - "NSPanel with .nonactivatingPanel in init styleMask (not set afterwards)"
    - "NSHostingView(rootView:) bridging NSPanel to SwiftUI content"
    - "Shared BezelViewModel instance bridging controller keyDown to SwiftUI view state"
    - "@Bindable for @Observable viewModel passed as parameter to SwiftUI view"
    - "NSEvent.addGlobalMonitorForEvents for click-outside panel dismissal"

key-files:
  created:
    - FlycutSwift/Views/BezelViewModel.swift
    - FlycutSwift/Views/BezelController.swift
    - FlycutSwift/Views/BezelView.swift
    - FlycutTests/BezelViewModelTests.swift
    - FlycutTests/BezelControllerTests.swift
  modified:
    - FlycutSwift.xcodeproj/project.pbxproj

key-decisions:
  - "BezelViewModel uses [String] not [@Model] — PasteService operates on content, BezelView maps @Query to strings before setting viewModel.clippings"
  - "BezelController shares viewModel instance with BezelView — controller routes keyDown to viewModel, view observes the same state"
  - "BezelControllerTests use per-test local controller vars — avoids Swift 6 Sendable error from nonisolated XCTestCase setUp"
  - ".nonactivatingPanel MUST be in NSPanel init styleMask — WindowServer does not honour post-init changes"

patterns-established:
  - "NSPanel init pattern: .nonactivatingPanel in styleMask init arg, level above .screenSaverWindow, collectionBehavior includes .canJoinAllSpaces + .fullScreenAuxiliary"
  - "Non-activating bezel pattern: show() calls makeKeyAndOrderFront (not NSApp.activate), hide() removes global monitor"
  - "TDD with @MainActor @Observable class: test class is @MainActor, per-test local vars avoid Sendable issues"

requirements-completed: [BEZL-01, BEZL-02, BEZL-03, BEZL-04, BEZL-05, INTR-02, INTR-04]

# Metrics
duration: 7min
completed: 2026-03-05
---

# Phase 3 Plan 1: Bezel HUD Summary

**Non-activating NSPanel bezel HUD with SwiftUI content, keyboard navigation, case-insensitive search, and 28 unit tests — built TDD**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-05T20:38:00Z
- **Completed:** 2026-03-05T20:45:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- BezelViewModel: @Observable @MainActor pure-Swift class — navigateUp/Down/First/Last/UpTen/DownTen all clamped, case-insensitive search filter, selectedIndex auto-reset on searchText change, 21 unit tests passing
- BezelController: @MainActor NSPanel with .nonactivatingPanel in init, level above screenSaverWindow, canJoinAllSpaces+fullScreenAuxiliary, canBecomeKey=true, canBecomeMain=false, click-outside global monitor, keyDown routing to viewModel
- BezelView: @Query SwiftData clippings mapped to viewModel.clippings, search TextField bound to viewModel.searchText, clipping content ScrollView, navigation counter label, empty/no-matches states, ultraThinMaterial + RoundedRectangle
- 7 BezelControllerTests pass (styleMask, level, collectionBehavior, canBecomeKey, canBecomeMain, isReleasedWhenClosed)

## Task Commits

Each task was committed atomically:

1. **Task 1: BezelViewModel with TDD** - `7f8d458` (feat — 21 tests green)
2. **Task 2: BezelController + BezelView + controller tests** - `793b846` (feat — 7 tests pass)

_Note: Task 1 used TDD (RED/GREEN combined since implementation was written alongside tests)_

## Files Created/Modified

- `FlycutSwift/Views/BezelViewModel.swift` — @Observable @MainActor pure-Swift navigation/search state
- `FlycutSwift/Views/BezelController.swift` — NSPanel subclass, non-activating, keyboard routing, show/hide lifecycle
- `FlycutSwift/Views/BezelView.swift` — SwiftUI view with @Query, search TextField, clipping content, navigation counter
- `FlycutTests/BezelViewModelTests.swift` — 21 unit tests covering all navigation mutations and search behaviors
- `FlycutTests/BezelControllerTests.swift` — 7 unit tests covering panel configuration properties
- `FlycutSwift.xcodeproj/project.pbxproj` — 5 new files registered in correct targets (BezelViewModel + BezelController + BezelView to FlycutSwift Sources; BezelViewModelTests + BezelControllerTests to FlycutTests Sources)

## Decisions Made

- **BezelViewModel uses [String] not [@Model]:** PasteService.paste takes String content; keeping the view model free of SwiftData means it's easily unit-testable without a model container. BezelView maps @Query results to strings before setting viewModel.clippings.
- **Shared BezelViewModel instance:** BezelController creates the viewModel and passes it to BezelView — both sides mutate/observe the same instance. Controller routes keyDown events; BezelView reads and displays state. No message passing needed.
- **Per-test controller initialization:** XCTestCase.setUp() is not @MainActor under Swift 6, so storing `BezelController` as an ivar caused Sendable errors. Fixed by creating the controller as a local constant in each test method.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] BezelControllerTests Swift 6 Sendable error from shared setUp controller**
- **Found during:** Task 2 (BezelController tests)
- **Issue:** Original tests used `private var controller: BezelController!` + `setUp()` pattern. Under Swift 6 strict concurrency, `setUp()` is nonisolated and can't return a `@MainActor`-isolated BezelController to an ivar in a `@MainActor` class without Sendable conformance.
- **Fix:** Moved controller instantiation into each test method as a local `let controller = BezelController()` — concurrency-safe because the entire test class is `@MainActor`.
- **Files modified:** `FlycutTests/BezelControllerTests.swift`
- **Verification:** All 7 tests compile and pass
- **Committed in:** `793b846` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — Swift 6 Sendable compliance)
**Impact on plan:** Necessary for correctness under Swift 6 strict concurrency. No scope creep. Same test coverage achieved.

## Issues Encountered

None beyond the auto-fixed Swift 6 Sendable issue above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- BezelController ready for wiring into AppDelegate hotkeys (03-02-PLAN.md)
- BezelController.pasteService and appTracker are var properties — AppDelegate can inject them after init
- BezelController needs to be instantiated in AppDelegate and .show()/.showWithSearch() called from KeyboardShortcuts hotkey handlers
- BezelView needs FlycutApp.sharedModelContainer injected (via .modelContainer()) when BezelController creates the NSHostingView — currently missing (to be addressed in 03-02 wiring plan)

---
*Phase: 03-ui-layer*
*Completed: 2026-03-05*
