---
phase: 11-app-launcher
plan: "01"
subsystem: services
tags: [macos, swift6, swiftui, app-launcher, filemanager, fuzzy-search, userdefaults]

requires:
  - phase: 07-intelligent-search-ai
    provides: "FuzzyMatcher service (reused in Plan 02 AppLaunchViewModel)"
  - phase: 10-lemon-squeezy-licensing-monetization
    provides: "AppSettingsKeys enum pattern; established PBX ID scheme through AF0080/AA0079"

provides:
  - "AppEntry struct (Sendable, Identifiable) — app bundle value type with name/url/bundleID/icon"
  - "AppScannerService (@MainActor @Observable) — scans 5 app directories, deduplicates, tracks recency"
  - "AppSettingsKeys.appLauncherEnabled and recentAppBundleIDs constants"
  - "AppScannerServiceTests — 4 passing recordLaunch unit tests"
  - "AppLaunchViewModelTests — 4 placeholder test stubs for Plan 02"
  - "PBX IDs AF0081-AF0083 / AA0080-AA0082 reserved and wired in project.pbxproj"

affects:
  - 11-02: AppLaunchViewModel references AppEntry, AppScannerService.recentBundleIDs
  - 11-03: AppDelegate wires appScannerService + appLaunchController, hotkey guard uses appLauncherEnabled

tech-stack:
  added: []
  patterns:
    - "@unchecked Sendable on AppEntry to allow NSImage across @MainActor boundary (mirrors ClippingInfo pattern)"
    - "nonisolated async scanApps() called via Task.detached from @MainActor refresh() — avoids implicit self capture warning"
    - "Five whitelisted FileManager.contentsOfDirectory(depth=1) search paths per CONTEXT D-01"
    - "recordLaunch dedup-then-prepend-then-cap-at-5 with UserDefaults persistence"

key-files:
  created:
    - "Clipsmith/Services/AppScannerService.swift"
    - "ClipsmithTests/AppScannerServiceTests.swift"
    - "ClipsmithTests/AppLaunchViewModelTests.swift"
  modified:
    - "Clipsmith/Settings/AppSettingsKeys.swift"
    - "Clipsmith.xcodeproj/project.pbxproj"

key-decisions:
  - "AppEntry uses @unchecked Sendable because NSImage is not Sendable in Swift 6; icon is only written from @MainActor so no concurrent mutation occurs"
  - "scanApps() marked nonisolated to allow call from Task.detached without compiler warning about crossing actor isolation"
  - "dedupeKey = bundleID ?? url.resolvingSymlinksInPath().path — handles both normal bundles and malformed/symlinked bundles without crashing"
  - "AppLaunchViewModelTests uses XCTSkip stubs (not compile-time symbols) so the test target builds without AppLaunchViewModel existing yet"

patterns-established:
  - "PBX ID assignment: AF0081 AppScannerService (main), AF0082 AppScannerServiceTests, AF0083 AppLaunchViewModelTests; AA0080-82 build file IDs"

requirements-completed: []

duration: ~15min
completed: 2026-05-25
---

# Phase 11 Plan 01: App Launcher Foundation Summary

**AppScannerService scans five macOS app directories via FileManager (depth=1), deduplicates by CFBundleIdentifier, and tracks the last 5 launched apps in UserDefaults — establishing the data layer for the Phase 11 keyboard-driven app launcher bezel**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-05-25T13:30:00Z
- **Completed:** 2026-05-25T13:45:00Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- `AppScannerService` with full scan, dedup, recency tracking, and `@MainActor @Observable` pattern established
- 4/4 `AppScannerServiceTests` (recordLaunch) pass
- `AppLaunchViewModelTests` stubs compile and show 4 skipped tests (no AppLaunchViewModel yet)
- All 3 new files registered in `project.pbxproj`; full project `BUILD SUCCEEDED`

## Task Commits

Each task was committed atomically:

1. **Task 1: AppScannerService + AppSettingsKeys additions** - `cd74df2` (feat)
2. **Task 2: Wave 0 test stubs** - `975e524` (test)
3. **Task 3: Register files in Xcode project.pbxproj** - `08aef87` (chore)

## Files Created/Modified

- `Clipsmith/Services/AppScannerService.swift` — AppEntry struct + AppScannerService with loadInitially/refresh/recordLaunch/scanApps
- `Clipsmith/Settings/AppSettingsKeys.swift` — appLauncherEnabled + recentAppBundleIDs constants added
- `ClipsmithTests/AppScannerServiceTests.swift` — 4 recordLaunch tests (prepend, dedup, cap-5, persist-to-UserDefaults)
- `ClipsmithTests/AppLaunchViewModelTests.swift` — 4 XCTSkip placeholder stubs for Plan 02
- `Clipsmith.xcodeproj/project.pbxproj` — PBX entries for all 3 new files (AF0081-83, AA0080-82)

## PBX IDs Assigned

| File | File Ref | Build File |
|------|----------|------------|
| AppScannerService.swift | AF0081 | AA0080 |
| AppScannerServiceTests.swift | AF0082 | AA0081 |
| AppLaunchViewModelTests.swift | AF0083 | AA0082 |

Next available IDs for Plan 02: AF0084+, AA0083+

## Decisions Made

- `AppEntry` uses `@unchecked Sendable` because `NSImage` is not `Sendable` in Swift 6; icon is only mutated from `@MainActor` after background scan completes, so no concurrent mutation occurs in practice (consistent with `ClippingInfo` pattern from Phase 03.1)
- `scanApps()` is `nonisolated` so it can be called from `Task.detached` without Swift 6 compiler warning about capturing `self` across actor isolation boundaries
- `AppLaunchViewModelTests` contains only `throw XCTSkip(...)` bodies — no references to `AppLaunchViewModel` — so the test target compiles cleanly before Plan 02 creates that type

## Notes for Plan 02

Plan 02 creates `AppLaunchViewModel` and fills in the 4 ViewModel test stubs. Key naming contracts:
- `AppScannerService.apps: [AppEntry]` — set by refresh()
- `AppScannerService.recentBundleIDs: [String]` — injected into ViewModel
- `AppEntry.bundleID: String?` — used for recency lookup
- `AppEntry.icon: NSImage?` — nil until Plan 02 loads icons
- `AppSettingsKeys.recentAppBundleIDs` — UserDefaults key for persistence

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Stub Tracking

`AppEntry.icon` is always `nil` in this plan. This is intentional — icon loading is Plan 02 scope per the plan's explicit `<action>` note: "Do NOT load icons in this task — icon stays nil." This stub is tracked here per SUMMARY stub-tracking requirement; it is intentional and Plan 02 resolves it.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundary changes introduced. AppScannerService only reads from five hardcoded whitelisted paths — consistent with PLAN.md threat model T-11-01 mitigation (never accepts URL from user input). No new threat flags.

## Self-Check

- [x] `Clipsmith/Services/AppScannerService.swift` exists
- [x] `Clipsmith/Settings/AppSettingsKeys.swift` contains `appLauncherEnabled` and `recentAppBundleIDs`
- [x] `ClipsmithTests/AppScannerServiceTests.swift` exists
- [x] `ClipsmithTests/AppLaunchViewModelTests.swift` exists
- [x] Commits `cd74df2`, `975e524`, `08aef87` exist
- [x] `xcodebuild build` succeeds
- [x] 4/4 AppScannerServiceTests pass
- [x] 4/4 AppLaunchViewModelTests skipped (not failed)

## Self-Check: PASSED

---
*Phase: 11-app-launcher*
*Completed: 2026-05-25*
