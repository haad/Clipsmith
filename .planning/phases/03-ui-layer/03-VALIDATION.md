---
phase: 3
slug: ui-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest — `FlycutTests` target (created in Phase 2) |
| **Config file** | None — uses Xcode project scheme |
| **Quick run command** | `xcodebuild build -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS"` |
| **Full suite command** | `xcodebuild test -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS" 2>&1 \| xcpretty` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS"`
- **After every plan wave:** Run `xcodebuild test -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS" 2>&1 | xcpretty`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 0 | BEZL-03 | unit | `xcodebuild test -only-testing FlycutTests/BezelControllerTests/testCenterOnMouseScreen` | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 0 | BEZL-04 | unit | `xcodebuild test -only-testing FlycutTests/BezelControllerTests/testCollectionBehavior` | ❌ W0 | ⬜ pending |
| 3-01-03 | 01 | 0 | BEZL-05 | unit | `xcodebuild test -only-testing FlycutTests/BezelControllerTests/testHideRemovesMonitor` | ❌ W0 | ⬜ pending |
| 3-01-04 | 01 | 0 | BEZL-02 | unit | `xcodebuild test -only-testing FlycutTests/BezelViewModelTests/testSelectedIndexMapsToClipping` | ❌ W0 | ⬜ pending |
| 3-01-05 | 01 | 0 | INTR-02 | unit | `xcodebuild test -only-testing FlycutTests/BezelViewModelTests/testNavigation` | ❌ W0 | ⬜ pending |
| 3-01-06 | 01 | 0 | INTR-04 | unit | `xcodebuild test -only-testing FlycutTests/BezelViewModelTests/testSearchFilter` | ❌ W0 | ⬜ pending |
| 3-xx-xx | xx | x | BEZL-01 | manual | Build verify — panel instantiation with correct styleMask | ✅ build | ⬜ pending |
| 3-xx-xx | xx | x | SHELL-02 | manual | Open menu bar, verify clipping list with preview text | ✅ exists | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `FlycutTests/BezelControllerTests.swift` — stubs for BEZL-03 (centering), BEZL-04 (collectionBehavior), BEZL-05 (hide/monitor cleanup)
- [ ] `FlycutTests/BezelViewModelTests.swift` — stubs for BEZL-02 (selectedIndex), INTR-02 (navigation), INTR-04 (search filter)

*BezelViewModel is a pure-Swift view model extracted from BezelView for testability.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Bezel shows without activating app | BEZL-01 | Requires window server + human observation | 1. Open TextEdit, 2. Press hotkey, 3. Verify bezel appears and TextEdit stays frontmost |
| Bezel appears over fullscreen app | BEZL-04 | Requires fullscreen app + window server | 1. Enter fullscreen in any app, 2. Press hotkey, 3. Verify bezel appears above fullscreen |
| Click-outside dismisses bezel | BEZL-05 | Global event monitors cannot be unit-tested | 1. Show bezel, 2. Click outside, 3. Verify bezel dismisses |
| Menu bar shows clippings | SHELL-02 | Already complete from Phase 2 | 1. Open menu bar dropdown, 2. Verify clipping list with preview text |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
