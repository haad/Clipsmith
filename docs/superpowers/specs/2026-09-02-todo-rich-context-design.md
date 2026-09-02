# Todo Rich Context & Snippet Linking — Design Spec

**Date:** 2026-09-02
**Status:** Approved design, pending implementation plan
**Research:** `docs/superpowers/research/2026-09-02-todo-attachments-research.md` (field survey: TaskPaper, org-attach, todo.txt, Taskwarrior, NotePlan/Obsidian, Things/OmniFocus/Bear URL schemes)

## Problem

Todo tasks (shipped in 5.3.0) are lean one-liners. Users need rich context on some tasks: long descriptions, code, links, screenshots. Making the TaskPaper format rich is the wrong move (research pattern D breaks down on binaries and bloats the file). Instead: keep tasks lean, put rich content in the snippet library Clipsmith already has, and link them.

Also in scope, carried from user feedback:
- Note lines in the todo file are preserved but never rendered.
- URLs in tasks/notes are not clickable.
- Bug: opening the todo window does not bring it to front / give it focus.

## Decisions (made with user)

| Decision | Choice |
|---|---|
| Linking mechanism | Plain TaskPaper tag `@snippet(<uuid>)` on the task line (research pattern C). Round-trips byte-exact; inert in other editors. |
| Snippet identity | New `uuid: UUID` field on the Snippet model (schema V3). Names are not stable identifiers. |
| Rich content store | Existing snippet library, extended to hold an optional image (user chose images-inside-snippets over a sidecar attachments folder). |
| Deep links | Register `clipsmith://` URL scheme; `clipsmith://snippet/<uuid>` opens the snippet; "Copy Link" on snippets (research pattern A, Things/OmniFocus style). |
| Notes | Render note lines in the todo list (dimmed, non-selectable), flat, in file order. Still plain text in the file. |
| Links in text | Auto-detect http(s)/www URLs in task titles and note lines; render tappable. |
| Focus bug | Diagnose with the running app first; candidate fix is an explicit `makeKeyAndOrderFront` + `NSApp.activate()` after `openWindow`. |

Out of scope for this iteration: pasting an image snippet's image via the paste bezel (image snippets paste their text content; the image is viewing context only), multiple rendered attachments per task (multiple `@snippet` tags are legal in the file; the UI acts on the first), attachments folder on disk, `./path` file-link detection, task-level deep links (`clipsmith://todo/...`).

## Architecture

### 1. Schema V3 (Snippet identity + image)

New `ClipsmithSchemaV3` in `Clipsmith/Models/Schema/`:
- `Snippet.uuid: UUID` — default `UUID()`, generated for existing rows by the migration. Not `.unique`-constrained (uniqueness holds by construction; avoids migration complications).
- `Snippet.imageData: Data?` — `@Attribute(.externalStorage)`, nil for text-only snippets.
- Lightweight migration stage V2 → V3 added to `ClipsmithMigrationPlan`. All other models carried forward unchanged.

### 2. Task ↔ snippet link (model layer)

- `TodoItem.snippetID: UUID?` — derived: value of the first `@snippet(...)` tag parsed as a UUID (invalid value ⇒ nil, tag still preserved verbatim in the file).
- `TodoStore.attachSnippet(taskID: UUID, snippetUUID: UUID)` — appends ` @snippet(<uuid-lowercase>)` to the task's rawLine (replacing an existing `@snippet` tag if present). `detachSnippet(taskID:)` removes the tag.
- `SnippetStore` additions: `find(uuid:)`, `insertReturningUUID(name:content:...)` (or equivalent) so the attach flow can create-and-link atomically.

### 3. Attach flow (todo window)

- Task row context menu + keyboard shortcut (⇧⌘A on selection): **Attach Snippet** with two paths:
  - **New Snippet** — creates a snippet named after the task title (empty content), links it, then opens the snippet window with that snippet selected for editing.
  - **Link Existing…** — sheet with a fuzzy-searchable snippet list; Enter links the selection.
- Rows with `snippetID` show a paperclip chip. **⌘O** (or clicking the chip) opens the linked snippet: activate app, open snippets window, select the snippet.
- Dangling link (snippet deleted): chip renders in warning style; opening shows a non-blocking notice with a "Detach" button.
- Snippet selection deep-link plumbing: `Notification.Name.clipsmithOpenSnippetByUUID` with the UUID in userInfo; `SnippetWindowView`/`SnippetListView` observe and select (same activation dance as existing window opens).

### 4. `clipsmith://` URL scheme

- `Info.plist`: `CFBundleURLTypes` with scheme `clipsmith`, URL name `com.github.haad.clipsmith`.
- `AppDelegate.application(_:open:)` routes via a testable `ClipsmithURLRouter` (pure function: `URL → Route`):
  - `clipsmith://snippet/<uuid>` → open snippet window, select snippet.
  - `clipsmith://todos` → open todo window.
  - Unknown routes: log and ignore.
