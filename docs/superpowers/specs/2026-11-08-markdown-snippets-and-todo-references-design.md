# Markdown snippets and snippet references in todos

Date: 2026-11-08
Status: approved 2026-11-08

## Intent

Snippets are turning into a personal wiki / documentation store. Adam writes
in markdown by habit, so a snippet should read as formatted markdown inside
Clipsmith. Todos often point at a topic whose thinking lives elsewhere
("Write a blog about xyz", with the notes on xyz in a snippet), so a todo
should be able to reference a snippet and open it.

Two features, one shared idea: the `[[Snippet name]]` link syntax.

## Goals

1. A snippet whose language is Markdown renders as formatted markdown in the
   Snippets section of the browser window, with a toggle to edit the raw text.
2. Pasting from a markdown snippet pastes only the selected text when there
   is a selection, otherwise the whole snippet (as today). Code snippets keep
   today's behaviour: always the whole snippet.
3. A todo can contain `[[Snippet name]]`. In the todo list it shows as a link;
   acting on it opens the browser on Snippets with that snippet selected.
   If no snippet has that name, acting on it creates one (language Markdown,
   empty content) and opens it in edit mode.

## Non-goals

- Live WYSIWYG markdown editing (Bear / Obsidian live preview). Rejected by
  Adam in favour of rendered view + raw edit toggle.
- Rendering markdown in what gets pasted. Paste is always plain text.
- Links between snippets (`[[x]]` inside a snippet). Same syntax will work
  later; not built now.
- Due-date notifications for todos. Separate feature, brainstormed next.
- Backlinks, graph view, folders for snippets.

## Anti-goals

- Changing how existing code snippets look or behave. Only snippets with
  language `markdown` get the rendered view.
- Making the TaskPaper file depend on Clipsmith. `[[name]]` is plain text in
  the task line and must survive round-tripping through other editors.
- A SwiftData schema migration. Neither feature needs a new field. (A
  snippet UUID was considered and dropped: todo lines have no stable
  identity to attach it to, and rename-rewrite by name covers the need.)

## Constraints (from the codebase)

- Snippet model: `ClipsmithSchemaV1.Snippet` with `name`, `content`,
  `language: String?`, `tags`. Markdown is already a language option
  (`"markdown"` in `SnippetEditorView.languageOptions`).
- Snippet names are not unique.
- Todos are a TaskPaper text file parsed by `TaskPaperParser`; `TodoItem.title`
  is the line minus `- ` and tags.
- Browser opening goes through `BrowserOpenRequest(section:query:)` →
  `BrowserOpenMailbox` → `BrowserWindowView` (see CLAUDE.md). Today only Docs
  consumes `query`.
- Docs renders HTML in a `WKWebView` (`Views/Browser/DocWebView.swift`) with
  custom light/dark CSS.
- Swift 6 strict concurrency, `@MainActor` UI types, Sendable models.
- Paste: `SnippetsSectionView.pasteSnippet` closes the browser and calls
  `PasteService.paste(content:into:)` with the previous app.

## Decided

### Markdown snippets

- Rendered view is the default when a markdown snippet is selected. An
  Edit / Done toggle (with a keyboard shortcut) switches to the existing raw
  editor (`HighlightedTextEditor`) and back.
- Rendering: markdown → HTML with Apple's open-source `swift-markdown`
  package (new SPM dependency), shown in a `WKWebView` styled like Docs
  (light/dark). Supports headings, lists, emphasis, links, block quotes,
  tables, fenced code blocks.
- Fenced code blocks are syntax-highlighted. *(Claude's call: the method is
  left to the builder; see below.)*
- Links in rendered markdown open in the default web browser, not inside the
  web view.
