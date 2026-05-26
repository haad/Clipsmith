---
phase: 12-launcher-command-palette-math-expression-evaluation-currency
plan: "03"
subsystem: services+views
tags:
  - swift
  - swiftui
  - observable
  - mainactor
  - testing
dependency_graph:
  requires:
    - 12-01 (ExpressionEvaluator, AppSettingsKeys)
    - 12-02 (UnitConversionService, CurrencyService)
  provides:
    - CommandResult (Sendable+Equatable value type)
    - CommandPaletteService (@MainActor @Observable dispatch layer)
    - CommandPaletteView (SwiftUI result card with toast overlay)
    - AppLaunchViewModel extensions (isCommandPaletteMode, commandResult, showCopiedToast, service injection)
    - AppLaunchView command-palette branch (header/placeholder/footer swapped)
  affects:
    - Clipsmith/Services/CommandPaletteService.swift (created)
    - Clipsmith/Views/CommandPaletteView.swift (created)
    - Clipsmith/Views/AppLaunchViewModel.swift (modified)
    - Clipsmith/Views/AppLaunchView.swift (modified)
    - ClipsmithTests/CommandPaletteServiceTests.swift (replaced XCTSkip stub)
    - ClipsmithTests/AppLaunchViewModelTests.swift (extended)
    - Clipsmith.xcodeproj/project.pbxproj (modified)
tech_stack:
  added:
    - Observation framework (CommandPaletteService @Observable)
  patterns:
    - "@MainActor @Observable" dispatch service orchestrating three pure converters
    - CommandResult Sendable+Equatable value type for cross-actor result passing
    - Weak injection point (setCurrencyService) to avoid retain cycle with AppDelegate-owned service
    - SwiftUI Group branch pattern for mode switching inside AppLaunchView
    - .overlay(alignment: .bottom) for Copied ✓ toast without layout disruption
key_files:
  created:
    - Clipsmith/Services/CommandPaletteService.swift
    - Clipsmith/Views/CommandPaletteView.swift
  modified:
    - Clipsmith/Views/AppLaunchViewModel.swift
    - Clipsmith/Views/AppLaunchView.swift
    - ClipsmithTests/CommandPaletteServiceTests.swift
    - ClipsmithTests/AppLaunchViewModelTests.swift
    - Clipsmith.xcodeproj/project.pbxproj
decisions:
  - "Dispatch order is currency → unit → math (Pitfall 5: 3-letter ISO pairs must not fall through to UnitConversionService)"
  - "currencyService declared weak on CommandPaletteService to avoid retain cycle AppDelegate→CommandPaletteService→CurrencyService→AppDelegate state"
  - "setCurrencyService(_:) injection method (separate from init) because AppLaunchViewModel creates CommandPaletteService before AppDelegate finishes wiring"
  - "isCommandPaletteMode is computed not stored so runtime flag/prefix changes take effect immediately"
  - "CommandPaletteView does not add its own background — relies on AppLaunchView outer ZStack (D-14 visual consistency)"
  - "Footer navigation counter hidden in command palette mode (empty string Text) — 'N of M' is meaningless with no app list"
metrics:
  duration_minutes: 12
  completed_date: "2026-05-26T14:20:00Z"
  tasks_completed: 3
  files_changed: 7
---

# Phase 12 Plan 03: CommandPaletteService Orchestration Layer Summary

Dispatch layer (CommandPaletteService) with currency→unit→math ordering, CommandResult value type, AppLaunchViewModel command-palette state extensions, and CommandPaletteView result card with Copied ✓ toast overlay.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | CommandResult + CommandPaletteService + tests (TDD) | 902f8af | CommandPaletteService.swift, CommandPaletteServiceTests.swift, project.pbxproj |
| 2 | AppLaunchViewModel command-palette state + tests (TDD) | 933c135 | AppLaunchViewModel.swift, AppLaunchViewModelTests.swift |
| 3 | CommandPaletteView + AppLaunchView branch + build/test | ac3bfaa | CommandPaletteView.swift, AppLaunchView.swift |

## PBX ID Assignments

