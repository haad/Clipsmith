---
phase: 12-launcher-command-palette-math-expression-evaluation-currency
plan: "01"
subsystem: services
tags:
  - swift
  - nsexpression
  - math
  - settings
  - testing
dependency_graph:
  requires: []
  provides:
    - ExpressionEvaluator service (safe-chars gate + NSExpression evaluation)
    - commandPaletteEnabled / commandPalettePrefix AppSettingsKeys + UserDefaults defaults
    - Wave 0 test stubs for UnitConversionService, CurrencyService, CommandPaletteService
  affects:
    - Clipsmith/Settings/AppSettingsKeys.swift
    - Clipsmith/App/AppDelegate.swift
    - Clipsmith.xcodeproj/project.pbxproj
tech_stack:
  added:
    - NSExpression (Foundation) for math evaluation
    - NSRegularExpression for safe-chars gate (T-12-01 mitigation)
  patterns:
    - nonisolated struct as enum-style namespace for stateless service
    - @MainActor on evaluate(_:) — matches Architectural Responsibility Map
    - Safe-chars regex gate before every NSExpression(format:) call site
    - intDivByZeroRegex pre-check for NSExpression silent 0-return on integer division
key_files:
  created:
    - Clipsmith/Services/ExpressionEvaluator.swift
    - ClipsmithTests/ExpressionEvaluatorTests.swift
    - ClipsmithTests/UnitConversionServiceTests.swift
    - ClipsmithTests/CurrencyServiceTests.swift
    - ClipsmithTests/CommandPaletteServiceTests.swift
  modified:
    - Clipsmith/Settings/AppSettingsKeys.swift
    - Clipsmith/App/AppDelegate.swift
    - Clipsmith.xcodeproj/project.pbxproj
decisions:
  - "Locale(identifier: en_US) used in NumberFormatter for formatResult — deterministic test output per plan spec; no deviation"
  - "sin/cos deferred per RESEARCH.md Open Question 1 — documented in ExpressionEvaluator.swift file-level comment"
  - "intDivByZeroRegex added to catch NSExpression silent 10/0=0.0 behavior — NSExpression returns 0.0 not Infinity/NaN for integer division by zero"
metrics:
  duration_minutes: 6
  completed_date: "2026-05-26T10:11:48Z"
  tasks_completed: 3
  files_changed: 8
---

# Phase 12 Plan 01: ExpressionEvaluator Foundation Summary

NSExpression-backed math service with mandatory T-12-01 safe-chars regex gate, ^→** preprocessing, integer-division-by-zero guard, and Wave 0 test stubs for Plans 02/03.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | AppSettingsKeys + defaults + Wave 0 test stubs (TDD RED) | 9de41d2 | AppSettingsKeys.swift, AppDelegate.swift, 4 test files |
| 2+3 | ExpressionEvaluator implementation + pbxproj registration (TDD GREEN) | a4b5d45 | ExpressionEvaluator.swift, project.pbxproj |

## PBX ID Assignments

| File | File Ref ID | Build File ID | Target |
|------|-------------|---------------|--------|
| Clipsmith/Services/ExpressionEvaluator.swift | AF0089 | AA0088 | Main app Sources |
| ClipsmithTests/ExpressionEvaluatorTests.swift | AF0090 | AA0089 | BB0005 test Sources |
| ClipsmithTests/UnitConversionServiceTests.swift | AF0091 | AA0090 | BB0005 test Sources |
| ClipsmithTests/CurrencyServiceTests.swift | AF0092 | AA0091 | BB0005 test Sources |
| ClipsmithTests/CommandPaletteServiceTests.swift | AF0093 | AA0092 | BB0005 test Sources |

No PBX ID collisions — each new ID appears exactly twice (AA: PBXBuildFile + Sources phase) or three times (AF: PBXBuildFile comment, PBXFileReference, group children).

## Safe-Chars Gate Confirmation

T-12-01 mitigation is in place. Every call to `NSExpression(format:)` is preceded by:
1. `safeMathRegex` check on the expression with function names stripped
2. `intDivByZeroRegex` check to catch NSExpression's silent `10/0=0.0` return

No call site reaches `NSExpression(format:)` without passing both gates.

## Test Suite Results

- `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` — 202 tests, 3 skipped, 0 failures — **PASSED**
- `xcodebuild test -only-testing:ClipsmithTests/ExpressionEvaluatorTests` — 6 tests, 0 failures — **PASSED**
- UnitConversionServiceTests, CurrencyServiceTests, CommandPaletteServiceTests — each skipped via `XCTSkipIf(true, "Stub — Plan NN...")`

## D-06 Locale Note

`formatResult(_:)` uses `Locale(identifier: "en_US")` in `NumberFormatter` as specified in the plan. This ensures deterministic test output. No deviation from plan spec.

## sin/cos Deferral

`sin()` and `cos()` are listed in D-05 but require a separate pre-processor (RESEARCH.md Open Question 1). They are not implemented in this plan. A file-level doc comment in `ExpressionEvaluator.swift` documents this deferral explicitly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Integer division by zero (NSExpression silent 0.0 return)**
- **Found during:** Task 2 TDD GREEN — `testIntegerDivisionByZeroReturnsNil` failed with `XCTAssertNil failed: "0.0"`
- **Issue:** NSExpression evaluates `10 / 0` as integer division and returns `0.0`, not `Infinity` or `NaN`. The existing `isNaN`/`isInfinite` guard does not catch this case.
- **Fix:** Added `intDivByZeroRegex` (`/\s*0(?![.\d])`) that detects integer division by zero before calling `NSExpression(format:)`. Float division by zero (e.g., `10.0 / 0.0`) still returns Infinity which is caught by the existing guard.
- **Files modified:** `Clipsmith/Services/ExpressionEvaluator.swift`
- **Commit:** a4b5d45

## Self-Check

### Files exist:
- [x] Clipsmith/Services/ExpressionEvaluator.swift
- [x] ClipsmithTests/ExpressionEvaluatorTests.swift
- [x] ClipsmithTests/UnitConversionServiceTests.swift
- [x] ClipsmithTests/CurrencyServiceTests.swift
- [x] ClipsmithTests/CommandPaletteServiceTests.swift
- [x] Clipsmith/Settings/AppSettingsKeys.swift (modified)
- [x] Clipsmith/App/AppDelegate.swift (modified)
- [x] Clipsmith.xcodeproj/project.pbxproj (modified)

### Commits exist:
- [x] 9de41d2 — test(12-01): add AppSettingsKeys keys, UserDefaults defaults, and Wave 0 test stubs (TDD RED)
- [x] a4b5d45 — feat(12-01): implement ExpressionEvaluator with safe-chars gate and register Phase 12 files in pbxproj (TDD GREEN)

## Self-Check: PASSED
