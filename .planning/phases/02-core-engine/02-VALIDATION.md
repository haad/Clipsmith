---
phase: 2
slug: core-engine
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-05
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

**Note:** Wave 0 test infrastructure (XCTest target, TestModelContainer, all test files) is embedded in Plan 02-01 Task 1 using a TDD approach: tests are written RED before implementation, then turned GREEN. No separate Wave 0 plan is required — the TDD task creates the test target and all test scaffolding as its first step.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest — created in Plan 02-01 Task 1 (TDD step 1) |
| **Config file** | None — Plan 02-01 creates FlycutTests target |
| **Quick run command** | `xcodebuild test -scheme FlycutSwift -destination "platform=macOS" -only-testing FlycutTests 2>&1 \| xcpretty` |
| **Full suite command** | `xcodebuild test -scheme FlycutSwift -destination "platform=macOS" 2>&1 \| xcpretty` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme FlycutSwift -destination "platform=macOS"` (build green)
- **After every plan wave:** Run `xcodebuild test -scheme FlycutSwift -destination "platform=macOS" 2>&1 | xcpretty`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | CLIP-02 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testTrimToLimit` | Created in 02-01 | ⬜ pending |
| 02-01-02 | 01 | 1 | CLIP-03 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testDuplicateSkipped` | Created in 02-01 | ⬜ pending |
| 02-01-03 | 01 | 1 | CLIP-05 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testPersistenceRoundTrip` | Created in 02-01 | ⬜ pending |
| 02-01-04 | 01 | 1 | CLIP-07 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testClearAll` | Created in 02-01 | ⬜ pending |
| 02-01-05 | 01 | 1 | CLIP-08 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testDeleteOne` | Created in 02-01 | ⬜ pending |
| 02-02-01 | 02 | 2 | CLIP-01 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardMonitorTests/testShouldNotSkipNormalText` | Created in 02-02 | ⬜ pending |
| 02-02-02 | 02 | 2 | CLIP-04 | unit | `xcodebuild test -only-testing FlycutTests/ClipboardMonitorTests/testShouldSkipTransientType` | Created in 02-02 | ⬜ pending |
| 02-02-03 | 02 | 2 | CLIP-06 | unit | `xcodebuild test -only-testing FlycutTests/PasteServiceTests/testPlainTextOnly` | Created in 02-02 | ⬜ pending |
| 02-03-01 | 03 | 3 | CLIP-08 | manual | Right-click clipping in menu, select Delete — single clipping removed | N/A (UI) | ⬜ pending |
| 02-03-02 | 03 | 3 | INTR-01 | manual | Press configured hotkey, verify callback fires | N/A (HW) | ⬜ pending |
| 02-03-03 | 03 | 3 | INTR-03 | manual | Open TextEdit, activate Flycut, paste — verify text appears | N/A (HW) | ⬜ pending |
| 02-03-04 | 03 | 3 | INTR-05 | manual | Press search hotkey, verify callback fires | N/A (HW) | ⬜ pending |

*Status: ⬜ pending / ✅ green / ❌ red / ⚠️ flaky*

---

## Wave 0 Requirements

All Wave 0 items are created within Plan 02-01 Task 1 (TDD approach — tests written RED before implementation):

- [x] `FlycutTests/` test target — created in Plan 02-01 Task 1 Step 1
- [x] `FlycutTests/TestModelContainer.swift` — in-memory `ModelContainer(for: FlycutSchemaV1.models, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])` for test isolation — created in Plan 02-01 Task 1 Step 2
- [x] `FlycutTests/ClipboardStoreTests.swift` — covers CLIP-02, CLIP-03, CLIP-05, CLIP-07, CLIP-08 — created in Plan 02-01 Task 1 Step 4
- [x] `FlycutTests/ClipboardMonitorTests.swift` — covers CLIP-01, CLIP-04 — created in Plan 02-02 Task 1
- [x] `FlycutTests/PasteServiceTests.swift` — covers CLIP-06 (verify pasteboard types after paste write) — created in Plan 02-02 Task 2

*Wave 0 is embedded in implementation plans via TDD; no separate Wave 0 plan needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Global bezel hotkey activates | INTR-01 | Requires real macOS window server; XCTest cannot simulate global hotkeys | Press configured hotkey, verify callback fires in console |
| Paste into previous app | INTR-03 | Cross-app CGEventPost requires window server and real app activation | Open TextEdit, copy text via Flycut, paste — verify text appears in TextEdit |
| Search hotkey activates | INTR-05 | Requires real macOS window server | Press search hotkey, verify callback fires in console |
| Delete individual clipping from menu | CLIP-08 | UI interaction: right-click context menu in MenuBarExtra | Right-click a clipping, select Delete, verify it is removed from list |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (embedded in Plan 02-01 TDD)
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
