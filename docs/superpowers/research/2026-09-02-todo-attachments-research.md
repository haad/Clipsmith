# Research: rich context for plain-text todo items

## 1. TaskPaper 3 (Hog Bay Software / Jesse Grosjean)

**Mechanism.** TaskPaper auto-links two things by regex over plain text, no special syntax required:
- Bare URLs (`www.example.com`, `https://...`) — rendered clickable inline.
- Paths: anything starting with `/` (absolute) or `./` (relative to the saved `.taskpaper` file's location) is recognized as a path and read until whitespace; spaces inside a path are escaped with a backslash (`./my\ file.txt`). Legacy `file:///` URLs still parse but only as absolute paths — no `./` support in that form.
- Forward slashes are used even for cross-platform/Dropbox-shared files (vs. Windows backslashes) so links keep working when shared with other outliners (e.g. PlainTasks).
- Click behavior differs by distribution: the direct-download build opens the file in its associated app; the Mac App Store build (sandboxed) can only reveal it in Finder — a sandboxing tax directly relevant to Clipsmith's own (currently non-sandboxed) status.
- No native image support and no URL scheme (`taskpaper://`) — confirmed by the developer on the support forum ("I never got around to adding a URL scheme to WriteRoom and TaskPaper 3"). No anchor/text-search linking into a file either (requested, not built).
- Notes (free-text lines under a task) are the only built-in place for longer text; they are plain, unrendered/unstyled lines — exactly Clipsmith's current model.

**Good at:** zero-syntax, keeps the file 100% plain text, works untouched in any editor, cross-app compatible because it's just filesystem paths.

**Breaks down at:** no image embedding, no deep-linking to a specific task (only whole-file), sandboxing neuters "open" to "reveal," no anchors within a linked file, community has to patch deep-linking via Keyboard Maestro macros triggering search-and-filter (fragile, per-user).

Citations: https://guide.taskpaper.com/reference/links/ (fetch blocked, 401), https://support.hogbaysoftware.com/t/linking-taskpaper-files/998, https://support.hogbaysoftware.com/t/url-scheme/3533, https://forum.zettelkasten.de/discussion/253/taskpaper-syntax-indentation-and-link-formatting-for-notes

## 2. Org-mode: org-attach

**Mechanism.** Every heading (node) can get a per-node attachment directory:
- Default: keyed by the heading's `ID` property, hashed into a shared `data/` directory next to the `.org` file (e.g. `data/3f/<rest-of-id>/`). This is fully automatic — no folder naming decision needed.
- Alternative: a `DIR` property pins an explicit directory to the node instead of using the ID hash.
- When org-attach adds the first file, it stamps the heading with an `:ATTACH:` tag — a purely visual/queryable marker ("this node has attachments"), not itself a pointer.
- Files inside the attachment dir are referenced from the node's text with `[[attachment:filename]]` links, e.g. `[[attachment:screenshot.png]]` — resolved relative to that node's attachment directory, so the link text stays short regardless of the real (hashed) path.
- Commands exist to attach a file by copy/move/link/URL-download, to attach a full Dired selection, and to attach a screenshot directly (`org-attach-screenshot`, platform tool dependent). Optional git integration auto-commits the `data/` directory.

**Good at:** clean separation of "one heading, one bag of files," survives node renaming (dir keyed by immutable ID not by title/position), the `:ATTACH:` tag makes "which tasks have attachments" a trivial search/filter, screenshot-to-attach is a first-class flow.

**Breaks down at:** requires a companion `data/` directory tree beside the text file — the "plain text file" is no longer self-contained, doesn't travel as a single file (e.g. can't just email the `.org` file and have attachments come along), the ID-hash directory naming is unreadable outside Emacs/org tooling, doesn't transfer to a flat, non-nested TaskPaper file as cleanly since org relies on heading nesting + drawers/properties that TaskPaper's syntax doesn't have.

Citations: https://orgmode.org/manual/Attachments.html, https://orgmode.org/manual/Attachment-links.html, https://orgmode.org/manual/Attachment-defaults-and-dispatcher.html, https://orgmode.org/manual/Attach-from-Dired.html

