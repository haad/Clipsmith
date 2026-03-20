---
phase: 10-lemon-squeezy-licensing-monetization
plan: 01
subsystem: licensing
tags: [license, lemon-squeezy, monetization, tdd, url-session]
dependency_graph:
  requires: []
  provides: [LicenseService, LicenseError, LSActivateResponse, LSValidateResponse, LSDeactivateResponse, LSLicenseKey, LSInstance, LSMeta]
  affects: [AppSettingsKeys, ClipsmithTests]
tech_stack:
  added: []
  patterns: [MockURLProtocol reuse, @MainActor @Observable service, injectable URLSession, Codable form-encoded API]
key_files:
  created:
    - Clipsmith/Services/LicenseService.swift
    - ClipsmithTests/LicenseServiceTests.swift
  modified:
    - Clipsmith/Settings/AppSettingsKeys.swift
    - Clipsmith.xcodeproj/project.pbxproj
decisions:
  - "[Phase 10-01]: httpBodyStream fallback used in URLProtocol request handler — URLSession ephemeral config delivers POST body via httpBodyStream, not httpBody, in MockURLProtocol"
  - "[Phase 10-01]: Free function default params use literal 0 not LicenseService.expectedStoreId — Swift compiler cannot resolve type default params in @testable import context for top-level private functions"
  - "[Phase 10-01]: expectedStoreId/expectedProductId declared static let (not private) — required for test helpers to reference them without coupling"
metrics:
  duration: 6 min
  completed_date: "2026-03-20"
  tasks_completed: 2
  files_changed: 4
---

# Phase 10 Plan 01: LicenseService Foundation Summary

Lemon Squeezy License API client with activate/validate/deactivate, offline tolerance, and 11 passing unit tests.

## What Was Built

### LicenseService.swift

`@MainActor @Observable final class LicenseService` implementing:

- `activate(key:)` — POSTs to `/activate`, verifies `storeId + productId` against hardcoded constants (anti-cross-product attack), persists `licenseKey + licenseInstanceId` to UserDefaults
- `validate()` — POSTs to `/validate` using persisted `instance_id`; tolerates URLErrors without revoking existing license (Pitfall 2 from RESEARCH.md)
- `deactivate()` — POSTs to `/deactivate`, clears both UserDefaults keys, sets isLicensed=false
- `static func shouldShowNag() -> Bool` — returns true if no `lastNagShownDate` or date was >30 days ago

All six Codable response types (`LSActivateResponse`, `LSValidateResponse`, `LSDeactivateResponse`, `LSLicenseKey`, `LSInstance`, `LSMeta`) with snake_case CodingKeys mapping.

`LicenseError` enum with five cases: `wrongProduct`, `activationLimitReached`, `invalidKey`, `networkError(Error)`, `apiError(String)`.

### LicenseServiceTests.swift

11 tests, all green:

| Test | Verifies |
|------|---------|
| `testActivateSuccess` | isLicensed=true, UserDefaults persisted |
| `testActivateWrongProduct` | LicenseError.wrongProduct on storeId mismatch |
| `testActivateInvalidKey` | Error thrown on activated=false response |
| `testActivateActivationLimitReached` | LicenseError.activationLimitReached on "limit" error |
| `testValidateUsesInstanceId` | POST body contains `instance_id`, not `instance_name` |
| `testValidateNetworkErrorKeepsLicense` | URLError does NOT revoke isLicensed |
| `testValidateApiRejectionRevokesLicense` | valid=false clears UserDefaults + isLicensed |
| `testDeactivateClearsState` | licenseKey/instanceId cleared, isLicensed=false |
| `testShouldShowNagNilDate` | shouldShowNag=true when no date set |
| `testShouldShowNag31DaysAgo` | shouldShowNag=true after 31 days |
| `testShouldShowNag29DaysAgo` | shouldShowNag=false within 30 days |

### AppSettingsKeys.swift

Added three keys: `licenseKey`, `licenseInstanceId`, `lastNagShownDate`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] URLProtocol httpBodyStream required for request body capture in tests**

- **Found during:** Task 2 — testValidateUsesInstanceId
- **Issue:** `request.httpBody` was nil in `MockURLProtocol.startLoading()` when using ephemeral URLSession config; URLSession delivers the POST body via `httpBodyStream` in this context
- **Fix:** Extended test handler to read `httpBodyStream` as a fallback when `httpBody` is nil
- **Files modified:** `ClipsmithTests/LicenseServiceTests.swift`
- **Commit:** 6cd7b72

**2. [Rule 1 - Bug] Free function default params cannot reference @testable module types**

- **Found during:** Task 2 compile — "Cannot find 'LicenseService' in scope"
- **Issue:** Default parameter values in top-level private functions are evaluated before `@testable import Clipsmith` resolution; `LicenseService.expectedStoreId` caused a compile error
- **Fix:** Changed default values from `LicenseService.expectedStoreId` to literal `0` (matching the placeholder value)
- **Files modified:** `ClipsmithTests/LicenseServiceTests.swift`
- **Commit:** 6cd7b72 (included in same commit)

## Self-Check: PASSED

- FOUND: `Clipsmith/Services/LicenseService.swift`
- FOUND: `ClipsmithTests/LicenseServiceTests.swift`
- FOUND: commit aab0fac (feat 10-01: LicenseService)
- FOUND: commit 6cd7b72 (test 10-01: LicenseServiceTests)
