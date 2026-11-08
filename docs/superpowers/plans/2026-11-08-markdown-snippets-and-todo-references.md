# Markdown Snippets and Todo Snippet References Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Markdown snippets render formatted (with an Edit toggle and selection-aware paste), and todos can reference snippets by `[[Name]]`, with references following snippet renames and snippet names kept unique.

**Architecture:** Pure helpers (reference parsing, unique names, paste choice, markdown→HTML) carry the logic and the tests; SwiftUI views stay thin. Markdown renders in a `WKWebView` sharing the Docs stylesheet. A todo reference opens the browser through the existing `BrowserOpenRequest` path; the Snippets section consumes a pending name the way Docs consumes `pendingDocsQuery`. Renames rewrite the todo file through `TodoStore`, so the normal debounced save and file watcher apply.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, WebKit, XCTest, `swift-markdown` (new SPM dependency), `HighlightSwift` (existing).

**Spec:** `docs/superpowers/specs/2026-11-08-markdown-snippets-and-todo-references-design.md`

## Global Constraints

- macOS 15+, Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`; UI types `@MainActor`, value types `Sendable`.
- No SwiftData schema change (no V4, no `.unique` attribute).
- Only snippets with `language == "markdown"` get the rendered view and selection-aware paste. Code snippets behave exactly as today.
- Paste is always plain text. No selection → full raw `content`.
- The todo file holds names only: `[[Snippet name]]`, verbatim. `TaskPaperParser` is not changed.
- Name matching for references and uniqueness is case-insensitive exact match on the whole name.
- New `.swift` files must be added to `Clipsmith.xcodeproj/project.pbxproj` by hand: next free IDs are `AA0130`/`AF0130` upward (build file / file ref, same number per file), `SP0005`+ for packages. Add each file to its group and to the target's Sources phase, mirroring `TodoStore.swift` (`AA0105`/`AF0105`).
- Build: `xcodebuild build -scheme Clipsmith -destination 'platform=macOS'`. Tests: `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' [-only-testing:ClipsmithTests/<Suite>]`.
- Tests never write `NSPasteboard.general` and never call `PasteService.paste`.

## Review Focus

1. A reference whose snippet was renamed while the todo file has unsaved in-app edits: the rewrite must apply to the in-memory document and save with it (TodoStore Task 2 test `testRenameReferencesWhileDirty`).
2. Renaming to a name that differs only in case (`xyz` → `XYZ`): not a collision with itself, references are rewritten to the new casing (Task 3 `testNameTakenIgnoresSelf`, Task 2 `testRenameReferencesCaseOnly`).
3. `[[` without a closing `]]`, empty `[[]]`, and `[[a]] and [[b]]` on one line: parsed sanely, no crash (Task 1 tests).
4. A reference clicked while the Snippets search or language filter would hide the target: the filter is cleared so the selected snippet is visible (Task 8 manual check).
5. ⌘↩ with a stale selection in a code snippet's editor still pastes the whole snippet (Task 6 `testCodeSnippetIgnoresSelection`).

---

### Task 0: Commit the outstanding work on a feature branch

The spec's precondition. The working tree holds unrelated finished work from 2026-11-07/08.

- [ ] **Step 1:** `git switch -c feature/markdown-snippets-todo-refs`
- [ ] **Step 2:** Run the full suite. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 3:** Commit in three commits, each ending with the attribution line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`:
  - `feat(todos): edit tasks, move between projects, All view, drag onto project chips` — `TodoStore.swift`, `TodoListView.swift`, `TodoWindowViewModel.swift`, `TodosSectionView.swift`, `BrowserPanes.swift`, both todo test files.
  - `fix: launcher glass border on macOS 26; ⌘N survives section switches; stop tests pasting` — `AppLaunchController.swift`, `AppLaunchView.swift`, `SnippetsSectionView.swift`, `PromptsSectionView.swift`, removal of `SnippetPasteTests.swift` and its pbxproj lines.
  - `docs: markdown snippets and todo references design + plan` — the spec and this plan.
  - `Clipsmith.xcscheme` is modified in the tree but not by this session: show `git diff` of it to Adam and leave it uncommitted unless he says otherwise.

---

### Task 1: Snippet reference parsing

**Files:**
- Create: `Clipsmith/Services/SnippetReference.swift`
- Test: `ClipsmithTests/SnippetReferenceTests.swift`

**Interfaces:**
- Produces:
  - `enum SnippetReference` (namespace, `Sendable`)
  - `enum SnippetReference.Segment: Equatable, Sendable { case text(String); case reference(String) }`
  - `static func segments(in text: String) -> [Segment]`
  - `static func names(in text: String) -> [String]` (in order, duplicates kept)
  - `static func rewriting(_ text: String, from oldName: String, to newName: String) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