Org link syntax more broadly (for comparison): `[[target][description]]`, e.g. `[[https://example.com][GNU Emacs]]`; internal links via `[[#custom-id]]` matching a `:CUSTOM_ID:` property, or `id:` links to a heading's `:ID:` property (stable across moves/renames — this is the org mechanism closest to "durable pointer to a specific item" that a lean-task-plus-linked-snippet design wants). Source: https://orgmode.org/guide/Hyperlinks.html, https://orgmode.org/manual/Internal-Links.html

## 3. todo.txt

**Mechanism.** The spec (todotxt/todo.txt on GitHub) reserves a generic `key:value` extension slot at the end of a task line, after priority/date/description/+project/@context: "Developers should use the format key:value to define additional metadata (e.g. due:2010-01-02)." Constraints: key and value are each non-whitespace, colon-free runs; exactly one colon splits them; multiple key:value pairs are allowed per line.
- No key is reserved for notes/links/attachments in the base spec — `due:`, `t:` (threshold date), `rec:` (recurrence) are the conventional ones that emerged. There is no ecosystem-wide `note:` or `link:` convention; apps that want richer context invent their own key or bolt on separate storage.
- Todo.txt ecosystem apps (Simpletask, Todo.txt Touch, various) generally do NOT extend into rich attachments — the format's whole philosophy is "one flat line, everything else is out of scope." Where apps need notes, they've historically stored them out-of-band (app-specific databases) rather than in the txt file, defeating plain-text portability for that content.

**Good at:** absolute minimalism, one line = one task, trivially parseable/grep-able, key:value is generic enough to carry a pointer key like `snippet:<id>` without spec violation.

**Breaks down at:** no standard for what a "rich" key should look like, so cross-app interop for anything beyond dates is nonexistent — every app picks its own keys and no other app honors them; no notion of a note/body at all (unlike TaskPaper, todo.txt has no multi-line task concept).

Citations: https://github.com/todotxt/todo.txt (README/spec), https://github.com/todotxt/todo.txt/issues/85 (issue title alone confirms "extra metadata tags" was contentious/discussed, full thread not retrievable)

## 4. Taskwarrior

**Mechanism.** Two distinct primitives:
- **Annotations** — free-text timestamped notes attached to a task (`task 12 annotate "waiting on legal review"`), stored internally as `annotation_<epoch>` keys, shown under the task. Unstructured, append-only, good for a log/journal of context but not queryable as structured data and not a place for a link with special handling.
- **UDAs (User Defined Attributes)** — task adds a formally-typed custom field: `task config uda.reference.type string`, `task config uda.reference.label Reference`, then `task add "Fix bug" reference:http://example.com`. UDA types are string/date/duration/numeric; each can get a default, an allowed-values list, and a report-column label. Once defined, UDAs behave like any built-in attribute for filtering/sorting/reporting.
- No built-in file-attachment mechanism at all — the docs make clear file attachment isn't native; a UDA storing a path or URL is the closest thing, and it's just a string the user is responsible for resolving.

**Good at:** annotations = zero-friction append-only context capture; UDAs = structured, typed, reportable metadata — closest of all the systems here to a genuine "pointer field" pattern (e.g. a UDA literally named `snippet` holding an ID).

**Breaks down at:** UDAs require schema setup (`task config`) before use — not zero-config like a todo.txt key:value; nothing renders a UDA's value specially (a UDA holding a URL is not clickable, a UDA holding a file path doesn't open the file) — the app has zero opinion about resolving the pointer, that's entirely on tooling built on top.

Citations: https://taskwarrior.org/docs/udas/, https://taskwarrior.org/docs/task/

## 5. NotePlan / Obsidian Tasks / Logseq (markdown-based)

**NotePlan.** Tasks are markdown checkboxes inside daily/project notes; rich context is provided by being IN a note, not by attaching to the checkbox line. Cross-referencing uses:
- `[[Note Title]]` wikilinks to jump to other notes (which is where the "rich content" actually lives).
- A full x-callback-url API (`noteplan://x-callback-url/<action>?...`) with actions like `openNote?noteTitle=...`; the "Link Creator" plugin gives a wizard (`/Get X-Callback-URL`) to build a callback URL to a specific note/heading and copy it — i.e., the same "copy link to item, paste elsewhere" pattern as Things/OmniFocus/Bear, but for notes rather than atomic tasks. Backlinks are automatic; a "link without a backlink" variant exists for casual references.

