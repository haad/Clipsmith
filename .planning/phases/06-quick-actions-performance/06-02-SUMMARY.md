---
phase: 06-quick-actions-performance
plan: 02
subsystem: bezel-ui, clipboard-monitoring
tags: [swift, nsMenu, context-menu, adaptive-polling, tdd, swift6, performance]

requires:
  - phase: 06-quick-actions-performance
    plan: 01
    provides: TextTransformer enum with 10 static transform/format/RTF functions

provides:
  - BezelController.rightMouseDown with NSMenu quick actions (Transform/Format/Share submenus)
  - BezelController.clipboardMonitor injection + blockedChangeCount self-capture prevention
  - BezelController Tab key shortcut for keyboard-only quick action access
  - ClipboardMonitor adaptive polling — 0.5s active, 3.0s idle (after 30s no activity)
  - ClipboardMonitor.checkPasteboardAdaptive() with NSEvent global activity monitor

affects:
  - 06-03 (export/import UI — uses the same ClipboardMonitor and ClipboardStore infrastructure)

tech-stack:
  added: []
  patterns:
    - "NSMenuItem.target = self required for non-activating NSPanel — responder chain does not work without explicit target"
    - "Adaptive polling via NSEvent.addGlobalMonitorForEvents + Task { @MainActor } hop for Swift 6 Sendable compliance"
    - "Timer interval delta guard (abs > 0.01) to avoid unnecessary timer churn when interval unchanged"
    - "TDD RED/GREEN cycle — compile failures confirmed before implementation"

key-files:
  created: []
  modified:
    - FlycutSwift/Views/BezelController.swift
    - FlycutSwift/App/AppDelegate.swift
    - FlycutSwift/Services/ClipboardMonitor.swift
    - FlycutTests/ClipboardMonitorTests.swift

key-decisions:
  - "[Phase 06-02]: NSMenuItem.target = self set explicitly on every item — non-activating NSPanel does not participate in responder chain (RESEARCH.md Pitfall 1)"
  - "[Phase 06-02]: showQuickActionMenu(at:) extracted from rightMouseDown — also called by Tab key handler for keyboard-only access"
  - "[Phase 06-02]: applyTransform does NOT auto-paste — user reviews transformed result and presses Enter (RESEARCH.md Open Question 1)"
  - "[Phase 06-02]: activeInterval stored as var (not let) in ClipboardMonitor — set in start() from UserDefaults to respect user config while keeping checkPasteboardAdaptive comparison accurate"
  - "[Phase 06-02]: clipboardMonitor?.blockedChangeCount set after RTF write as well as string writes — both write types must prevent self-capture"

patterns-established:
  - "Quick action menus in non-activating panels require target = self on every NSMenuItem"
  - "Adaptive polling stores effective activeInterval as property — avoids mismatch between start() config and checkPasteboardAdaptive() comparison"

requirements-completed: [QACT-01, QACT-02, QACT-03, PERF-02]

duration: 6min
completed: 2026-03-12
---

# Phase 06 Plan 02: Quick Action NSMenu + Adaptive Polling Summary

**Right-click context menu on bezel items (Transform/Format/Share submenus via TextTransformer) wired into BezelController, plus adaptive clipboard polling (0.5s active / 3.0s idle) in ClipboardMonitor, built TDD with 2 new passing tests**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-12T12:06:01Z
- **Completed:** 2026-03-12T12:12:35Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- BezelController gains `rightMouseDown` override presenting NSMenu with Transform (6 items), Format (3 items), Share (2 items) submenus
- `applyTransform(_ transform:)` helper writes result to pasteboard, sets `blockedChangeCount` to prevent self-capture, inserts into clipboard history with `"Flycut (transformed)"` source
- `actionCopyAsRTF` writes RTF data to pasteboard with `.rtf` type and hides bezel
- `actionShareAsGist` posts `.flycutShareAsGist` notification — reuses AppDelegate handler (zero new Gist code)
- Tab key (keyCode 48) in `sendEvent` calls `showQuickActionMenu` for keyboard-only access
- AppDelegate wired: `bezelController.clipboardMonitor = clipboardMonitor`
- ClipboardMonitor adaptive polling: `activeInterval` (0.5s or user-configured), `idleInterval` (3.0s), switches after 30s idle
- NSEvent global monitor tracks mouse/key/scroll events; `Task { @MainActor }` hop for Swift 6 Sendable compliance
- `timerRecreationCount` and `hasActivityMonitor` test support properties added
- All 10 ClipboardMonitorTests pass including 2 new adaptive polling tests
- Full test suite passes with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Quick Action NSMenu in BezelController** — `2468f8e`
2. **Task 2: Adaptive clipboard polling in ClipboardMonitor with TDD** — `a154c95`