- Snippet row context menu gains **Copy Link** (writes `clipsmith://snippet/<uuid>` to the pasteboard, with ClipboardMonitor self-capture suppression like other in-app copies).

### 5. Image support in snippets

- `SnippetEditorView`: when the pasteboard holds an image, ⌘V sets `imageData` (PNG-normalized); image preview rendered above the content editor with a remove (✕) button. Text content remains independent and editable.
- `SnippetListView` rows show a small photo indicator for snippets with images.
- Paste behavior of image snippets through bezels is unchanged (text content pastes; empty text pastes nothing). Stated limitation, revisit after use.

### 6. Notes rendering + URL linkify (todo window)

- Parser: `TodoNode.note` gains a derived indent level (leading tabs), exposed for display. No format change.
- `TodoWindowViewModel`: new `visibleRows(in:today:)` returning an ordered mix of task rows and note rows for project tabs (notes follow their file position; a note line is displayed under the tab of the project it belongs to). The Today tab remains tasks-only. Search hides note rows (notes are not searched in v1). Show-completed does not affect notes.
- `TodoListView`: note rows render dimmed, smaller type, non-selectable, indented per tab level.
- Linkify: shared helper (`LinkifiedText` view or `AttributedString` builder) using `NSDataDetector` for http(s)/www links in task titles and note lines; links open in the default browser. Plain text remains selectable behavior-wise (row selection unchanged).

### 7. Focus bug (todo window)

- Reproduce first with the running app (menu-bar path and hotkey path). Suspected: `openWindow(id:)` after the activation-policy switch leaves the new window non-key when another app was frontmost.
- Candidate fix in `MenuBarView.openTodoWindow()`: after `openWindow`, brief delay, then find the todos window (`NSApp.windows` by identifier/title) and `makeKeyAndOrderFront(nil)` + `NSApp.activate()`. If diagnosis shows the same defect in the snippets/toolkit paths, fix only todos in this iteration and note the shared helper as follow-up (surgical-changes rule).

## Error handling

- `@snippet(garbage)`: `snippetID` is nil, tag preserved verbatim; no chip shown.
- Snippet deleted while linked: dangling-link chip + notice + Detach (no auto-cleanup of the file).
- URL route with malformed UUID: ignored, logged.
- Image paste failures (unreadable pasteboard image): no-op.
- Migration V2→V3 failure surfaces as the existing fatalError path in `ClipsmithApp.sharedModelContainer` (consistent with V1→V2 handling).

## Testing (TDD, XCTest)

- `TaskPaperParserTests` additions: `snippetID` derivation (valid UUID, invalid value, multiple tags → first wins), note indent levels, round-trip unchanged.
- `TodoStoreTests` additions: `attachSnippet` writes/replaces the tag; `detachSnippet` removes it; round-trip byte-fidelity of attach/detach on otherwise untouched lines.
- `TodoWindowViewModelTests` additions: `visibleRows` interleaving (notes under correct project, Today tasks-only, search hides notes).
- `SchemaMigrationTests` additions: V2 store with snippets migrates, snippets get distinct UUIDs, `imageData` nil.
- New `ClipsmithURLRouterTests`: route parsing (snippet UUID, todos, malformed, unknown host).
- `SnippetStoreTests` additions: `find(uuid:)`, image data set/clear round-trip.
- Focus fix and image paste UI verified via the running app (manual/`run`-skill smoke), not unit tests.

## New / touched files

| File | Change |
|---|---|
| `Models/Schema/ClipsmithSchemaV3.swift` | New — V3 models (Snippet + uuid + imageData) |
| `Models/Schema/ClipsmithMigrationPlan.swift` | Add V2→V3 stage |
| `Services/TaskPaperParser.swift` | `TodoItem.snippetID`, note indent helper |
| `Services/TodoStore.swift` | `attachSnippet` / `detachSnippet` |
| `Services/SnippetStore.swift` | `find(uuid:)`, image support, create-and-link helper |
| `Services/ClipsmithURLRouter.swift` | New — pure URL → Route parsing |
| `Views/Todos/TodoWindowViewModel.swift` | `visibleRows` (tasks + notes) |
| `Views/Todos/TodoListView.swift` | Note rows, linkified text, chip, attach menu, ⇧⌘A/⌘O |
| `Views/Snippets/SnippetEditorView.swift` | Image paste/preview/remove |
| `Views/Snippets/SnippetListView.swift` | Copy Link, image indicator, select-by-UUID |
| `Views/Snippets/SnippetWindowView.swift` | Observe select-by-UUID notification |
| `Views/MenuBarView.swift` | Focus fix in `openTodoWindow`, new notification name |
| `App/AppDelegate.swift` | `application(_:open:)` URL handling |
| `Clipsmith/Info.plist` | `CFBundleURLTypes` |
| `Clipsmith.xcodeproj/project.pbxproj` | Register new files (AA/AF scheme) |
| `CHANGELOG.md` | Unreleased entries |
