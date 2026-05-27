---
phase: 12
slug: launcher-command-palette-math-expression-evaluation-currency
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-26
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (native Xcode, existing) |
| **Config file** | `ClipsmithTests/` directory in Xcode project |
| **Quick run command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/ExpressionEvaluatorTests` |
| **Full suite command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run targeted test for the modified service (e.g., `-only-testing:ClipsmithTests/ExpressionEvaluatorTests`)
- **After every plan wave:** Run `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-T2 | 12-01 | 1 | D-04 | T-12-01 | Safe-chars regex rejects `NSExpression(format:)` injection | unit | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/ExpressionEvaluatorTests` | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-01-T2 | 12-01 | 1 | D-04/Pitfall 1 | — | `2^10` pre-processed → 1024 (not 8 from XOR) | unit | same | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-01-T2 | 12-01 | 1 | D-04/Pitfall 8 | — | Division by zero → nil (not inf or crash) | unit | same | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-01-T2 | 12-01 | 1 | D-05 | — | `sin(0.5)` pre-processed via `Foundation.sin()`; nested `sin(2+3)` → nil | unit | same | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-01-T2 | 12-01 | 1 | D-06 | — | `formatResult(42.0)` → `"42"`, `formatResult(3.14159)` → `"3.14159"` | unit | `xcodebuild test ... -only-testing:ClipsmithTests/CommandPaletteServiceTests` | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-02-T1 | 12-02 | 2 | D-07/D-08 | — | `"5 km to miles"` → 3.10686 | unit | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/UnitConversionServiceTests` | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-02-T1 | 12-02 | 2 | D-07/Pitfall 4 | — | `"100 C to F"` → 212.0 (no float drift) | unit | same | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-02-T2 | 12-02 | 2 | D-09/D-10 | T-12-03 | `CurrencyService.convert(10, "USD", "EUR")` → non-nil | unit | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/CurrencyServiceTests` | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-02-T2 | 12-02 | 2 | D-11 | — | Parser identifies `"10 USD to EUR"` as currency query | unit | same | ❌ W0 (12-01-T1) | ⬜ pending |
| 12-03-T2 | 12-03 | 3 | D-01/D-03 | — | `isCommandPaletteMode` true when `searchText = "=2+2"` | unit | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/AppLaunchViewModelTests` | ✅ extend | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ClipsmithTests/ExpressionEvaluatorTests.swift` — stubs for D-04, `^`→`**` pre-processing, division by zero
- [ ] `ClipsmithTests/UnitConversionServiceTests.swift` — stubs for D-07, D-08, temperature float drift (Pitfall 4)
- [ ] `ClipsmithTests/CurrencyServiceTests.swift` — stubs for D-09, D-11; uses bundled JSON fixture; URLSession mocked for D-10 download
- [ ] `ClipsmithTests/CommandPaletteServiceTests.swift` — stubs for D-06 result formatting and query dispatch

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Typing `=` only shows placeholder card (no crash) | D-01 | Requires live bezel UI | Open app launcher, type `=`, verify placeholder shows; delete `=`, verify app list returns |
| "Copied ✓" toast appears and auto-dismisses | D-13 | SwiftUI animation in NSPanel | Evaluate `=2+2`, press Enter, verify toast appears and disappears within ~1.5s |
| "Refresh rates" button shows spinner then timestamp | D-10 | Requires live network | Go to Settings > Features > Command Palette, click Refresh rates, verify spinner then "Last updated" timestamp |
| Prefix char field rejects >1 char and alphanumerics | D-02 | TextField input behavior | Settings > Features > Command Palette, try typing "ab", verify only 1 char accepted; try "a", verify rejected |
| Calculator results not added to clipboard history | Pitfall 6 | Requires live clipboard monitor | Evaluate `=2+2`, press Enter, open clipboard bezel, verify result not in history |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