func testSegmentsSplitTextAndReferences() {
    XCTAssertEqual(SnippetReference.segments(in: "Write a blog about [[xyz]] soon"),
                   [.text("Write a blog about "), .reference("xyz"), .text(" soon")])
}
func testTwoReferencesOnOneLine() {
    XCTAssertEqual(SnippetReference.names(in: "[[a]] and [[b]]"), ["a", "b"])
}
func testUnclosedAndEmptyAreText() {
    XCTAssertEqual(SnippetReference.segments(in: "x [[open"), [.text("x [[open")])
    XCTAssertEqual(SnippetReference.names(in: "[[]] and [[  ]]"), [])
}
func testNameIsTrimmed() {
    XCTAssertEqual(SnippetReference.names(in: "[[ xyz ]]"), ["xyz"])
}
func testRewriteIsCaseInsensitiveAndLeavesOthers() {
    XCTAssertEqual(
        SnippetReference.rewriting("- see [[XYZ]] and [[xyzzy]] @today", from: "xyz", to: "Blog notes"),
        "- see [[Blog notes]] and [[xyzzy]] @today")
}
func testRewriteMatchesTrimmedName() {
    XCTAssertEqual(SnippetReference.rewriting("[[ xyz ]]", from: "xyz", to: "abc"), "[[abc]]")
}
```

- [ ] **Step 2:** Run `-only-testing:ClipsmithTests/SnippetReferenceTests`. Expected: build failure, `SnippetReference` not found.
- [ ] **Step 3: Implement** with a non-greedy regex `\[\[([^\[\]]*)\]\]`; a match whose trimmed capture is empty is left as text. `rewriting` rebuilds only matching references (trimmed, `caseInsensitiveCompare == .orderedSame`) and leaves every other character untouched. Add both files to the pbxproj.
- [ ] **Step 4:** Run the suite again. Expected: PASS.
- [ ] **Step 5:** Commit `feat(todos): parse [[snippet]] references`.

---

### Task 2: Rewrite references in the todo file

**Files:**
- Modify: `Clipsmith/Services/TodoStore.swift` (Task CRUD section)
- Test: `ClipsmithTests/TodoStoreTests.swift`

**Interfaces:**
- Consumes: `SnippetReference.rewriting(_:from:to:)`
- Produces: `TodoStore.renameSnippetReferences(from oldName: String, to newName: String)`. Rewrites task lines and note lines in every project. Marks the store dirty only when something changed. Task ids are kept.

- [ ] **Step 1: Write the failing tests** (use the existing `makeStore(initialContent:)` / `fileContent(of:)` helpers)

```swift
func testRenameReferencesRewritesTasksAndNotes() {
    let store = makeStore(initialContent: "- blog [[xyz]]\nWork:\n- ship [[XYZ]] @today\n\tsee [[xyz]]\n")
    let ids = store.document.allTasks.map(\.id)
    store.renameSnippetReferences(from: "xyz", to: "Blog notes")
    store.saveNow()
    XCTAssertEqual(fileContent(of: store),
                   "- blog [[Blog notes]]\nWork:\n- ship [[Blog notes]] @today\n\tsee [[Blog notes]]\n")
    XCTAssertEqual(store.document.allTasks.map(\.id), ids)
}
func testRenameReferencesNoMatchIsNoOp() {
    let store = makeStore(initialContent: "- plain task\n")
    store.renameSnippetReferences(from: "xyz", to: "abc")
    XCTAssertFalse(store.hasPendingChanges)
}
func testRenameReferencesCaseOnly() {
    let store = makeStore(initialContent: "- [[xyz]]\n")
    store.renameSnippetReferences(from: "xyz", to: "XYZ")
    XCTAssertEqual(store.document.allTasks[0].rawLine, "- [[XYZ]]")
}
func testRenameReferencesWhileDirty() {
    let store = makeStore(initialContent: "- [[xyz]]\n")
    store.addTask(text: "new [[xyz]]", projectName: nil)
    store.renameSnippetReferences(from: "xyz", to: "abc")
    store.saveNow()
    XCTAssertEqual(fileContent(of: store), "- [[abc]]\n- new [[abc]]\n")
}
```

- [ ] **Step 2:** Run `-only-testing:ClipsmithTests/TodoStoreTests`. Expected: build failure, missing method.
- [ ] **Step 3: Implement** by mapping each `TodoNode`: `.task(item)` → `TodoItem(rawLine: rewritten, id: item.id)`, `.note(line)` → `.note(rewritten)`. Call `markDirty()` once, and only if any line changed.
- [ ] **Step 4:** Run again. Expected: PASS.
- [ ] **Step 5:** Commit `feat(todos): rewrite [[snippet]] references on rename`.

---

### Task 3: Unique snippet names in the store

**Files:**
- Modify: `Clipsmith/Services/SnippetStore.swift`
- Modify: `Clipsmith/Services/SnippetFilter.swift` (pure helpers live with the other snippet filters)
- Test: `ClipsmithTests/SnippetStoreTests.swift`, `ClipsmithTests/SnippetFilterTests.swift`

**Interfaces:**
- Produces:
  - `SnippetStore.insert(...)` becomes `@discardableResult func insert(name:content:language:tags:) throws -> PersistentIdentifier`. Existing call sites are unchanged.
  - `SnippetStore.isNameTaken(_ name: String, excluding id: PersistentIdentifier?) throws -> Bool`
  - `SnippetStore.availableName(base: String) throws -> String`. Returns `base` if it's free, else `"<base> 2"`, `"<base> 3"`, …
  - `SnippetStore.findByName(_ name: String) throws -> PersistentIdentifier?`. Most recently updated match.
  - `SnippetFilter.duplicateNames(_ names: [String]) -> Set<String>`. Lowercased names that occur more than once.
  - `SnippetFilter.bestMatch(named name: String, in snippets: [ClipsmithSchemaV1.Snippet]) -> ClipsmithSchemaV1.Snippet?`. Case-insensitive, largest `updatedAt` wins.

- [ ] **Step 1: Write the failing tests**

```swift
// SnippetStoreTests
func testNameTakenIsCaseInsensitive() async throws {
    let store = SnippetStore(modelContainer: try makeTestContainer())
    try await store.insert(name: "Blog Notes", content: "", language: nil, tags: [])
    let taken = try await store.isNameTaken("blog notes", excluding: nil)
    XCTAssertTrue(taken)
}
func testNameTakenIgnoresSelf() async throws {
    let store = SnippetStore(modelContainer: try makeTestContainer())
    let id = try await store.insert(name: "xyz", content: "", language: nil, tags: [])
    let taken = try await store.isNameTaken("XYZ", excluding: id)
    XCTAssertFalse(taken)
}
func testAvailableNameAppendsCounter() async throws {
    let store = SnippetStore(modelContainer: try makeTestContainer())
    try await store.insert(name: "Untitled Snippet", content: "", language: nil, tags: [])
    try await store.insert(name: "Untitled Snippet 2", content: "", language: nil, tags: [])
    let name = try await store.availableName(base: "Untitled Snippet")
    XCTAssertEqual(name, "Untitled Snippet 3")
}
func testFindByNamePicksMostRecentlyUpdated() async throws {
    let store = SnippetStore(modelContainer: try makeTestContainer())
    let older = try await store.insert(name: "dup", content: "old", language: nil, tags: [])
    let newer = try await store.insert(name: "DUP", content: "new", language: nil, tags: [])
    try await store.update(id: older, name: "dup", content: "old!", language: nil, tags: [])
    let found = try await store.findByName("Dup")
    XCTAssertEqual(found, older)
    _ = newer
}
// SnippetFilterTests
func testDuplicateNames() {
    XCTAssertEqual(SnippetFilter.duplicateNames(["a", "A", "b", "c", "c "]), ["a"])
}
```

- [ ] **Step 2:** Run `-only-testing:ClipsmithTests/SnippetStoreTests -only-testing:ClipsmithTests/SnippetFilterTests`. Expected: build failure.
- [ ] **Step 3: Implement.** Fetch all snippets and compare in Swift with `caseInsensitiveCompare`. Don't use a `#Predicate`: it can't do case-insensitive equality reliably, and the data set is small. Names are compared as stored, without trimming, so the `"c "` case above is not a duplicate of `"c"`.
- [ ] **Step 4:** Run again. Expected: PASS.
- [ ] **Step 5:** Commit `feat(snippets): unique-name helpers in SnippetStore`.

