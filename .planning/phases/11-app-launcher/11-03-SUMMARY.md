---
phase: 11-app-launcher
plan: "03"
subsystem: ui
tags: [macos, swift6, swiftui, app-launcher, hotkey-wiring, settings, keyboard-shortcuts]

requires:
  - phase: 11-02
    provides: "AppLaunchController, AppLaunchViewModel, AppLaunchView, AppScannerService with icon loading"
  - phase: 11-01
    provides: "AppScannerService, AppEntry, AppSettingsKeys.appLauncherEnabled"

provides:
  - "KeyboardShortcuts.Name.appLauncher constant (no default binding, D-07)"
  - "AppDelegate wiring: appScannerService + appLaunchController stored properties, loadInitially() kick-off"
  - "Hotkey registration with appLauncherEnabled feature-flag guard (D-10)"
  - ".clipsmithOpenAppLauncher Notification.Name + openAppLauncherFromMenu @objc handler"
  - "MenuBarView conditional 'App Launcher...' button (gated on appLauncherEnabled)"
  - "HotkeySettingsTab: App Launcher recorder row"
  - "GeneralSettingsTab: App Launcher feature toggle in Features section"

affects: []

tech-stack:
  added: []
  patterns:
    - "Feature-flag guard in hotkey handler — checks UserDefaults.bool(forKey: appLauncherEnabled) inside handler, not at registration time; mirrors activateDocLookup pattern"
    - "No isHotkeyHold for AppLaunchController — launcher is always sticky (no hold mode)"

key-files:
  created: []
  modified:
    - "Clipsmith/Settings/KeyboardShortcutNames.swift"
    - "Clipsmith/App/AppDelegate.swift"
    - "Clipsmith/Views/MenuBarView.swift"
    - "Clipsmith/Views/Settings/HotkeySettingsTab.swift"
    - "Clipsmith/Views/Settings/GeneralSettingsTab.swift"

key-decisions:
  - "Hotkey handler unconditionally registered at startup; feature-flag check is inside the handler (consistent with docLookup pattern) so toggling Settings works without restart"
  - "AppLaunchController has no isHotkeyHold/flagsMonitor — launcher is always sticky per Plan 02 decision"
  - "loadInitially() called via Task { await ... } — non-blocking; if user opens launcher before scan completes, show() presents with isLoading=true (ProgressView displayed)"

patterns-established:
  - "Phase 11 wiring complete: AppLauncher accessible via hotkey (no default) + menu bar button; both gated by appLauncherEnabled toggle in Settings"

requirements-completed: []

duration: ~20min
completed: 2026-05-25
---

# Phase 11 Plan 03: App Launcher Wiring Summary

**Hotkey registration, menu bar button, Settings toggle, and controller initialization wired into AppDelegate — connecting Phase 11's AppLaunchController to user-accessible entry points with feature-flag guard; Task 2 (human verification) pending user sign-off**

## Status: CHECKPOINT PENDING — Task 2 awaiting human verification

Task 1 is complete and committed. Task 2 is a `checkpoint:human-verify` gate that requires the user to run the app and verify the 6-scenario end-to-end flow before Phase 11 can be marked complete.

## Performance

- **Duration:** ~20 min
- **Started:** 2026-05-25T16:00:00Z
- **Completed (Task 1):** 2026-05-25T16:11:00Z
- **Tasks completed:** 1 of 2 (Task 2 = checkpoint:pending)
- **Files modified:** 5

## Accomplishments

- `KeyboardShortcuts.Name.appLauncher` added (no default binding per D-07)
- `AppDelegate`: `appScannerService` and `appLaunchController` stored properties added
- `AppDelegate`: initialization block for Phase 11 components with `loadInitially()` kick-off
- `AppDelegate`: `KeyboardShortcuts.onKeyDown(.appLauncher)` handler with `appLauncherEnabled` feature-flag guard (D-10)
- `AppDelegate`: `.clipsmithOpenAppLauncher` notification observer + `openAppLauncherFromMenu()` @objc handler
- `MenuBarView`: `clipsmithOpenAppLauncher` Notification.Name + conditional "App Launcher..." button
- `HotkeySettingsTab`: App Launcher recorder row added
- `GeneralSettingsTab`: App Launcher toggle in Features section
- BUILD SUCCEEDED; 193/193 tests pass

