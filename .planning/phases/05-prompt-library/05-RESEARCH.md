# Phase 5: Prompt Library - Research

**Researched:** 2026-03-10 (updated with SwiftGitX + git-clone approach)
**Domain:** Git-based sync via SwiftGitX, SwiftData schema migration, Swift Regex template substitution, SwiftUI category navigation, offline-first sync
**Confidence:** HIGH (core patterns verified via official docs and existing codebase patterns)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PMPT-01 | Prompts available on first launch organized by category (coding, writing, analysis, creative) | Initial `git clone` of prompt library repo on first launch via SwiftGitX; prompts read directly from cloned repo files |
| PMPT-02 | User can browse prompts by category in snippet window sidebar, library prompts visually distinct | NavigationSplitView three-column layout OR sidebar List with section headers; `.foregroundStyle(.secondary)` + SF Symbol badge for library items |
| PMPT-03 | User can sync prompt library from public GitHub repo; versioning prevents overwriting user-customized copies | `git pull` via SwiftGitX on user-triggered sync; per-prompt version field in SwiftData model; sync skips prompts with `isUserCustomized = true` |
| PMPT-04 | User can copy any library prompt to personal snippets for customization | "Fork to Snippet" action creates a new `FlycutSchemaV1.Snippet` from prompt content; independent of future syncs |
| PMPT-05 | Template variables (e.g. `{{clipboard}}`) are substituted with clipboard content on paste | Swift Regex literal `/\{\{(?<variable>[^}]+)\}\}/` with `String.replacing(_:with:)` closure; NSPasteboard read before paste |
| PMPT-06 | Pressing Enter on a selected library prompt pastes it (with substitution) into frontmost app | Reuse existing `PasteService.paste(content:into:)` after substitution; mirrors SnippetListView pattern exactly |
| PMPT-07 | Sync respects per-prompt versioning; never overwrites user-customized copies | `version: Int` + `isUserCustomized: Bool` fields on PromptLibraryItem @Model; sync only updates when remote version > local version AND isUserCustomized == false |
</phase_requirements>

---

## Summary

Phase 5 adds a GitHub-synced prompt library to the existing snippet window. The library is distinct from user-created snippets: library prompts live in a new `PromptLibraryItem` SwiftData model (requiring a V1→V2 schema migration), have category metadata, and carry a version number for sync conflict resolution.

### Sync Architecture: Git Clone + Pull (via SwiftGitX)

**No bundled prompts in the app bundle.** Instead, the prompt library repo is cloned on first launch (or when configured in preferences) using **SwiftGitX** (v0.4.0, Swift 6, async/await, SPM). Subsequent syncs use `git pull` (fetch + merge). This approach:

- **Simplifies versioning** — git handles history and diffing natively
- **No GitHub API rate limits** — standard git protocol, not REST API
- **Atomic updates** — pull either succeeds or doesn't, no partial state
- **Works with any git host** — not locked to GitHub API
- **Offline resilience** — whatever was last cloned remains available