---

### Task 4: Editor enforces unique names and rewrites references on rename

**Files:**
- Modify: `Clipsmith/Views/Snippets/SnippetEditorView.swift` (`saveSnippet`, name row)
- Modify: `Clipsmith/Views/Browser/SnippetsSectionView.swift` (`createNewSnippet`, `snippetRow`)

**Interfaces:**
- Consumes: `SnippetStore.isNameTaken`, `SnippetStore.availableName`, `TodoStore.renameSnippetReferences`, `SnippetFilter.duplicateNames`
- Produces: nothing new for later tasks.

- [ ] **Step 1:** In `SnippetEditorView`, add `@Environment(TodoStore.self) private var todoStore` (the browser window already injects it) and `@State private var nameWarning: String?`.
- [ ] **Step 2:** Rework `saveSnippet()`:
  - Let `newName` be the trimmed name, or `snippet.name` if it's empty.
  - Let `oldName` be `snippet.name`, read before saving.
  - If `newName` is taken (excluding this snippet), save every other field with `oldName` and set `nameWarning = "Another snippet is already named “\(newName)”"`.
  - Otherwise save with `newName` and clear the warning. If `oldName != newName`, also call `todoStore.renameSnippetReferences(from: oldName, to: newName)`, even when only the case changed.
- [ ] **Step 3:** Show `nameWarning` under the Name field as a `.caption` in `.red`. Clear it in `loadFromSnippet()`.
- [ ] **Step 4:** `createNewSnippet()` inserts `try await store.availableName(base: "Untitled Snippet")` and selects the returned id. Today's `allSnippets.first` lookup is not needed.
- [ ] **Step 5:** In `snippetRow`, compute `SnippetFilter.duplicateNames(allSnippets.map(\.name))` once per body pass, not per row. For each row whose lowercased name is in that set, show `Image(systemName: "exclamationmark.triangle.fill")` in `.orange` with the help text `"Another snippet has the same name — rename one so [[links]] stay unambiguous"`.
- [ ] **Step 6:** Build, then run the full suite. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 7: Manual check.** Create two snippets. Renaming the second to the first's name shows the warning and the list keeps the old name. Add a todo `- read [[A]]`, rename snippet A to B, and the todo reads `[[B]]` within about a second.
- [ ] **Step 8:** Commit `feat(snippets): unique names; renames update todo references`.

