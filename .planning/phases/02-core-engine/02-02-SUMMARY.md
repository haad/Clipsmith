---
phase: 02-core-engine
plan: 02
subsystem: services
tags: [nspasteboard, cgevent, nsworkspace, swift6, tdd, clipboard, pasteboard-monitoring]

# Dependency graph
requires:
  - phase: 02-core-engine/02-01
    provides: ClipboardStore @ModelActor, FlycutTests bundle target with makeTestContainer()
  - phase: 01-foundation
    provides: AccessibilityMonitor pattern, AppSettingsKeys, project structure

provides:
  - ClipboardMonitor @Observable @MainActor NSPasteboard poller at 0.5s in RunLoop.common mode with transient/password filter and blockedChangeCount self-capture prevention
  - PasteService @MainActor plain-text paste injector via CGEvent.post Cmd-V with 200ms activation delay
  - AppTracker @Observable @MainActor NSWorkspace notification observer tracking previousApp (excluding Flycut)
  - 5 ClipboardMonitorTests (shouldSkip/blockedChangeCount) + 1 PasteServiceTests (plain-text-only)
affects: [02-03-hotkey-registration, 02-04-MenuBarView, 03-bezel-ui, all tests referencing ClipboardMonitor/PasteService]

# Tech tracking
tech-stack:
  added: []
  patterns: [NSPasteboard changeCount polling with RunLoop.common, CGEvent.post(tap:) Cmd-V injection, NSWorkspace notification observer with Task @MainActor hop for Swift 6, activate(from:options:) macOS 14+ app activation]

key-files:
  created:
    - FlycutSwift/Services/ClipboardMonitor.swift
    - FlycutSwift/Services/PasteService.swift
    - FlycutSwift/Services/AppTracker.swift
    - FlycutTests/ClipboardMonitorTests.swift
    - FlycutTests/PasteServiceTests.swift
  modified:
    - FlycutSwift.xcodeproj/project.pbxproj

key-decisions:
  - "CGEventPost is obsoleted in Swift 3 — use CGEvent.post(tap:) instance method with CGEventTapLocation(rawValue: 0) for kCGHIDEventTap"
  - "activateIgnoringOtherApps deprecated macOS 14 — use activate(from: NSRunningApplication.current, options: []) instead"
  - "AppTracker notification closure uses Task { @MainActor } hop for Swift 6 Sendable compliance — .main queue is insufficient on its own"
  - "shouldSkip and checkPasteboard are internal (not private) on ClipboardMonitor — enables direct test invocation without timer"

patterns-established:
  - "NSPasteboard polling: RunLoop.current.add(timer, forMode: .common) — NOT Timer.scheduledTimer which stops during menu tracking"
  - "Self-capture prevention: PasteService sets clipboardMonitor.blockedChangeCount = pasteboard.changeCount after every write"
  - "CGEvent injection: CGEvent.post(tap: CGEventTapLocation(rawValue: 0)!) — rawValue 0 == kCGHIDEventTap"
  - "App activation macOS 14+: app.activate(from: NSRunningApplication.current, options: [])"

requirements-completed: [CLIP-01, CLIP-04, CLIP-06, INTR-03]

# Metrics
duration: 7min
completed: 2026-03-05
---

# Phase 2 Plan 02: ClipboardMonitor, PasteService, and AppTracker Summary

**NSPasteboard poller with 8-type transient/password filter, CGEvent.post Cmd-V injector with self-capture prevention via blockedChangeCount, and workspace notification app tracker — 6 new tests passing under Swift 6 strict concurrency**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-05T17:17:01Z
- **Completed:** 2026-03-05T17:24:10Z
- **Tasks:** 2 (TDD: red+green on Task 1, standard on Task 2)
- **Files modified:** 6

## Accomplishments

- ClipboardMonitor polls NSPasteboard.general at 0.5s intervals in RunLoop.common mode (fires while menus are open — critical for usability); filters 8 known transient/password types from nspasteboard.org and 1Password; blockedChangeCount property prevents self-capture when PasteService writes to pasteboard
- PasteService writes plain text only (clearContents + setString .string) per CLIP-06, sets blockedChangeCount after write, activates previousApp via macOS 14+ activate(from:options:), waits 200ms, then fires CGEvent.post Cmd-V via kCGHIDEventTap (rawValue 0)
- AppTracker observes NSWorkspace.didActivateApplicationNotification and tracks previousApp excluding Flycut's own bundleID; uses Task { @MainActor } hop for Swift 6 compliance
- All 6 new unit tests pass (5 ClipboardMonitor + 1 PasteService); all 13 total tests pass (includes 7 ClipboardStore from Plan 01)

## Task Commits

Each task was committed atomically:

