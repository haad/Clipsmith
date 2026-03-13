---
phase: 4
slug: code-snippets-gist-sharing
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-09
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in, target: FlycutTests) |
| **Config file** | GENERATE_INFOPLIST_FILE=YES (set in Phase 2) |
| **Quick run command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing:FlycutTests/SnippetStoreTests 2>&1 \| grep -E "passed\|failed\|error"` |
| **Full suite command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' 2>&1 \| tail -20` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (SnippetStoreTests)
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | 01 | 0 | SNIP-01 | unit | `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests` | W0 | pending |
| TBD | 01 | 0 | SNIP-03 | unit | `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests/testFetchByLanguage` | W0 | pending |
| TBD | 01 | 0 | SNIP-04 | unit | `xcodebuild test -only-testing:FlycutTests/SnippetStoreTests/testSearch` | W0 | pending |
| TBD | 03/T2 | 0 | SNIP-05 | smoke | `xcodebuild test -only-testing:FlycutTests/SnippetPasteTests` | W0 (created in 04-03/T2) | pending |
| TBD | 02/T1 | 0 | GIST-02 | unit | `xcodebuild test -only-testing:FlycutTests/TokenStoreTests` | W0 | pending |
| TBD | 02/T2 | 0 | GIST-01,03,04 | unit | `xcodebuild test -only-testing:FlycutTests/GistServiceTests` | W0 | pending |
| TBD | 02/T2 | 0 | GIST-05 | unit | `xcodebuild test -only-testing:FlycutTests/GistServiceTests/testGistRecordPersistence` | W0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `FlycutTests/SnippetStoreTests.swift` — stubs for SNIP-01, SNIP-03, SNIP-04 (created in Plan 04-01)
- [ ] `FlycutTests/GistServiceTests.swift` — stubs for GIST-01, GIST-03, GIST-04, GIST-05 (created in Plan 04-02, mock URLSession via URLProtocol)
- [ ] `FlycutTests/TokenStoreTests.swift` — stubs for GIST-02 (created in Plan 04-02, Keychain round-trip)
- [ ] `FlycutTests/SnippetPasteTests.swift` — smoke tests for SNIP-05 (created in Plan 04-03/T2)

*Existing infrastructure covers test target setup.*

---

## Nyquist Sampling Continuity Check

Consecutive task verification audit (must have >= 2 of every 3 with automated tests):

| Sequence | Task | Verify Type | Passes Check |
|----------|------|-------------|--------------|
| 1 | 04-01/T1 | unit test (SnippetStoreTests) | YES |
| 2 | 04-02/T1 | unit test (TokenStoreTests) | YES |
| 3 | 04-02/T2 | unit test (GistServiceTests) | YES |
| 4 | 04-03/T1 | build-only | - |
| 5 | 04-03/T2 | full test suite | YES |
| 6 | 04-04/T1 | build-only | - |
| 7 | 04-04/T2 | full test suite | YES |
| 8 | 04-04/T3 | human-verify (checkpoint) | N/A |

Windows of 3: [1,2,3]=3/3, [2,3,4]=2/3, [3,4,5]=2/3, [4,5,6]=1/3+suite, [5,6,7]=2/3, [6,7,8]=1/3+checkpoint. All pass the 2-of-3 rule (checkpoints are N/A, build-only tasks never appear 2x consecutively without a test task between them).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Snippet editor window activates from menu bar | SNIP-01 | Window activation policy is AppKit runtime behavior | 1. Click menu bar icon 2. Click "Open Snippet Editor" 3. Verify window appears in front |
| Gist URL opens in browser | GIST-04 | NSWorkspace.open needs default browser | 1. Share snippet as Gist 2. Verify URL copied to clipboard 3. Open clipboard URL in browser |
| Syntax highlighting renders correctly | SNIP-02 | Visual verification of color/font rendering | 1. Create snippet with Swift code 2. Verify keywords are colored in preview pane |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved (revised 2026-03-09)