---

### Task 5: Markdown → HTML

**Files:**
- Modify: `Clipsmith.xcodeproj/project.pbxproj`. Add package `https://github.com/swiftlang/swift-markdown` (`SP0005`, `upToNextMinorVersion` from the latest 0.x release that provides `HTMLFormatter`), product `Markdown` (`SP0006`), and build file `AA0131` (or the next free number) in the app target's Frameworks phase and `packageProductDependencies`. Mirror the existing HighlightSwift entries (`SP0003`/`SP0004`/`AA0036`).
- Create: `Clipsmith/Services/MarkdownRenderer.swift`
- Test: `ClipsmithTests/MarkdownRendererTests.swift`

**Interfaces:**
- Produces: `enum MarkdownRenderer { static func bodyHTML(from markdown: String) -> String }`. Returns an HTML fragment for `<body>`. Fenced code blocks come out as `<pre><code class="language-<lang>">`.

- [ ] **Step 1: Write the failing tests** (assert with `contains`, not exact HTML)

```swift
func testHeadingListEmphasis() {
    let html = MarkdownRenderer.bodyHTML(from: "# Title\n\n- one\n- **two**\n")
    XCTAssertTrue(html.contains("<h1>Title</h1>"))
    XCTAssertTrue(html.contains("<li>one</li>"))
    XCTAssertTrue(html.contains("<strong>two</strong>"))
}
func testFencedCodeKeepsLanguageClassAndEscapes() {
    let html = MarkdownRenderer.bodyHTML(from: "```swift\nlet a = 1 < 2\n```\n")
    XCTAssertTrue(html.contains(#"class="language-swift""#))
    XCTAssertTrue(html.contains("1 &lt; 2"))
}
func testTable() {
    let html = MarkdownRenderer.bodyHTML(from: "| a | b |\n|---|---|\n| 1 | 2 |\n")
    XCTAssertTrue(html.contains("<table>"))
    XCTAssertTrue(html.contains("<td>1</td>"))
}
func testLink() {
    XCTAssertTrue(MarkdownRenderer.bodyHTML(from: "[x](https://example.com)")
        .contains(#"<a href="https://example.com">x</a>"#))
}
```

