---
phase: 03-ui-layer
plan: 02
subsystem: ui
tags: [swiftui, nswindow, nspanel, bezel, hud, swiftdata, keyboard-shortcuts, appdelegate]

# Dependency graph
requires:
  - phase: 03-ui-layer/03-01
    provides: BezelController, BezelViewModel, BezelView — non-activating NSPanel HUD with keyboard navigation and search
  - phase: 02-core-engine
    provides: PasteService, AppTracker, ClipboardStore, FlycutApp.sharedModelContainer

provides:
  - "Fully wired bezel HUD triggered by global hotkeys from AppDelegate"
  - "BezelController with injected model container (SwiftData @Query functional)"
  - "Toggle show/hide on activateBezel hotkey"
  - "Search-focused open on activateSearch hotkey"
  - "Clean bezel teardown on app termination"

affects:
  - 03-03-PLAN.md (if any — bezel is now live end-to-end)
  - Any future phase needing bezel show/hide interface

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NSHostingView rootView wraps SwiftUI view with .modelContainer() modifier when model container is injected"
    - "BezelController.init(modelContainer:) pattern — optional ModelContainer enables test-safe no-container init"
    - "AppDelegate injects services into BezelController after init, before first hotkey fires"
    - "applicationWillTerminate calls bezelController?.hide() to ensure NSEvent global monitor is removed on quit"

key-files:
  created: []
  modified:
    - FlycutSwift/App/AppDelegate.swift
    - FlycutSwift/Views/BezelController.swift

key-decisions:
  - "BezelController.init(modelContainer:) with a convenience init() — preserves test/preview compatibility while enabling model container injection in production path"
  - "AnyView wrapping in NSHostingView rootView — required to conditionally apply .modelContainer() since SwiftUI view modifiers return opaque 'some View' types that don't unify without type erasure"

patterns-established:
  - "Model container injection pattern: BezelController(modelContainer: FlycutApp.sharedModelContainer) followed by property injection for services"
  - "NSHostingView with conditional model container: if let modelContainer { AnyView(view.modelContainer(mc)) } else { AnyView(view) }"

requirements-completed: [BEZL-01, BEZL-02, BEZL-03, BEZL-04, BEZL-05, INTR-02, INTR-04, SHELL-02]

# Metrics
duration: 5min
completed: 2026-03-05
---

# Phase 3 Plan 2: Bezel HUD Wiring Summary

**Global hotkeys wired to BezelController show/hide/showWithSearch in AppDelegate, with SwiftData model container injected so @Query populates clipping history**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-05T20:43:00Z
- **Completed:** 2026-03-05T20:48:00Z
- **Tasks:** 1 auto + 1 auto-approved checkpoint
- **Files modified:** 2

## Accomplishments

- AppDelegate creates BezelController with `FlycutApp.sharedModelContainer` so BezelView's `@Query` can fetch clippings from the live SwiftData store
- `activateBezel` hotkey now toggles bezel show/hide (if visible: hide, else: show)
- `activateSearch` hotkey now calls `showWithSearch()` — opens bezel with search field focused
- `applicationWillTerminate` calls `bezelController?.hide()` to remove the NSEvent global monitor on quit
- BezelController gained a `init(modelContainer:)` designated initialiser and a no-arg convenience `init()` for tests/previews
- All 28 unit tests continue to pass — no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire BezelController into AppDelegate hotkey handlers** - `e99e00c` (feat)
2. **Task 2: Verify complete bezel HUD interaction flow** - auto-approved checkpoint (auto_advance=true)

**Plan metadata:** (committed with SUMMARY/STATE/ROADMAP update)

## Files Created/Modified

- `FlycutSwift/App/AppDelegate.swift` — added `bezelController` property, init with model container, hotkey toggle wiring, terminate cleanup
- `FlycutSwift/Views/BezelController.swift` — new `init(modelContainer:)` with `AnyView` wrapping for conditional model container injection; no-arg convenience `init()` preserved for tests

## Decisions Made

- **BezelController.init(modelContainer: ModelContainer?) designated init:** The convenience `init()` (no args) is preserved so existing BezelControllerTests continue to work without a model container. The new `init(modelContainer:)` is the production path used by AppDelegate.
- **AnyView wrapping for conditional .modelContainer():** SwiftUI's `.modelContainer()` modifier returns `some View` — not the same opaque type in both branches of an if/else. `AnyView` type-erases both branches so `NSHostingView(rootView:)` accepts a single type.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added model container injection to BezelController**
- **Found during:** Task 1 (Wire BezelController into AppDelegate)
- **Issue:** 03-01-SUMMARY.md explicitly flagged "BezelView needs FlycutApp.sharedModelContainer injected (via .modelContainer()) when BezelController creates the NSHostingView — currently missing (to be addressed in 03-02 wiring plan)". Without this, `@Query` in BezelView returns empty results and clippings never appear in the bezel.
- **Fix:** Added `init(modelContainer: ModelContainer?)` to BezelController, wrapping the rootView with `.modelContainer(modelContainer)` when provided. Used `AnyView` to unify the conditional branches.
- **Files modified:** `FlycutSwift/Views/BezelController.swift`
- **Verification:** Build succeeds, tests pass, BezelController(modelContainer: container) path tested at build/link time
- **Committed in:** `e99e00c` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing critical functionality pre-flagged in prior SUMMARY)
**Impact on plan:** Essential for correct operation — without model container injection, the bezel would show but always display "No clippings". No scope creep.

## Issues Encountered

None beyond the auto-fixed model container injection (which was pre-identified and planned).

## User Setup Required

To verify bezel HUD end-to-end:
1. Grant Accessibility permission to FlycutSwift in System Settings > Privacy & Security > Accessibility
2. Assign hotkeys for "Activate Bezel" and "Activate Search" in Flycut Preferences > Shortcuts

## Next Phase Readiness

- Bezel HUD fully wired and ready for end-to-end human verification
- BezelController exposes clean show/hide/showWithSearch interface — no further AppDelegate changes expected
- Phase 3 UI layer complete pending any remaining plans

---
*Phase: 03-ui-layer*
*Completed: 2026-03-05*
