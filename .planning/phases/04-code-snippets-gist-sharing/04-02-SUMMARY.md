---
phase: 04-code-snippets-gist-sharing
plan: 02
subsystem: api
tags: [keychain, security-framework, urlsession, github-api, gist, swiftdata, tdd, swift6]

# Dependency graph
requires:
  - phase: 04-code-snippets-gist-sharing
    provides: FlycutSchemaV1.GistRecord model, Snippet model with tags field
provides:
  - TokenStore: Keychain wrapper for GitHub PAT save/load/delete
  - GistService: GitHub REST API client (POST/DELETE /gists) with GistRecord persistence
  - GistError enum: noToken, httpError, networkError
  - Language-to-extension map for 19 common languages
  - GistRecord clipboard copy (GIST-04)
affects: [04-03-snippets-ui, 04-04-gist-integration]

# Tech tracking
tech-stack:
  added: [Security.framework raw SecItem APIs, URLSession async/await, MockURLProtocol for testing]
  patterns:
    - nonisolated(unsafe) for test mock static state (Swift 6 compatible URLProtocol mock)
    - @MainActor on GistServiceTests class to access container.mainContext safely
    - nonisolated static for GistService.languageExtension and languageExtensions map
    - TokenStore with injectable service/account params for test isolation (distinct keychain keys)
    - deleteToken-before-saveToken pattern to avoid errSecDuplicateItem

key-files:
  created:
    - FlycutSwift/Services/TokenStore.swift
    - FlycutSwift/Services/GistService.swift
    - FlycutTests/TokenStoreTests.swift
    - FlycutTests/GistServiceTests.swift
  modified:
    - FlycutSwift/Models/Schema/FlycutSchemaV1.swift
    - FlycutSwift.xcodeproj/project.pbxproj

key-decisions:
  - "TokenStore accepts injectable service/account strings — production defaults, test-specific values for isolation; avoids polluting com.generalarcade.flycut.github-pat keychain in tests"
  - "GistService marked @MainActor @Observable — consistent with PasteService pattern; URLSession data(for:) is Sendable-clean in Swift 6 without @preconcurrency"
  - "GistService.languageExtension and languageExtensions marked nonisolated — pure computed from immutable data, no actor isolation needed; enables synchronous test calls without await"
  - "MockURLProtocol.requestHandler uses nonisolated(unsafe) — test-only global, single-threaded test execution; consistent with established project pattern for Swift 6 test globals"
  - "GistServiceTests class marked @MainActor — required to access container.mainContext (MainActor-isolated); eliminates need for MainActor.run call sites throughout test methods"
  - "deleteGist fetches GistRecord by PersistentIdentifier before API call — correct cross-actor pattern; @Model not Sendable so ID is passed at boundaries"
  - "Snippet.tags: [String] = [] added to FlycutSchemaV1 — required by SnippetStore (committed in 04-01); field has default value so no migration stage needed for V1 dev schema"

patterns-established:
  - "TokenStore: Sendable struct with injectable (service, account) — SecItemDelete+SecItemAdd idiom for overwrite safety"
  - "GistService: @MainActor @Observable with URLSession DI — MockURLProtocol intercepts test requests; no real network in tests"
  - "Test isolation via distinct keychain service strings — parallel test suites won't collide on Keychain entries"
  - "nonisolated static for pure language-map queries — avoids await overhead for a simple dictionary lookup"

requirements-completed: [GIST-01, GIST-02, GIST-03, GIST-04]

# Metrics
duration: 7min
completed: 2026-03-09
---

# Phase 4 Plan 2: TokenStore & GistService Summary

**Keychain PAT wrapper (TokenStore) and GitHub Gist REST client (GistService) with mocked URLSession TDD — 10 tests covering save/load/delete, HTTP 201/422, GistRecord persistence, and language extension map**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-09T19:54:36Z
- **Completed:** 2026-03-09T21:01:36Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- TokenStore wraps raw Security.framework SecItem APIs with injectable service/account for test isolation; 4 tests cover save/load/delete/overwrite round-trips
- GistService implements POST and DELETE /gists via URLSession async/await, copies URL to clipboard, persists GistRecord, with 6 tests using MockURLProtocol
- GistError enum provides noToken, httpError(Int), networkError(Error) with LocalizedError descriptions
- Language-to-extension map covers 19 common languages (swift, python, js, ts, etc.)
- All 10 new tests pass; full test suite of existing tests unaffected