**Obsidian Tasks plugin.** The plugin itself only recognizes task lines (`- [ ] text 📅 date` etc.) inside otherwise normal markdown notes; there's no per-task attachment concept — the task's "rich context" is just: the rest of the note it lives in, plus whatever `![[image.png]]` embeds or `[[Note]]` wikilinks are near it in that note. Image handling is native Obsidian: paste/drag an image and it's copied into a configurable attachment folder, then embedded via `![[filename.png]]` (wiki-embed) or converted to standard markdown `![](path)` by community plugins if wiki-syntax is undesired.

**Logseq.** Block-based outliner; tasks are blocks with a TODO/DOING marker. Rich context options: `{{embed [[page]]}}` / `{{embed ((block-uuid))}}` to pull in whole pages or specific blocks by UUID (finer-grained than Obsidian's file-level linking), and native image paste that copies the file into the local assets folder and inserts a markdown image reference automatically.

**Synthesis for this group:** all three separate "the task line" from "the rich content," but do it by co-location in a shared document/graph (wikilinks + backlinks) rather than an explicit task→attachment field. The image workflow (paste → auto-save to assets folder → auto-insert reference) is the most user-friction-free of everything surveyed and is the direct precedent for "paste a screenshot, get a link inserted automatically."

Citations: https://help.noteplan.co/article/49-x-callback-url-scheme, https://noteplan.co/plugins/np.CallbackURLs, https://help.noteplan.co/article/47-create-custom-links, https://help.obsidian.md/How+to/Embed+files, https://community.obsidian.md/plugins/image-link-updater, https://discuss.logseq.com/t/more-markdown-ish-syntax-to-embed-pages-blocks-etc/21681

## 6. macOS deep-linking pattern (Things, OmniFocus, Bear, Hookmark) + URL scheme registration

**Things.** `things:///show?id=today` and per-item: Control-click a to-do → Share → Copy Link produces `things:///show?id=<UUID>`. Clicking it brings Things to front and briefly highlights the exact to-do (yellow flash + haptic on iOS). This is the canonical "copy link to item" affordance other apps should mimic.

**OmniFocus.** `omnifocus:///task/<task-primary-key>` — same shape, exposed via an "Copy Link to Selected Object" Omni Automation plug-in and a scriptable `URL` class; works for task/project/tag/folder, not just tasks.

**Bear.** Full x-callback-url implementation: `bear://x-callback-url/open-note?id=<id>` (id or title-addressed), plus x-success/x-error round-trip parameters so a caller app can get data back, not just navigate. This is the most "API-like" of the schemes.

**Hookmark (formerly Hook).** Not app-specific — a cross-app linking layer. Invoked (⌃H or menu bar) over the frontmost window/document, it identifies "what kind of item is this" per-app and either fetches or synthesizes that app's native copy-link URL, then lets the user "hook" two items together bidirectionally (link A→B and B→A simultaneously) so invoking Hookmark on either one shows the other under "HOOKED." It also tracks moved files so links to file-system items keep resolving. Hookmark's own docs describe "principles that determine which URL scheme is returned for Copy Link" per app — i.e., it's essentially a directory + resolver for other apps' schemes, plus its own hook-graph for items that have no scheme at all (arbitrary files, Finder items).

**Registering a scheme on macOS (non-sandboxed relevant too).** `Info.plist` needs a `CFBundleURLTypes` array entry with `CFBundleURLName` (a reverse-DNS identifier) and `CFBundleURLSchemes` (array of scheme strings, e.g. `clipsmith`). LaunchServices auto-registers it from the bundle at build/first-run — no separate registration step or entitlement needed, and this works identically whether or not the app is sandboxed (sandboxing affects what the app can *do* once launched via the URL, not whether it can register/receive one). Handling side: implement `NSApplicationDelegate.application(_:open:)` (`open urls: [URL]`) for macOS 10.13+. Concretely for Clipsmith: register `clipsmith://` (or similar), support `clipsmith:///snippet/<id>` and `clipsmith:///task/<taskID>` show-actions, and add a "Copy Link" action on both snippets and tasks that puts that URL on the pasteboard — this is the mechanism that makes "task ↔ snippet" a real bidirectional link rather than a fragile string match.

Citations: https://culturedcode.com/things/help/url-scheme/, https://culturedcode.com/things/blog/2018/02/hey-things/, https://inside.omnifocus.com/url-schemes, https://www.omni-automation.com/omnifocus/plug-in-copy-link-to-object.html, https://bear.app/faq/x-callback-url-scheme-documentation/, https://hookproductivity.com/help/integration/url-scheme-selection-principles/, https://setapp.com/how-to/link-items-in-apps-with-hookmark, https://wiki.lazarus.freepascal.org/macOS_File_and_Custom_URL_Scheme_Associations, https://gist.github.com/mralexgray/3915592

## 7. Screenshots/images with plain-text todos — established patterns

Three recurring shapes across everything above:
1. **Sidecar attachment directory keyed by node identity** (org-attach): `data/<hash-of-ID>/`, referenced by a short `[[attachment:name]]` link. Directory travels with the text file but is a second thing on disk.
2. **Vault-relative attachment folder + auto-insert on paste** (Obsidian, Logseq, and by extension NotePlan): a single well-known folder (commonly `attachments/` or `assets/`) holds all pasted images for the whole vault/file-tree, not per-node; pasting an image auto-copies it there and inserts a `![[name.png]]` / `![](path)` reference at the cursor. This is the friction-minimal, user-facing gold standard for "screenshot → in my notes" and is exactly the gesture a modern user expects (paste image, get inline reference), but it externalizes to a shared folder rather than one folder per task.
3. **No native handling, delegate entirely to the OS file system** (TaskPaper, todo.txt, Taskwarrior): none of these render or embed images; a screenshot becomes "a file somewhere, referenced by a path/URL string," and the burden of capturing/saving/naming it is entirely on the user or an external tool (e.g. macOS screenshot utility saving to Desktop, then the user manually typing/dragging a `./` path into TaskPaper).

Given Clipsmith already has a snippet library with its own storage (SwiftData) and a bezel-paste UX, it is better positioned than any of these systems: it doesn't need a sidecar folder or a vault convention at all, because "paste image → save into an existing rich store → insert a lightweight pointer" is a solved sub-problem already (the snippet library), and the "insert a lightweight pointer" half is exactly the deep-link pattern from Things/OmniFocus/Bear (section 6), not a filesystem path.

---

## Synthesis: the recurring patterns

**Pattern A — Inline URL/path + app deep-link scheme.**
Examples: TaskPaper's auto-linked `./relative/path` and bare URLs; Things/OmniFocus/Bear's `app:///show?id=...` copy-link; NotePlan's x-callback-url.
- Plain-text purity: near-total — the task line stays one line, the "rich" thing is a URL string sitting in it (or in its note line).
- Externalizes: the actual content lives entirely outside the todo file — another app, another file, or another record.
- Editor interop: excellent — in vim/grep the line reads as `- task @tag(...) https://... ` or a path; a human can still follow it manually (path) or with less certainty (opaque UUID-bearing app URL, which means nothing to `cat` or grep-by-content, only grep-by-ID).
- Image handling: none built in; images are just files a path happens to point at, or not handled at all (Things/Bear schemes point at structured data, not images).

**Pattern B — Sidecar attachment directory keyed by node/task identity.**
Example: org-attach (`data/<ID-hash>/`, `:ATTACH:` tag, `[[attachment:file]]` link).
- Plain-text purity: partial — the `.org`/text file itself stays plain, but "the todo system" now means file + directory tree, so a single `.taskpaper`-equivalent file no longer represents the whole world.
- Externalizes: binary content to per-node folders; keeps a strong 1:1 ownership relationship (delete the node, you know which folder to clean up).
- Editor interop: fine for the text (still just a link string), but the directory-of-directories requires org-attach-aware tooling to be legible/navigable at all — a human in Finder sees hashed folder names, not task titles.
- Image handling: explicit first-class support (`org-attach-screenshot` et al.), best-in-class for "task has 1-3 files that conceptually belong only to it."

**Pattern C — key:value pointer to an external store.**
Examples: todo.txt's generic `key:value` extension slot; Taskwarrior UDAs (`reference:<url>` or a typed `snippet:<id>` field).
- Plain-text purity: total, and arguably the cleanest of all — it's still exactly one line, and the key namespace is generic so a new key (e.g. `snippet:`) doesn't break the format or existing parsers (unknown keys are just inert extra text/metadata to older tooling).
- Externalizes: 100% of the rich content, to whatever store the app defines; the todo file holds only an ID/foreign key.
- Editor interop: excellent for reading task text, but the pointer itself (a bare ID or UUID) is meaningless to a human without the owning app open — grep finds it, nobody can *use* it standalone the way a `./path` or URL can be opened directly.
- Image handling: none directly; entirely deferred to whatever the pointer resolves to.

**Pattern D — Notes-as-context, in-file.**
Examples: TaskPaper's own note lines (today, unrendered); Obsidian Tasks/Logseq/NotePlan's "the checkbox lives inside a normal note, so context is just prose/wikilinks/embeds around it in the same document."
- Plain-text purity: total for TaskPaper's flavor (still literally the same file, same tab/indent grammar); Obsidian/Logseq's flavor blends this with Pattern A (embeds pull in the vault's attachment folder).
- Externalizes: nothing, by design — this is the "don't externalize" pole of the spectrum, everything is prose in the file, so it doesn't need any resolver, but it also can't hold binary content (images) without borrowing Pattern B/A machinery, and it makes the "task" file bigger and messier for content-rich items — the exact problem the driving idea in this brief is trying to avoid.

## Which pattern(s) fit "lean task + rich context in a linked snippet"

**Pattern C (key:value pointer) + Pattern A (deep-link URL), combined, is the right fit — and it's close to what Clipsmith is already positioned to do uniquely well.**

Concretely: keep the TaskPaper task line lean with a tag like `@snippet(<snippet-id>)` (pure Pattern C — a typed, generic, namespaced pointer, exactly like Taskwarrior's `reference:` UDA or todo.txt's `key:value` slot, and it round-trips byte-exact since it's just another `@tag(value)` TaskPaper already understands). Then register a `clipsmith://` URL scheme (Pattern A, per section 6) so the pointer is independently openable/shareable outside the app too — e.g. `clipsmith:///snippet/<id>` could be the value, or the tag could hold a bare ID and the app resolves it internally, with a "Copy Link" affordance on the snippet side for symmetry with Things/OmniFocus/Bear.

Why this beats the alternatives for Clipsmith specifically:
- Pattern B (sidecar directory) is redundant — Clipsmith already has a rich, syntax-highlighted store (SwiftData snippet library) that's a better home for long text/code/images than a folder of files ever would be, and it avoids introducing a second on-disk artifact next to the TaskPaper file (no `data/` tree to keep in sync, back up, or explain to the user).
- Pattern D (notes-as-context) is what the brief explicitly wants to avoid for content-rich tasks — it's the "make the todo format rich" path, and it doesn't solve images at all without bolting on B or A anyway. It's still fine, unchanged, for short free-text notes (Clipsmith's current unrendered note lines) — nothing here says notes should go away, just that they shouldn't be asked to carry images/long-form content.
- Pure Pattern A (bare path/URL, no app-owned store) fails the "image" requirement cleanly and fails "long description" moderately — TaskPaper already proves this is the status quo (no image support, developer explicitly never built a URL scheme), which is presumably part of why this redesign is happening.
- The pointer stays inert to any other TaskPaper-reading tool (a generic `@snippet(id)` tag is exactly as safe as any other custom tag TaskPaper users already invent), while the `clipsmith://` scheme makes the link resolvable/shareable the same way Things/OmniFocus/Bear links are — satisfying both "stays plain-text-pure" and "not a dead end outside the app."