## Files Created/Modified

- `FlycutSwift/Views/BezelController.swift` — Added `clipboardMonitor` property, `rightMouseDown` override, `showQuickActionMenu(at:)`, `applyTransform`, 11 `@objc` action handlers, Tab key handling, NSRect center helper
- `FlycutSwift/App/AppDelegate.swift` — Added `bezelController.clipboardMonitor = clipboardMonitor` injection
- `FlycutSwift/Services/ClipboardMonitor.swift` — Replaced fixed timer with adaptive polling: `scheduleTimer`, `checkPasteboardAdaptive`, `registerActivityMonitor`, `hasActivityMonitor`, `timerRecreationCount`, updated `start()` and `stop()`
- `FlycutTests/ClipboardMonitorTests.swift` — Added `testActivityMonitorRegistered` and `testTimerNotRecreatedWhenIntervalUnchanged`

## Decisions Made

- `NSMenuItem.target = self` set explicitly on every NSMenuItem — non-activating NSPanel does not route actions through responder chain without explicit target (RESEARCH.md Pitfall 1)
- `showQuickActionMenu(at:)` extracted to separate method — called from both `rightMouseDown` and Tab key handler
- `applyTransform` does NOT auto-paste — user reviews transformed content and presses Enter (RESEARCH.md Open Question 1)
- `activeInterval` stored as `var` property (set in `start()`) rather than constant — required so `checkPasteboardAdaptive()` comparison uses the same interval as the running timer when user config overrides the default
- Tab key (keyCode 48) intercepted in `sendEvent` before SwiftUI — same approach used by Escape, arrow keys

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed timer recreation false positive due to user-configured interval mismatch**
- **Found during:** Task 2 (TDD Green phase — `testTimerNotRecreatedWhenIntervalUnchanged` failed)
- **Issue:** `start()` used user-configured interval (e.g. 1.0s from UserDefaults) as `startInterval`, but `checkPasteboardAdaptive()` compared against hardcoded `activeInterval` (0.5s) — causing `abs(1.0 - 0.5) = 0.5 > 0.01`, which triggered a spurious timer recreation on the very first tick
- **Fix:** Changed `activeInterval` from `let` constant to `var` property; `start()` sets `activeInterval = stored > 0 ? stored : defaultActiveInterval` so `checkPasteboardAdaptive()` compares against the same value the timer was created with
- **Files modified:** `FlycutSwift/Services/ClipboardMonitor.swift`
- **Verification:** `testTimerNotRecreatedWhenIntervalUnchanged` now passes; full suite passes
- **Committed in:** `a154c95` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 bug — timer interval mismatch between start() and adaptive check)
**Impact on plan:** Mechanical correctness fix, no scope change.

## Issues Encountered

None requiring escalation.

## User Setup Required

None — fully automated.

## Next Phase Readiness

- Quick action menu fully operational — Plan 06-03 can add Export/Import UI buttons
- Adaptive polling active — CPU usage reduces after 30s idle
- TextTransformerTests, ClipboardMonitorTests, and full suite all pass
- ClipboardMonitor `blockedChangeCount` self-capture prevention works for both string and RTF pasteboard writes

## Self-Check: PASSED

- BezelController.swift: FOUND (rightMouseDown present)
- ClipboardMonitor.swift: FOUND (activityMonitor present)
- ClipboardMonitorTests.swift: FOUND
- 06-02-SUMMARY.md: FOUND
- Commit 2468f8e (Task 1): FOUND
- Commit a154c95 (Task 2): FOUND

---
*Phase: 06-quick-actions-performance*
*Completed: 2026-03-12*
