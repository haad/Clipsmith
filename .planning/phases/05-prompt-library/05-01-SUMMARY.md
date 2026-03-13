---
phase: 05-prompt-library
plan: "01"
subsystem: database
tags: [swiftdata, schema-migration, modelactor, swift-regex, prompt-library]

# Dependency graph
requires:
  - phase: 04-code-snippets-gist-sharing
    provides: "SnippetStore @ModelActor pattern, SnippetInfo Sendable struct, TestModelContainer, FlycutSchemaV1 with Clipping/Snippet/GistRecord models"

provides:
  - "FlycutSchemaV2 with PromptLibraryItem @Model (complete field set with sync metadata)"
  - "V1-to-V2 lightweight migration plan preserving all existing data"
  - "PromptLibraryStore @ModelActor with full CRUD + version-aware upsert + #category search"
  - "PromptInfo Sendable struct for cross-actor transfer"
  - "PromptDTO + PromptCatalog Decodable structs for JSON parsing"
  - "TemplateSubstitutor pure struct for {{variable}} substitution with extractVariables"
  - "Bundled prompts.json with 11 default prompts across 4 categories"
  - "AppSettingsKeys Phase 5 keys: promptLibraryURL, promptLibraryLastSync, promptLibraryVariables"

affects:
  - "05-02: PromptSyncService (uses PromptLibraryStore.upsert + PromptDTO)"
  - "05-03: Prompt bezel (uses PromptLibraryStore.search, TemplateSubstitutor)"
  - "05-04: Prompts tab (uses PromptLibraryStore @Query, PromptInfo)"
  - "05-05: Settings wiring (uses AppSettingsKeys Phase 5 additions)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FlycutSchemaV2 typealias pattern: re-export V1 models via typealias (Clipping/Snippet/GistRecord) so migration plan can reference all 4 models"
    - "PromptInfo Sendable struct mirrors SnippetInfo pattern for cross-actor transfer"
    - "TemplateSubstitutor uses computed var Regex (not static let) to avoid Swift 6 Sendable error on Regex type"
    - "Version-aware upsert: skip if isUserCustomized=true; skip if remote.version <= local; update otherwise; insert if not found"
    - "#category search syntax: strip # prefix, split on first space for category+text combined filter"

key-files:
  created:
    - "FlycutSwift/Models/Schema/FlycutSchemaV2.swift"
    - "FlycutSwift/Services/PromptLibraryStore.swift"
    - "FlycutSwift/Services/TemplateSubstitutor.swift"
    - "FlycutSwift/Resources/prompts.json"
    - "FlycutTests/SchemaMigrationTests.swift"
    - "FlycutTests/PromptLibraryStoreTests.swift"
    - "FlycutTests/TemplateSubstitutorTests.swift"
  modified:
    - "FlycutSwift/Models/Schema/FlycutMigrationPlan.swift"
    - "FlycutSwift/App/FlycutApp.swift"
    - "FlycutSwift/Settings/AppSettingsKeys.swift"
    - "FlycutTests/TestModelContainer.swift"
    - "FlycutSwift.xcodeproj/project.pbxproj"

key-decisions:
  - "[Phase 05-01]: FlycutSchemaV2 uses typealias to re-export V1 models — ensures migration plan lists all 4 models, prevents accidental data loss during lightweight migration"
  - "[Phase 05-01]: TemplateSubstitutor uses computed var Regex (not static let) — avoids Swift 6 Sendable error; Regex<(Substring, variable: Substring)> is not Sendable in Swift 6 strict concurrency mode"
  - "[Phase 05-01]: SchemaMigrationTests use await MainActor.run for SwiftData context access — container.mainContext is MainActor-isolated; pattern mirrors GistServiceTests"
  - "[Phase 05-01]: PromptLibraryStore upsert uses #Predicate { $0.id == remoteID } with captured local let — avoids SwiftData #Predicate capture limitation with parameter variables"

patterns-established:
  - "PromptInfo Sendable struct pattern (mirrors SnippetInfo): promptID slug field for stable identity across actor boundaries"
  - "TemplateSubstitutor.extractVariables returns ordered unique variable names for UI display"
  - "Version-aware upsert guard ordering: isUserCustomized first, then version comparison — user protection takes priority"

requirements-completed: [PMPT-01, PMPT-03, PMPT-04, PMPT-05, PMPT-07]

# Metrics
duration: 9min
completed: 2026-03-11
---

# Phase 5 Plan 01: Data Foundation Summary

**SwiftData V2 schema with PromptLibraryItem model, V1-to-V2 lightweight migration, PromptLibraryStore @ModelActor with version-aware sync upsert and #category search, TemplateSubstitutor for {{variable}} substitution, and bundled prompts.json for offline first launch**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-11T12:40:49Z
- **Completed:** 2026-03-11T12:50:26Z
- **Tasks:** 2
- **Files modified:** 12 (7 created, 5 modified)

## Accomplishments

- FlycutSchemaV2 with PromptLibraryItem @Model (10 fields: id slug, title, content, category, version, isUserCustomized, isUserCreated, sourceURL, createdAt, updatedAt) and #Index on category + title
- V1-to-V2 lightweight migration stage — adds PromptLibraryItem with no data transformation needed; all existing Clipping/Snippet/GistRecord data preserved
- PromptLibraryStore @ModelActor with full CRUD: insert, fetchAll, fetchByCategory, search (#category syntax), version-aware upsert, update (sets isUserCustomized), revertToOriginal, delete, content accessor, prompt(for:) returning PromptInfo
- TemplateSubstitutor pure struct with substitute(in:variables:) and extractVariables(from:) using Swift Regex literal /\{\{(?<variable>[^}]+)\}\}/
- Bundled prompts.json with 11 default prompts in 4 categories (coding 4, writing 3, analysis 2, creative 2) for offline first launch
- 31 new tests green (5 SchemaMigrationTests + 14 PromptLibraryStoreTests + 12 TemplateSubstitutorTests)

