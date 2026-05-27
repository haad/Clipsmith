# Phase 11: App Launcher - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-25
**Phase:** 11-app-launcher
**Areas discussed:** App discovery scope, App icons, Search activation mode, Post-launch & activation policy, Initial display, Result ranking, Hotkey default

---

## App Discovery Scope

| Option | Description | Selected |
|--------|-------------|----------|
| /Applications + ~/Applications only | Fast, predictable, no system noise. Misses MAS system apps. | |
| All user-visible apps via NSWorkspace | Catches MAS apps, Utilities, /System/Applications. More complete. | ✓ |
| User decides | Let Claude pick the most practical default. | |

**User's choice:** All user-visible apps via NSWorkspace

---

### App Scan Freshness

| Option | Description | Selected |
|--------|-------------|----------|
| Cache on launch, refresh on open | Build list at startup, refresh each time bezel opens. | ✓ |
| Cache on launch only | Fastest; newly installed apps won't appear until restart. | |
| Scan on every open | Always fresh but adds delay. | |

**User's choice:** Cache on launch, refresh on open

---

## App Icons in the List

| Option | Description | Selected |
|--------|-------------|----------|
| Icon + app name | Standard launcher UX. NSWorkspace.icon(forFile:). | ✓ |
| Text-only | Consistent with existing bezels. Simpler view. | |

**User's choice:** Yes — icon + app name

---

## Search Activation Mode

| Option | Description | Selected |
|--------|-------------|----------|
| Instant type-to-filter | Open and type immediately. No secondary hotkey. | ✓ |
| Follow existing bezel pattern | Arrow keys first, hotkey to search. | |

**User's choice:** Instant type-to-filter

---

## Post-Launch & Activation Policy

### Post-launch behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Close bezel, app comes to front | NSWorkspace.open() activates launched app. | ✓ |
| Close bezel, app launches in background | Launched app doesn't steal focus. | |

### Panel activation
| Option | Description | Selected |
|--------|-------------|----------|
| Non-activating panel (same as clipboard bezel) | Clipsmith stays in background; panel becomes key for typing. | ✓ |
| Activating window | Clipsmith comes to front like Spotlight. | |

**User's choice:** Close + activate; non-activating panel

---

## Initial Display (no text typed)

| Option | Description | Selected |
|--------|-------------|----------|
| All apps alphabetically | Full list, can scroll or type. | |
| Empty with placeholder | Clean; user must type to see anything. | |
| Recently launched apps | Shows last N launched apps for fast re-opening. | ✓ |

### Count of recent apps
| Option | Description | Selected |
|--------|-------------|----------|
| 5 recent apps | Compact, covers common case. | ✓ |
| 10 recent apps | More context for heavy context-switchers. | |

**User's choice:** 5 most recently launched apps

---

## Result Ranking

| Option | Description | Selected |
|--------|-------------|----------|
| Fuzzy score + recency boost | FuzzyMatcher score; recency boosts close matches. | ✓ |
| Pure fuzzy score | Match quality only. Deterministic. | |

**User's choice:** Fuzzy score + recency boost

---

## Hotkey Default

| Option | Description | Selected |
|--------|-------------|----------|
| Cmd-Shift-Space | Parallels Spotlight. Not used by existing bezels. | |
| Cmd-Shift-A | Consistent with Clipsmith letter pattern. | |
| No default — user configures | No system conflicts. Requires user setup. | ✓ |

**User's choice:** No default — user must configure their own binding

---

## Claude's Discretion

None — all areas had explicit user decisions.

## Deferred Ideas

- **Inline launcher calculations / unit / currency conversions** — User mentioned this as a potential future capability ("simple match questions, currency conversions, unit conversions"). Would turn the launcher into a general-purpose command palette. Deferred to a future phase after the base launcher ships.