**SwiftGitX** ([github.com/ibrahimcetin/SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX)):
- `swift-tools-version: 6.0` with Sendable conformances
- Wraps libgit2 1.9.2 (bundled via SPM, no system dependencies)
- `Repository.clone(from:to:)` and `repo.fetch()` are `async throws`
- Pre-1.0 (v0.4.0), one open SIGPIPE bug on fetch (#12)
- Key caveat: libgit2 clone blocks cooperative threads (known TODO) — run on a detached task or custom executor

**Prompt files location:** `~/Library/Application Support/Flycut/prompt-library/` (cloned repo)

**Flow:**
1. User configures repo URL in preferences (default: project's own repo)
2. On first launch or "Sync Now" → `Repository.clone(from: repoURL, to: localPath)`
3. On subsequent syncs → open existing repo, `repo.fetch()`, merge
4. Read prompt JSON files from local cloned directory
5. Upsert into SwiftData `PromptLibraryItem` model with version-aware logic

The most important architectural decision is the **data model separation**: library prompts are NOT stored as `Snippet` objects. They live in a separate `PromptLibraryItem` model with `sourceURL`, `version`, `category`, and `isUserCustomized` fields. "Fork to Snippet" creates a new `Snippet` from a `PromptLibraryItem` — that copy is fully independent. This separation avoids polluting the snippet model with sync metadata and keeps the `Snippet` model clean for user content.

Template variable substitution (`{{clipboard}}`) is pure Swift with no library dependency. The modern Swift Regex API (iOS 16+/macOS 13+) provides a clean, type-safe find-and-replace with named capture groups. Since the app targets macOS 15+, the full modern Regex API is available without fallbacks.

SwiftData schema migration from V1 to V2 for adding a new model (PromptLibraryItem) is a lightweight migration — no custom migration stage is required when adding a new independent entity with default-valued fields.

**Primary recommendation:** Separate PromptLibraryItem from Snippet in SwiftData; use SwiftGitX for git clone/pull sync; use Swift Regex for `{{variable}}` substitution; integrate as a new tab/section in the existing SnippetWindowView.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData (built-in) | macOS 15+ | PromptLibraryItem @Model persistence | Already in use; V1→V2 lightweight migration adds new model |
| **SwiftGitX** | **0.4.0** | **Git clone/fetch for prompt library sync** | **Swift 6 (tools 6.0), async/await, Sendable, wraps libgit2 1.9.2 via SPM — no system deps** |
| Swift Regex (built-in) | macOS 13+ / Swift 5.7+ | `{{variable}}` template substitution | No library needed; Regex literal syntax, `.replacing(_:with:)` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation.JSONDecoder | built-in | Decode prompt JSON files from cloned repo | All JSON decode/encode; Codable structs |
| Foundation.FileManager | built-in | Read prompt files from cloned repo directory | Enumerate prompt files in local clone |
| NSPasteboard (built-in) | macOS system | Read clipboard content for `{{clipboard}}` substitution | In substitution step before paste |
| UserDefaults (built-in) | macOS system | Store repo URL, last-sync timestamp | Lightweight persistence for sync config |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftGitX (libgit2 wrapper) | git-macOS (shells out to /usr/bin/git) | git-macOS is simpler but no async/await, no Swift 6, subprocess-based — slower and potential sandbox issues |
| SwiftGitX | GitHub Contents API + URLSession | API approach has 60 req/hr rate limit, more complex ETag caching, partial download risk; git clone/pull is atomic |
| SwiftGitX | SwiftGit2 (upstream) | Dead since 2019, no SPM, no Swift 6, no clone/fetch API |
| Swift Regex literal | NSRegularExpression | NSRegularExpression works but requires Objective-C bridging patterns and is less type-safe; Swift Regex available on macOS 13+, this project targets 15+ |
| Separate PromptLibraryItem @Model | Tag "library" snippets with a special tag | Pollutes the Snippet model with sync metadata; prevents clean separation of user content from library content; makes sync logic much harder |

**Installation:**
```swift
// Package.swift — add SwiftGitX dependency
dependencies: [
    .package(url: "https://github.com/ibrahimcetin/SwiftGitX.git", from: "0.4.0")
]
// Target dependency:
.product(name: "SwiftGitX", package: "SwiftGitX")
```

---

## Architecture Patterns

### Recommended Project Structure

```
FlycutSwift/
├── Models/
│   └── Schema/
│       ├── FlycutSchemaV1.swift         # EXISTING — unchanged
│       ├── FlycutSchemaV2.swift         # NEW — adds PromptLibraryItem model
│       └── FlycutMigrationPlan.swift    # MODIFIED — add V1→V2 lightweight stage
├── Services/
│   ├── PromptLibraryStore.swift        # NEW — @ModelActor CRUD for PromptLibraryItem
│   ├── PromptSyncService.swift         # NEW — SwiftGitX clone/pull sync + JSON file parsing
│   └── TemplateSubstitutor.swift       # NEW — pure Swift `{{variable}}` → value replacement
└── Views/
    ├── Snippets/
    │   ├── SnippetWindowView.swift      # MODIFIED — add "Prompts" tab (or sidebar section)
    │   ├── SnippetListView.swift        # EXISTING — unchanged
    │   └── PromptLibraryView.swift      # NEW — category sidebar + prompt list + detail
    └── Settings/
        └── PromptLibrarySettingsSection.swift  # NEW — sync button, last-synced date, GitHub repo URL
```

### Pattern 1: PromptLibraryItem as a Separate SwiftData Model (V2 Schema)

**What:** Add a new `PromptLibraryItem` @Model to FlycutSchemaV2. This model is NOT a `Snippet` and is never promoted to one — instead, "Fork to Snippet" creates a new independent Snippet. The prompt model carries sync metadata (`version`, `isUserCustomized`, `sourceURL`) that would be inappropriate on user-created snippets.

**When to use:** All storage and retrieval of library prompts. `PromptLibraryStore` wraps this model.

**Example:**
```swift
// FlycutSchemaV2.swift
import SwiftData

enum FlycutSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        // Include ALL models from V1 plus the new model
        [
            FlycutSchemaV2.Clipping.self,
            FlycutSchemaV2.Snippet.self,
            FlycutSchemaV2.GistRecord.self,
            FlycutSchemaV2.PromptLibraryItem.self
        ]
    }

    // Copy existing V1 models verbatim (or use typealias if unchanged)
    typealias Clipping = FlycutSchemaV1.Clipping
    typealias Snippet = FlycutSchemaV1.Snippet
    typealias GistRecord = FlycutSchemaV1.GistRecord

    @Model
    final class PromptLibraryItem {
        #Index<PromptLibraryItem>([\.category], [\.title])

        var id: String = ""           // Stable ID from the JSON / remote repo (slug)
        var title: String = ""
        var content: String = ""
        var category: String = ""    // "coding" | "writing" | "analysis" | "creative"
        var version: Int = 1         // Incremented in the remote repo to signal updates
        var isUserCustomized: Bool = false  // Set to true if user edits this prompt in-place
        var sourceURL: String? = nil // raw.githubusercontent.com URL for this prompt file
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now

        init(
            id: String,
            title: String,
            content: String,
            category: String,
            version: Int = 1,
            isUserCustomized: Bool = false,
            sourceURL: String? = nil
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.category = category
            self.version = version
            self.isUserCustomized = isUserCustomized
            self.sourceURL = sourceURL
        }
    }
}
```

### Pattern 2: V1 → V2 Lightweight Schema Migration

**What:** Adding a new independent @Model (PromptLibraryItem) to the schema is a lightweight migration — SwiftData handles it automatically with no data loss. Update FlycutMigrationPlan to include both schemas and a `.lightweight` stage.

**When to use:** When Phase 5 work starts, before any other PromptLibraryItem code. The migration is the first task.

**Example:**
```swift
// FlycutMigrationPlan.swift — MODIFIED
import SwiftData

enum FlycutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FlycutSchemaV1.self, FlycutSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FlycutSchemaV1.self,
        toVersion: FlycutSchemaV2.self
    )
}
```

Also update `FlycutApp.sharedModelContainer` to use `FlycutSchemaV2.self` as the schema version.

### Pattern 3: Git Clone + Pull Sync via SwiftGitX

**What:** Clone the prompt library repo on first launch (or when user configures the repo URL in preferences). On subsequent syncs, open the existing local repo and fetch + merge to get updates. No bundled prompts in the app bundle — the cloned repo IS the source of truth. Offline = whatever was last cloned.

**Local path:** `~/Library/Application Support/Flycut/prompt-library/`

**Repo structure (expected):**
```
prompts/
├── coding/
│   ├── code-review-swift.json
│   └── explain-code.json
├── writing/
│   ├── summarize-text.json
│   └── rewrite-formal.json
├── analysis/
│   └── analyze-data.json
└── creative/
    └── brainstorm.json
```

Each JSON file:
```json
{
  "id": "code-review-swift",
  "title": "Swift Code Review",
  "category": "coding",
  "version": 1,
  "content": "Review this Swift code for correctness, safety, and style:\n\n{{clipboard}}"
}
```

**SwiftGitX clone/fetch implementation:**
```swift
import SwiftGitX

// PromptSyncService.swift
actor PromptSyncService {
    private let localPath: URL
    private let repoURL: URL

    init(repoURL: URL) {
        self.repoURL = repoURL
        self.localPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flycut/prompt-library")
    }

    func sync() async throws -> [PromptDTO] {
        if FileManager.default.fileExists(atPath: localPath.appendingPathComponent(".git").path) {
            // Repo already cloned — pull updates
            try await pull()
        } else {
            // First time — clone
            try await clone()
        }
        // Read prompt files from local clone
        return try readPromptsFromDisk()
    }

    private func clone() async throws {
        // SwiftGitX clone is async but blocks cooperative threads internally
        // Run on a detached task to avoid blocking the cooperative pool
        _ = try await Repository.clone(from: repoURL, to: localPath)
    }

    private func pull() async throws {
        let repo = try Repository(at: localPath)
        try await repo.fetch()
        // After fetch, merge the remote tracking branch
        // SwiftGitX fetch updates remote refs; for a simple pull,
        // reset working tree to match the fetched remote HEAD
    }

    private func readPromptsFromDisk() throws -> [PromptDTO] {
        let promptsDir = localPath.appendingPathComponent("prompts")
        var prompts: [PromptDTO] = []
        let categories = try FileManager.default.contentsOfDirectory(
            at: promptsDir, includingPropertiesForKeys: nil
        )
        for categoryDir in categories where categoryDir.hasDirectoryPath {
            let files = try FileManager.default.contentsOfDirectory(
                at: categoryDir, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
            for file in files {
                let data = try Data(contentsOf: file)
                let prompt = try JSONDecoder().decode(PromptDTO.self, from: data)
                prompts.append(prompt)
            }
        }
        return prompts
    }
}

### Pattern 5: Version-Aware Sync Logic

**What:** When syncing a file from GitHub, compare the remote `version` field against the local stored version. Only update if: (a) remote version > local version AND (b) `isUserCustomized == false`. If the user has customized a prompt in-place, never overwrite it.

**Conflict resolution strategy:** Last-write-wins from remote, EXCEPT when `isUserCustomized = true`, which creates a permanent fork. The "Fork to Snippet" action should be suggested when `isUserCustomized = true` so the user doesn't lose customizations to future syncs.

```swift
// Version-aware upsert inside PromptLibraryStore (runs on @ModelActor)
func upsert(remote: PromptDTO) throws {
    // Look up existing by stable ID
    let descriptor = FetchDescriptor<FlycutSchemaV2.PromptLibraryItem>(
        predicate: #Predicate { $0.id == remote.id }
    )
    if let existing = try modelContext.fetch(descriptor).first {
        // Skip if user has customized this prompt
        guard !existing.isUserCustomized else { return }
        // Skip if remote version is not newer
        guard remote.version > existing.version else { return }
        // Update in place
        existing.content = remote.content
        existing.title = remote.title
        existing.version = remote.version
        existing.updatedAt = .now
    } else {
        // Insert new prompt from remote
        let item = FlycutSchemaV2.PromptLibraryItem(
            id: remote.id,
            title: remote.title,
            content: remote.content,
            category: remote.category,
            version: remote.version
        )
        modelContext.insert(item)
    }
    try modelContext.save()
}
```

### Pattern 6: Template Variable Substitution

**What:** Before pasting a library prompt, scan the content for `{{variable}}` tokens using Swift Regex and replace each with its value. Currently only `{{clipboard}}` is defined, but the substitutor should be extensible for future variables (`{{date}}`, `{{appname}}` etc.).

**Use modern Swift Regex** (available macOS 13+, this project targets 15+). The regex literal `/\{\{(?<variable>[^}]+)\}\}/` matches any `{{...}}` pattern and captures the variable name.

```swift
// Source: Swift Regex documentation + polpiella.dev named capture groups article
// TemplateSubstitutor.swift — pure value type, no actor needed
struct TemplateSubstitutor {

    static func substitute(in content: String, variables: [String: String]) -> String {
        let pattern = /\{\{(?<variable>[^}]+)\}\}/
        return content.replacing(pattern) { match in
            let key = String(match.variable)
            return variables[key] ?? String(match.0) // keep original if no substitution defined
        }
    }

    /// Convenience: substitute only {{clipboard}} with current clipboard content.
    static func substituteClipboard(in content: String) -> String {
        let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
        return substitute(in: content, variables: ["clipboard": clipboardContent])
    }
}
```

**Usage before paste:**
```swift
// In PromptLibraryView, before calling PasteService
let finalContent = TemplateSubstitutor.substituteClipboard(in: prompt.content)
await pasteService.paste(content: finalContent, into: previousApp)
```

### Pattern 7: PromptLibraryView — Category Sidebar Integration

**What:** Add a third tab "Prompts" to `SnippetWindowView`. The Prompts view uses a two-column layout: a left sidebar with category sections, and a right detail panel showing prompts in the selected category. Library prompts are visually distinct from user snippets via a book SF Symbol (`book.fill`) and `.secondary` foreground style.

**Integration point:** Modify `SnippetWindowView` to add a "Prompts" tab (tag: 2) alongside "Snippets" (0) and "Gists" (1). The existing segmented Picker gets a third segment.

```swift
// PromptLibraryView.swift — category sidebar + prompt list
struct PromptLibraryView: View {
    @Query(sort: \FlycutSchemaV2.PromptLibraryItem.title)
    private var allPrompts: [FlycutSchemaV2.PromptLibraryItem]