## Task Commits

Each task was committed atomically:

1. **Task 1: FlycutSchemaV2 + PromptLibraryItem + Migration + Bundled JSON + AppSettingsKeys** - `b8c22bf` (feat)
2. **Task 2: PromptLibraryStore + TemplateSubstitutor Unit Tests** - `052cc28` (test)

## Files Created/Modified

- `FlycutSwift/Models/Schema/FlycutSchemaV2.swift` - NEW: VersionedSchema V2 with PromptLibraryItem @Model and typealias for V1 models
- `FlycutSwift/Models/Schema/FlycutMigrationPlan.swift` - MODIFIED: added FlycutSchemaV2.self to schemas, added migrateV1toV2 lightweight stage
- `FlycutSwift/App/FlycutApp.swift` - MODIFIED: sharedModelContainer now uses FlycutSchemaV2.models
- `FlycutSwift/Settings/AppSettingsKeys.swift` - MODIFIED: added promptLibraryURL, promptLibraryLastSync, promptLibraryVariables keys
- `FlycutSwift/Resources/prompts.json` - NEW: 11 bundled default prompts across 4 categories
- `FlycutSwift/Services/PromptLibraryStore.swift` - NEW: @ModelActor store with PromptInfo Sendable struct, PromptDTO, PromptCatalog
- `FlycutSwift/Services/TemplateSubstitutor.swift` - NEW: pure struct with Swift Regex {{variable}} substitution
- `FlycutTests/TestModelContainer.swift` - MODIFIED: uses FlycutSchemaV2.models for all tests
- `FlycutTests/SchemaMigrationTests.swift` - NEW: 5 tests for schema model count, container creation, insert/fetch, defaults, V1 model compat
- `FlycutTests/PromptLibraryStoreTests.swift` - NEW: 14 tests covering full CRUD and version-aware upsert
- `FlycutTests/TemplateSubstitutorTests.swift` - NEW: 12 tests for substitution, unknown passthrough, whitespace trimming, extractVariables
- `FlycutSwift.xcodeproj/project.pbxproj` - MODIFIED: added all new files to Sources/Resources build phases and groups

## Decisions Made

- **FlycutSchemaV2 typealias pattern:** Re-exporting V1 models via typealias (Clipping/Snippet/GistRecord) ensures migration plan lists all 4 models and prevents accidental data loss during lightweight migration (Pitfall 4 avoidance)
- **TemplateSubstitutor uses computed var Regex:** `static var pattern: Regex<...> { /.../ }` avoids Swift 6 Sendable error — `Regex<(Substring, variable: Substring)>` is not Sendable in strict concurrency mode
- **SchemaMigrationTests use await MainActor.run:** container.mainContext is MainActor-isolated; pattern mirrors GistServiceTests for consistent V6 compliance
- **PromptLibraryStore upsert captures remoteID to local let before #Predicate:** Required by SwiftData #Predicate capture rules — cannot capture function parameters directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Swift 6 Sendable error on static Regex property**
- **Found during:** Task 1 (TemplateSubstitutor creation)
- **Issue:** `private static let pattern = /\{\{.../` causes Swift 6 error "static property is not concurrency-safe because non-Sendable type Regex<...>"
- **Fix:** Changed to computed `private static var pattern: Regex<...> { /.../ }` — returned by value each call, no shared mutable state
- **Files modified:** FlycutSwift/Services/TemplateSubstitutor.swift
- **Verification:** All 12 TemplateSubstitutorTests pass
- **Committed in:** b8c22bf (Task 1 commit)

**2. [Rule 1 - Bug] Fixed Swift 6 MainActor isolation in SchemaMigrationTests**
- **Found during:** Task 1 (SchemaMigrationTests creation)
- **Issue:** `container.mainContext` is MainActor-isolated; accessing from nonisolated test methods causes compile error
- **Fix:** Wrapped context access in `await MainActor.run { ... }` in async test methods
- **Files modified:** FlycutTests/SchemaMigrationTests.swift
- **Verification:** All 5 SchemaMigrationTests pass
- **Committed in:** b8c22bf (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 — Swift 6 bugs)
**Impact on plan:** Both auto-fixes required for Swift 6 strict concurrency compliance. No scope creep.

## Issues Encountered

- **Pre-existing test failure (PasteServiceTests.testPlainTextOnly):** This test was failing before Phase 5 work began. macOS 15 appends additional pasteboard types when NSPasteboard.setString is called. Not caused by schema migration. Logged to deferred-items.md.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- FlycutSchemaV2 with PromptLibraryItem is ready for Phase 5 Plan 02 (PromptSyncService)
- PromptLibraryStore.upsert(remote: PromptDTO) is the exact interface PromptSyncService needs
- TemplateSubstitutor is ready for use in the prompt bezel (Phase 5 Plan 03)
- TestModelContainer updated — all existing tests compile and pass with V2 schema
- Bundled prompts.json available for offline first launch in Phase 5 Plan 04 (settings + loading)

---
*Phase: 05-prompt-library*
*Completed: 2026-03-11*
