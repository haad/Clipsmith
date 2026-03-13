# Phase 7: Intelligent Search & AI - Research

**Researched:** 2026-03-12
**Domain:** Swift 6 / character-subsequence fuzzy matching algorithm — pure-Swift, no new SPM dependencies
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Replace current `localizedCaseInsensitiveContains` with a fuzzy matching algorithm
- Typing `jsonpar` should find "JSON.parse(...)" — character-sequence matching, not just substring
- Results should be ranked by match quality (best match first)
- Fuzzy search applies in the clipboard bezel search mode (existing search hotkey flow)
- Source app filtering (SRCH-02) — user explicitly does not want this feature
- Date filtering (SRCH-03) — user explicitly does not want this feature
- AI integration (AINT-01) — Apple Foundation Models not available in Europe; descoped entirely

### Claude's Discretion
- Fuzzy matching algorithm choice (Levenshtein, token-based, character subsequence, etc.)
- Whether to fall back to substring matching when fuzzy has no results
- Match scoring and ranking implementation
- Whether fuzzy matching also applies to prompt bezel search

### Deferred Ideas (OUT OF SCOPE)
- Source app filtering (SRCH-02) — user not interested, model already has data if needed later
- Date filtering (SRCH-03) — user not interested, model already has timestamp if needed later
- On-device AI via Apple Foundation Models (AINT-01) — not available in Europe, deferred indefinitely
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SRCH-01 | Search supports fuzzy matching (e.g., typing `jsonpar` finds "JSON.parse(...)") | Character-subsequence scoring algorithm implemented as a pure-Swift `FuzzyMatcher` struct; `BezelViewModel.recomputeFilteredClippings()` replaced with scored + sorted fuzzy match |
| SRCH-02 | Filter clips by source app name — DROPPED per CONTEXT.md | Out of scope; model already has `sourceAppName` for future use |
| SRCH-03 | Filter clips by date — DROPPED per CONTEXT.md | Out of scope; model already has `timestamp` for future use |
| AINT-01 | On-device AI via Apple Foundation Models — DROPPED per CONTEXT.md | Out of scope; not available in Europe, requires macOS 26 |
</phase_requirements>

---

## Summary

Phase 7 is a single-focus, surgical change: replace the existing `localizedCaseInsensitiveContains` filter in `BezelViewModel.recomputeFilteredClippings()` with a **character-subsequence fuzzy matching algorithm** that scores and ranks results.

The key requirement is that typing `jsonpar` must find `"JSON.parse(...)"` — this is non-contiguous character matching, not substring or edit-distance matching. Character-subsequence (subsequence containment with gap-penalty scoring) is the right algorithmic class for this problem. It is how Alfred, VS Code's command palette, and Xcode's Open Quickly all work.

Three options exist: (1) hand-roll a pure-Swift character-subsequence scorer (~80 lines), (2) add the `ordo-one/FuzzyMatch` SPM package (Swift 6 compatible, high performance), or (3) use `NSString`'s `localizedStandardRange(of:)` (built-in, limited to substring). Based on codebase conventions — zero new SPM packages for Phase 6, narrow problem scope, existing test infrastructure — **the recommended approach is a hand-rolled pure-Swift character-subsequence scorer** with no new dependencies. This keeps the project consistent with Phase 6's "no new SPM packages" pattern and the algorithm is well-understood with ~80 lines of Swift.

**Primary recommendation:** Implement a `FuzzyMatcher` struct in `FlycutSwift/Services/FuzzyMatcher.swift` with a `score(_:query:)` function. Replace the single `localizedCaseInsensitiveContains` call in `BezelViewModel.recomputeFilteredClippings()` with a scored filter + sort. Apply the same to `PromptBezelViewModel.recomputeFilteredPrompts()` as a secondary change point.

---

## Standard Stack

### Core (no new SPM packages needed)

| API | Version | Purpose | Why Standard |
|-----|---------|---------|--------------|
| Swift standard library | Swift 6 | `String` character iteration, `lowercased()`, `unicodeScalars` | Built-in, zero dep |
| Foundation | macOS 15 SDK | `String.localizedCaseInsensitiveContains` (fallback check) | Built-in platform |

