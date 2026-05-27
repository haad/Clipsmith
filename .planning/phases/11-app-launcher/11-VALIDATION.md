---
phase: 11
slug: app-launcher
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-25
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (existing project setup) |
| **Config file** | `Clipsmith.xcodeproj` (no separate test config) |
| **Quick run command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/AppLaunchViewModelTests -only-testing:ClipsmithTests/AppScannerServiceTests` |
| **Full suite command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command above
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | AppScannerService scan | — | Only whitelisted paths scanned | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | Bundle name extraction | — | N/A | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 1 | Deduplication by bundle ID | — | N/A | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | ❌ W0 | ⬜ pending |
| 11-01-04 | 01 | 1 | recordLaunch (UserDefaults) | — | N/A | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppScannerServiceTests` | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 2 | Fuzzy filtering | — | N/A | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 2 | Recency boost ranking | — | N/A | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | ❌ W0 | ⬜ pending |
| 11-02-03 | 02 | 2 | Recent apps when no query | — | N/A | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | ❌ W0 | ⬜ pending |
| 11-03-01 | 03 | 3 | Bezel show/hide panel | — | N/A | manual | N/A | manual | ⬜ pending |
| 11-03-02 | 03 | 3 | Feature flag guard | — | N/A | manual | N/A | manual | ⬜ pending |
| 11-03-03 | 03 | 3 | App launches via NSWorkspace | — | URLs from scanner only | manual | N/A | manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ClipsmithTests/AppScannerServiceTests.swift` — stubs for scan, dedup, bundle name extraction, recordLaunch
- [ ] `ClipsmithTests/AppLaunchViewModelTests.swift` — stubs for fuzzy filter, recency boost, navigation, empty-query recent apps

*Existing test infrastructure (XCTest target already configured) covers all other phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| AppLaunchController shows/hides bezel panel | D-08 | NSPanel behavior requires UI; no headless testing | Press hotkey, verify bezel appears centered on screen without stealing focus |
| Feature flag guard prevents show when disabled | D-10 | Requires real AppDelegate + UserDefaults state | Set appLauncherEnabled=false in Settings, press hotkey, verify nothing appears |
| Pressing Enter launches app and dismisses bezel | D-09 | Requires NSWorkspace interaction with live system | Select an app in the bezel, press Enter, verify app launches and bezel dismisses |
| Search field focused on bezel open | D-03 | Focus state requires real NSPanel key status | Open bezel, type immediately, verify characters appear in search field |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