- Paste with a selection:
  - Rendered view: paste the selected text as displayed (no markdown
    symbols). Selecting a command inside a code block yields just the command.
  - Edit view: paste the raw markdown of the selection.
  - No selection: paste the full raw `content`, unchanged from today.
  - Triggers: the existing paste button, Return in the snippet list (both
    unchanged), plus ⌘↩ which works from anywhere in the Snippets section,
    including inside the rendered view and the raw editor where Return
    cannot be used. ⌘↩ is selection-aware for markdown snippets and pastes
    the whole snippet otherwise. *(Claude's call: keyboard-first app, and
    Return in the editor must stay a newline.)*

### Snippet references in todos

- Syntax: `[[Snippet name]]` anywhere in the task text, e.g.
  `- Write a blog about [[xyz]] @today`. Stored verbatim in the file.
- Display: the reference renders as a link-styled inline chip in the task
  row; the brackets are not shown.
- Activation: clicking the chip, or a keyboard shortcut on the selected task
  (opens its first reference). *(Claude's call: shortcut key left to the
  builder, must not clash with the Todos table in `TodosSectionView`.)*
- Activation posts a `BrowserOpenRequest` for Snippets carrying the snippet
  name; the Snippets section selects the matching snippet.
- Name matching: case-insensitive exact match on `name`. If several match
  (legacy duplicates, see below), pick the most recently updated.
- Missing snippet: create `name = <reference>`, `language = "markdown"`,
  empty content, select it, open in edit mode. *(Claude's call; Adam did not
  answer this one.)*
- Renaming a snippet rewrites references in the todo file (decided with
  Adam). The file only ever holds names; no IDs are stored anywhere:
  - Whenever a snippet save changes `name` (the editor auto-saves 500 ms
    after typing stops), every `[[old name]]` in the todo file, matched
    case-insensitively, is rewritten to `[[new name]]` through `TodoStore`
    (so it goes through the normal debounced save and watcher logic).
    Intermediate names while typing are fine: references follow each save.
  - Requires unique snippet names, below. Without uniqueness a rename could
    capture references meant for another snippet.
  - Known gap: an external editor holding an older copy of the todo file can
    overwrite the rewrite when it saves (existing last-write-wins behaviour).
- Snippet names are unique, case-insensitive (decided with Adam):
  - Creating or renaming to a name another snippet already has is refused:
    the editor shows an inline warning and does not save the name (other
    fields still save). New snippets get a free name ("Untitled Snippet",
    "Untitled Snippet 2", ...).
  - Existing duplicates are not changed automatically. They are marked in
    the snippet list so Adam can rename them; references to a duplicated
    name open the most recently updated one.
  - No schema change: uniqueness is enforced in `SnippetStore` /
    the editor, not with a SwiftData `.unique` attribute (which would need a
    migration and would fail on existing duplicates).
- Editing a task (the inline edit field) shows the raw `[[...]]` text.
- A reference name containing ` @word` (e.g. `[[Notes on @swift]]`) breaks,
  because TaskPaper reads ` @word` as a tag. Accepted limitation;
  `TaskPaperParser` is not changed, so the file reads the same in every
  TaskPaper editor. References are extracted from the raw line by a new,
  separate extractor. *(Claude's call.)*

## Precondition

Builds on the uncommitted Todos work from 2026-11-07/08 (task edit via
Return / double-click / context menu, Move to, All tab, drag onto project
chips). That work is committed before implementation starts. The reference
chip's click handling must coexist with row selection, double-click-to-edit
and row dragging.

## Left to the builder

- How code blocks get highlighted (bundled highlight.js in the web view,
  HighlightSwift → HTML, or similar), provided it works offline and matches
  light/dark.
- Whether the markdown web view reuses `DocWebView` or is a sibling view.
- How the selection is read from the web view (JS `getSelection()` is the
  obvious route) and from the raw editor.
- How the Snippets section consumes a name from `BrowserOpenRequest` (a
  pending-name field mirroring `pendingDocsQuery` is the obvious route).
- Exact visual styling of the reference chip and the Edit/Done toggle.
- Test layout: parser for `[[...]]` references, name matching, rename
  rewrite, unique-name checks and markdown→HTML conversion should be
  unit-tested; UI is verified by hand.