- [ ] **Step 2:** Run `-only-testing:ClipsmithTests/MarkdownRendererTests`. Expected: build failure. The package resolves during the build, which needs network access.
- [ ] **Step 3: Implement** `HTMLFormatter.format(Document(parsing: markdown))`. If the resolved version's output differs from the asserted markup (e.g. the table wraps its rows in `<thead>`), loosen the assertion to the element that matters. Don't post-process the HTML.
- [ ] **Step 4:** Run again. Expected: PASS.
- [ ] **Step 5:** Commit `feat(snippets): markdown to HTML via swift-markdown`.

---

### Task 6: Rendered view, Edit toggle, selection-aware paste

**Files:**
- Modify: `Clipsmith/Views/Browser/DocWebView.swift`. Extract the inline `<style>` block into `static let docStyles: String` on a new `enum BrowserWebStyles` in the same file, so it can be reused. `DocWebView` output is unchanged.
- Create: `Clipsmith/Views/Snippets/MarkdownWebView.swift`
- Create: `Clipsmith/Views/Snippets/SnippetSelection.swift`
- Modify: `Clipsmith/Views/Snippets/HighlightedTextEditor.swift`. Accept an optional `SnippetSelection` and register its `NSTextView` with it in `makeNSView`.
- Modify: `Clipsmith/Views/Snippets/SnippetEditorView.swift`, `Clipsmith/Views/Browser/SnippetsSectionView.swift`
- Test: `ClipsmithTests/SnippetSelectionTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.bodyHTML(from:)`, `BrowserWebStyles.docStyles`
- Produces:
  - `@MainActor final class SnippetSelection`:
    - `weak var textView: NSTextView?`
    - `weak var webView: WKWebView?`
    - `func selectedText() async -> String?`. Returns the web view's selection when the rendered view is showing, otherwise the text view's. Returns nil when the selection is empty.
  - `enum SnippetPaste { static func content(full: String, language: String?, selection: String?) -> String }`. Pure. Returns the selection only for `language == "markdown"` with a non-empty selection, otherwise `full`.
  - `MarkdownWebView(markdown: String, selection: SnippetSelection)` (NSViewRepresentable)
  - `SnippetEditorView(snippet:snippetStore:isEditing:selection:)`, where `isEditing: Binding<Bool>`

- [ ] **Step 1: Write the failing tests** for the pure function

```swift
func testMarkdownUsesSelection() {
    XCTAssertEqual(SnippetPaste.content(full: "# all", language: "markdown", selection: "part"), "part")
}
func testEmptySelectionPastesFull() {
    XCTAssertEqual(SnippetPaste.content(full: "# all", language: "markdown", selection: ""), "# all")
    XCTAssertEqual(SnippetPaste.content(full: "# all", language: "markdown", selection: nil), "# all")
}
func testCodeSnippetIgnoresSelection() {
    XCTAssertEqual(SnippetPaste.content(full: "let a = 1", language: "swift", selection: "a"), "let a = 1")
}
```