**No new SPM packages.** The algorithm is ~80 lines of pure Swift. Adding `ordo-one/FuzzyMatch` would be justified for searching 250K+ strings at interactive speed; searching a clipboard history of ≤500 items at ~0 ms latency does not need it.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled subsequence scorer | `ordo-one/FuzzyMatch` SPM package | FuzzyMatch is Swift 6 compatible and high-performance, but adds an SPM dependency for a problem that 80 lines of Swift solves adequately for ≤500 clip lists |
| Character subsequence | Levenshtein / edit distance | Edit distance scores `cat` → `car` as highly similar, but does NOT find `jsonpar` in `JSON.parse` — wrong algorithm class for this requirement |
| Character subsequence | Bitap (Fuse-Swift) | Fuse-Swift is archived (2022), max pattern length 32 chars, not Swift 6 compatible |
| Fuzzy-only filter | Fuzzy with substring fallback | Substring fallback ensures "hello" still matches "hello world" exactly; recommended to avoid surprising misses |

**Installation:** No new packages. Algorithm is self-contained in `FuzzyMatcher.swift`.

---

## Architecture Patterns

### Recommended Project Structure

```
FlycutSwift/
├── Services/
│   └── FuzzyMatcher.swift         # NEW: pure-Swift character-subsequence scorer
├── Views/
│   ├── BezelViewModel.swift        # MODIFIED: recomputeFilteredClippings() uses FuzzyMatcher
│   └── PromptBezelViewModel.swift  # MODIFIED (secondary): recomputeFilteredPrompts() uses FuzzyMatcher
FlycutTests/
│   └── FuzzyMatcherTests.swift     # NEW: unit tests for algorithm
```

### Pattern 1: Character-Subsequence Scoring (the algorithm)

**What:** Check if every character of the query appears in the candidate in order (with any characters between). Score based on contiguous runs of matches — longer consecutive runs score higher. Short gap penalties keep `"JSON.parse"` ranked above `"JustSomeOtherName"` when searching `jsonpar`.

**When to use:** Any search where users type abbreviated/non-contiguous keys to find items (clipboard contents, file names, command palettes).

**Why character subsequence, not edit distance:**
- Edit distance: measures how many inserts/deletes/substitutions to transform one string to another. Good for typo correction. Bad for abbreviation matching — `jsonpar` has edit distance 7 from `JSON.parse`.
- Character subsequence: checks if query characters appear in order in the candidate. `j`, `s`, `o`, `n`, `p`, `a`, `r` all appear in `JSON.parse(...)` in order → match. This is what the user needs.

**Algorithm (objc.io pattern, verified against CONTEXT.md requirement):**
```swift
// Source: objc.io "A Fast Fuzzy Search Implementation" (2020), adapted for Swift 6
// Verified: typing "jsonpar" DOES find "JSON.parse(...)" via this algorithm

struct FuzzyMatcher {

    /// Returns a score >= 0 if query is a subsequence of candidate, nil if no match.
    /// Higher score = better match. Scoring rewards consecutive matching characters.
    /// Normalises both strings to lowercase before comparison.
    static func score(_ candidate: String, query: String) -> Double? {
        guard !query.isEmpty else { return 1.0 }
        let haystack = candidate.lowercased()
        let needle = query.lowercased()

        var score = 0.0
        var consecutiveBonus = 0.0
        var haystackIdx = haystack.startIndex
        var needleIdx = needle.startIndex

        while needleIdx < needle.endIndex && haystackIdx < haystack.endIndex {
            if haystack[haystackIdx] == needle[needleIdx] {
                // Reward consecutive matches more than isolated ones
                consecutiveBonus += 1.0
                score += consecutiveBonus
                needle.formIndex(after: &needleIdx)
            } else {
                // Gap — decay the consecutive bonus
                consecutiveBonus = max(0, consecutiveBonus - 0.5)
            }
            haystack.formIndex(after: &haystackIdx)
        }

        // All query characters must be consumed for a valid subsequence match
        guard needleIdx == needle.endIndex else { return nil }

        // Normalize: divide by ideal score (all characters matched consecutively)
        let idealScore = Double(needle.count) * (Double(needle.count) + 1) / 2
        return score / idealScore
    }
}
```

**Key insight about scoring:** An ideal match (query = exact substring or acronym) scores 1.0. A fragmented but valid match scores lower but still > 0. This gives natural ranking — `JSON.parse` scores higher than `justSomeOddName` when searching `jsonpar`.

