# Phase 5: Prompt Library - Context

**Gathered:** 2026-03-10 (updated 2026-03-11)
**Status:** Ready for planning

<domain>
## Phase Boundary

A community-driven prompt library with a searchable prompt bezel as the primary interface. Prompts are maintained in a git repo (individual files for easy PR contributions), built into a single `prompts.json` served via HTTP. Flycut fetches this JSON, stores prompts locally via SwiftData, and provides fast access via a dedicated bezel hotkey with `{{variable}}` template substitution on paste. A Prompts tab in the snippet window provides browsing and management. Users can also create their own prompts and edit library prompts in-place.

</domain>

<decisions>
## Implementation Decisions

### Architecture: Markdown repo → build → JSON → HTTP fetch
- **Source repo:** Individual prompt `.md` files organized by category directories (contributors submit PRs)
- **Prompt format:** Markdown with YAML frontmatter — `title`, `category`, `version` in frontmatter, prompt content as Markdown body. `id` derived from filename (e.g., `code-review-swift.md` → `"code-review-swift"`)
- **Build step:** GitHub Action parses all `.md` files (frontmatter + body), converts to a single `prompts.json` (published as release asset or GitHub Pages)
- **Client (Flycut):** Fetches `prompts.json` via URLSession — no git dependency in the app
- **No SwiftGitX, no libgit2, no git clone/pull in the app** — just a simple HTTP GET
- Per-prompt `version` field for incremental updates (only update prompts where remote version > local)

**Prompt Markdown format (repo source):**
```markdown
---
title: Swift Code Review
category: coding
version: 1
---

Review this Swift code for correctness, safety, and style:

{{clipboard}}
```

**Generated JSON format (what Flycut fetches):**
```json
{
  "version": 1,
  "prompts": [
    {
      "id": "code-review-swift",
      "title": "Swift Code Review",
      "category": "coding",
      "version": 1,
      "content": "Review this Swift code for correctness, safety, and style:\n\n{{clipboard}}"
    }
  ]
}
```
Top-level `version` is the catalog version (incremented on each build). Per-prompt `version` tracks individual prompt changes.

### Data model: SwiftData V2 with PromptLibraryItem
- **New `PromptLibraryItem` @Model** in FlycutSchemaV2 — separate from Snippet
- **Lightweight V1→V2 migration** — adding a new independent model, no data transformation needed
- **`@ModelActor` PromptLibraryStore** — mirrors SnippetStore pattern for background CRUD
- **`PromptInfo` Sendable struct** — mirrors SnippetInfo for cross-actor transfer
- **Reactive `@Query`** in Prompts tab and bezel views

### Three types of prompts
- **Library prompts** — synced from remote, editable in-place
- **Customized library prompts** — edited in-place, `isUserCustomized=true`, sync skips them, user can revert to latest upstream version
- **User prompts** — created locally by the user, live in "My Prompts" category, never affected by sync (no remote counterpart)

### In-place editing & revert
- Library prompts are editable in-place — editing sets `isUserCustomized=true`
- Sync skips prompts with `isUserCustomized=true` — user edits are preserved
- **Revert to upstream:** user can reset a customized prompt back to the latest synced version (clears `isUserCustomized`, next sync restores remote content)
- Customized prompts are visually marked as such — both in the list (badge/indicator) and in the detail view
- Revert action accessible from the detail view

### User-created prompts
- "+" button in the Prompts tab toolbar to create a new prompt
- User prompts go into a dedicated "My Prompts" category
- Fully editable, never affected by sync
- Show up in both the Prompts tab and the prompt bezel alongside library prompts

### Prompt bezel (primary interface)
- Separate searchable bezel for fast prompt access — dedicated hotkey (configurable in Settings, distinct from clipboard bezel hotkey)
- **Same visual style** as the clipboard bezel — same material blur, opacity, rounded corners, sizing. Consistent and familiar.
- Mirrors the clipboard bezel pattern: non-activating NSPanel, search field, keyboard navigation (arrows/j/k), Enter to paste
- **List items show title + category badge** — each item displays the prompt title with a small category tag
- **Category cycling via Tab key** — Tab cycles through All → coding → writing → analysis → creative → My Prompts → All. Current category shown in the bezel header.
- **`#category` search syntax** — typing `#coding Python` filters to coding category and searches for "Python". Works in both bezel and Prompts tab.
- Searches all prompts (library + user-created) — filters by title and content as user types
- Template variable substitution on paste (`{{clipboard}}` auto-substituted, unknown vars left as-is)
- This is the primary "use a prompt" interface — optimized for the 3-second interaction: hotkey → type → Enter → pasted

### Prompts tab (management interface)
- **2nd tab** in SnippetWindowView: Snippets (⌘1) | Prompts (⌘2) | Gists (⌘3)
- **Flat searchable list** with category shown as tags on each item — not a category tree or grouped sections
- **`#category` search syntax** — same as bezel, `#coding` filters to coding category
- Detail view shows prompt content with `{{variable}}` tokens highlighted
- Customized prompts visually marked (badge/indicator in list + detail view)
- "Save to My Snippets" button in detail view for explicit copy to user's snippets
- "+" button in toolbar to create user prompts (goes to "My Prompts" category)
- "Revert to Original" action in detail view for customized library prompts