1. **Task 1: ClipboardMonitor with transient/password filter and tests** - `f05a008` (feat)
2. **Task 2: PasteService, AppTracker, and PasteServiceTests** - `5e356df` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `FlycutSwift/Services/ClipboardMonitor.swift` — @Observable @MainActor NSPasteboard poller with shouldSkip filter, blockedChangeCount self-capture prevention, RunLoop.common timer
- `FlycutSwift/Services/PasteService.swift` — @MainActor plain-text paste injector with AXIsProcessTrusted guard, self-capture wiring, activate(from:options:), 200ms sleep, CGEvent.post Cmd-V
- `FlycutSwift/Services/AppTracker.swift` — @Observable @MainActor workspace notification observer tracking previousApp excluding Flycut bundle ID
- `FlycutTests/ClipboardMonitorTests.swift` — 5 tests: transient/concealed/1password types skipped, normal text not skipped, blockedChangeCount prevents self-capture
- `FlycutTests/PasteServiceTests.swift` — 1 test: plain-text-only pasteboard write verified (no RTF/HTML types)
- `FlycutSwift.xcodeproj/project.pbxproj` — Added 5 new file references (AF0022-AF0026), 3 PBXBuildFiles to FlycutSwift Sources (AA0020-AA0023), 2 PBXBuildFiles to FlycutTests Sources (AA0021, AA0024), updated GG0004 Services group and GG0010 FlycutTests group

## Decisions Made

- `CGEventPost` is obsoleted in Swift 3 — the modern API is `CGEvent.post(tap:)` instance method; `CGEventTapLocation` has no named `.hid` member in the SDK, use `CGEventTapLocation(rawValue: 0)` for `kCGHIDEventTap`
- `activateIgnoringOtherApps` deprecated macOS 14 — replaced with `activate(from: NSRunningApplication.current, options: [])` which explicitly delegates focus from Flycut to the target app
- AppTracker notification closure uses `Task { @MainActor }` hop even though `queue: .main` is specified — Swift 6 strict concurrency requires this because the closure is Sendable
- `shouldSkip` and `checkPasteboard` are `internal` (not `private`) on ClipboardMonitor — direct test invocation avoids timer complexity; test calls `monitor.checkPasteboard()` after manually setting `lastChangeCount`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CGEventPost obsoleted in Swift 3 — wrong API in research doc**
- **Found during:** Task 2 (PasteService implementation)
- **Issue:** Research doc Pattern 3 used `CGEventPost(.hid, keyDown)` which doesn't compile — `CGEventPost` was obsoleted in Swift 3 and `CGEventTapLocation` has no `.hid` or `.cgHIDEventTap` Swift member
- **Fix:** Changed to `CGEvent.post(tap: CGEventTapLocation(rawValue: 0)!)` instance method; `rawValue: 0` == `kCGHIDEventTap`
- **Files modified:** FlycutSwift/Services/PasteService.swift
- **Verification:** Build succeeded, PasteServiceTests pass
- **Committed in:** 5e356df (Task 2 commit)

**2. [Rule 1 - Bug] activateIgnoringOtherApps deprecated macOS 14**
- **Found during:** Task 2 (PasteService implementation)
- **Issue:** `NSApplicationActivateIgnoringOtherApps` deprecated in macOS 14, generates warning — plan used the deprecated option
- **Fix:** Replaced with `app.activate(from: NSRunningApplication.current, options: [])` — the macOS 14+ API that explicitly specifies the activating application
- **Files modified:** FlycutSwift/Services/PasteService.swift
- **Verification:** Build clean (zero warnings), PasteServiceTests pass
- **Committed in:** 5e356df (Task 2 commit)

**3. [Rule 1 - Bug] AppTracker @MainActor property mutation from Sendable closure**
- **Found during:** Task 2 (AppTracker implementation)
- **Issue:** Assigning to `self.previousApp` from the `addObserver` closure caused Swift 6 error: "Main actor-isolated property cannot be mutated from a Sendable closure"
- **Fix:** Captured `activatedApp` from notification userInfo, then dispatched `Task { @MainActor [weak self] in self?.previousApp = activatedApp }` to hop to the main actor explicitly
- **Files modified:** FlycutSwift/Services/AppTracker.swift
- **Verification:** Build clean (zero warnings)
- **Committed in:** 5e356df (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (Rule 1 — all API correctness bugs from research doc or Swift 6 concurrency)
**Impact on plan:** All three fixes required for correctness and zero-warning Swift 6 compliance. No scope creep.

## Issues Encountered

- Research doc Pattern 3 had incorrect CGEventPost syntax that was never validated against the actual SDK — `CGEventTapLocation` has no named Swift members, only rawValue. Verified fix compiles correctly.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ClipboardMonitor, PasteService, and AppTracker are ready for wiring in AppDelegate (Plan 03)
- PasteService requires `clipboardMonitor` property to be set after both objects are created
- AppTracker must be started before any hotkey fires so `previousApp` is populated at activation time
- All 6 unit tests passing; CGEventPost path requires manual smoke test (INTR-03) with accessibility permission granted

## Self-Check: PASSED

- ClipboardMonitor.swift: FOUND
- PasteService.swift: FOUND
- AppTracker.swift: FOUND
- ClipboardMonitorTests.swift: FOUND
- PasteServiceTests.swift: FOUND
- 02-02-SUMMARY.md: FOUND
- Commit f05a008: FOUND
- Commit 5e356df: FOUND

---
*Phase: 02-core-engine*
*Completed: 2026-03-05*
