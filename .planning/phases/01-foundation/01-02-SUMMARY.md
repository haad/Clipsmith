---
phase: 01-foundation
plan: 02
subsystem: ui
tags: [swift, swiftui, swiftdata, macos, settings, keyboard-shortcuts, spm, smappservice, accessibility]

# Dependency graph
requires:
  - phase: 01-01
    provides: AppDelegate with AccessibilityMonitor, FlycutApp with Settings scene, placeholder SettingsView
provides:
  - AppSettings @Observable class with @ObservationIgnored @AppStorage pattern for all user settings
  - AppSettingsKeys enum namespace for all UserDefaults string constants
  - KeyboardShortcuts.Name stubs for activateBezel and activateSearch
  - SettingsView TabView with General and Shortcuts tabs
  - GeneralSettingsTab with steppers for history/display, toggles for paste behavior, SMAppService launch-at-login
  - HotkeySettingsTab with KeyboardShortcuts.Recorder for both hotkeys
  - AccessibilitySettingsSection showing trust status with system-settings link
  - KeyboardShortcuts SPM 2.4.0 linked to FlycutSwift target
affects: [03-clipboard, 04-bezel, 05-search]

# Tech tracking
tech-stack:
  added:
    - KeyboardShortcuts 2.4.0 (sindresorhus/KeyboardShortcuts) via SPM
    - ServiceManagement (SMAppService.mainApp for launch-at-login)
  patterns:
    - "@ObservationIgnored @AppStorage on each property of @Observable class (Swift 6 requirement)"
    - "SMAppService status check before register/unregister to avoid double-registration error"
    - "syncLaunchAtLogin() on .onAppear reads system ground truth; reverts toggle on SMAppService error"
    - "@AppStorage directly in views (no @Bindable AppSettings needed) — simplest correct approach"
    - "KeyboardShortcuts.Recorder references .Name stubs defined in KeyboardShortcutNames.swift"

key-files:
  created:
    - FlycutSwift/Settings/AppSettingsKeys.swift
    - FlycutSwift/Settings/AppSettings.swift
    - FlycutSwift/Settings/KeyboardShortcutNames.swift
    - FlycutSwift/Views/Settings/GeneralSettingsTab.swift
    - FlycutSwift/Views/Settings/HotkeySettingsTab.swift
    - FlycutSwift/Views/Settings/AccessibilitySettingsSection.swift
  modified:
    - FlycutSwift/Views/SettingsView.swift
    - FlycutSwift/App/FlycutApp.swift
    - FlycutSwift.xcodeproj/project.pbxproj

key-decisions:
  - "@AppStorage used directly in views (not via AppSettings) — removes need for @Bindable, simpler binding chain"
  - "KeyboardShortcuts.Recorder shown in Phase 1 as placeholder; actual CGEventTap registration deferred to Phase 2"
  - "SMAppService.status checked before register/unregister — avoids 'already registered' error without try/catch masking"

patterns-established:
  - "Rule 2 - Missing Critical: syncLaunchAtLogin() on .onAppear added — system may change launch-at-login externally"

requirements-completed: [SETT-01, SETT-02, SETT-03, SETT-04, SETT-05, SHELL-03]

# Metrics
duration: 4min
completed: 2026-03-05
---

# Phase 1 Plan 02: Settings Infrastructure Summary

**AppSettings @Observable class, KeyboardShortcuts 2.4.0 SPM, tabbed preferences window with General (history/paste/SMAppService launch-at-login/accessibility status) and Shortcuts (KeyboardShortcuts.Recorder) tabs — Swift 6 strict concurrency throughout**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-05T14:58:09Z
- **Completed:** 2026-03-05T15:01:53Z
- **Tasks:** 2 auto-tasks + 1 human-verify checkpoint (approved 2026-03-05)
- **Files modified:** 9

## Accomplishments

- Added KeyboardShortcuts 2.4.0 SPM dependency and linked to FlycutSwift target (resolves cleanly)
- Created AppSettings @Observable class with @ObservationIgnored @AppStorage pattern (Swift 6 requirement)
- Built complete settings UI: tabbed SettingsView, GeneralSettingsTab, HotkeySettingsTab, AccessibilitySettingsSection
- SMAppService launch-at-login toggle with status-check guard and .onAppear sync to system ground truth
- AccessibilitySettingsSection reads AccessibilityMonitor.isTrusted from environment; never calls prompt variant

## Task Commits

Each task was committed atomically:

1. **Task 1: Add KeyboardShortcuts SPM, AppSettings, AppSettingsKeys, KeyboardShortcutNames** - `110ebc2` (feat)
2. **Task 2: Build SettingsView with General/Shortcuts tabs, wire SMAppService and AccessibilityMonitor** - `efa1ec4` (feat)

## Files Created/Modified

- `FlycutSwift/Settings/AppSettingsKeys.swift` - String constants for all 7 UserDefaults keys
- `FlycutSwift/Settings/AppSettings.swift` - @Observable class with @ObservationIgnored @AppStorage on each property
- `FlycutSwift/Settings/KeyboardShortcutNames.swift` - KeyboardShortcuts.Name extensions for activateBezel, activateSearch
- `FlycutSwift/Views/SettingsView.swift` - TabView with General and Shortcuts tabs, minWidth 420
- `FlycutSwift/Views/Settings/GeneralSettingsTab.swift` - History steppers, paste toggles, SMAppService launch-at-login, AccessibilitySettingsSection
- `FlycutSwift/Views/Settings/HotkeySettingsTab.swift` - KeyboardShortcuts.Recorder for both hotkeys with footer note
- `FlycutSwift/Views/Settings/AccessibilitySettingsSection.swift` - Trust status display, "Open System Settings" button
- `FlycutSwift/App/FlycutApp.swift` - Inject AppSettings into environment for MenuBarExtra and Settings scenes
- `FlycutSwift.xcodeproj/project.pbxproj` - SPM package refs, product dep, 6 new file refs in Settings + Views/Settings groups

## Decisions Made

- **@AppStorage used directly in views (not via @Bindable AppSettings)**: Using @AppStorage directly in GeneralSettingsTab avoids the @Observable + @Bindable binding chain complexity. Settings views can bind directly to @AppStorage which is always safe in a SwiftUI view context.
- **KeyboardShortcuts.Recorder as placeholder only**: Recorders store user-assigned shortcuts via KeyboardShortcuts library but actual CGEventTap registration is Phase 2. UI is fully functional for shortcut assignment.
- **SMAppService status guard before register/unregister**: Checking `.status != .enabled` before `.register()` prevents the "already registered" error without silently masking real failures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added syncLaunchAtLogin() on .onAppear to read system ground truth**
- **Found during:** Task 2 (GeneralSettingsTab implementation)
- **Issue:** Plan specified calling SMAppService on toggle change but the system can change launch-at-login state externally (user removes it via Login Items settings). Without syncing on appear, the toggle would show stale stored state.
- **Fix:** Added `syncLaunchAtLogin()` private method called in `.onAppear` modifier — reads `SMAppService.mainApp.status == .enabled` and corrects `launchAtLogin` if it differs.
- **Files modified:** FlycutSwift/Views/Settings/GeneralSettingsTab.swift
- **Verification:** Build succeeds; logic is correct per plan's Pitfall 4 note.
- **Committed in:** efa1ec4 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing critical correctness behavior)
**Impact on plan:** Sync on appear is essential for correctness. The plan mentioned "sync launchAtLogin with SMAppService.mainApp.status == .enabled to reflect system ground truth" — implementing it was required, not out of scope.

## Issues Encountered

None — both tasks completed cleanly on first build attempt.

## Human Verification

Task 3 (`checkpoint:human-verify`) was approved by the user on 2026-03-05. The following was confirmed:

- Menu bar icon appears, no dock icon visible
- Preferences window opens via cmd-comma with General and Shortcuts tabs
- Settings persist across app restart (history steppers, toggles)
- Accessibility status displayed correctly in General tab
- Hotkey recorders in Shortcuts tab accept and display key combinations
- No errors in Xcode console

## User Setup Required

None — no external service configuration required beyond granting Accessibility permission in System Settings if not already done.

## Next Phase Readiness

- All Phase 1 settings infrastructure is complete
- Phase 2 reads `AppSettings.rememberNum`, `displayNum`, `displayLen` to configure clipboard monitoring
- Phase 2 registers `KeyboardShortcuts.Name.activateBezel` and `.activateSearch` via CGEventTap
- `AccessibilityMonitor` is in environment for all views

---
*Phase: 01-foundation*
*Completed: 2026-03-05*

## Self-Check: PASSED

All created files verified on disk. Both task commits (110ebc2, efa1ec4) verified in git log. Human verification checkpoint approved. Build succeeds with zero errors (Swift 6 strict concurrency).