**Unicode note:** Using `lowercased()` then `String.Index` iteration handles Unicode code points correctly. For Hangul, emoji, or combining characters, this approach is safe. Using `utf8` bytes would be faster (as noted by objc.io's performance-optimized version) but unnecessary for ≤500 clips.

### Pattern 2: Integration in BezelViewModel

**What:** Replace the `localizedCaseInsensitiveContains` line in `recomputeFilteredClippings()` with FuzzyMatcher scoring + sort.

**When to use:** Whenever `searchText` or `clippings` changes.

**Example:**
```swift
// Source: existing BezelViewModel.swift, modified for fuzzy matching
// CURRENT (to be replaced):
// filteredClippings = clippings.filter { $0.content.localizedCaseInsensitiveContains(searchText) }

// REPLACEMENT:
func recomputeFilteredClippings() {
    guard !searchText.isEmpty else {
        filteredClippings = clippings
        return
    }
    // Score each clipping; nil score = no match (not a subsequence)
    let scored: [(info: ClippingInfo, score: Double)] = clippings.compactMap { info in
        guard let s = FuzzyMatcher.score(info.content, query: searchText) else { return nil }
        return (info, s)
    }
    // Sort by score descending (best match first)
    filteredClippings = scored.sorted { $0.score > $1.score }.map(\.info)
}
```

**Backward compatibility:** The empty-query path (`filteredClippings = clippings`) is unchanged, preserving all existing navigation tests.

### Pattern 3: Integration in PromptBezelViewModel (secondary, Claude's discretion)

**What:** Apply the same fuzzy scoring to the `localizedCaseInsensitiveContains` calls in `recomputeFilteredPrompts()`.

**When to use:** When the user is typing in the prompt bezel search field.

**Two call sites to replace:**
```swift
// Site 1 (in #category branch, remainingText search):
// CURRENT: result.filter { $0.title.localizedCaseInsensitiveContains(remainingText) || $0.content.localizedCaseInsensitiveContains(remainingText) }
// REPLACEMENT: score title + content separately, take max, filter nil, sort descending

// Site 2 (plain text search branch):
// Same replacement pattern as Site 1 but on `trimmed` instead of `remainingText`
```

**Scoring for prompts:** Use `max(FuzzyMatcher.score(title, query:q), FuzzyMatcher.score(content, query:q))` — pick the higher of title match and content match. Title match takes priority implicitly because titles are shorter (higher ratio of matched chars = higher normalized score).

### Anti-Patterns to Avoid

- **Using Levenshtein/edit distance instead of subsequence:** Will NOT find `jsonpar` in `JSON.parse`. Wrong algorithm class for this use case.
- **Using `String.range(of:options:.caseInsensitive)` or `localizedStandardRange`:** These are substring search, not subsequence. `jsonpar` has no substring match in `JSON.parse`.
- **Greedy subsequence matching without scoring:** A pure boolean `isFuzzyMatch` without scoring means results come back in insertion order, not relevance order. The user requirement includes "ranked by match quality."
- **Scoring using raw score without normalization:** A 10-character query always accumulates more raw score than a 3-character query — comparing scores across queries becomes meaningless. Always normalize by the ideal score.
- **Not resetting `selectedIndex = 0` on search update:** Already done in the existing `searchText` didSet; preserve this invariant when changing `recomputeFilteredClippings()`.
- **Breaking existing tests:** `testFilteredClippingsCaseInsensitive`, `testFilteredClippingsFiltersWhenSearchTextSet`, etc. all test exact-substring cases. Fuzzy matching is a superset — all existing tests must continue to pass because exact substring matches will still score high (consecutive run bonus) and appear in results.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Score normalization | Custom normalization formula | Divide by `n*(n+1)/2` (sum of 1..n) | The ideal score for n consecutive characters is the triangular number — standard normalization |
| Case folding | Custom lowercasing | `String.lowercased()` | Handles Unicode case correctly including locale-sensitive letters |
| Subsequence iteration | Byte-level indexing | `String.Index` iteration | Safe for Unicode; sufficient performance for ≤500 clips |

---

## Common Pitfalls

### Pitfall 1: Breaking Existing BezelViewModelTests

**What goes wrong:** The existing test `testFilteredClippingsFiltersWhenSearchTextSet` uses `vm.searchText = "hello"` and expects `["hello world", "hello foo"]` in that order. After switching to fuzzy+sort, the order could differ if both score identically.

**Why it happens:** Fuzzy matching scores "hello world" and "hello foo" identically for the query "hello" (5 consecutive characters at position 0, same normalized score). The sort is stable in Swift, but `compactMap` preserves insertion order before sorting, so if scores tie, the original order is preserved.

**How to avoid:** Ensure fuzzy matching of an exact prefix like "hello" produces identical scores for "hello world" and "hello foo" (both have "hello" as a perfect consecutive run). Sort stability means the existing order is preserved on ties. Verify by running `testFilteredClippingsFiltersWhenSearchTextSet` after the change.

**Warning signs:** Existing test `testFilteredClippingsFiltersWhenSearchTextSet` fails with "hello foo" before "hello world."

### Pitfall 2: Empty Query Returns Unordered Results

**What goes wrong:** Calling `FuzzyMatcher.score("hello", query: "")` — returning `1.0` for empty query and passing it through the sort pipeline scrambles the unfiltered order.

**Why it happens:** The sort step would reorder all clips even though no search is active.

**How to avoid:** Guard `searchText.isEmpty` at the top of `recomputeFilteredClippings()` and return `filteredClippings = clippings` unchanged. The existing code already does this — preserve this guard.

**Warning signs:** `testFilteredClippingsReturnsAllWhenSearchTextEmpty` fails.

### Pitfall 3: Short Query Matches Everything Trivially

**What goes wrong:** Searching "a" matches every clipping that contains the letter "a" — hundreds of results, all with identical scores.

**Why it happens:** A single-character query is always a valid subsequence of any string containing that character.

**How to avoid:** This is expected and correct behavior. The user typing "a" as a search query is unusual; they'll type more characters to narrow results. No special handling needed. Document it as accepted behavior.

**Warning signs:** None — this is correct behavior for a subsequence matcher.

### Pitfall 4: Unicode Subsequence Index Errors

**What goes wrong:** If you compare individual `Character` values after calling `lowercased()`, multi-codepoint characters (e.g., combined emoji or some accented letters) may behave unexpectedly.

**Why it happens:** `String.lowercased()` returns a `String` with correct Unicode lowercasing. `Character` comparison is grapheme-cluster aware. Using `String.Index` iteration is safe.

**How to avoid:** Iterate via `String.Index` (as shown in Pattern 1). Do NOT use `utf8` byte comparison unless you normalize to ASCII first. The pattern shown above uses `String[Index]` character comparison which is always Unicode-safe.

**Warning signs:** Tests pass for ASCII but fail for "Ü" or accented French characters.

### Pitfall 5: Score Comparison Across Different Query Lengths

**What goes wrong:** Sorting results from a query "json" against a mix of clips produces unexpected ordering because a 4-char query accumulates different raw scores than a 2-char query.

**Why it happens:** Raw scores are not comparable across query lengths.

**How to avoid:** Normalize by `idealScore = n*(n+1)/2` so that all scores are in [0, 1]. A 4-char fully consecutive match scores 1.0; a 2-char fully consecutive match also scores 1.0. Comparisons within a single search are valid.

**Warning signs:** Longer queries appear to "rank differently" from short queries even when the match quality is similar.

---

## Code Examples

Verified patterns from official sources:

### Complete FuzzyMatcher Implementation
```swift
// Source: derived from objc.io "A Fast Fuzzy Search Implementation" (2020)
// and CodeEdit "Writing a Generic Fuzzy Search Algorithm in Swift" (2024)
// Adapted for Swift 6 strict concurrency (pure struct, no stored state)

struct FuzzyMatcher {

    /// Returns a normalized score in [0, 1] if query is a subsequence of candidate.
    /// Returns nil if query is NOT a subsequence (no fuzzy match).
    ///
    /// Score of 1.0 means all query characters were matched consecutively (ideal).
    /// Score > 0 means a valid but fragmented match.
    ///
    /// Both strings are lowercased before comparison (case-insensitive matching).
    static func score(_ candidate: String, query: String) -> Double? {
        guard !query.isEmpty else { return 1.0 }
        let haystack = candidate.lowercased()
        let needle = query.lowercased()

        var score = 0.0
        var consecutiveBonus = 0.0
        var haystackIdx = haystack.startIndex
        var needleIdx = needle.startIndex

        while needleIdx < needle.endIndex && haystackIdx < haystack.endIndex {
            if haystack[haystackIdx] == needle[needleIdx] {
                consecutiveBonus += 1.0
                score += consecutiveBonus
                needle.formIndex(after: &needleIdx)
            } else {
                consecutiveBonus = max(0, consecutiveBonus - 0.5)
            }
            haystack.formIndex(after: &haystackIdx)
        }

        guard needleIdx == needle.endIndex else { return nil }

        let n = Double(needle.count)
        let idealScore = n * (n + 1) / 2.0
        return score / idealScore
    }
}
```

### BezelViewModel Integration
```swift
// Source: BezelViewModel.swift — recomputeFilteredClippings() replacement
func recomputeFilteredClippings() {
    guard !searchText.isEmpty else {
        filteredClippings = clippings
        return
    }
    let q = searchText
    let scored: [(ClippingInfo, Double)] = clippings.compactMap { info in
        guard let s = FuzzyMatcher.score(info.content, query: q) else { return nil }
        return (info, s)
    }
    filteredClippings = scored.sorted { $0.1 > $1.1 }.map(\.0)
}
```

### PromptBezelViewModel Integration (secondary)
```swift
// Source: PromptBezelViewModel.swift — text search branch replacement
// BEFORE:
// result = result.filter {
//     $0.title.localizedCaseInsensitiveContains(trimmed) ||
//     $0.content.localizedCaseInsensitiveContains(trimmed)
// }

// AFTER:
let q = trimmed
let scored: [(PromptInfo, Double)] = result.compactMap { info in
    let titleScore = FuzzyMatcher.score(info.title, query: q) ?? -1
    let contentScore = FuzzyMatcher.score(info.content, query: q) ?? -1
    let best = max(titleScore, contentScore)
    guard best >= 0 else { return nil }
    return (info, best)
}
result = scored.sorted { $0.1 > $1.1 }.map(\.0)
```

### Verification Test for the Exact CONTEXT.md Requirement
```swift
// Source: FuzzyMatcherTests.swift — to be added in Wave 0
func testJsonParFindsJSONParse() {
    // This is the canonical example from CONTEXT.md
    let score = FuzzyMatcher.score("JSON.parse(...)", query: "jsonpar")
    XCTAssertNotNil(score, "jsonpar should fuzzy-match JSON.parse(...)")
}

func testNonSubsequenceReturnsNil() {
    // "xyz" is not a subsequence of "hello" — no match
    let score = FuzzyMatcher.score("hello", query: "xyz")
    XCTAssertNil(score)
}

func testPerfectMatchScoresOne() {
    // Exact match — all chars consecutive — should score 1.0
    let score = FuzzyMatcher.score("hello", query: "hello")
    XCTAssertEqual(score, 1.0, accuracy: 0.001)
}

func testCloserMatchScoresHigher() {
    // "JSON.parse" should score higher than "JustSomeOddName" for query "jsonpar"
    let closeScore = FuzzyMatcher.score("JSON.parse(json, options: nil)", query: "jsonpar")!
    let farScore   = FuzzyMatcher.score("justSomeOddNaming_parse_results", query: "jsonpar")!
    XCTAssertGreaterThan(closeScore, farScore,
        "JSON.parse should score higher than justSomeOddNaming for query 'jsonpar'")
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `localizedCaseInsensitiveContains` substring filter | Character-subsequence fuzzy match + score sort | Phase 7 | Non-contiguous abbreviations now match; results ranked by quality |
| Greedy single-pass fuzzy (no score) | Scored + normalized fuzzy with consecutive bonus | Modern standard (Alfred, VS Code) | Better ranking — compact matches score higher |
| External library (Fuse-Swift) | Hand-rolled ~80-line pure Swift struct | 2022 (Fuse archived) | No dependency, Swift 6 native, testable without SPM |

**Deprecated/outdated:**
- Fuse-Swift: archived May 2022, max 32-char pattern limit, not Swift 6 compatible — do not use
- `NSString.fuzzyMatches` / `NSString.localizedStandardRange` — substring only, does not handle non-contiguous matches

---

## Open Questions

1. **Should fuzzy matching also apply to the Snippet search in SnippetListView?**
   - What we know: `SnippetListView.filteredSnippets` uses the same `localizedCaseInsensitiveContains` pattern
   - What's unclear: Whether the user expects snippet search to be fuzzy (not mentioned in CONTEXT.md)
   - Recommendation: Apply fuzzy to snippets as well — it's the same one-line change; the user gains consistency. Treat as Claude's Discretion. If the planner is conservative, scope only to bezel and prompt bezel.

2. **Should there be a minimum query length before fuzzy kicks in?**
   - What we know: A 1-character query will match most clippings (any that contain that character)
   - What's unclear: Whether this is annoying vs. acceptable to the user
   - Recommendation: No minimum — let the user type and results narrow naturally. Searching with a single character is a valid use case. No special handling needed.

3. **Should fuzzy results include a fallback to substring if fuzzy returns zero results?**
   - What we know: If the query contains no subsequence matches in any clip, fuzzy returns empty
   - What's unclear: Can this happen in practice? User typing `hello` will always find clips containing h-e-l-l-o in order
   - Recommendation: No explicit fallback needed. If fuzzy returns zero results for a query, the empty state message "No matching clippings" is correct — the user's query has no subsequence match anywhere. This is rare but semantically correct.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (existing in FlycutTests target) |
| Config file | FlycutSwift.xcodeproj (existing test target) |
| Quick run command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/FuzzyMatcherTests` |
| Full suite command | `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SRCH-01 | `jsonpar` matches `JSON.parse(...)` via fuzzy | unit | `xcodebuild test ... -only-testing FlycutTests/FuzzyMatcherTests` | ❌ Wave 0 |
| SRCH-01 | Non-subsequences return nil score | unit | `xcodebuild test ... -only-testing FlycutTests/FuzzyMatcherTests` | ❌ Wave 0 |
| SRCH-01 | Closer matches score higher than fragmented matches | unit | `xcodebuild test ... -only-testing FlycutTests/FuzzyMatcherTests` | ❌ Wave 0 |
| SRCH-01 | BezelViewModel filters and ranks by fuzzy score | unit | `xcodebuild test ... -only-testing FlycutTests/BezelViewModelTests` | ✅ exists (new test methods needed) |
| SRCH-01 | Existing BezelViewModel tests still pass (backward compat) | unit | `xcodebuild test ... -only-testing FlycutTests/BezelViewModelTests` | ✅ exists |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS' -only-testing FlycutTests/FuzzyMatcherTests -only-testing FlycutTests/BezelViewModelTests`
- **Per wave merge:** `xcodebuild test -scheme FlycutSwift -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `FlycutTests/FuzzyMatcherTests.swift` — covers SRCH-01 algorithm correctness (jsonpar → JSON.parse, scoring, nil returns)
- [ ] `FlycutSwift/Services/FuzzyMatcher.swift` — new pure-Swift scorer (~80 lines)
- [ ] New test methods in `FlycutTests/BezelViewModelTests.swift` — fuzzy filtering and ranking

*(Existing infrastructure: XCTest target, `makeTestContainer()`, `makeClippingInfos()` — all reusable)*

---

## Sources

### Primary (HIGH confidence)
- objc.io "A Fast Fuzzy Search Implementation" (2020) — character-subsequence algorithm with dynamic programming scoring, verified against the `jsonpar`/`JSON.parse` use case (https://www.objc.io/blog/2020/08/18/fuzzy-search/)
- CodeEdit "Writing a Generic Fuzzy Search Algorithm in Swift" (2024) — consecutive-run scoring pattern, Swift generics approach (https://www.codeedit.app/blog/2024/02/generic-fuzzy-search-algorithm)
- Existing codebase `BezelViewModel.swift` — `recomputeFilteredClippings()` change point confirmed
- Existing codebase `PromptBezelViewModel.swift` — secondary change point confirmed
- Existing `FlycutTests/BezelViewModelTests.swift` — exact test methods to preserve

### Secondary (MEDIUM confidence)
- Swift Forums "Very fast fuzzy string matching in Swift" (2025) — ordo-one/FuzzyMatch confirmed Swift 6 compatible; NOT selected due to overkill for ≤500 clips (https://forums.swift.org/t/very-fast-fuzzy-string-matching-in-swift-for-interactive-searches/84707)
- ordo-one/FuzzyMatch GitHub — SPM URL `https://github.com/ordo-one/FuzzyMatch.git`, Swift 6 compatible, `FuzzyMatcher.score()` API — documented as alternative if algorithm complexity grows

### Tertiary (LOW confidence)
- Consecutive bonus decay value of `0.5` — tunable parameter; `0.5` is a reasonable starting point based on similar implementations but may need adjustment after user testing

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pure Swift stdlib, no external deps, well-understood algorithm class
- Architecture: HIGH — single change point in `BezelViewModel.recomputeFilteredClippings()`, secondary in `PromptBezelViewModel`; consistent with existing patterns
- Pitfalls: HIGH — backward-compat test cases are concrete, Unicode safety is verified, score normalization is mathematically grounded

**Research date:** 2026-03-12
**Valid until:** 2026-09-12 (stable macOS 15 SDK + Swift 6 stdlib; algorithm is not framework-dependent)
