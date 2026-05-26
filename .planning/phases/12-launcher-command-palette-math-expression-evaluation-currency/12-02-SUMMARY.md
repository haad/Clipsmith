---
phase: 12-launcher-command-palette-math-expression-evaluation-currency
plan: "02"
subsystem: services
tags:
  - swift
  - foundation-measurement
  - currency-api
  - testing
dependency_graph:
  requires:
    - 12-01 (AppSettingsKeys, Wave 0 test stubs)
  provides:
    - UnitConversionService (nonisolated struct, full alias table, currency disambiguator)
    - CurrencyService (@MainActor @Observable, bundled+downloaded rates, refresh)
    - exchange-rates-bundled.json (45 ISO currencies, USD base)
    - Full test coverage for UnitConversionServiceTests and CurrencyServiceTests
  affects:
    - Clipsmith/Services/UnitConversionService.swift (created)
    - Clipsmith/Services/CurrencyService.swift (created)
    - Clipsmith/Resources/exchange-rates-bundled.json (created)
    - ClipsmithTests/UnitConversionServiceTests.swift (replaced XCTSkip stub)
    - ClipsmithTests/CurrencyServiceTests.swift (replaced XCTSkip stub)
    - Clipsmith.xcodeproj/project.pbxproj (modified)
tech_stack:
  added:
    - Foundation.Measurement / UnitLength / UnitMass / UnitTemperature / UnitVolume
    - NSRegularExpression (query parser for unit conversion)
    - URLSession async/await (currency rate refresh)
    - JSONDecoder + Codable (ExchangeRateResponse typed decode, T-12-03 mitigation)
    - OSLog Logger (CurrencyService diagnostic logging)
    - Observation framework (@Observable macro for CurrencyService)
  patterns:
    - nonisolated struct as stateless service (UnitConversionService)
    - "@MainActor @Observable" for stateful service with SwiftUI binding (CurrencyService)
    - Decode-before-write ordering (T-12-03 defence-in-depth)
    - MockURLProtocol pattern for URLSession test injection (MockURLProtocolForCurrency)
    - Bundle.main fallback for bundled resources (mirrors PromptSyncService)
key_files:
  created:
    - Clipsmith/Services/UnitConversionService.swift
    - Clipsmith/Services/CurrencyService.swift
    - Clipsmith/Resources/exchange-rates-bundled.json
  modified:
    - ClipsmithTests/UnitConversionServiceTests.swift
    - ClipsmithTests/CurrencyServiceTests.swift
    - Clipsmith.xcodeproj/project.pbxproj
decisions:
  - "UnitConversionService isCurrencyPair checks both tokens against ^[A-Z]{3}$ before alias lookup — routes 3-letter ISO pairs to CurrencyService (Pitfall 5)"
  - "CurrencyService.downloadedRatesURL is internal not private — test tearDown can clean up the file without requiring test helpers in production code"
  - "CurrencyServiceTests uses MockURLProtocolForCurrency (distinct name from MockURLProtocol in GistServiceTests) — avoids ambiguous Swift module-scoped symbol in same test target"
  - "exchange-rates-bundled.json uses plausible 2026-05-26 spot rates for 45 ISO currencies — exact values not asserted in tests; only non-nil conversion checked"
  - "Test for bundled JSON load uses loadRates() directly; no setRatesForTesting helper needed since exchange-rates-bundled.json is registered in main app Sources and loads via Bundle.main"
  - "T-12-03 decode-before-write: JSONDecoder().decode called on raw data before data.write(to:); testRefreshRatesMalformedJSONSetsErrorWithoutCorruptingDisk verifies no file created on bad response"
metrics:
  duration_minutes: 15
  completed_date: "2026-05-26T10:35:00Z"
  tasks_completed: 3
  files_changed: 6
---

# Phase 12 Plan 02: UnitConversionService + CurrencyService Summary

Foundation.Measurement-backed unit conversion service and open.er-api.com currency service with bundled-first/downloaded-first rate loading, atomic write after decode (T-12-03), and complete XCTest coverage replacing Wave 0 stubs.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | UnitConversionService with full alias table and tests (TDD) | 48c0388 | UnitConversionService.swift, UnitConversionServiceTests.swift |
| 2 | CurrencyService + exchange-rates-bundled.json + tests (TDD) | 944d644 | CurrencyService.swift, exchange-rates-bundled.json, CurrencyServiceTests.swift |
| 3 | Register all files in project.pbxproj; verify full test suite | 95b890d | project.pbxproj |

