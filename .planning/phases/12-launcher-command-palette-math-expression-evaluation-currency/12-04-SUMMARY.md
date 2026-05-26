---
phase: 12-launcher-command-palette-math-expression-evaluation-currency
plan: "04"
subsystem: views+services+settings
tags:
  - swift
  - swiftui
  - appdelegate
  - settings
  - human-verify
dependency_graph:
  requires:
    - 12-01 (AppSettingsKeys, ExpressionEvaluator)
    - 12-02 (CurrencyService, UnitConversionService)
    - 12-03 (CommandPaletteService, CommandPaletteView, AppLaunchViewModel extensions)
  provides:
    - AppLaunchController with clipboardMonitor injection + copyResult() + isCommandPaletteMode-branched Return/Enter
    - AppDelegate wiring: CurrencyService + CommandPaletteService creation and injection
    - .clipsmithCurrencyRatesRefreshed notification path (Settings → AppDelegate reload)
    - Settings > Features Command Palette toggle, prefix field, Refresh rates button, timestamp/attribution
  affects:
    - Clipsmith/Views/AppLaunchController.swift
    - Clipsmith/App/AppDelegate.swift
    - Clipsmith/Views/Settings/GeneralSettingsTab.swift
    - Clipsmith/Views/MenuBarView.swift
tech-stack:
  added: []
  patterns:
    - Dual-instance CurrencyService pattern (AppDelegate owns live bezel instance, Settings owns local UI instance; both sync via .clipsmithCurrencyRatesRefreshed notification + shared on-disk file)
    - blockedChangeCount self-capture prevention applied to AppLaunchController.copyResult() (mirrors BezelController.applyTransform pattern)
key-files:
  created: []
  modified:
    - Clipsmith/Views/AppLaunchController.swift
    - Clipsmith/App/AppDelegate.swift
    - Clipsmith/Views/Settings/GeneralSettingsTab.swift
    - Clipsmith/Views/MenuBarView.swift
key-decisions:
  - "GeneralSettingsTab uses @State private var currencyService = CurrencyService() (local instance) following DocsetSettingsSection precedent — Settings manages own lifecycle, not injected from AppDelegate"
  - "Cross-instance rates sync via .clipsmithCurrencyRatesRefreshed notification + shared on-disk file — AppDelegate handler calls loadRates() which reads the same exchange-rates.json written by the Settings CurrencyService.refreshRates()"
  - ".task { currencyService.loadRates() } attached to Section(.Features) so bundled rates load when the settings tab opens, making the timestamp/lastUpdated state available before any user-initiated refresh"
requirements-completed:
  - D-01
  - D-02
  - D-03
  - D-10
  - D-13
  - D-14
duration: ~10min
completed: "2026-05-26T14:32:00Z"
checkpoint_state:
  status: awaiting-human-verify
  task: 3
  reason: "Human verification required for all 5 manual scenarios (D-01, D-02, D-10, D-13, Pitfall 6 / T-12-02)"
---

# Phase 12 Plan 04: Live Wiring + Settings UI Summary

AppLaunchController.copyResult() + clipboardMonitor injection, AppDelegate CurrencyService/CommandPaletteService wiring, .clipsmithCurrencyRatesRefreshed cross-instance sync, and Settings > Features Command Palette UI (toggle, prefix field, Refresh button with spinner/timestamp/attribution).

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-26T14:25:00Z
- **Completed (at checkpoint):** 2026-05-26T14:32:00Z
- **Tasks:** 2/3 complete (Task 3 is checkpoint:human-verify)
- **Files modified:** 4

## Accomplishments

- AppLaunchController: added `var clipboardMonitor: ClipboardMonitor?` injection point; implemented `copyResult()` with T-12-02 self-capture prevention; branched `sendEvent` and `keyDown` case 36/76 on `viewModel.isCommandPaletteMode` (routes to `copyResult()` in CP mode, `launchSelected()` otherwise)
- AppDelegate: creates `CurrencyService` (calls `loadRates()`), `CommandPaletteService(currencyService:)`, injects both into `appLaunchController.viewModel.commandPaletteService` and `appLaunchController.clipboardMonitor`; registers `.clipsmithCurrencyRatesRefreshed` observer so Settings refresh propagates to live bezel without restart
- MenuBarView: added `static let clipsmithCurrencyRatesRefreshed` to the `extension Notification.Name` block
- GeneralSettingsTab: added Command Palette toggle, prefix TextField (1-char, non-alphanumeric enforcement), Refresh exchange rates button with spinner/timestamp/error/attribution — all gated on `commandPaletteEnabled`

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | AppLaunchController: clipboardMonitor + copyResult() + sendEvent/keyDown branches | 3088fc3 | AppLaunchController.swift |
| 2 | AppDelegate wiring + Settings UI + MenuBarView notification name | 385c11c | AppDelegate.swift, GeneralSettingsTab.swift, MenuBarView.swift |
| 3 | CHECKPOINT: human-verify all 5 scenarios | — | pending human verification |

