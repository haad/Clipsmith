---
phase: 02-core-engine
plan: 01
subsystem: testing
tags: [swiftdata, modelactor, xctest, swift6, tdd, clipboard]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: FlycutSchemaV1.Clipping @Model, ModelContainer setup, project structure
provides:
  - FlycutTests XCTest bundle target in project.pbxproj with TEST_HOST wired to FlycutSwift.app
  - makeTestContainer() in-memory ModelContainer helper for all test isolation
  - ClipboardStore @ModelActor with insert/fetchAll/content(for:)/delete(id:)/clearAll/trimToLimit
affects: [02-02-ClipboardMonitor, 02-03-PasteService, 02-04-MenuBarView, all future test files]

# Tech tracking
tech-stack:
  added: [XCTest (test bundle target), SwiftData ModelActor pattern]
  patterns: [TDD red-green cycle, @ModelActor background persistence, PersistentIdentifier cross-actor pattern]

key-files:
  created:
    - FlycutSwift/Services/ClipboardStore.swift
    - FlycutTests/TestModelContainer.swift
    - FlycutTests/ClipboardStoreTests.swift
  modified:
    - FlycutSwift.xcodeproj/project.pbxproj

key-decisions:
  - "@ModelActor used for ClipboardStore — macro auto-synthesizes modelExecutor and modelContainer init boilerplate, no nonisolated(unsafe) needed"
  - "fetchAll returns [PersistentIdentifier] not [@Model] objects — @Model is not Sendable, PersistentIdentifier is; this is the safe cross-actor pattern"
  - "trimToLimit fetches all and slices beyond rememberNum — simpler than deleteBatch, correct for small history sizes (< 1000 items)"
  - "GENERATE_INFOPLIST_FILE=YES on FlycutTests target — eliminates need for a hand-crafted test bundle Info.plist"

patterns-established:
  - "ClipboardStore pattern: @ModelActor insert/fetch/delete always saves explicitly via modelContext.save() after mutations"
  - "Test isolation: makeTestContainer() creates a fresh isStoredInMemoryOnly container per test — no shared state"
  - "Cross-actor safety: only PersistentIdentifier crosses actor boundary from ClipboardStore to callers"

requirements-completed: [CLIP-02, CLIP-03, CLIP-05, CLIP-07, CLIP-08]

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 2 Plan 01: ClipboardStore and Test Target Summary

**@ModelActor ClipboardStore with dedup/trim/delete/clearAll, backed by 7-test XCTest suite in a new FlycutTests bundle target using in-memory SwiftData isolation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T17:11:55Z
- **Completed:** 2026-03-05T17:14:49Z
- **Tasks:** 1 (TDD: red+green in single cycle)
- **Files modified:** 4

## Accomplishments

- FlycutTests XCTest target created in project.pbxproj — properly wired with TEST_HOST, BUNDLE_LOADER, GENERATE_INFOPLIST_FILE, Swift 6 strict concurrency, and PBXTargetDependency on FlycutSwift
- ClipboardStore @ModelActor delivers insert (dedup via fetchCount + trim), fetchAll (sorted newest-first), content(for:) (by PersistentIdentifier), delete(id:), clearAll, and private trimToLimit — zero Swift 6 warnings
- makeTestContainer() provides per-test in-memory ModelContainer isolation via isStoredInMemoryOnly=true
- All 7 unit tests pass: testInsertAndFetch, testDuplicateSkipped, testTrimToLimit, testPersistenceRoundTrip, testClearAll, testDeleteOne, testFetchOrdering

## Task Commits

Each task was committed atomically:

1. **Task 1: Create FlycutTests target and ClipboardStore with TDD** - `346416f` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `FlycutSwift/Services/ClipboardStore.swift` — @ModelActor background persistence actor for all clipboard history operations
- `FlycutTests/TestModelContainer.swift` — makeTestContainer() helper providing in-memory SwiftData isolation for tests
- `FlycutTests/ClipboardStoreTests.swift` — 7 XCTest cases covering all ClipboardStore operations
- `FlycutSwift.xcodeproj/project.pbxproj` — Added FlycutTests bundle target (TT0002), all new file references, build phases, build configurations (XC0005/XC0006), and PBXTargetDependency

## Decisions Made

- `@ModelActor` used instead of manually managing a background `ModelContext` — macro synthesizes the executor, no boilerplate needed
- `fetchAll` returns `[PersistentIdentifier]` not `[FlycutSchemaV1.Clipping]` — `@Model` objects are not `Sendable` and cannot cross actor boundaries in Swift 6
- `GENERATE_INFOPLIST_FILE = YES` added to FlycutTests build settings — Xcode auto-generates the required bundle Info.plist, no manual file needed
- Tests use `await store.method()` pattern via Swift async/await naturally calling into the actor — no explicit `Task {}` wrapping needed in tests

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added GENERATE_INFOPLIST_FILE=YES to FlycutTests build settings**
- **Found during:** Task 1 (first test run attempt)
- **Issue:** FlycutTests build failed with "Cannot code sign because the target does not have an Info.plist file" — the plan did not specify this setting
- **Fix:** Added `GENERATE_INFOPLIST_FILE = YES` to both Debug (XC0005) and Release (XC0006) build configurations for FlycutTests
- **Files modified:** FlycutSwift.xcodeproj/project.pbxproj
- **Verification:** xcodebuild test succeeded after fix
- **Committed in:** 346416f (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 — blocking build configuration issue)
**Impact on plan:** Required for test bundle to build and sign. No scope creep.

## Issues Encountered

None beyond the auto-fixed GENERATE_INFOPLIST_FILE setting above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ClipboardStore is the persistence backbone Phase 2 plans 02 and 03 depend on
- Test infrastructure is now in place — new test files can be added to FlycutTests target by referencing `makeTestContainer()`
- ClipboardMonitor (02-02) can call `await store.insert(content:rememberNum:)` directly via Task hop from @MainActor

## Self-Check: PASSED

- ClipboardStore.swift: FOUND
- TestModelContainer.swift: FOUND
- ClipboardStoreTests.swift: FOUND
- 02-01-SUMMARY.md: FOUND
- Commit 346416f: FOUND

---
*Phase: 02-core-engine*
*Completed: 2026-03-05*