- [ ] **Step 2:** Run `-only-testing:ClipsmithTests/SnippetSelectionTests`. Expected: build failure.
- [ ] **Step 3: Implement `SnippetPaste` and `SnippetSelection`.** The web view selection is read with `evaluateJavaScript("window.getSelection().toString()")`. The text view selection is `(textView.string as NSString).substring(with: textView.selectedRange())`.
- [ ] **Step 4: Implement `MarkdownWebView`.**
  - Page: `BrowserWebStyles.docStyles` + `MarkdownRenderer.bodyHTML`.
  - Links: external links open in the default browser, as in `DocWebView.Coordinator`.
  - Reload only when `markdown` changes. Keep the last HTML in the coordinator so the selection survives SwiftUI updates.
  - Code-block highlighting is the implementer's choice. It must work offline and follow light/dark mode, and must not add a second new dependency. Options: HighlightSwift output converted per `<code class="language-…">` block, or a highlight.js copy bundled as an app resource.
  - Register the web view with `selection.webView`.
- [ ] **Step 5: Wire the views.**
  - `SnippetEditorView`: if `language == "markdown" && !isEditing`, show `MarkdownWebView` in place of the "Source" editor. The name, language and tags rows stay as they are.
  - `SnippetsSectionView` state:
    - `@State isEditingMarkdown = false`, reset to `false` whenever the selected snippet changes.
    - `@State selection = SnippetSelection()`
  - Detail header: for markdown snippets, an `Edit` / `Done` button with ⌘E as a hidden-button shortcut. Per the ⌘N fix, shortcuts don't go on toolbar items.
  - `pasteSnippet` becomes `async`. It reads `await selection.selectedText()` before closing the window and pastes `SnippetPaste.content(full:language:selection:)`.
  - Add a hidden ⌘↩ button that calls `pasteSnippet(selectedSnippet)`. Return in the list and the Paste button keep working and are selection-aware too.
- [ ] **Step 6:** Build, then run the full suite. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 7: Manual check.**
  - A markdown snippet with a heading, a list, a table and a fenced Swift block renders in both light and dark mode.
  - ⌘E toggles between the rendered view and the raw editor.
  - Selecting a command inside the code block and pressing ⌘↩ pastes only that command into TextEdit.
  - Pressing ⌘↩ with nothing selected pastes the whole raw markdown.
  - In a code snippet, ⌘↩ pastes the whole snippet even with text selected.
- [ ] **Step 8:** Commit `feat(snippets): rendered markdown view, edit toggle, selection-aware paste`.

---

### Task 7: Reference chips in the todo list

**Files:**
- Modify: `Clipsmith/Views/Todos/TodoListView.swift` (`TodoRowView`, hidden shortcuts)
- Modify: `Clipsmith/Views/Browser/TodosSectionView.swift` (shortcut table doc comment)
- Test: none new. The parsing is covered by Task 1. The open request is covered in Task 8.

**Interfaces:**
- Consumes: `SnippetReference.segments(in:)`, `SnippetReference.names(in:)`
- Produces: `TodoRowView(item:today:onToggle:onOpenReference:)`, where `onOpenReference: (String) -> Void`, and a free function in `TodoListView.swift`: `@MainActor func openSnippetReference(_ name: String)`. It posts `.clipsmithRequestBrowser` with `BrowserOpenRequest(section: .snippets, query: name).userInfo`.

- [ ] **Step 1:** `TodoRowView` renders `item.title` as an `HStack(spacing: 0)` of `SnippetReference.segments`.
  - `.text` segments stay plain `Text`, with the strikethrough and secondary style for done tasks applied as today.
  - `.reference(name)` segments become a `.borderless` `Button` with `Image(systemName: "doc.text")` and the name, in `.accentColor`, calling `onOpenReference(name)`.
  - Keep `.lineLimit(1)` on the HStack.
