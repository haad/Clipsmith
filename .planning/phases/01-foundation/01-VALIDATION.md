---
phase: 1
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in with Xcode) |
| **Config file** | FlycutTests target in Flycut.xcodeproj |
| **Quick run command** | `xcodebuild test -scheme Flycut -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -scheme Flycut -destination 'platform=macOS'` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme Flycut -destination 'platform=macOS'`
- **After every plan wave:** Run `xcodebuild test -scheme Flycut -destination 'platform=macOS'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | SHELL-01 | manual | N/A — verify menu bar icon visible, no dock icon | N/A | ⬜ pending |
| 1-01-02 | 01 | 1 | SHELL-04 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | SHELL-03 | manual | N/A — verify launch at login toggle works | N/A | ⬜ pending |
| 1-02-02 | 02 | 1 | SETT-01 | manual | N/A — verify hotkey recorder captures shortcuts | N/A | ⬜ pending |
| 1-02-03 | 02 | 1 | SETT-02 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| 1-02-04 | 02 | 1 | SETT-03 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| 1-02-05 | 02 | 1 | SETT-04 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| 1-02-06 | 02 | 1 | SETT-05 | manual | N/A — verify SwiftUI Settings scene opens | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `FlycutTests/AccessibilityCheckerTests.swift` — stubs for SHELL-04
- [ ] `FlycutTests/AppSettingsTests.swift` — stubs for SETT-02, SETT-03, SETT-04
- [ ] XCTest target configured in new Swift project

*Note: Many Phase 1 requirements involve UI and system integration that require manual verification.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Menu bar icon visible, no dock icon | SHELL-01 | Requires running app, visual check | Launch app → verify status bar icon → verify no dock icon |
| Launch at login toggle | SHELL-03 | Requires system-level SMAppService | Toggle in prefs → log out/in → verify app launches |
| Accessibility permission prompt | SHELL-04 | Requires system permission dialog | Fresh install → launch → verify prompt appears |
| Hotkey recorder captures shortcuts | SETT-01 | Requires KeyboardShortcuts UI interaction | Open prefs → click recorder → press key combo → verify display |
| Settings window opens | SETT-05 | Requires SwiftUI Settings scene lifecycle | Click menu bar → select Preferences → verify window appears |
| Settings persist across restart | SETT-02-05 | Requires app restart cycle | Change settings → quit app → relaunch → verify values retained |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
