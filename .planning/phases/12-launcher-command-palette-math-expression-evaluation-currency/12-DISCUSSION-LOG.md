# Phase 12: Launcher Command Palette — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-26
**Phase:** 12-launcher-command-palette-math-expression-evaluation-currency
**Areas discussed:** Detection strategy, Math evaluation engine, Currency & unit data, Result UI & Enter behavior, Feature flag

---

## Detection Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Implicit auto-detect | Try to parse every query as math/conversion; show result if valid | |
| Explicit prefix `=` | User types `=` first to enter calculator mode | ✓ |
| Explicit prefix, user-configurable | Default `=` but user can change in Settings | (folded into selected) |

**User's choice:** Explicit prefix `=`, AND the prefix character should be user-configurable in Settings > Features tab.

**Notes:** When `=` prefix is detected, the app list is hidden entirely (clean separation of modes). Prefix stored in `AppSettingsKeys.commandPalettePrefix` with default `"="`. User confirmed Settings > Features tab (next to the existing app launcher toggle) as the right location.

---

## Math Evaluation Engine

| Option | Description | Selected |
|--------|-------------|----------|
| NSExpression | Apple's built-in evaluator; arithmetic + math functions; no dependencies | ✓ |
| JavaScriptCore | Full JS math; powerful but heavyweight | |
| Pure Swift parser | Full control; significant implementation effort | |

**User's choice:** NSExpression

**Notes:** Extended functions requested (sqrt, pow, sin, cos) — not just basic arithmetic. Smart number formatting: integers shown without decimal point, decimals rounded to 6 sig-figs.

---

## Currency & Unit Data

| Option | Description | Selected |
|--------|-------------|----------|
| Free public API, fetched on demand | Live rates; cache with TTL; offline fallback | |
| Bundled static rates, updated with releases | Ships JSON; no network; rates go stale | ✓ (+ download action) |
| Apple's built-in currency info | NSLocale metadata only; not practical | |

**User's choice:** Bundled static rates as baseline, with a "Refresh rates" button in Settings > Features tab that downloads fresh rates from a free open API (open.er-api.com) and saves to app support directory.

**Notes:** Shows last-updated timestamp next to the Refresh button. Errors during download leave the bundled rates active. Unit categories: length, weight/mass, temperature, volume (Foundation Measurement API). Natural query syntax: `{value} {unit} to {unit}` and `{value} {unit} in {unit}`.

---

## Result UI & Enter Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Full-width result card replacing app list | Dedicated result area; clean, focused | ✓ |
| Top pinned result row in list | Highlighted first row; app results below | |

| Enter behavior | Description | Selected |
|----------------|-------------|----------|
| Copy + 'Copied' toast + dismiss | Writes to pasteboard, brief confirmation, closes bezel | ✓ |
| Copy without toast, just dismiss | Quieter UX | |
| Copy and keep bezel open | Allows chaining | |

| Invalid expression | Description | Selected |
|-------------------|-------------|----------|
| Show 'Invalid expression' placeholder, Enter no-op | Dimmed hint; prevents copying garbage | ✓ |
| Empty result area until valid | Silent | |
| Show last valid result | More complex state | |

**User's choice:** Full-width result card, copy + toast + dismiss on Enter, 'Invalid expression' placeholder on bad input.

---

## Feature Flag

| Option | Description | Selected |
|--------|-------------|----------|
| Single `commandPaletteEnabled` flag | One toggle covers all three capabilities | ✓ |
| Separate flags per capability | `mathEvalEnabled`, `currencyEnabled`, `unitEnabled` | |

**User's choice:** Single `commandPaletteEnabled` flag in AppSettingsKeys (default `false`), labeled "Command Palette" in Settings > Features. Consistent with `appLauncherEnabled` and `docLookupEnabled` patterns.

---

## Claude's Discretion

- Number formatting details (exactly how 6 sig-figs are rendered)
- Exact unit abbreviation list and aliases for the parser
- Toast animation style and duration
- Exact API endpoint for currency rate refresh

## Deferred Ideas

- Additional unit categories (area, speed, pressure, data size, time) — Foundation supports these; defer to v2
- Live streaming exchange rates with auto-refresh
- File search dispatch (`=find:term`)
- Web search dispatch (`=web:query`)
- Per-capability feature flags
