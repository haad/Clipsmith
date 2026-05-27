---
phase: 10
slug: lemon-squeezy-licensing-monetization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via xcodebuild |
| **Config file** | Clipsmith.xcodeproj |
| **Quick run command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/LicenseServiceTests` |
| **Full suite command** | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | LicenseService | unit | `xcodebuild test -only-testing:ClipsmithTests/LicenseServiceTests` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | Nag dialog | manual | N/A | N/A | ⬜ pending |
| 10-02-01 | 02 | 2 | Settings UI | manual | N/A | N/A | ⬜ pending |
| 10-02-02 | 02 | 2 | License validation | unit | `xcodebuild test -only-testing:ClipsmithTests/LicenseServiceTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ClipsmithTests/LicenseServiceTests.swift` — stubs for license activation, validation, deactivation
- [ ] MockURLProtocol reuse from existing GistServiceTests

*Existing test infrastructure covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Nag dialog appearance | Startup dialog | UI timing + window management | Launch app, verify dialog shows after delay, dismiss, verify 30-day suppression |
| Settings license key entry | License UI | Interactive UI flow | Open Settings > License, enter key, verify validation feedback |
| GitHub Sponsors link | FUNDING.yml | External service | Visit repo on GitHub, verify Sponsor button appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