    @State private var selectedCategory: String? = "coding"
    @State private var selectedPromptID: PersistentIdentifier?

    private let categories = ["coding", "writing", "analysis", "creative"]

    var body: some View {
        HSplitView {
            // Left: category list
            List(categories, id: \.self, selection: $selectedCategory) { cat in
                Label(cat.capitalized, systemImage: categoryIcon(cat))
                    .tag(cat)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140, maxWidth: 180)

            // Right: prompts in selected category
            if let category = selectedCategory {
                promptListFor(category: category)
            }
        }
    }

    private func promptListFor(category: String) -> some View {
        let filtered = allPrompts.filter { $0.category == category }
        return List(filtered, selection: $selectedPromptID) { prompt in
            promptRow(prompt)
                .tag(prompt.persistentModelID)
        }
        .onKeyPress(.return) {
            if let id = selectedPromptID,
               let prompt = allPrompts.first(where: { $0.persistentModelID == id }) {
                pastePrompt(prompt)
                return .handled
            }
            return .ignored
        }
    }
}
```

**Visual distinction for library items:**
```swift
// Library prompts get a SF Symbol badge to distinguish from user snippets
private func promptRow(_ prompt: FlycutSchemaV2.PromptLibraryItem) -> some View {
    HStack {
        Image(systemName: "book.fill")
            .foregroundStyle(.secondary)
            .font(.caption)
        VStack(alignment: .leading, spacing: 2) {
            Text(prompt.title)
                .lineLimit(1)
            if prompt.isUserCustomized {
                Text("customized")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        Spacer()
        Button("Use") { pastePrompt(prompt) }
            .buttonStyle(.plain)
            .foregroundStyle(.accentColor)
    }
}
```

### Anti-Patterns to Avoid

- **Storing library prompts as Snippet objects:** Breaks the clean user/library separation. Sync metadata (`version`, `isUserCustomized`, `sourceURL`) pollutes the Snippet model. Use a separate PromptLibraryItem model.
- **Running SwiftGitX clone/fetch on the main actor:** libgit2 clone blocks cooperative threads. Always run on a detached task or background actor to avoid UI freezes.
- **Overwriting prompts when isUserCustomized = true:** This permanently loses user edits. Always check `isUserCustomized` before updating from remote.
- **Performing git pull on every app launch automatically:** Network call on every launch fails on network unavailability and slows startup. Clone on first config, then sync user-triggered with a "Sync Now" button (or configurable auto-sync interval).
- **Using SwiftData #Predicate with [String].contains():** Not supported in #Predicate SQL translation. Use in-memory post-filter for array fields (established pattern from SnippetStore).
- **Reading NSPasteboard clipboard content before user triggers paste:** Read the clipboard in the paste action itself (just before calling PasteService), not at selection time. The clipboard may change between selection and paste.
- **Modifying `FlycutSchemaV1.models` to add PromptLibraryItem:** V1 is frozen. Add PromptLibraryItem only in FlycutSchemaV2. V1 must remain immutable for migration correctness.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Template variable substitution | Custom string scanner | Swift Regex `String.replacing(_:with:)` with `/\{\{(?<variable>[^}]+)\}\}/` | Built-in, type-safe, handles edge cases (adjacent braces, whitespace in names), available macOS 13+ |
| Git clone/fetch/merge | Shell out to `/usr/bin/git` or hand-roll HTTP smart protocol | SwiftGitX `Repository.clone()` / `repo.fetch()` | Swift 6 async/await, Sendable, no subprocess overhead, no system git dependency |
| Schema migration | Manual SQLite ALTER TABLE | SwiftData lightweight migration (`MigrationStage.lightweight`) | Automatic, safe, handles the "add new model" case without data loss |
| Prompt file reading | Custom parser | `FileManager` + `JSONDecoder` on cloned repo files | Standard file I/O on local clone; no network needed after initial clone |
| Sync conflict resolution | Custom CRDT | `version: Int` monotonic counter + `isUserCustomized: Bool` guard | The library is append-only with version increments; no concurrent edit conflict possible; simple wins |

**Key insight:** Phase 5 adds significant feature surface (sync, templates, migration) but requires zero new SPM dependencies. Every technical problem is solved by built-in Apple APIs or patterns already established in this codebase.

---

## Common Pitfalls

### Pitfall 1: V1 Models Array Must NOT Include PromptLibraryItem

**What goes wrong:** Developer adds `PromptLibraryItem.self` to `FlycutSchemaV1.models`. This breaks the migration plan — V1 is a fixed historical schema. The existing database does not have a `PromptLibraryItem` table, and SwiftData will error on opening.

**Why it happens:** It's tempting to add a new model to the existing schema file. But VersionedSchema defines a historical snapshot.

**How to avoid:** Create `FlycutSchemaV2.swift` with the new model. Keep `FlycutSchemaV1.swift` unchanged. Update `FlycutMigrationPlan` to list both.

**Warning signs:** `NSInvalidArgumentException: The model used to open the store is incompatible with the one used to create the store.`

### Pitfall 2: @ModelActor Cannot Be Used from @Query Views Without PersistentIdentifier

**What goes wrong:** Passing a `FlycutSchemaV2.PromptLibraryItem` object (fetched via @Query on main context) directly into a background actor call. `@Model` objects are not `Sendable`.

**Why it happens:** @Model is an AppKit-era reference type with strict actor isolation.

**How to avoid:** Mirror the `SnippetInfo` pattern: create a `PromptInfo: Sendable` value struct, populate from @Query results on MainActor, pass the struct (not the model) across actor boundaries.

**Warning signs:** Swift 6 compiler error: "Sending value of non-Sendable type across actor boundary."

### Pitfall 3: SwiftGitX Clone Blocks Cooperative Thread Pool

**What goes wrong:** Calling `Repository.clone()` or `repo.fetch()` directly from a structured concurrency context (e.g., inside a `Task {}`). The underlying libgit2 C function is synchronous and blocks the cooperative thread, potentially starving other async work.

**Why it happens:** SwiftGitX wraps libgit2's synchronous C calls. The `nonisolated` async methods don't yet use a custom executor or detached thread internally (documented TODO in SwiftGitX source).

**How to avoid:** Run clone/fetch operations on a dedicated actor or inside `Task.detached {}` to avoid blocking the cooperative pool. For the prompt library sync, this is acceptable since it's user-triggered and infrequent.

**Warning signs:** UI freezes during sync, or other async tasks stall while clone/fetch is running.

### Pitfall 3b: SwiftGitX SIGPIPE on Fetch (Open Issue #12)

**What goes wrong:** `repo.fetch()` raises SIGPIPE under certain network configurations.

**Why it happens:** Open bug in SwiftGitX v0.4.0 (#12, filed Dec 2025).

**How to avoid:** Wrap fetch in a do/catch and handle gracefully — show "Sync failed, try again later" rather than crashing. Consider adding `signal(SIGPIPE, SIG_IGN)` early in app startup as a safety measure (standard practice for apps doing network I/O).

### Pitfall 4: MigrationStage.lightweight Fails If V1 Models Are Not All Re-Declared in V2

**What goes wrong:** FlycutSchemaV2.models omits one of the V1 models (e.g., GistRecord). SwiftData drops that table during migration.

**Why it happens:** V2 must list ALL models that should exist after migration, including V1 models that haven't changed.

**How to avoid:** Use typealias in V2 to re-export V1 models that are unchanged:
```swift
// In FlycutSchemaV2:
typealias Clipping = FlycutSchemaV1.Clipping
typealias Snippet = FlycutSchemaV1.Snippet
typealias GistRecord = FlycutSchemaV1.GistRecord
// Plus new:
// class PromptLibraryItem { ... }
```
Then `models` array includes all four.

**Warning signs:** GistRecord or Snippet data disappears after schema migration in testing.

### Pitfall 5: Local Clone Directory Must Exist Before Clone

**What goes wrong:** `Repository.clone(from:to:)` fails because the parent directory (`~/Library/Application Support/Flycut/`) doesn't exist yet.

**Why it happens:** SwiftGitX/libgit2 expects the parent directory to exist (it creates only the final component).

**How to avoid:** Call `FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)` before cloning. Also check if the target directory already exists (partially failed clone) and remove it before retrying.

**Warning signs:** Clone throws a file system error; subsequent clone attempts fail because a partial `.git` directory exists.

### Pitfall 6: Swift Regex `/\{\{/` — Braces Must Be Escaped

**What goes wrong:** Using `/{{/` as a regex literal to match literal `{{`. Swift Regex literals parse `{` as a quantifier start character (like `{2,4}` in POSIX regex).

**Why it happens:** Regex `{` is a metacharacter for repetition quantifiers.

**How to avoid:** Escape literal braces: `/\{\{(?<variable>[^}]+)\}\}/`. Test with at least: `{{clipboard}}`, `{{ clipboard }}`, `{{with spaces}}`, `text before {{var}} text after`.

**Warning signs:** Compile error "invalid regex: expected repetition count" or substitution silently fails on valid `{{variable}}` patterns.

### Pitfall 7: PromptLibraryView @Query Sees Both V1 and V2 Objects

**What goes wrong:** After updating `FlycutApp.sharedModelContainer` to use FlycutSchemaV2, the `makeTestContainer()` utility in tests still uses `Schema(FlycutSchemaV1.models)`. Tests that create PromptLibraryItem objects fail because the schema doesn't include them.

**Why it happens:** Test helper was written for V1 only.

**How to avoid:** Update `TestModelContainer.swift` to use `Schema(FlycutSchemaV2.models)` after the migration is in place.

**Warning signs:** Test crashes with `Invalid type: PromptLibraryItem is not part of schema`.

---

## Code Examples

Verified patterns from official sources and this codebase:

### PromptInfo Sendable Struct (mirrors SnippetInfo pattern)
```swift
// Source: SnippetInfo pattern (this codebase, FlycutSwift/Services/SnippetStore.swift)
struct PromptInfo: Sendable, Identifiable {
    let id: PersistentIdentifier
    let promptID: String         // stable slug from JSON ("code-review-swift")
    let title: String
    let content: String
    let category: String
    let version: Int
    let isUserCustomized: Bool
}
```

### PromptDTO — Decodable Struct for Prompt JSON Files
```swift
// Represents a single prompt JSON file from the cloned repo
struct PromptDTO: Decodable, Sendable {
    let id: String            // stable slug ("code-review-swift")
    let title: String
    let category: String      // directory name ("coding", "writing", etc.)
    let version: Int
    let content: String       // template content with {{variable}} placeholders
}
```

### Template Substitution — Full Example
```swift
// Source: Swift Regex documentation (swift.org/documentation/swift-book) + polpiella.dev
import Foundation

struct TemplateSubstitutor {
    // Matches {{variable}} and {{  spaced  }} patterns
    private static let pattern = /\{\{(?<variable>[^}]+)\}\}/

    static func substitute(in content: String, variables: [String: String]) -> String {
        content.replacing(Self.pattern) { match in
            let key = String(match.variable).trimmingCharacters(in: .whitespaces)
            return variables[key] ?? String(match.0)
        }
    }

    static func substituteClipboard(in content: String) -> String {
        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        return substitute(in: content, variables: ["clipboard": clipboardText])
    }
}
```

### Git Clone + Pull Sync — Complete Pattern
```swift
import SwiftGitX

// PromptSyncService.swift — actor for thread safety
actor PromptSyncService {
    private let localPath: URL
    private var repoURL: URL

    init(repoURL: URL) {
        self.repoURL = repoURL
        self.localPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flycut/prompt-library")
    }

    /// Clone or pull, then read all prompt JSON files and upsert into SwiftData
    func sync(store: PromptLibraryStore) async throws {
        let gitDir = localPath.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            // Already cloned — fetch updates
            let repo = try Repository(at: localPath)
            try await repo.fetch()
            // TODO: merge remote tracking branch after fetch
        } else {
            // First time — ensure parent dir exists, then clone
            try FileManager.default.createDirectory(
                at: localPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try await Repository.clone(from: repoURL, to: localPath)
        }

        // Read prompt files from disk and upsert
        let prompts = try readPromptsFromDisk()
        for prompt in prompts {
            try await store.upsert(remote: prompt)
        }
    }

    private func readPromptsFromDisk() throws -> [PromptDTO] {
        let promptsDir = localPath.appendingPathComponent("prompts")
        var results: [PromptDTO] = []
        let categoryDirs = try FileManager.default.contentsOfDirectory(
            at: promptsDir, includingPropertiesForKeys: [.isDirectoryKey]
        )
        for dir in categoryDirs where dir.hasDirectoryPath {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
            for file in files {
                let data = try Data(contentsOf: file)
                let prompt = try JSONDecoder().decode(PromptDTO.self, from: data)
                results.append(prompt)
            }
        }
        return results
    }
}
```

### V1 → V2 Migration Plan (Complete)
```swift
// FlycutMigrationPlan.swift — updated for V2
import SwiftData

enum FlycutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FlycutSchemaV1.self, FlycutSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // Lightweight migration: adding a new independent model requires no data transformation
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FlycutSchemaV1.self,
        toVersion: FlycutSchemaV2.self
    )
}
```

### "Fork to Snippet" Action
```swift
// In PromptLibraryView or PromptLibraryStore
func forkToSnippet(_ prompt: PromptInfo, snippetStore: SnippetStore) async throws {
    // Create a fully independent Snippet from library prompt content
    try await snippetStore.insert(
        name: prompt.title,
        content: prompt.content,
        language: nil,
        tags: ["prompt", prompt.category]
    )
    // The original PromptLibraryItem is unaffected — it remains in the library
}
```

### Settings Integration — Repo URL Configuration
```swift
// In PromptLibrarySettingsSection.swift
struct PromptLibrarySettingsSection: View {
    @AppStorage("promptLibraryRepoURL") private var repoURL = "https://github.com/generalarcade/flycut-prompts"
    @State private var isSyncing = false
    @State private var lastSyncDate: Date?

    var body: some View {
        Section("Prompt Library") {
            TextField("Repository URL", text: $repoURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(isSyncing ? "Syncing..." : "Sync Now") {
                    Task.detached { // detached to avoid blocking cooperative pool
                        await syncPromptLibrary()
                    }
                }
                .disabled(isSyncing)

                if let date = lastSyncDate {
                    Text("Last synced: \(date.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSRegularExpression for string templates | Swift Regex literal with `.replacing(_:with:)` | Swift 5.7 / macOS 13 (2022) | Type-safe named capture groups; compile-time syntax check; no Obj-C bridging |
| Custom SwiftData schema with no migration | `VersionedSchema` + `SchemaMigrationPlan` | SwiftData GA / macOS 14 (2023) | Safe schema evolution without manual SQLite migration |
| GitHub Contents API sync (REST, ETag, rate-limited) | Git clone/pull via SwiftGitX (libgit2) | 2025+ | Atomic updates, no API rate limits, works with any git host, version history built-in |
| Bundled resources + network sync | Clone-on-first-launch from preferences | 2025+ | No app bundle bloat, single source of truth (git repo), community contributions via PRs |

**Deprecated/outdated:**
- `SecKeychainItem` APIs: Not relevant here (no auth token needed for public repo clone).
- `NSRegularExpression.replacingMatches(in:options:range:withTemplate:)`: The template parameter uses `$1`, `$2` back-references, not Swift Regex capture group names. Use `String.replacing(_:with:)` closure form instead for named captures.
- GitHub Contents API for sync: Replaced by git clone/pull approach — simpler, no rate limits, atomic updates.
- SwiftGit2 (upstream): Dead since 2019, no SPM, no Swift 6. Use SwiftGitX instead.

---

## Open Questions

1. **GitHub Repo URL — Where Does the Library Live?**
   - What we know: The sync URL must be a public git repo (cloned via SwiftGitX). The research assumes a repo owned/maintained by the Flycut project.
   - What's unclear: The actual repo URL for the prompt library. This may be a directory in this same repo or a separate dedicated repo.
   - Recommendation: Use an `@AppStorage`/`UserDefaults` key for the repo URL so it can be changed via Settings. Default to a Flycut project repo. User configures in preferences.

2. **`{{variable}}` Variables Beyond `{{clipboard}}`**
   - What we know: `{{clipboard}}` is specified in the requirements. The `TemplateSubstitutor` pattern supports arbitrary variables.
   - What's unclear: Whether `{{date}}`, `{{appname}}`, `{{selection}}` are in scope for this phase.
   - Recommendation: Implement the generic substitution dictionary pattern (not hardcoded to clipboard-only) so future variables are additive. For this phase, only populate `"clipboard"` in the variables dict.

3. **In-Place Prompt Editing vs. Fork-Only**
   - What we know: Requirements say "copy any library prompt to personal snippets for customization" (PMPT-04). The `isUserCustomized` field on PromptLibraryItem suggests in-place editing is also supported.
   - What's unclear: Should the prompt detail view allow in-place editing (setting `isUserCustomized = true`)? Or should all customization flow through "Fork to Snippet"?
   - Recommendation: Support both. In-place editing within the library (sets `isUserCustomized = true`, protects from future sync overwrites) is more convenient. "Fork to Snippet" creates an independent copy. Document the difference to the user.

4. **App Store vs. Direct Download — No Network/FS Entitlement Concern**
   - What we know: The app is direct download, not sandboxed, and already makes network calls to GitHub (Gist API). SwiftGitX uses libgit2 (linked statically via SPM), not the system git binary. Writing to `~/Library/Application Support/` is standard for non-sandboxed apps.
   - What's unclear: None — no entitlement concern.
   - Recommendation: No action required. Verify the clone directory is in Application Support (not Documents or tmp).

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in, target: FlycutTests) |
| Config file | GENERATE_INFOPLIST_FILE=YES (set in Phase 2) |
| Quick run command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing:FlycutTests/PromptLibraryStoreTests 2>&1 \| grep -E "passed\|failed\|error"` |
| Full suite command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' 2>&1 \| tail -20` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PMPT-01 | Prompts loaded from cloned repo and populated into PromptLibraryStore | unit | `xcodebuild test -only-testing:FlycutTests/PromptSyncServiceTests/testReadPromptsFromDisk` | ❌ Wave 0 |
| PMPT-03 | Sync upserts new prompts; skips isUserCustomized=true; skips same-version | unit | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests/testUpsertVersioning` | ❌ Wave 0 |
| PMPT-04 | Fork to Snippet creates independent Snippet with correct content | unit | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests/testForkToSnippet` | ❌ Wave 0 |
| PMPT-05 | TemplateSubstitutor replaces {{clipboard}} with clipboard content | unit | `xcodebuild test -only-testing:FlycutTests/TemplateSubstitutorTests` | ❌ Wave 0 |
| PMPT-06 | Paste flow: substitute + PasteService receives substituted content | integration | `xcodebuild test -only-testing:FlycutTests/PromptPasteTests` | ❌ Wave 0 |
| PMPT-07 | Version-aware sync: isUserCustomized=true blocks overwrite; lower remote version blocks overwrite | unit | `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests/testUpsertVersioning` | ❌ Wave 0 |
| Migration | V1→V2 migration preserves all existing Clipping/Snippet/GistRecord rows | unit | `xcodebuild test -only-testing:FlycutTests/SchemaMigrationTests` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -only-testing:FlycutTests/PromptLibraryStoreTests` (fastest relevant suite)
- **Per wave merge:** Full suite command above
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `FlycutTests/PromptLibraryStoreTests.swift` — covers PMPT-03, PMPT-04, PMPT-07 (upsert, version guard, fork)
- [ ] `FlycutTests/PromptSyncServiceTests.swift` — covers PMPT-01 (reading prompts from disk directory), PMPT-03 (upsert after sync)
- [ ] `FlycutTests/TemplateSubstitutorTests.swift` — covers PMPT-05 (substitution happy path, no-match pass-through, whitespace trimming, multiple variables)
- [ ] `FlycutTests/PromptPasteTests.swift` — covers PMPT-06 (end-to-end: substitute → PasteService input)
- [ ] `FlycutTests/SchemaMigrationTests.swift` — covers V1→V2 migration data preservation
- [ ] Update `FlycutTests/TestModelContainer.swift` — change `Schema(FlycutSchemaV1.models)` to `Schema(FlycutSchemaV2.models)` so all existing tests still compile against the new schema

---

## Sources

### Primary (HIGH confidence)
- FlycutSchemaV1.swift (this codebase) — V1 model definitions to preserve in migration
- FlycutMigrationPlan.swift (this codebase) — migration plan structure to extend
- SnippetStore.swift (this codebase) — @ModelActor pattern to mirror for PromptLibraryStore
- GistService.swift + AppDelegate.swift (this codebase) — existing service patterns
- SnippetInfo pattern (this codebase) — Sendable value struct for cross-actor transfer
- Apple SwiftData documentation — VersionedSchema, MigrationStage.lightweight, adding new model type
- Swift Regex documentation / polpiella.dev — named capture groups in Swift Regex literals, `.replacing(_:with:)` closure
- SwiftGitX GitHub repo (ibrahimcetin/SwiftGitX) — Swift 6 git library, v0.4.0, async clone/fetch API
- SwiftGitX Swift Forums announcement (Feb 2025) — project goals and architecture

### Secondary (MEDIUM confidence)
- donnywals.com SwiftData migrations deep dive — confirms lightweight migration supports adding new independent model types
- git-macOS (way-to-code/git-macOS) — alternative git library research (subprocess-based, not recommended)
- SwiftGit2 / SwiftGit3 research — confirmed dead/unmaintained alternatives

### Tertiary (LOW confidence)
- azamsharp.com "if you are not versioning your SwiftData schema" — versioned schema best practices; single source, directionally consistent with Apple docs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — SwiftGitX confirmed Swift 6 + async/await via source inspection; built-in Apple frameworks for everything else
- Architecture (schema migration, sync service, substitutor): HIGH — SwiftData migration confirmed via official docs + donnywals.com; Swift Regex confirmed via official docs
- SwiftGitX: MEDIUM-HIGH — actively maintained, Swift 6, but pre-1.0 (v0.4.0) with one open bug (#12 SIGPIPE on fetch)
- Git clone/pull approach: HIGH — standard git operations, atomic, no rate limits, proven pattern
- Pitfalls: HIGH — most derived from existing codebase decisions and verified Swift 6 compiler constraints

**Research date:** 2026-03-10
**Valid until:** 2026-06-10 (stable APIs; SwiftData and Swift Regex are stable in macOS 15+)
