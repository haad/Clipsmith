---
phase: 6
slug: quick-actions-performance
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (existing in FlycutTests target) |
| **Config file** | FlycutSwift.xcodeproj (existing test target) |
| **Quick run command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/TextTransformerTests -only-testing FlycutTests/ClipboardExportServiceTests` |
| **Full suite command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/TextTransformerTests -only-testing FlycutTests/ClipboardExportServiceTests`
- **After every plan wave:** Run `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 6-01-T1 | 01 | 1 | QACT-01, QACT-02 | unit (TDD) | `xcodebuild test ... -only-testing FlycutTests/TextTransformerTests` | ❌ created in task | ⬜ pending |
| 6-01-T2 | 01 | 1 | PERF-01 | unit (TDD) | `xcodebuild test ... -only-testing FlycutTests/ClipboardExportServiceTests` | ❌ created in task | ⬜ pending |
| 6-02-T1 | 02 | 2 | QACT-01, QACT-02, QACT-03 | regression | `xcodebuild test ... -only-testing FlycutTests/TextTransformerTests` | ✅ from 06-01 | ⬜ pending |
| 6-02-T2 | 02 | 2 | PERF-02 | unit (TDD) | `xcodebuild test ... -only-testing FlycutTests/ClipboardMonitorTests` | ✅ (new methods added) | ⬜ pending |
| 6-03-T1 | 03 | 2 | PERF-01 | build | `xcodebuild build ...` | N/A | ⬜ pending |
| 6-03-T2 | 03 | 2 | ALL | manual | checkpoint:human-verify | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `FlycutTests/TextTransformerTests.swift` — stubs for QACT-01, QACT-02, QACT-03 (RTF)
- [ ] `FlycutTests/ClipboardExportServiceTests.swift` — stubs for PERF-01 export/import round-trip
- [ ] New test methods in `FlycutTests/ClipboardMonitorTests.swift` — adaptive polling stubs (PERF-02)

*Existing infrastructure covers framework and config; only new test files needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Right-click menu appears on bezel item | QACT-01 | NSMenu in non-activating NSPanel requires UI interaction | 1. Open bezel 2. Right-click an item 3. Verify menu appears with transform/format/share submenus |
| Gist share opens browser | QACT-03 | Requires GitHub API + browser launch | 1. Select clip 2. Right-click > Share > Create Gist 3. Verify browser opens with gist URL |
| CPU usage drops in idle | PERF-02 | Requires Activity Monitor observation | 1. Leave Flycut idle 30s 2. Check CPU in Activity Monitor 3. Verify < 0.5% usage |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