## Task Commits

Both tasks were implemented in a single prior commit (04-01 agent pre-committed the files; this execution verified and confirmed passing):

1. **Task 1: TokenStore keychain wrapper** - `d59f6f4` (feat)
2. **Task 2: GistService API client** - `d59f6f4` (feat)

## Files Created/Modified

- `/Volumes/Devel/apple/Flycut/FlycutSwift/Services/TokenStore.swift` - Sendable struct wrapping SecItemAdd/SecItemCopyMatching/SecItemDelete for GitHub PAT
- `/Volumes/Devel/apple/Flycut/FlycutSwift/Services/GistService.swift` - @MainActor @Observable class: createGist, deleteGist, languageExtension, GistError, CreateGistRequest/GistResponse types
- `/Volumes/Devel/apple/Flycut/FlycutTests/TokenStoreTests.swift` - 4 keychain round-trip tests with test-scoped keychain service
- `/Volumes/Devel/apple/Flycut/FlycutTests/GistServiceTests.swift` - 6 tests with MockURLProtocol intercepting GitHub API calls
- `/Volumes/Devel/apple/Flycut/FlycutSwift/Models/Schema/FlycutSchemaV1.swift` - Added tags: [String] = [] to Snippet model
- `/Volumes/Devel/apple/Flycut/FlycutSwift.xcodeproj/project.pbxproj` - Added TokenStore, GistService, TokenStoreTests, GistServiceTests to build phases

## Decisions Made

- `TokenStore` accepts injectable `service`/`account` parameters with production defaults — enables test-scoped keychain entries that don't interfere with the production keychain
- `GistService` is `@MainActor @Observable` — matches established PasteService pattern; `@Observable` allows SwiftUI environment injection; `@MainActor` required because `ModelContext` is MainActor-isolated
- `languageExtension` and `languageExtensions` are `nonisolated` — pure functions over immutable data; can be called synchronously without `await` from any context
- `MockURLProtocol.requestHandler` uses `nonisolated(unsafe)` — test-only global accessed from a single test thread, same pattern as other test globals in this codebase
- `GistServiceTests` class annotated `@MainActor` — eliminates per-method `MainActor.run` boilerplate; `container.mainContext` access is valid throughout all test methods

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MockURLProtocol static handler Swift 6 concurrency**
- **Found during:** Task 2 (GistService tests compilation)
- **Issue:** `static var requestHandler` is shared mutable state — Swift 6 strict concurrency rejects it without isolation annotation
- **Fix:** Added `nonisolated(unsafe)` to `MockURLProtocol.requestHandler`; safe because tests run serially
- **Files modified:** FlycutTests/GistServiceTests.swift
- **Verification:** Build and tests pass with SWIFT_STRICT_CONCURRENCY=complete
- **Committed in:** d59f6f4

**2. [Rule 2 - Missing Critical] GistServiceTests Swift 6 actor isolation**
- **Found during:** Task 2 (GistService tests compilation)
- **Issue:** Test methods accessed `container.mainContext` (MainActor-isolated) and GistService init from non-MainActor context
- **Fix:** Annotated `GistServiceTests` class with `@MainActor`; simplified test methods to use `container.mainContext` directly without `MainActor.run` wrapping
- **Files modified:** FlycutTests/GistServiceTests.swift
- **Verification:** All 6 GistServiceTests pass; no data race warnings
- **Committed in:** d59f6f4

---

**Total deviations:** 2 auto-fixed (1 concurrency bug, 1 missing isolation annotation)
**Impact on plan:** Both fixes required for Swift 6 strict concurrency mode. No scope creep.

## Issues Encountered

None — Keychain tests pass in the non-sandboxed test bundle context. URLSession mocking via URLProtocol subclass works cleanly without third-party libraries.

## User Setup Required

None — no external service configuration required. GitHub PAT entry is deferred to the Settings UI (plan 04-04).

## Next Phase Readiness

- TokenStore and GistService ready for integration in plan 04-04 (Gist share action + Settings PAT entry)
- GistError enum provides user-facing error messages for noToken and httpError cases
- GistRecord persistence and clipboard copy (GIST-04) fully verified

---
*Phase: 04-code-snippets-gist-sharing*
*Completed: 2026-03-09*