## Files Created/Modified

- `Clipsmith/Views/AppLaunchController.swift` — added clipboardMonitor injection + copyResult() + isCommandPaletteMode-branched Return/Enter in sendEvent and keyDown
- `Clipsmith/App/AppDelegate.swift` — Phase 12 stored properties + init block 10 + .clipsmithCurrencyRatesRefreshed observer/handler
- `Clipsmith/Views/Settings/GeneralSettingsTab.swift` — Command Palette UI section: toggle, prefix field, Refresh button, attribution
- `Clipsmith/Views/MenuBarView.swift` — clipsmithCurrencyRatesRefreshed Notification.Name entry

## Decisions Made

- **Local CurrencyService in Settings:** GeneralSettingsTab creates its own `@State private var currencyService = CurrencyService()` following the DocsetSettingsSection precedent from Phase 8-02 (STATE.md: "DocsetSettingsSection uses local @State DocsetManagerService — settings manages own lifecycle, not injected from AppDelegate"). This avoids passing the AppDelegate instance through the SwiftUI environment.

- **Cross-instance sync via notification:** When Settings' `currencyService.refreshRates()` succeeds, GeneralSettingsTab posts `.clipsmithCurrencyRatesRefreshed`. AppDelegate's `handleCurrencyRatesRefreshed()` calls `currencyService.loadRates()` which reads the same `~/Library/Application Support/Clipsmith/exchange-rates.json` file written by the Settings instance. Both instances stay in sync without restart.

- **blockedChangeCount applied immediately after pasteboard write:** In `copyResult()`, `clipboardMonitor?.blockedChangeCount = pasteboard.changeCount` is set synchronously on the same actor (MainActor), immediately after `pasteboard.setString(...)`. This ensures ClipboardMonitor's next polling cycle sees the blocked change count and skips the self-capture.

## Deviations from Plan

None — plan executed exactly as written. The worktree path safety issue (accidental edit to main repo files) was detected and corrected before any functional change landed on the wrong branch.

## Known Stubs

None. All UI is wired to live state. CurrencyService is initialized with real rates (bundled JSON), and the refresh button calls the real API.

## Threat Surface Scan

No new threat surface beyond what is documented in the plan's threat model:
- T-12-02: blockedChangeCount mitigation is in place in copyResult()
- T-12-03: refreshRates() uses existing typed Codable decode (Plan 02)
- T-12-04: prefix field enforces 1-char non-alphanumeric constraint in onChange

## Checkpoint State: AWAITING HUMAN VERIFICATION

**Task 3 is a `checkpoint:human-verify` gate.** The following scenarios require manual testing before this plan can be marked complete:

| Scenario | Decision | Focus |
|----------|----------|-------|
| 1 | D-01 | Prefix-only placeholder (bare "=" shows "Command Palette" header + dimmed "Invalid expression", reverts to app list on Backspace) |
| 2 | D-13 | "=2+2" → "4" result → Return → "Copied ✓" toast → bezel dismisses in ~1.5s → `pbpaste` confirms "4" |
| 3 | D-10 | Refresh button spinner → timestamp updates → `exchange-rates.json` written → `=10 USD to EUR` returns live rates WITHOUT app restart |
| 4 | D-02 | Prefix field rejects >1 char and alphanumeric; accepts ">" and activates CP mode with ">5+5" = "10" |
| 5 | T-12-02 | After `=99+1` Return, "100" NOT in Phase 3 clipboard history; copying other text via Cmd-C still appears |

The built app is at:
`/Users/haad/Library/Developer/Xcode/DerivedData/Clipsmith-ecrdqctlegmgsbdcxmchytzohmnd/Build/Products/Release/Clipsmith.app`

To build before launching:
```bash
xcodebuild build -scheme Clipsmith -destination 'platform=macOS'
```

## Self-Check

### Files exist:
- [x] Clipsmith/Views/AppLaunchController.swift (modified — contains clipboardMonitor + copyResult)
- [x] Clipsmith/App/AppDelegate.swift (modified — contains currencyService + commandPaletteService)
- [x] Clipsmith/Views/Settings/GeneralSettingsTab.swift (modified — contains Command Palette UI)
- [x] Clipsmith/Views/MenuBarView.swift (modified — contains clipsmithCurrencyRatesRefreshed)

### Commits exist:
- [x] 3088fc3 — feat(12-04): add clipboardMonitor injection + copyResult() to AppLaunchController
- [x] 385c11c — feat(12-04): wire CurrencyService and CommandPaletteService in AppDelegate

## Self-Check: PASSED
