# Phase 7: Intelligent Search & AI - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Upgrade the bezel search from exact substring matching to fuzzy matching. Source app filtering, date filtering, and AI integration are descoped from this phase.

</domain>

<decisions>
## Implementation Decisions

### Fuzzy matching
- Replace current `localizedCaseInsensitiveContains` with a fuzzy matching algorithm
- Typing `jsonpar` should find "JSON.parse(...)" — character-sequence matching, not just substring
- Results should be ranked by match quality (best match first)
- Fuzzy search applies in the clipboard bezel search mode (existing search hotkey flow)

### Source app filtering — DROPPED
- User explicitly does not want this feature
- Clipping model already stores `sourceAppName` if needed in the future

### Date filtering — DROPPED
- User explicitly does not want this feature
- Clipping model already stores `timestamp` if needed in the future

### AI integration — DROPPED
- Apple Foundation Models not available in Europe (user's region)
- Requires macOS 26 which is not yet released
- Descoped entirely from this phase and milestone

### Claude's Discretion
- Fuzzy matching algorithm choice (Levenshtein, token-based, character subsequence, etc.)
- Whether to fall back to substring matching when fuzzy has no results
- Match scoring and ranking implementation
- Whether fuzzy matching also applies to prompt bezel search

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BezelViewModel.recomputeFilteredClippings()`: Current filter logic using `localizedCaseInsensitiveContains` — replace with fuzzy matching
- `PromptBezelViewModel`: Has similar search filtering — consider applying fuzzy matching here too
- `ClippingInfo`: Sendable struct already carries all needed fields

### Established Patterns
- `@Observable @MainActor` view models with cached filtered results
- Search text triggers `recomputeFilteredClippings()` via `didSet`
- `filteredClippings` is the single source of truth for display

### Integration Points
- `BezelViewModel.recomputeFilteredClippings()` — primary change point
- `PromptBezelViewModel` — secondary change point if fuzzy matching extends to prompts

</code_context>

<specifics>
## Specific Ideas

- User wants fuzzy matching specifically — the ability to type partial/non-contiguous characters and find clips
- This is a focused, surgical change to the existing search pipeline

</specifics>

<deferred>
## Deferred Ideas

- Source app filtering (SRCH-02) — user not interested, model already has data if needed later
- Date filtering (SRCH-03) — user not interested, model already has timestamp if needed later
- On-device AI via Apple Foundation Models (AINT-01) — not available in Europe, deferred indefinitely

</deferred>

---

*Phase: 07-intelligent-search-ai*
*Context gathered: 2026-03-12*
