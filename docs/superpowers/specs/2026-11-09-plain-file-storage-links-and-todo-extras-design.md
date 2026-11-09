# Plain-file storage, wiki links, todo extras

## Why

Snippets are turning into a personal wiki. Adam wants the notes **grepable**:
plain files on disk he can `rg`, keep in git, or sync with iCloud. Todos are
already a plain TaskPaper file; snippets should follow. Both live in one
configurable folder, default `~/.config/clipsmith`.

## Stage 1 — Folder storage

- Setting **Data folder** (`AppSettingsKeys.dataFolderPath`, empty = default
  `~/.config/clipsmith`), in Settings > General. Changing it switches both
  stores to the new folder; files are not moved (the folder may already be a
  repo with content).
- Todos: `<folder>/todos.taskpaper`. The existing `todoFilePath` override still
  wins when set (custom paths are left alone).
- Snippets: `<folder>/snippets/<name>.<ext>`, one file per snippet.
  - The file name *is* the name. Characters a file name can't hold (`/`, `:`,
    leading `.`) are replaced with `-` in the name itself when saving, so
    name and file always agree.
  - Extension from language (`markdown` → `md`, `python` → `py`, plain → `txt`,
    …) and back; unknown extensions load as plain text and keep their
    extension.
  - Tags: a header only when there are tags, exactly three lines
    `---` / `tags: [a, b]` / `---`. Anything else at the top is content (so
    a YAML document starting with `---` is not eaten). Obsidian reads this
    header. Pasting never includes it.
  - updated = file modification date, created = file creation date.
  - Names unique case-insensitively (as today, and as macOS compares file
    names). Two files with the same stem and different extensions are legal
    on disk; they show the existing duplicate-name warning.
- Clipsmith watches the folder (FSEvents) and rescans on change: edits, new
  and deleted files made in an editor show up. Our own writes are recognised
  by modification date and ignored. Last save wins, like todos.
- `SnippetStore` becomes a `@MainActor @Observable` file-backed store with the
  same operations (save/insertUnique/findOrCreate/delete/isNameTaken…), ids
  are in-memory UUIDs kept stable across rescans by file path. SwiftData
  `Snippet` stays in the schema, unused except by migration.
- Migration, once (`snippetsMigratedToFiles` flag): every SwiftData snippet is
  written to the folder (name collisions get " 2"); SwiftData rows are kept as
  a backup. The todo file moves from the old default
  (`~/Library/Application Support/Clipsmith/todos.taskpaper`) to the new one
  when there's no custom path and the new file doesn't exist.

## Stage 2 — Links

- **Backlinks**: the snippet detail shows "Referenced by N" — todos and other
  snippets whose text contains `[[name]]`; clicking one opens it (todo → Todos
  section selecting it; snippet → select it).
- **`[[` autocomplete** in the todo inline editor, new-task field and quick-add
  bezel: typing `[[` plus letters lists matching snippet names; ↑/↓ + Return
  or Tab completes to `[[Name]]`.
- **Snippet → snippet links**: `[[Other]]` in a rendered markdown snippet is a
  link; clicking opens (or creates) that snippet. A rename rewrites `[[old]]`
  in every snippet file as well as the todo file.

## Stage 3 — Todo extras

- **Due notifications**: one local notification per open task with a due
  date, at a fixed time on the due day (default 09:00, Settings > Todos).
  Rescheduled whenever the document changes. Dates stay date-only (a time in
  `@due()` would break the string date comparisons the Today view uses).
  Only while Todo Tracking is enabled.
- **Natural dates**: `@due(today|tomorrow|mon…sun|+3d|+2w)` is rewritten to
  ISO `@due(YYYY-MM-DD)` when a task is added or edited. Weekday = next
  occurrence after today.
- **Repeating**: completing a task with `@every(day|week|month|Nd|Nw)` and a
  due date appends a fresh copy with the due date advanced (from the old due
  date) and no `@done`.
- **Capture context**: the quick-add hotkey grabs the selected text (existing
  `SelectedTextService`) and, when the frontmost app is Safari or a Chromium
  browser, the current tab URL (Apple Events; needs the automation
  entitlement + usage string). Captured text goes in as a note under the new
  task; quick-add shows it and lets it be cleared.

## Non-goals

Sync service, nested folders for snippets, times in `@due`, moving files when
the data folder changes, deleting the SwiftData backup.
