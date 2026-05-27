---
phase: 11-app-launcher
plan: "02"
subsystem: views
tags: [macos, swift6, swiftui, app-launcher, bezel-pattern, fuzzy-search, nsworkspace]

requires:
  - phase: 11-01
    provides: "AppEntry struct, AppScannerService (@MainActor @Observable), AppSettingsKeys additions"
  - phase: 07-intelligent-search-ai
    provides: "FuzzyMatcher.score (static, reused for ranking)"

provides:
  - "AppLaunchViewModel (@Observable @MainActor) — displayedApps computation with fuzzy+recency ranking, navigation"
  - "AppLaunchView (SwiftUI) — frosted glass bezel with always-focused TextField, 24x24 icon rows, ScrollViewReader"
  - "AppLaunchController (@MainActor NSPanel) — non-activating bezel #4, sendEvent intercept, show/hide, launchSelected"
  - "AppScannerService icon loading — loadIcons(for:) nonisolated helper, Task.detached icon load after scan"
  - "AppLaunchViewModelTests — 4/4 real assertions (fuzzy ranking, recency boost, empty-query, navigation clamping)"
  - "PBX IDs AF0086-AF0088 / AA0085-AA0087 wired in project.pbxproj"

affects:
  - 11-03: AppDelegate wires appScannerService + appLaunchController; hotkey handler uses appLauncherEnabled;
           MenuBarView adds .clipsmithOpenAppLauncher notification + button; Settings adds toggle + hotkey recorder

tech-stack:
  added: []
  patterns:
    - "NSWorkspace.OpenConfiguration (not NSWorkspaceOpenConfiguration — renamed in macOS 15 SDK)"
    - "FuzzyMatcher score comparison: query 'fi' → 'Finder' scores 1.0 (prefix), 'FaceTime'/'Safari' score 0.667 (non-consecutive)"
    - "AppLaunchController.show(): sync cached state BEFORE makeKeyAndOrderFront, then async refresh updates state on completion"
    - "AppScannerService two-phase refresh: apps assigned with nil icons first (instant display), then Task.detached loads icons and updates"

key-files:
  created:
    - "Clipsmith/Views/AppLaunchViewModel.swift"
    - "Clipsmith/Views/AppLaunchView.swift"
    - "Clipsmith/Views/AppLaunchController.swift"
  modified:
    - "Clipsmith/Services/AppScannerService.swift"
    - "ClipsmithTests/AppLaunchViewModelTests.swift"
    - "Clipsmith.xcodeproj/project.pbxproj"

key-decisions:
  - "NSWorkspaceOpenConfiguration renamed: macOS 15 SDK uses NSWorkspace.OpenConfiguration — PATTERNS.md had the old name. Fixed in AppLaunchController."
  - "FuzzyMatcher 'calc' does NOT match 'Calendar': 'c-a-l-c' requires a second 'c' after 'l' which Calendar lacks. Test fixtures updated to use 'fi'/'Finder'/'FaceTime'/'Safari' which genuinely differ in score."
  - "Tie-break in recomputeDisplayedApps: equal-scored apps sorted by name.lowercased() ascending — documented in AppLaunchViewModel for Plan 03 human-verify predictability."
  - "AppLaunchController has no isHotkeyHold/flagsMonitor/pasteService/appTracker — launcher is always sticky (no hold-to-show mode)."
  - "ClaudeToolkit files (untracked in main repo, referenced in pbxproj) added to worktree to unblock build — pre-existing issue not caused by Plan 02."

patterns-established:
  - "PBX ID assignment: AF0086 AppLaunchViewModel (main), AF0087 AppLaunchView (main), AF0088 AppLaunchController (main); AA0085-87 build file IDs"

requirements-completed: []

duration: ~30min
completed: 2026-05-25
---

# Phase 11 Plan 02: App Launcher ViewModel + Controller + View Summary

**AppLaunchViewModel with FuzzyMatcher+recency ranking, AppLaunchController as non-activating bezel #4, and AppLaunchView SwiftUI surface — implementing the fourth bezel in the app with 4/4 unit tests passing and full test suite green**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-05-25T15:45:00Z
- **Completed:** 2026-05-25T16:15:00Z
- **Tasks:** 4
- **Files modified:** 6

