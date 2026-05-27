# Phase 12: Launcher Command Palette — math expression evaluation, currency conversion, and unit conversion - Context

**Gathered:** 2026-05-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Extends the Phase 11 App Launcher bezel into a lightweight command palette. When the user types a configurable prefix character (default `=`), the bezel switches from app-search mode to command palette mode and evaluates the remaining text as a math expression, currency conversion, or unit conversion. Results are displayed in a full-width result card; Enter copies the result to clipboard.

This phase delivers:
- `CommandPaletteService` — parses queries, dispatches to math evaluator or unit/currency converter, returns `CommandResult`
- `ExpressionEvaluator` — NSExpression-based math engine with extended function support (sqrt, pow, sin, cos)
- `UnitConversionService` — Foundation Measurement-based converter for length, weight/mass, temperature, volume
- `CurrencyService` — loads bundled static rates JSON; downloads fresh rates on demand; converts currency pairs
- `CommandPaletteView` — SwiftUI result card shown in place of the app list when in `=` mode
- Settings > Features additions: `commandPaletteEnabled` toggle, prefix character field, "Refresh rates" button + last-updated timestamp

Out of scope: file search, web search, process management, live streaming rates, additional unit categories beyond the core four.

</domain>

<decisions>
## Implementation Decisions

### Mode Detection & Switching
- **D-01:** Explicit prefix character (default `=`) triggers command palette mode. When `searchText` starts with the prefix character, `AppLaunchViewModel` routes to command palette mode and hides the app list entirely. Typing only `=` (nothing after) shows an empty/placeholder result card; removing the prefix restores the app list instantly.
- **D-02:** The prefix character is user-configurable in Settings > Features tab (stored in UserDefaults via `@AppStorage` under a new `AppSettingsKeys.commandPalettePrefix` key; default `"="`). Changes take effect immediately — no restart required.

### Feature Flag
- **D-03:** The entire Phase 12 feature is gated behind `commandPaletteEnabled` in `AppSettingsKeys` (default `false`), consistent with `appLauncherEnabled` and `docLookupEnabled`. Labeled "Command Palette" in Settings > Features. When disabled: prefix detection is skipped, Settings UI elements are hidden.

### Math Evaluation Engine
- **D-04:** Use `NSExpression` for math evaluation — no third-party dependencies. The expression text (after stripping the prefix character) is passed to `NSExpression(format:)`. Catch any thrown exceptions and treat them as invalid expressions.
- **D-05:** Support extended functions beyond basic arithmetic: `sqrt()`, `pow()`, `sin()`, `cos()` via NSExpression's built-in function evaluation. Map user-friendly names (e.g., `sqrt(16)`) to NSExpression function syntax.
- **D-06:** Smart number formatting: if the result is a whole number, display as an integer (no decimal point). Otherwise, round to 6 significant figures. Use `NumberFormatter` for locale-aware thousands separators.

### Unit Conversions
- **D-07:** Use Foundation's `Measurement` API for unit conversions. Core categories: length (`UnitLength`), weight/mass (`UnitMass`), temperature (`UnitTemperature`), volume (`UnitVolume`). These four cover the vast majority of everyday conversion needs.
- **D-08:** Natural query syntax: `{value} {unit} to {unit}` and `{value} {unit} in {unit}`. Examples: `5 km to miles`, `100 F to C`, `2 liters in cups`. Parser is case-insensitive; common abbreviations and full names both accepted.

