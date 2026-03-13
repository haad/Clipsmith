---
phase: 04-code-snippets-gist-sharing
plan: "01"
subsystem: snippet-store
tags: [swiftdata, modelactor, tdd, snippet, crud]
dependency_graph:
  requires: []
  provides: [SnippetStore, SnippetInfo, FlycutSchemaV1.Snippet.tags]
  affects: [FlycutSchemaV1, FlycutTests]
tech_stack:
  added: []
  patterns: [ModelActor, PersistentIdentifier, Sendable-struct, in-memory-tag-filter]
key_files:
  created:
    - FlycutSwift/Services/SnippetStore.swift
    - FlycutTests/SnippetStoreTests.swift
  modified:
    - FlycutSwift/Models/Schema/FlycutSchemaV1.swift
    - FlycutSwift.xcodeproj/project.pbxproj
    - FlycutTests/GistServiceTests.swift
decisions:
  - tags:[String] added to Snippet model alongside category (backward compat); SwiftData serializes [String] natively
  - Tag search uses in-memory filter (post-SQL) because #Predicate does not support [String].contains()
  - SnippetInfo Sendable struct transfers data across actor boundaries (mirrors ClippingInfo pattern)
  - GistServiceTests Swift 6 MainActor isolation fixed inline (pre-existing blocker, Rule 3)
metrics:
  duration: "6 min"
  completed_date: "2026-03-09"
  tasks_completed: 1
  files_modified: 5
requirements_satisfied: [SNIP-01, SNIP-03, SNIP-04]
---

# Phase 4 Plan 1: SnippetStore Backend Service Summary

**One-liner:** SnippetStore @ModelActor with full CRUD, language filter, multi-field search (name/content/tags), and SnippetInfo Sendable struct — 10 tests green.

## What Was Built

### FlycutSchemaV1.Snippet — tags field added

Added `var tags: [String] = []` to the existing Snippet @Model. The `category: String?` field is retained for backward compatibility (no migration needed — new field with default value is additive in SwiftData).

The Snippet `init()` accepts an optional `tags: [String] = []` parameter.

### SnippetStore (@ModelActor)

A new `@ModelActor actor SnippetStore` mirrors the ClipboardStore pattern:

| Method | Signature | Notes |
|--------|-----------|-------|
| `insert` | `(name:content:language:tags:) throws` | Saves immediately (PITFALL 3) |
| `fetchAll` | `() throws -> [PersistentIdentifier]` | Sorted by updatedAt descending |
| `fetchByLanguage` | `(_ language:) throws -> [PersistentIdentifier]` | #Predicate equality filter |
| `search` | `(query:) throws -> [PersistentIdentifier]` | name+content via #Predicate; tags in-memory |
| `update` | `(id:name:content:language:tags:) throws` | Refreshes updatedAt |
| `delete` | `(id:) throws` | modelContext.delete + save |
| `content(for:)` | `-> String?` | Direct @Model access |
| `snippet(for:)` | `-> SnippetInfo?` | Returns Sendable value copy |

### SnippetInfo (Sendable struct)

```swift
struct SnippetInfo: Sendable, Identifiable {
    let id: PersistentIdentifier
    let name: String
    let content: String
    let language: String?
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
}
```

### SnippetStoreTests (10 tests)

| Test | Behavior Covered |
|------|-----------------|
| `testInsertAndFetch` | Insert + retrieve all fields including tags |
| `testFetchByLanguage` | Language filter returns only matching snippets |
| `testSearchByName` | Name substring search |
| `testSearchByContent` | Content substring search |
| `testSearchByTag` | Tag match (in-memory filter) |
| `testSearchEmptyQueryReturnsAll` | Empty query returns all |
| `testUpdate` | Update all fields + updatedAt refresh |
| `testDelete` | Delete by PersistentIdentifier |
| `testFetchAllSortedByUpdatedAtDescending` | Most recent first ordering |
| `testContentAccessor` | content(for:) accessor |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed GistServiceTests Swift 6 MainActor isolation errors**
- **Found during:** Build phase (before tests could run)
- **Issue:** GistServiceTests.swift (pre-existing) used `container.mainContext` from non-`@MainActor` context and called `@MainActor`-isolated `languageExtension` from sync context — 16 compiler errors
- **Fix:** Wrapped all `container.mainContext` accesses in `MainActor.run { }`, made `GistService.languageExtension` `nonisolated static`, used `nonisolated(unsafe)` on `MockURLProtocol.requestHandler`
- **Files modified:** `FlycutTests/GistServiceTests.swift`
- **Commit:** d59f6f4

**2. [Rule 3 - Blocking] Added SnippetStore.swift and SnippetStoreTests.swift to Xcode project file**
- **Found during:** Build phase
- **Issue:** New Swift files are not auto-discovered by Xcode — project.pbxproj must explicitly reference them
- **Fix:** Added PBXBuildFile, PBXFileReference entries (AF0036/AF0037), added to group children and Sources build phases
- **Files modified:** `FlycutSwift.xcodeproj/project.pbxproj`
- **Commit:** d59f6f4

## Self-Check: PASSED

- SnippetStore.swift: FOUND
- SnippetStoreTests.swift: FOUND
- tags field in FlycutSchemaV1.Snippet: FOUND
- Commit d59f6f4: FOUND
- All 10 SnippetStoreTests: PASSED
- Full test suite: PASSED
