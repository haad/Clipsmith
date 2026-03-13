# Phase 4: Code Snippets & Gist Sharing - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

A code snippet manager with syntax highlighting and GitHub Gist sharing. Snippets are saved pieces of code/commands (kubectl, jq, prompts) that users can quickly paste into any app. Gists can be created from snippets or clipboard history entries. This phase delivers SNIP-01 through SNIP-05 and GIST-01 through GIST-05.

</domain>

<decisions>
## Implementation Decisions

### Snippet editor layout
- Master-detail layout: snippet names listed on the left, selected snippet content displayed on the right
- Right side is always editable with syntax highlighting applied (no separate view/edit modes)
- Language selector (dropdown/picker) for choosing syntax highlighting language
- Inline "+" button for creating new snippets directly in the list
- Use case includes prompt libraries — snippets are not just code, any named text

### Snippet organization
- Tags instead of categories — snippets can have multiple tags
- Filter/search by tag in the snippet list
- Tags are free-text, user-created

### Snippet search
- Top search bar in the snippet window
- Filters by name, content, and tags as the user types

### Snippet access
- Menu bar dropdown includes a "Snippets..." item that opens the snippet window
- Configurable global hotkey for instant snippet window access
- Snippet window is a separate WindowGroup (activation policy switch pattern)
- Snippets are completely separate from the bezel — bezel stays for clipboard history only

### Snippet paste behavior
- Double-click a snippet name in the list, or press Enter when selected
- Window closes and snippet content is pasted into the frontmost app via PasteService
- Same paste mechanism as clipboard history

### Gist sharing flow
- "Share as Gist" available from snippet editor AND from menu bar dropdown (right-click a clipping)
- One-click share — no confirmation popover or modal
- Creates gist immediately with auto-generated filename (language-based extension)
- macOS system notification on success: "Gist created" with URL; click notification to open in browser
- Gist URL automatically copied to clipboard after creation

### Gist visibility
- Public/private default is configurable in Settings (Gist settings section)
- One-click share uses the configured default visibility

### Gist history
- Accessible as a tab/segment in the snippet window ("Snippets" | "Gists")
- Each entry shows: filename, creation date, clickable link to open in browser
- Delete action removes the gist from GitHub (API DELETE call) and removes local record

### Claude's Discretion
- Exact window dimensions for the snippet window
- Notification sound/no-sound on gist creation
- Tag input widget design (comma-separated field, tag chips, etc.)
- Exact search debounce timing
- Error state UI for failed gist operations
- How to handle gist deletion failure (network error)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FlycutSchemaV1.Snippet`: @Model already defined with name, content, language, category, createdAt, updatedAt fields — needs tag field addition (category → tags migration or new field)
- `FlycutSchemaV1.GistRecord`: @Model already defined with gistID, gistURL, filename, createdAt
- `ClipboardStore`: @ModelActor pattern to mirror for SnippetStore
- `PasteService`: Reuse directly for snippet paste-into-frontmost-app
- `BezelController`: Activation policy switch pattern already established
- `AppDelegate`: Service wiring pattern (environment injection)

### Established Patterns
- `@ModelActor` for all SwiftData background writes
- `@Query` in SwiftUI views for reactive data display
- `PersistentIdentifier` for cross-actor model references (not @Model objects)
- `@AppStorage` for user preferences
- `UserDefaults.standard` reads in non-view code
- `OSLog.Logger` for structured logging per subsystem

### Integration Points
- `FlycutApp.body`: Add new WindowGroup(id: "snippets") scene
- `MenuBarView`: Add "Snippets..." menu item + "Share as Gist" context action on clippings
- `SettingsView`: Add Gist settings tab/section (PAT entry, default visibility)
- `FlycutApp.sharedModelContainer`: Already includes Snippet and GistRecord models in schema

</code_context>

<specifics>
## Specific Ideas

- Snippets are quick-access saved commands/code — think kubectl commands, jq filters, prompt templates
- Not a full code editor — just a fast way to save, find, and paste named text
- Use case explicitly includes a "prompt library" — snippets aren't limited to programming languages
- One-click gist sharing with zero-friction flow: click share, get notification, URL is on clipboard

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-code-snippets-gist-sharing*
*Context gathered: 2026-03-09*
