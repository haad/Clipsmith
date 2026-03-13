---
phase: 5
slug: prompt-library
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-10
updated: 2026-03-11
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in, target: FlycutTests) |
| **Config file** | GENERATE_INFOPLIST_FILE=YES (set in Phase 2) |
| **Quick run command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing:FlycutTests/PromptLibraryStoreTests -only-testing:FlycutTests/TemplateSubstitutorTests 2>&1 \| grep -E "passed\|failed\|error"` |
| **Full suite command** | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' 2>&1 \| tail -20` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests -only-testing:FlycutTests/TemplateSubstitutorTests`
- **After every plan wave:** Run `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' 2>&1 | tail -20`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | Migration | unit | `xcodebuild test -only-testing:FlycutTests/SchemaMigrationTests` | W0 | pending |
| 05-01-02 | 01 | 1 | PMPT-01 | unit | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests` | W0 | pending |
| 05-01-03 | 01 | 1 | PMPT-03, PMPT-07 | unit | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests/testUpsertVersioning` | W0 | pending |
| 05-01-04 | 01 | 1 | PMPT-05 | unit | `xcodebuild test -only-testing:FlycutTests/TemplateSubstitutorTests` | W0 | pending |
| 05-01-05 | 01 | 2 | PMPT-04 | unit | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests/testForkToSnippet` | W0 | pending |
| 05-01-06 | 01 | 2 | PMPT-02 | manual | UI visual inspection | N/A | pending |
| 05-02-* | 02 | 2 | PMPT-01, PMPT-03 | regression | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests -only-testing:FlycutTests/TemplateSubstitutorTests` | Plan 01 | pending |
| 05-03-* | 03 | 2 | PMPT-02, PMPT-05, PMPT-06 | regression | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests -only-testing:FlycutTests/TemplateSubstitutorTests` | Plan 01 | pending |
| 05-04-* | 04 | 3 | PMPT-02, PMPT-04 | regression | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests -only-testing:FlycutTests/TemplateSubstitutorTests` | Plan 01 | pending |
| 05-05-01 | 05 | 4 | PMPT-01, PMPT-06 | build+test | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'` | N/A | pending |
| 05-05-02 | 05 | 4 | All | manual | Full flow human verification | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `FlycutTests/PromptLibraryStoreTests.swift` — stubs for PMPT-03, PMPT-04, PMPT-07
- [ ] `FlycutTests/TemplateSubstitutorTests.swift` — stubs for PMPT-05
- [ ] `FlycutTests/SchemaMigrationTests.swift` — stubs for V1->V2 migration
- [ ] Update `FlycutTests/TestModelContainer.swift` — change to `Schema(FlycutSchemaV2.models)`

**Removed:** `PromptSyncServiceTests.swift` — architecture changed from disk-read sync to HTTP URLSession fetch; PromptSyncService is a thin @Observable wrapper around URLSession + store.upsert() calls, tested implicitly via PromptLibraryStoreTests (upsert logic) and integration testing (Plan 05-05 human verify).

**Deferred:** `PromptPasteTests.swift` for PMPT-06 end-to-end substitute-then-paste — would require mocking PasteService and NSPasteboard; covered by TemplateSubstitutorTests (substitution logic) + Plan 05-05 human verification (end-to-end flow).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Library prompts visually distinct from user snippets | PMPT-02 | Visual styling (SF Symbol, foreground color) | 1. Open snippet window 2. Switch to Prompts tab 3. Verify book.fill icon and secondary foreground style on library items |
| Category cycling in bezel | PMPT-02 | UI interaction | 1. Open prompt bezel 2. Press Tab repeatedly 3. Verify category cycles through all categories |
| End-to-end prompt paste flow | PMPT-06 | Requires running app + clipboard + frontmost app | 1. Copy text 2. Open prompt bezel 3. Select prompt with {{clipboard}} 4. Press Enter 5. Verify pasted content has substitution |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