### Currency Conversions
- **D-09:** Ship a bundled static exchange rates JSON file (USD base, covering ~50 major currencies). This is the fallback when no updated rates have been downloaded.
- **D-10:** "Refresh rates" button in Settings > Features tab. Fetches fresh rates from a free open API (open.er-api.com). Saves the response JSON to `~/Library/Application Support/Clipsmith/exchange-rates.json`, overriding the bundled file for future lookups. The button shows a last-updated timestamp (read from the saved file's modification date). Network errors show an inline error message; the bundled rates remain active.
- **D-11:** Currency query syntax follows the same natural pattern: `10 USD to EUR`, `100 GBP in JPY`. Parser detects 3-letter ISO currency codes (case-insensitive).

### Result UI
- **D-12:** When in `=` mode, the app list is replaced by a full-width `CommandPaletteView`. Layout: expression text (secondary, smaller) at the top, large result value in the center. When the expression is invalid or incomplete, show a dimmed "Invalid expression" placeholder in the result area.
- **D-13:** Enter on a valid result: copies the result string to `NSPasteboard.general`, shows a brief "Copied ✓" toast overlay, then calls `hide()` to dismiss the bezel. Enter on an invalid expression is a no-op.
- **D-14:** The `CommandPaletteView` reuses the same frosted glass background (`.ultraThinMaterial` + `bezelAlpha` overlay) as `AppLaunchView` and other bezels for visual consistency.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Bezel Pattern (copy this structure)
- `Clipsmith/Views/AppLaunchController.swift` — NSPanel subclass; keyboard routing via `sendEvent` and `keyDown`; show/hide lifecycle with `registerClickOutsideMonitor`
- `Clipsmith/Views/AppLaunchViewModel.swift` — `@Observable @MainActor` ViewModel; `searchText` didSet triggers recomputation; `displayedApps` cached result
- `Clipsmith/Views/AppLaunchView.swift` — SwiftUI hosting view; frosted glass background; `@FocusState` for search field; result area replaces app list based on `viewModel` state

### Feature Flag Pattern
- `Clipsmith/Settings/AppSettingsKeys.swift` — add `commandPaletteEnabled` and `commandPalettePrefix` keys here
- `Clipsmith/Views/Settings/FeaturesSettingsTab.swift` (or equivalent) — where to add the toggle, prefix field, and Refresh rates button
- `Clipsmith/App/AppDelegate.swift` — feature flag guard pattern for the `=` prefix check; see `docLookupEnabled` block as reference

### Services to Reference
- `Clipsmith/Services/FuzzyMatcher.swift` — scoring pattern; unit test pattern for pure-Swift service
- `Clipsmith/Services/GistService.swift` — network call pattern (URLSession, error handling, async/await); reference for `CurrencyService` download

### Phase 11 Context (decisions that carry forward)
- `.planning/phases/11-app-launcher/11-CONTEXT.md` — all D-01–D-10 decisions about the bezel panel, hotkey, and feature flag pattern remain authoritative

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AppLaunchViewModel.searchText` — already a `@Observable` published string; add `var isCommandPaletteMode: Bool` computed from `searchText.hasPrefix(prefix)` to drive view switching
- `AppLaunchView` frosted glass background — copy the `ZStack { RoundedRectangle(.ultraThinMaterial) + opacity layer }` pattern verbatim for `CommandPaletteView`
- `AppLaunchController.sendEvent` — already intercepts Return/Enter (keyCodes 36, 76); route to `copyResult()` instead of `launchSelected()` when in command palette mode
- `NSPasteboard.general.setString` — used elsewhere in `PasteService`; use the same pattern for copying results

### Established Patterns
- **Non-activating panel** — `.nonactivatingPanel` in styleMask at `init` time (CRITICAL — cannot be changed afterwards)
- **Feature flag guard in AppDelegate** — register unconditionally; check `commandPaletteEnabled` inside the handler
- **`@AppStorage` + `AppSettingsKeys`** — all settings keys defined as static strings in `AppSettingsKeys.swift`
- **`@Observable @MainActor`** — all ViewModels follow this pattern; `CommandPaletteService` should also be `@MainActor` if it vends results to the ViewModel

### Integration Points
- `AppLaunchViewModel` — add `commandPaletteMode: Bool`, `commandResult: CommandResult?` properties; `recomputeDisplayedApps()` checks `isCommandPaletteMode` to short-circuit app filtering
- `AppLaunchView` — branch on `viewModel.commandPaletteMode` to show `CommandPaletteView` instead of `appListView`
- `AppLaunchController.launchSelected()` — rename/extend to also handle `copyResult()` when in command palette mode
- `HotkeySettingsTab.swift` — no changes needed (no new hotkey; uses existing launcher hotkey)
- Settings > Features tab — add: `commandPaletteEnabled` toggle, prefix character `TextField` (1-char limit), Refresh rates button + timestamp label

</code_context>

<specifics>
## Specific Ideas

- The experience should feel as snappy as the app launcher — no perceptible delay between typing and seeing the result. NSExpression evaluation is synchronous and fast enough for this.
- The "Refresh rates" download is a one-shot async action; show a spinner on the button while in-flight, then update the timestamp on success.
- Prefix character field in Settings should enforce a 1-character limit and reject alphanumeric characters (to avoid conflicts with app names).

</specifics>

<deferred>
## Deferred Ideas

- **Additional unit categories** (area, speed, pressure, data size, time) — Foundation supports these, but keep v1 focused on the core four.
- **Live streaming exchange rates** — real-time rates with auto-refresh. Adds complexity and network dependency; static + manual refresh is sufficient for v1.
- **File search** (`=find:term`) — out of scope for this phase.
- **Web search dispatch** (`=web:query`) — out of scope; would need browser handoff logic.
- **Per-capability feature flags** (`mathEvalEnabled`, `currencyEnabled`, `unitEnabled`) — one flag covers all three for v1; granular flags deferred until user demand is confirmed.

</deferred>

---

*Phase: 12-launcher-command-palette-math-expression-evaluation-currency*
*Context gathered: 2026-05-26*