- [ ] **Step 2:** Add a hidden button for ⌘O. With a selected task and no edit in progress, it opens the first `SnippetReference.names(in: item.rawLine)` entry and does nothing if there's none. Add `| ⌘O | Open the task's snippet reference |` to the table in `TodosSectionView`.
- [ ] **Step 3:** Build, then run the full suite. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 4: Manual check.**
  - Clicking the chip doesn't start a row edit or a drag.
  - Dragging the row by its text still works.
  - Double-clicking the plain text still edits, and the edit field shows the raw `[[...]]`.
- [ ] **Step 5:** Commit `feat(todos): [[snippet]] references render as chips; ⌘O opens`.

---

### Task 8: Snippets section opens or creates the referenced snippet

**Files:**
- Modify: `Clipsmith/Views/Browser/BrowserWindowViewModel.swift`
- Modify: `Clipsmith/Views/Browser/BrowserWindowView.swift` (pass `viewModel` into `SnippetsSectionView`)
- Modify: `Clipsmith/Views/Browser/SnippetsSectionView.swift`
- Test: `ClipsmithTests/BrowserWindowViewModelTests.swift`

**Interfaces:**
- Consumes: `SnippetFilter.bestMatch(named:in:)`, `SnippetStore.insert` (returns an id), `isEditingMarkdown` from Task 6
- Produces:
  - `BrowserWindowViewModel.pendingSnippetName: String?`
  - `SnippetsSectionView(windowViewModel: BrowserWindowViewModel)`

- [ ] **Step 1: Write the failing tests**

```swift
func testSnippetsRequestSetsPendingName() {
    let vm = BrowserWindowViewModel(defaults: defaults)   // the suite's per-test suiteName defaults
    vm.apply(BrowserOpenRequest(section: .snippets, query: "xyz"), docLookupEnabled: false, todoTrackingEnabled: true)
    XCTAssertEqual(vm.selectedSection, .snippets)
    XCTAssertEqual(vm.pendingSnippetName, "xyz")
    XCTAssertNil(vm.pendingDocsQuery)
}
func testOtherRequestClearsPendingName() {
    let vm = BrowserWindowViewModel(defaults: defaults)
    vm.apply(BrowserOpenRequest(section: .snippets, query: "xyz"), docLookupEnabled: false, todoTrackingEnabled: true)
    vm.apply(BrowserOpenRequest(section: .todos, query: nil), docLookupEnabled: false, todoTrackingEnabled: true)
    XCTAssertNil(vm.pendingSnippetName)
}
```

- [ ] **Step 2:** Run `-only-testing:ClipsmithTests/BrowserWindowViewModelTests`. Expected: build failure.
- [ ] **Step 3:** In `apply`, set `pendingSnippetName = request.query` when the request asked for `.snippets` and Snippets is now selected. Set it to nil otherwise.
- [ ] **Step 4:** In `SnippetsSectionView`, consume `pendingSnippetName` in `onAppear` and in `onChange`, mirroring `DocsSectionView.consumePendingQuery`:
  - Clear `searchText` and `languageFilter` first.
  - If `SnippetFilter.bestMatch` finds a snippet, select it.
  - If not, insert `name: <reference>, content: "", language: "markdown", tags: []`, select the returned id, and set `isEditingMarkdown = true`.
  - Set `pendingSnippetName = nil` either way.
- [ ] **Step 5:** Run the full suite. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Manual check.**
  - With a Snippets language filter active, click a todo chip for an existing snippet: the window switches to Snippets, the filter clears, and that snippet is selected.
  - Click a chip for a name that doesn't exist: a markdown snippet with that name is created and opens in edit mode.
  - The same from the ⌘O shortcut.
- [ ] **Step 7:** Update `CHANGELOG.md` `[Unreleased]` with an `### Added` entry for markdown rendering, selection paste, todo references and unique names, and a `### Changed` entry for the todo edit/move/All/drag and launcher fixes. In `CLAUDE.md`, add one line under Browser Window: "Snippets: markdown snippets render via `MarkdownWebView`; `pendingSnippetName` opens a snippet from a todo `[[reference]]`".
- [ ] **Step 8:** Commit `feat(browser): todo references open or create the snippet`.