## Accomplishments

- `AppLaunchViewModel` with D-04/D-05 ranking, navigation methods, tie-break by name
- `AppLaunchView` with frosted glass, always-focused TextField (D-03), 24x24 icon rows (D-06)
- `AppLaunchController` as non-activating NSPanel: sendEvent intercept, show/hide/launchSelected (D-08/D-09)
- `AppScannerService` extended with two-phase async icon loading (scan then icons, both on Task.detached)
- All 4 `AppLaunchViewModelTests` pass with real assertions (not XCTSkip stubs)
- Full test suite (`TEST SUCCEEDED`) — no regressions across all 20 test suites

## Task Commits

1. **Task 1: AppLaunchViewModel + test stubs replaced** — `c77849e` (feat)
2. **Task 2: AppLaunchView SwiftUI surface** — `8a13af8` (feat)
3. **Task 3: AppLaunchController + icon loading** — `e0234a8` (feat)
4. **Task 4: pbxproj entries** — `f925ab0` (chore)

## Files Created/Modified

- `Clipsmith/Views/AppLaunchViewModel.swift` — @Observable @MainActor ranking ViewModel
- `Clipsmith/Views/AppLaunchView.swift` — SwiftUI bezel view with frosted glass + icon rows
- `Clipsmith/Views/AppLaunchController.swift` — NSPanel subclass (non-activating bezel #4)
- `Clipsmith/Services/AppScannerService.swift` — extended with loadIcons(for:) + second Task.detached
- `ClipsmithTests/AppLaunchViewModelTests.swift` — 4 real test cases replacing XCTSkip stubs
- `Clipsmith.xcodeproj/project.pbxproj` — AF0086-88, AA0085-87 for the three new view files

## PBX IDs Assigned

| File | File Ref | Build File |
|------|----------|------------|
| AppLaunchViewModel.swift | AF0086 | AA0085 |
| AppLaunchView.swift | AF0087 | AA0086 |
| AppLaunchController.swift | AF0088 | AA0087 |

Next available IDs for Plan 03: AF0089+, AA0088+

## Ranking Edge Cases Discovered

1. **FuzzyMatcher 'calc' does not match 'Calendar'**: The plan specified fixtures using "Calendar" and "Calculator" with query "calc". In practice, 'c-a-l-c' is NOT a subsequence of 'Calendar' (the second 'c' after 'l' doesn't exist in "Calendar"). Test fixtures were updated to use apps with genuinely different scores ("Finder" scores 1.0 for "fi" vs "FaceTime"/"Safari" scoring ~0.67).

2. **NSWorkspace.OpenConfiguration API**: PATTERNS.md referenced `NSWorkspaceOpenConfiguration` (the Obj-C name) but the Swift 6 / macOS 15 SDK uses `NSWorkspace.OpenConfiguration`. Auto-fixed (Rule 1).

3. **Tie-break behavior**: Two apps with identical FuzzyMatcher + recency scores sort by `name.lowercased()` ascending. This is documented in `AppLaunchViewModel.recomputeDisplayedApps()` for deterministic human-verify expectations in Plan 03.

## Notes for Plan 03

- **AppDelegate wiring**: Inject `appScannerService` into `appLaunchController.appScannerService` after creation. Call `Task { await appScannerService.refresh() }` at startup for cache warm-up.
- **Hotkey guard**: Register `.appLauncher` hotkey unconditionally; check `appLauncherEnabled` inside handler. On press when visible: `viewModel.navigateDown()`. On press when hidden: `show()`.
- **MenuBarView notification**: `.clipsmithOpenAppLauncher` → `openAppLauncherFromMenu()` in AppDelegate calls `appLaunchController?.show()`.
- **Settings**: `@AppStorage(AppSettingsKeys.appLauncherEnabled)` toggle in Features section + `KeyboardShortcuts.Recorder` in HotkeySettingsTab.
- **Edge case — no initial scan**: If user opens launcher before `loadInitially()` completes, `show()` presents with `apps=[]` and `viewModel.isLoading=true` (shows ProgressView). Refresh fires async on each show(), so list appears within ~0.5s.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NSWorkspaceOpenConfiguration → NSWorkspace.OpenConfiguration**
- **Found during:** Task 3
- **Issue:** PATTERNS.md specified `NSWorkspaceOpenConfiguration()` which is the Objective-C name. The Swift SDK on macOS 15 uses `NSWorkspace.OpenConfiguration()`.
- **Fix:** Used `NSWorkspace.OpenConfiguration()` in `launchSelected()`.
- **Files modified:** `Clipsmith/Views/AppLaunchController.swift`
- **Commit:** `e0234a8`

**2. [Rule 1 - Bug] Test fixture: 'calc' doesn't match 'Calendar'**
- **Found during:** Task 1 (test run)
- **Issue:** Plan specified `Calendar` should match query `"calc"` and rank second after `Calculator`. `FuzzyMatcher.score("Calendar", query: "calc")` returns nil because 'c-a-l-c' requires a 'c' after the 'l' in Calendar — which doesn't exist.
- **Fix:** Redesigned `testFuzzyFilterReturnsRankedMatches` to use `["Finder", "FaceTime", "Safari", "Notes"]` with query `"fi"`. Finder scores 1.0 (prefix); FaceTime and Safari score 0.667 (non-consecutive); Notes has no 'i' → nil. This genuinely tests ranking differentiation.
- **Files modified:** `ClipsmithTests/AppLaunchViewModelTests.swift`
- **Commit:** `c77849e`

**3. [Rule 3 - Blocking] ClaudeToolkit files missing from worktree**
- **Found during:** Task 4 (initial build attempt)
- **Issue:** `Clipsmith/Services/ClaudeToolkitService.swift` and `Clipsmith/Views/ClaudeToolkit/ClaudeToolkitWindowView.swift` are referenced in `project.pbxproj` (AA0083/AA0084) but don't exist in the worktree. These are untracked files in the main working tree added by an unrelated session.
- **Fix:** Copied the files from the main repo into the worktree to unblock the build. They compile cleanly.
- **Files modified:** `Clipsmith/Services/ClaudeToolkitService.swift` (new in worktree), `Clipsmith/Views/ClaudeToolkit/ClaudeToolkitWindowView.swift` (new in worktree)
- **Commit:** `e0234a8`

## Known Stubs

`AppEntry.icon` starts as nil in `AppScannerService.scanApps()` and is populated by `loadIcons(for:)` in the second Task.detached phase. Before icons load, `AppLaunchView.appRow` renders the `Image(systemName: "app.dashed")` placeholder. This is intentional — the two-phase load (scan first, icons second) ensures the bezel opens immediately with app names while icons stream in.

## Threat Surface Scan

No new network endpoints or auth paths introduced. The URL passed to `NSWorkspace.shared.openApplication(at:configuration:)` originates from `AppScannerService.scanApps()` enumeration of the five whitelisted paths — never from user input. Threat T-11-02 (elevation of privilege via `launchSelected`) is mitigated: search query is filter-only and never reaches NSWorkspace.

## Self-Check

- [x] `Clipsmith/Views/AppLaunchViewModel.swift` exists
- [x] `Clipsmith/Views/AppLaunchView.swift` exists
- [x] `Clipsmith/Views/AppLaunchController.swift` exists
- [x] `Clipsmith/Services/AppScannerService.swift` has `loadIcons` + 2nd `Task.detached`
- [x] `ClipsmithTests/AppLaunchViewModelTests.swift` has 0 XCTSkip stubs
- [x] Commits `c77849e`, `8a13af8`, `e0234a8`, `f925ab0` exist
- [x] `xcodebuild build` → BUILD SUCCEEDED
- [x] AppLaunchViewModelTests 4/4 pass
- [x] AppScannerServiceTests 4/4 still pass
- [x] Full TEST SUCCEEDED (20 test suites, 0 failures)

## Self-Check: PASSED

---
*Phase: 11-app-launcher*
*Completed: 2026-05-25*