| File | File Ref ID | Build File ID | Target |
|------|-------------|---------------|--------|
| Clipsmith/Services/CommandPaletteService.swift | AF0097 | AA0096 | Main app Sources (BB0002) |
| Clipsmith/Views/CommandPaletteView.swift | AF0098 | AA0097 | Main app Sources (BB0002) |

No PBX ID collisions — IDs AF0097/AF0098 and AA0096/AA0097 are each new and sequential from Plan 02's highest (AF0096, AA0095).

## Dispatch Order Confirmation

The ordering in `CommandPaletteService.evaluate(_:)` is:

1. **Currency FIRST** — `CurrencyService.isCurrencyQuery(from:to:)` checks both tokens against `^[A-Z]{3}$`. If matched, route to `CurrencyService.convert`; on nil return nil (no fallthrough). This prevents "10 USD to EUR" from being misrouted to UnitConversionService (Pitfall 5).
2. **Unit SECOND** — `UnitConversionService.convert(_:)` handles physical-unit queries like "5 km to miles".
3. **Math LAST** — `ExpressionEvaluator.evaluate(_:)` handles bare expressions like "2+2" or "sqrt(16)". These never contain " to " or " in " so they skip the conversion shape regex entirely.

## Tests Added in Plan 03

| Suite | Tests Added | Total |
|-------|-------------|-------|
| CommandPaletteServiceTests | 13 (replaced 1 XCTSkip stub) | 13 |
| AppLaunchViewModelTests | 8 new Phase 12 tests | 12 (4 Phase 11 + 8 Phase 12) |
| **Total new tests** | **21** | — |

Full suite: 242 tests, 0 failures, 0 skipped.

## Wave 0 Stubs Status

All Wave 0 XCTSkipIf stubs are now filled in:
- ExpressionEvaluatorTests — filled in Plan 01
- UnitConversionServiceTests — filled in Plan 02
- CurrencyServiceTests — filled in Plan 02
- CommandPaletteServiceTests — filled in Plan 03 (this plan)

`grep -l XCTSkipIf ClipsmithTests/*.swift` returns empty.

## Plan 04 Integration Notes

Plan 04 will wire `CommandPaletteService` and `CurrencyService` into `AppLaunchViewModel` from `AppDelegate.applicationDidFinishLaunching` via:
```swift
viewModel.commandPaletteService = commandPaletteService
commandPaletteService.setCurrencyService(currencyService)
```

Plan 04 will also route the Enter key in `AppLaunchController` to call `copyResult()` which sets `viewModel.showCopiedToast = true`, triggering the Copied ✓ overlay in CommandPaletteView.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. CommandPaletteView receives live state from AppLaunchViewModel which evaluates real expressions via CommandPaletteService. The service injection point (`commandPaletteService`) is nil until Plan 04 wires it from AppDelegate — this is by design (documented in the plan) and does not affect correctness of the view layer.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes were introduced. The threat mitigations from the plan's threat register are in place:
- **T-12-01b**: CommandPaletteService adds no new NSExpression call sites — all validation is in the downstream services.
- **T-12-04**: `isCommandPaletteMode` uses `String.hasPrefix()` only — no shell, no eval, no interpolation.

## Self-Check

### Files exist:
- [x] Clipsmith/Services/CommandPaletteService.swift
- [x] Clipsmith/Views/CommandPaletteView.swift
- [x] Clipsmith/Views/AppLaunchViewModel.swift (modified)
- [x] Clipsmith/Views/AppLaunchView.swift (modified)
- [x] ClipsmithTests/CommandPaletteServiceTests.swift (replaced stub)
- [x] ClipsmithTests/AppLaunchViewModelTests.swift (extended)
- [x] Clipsmith.xcodeproj/project.pbxproj (modified)

### Commits exist:
- [x] 902f8af — feat(12-03): implement CommandResult + CommandPaletteService with dispatch order (TDD GREEN)
- [x] 933c135 — feat(12-03): extend AppLaunchViewModel with command-palette state and isCommandPaletteMode (TDD GREEN)
- [x] ac3bfaa — feat(12-03): add CommandPaletteView and AppLaunchView command-palette branch

## Self-Check: PASSED
