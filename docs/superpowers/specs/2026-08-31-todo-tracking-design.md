# Todo Tracking — Design Spec

**Date:** 2026-08-31
**Status:** Approved design, pending implementation plan

## Problem

Clipsmith users (keyboard-first developers) want lightweight todo tracking without leaving their workflow. Existing tools are either heavyweight apps or raw text files with no UI. Clipsmith adds a native, keyboard-first UI on top of a plain-text file the user still owns.

## Decisions (made with user)

| Decision | Choice |
|---|---|
| Storage | Plain-text file is the single source of truth. No SwiftData. |
| Format | TaskPaper (`Project:` lines, `- task` items, notes, `@tag(value)` tags) |
| UI placement | New dedicated window (like the Snippet window), project tabs |
| v1 scope | `@today` + Today view, `@due(date)`, free-form `@tags`, quick-add bezel |
| File location | Default `~/Library/Application Support/Clipsmith/todos.taskpaper`, user-overridable in Settings |
| Done handling | `@done(YYYY-MM-DD)` tag in place; show/hide-completed toggle |
| Rollout | Feature flag `todoTrackingEnabled`, default off, Settings > Features |

Explicitly out of scope for v1: priorities, subtask collapse/folding, recurrence, reminders/notifications, multiple files, sync conflict resolution beyond last-write-wins.

## Architecture

### 1. Data model + parser

New files under `Clipsmith/Services/` (model types may live alongside the parser):

- **`TodoItem`** — `Sendable` struct: raw text, title (text minus tags), `tags: [TodoTag]` (`name` + optional `value`), indent level, in-memory `UUID` for UI selection (never serialized). Derived properties: `isDone` (`@done` present), `doneDate`, `dueDate` (parsed from `@due(YYYY-MM-DD)`), `isToday` (`@today` present).
- **`TodoProject`** — name + ordered `[TodoNode]`. A synthetic **Inbox** project holds top-level items that precede any project line.
- **`TaskPaperDocument`** — ordered projects + preservation of all non-task lines (notes, blank lines) verbatim.
- **`TaskPaperParser`** — parses the four TaskPaper concepts:
  - Project: line ending in `:` (ignoring trailing tags)
  - Task: line whose trimmed form starts with `- `
  - Note: any other non-blank line
  - Tag: `@name` or `@name(value)`, multiple per line
  - Hierarchy: literal tab indentation. Nested items are parsed and rendered indented, but v1 treats them as flat tasks (no fold/collapse).
- **Serializer** — writes the document back. **Round-trip invariant: parse → serialize with no edits reproduces the input byte-for-byte.** Unknown/malformed lines are preserved verbatim as notes.

### 2. TodoStore

`Clipsmith/Services/TodoStore.swift` — `@MainActor @Observable` class (not `@ModelActor`; no SwiftData).

- Owns the `TaskPaperDocument`, loads on init/flag-enable.
- CRUD: `addTask(text:project:tags:)`, `toggleDone(id:)` (adds/removes `@done(YYYY-MM-DD)`), `editTask(id:text:)`, `deleteTask(id:)`, `moveTask(id:toProject:)`, `addProject(name:)`, `renameProject`, `deleteProject`.
- Persistence: debounced (~0.5 s) atomic writes (write-to-temp + rename).
- File path: default `~/Library/Application Support/Clipsmith/todos.taskpaper`; user-overridable via Settings with security-scoped bookmark for paths outside the container. Path stored in UserDefaults (`AppSettingsKeys.todoFilePath` / bookmark data).
- External edits: `DispatchSource.makeFileSystemObjectSource` watcher; reload when there are no unsaved in-app changes; otherwise last-write-wins (in-app changes win on next save). Missing file → created on first write.

### 3. Todo window

- `WindowGroup(id: "todos")` in `ClipsmithApp.swift`, mirroring the snippets window (activation-policy switch to `.regular`, restore `.accessory` in `onDisappear`).
- **`TodoWindowView`** (`Clipsmith/Views/Todos/`) — tab strip: **Today** first (all `@today` items plus overdue/today `@due` items across projects), then one tab per project (Inbox included when non-empty). `Cmd-1…9` switches tabs. "+" affordance to add a project.
- **`TodoListView`** — task rows: checkbox, title, tag chips, due date (overdue highlighted red). Keyboard: `⌘N` new task (inline edit row), `Space` toggle done on selection, `⌘⌫` delete, `⌘F` focus search, `⇧⌘H` toggle show-completed, arrows navigate. Search uses existing `FuzzyMatcher`; `@tag` query terms match tags.
- ViewModel (`TodoWindowViewModel`) holds tab selection, search text, show-completed flag, filtered items — pure state, testable.

