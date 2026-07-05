# Bezel Transform Picker — Design

**Date:** 2026-07-05
**Status:** Approved (design review with Adam)

## Problem

Text transforms are effectively unreachable from the primary Cmd-Shift-V paste flow. They exist behind Tab / right-click as a nested NSMenu (`BezelController.swift:351-429`), but:

1. Picking a transform does **not** paste — `applyTransform` (`BezelController.swift:438-460`) writes the result to the pasteboard and history, then requires the user to notice and press Enter. In a muscle-memory paste flow this reads as "nothing happened".
2. A nested context menu has no fuzzy search and no discoverability hint, and does not scale past ~10 transforms.

## Decisions (from design review)

- **Transform-and-paste in one motion.** Picking a transform pastes the transformed result into the target app immediately and closes the bezel. No review step.
- **Fuzzy-searchable overlay** replaces the NSMenu as the keyboard path (Tab). The right-click menu stays for mouse users but gains the same paste behavior.
- **Ship the new transform pack together with the picker** (~16 new transforms, ~26 total).
- **Failable transforms return `nil`** and show an inline error in the overlay instead of silently pasting unchanged input.
- **Cut for now:** JSON↔YAML conversion (would require the Yams SPM dependency; not worth it yet).

## User flow

```
Cmd-Shift-V → navigate to clipping → Tab
  → overlay over the bezel: filter field + transform list (fuzzy)
  → type "up" → UPPERCASE selected → Enter
  → transformed text pasted into target field, bezel closes
Escape in overlay → close overlay only, back to clipping list
Tab in overlay → close overlay (toggle)
```

## Components

### 1. TransformRegistry (new, `Services/TransformRegistry.swift`)

Flat array of transform descriptors:

```swift
struct TextTransform: Sendable, Identifiable {
    let id: String            // stable, e.g. "case.upper"
    let displayName: String   // "UPPERCASE"
    let keywords: String      // extra fuzzy-match terms, e.g. "b64" for Base64
    let apply: @Sendable (String) -> String?   // nil = not applicable (shows inline error, no paste)
}
```

`TextTransformer` keeps the pure functions; the registry only enumerates them. This is the foundation for future pipelines (ordered arrays of transform IDs).

### 2. Transform pack (new pure functions in `TextTransformer`)

- **Case:** camelCase, snake_case, kebab-case, PascalCase
- **Encoding:** Base64 encode, Base64 decode (nil on invalid input)
- **Lines:** sort lines, sort unique (dedupe), reverse lines
- **Extract:** URLs, email addresses (one match per line; nil when no matches)
- **Dev:** JWT decode (header + payload pretty-printed; nil on malformed token),
  Unix timestamp → ISO 8601 and ISO 8601 → Unix timestamp (nil on parse failure),
  slugify, escape (quotes + newlines), unescape

Existing failable transforms change semantics: `jsonPrettyPrint` and `urlDecode` return `nil` on invalid input instead of returning the input unchanged.

### 3. Overlay UI (`BezelView` + `BezelViewModel`)

Same overlay pattern as the `?` cheat sheet (`BezelView.swift:170-236`).

New `BezelViewModel` state:
- `isShowingTransformPicker: Bool`
- `transformFilterText: String`
- `transformSelectedIndex: Int`
- `transformError: String?` (inline error line, cleared on filter change)

Filtering reuses `FuzzyMatcher` over `displayName + keywords`. Each row shows the transform name plus a dimmed one-line preview of the result applied to the current clipping (transforms are pure; clipping display is already truncated to 5,000 chars).

All picker state resets in `BezelController.hide()` alongside the existing resets.

### 4. Keyboard routing (`BezelController`)

- **Tab** (`sendEvent`, keyCode 48): toggles the picker instead of opening the NSMenu.
- While picker is open, `keyDown` routes: printable chars → filter text; Up/Down and j/k (when filter empty) → picker navigation; **Enter** → apply + paste; **Escape** → close picker only.
- Enter path: `transform.apply(clipping)`; on `nil` set `transformError`, stay open; on success paste via a parameterized variant of the existing paste path — `pasteAndHide(content:)` — with the transformed string (`pasteAndHide()` currently hardcodes `viewModel.currentClipping`; extract the content into a parameter so paste timing, `blockedChangeCount` self-capture protection, and pasteMovesToTop are shared, not duplicated).

### 5. Existing NSMenu (right-click)

Stays for mouse users. Transform/Format items call the same new transform-and-paste action — the no-paste `applyTransform` behavior is removed everywhere. Share actions (Copy as RTF, Create Gist…) remain menu-only; they are not text transforms and do not appear in the picker.

### 6. History behavior

Unchanged in spirit: transformed content is inserted into history as "Clipsmith (transformed)" and is on the pasteboard after paste, so a subsequent Cmd-V repeats it — consistent with normal paste.

### 7. Discoverability

- Bezel footer gains a `⇥ transform` hint next to the navigation counter.
- Cheat sheet (`?`) gains a Tab row.

## Error handling

- Transform returns `nil` → inline error in the overlay ("Not valid JSON", "No URLs found"…), no paste, picker stays open.
- Empty filter result → standard "No matches" row.
- No clipping selected → Tab is a no-op (same guard as today's menu, `BezelController.swift:352`).

## Testing

- Unit tests per new transform in `TextTransformerTests` (pure functions), including nil cases.
- `BezelViewModelTests`: picker filter, navigation clamping, state reset, error set/clear.
- Routing test: Tab toggles `isShowingTransformPicker`.
- CGEvent paste synthesis remains manually verified (as today).

## Out of scope

- JSON↔YAML (Yams dependency)
- Transform pipelines/chaining (future; registry is designed for it)
- Custom shell filters
- Prompt/doc bezel transform support
