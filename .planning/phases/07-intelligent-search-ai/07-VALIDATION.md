---
phase: 7
slug: intelligent-search-ai
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (existing in FlycutTests target) |
| **Config file** | FlycutSwift.xcodeproj (existing test target) |
| **Quick run command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/FuzzyMatcherTests -only-testing FlycutTests/BezelViewModelTests` |
| **Full suite command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/FuzzyMatcherTests -only-testing FlycutTests/BezelViewModelTests`
- **After every plan wave:** Run `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | SRCH-01 | unit | `xcodebuild test ... -only-testing FlycutTests/FuzzyMatcherTests` | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | SRCH-01 | unit | `xcodebuild test ... -only-testing FlycutTests/BezelViewModelTests` | ✅ | ⬜ pending |
| 07-01-03 | 01 | 1 | SRCH-01 | unit | `xcodebuild test ... -only-testing FlycutTests/BezelViewModelTests` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `FlycutTests/FuzzyMatcherTests.swift` — stubs for SRCH-01 algorithm correctness (jsonpar → JSON.parse, scoring, nil returns)
- [ ] `FlycutSwift/Services/FuzzyMatcher.swift` — new pure-Swift character-subsequence scorer (~80 lines)
- [ ] New test methods in `FlycutTests/BezelViewModelTests.swift` — fuzzy filtering and ranking

*Existing infrastructure: XCTest target, `makeTestContainer()`, `makeClippingInfos()` — all reusable*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual ranking in bezel | SRCH-01 | UI rendering verification | 1. Open bezel 2. Type "jsonpar" 3. Verify JSON.parse appears first |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