### 4. Quick-add bezel

- **`TodoQuickAddController`** — small non-activating `NSPanel` (stripped-down `BezelController` pattern: `.nonactivatingPanel`, high window level, click-outside + Escape dismissal). Single text field.
- Inline parsing (Todoist-style): `Fix pricing page #lara @due(2026-09-05) @today` → project `lara` (case-insensitive match against existing projects; unmatched `#name` creates the project), remaining `@tags` attached, rest is the title. No `#project` → Inbox.
- Enter saves via `TodoStore` and dismisses; Escape cancels. Parsing lives in a testable `TodoQuickAddParser` type.

### 5. Wiring (existing conventions)

- `KeyboardShortcutNames.swift`: `.openTodos`, `.todoQuickAdd`.
- `HotkeySettingsTab.swift`: two recorders, shown only when the flag is on.
- `AppDelegate.applicationDidFinishLaunching`: register both hotkeys; handlers guard on `todoTrackingEnabled` at invocation site (project convention).
- `MenuBarView.swift`: `.clipsmithOpenTodos` notification name + "Todos…" button behind the flag; AppDelegate observer opens the window (same `activateAsRegularApp` + `openWindow` dance as snippets).
- `AppSettingsKeys.swift`: `todoTrackingEnabled` (default false), `todoFilePath`/bookmark, `todoShowCompleted`.
- Settings: Features toggle in `GeneralSettingsTab`; new `TodoSettingsSection.swift` (file path picker with "Reveal in Finder", reset to default).
- `project.pbxproj`: continue sequential AA/AF ID scheme.

## Error handling

- Unreadable/corrupt file: parser never throws on content — every line lands somewhere (task, project, or verbatim note). I/O errors surface as a non-blocking alert in the todo window; store keeps in-memory state.
- File deleted externally: watcher detects, store keeps memory state, recreates file on next save.
- Security-scoped bookmark stale: fall back to default path, show notice in Settings section.

## Testing (TDD, XCTest)

- **`TaskPaperParserTests`** — spec conformance cases, tag parsing (with/without values), indentation, round-trip byte-fidelity on real-world sample files, malformed input preserved.
- **`TodoStoreTests`** — CRUD, done-toggle writes correct `@done(date)`, debounced save produces expected file content, external-change reload, missing-file creation (temp dirs).
- **`TodoQuickAddParserTests`** — `#project` extraction, `@tag`/`@tag(value)` extraction, plain text → Inbox, unmatched project creation semantics.
- **`TodoWindowViewModelTests`** — tab list derivation (Today first), Today-view filtering (`@today` + overdue), search filtering, show-completed toggle, selection navigation.

## New files

| File | Purpose |
|---|---|
| `Services/TaskPaperParser.swift` | Model types + parser + serializer |
| `Services/TodoStore.swift` | Document ownership, CRUD, file I/O, watcher |
| `Services/TodoQuickAddParser.swift` | Quick-add inline syntax parsing |
| `Views/Todos/TodoWindowView.swift` | Window container + project tabs |
| `Views/Todos/TodoListView.swift` | Task list, rows, keyboard handling |
| `Views/Todos/TodoWindowViewModel.swift` | Tab/filter/selection state |
| `Views/Todos/TodoQuickAddController.swift` (+ small view) | Quick-add NSPanel |
| `Views/Settings/TodoSettingsSection.swift` | File path picker, defaults |
| 4 test files | As listed above |

Touched: `AppDelegate.swift`, `ClipsmithApp.swift`, `MenuBarView.swift`, `KeyboardShortcutNames.swift`, `AppSettingsKeys.swift`, `HotkeySettingsTab.swift`, `GeneralSettingsTab.swift`, `SettingsView.swift` (if section gets a tab slot), `project.pbxproj`, `CHANGELOG.md` (Unreleased).