## Task Commits

1. **Task 1: Wire AppLauncher into AppDelegate, MenuBarView, KeyboardShortcutNames, and Settings tabs** — `fa3b1be` (feat)
2. **Task 2: Human-verify end-to-end App Launcher flow** — checkpoint:pending — awaiting user sign-off

## Files Modified

- `Clipsmith/Settings/KeyboardShortcutNames.swift` — `static let appLauncher = Self("appLauncher")` (no default binding)
- `Clipsmith/App/AppDelegate.swift` — 5 edits: stored properties, defaults registration, controller init, notification observer, hotkey handler + @objc method
- `Clipsmith/Views/MenuBarView.swift` — `clipsmithOpenAppLauncher` Notification.Name + `@AppStorage(appLauncherEnabled)` + conditional "App Launcher..." button
- `Clipsmith/Views/Settings/HotkeySettingsTab.swift` — App Launcher recorder row + updated footer text
- `Clipsmith/Views/Settings/GeneralSettingsTab.swift` — `@AppStorage(appLauncherEnabled)` + Toggle in Features section

## Decisions Made

- Hotkey registered unconditionally at startup (no guard at registration); feature-flag check is inside the handler, mirroring the `activateDocLookup` pattern — toggling the Settings flag works without restart
- `AppLaunchController` has no `isHotkeyHold` — the launcher is always sticky (confirmed in Plan 02)
- `loadInitially()` is non-blocking: kicked off in a `Task { await ... }` — if user opens launcher before scan completes, `show()` presents immediately with `isLoading=true` and shows a ProgressView

## Task 2: Human Verification Checkpoint — Pending

The following 6-scenario checklist must be verified by the user before Phase 11 can be marked complete:

**Test 1: Feature flag OFF (default state)**
1. Open Settings > General. Scroll to the "Features" section.
2. Confirm "App Launcher" toggle exists and is OFF by default.
3. Open the menu bar dropdown — confirm there is NO "App Launcher..." item.
4. Open Settings > Shortcuts. Confirm "App Launcher" recorder row exists (always visible — only activation is gated).
5. Assign a hotkey to "App Launcher" (e.g. Cmd+Shift+L). Press it.
6. Expected: nothing happens (no bezel appears). The hotkey is registered but the feature-flag guard short-circuits.