## PBX ID Assignments

| File | File Ref ID | Build File ID | Target |
|------|-------------|---------------|--------|
| Clipsmith/Services/UnitConversionService.swift | AF0094 | AA0093 | Main app Sources (BB0002) |
| Clipsmith/Services/CurrencyService.swift | AF0095 | AA0094 | Main app Sources (BB0002) |
| Clipsmith/Resources/exchange-rates-bundled.json | AF0096 | AA0095 | Main app Resources (BB0003) |

No PBX ID collisions — each new ID appears exactly twice (AA: PBXBuildFile + Sources/Resources phase) or three times (AF: PBXBuildFile comment, PBXFileReference, group children).

## Bundled Exchange Rates JSON

- **Source:** Plausible spot rates as of research date 2026-05-26, shaped to match open.er-api.com v6 response
- **Rate entries:** 45 ISO currencies (USD, EUR, GBP, JPY, CAD, AUD, CHF, CNY, HKD, SEK, NOK, DKK, NZD, SGD, INR, MXN, BRL, ZAR, KRW, TRY, AED, SAR, THB, MYR, IDR, PHP, CZK, HUF, PLN, ILS, EGP, NGN, PKR, BDT, VND, COP, ARS, CLP, PEN, RON, BGN, HRK, UAH, TWD, RUB)
- **Base currency:** USD
- **Validation:** `python3 -m json.tool` exits 0; tests load 45 rates via Bundle.main

## T-12-03 Ordering Confirmation

`refreshRates()` calls `JSONDecoder().decode(ExchangeRateResponse.self, from: data)` **before** `data.write(to: downloadedRatesURL, options: .atomic)`. A response that fails to decode is discarded — the on-disk cache is never overwritten with malformed or malicious content. The test `testRefreshRatesMalformedJSONSetsErrorWithoutCorruptingDisk` verifies this ordering explicitly.

## Test Strategy: Bundle Resource vs setRatesForTesting Helper

Tests use direct `loadRates()` calls backed by `Bundle.main.url(forResource: "exchange-rates-bundled", withExtension: "json")`. The JSON file is registered in the main app's `PBXResourcesBuildPhase` (BB0003). Since the test target links the main app bundle, `Bundle.main` resolves to the app bundle which includes the resource — no `setRatesForTesting` helper was needed.

## Test Suite Results

- `xcodebuild test -only-testing:ClipsmithTests/UnitConversionServiceTests` — 12 tests, 0 failures — **PASSED**
- `xcodebuild test -only-testing:ClipsmithTests/CurrencyServiceTests` — 10 tests, 0 failures — **PASSED**
- `xcodebuild test -scheme Clipsmith` — 222 tests, 1 skipped, 0 failures — **PASSED**
- Only remaining XCTSkip: `CommandPaletteServiceTests.swift` (Plan 03 territory)

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Additional Tests

The plan specified at least 11 unit conversion tests; 12 were implemented (added `testKilometersToMilesUsingInPreposition` to explicitly cover the D-08 `"in"` preposition variant). The plan specified at least 9 currency tests; 10 were implemented (added `testInitialStateIsEmpty` to cover the initial-state contract specified in the behavior section).

## Threat Flags

None — all new surface was covered by the plan's threat model (T-12-03 for JSON decode ordering, T-12-04 for regex input validation in UnitConversionService).

## Self-Check

### Files exist:
- [x] Clipsmith/Services/UnitConversionService.swift
- [x] Clipsmith/Services/CurrencyService.swift
- [x] Clipsmith/Resources/exchange-rates-bundled.json
- [x] ClipsmithTests/UnitConversionServiceTests.swift (replaced stub)
- [x] ClipsmithTests/CurrencyServiceTests.swift (replaced stub)
- [x] Clipsmith.xcodeproj/project.pbxproj (modified)

### Commits exist:
- [x] 48c0388 — feat(12-02): implement UnitConversionService with full alias table and tests
- [x] 944d644 — feat(12-02): implement CurrencyService with bundled JSON fallback and tests
- [x] 95b890d — chore(12-02): register UnitConversionService, CurrencyService, and bundled rates JSON in pbxproj

## Self-Check: PASSED