### Prompt content display
- Editable text view for library prompts (editing sets `isUserCustomized=true`) and user prompts
- `{{variable}}` tokens highlighted in a distinct color so they stand out visually
- No separate variable list — variables are visible in the content itself

### Sync & config
- No auto-sync on first launch — user must configure in Settings
- New "Prompt Library" tab in SettingsView with: JSON URL text field, Sync Now button, last-synced status
- Default URL points to the project's published `prompts.json`
- Sync is manual only — "Sync Now" button in Settings
- Error display: inline error message below the sync button in settings (no system notifications)
- Bundled default `prompts.json` in app bundle for offline first launch — prompts available immediately without network
- Online sync adds/updates prompts from the remote JSON
- Sync skips prompts with `isUserCustomized=true` — never overwrites user edits

### Template variables
- **`{{clipboard}}`** — built-in, auto-substituted with current system clipboard content (equivalent to Flycut history top since Flycut captures from system clipboard). **Security note:** warn users that `{{clipboard}}` inserts whatever is on the clipboard — if a password is there, it will be included. Show a note in Settings (Prompt Library tab) and in prompt detail view when `{{clipboard}}` is present.
- **User-defined variables** — configured in Settings as key=value pairs (e.g., `language=python`, `name=John`). Auto-substituted on paste if defined. Settings UI: a key-value list editor in the Prompt Library settings tab.
- **Unknown variables** — any `{{variable}}` not matching a built-in or user-defined key is left as-is in the pasted text. User replaces manually.
- No fill-in dialog, no evaluation — just a simple dictionary lookup on paste

### Save to Snippets
- "Save to My Snippets" button in the prompt detail view — explicit action, not automatic
- Creates a plain Snippet copy (editable, independent of library)
- Library prompt is unaffected — continues to receive sync updates

### Claude's Discretion
- Prompt bezel keyboard handling details (reuse BezelController keyDown or customize)
- Prompt detail view layout and spacing
- How "Revert to Original" confirmation works (alert vs inline)
- PromptInfo Sendable struct field design
- Category badge styling (color-coded vs monochrome)
- Build script implementation (Node/Python/shell for GitHub Action)

</decisions>

<specifics>
## Specific Ideas

- Prompts authored in Markdown with YAML frontmatter — easy for contributors (no raw JSON editing)
- Build step (GitHub Action) parses frontmatter + Markdown body → generates `prompts.json`
- `id` derived from filename, `content` is the Markdown body (everything below the frontmatter)
- Community contributors submit PRs with `.md` files — easy to review, easy to write
- Flycut fetches the single generated JSON file via HTTP — URLSession, same pattern as GistService
- Bundled `prompts.json` in app bundle means prompts work on first launch with zero config
- The bezel is the star — it should feel as fast and invisible as the clipboard bezel
- The build script can be a simple Node/Python/shell script that reads frontmatter and outputs JSON
- `#category` search syntax inspired by tag-based filtering — natural for users, no extra UI chrome needed

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BezelController` + `BezelView` + `BezelViewModel`: Pattern for the prompt bezel — non-activating panel, search mode, keyboard nav, paste-and-hide flow
- `SnippetWindowView`: Already has segmented Picker for tabs — add "Prompts" as tag 1 (Snippets=0, Prompts=1, Gists=2)
- `SnippetListView`: Flat searchable list pattern to mirror for Prompts tab
- `SnippetStore`: @ModelActor pattern to mirror for PromptLibraryStore
- `PasteService`: Reuse directly for prompt paste-into-frontmost-app
- `AppTracker`: Tracks previous app for paste target
- `FlycutSchemaV1.Snippet`: Target model for "Save to My Snippets" — use `SnippetStore.insert()`
- `GistSettingsSection`: Pattern for adding a new settings tab (Prompt Library settings)
- `GistService`: Pattern for URLSession network calls (fetch JSON from URL)

### Established Patterns
- `@ModelActor` for all SwiftData background writes
- `@Query` in SwiftUI views for reactive data display
- `PersistentIdentifier` for cross-actor model references
- `@AppStorage` for user preferences in views
- `UserDefaults.standard` reads in non-view code
- `SnippetInfo` Sendable struct for cross-actor transfer (mirror for PromptInfo)
- Notification bridge pattern (`.flycutOpenSnippets`) for cross-component communication
- `KeyboardShortcuts` library for registering global hotkeys

### Integration Points
- `SnippetWindowView`: Reorder tabs — Snippets (⌘1), Prompts (⌘2), Gists (⌘3)
- `SettingsView`: Add "Prompt Library" tab with URL config, sync button, custom variables editor
- `AppDelegate`: Create prompt bezel, register hotkey, wire PromptLibraryStore and sync service
- `KeyboardShortcutNames`: Add `.activatePrompts` hotkey name
- `FlycutSchemaV1` → `FlycutSchemaV2`: Add PromptLibraryItem model, lightweight migration

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-prompt-library*
*Context gathered: 2026-03-10, updated: 2026-03-11*