**Test 2: Feature flag ON**
1. In Settings > General, toggle "App Launcher" ON.
2. Open the menu bar dropdown — confirm "App Launcher..." item now appears.
3. Click "App Launcher..." in the menu — the bezel must appear centered on the screen.
4. The bezel header should read "App Launcher". The TextField should be focused immediately (cursor blinking inside it).
5. The list area should briefly show "Scanning apps..." on first open, then populate with apps.
6. When the search field is empty, the list shows up to 5 recently launched apps (initially empty if you haven't launched anything yet via the bezel).
7. Close the bezel (Escape).

**Test 3: Hotkey invocation + non-activating panel (D-08)**
1. Click in another app (e.g. TextEdit, Safari) so it is frontmost. Note the active app.
2. Press the configured hotkey (Cmd+Shift+L).
3. The bezel must appear, but the previously frontmost app must REMAIN frontmost (its menu bar still shown, its window still active). Clipsmith itself must NOT become the active app.
4. Type "saf" — the list should filter live to apps containing those characters in order (Safari, etc.).

**Test 4: Launch + recency tracking (D-09, D-05)**
1. With the bezel open and search empty (or with a query), use arrow keys to select an app.
2. Press Enter.
3. Expected: bezel dismisses immediately. The selected app activates (becomes frontmost).
4. Re-open the bezel via hotkey. The just-launched app should appear in the recents (empty query view).
5. Launch 2 more distinct apps the same way. Confirm the recents list grows (in launch order, most recent first).
6. Type a query that matches both a recent and a non-recent app. Confirm the recent app ranks higher (the +0.1 boost).

**Test 5: Escape, click-outside, search behavior**
1. Open the bezel. Press Escape — bezel dismisses.
2. Open the bezel. Click outside the bezel — bezel dismisses.
3. Open the bezel. Type "qwerty" or some garbage that matches nothing. List should show "No matches".
4. Open the bezel and type immediately (the TextField must already be focused — no need to click it). The first keystroke should appear in the search field (D-03).

**Test 6: Feature flag dynamic toggle (no restart required)**
1. With bezel hidden, toggle the feature OFF in Settings > General.
2. Press the hotkey. Bezel must NOT appear.
3. Close the menu bar dropdown (if open) and reopen it — "App Launcher..." item must be gone.
4. Toggle back ON. Reopen menu — item returns. Press hotkey — bezel appears.

Report results as PASS/FAIL for each test (T1–T6) and any unexpected behavior.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Stub Tracking

No stubs introduced in this plan. All wiring is functional. The bezel itself (AppLaunchView, AppLaunchController, AppLaunchViewModel) was completed in Plan 02 and is now fully accessible.

## Threat Surface Scan

No new network endpoints or auth paths introduced. The `.clipsmithOpenAppLauncher` NotificationCenter path is process-local (T-11-01: accept). The hotkey handler calls only `appLaunchController.show()` — no app launch occurs at this point (T-11-02: mitigated, launch only via `launchSelected()` which uses scanner-provided URLs).

## Self-Check

- [x] `Clipsmith/Settings/KeyboardShortcutNames.swift` contains `static let appLauncher`
- [x] `Clipsmith/App/AppDelegate.swift` contains `var appLaunchController: AppLaunchController!`
- [x] `Clipsmith/App/AppDelegate.swift` contains `var appScannerService: AppScannerService!`
- [x] `Clipsmith/App/AppDelegate.swift` contains `appLaunchController = AppLaunchController()`
- [x] `Clipsmith/App/AppDelegate.swift` contains `AppSettingsKeys.appLauncherEnabled` (2 occurrences)
- [x] `Clipsmith/App/AppDelegate.swift` contains `KeyboardShortcuts.onKeyDown(for: .appLauncher)`
- [x] `Clipsmith/App/AppDelegate.swift` contains `name: .clipsmithOpenAppLauncher`
- [x] `Clipsmith/App/AppDelegate.swift` contains `@objc private func openAppLauncherFromMenu`
- [x] `Clipsmith/Views/MenuBarView.swift` contains `clipsmithOpenAppLauncher` (2 occurrences)
- [x] `Clipsmith/Views/MenuBarView.swift` contains `@AppStorage(AppSettingsKeys.appLauncherEnabled)`
- [x] `Clipsmith/Views/MenuBarView.swift` contains `if appLauncherEnabled`
- [x] `Clipsmith/Views/Settings/HotkeySettingsTab.swift` contains `name: .appLauncher`
- [x] `Clipsmith/Views/Settings/GeneralSettingsTab.swift` contains `@AppStorage(AppSettingsKeys.appLauncherEnabled)`
- [x] `Clipsmith/Views/Settings/GeneralSettingsTab.swift` contains `Toggle("App Launcher"`
- [x] Commit `fa3b1be` exists
- [x] `xcodebuild build` → BUILD SUCCEEDED
- [x] 193/193 tests pass (TEST SUCCEEDED)
- [x] Order check: `appLaunchController = AppLaunchController()` (line 181) before `name: .clipsmithOpenAppLauncher` (line 275)

## Self-Check: PASSED

---
*Phase: 11-app-launcher*
*Task 1 Completed: 2026-05-25*
*Task 2: checkpoint:pending — awaiting human verification*
