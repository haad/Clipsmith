---
phase: 8
slug: documentation-lookup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in) |
| **Config file** | Clipsmith.xcodeproj |
| **Quick run command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests` |
| **Full suite command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick test command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | DOCS-01 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| 08-01-02 | 01 | 1 | DOCS-02 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| 08-01-03 | 01 | 1 | DOCS-03 | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Test stubs for DOCS-01, DOCS-02, DOCS-03
- [ ] Shared fixtures for docset test data

*Existing XCTest infrastructure covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Hotkey triggers doc lookup popup | DOCS-01 | Requires system hotkey + UI interaction | 1. Select text in any app 2. Press doc-lookup hotkey 3. Verify popup appears with results |
| Docset download and extraction | DOCS-02 | Requires network + file system | 1. Open Settings 2. Download a docset 3. Verify it appears in search |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
