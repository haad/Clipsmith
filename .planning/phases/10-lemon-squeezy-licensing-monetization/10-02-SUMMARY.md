---
phase: 10-lemon-squeezy-licensing-monetization
plan: 02
subsystem: ui
tags: [swiftui, nspanel, appkit, licensing, lemonsqueezy, monetization]

requires:
  - phase: 10-lemon-squeezy-licensing-monetization plan 01
    provides: LicenseService with activate/validate/deactivate, LicenseError, AppSettingsKeys for license, shouldShowNag()

provides:
  - LicenseNagController: activating NSPanel nag dialog shown on launch for unlicensed users
  - LicenseNagView: SwiftUI nag UI with Sponsor/Buy/HaveKey CTAs
  - LicenseSettingsSection: Settings tab for license key entry and licensed state display
  - SettingsTab enum + @AppStorage("selectedSettingsTab") programmatic tab navigation
  - AppDelegate wiring: licenseService init, background validate, nag gating, notification handler
  - LICENSE (PolyForm Noncommercial 1.0.0) and .github/FUNDING.yml

affects:
  - Any future phase that adds Settings tabs (must increment SettingsTab enum and .tag values)
  - AppDelegate (phase 10 properties and launch wiring added)

tech-stack:
  added: []
  patterns:
    - LicenseNagController uses activating NSPanel (.titled | .closable) — contrast with bezel's .nonactivatingPanel
    - SettingsTab Int enum + @AppStorage selection binding enables programmatic Settings tab navigation from AppDelegate
    - handleOpenLicenseSettings writes UserDefaults BEFORE sendAction showSettingsWindow so SettingsView reads correct tab on appear

key-files:
  created:
    - Clipsmith/Views/LicenseNagController.swift
    - Clipsmith/Views/LicenseNagView.swift
    - Clipsmith/Views/Settings/LicenseSettingsSection.swift
    - LICENSE
    - .github/FUNDING.yml
  modified:
    - Clipsmith/Views/SettingsView.swift
    - Clipsmith/Views/MenuBarView.swift
    - Clipsmith/App/AppDelegate.swift
    - Clipsmith.xcodeproj/project.pbxproj

key-decisions:
  - "SettingsTab Int enum defined at file scope above SettingsView — AppDelegate references SettingsTab.license.rawValue directly (no @testable import needed)"
  - "handleOpenLicenseSettings writes selectedSettingsTab to UserDefaults BEFORE showSettingsWindow — SettingsView reads @AppStorage value on appear, so tab must be set before window opens"
  - "LicenseNagController is NSObject+NSWindowDelegate (not NSPanel subclass) — panel is a private stored property; cleaner ownership than BezelController's self-is-panel pattern"
  - "LicenseSettingsSection uses local @State LicenseService — same pattern as DocsetSettingsSection; settings manages its own lifecycle"

patterns-established:
  - "Programmatic Settings tab navigation: write UserDefaults key before sendAction showSettingsWindow"
  - "Activating NSPanel for dialogs: .titled|.closable styleMask, level = .floating, restore .accessory in windowWillClose"

requirements-completed: [LIC-07, LIC-08, LIC-09, LIC-10, LIC-11]

duration: 5min
completed: 2026-03-20
---

# Phase 10 Plan 02: Licensing UI and AppDelegate Wiring Summary

**Activating nag dialog + License Settings tab + AppDelegate wiring completing full Lemon Squeezy licensing integration with PolyForm Noncommercial license**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-20T15:16:58Z
- **Completed:** 2026-03-20T15:21:45Z
- **Tasks:** 2 (+ 1 auto-approved human-verify checkpoint)
- **Files modified:** 8

## Accomplishments

- LicenseNagController activating NSPanel shows on launch for unlicensed users (30-day gate), with restore of .accessory policy on close
- LicenseSettingsSection Settings tab with unlicensed/validating/error/licensed states wired to LicenseService
- SettingsView gained SettingsTab enum + @AppStorage("selectedSettingsTab") + .tag() on all tabs, enabling programmatic navigation from AppDelegate
- AppDelegate wires licenseService (init + background validate), licenseNagController (launch nag), and handleOpenLicenseSettings handler
- LICENSE (PolyForm Noncommercial 1.0.0) and .github/FUNDING.yml added

## Task Commits

1. **Task 1: LicenseNagController, LicenseNagView, LicenseSettingsSection, notification wiring** - `9916081` (feat)
2. **Task 2: AppDelegate wiring, LICENSE, FUNDING.yml** - `ea9c6e8` (feat)
3. **Task 3: Human verify** - auto-approved (auto_advance: true)

## Files Created/Modified

- `Clipsmith/Views/LicenseNagController.swift` - Activating NSPanel controller for nag dialog, restores .accessory on close
- `Clipsmith/Views/LicenseNagView.swift` - SwiftUI nag view: scissors icon, title, Sponsor/Buy/HaveKey buttons
- `Clipsmith/Views/Settings/LicenseSettingsSection.swift` - License key entry form + licensed state display
- `Clipsmith/Views/SettingsView.swift` - Added SettingsTab enum, @AppStorage selection binding, .tag() on all tabs, License tab
- `Clipsmith/Views/MenuBarView.swift` - Added .clipsmithOpenLicenseSettings notification name
- `Clipsmith/App/AppDelegate.swift` - Phase 10 properties, init, background validate, nag gating, observer + handler
- `LICENSE` - PolyForm Noncommercial 1.0.0
- `.github/FUNDING.yml` - github: haad + Lemon Squeezy store link

## Decisions Made

- SettingsTab enum defined at file scope (not nested) so AppDelegate can reference `SettingsTab.license.rawValue` without @testable import
- `handleOpenLicenseSettings` writes UserDefaults BEFORE calling `showSettingsWindow:` — SettingsView @AppStorage reads the value on appear, so the key must be set before the window opens
- LicenseNagController is `NSObject + NSWindowDelegate` holding a private `NSPanel`, not an NSPanel subclass — cleaner ownership; panel is entirely managed by the controller

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.
The Lemon Squeezy store URL and product/store IDs have TODO placeholders that must be replaced before shipping.

## Next Phase Readiness

- Complete licensing integration is ready for end-to-end testing
- `LicenseService.expectedStoreId` and `expectedProductId` are 0 (TODO) — must be set to real values before shipping
- Purchase URL has TODO-product-slug placeholder — must be updated in both LicenseNagController and LicenseSettingsSection before shipping

---
*Phase: 10-lemon-squeezy-licensing-monetization*
*Completed: 2026-03-20*

## Self-Check: PASSED

- FOUND: Clipsmith/Views/LicenseNagController.swift
- FOUND: Clipsmith/Views/LicenseNagView.swift
- FOUND: Clipsmith/Views/Settings/LicenseSettingsSection.swift
- FOUND: LICENSE
- FOUND: .github/FUNDING.yml
- FOUND: commit 9916081 (Task 1)
- FOUND: commit ea9c6e8 (Task 2)
