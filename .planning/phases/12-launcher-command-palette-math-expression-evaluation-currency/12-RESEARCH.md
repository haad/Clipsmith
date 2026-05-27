# Phase 12: Launcher Command Palette — Research

**Researched:** 2026-05-26
**Domain:** NSExpression math evaluation, Foundation Measurement unit conversion, open.er-api.com currency API, SwiftUI bezel integration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Prefix character `=` (default) triggers command palette mode. `searchText.hasPrefix(prefix)` routes to command palette, app list hidden entirely. Typing only `=` shows placeholder card; removing prefix restores app list instantly.
- **D-02:** Prefix character is user-configurable, stored in `UserDefaults` via `@AppStorage(AppSettingsKeys.commandPalettePrefix)`, default `"="`. Changes take effect immediately.
- **D-03:** Entire feature gated behind `commandPaletteEnabled` in `AppSettingsKeys` (default `false`). When disabled: prefix detection skipped, Settings UI hidden.
- **D-04:** Use `NSExpression` for math evaluation — no third-party dependencies. Pass stripped expression text to `NSExpression(format:)`. Catch exceptions and treat as invalid.
- **D-05:** Support `sqrt()`, `pow()`, `sin()`, `cos()` beyond basic arithmetic.
- **D-06:** Smart number formatting: whole numbers shown as integers (no decimal); others rounded to 6 significant figures. `NumberFormatter` for locale-aware thousands separators.
- **D-07:** Use Foundation `Measurement` API for unit conversions: length, mass, temperature, volume.
- **D-08:** Natural query syntax `{value} {unit} to {unit}` and `{value} {unit} in {unit}`. Case-insensitive, common abbreviations and full names accepted.
- **D-09:** Bundled static exchange rates JSON (USD base, ~50 major currencies) as fallback.
- **D-10:** "Refresh rates" button in Settings fetches from `open.er-api.com`. Saves to `~/Library/Application Support/Clipsmith/exchange-rates.json`. Button shows last-updated timestamp. Network errors show inline error; bundled rates remain active.
- **D-11:** Currency query syntax: `10 USD to EUR`, `100 GBP in JPY`. Parser detects 3-letter ISO codes (case-insensitive).
- **D-12:** In `=` mode, app list replaced by full-width `CommandPaletteView`. Layout: expression text (secondary) at top, large result in center. Invalid/incomplete: dimmed "Invalid expression" placeholder.
- **D-13:** Enter on valid result: copies result string to `NSPasteboard.general`, shows "Copied ✓" toast overlay, then `hide()`. Enter on invalid: no-op.
- **D-14:** `CommandPaletteView` reuses same frosted glass background (`.ultraThinMaterial` + `bezelAlpha` overlay) as `AppLaunchView`.

### Claude's Discretion

None specified — all key decisions are locked.

### Deferred Ideas (OUT OF SCOPE)

- Additional unit categories (area, speed, pressure, data size, time)
- Live streaming exchange rates with auto-refresh
- File search (`=find:term`)
- Web search dispatch (`=web:query`)
- Per-capability feature flags (`mathEvalEnabled`, `currencyEnabled`, `unitEnabled`)
</user_constraints>

---

## Summary

Phase 12 extends the Phase 11 App Launcher bezel into a lightweight command palette triggered by a configurable prefix character (default `=`). When the user types `=`, the bezel replaces the app list with a full-width result card showing math, unit, or currency conversion results in real time.

The technical implementation rests on three zero-dependency foundations: `NSExpression` for arithmetic evaluation (available since macOS 10.6, no new APIs required), `Foundation.Measurement<Unit>` for unit conversions (macOS 10.12+), and `URLSession` + `JSONDecoder` for the free open.er-api.com currency API. No new SPM packages are needed.

The primary complexity is (a) NSExpression's ObjC exception model — it throws uncatchable `NSInvalidArgumentException` for malformed input, requiring mandatory pre-validation before every call; (b) NSExpression's incomplete function support — `sin`/`cos` are NOT supported and must be implemented via pre-processing using Swift's built-in math functions; and (c) `^` in NSExpression means bitwise XOR, not power — user input `2^10` must be preprocessed to `2**10`.

**Primary recommendation:** Implement `ExpressionEvaluator` as a `nonisolated` struct with static methods that pre-validate and preprocess input before calling `NSExpression(format:)`. Keep the copy-to-clipboard path identical to `PasteService`'s `blockedChangeCount` pattern. Add `clipboardMonitor: ClipboardMonitor?` injection to `AppLaunchController` (same as `BezelController`).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Mode detection (prefix char) | AppLaunchViewModel | AppLaunchController | ViewModel owns searchText; controller reads computed property for Enter routing |
| Math evaluation | ExpressionEvaluator (struct) | CommandPaletteService | Pure computation, no state, synchronous — struct is correct |
| Unit conversion | UnitConversionService (struct) | CommandPaletteService | Pure computation, no state, synchronous |
| Currency rates load/refresh | CurrencyService (@MainActor @Observable) | AppDelegate (injection) | Has observable state (isRefreshing, lastError, lastUpdated) |
| Query dispatch (math vs unit vs currency) | CommandPaletteService (@MainActor) | AppLaunchViewModel | Owned by ViewModel, same tier |
| Result display | CommandPaletteView (SwiftUI) | AppLaunchView (branch point) | SwiftUI view branch on `viewModel.isCommandPaletteMode` |
| Copy to clipboard (without recording) | AppLaunchController | clipboardMonitor injection | Mirrors BezelController pattern exactly |
| "Copied ✓" toast | CommandPaletteView (@State) | — | Local view state, Task.sleep auto-dismiss |
| Settings UI | GeneralSettingsTab (Features section) | — | All Phase 8+11 feature flags live there |
| Exchange rates download | CurrencyService async func | URLSession.shared | Network call pattern from GistService |
| Bundled rates JSON | Bundle.main resource | CurrencyService fallback | Mirrors prompts.json pattern |

---

## Standard Stack

No new SPM packages. Everything is Foundation + AppKit + SwiftUI.

### Core (all system frameworks, already imported)

| Component | Source | Purpose | Notes |
|-----------|--------|---------|-------|
| `NSExpression` | Foundation | Math evaluation | No sandbox. Available macOS 10.6+. |
| `Foundation.Measurement<Unit>` | Foundation | Unit conversion | `UnitLength`, `UnitMass`, `UnitTemperature`, `UnitVolume` |
| `URLSession.shared` | Foundation | Currency API download | Async/await, same pattern as `GistService` |
| `JSONDecoder` | Foundation | Decode open.er-api.com response + local JSON | Standard Codable |
| `Bundle.main.url(forResource:withExtension:)` | Foundation | Load bundled exchange-rates JSON | Same as `prompts.json` pattern |
| `NSPasteboard.general` | AppKit | Copy result to clipboard | Same as `PasteService` |
| `NumberFormatter` | Foundation | Locale-aware number display | D-06 formatting |
| `NSRegularExpression` | Foundation | Query parsing, pre-validation | NSExpression safety gate |

### Package Legitimacy Audit

Phase 12 adds **zero new SPM packages**. No audit required.

---

## Architecture Patterns

### System Architecture Diagram

```
User types "=" prefix
        │
        ▼
AppLaunchViewModel.searchText.didSet
        │ hasPrefix(commandPalettePrefix)?
        ├──NO──► recomputeDisplayedApps() ──► AppLaunchView shows app list
        │
        └──YES──► isCommandPaletteMode = true
                  queryText = searchText.dropFirst(1)
                        │
                        ▼
              CommandPaletteService.evaluate(queryText)
                        │
              ┌─────────┼──────────┐
              ▼         ▼          ▼
    UnitConversionSvc  CurrencyService  ExpressionEvaluator
    (regex: "5 km       (regex: "10      (pre-validate →
     to miles")          USD to EUR")    NSExpression(format:))
              │         │          │
              └────────►│◄─────────┘
                        │ CommandResult
                        ▼
              AppLaunchViewModel.commandResult
                        │
                        ▼
              AppLaunchView branches to CommandPaletteView
                        │
              ┌─────────┴──────────┐
              │                    │
           valid result        invalid/empty
           (large text)        ("Invalid expression" dimmed)
                        │
                   User presses Enter
                        │
              AppLaunchController.sendEvent(36/76)
                        │ isCommandPaletteMode?
                        ├──YES──► copyResult() ──► NSPasteboard + blockedChangeCount
                        │                          + "Copied ✓" toast + hide()
                        └──NO──► launchSelected()
```

### Recommended Project Structure

```
Clipsmith/
├── Services/
│   ├── CommandPaletteService.swift      # @MainActor @Observable — query dispatch, owns evaluators
│   ├── ExpressionEvaluator.swift        # nonisolated struct — NSExpression wrapper + safety
│   ├── UnitConversionService.swift      # nonisolated struct — Measurement-based converter + alias table
│   └── CurrencyService.swift            # @MainActor @Observable — load bundled/downloaded rates, refresh
├── Views/
│   ├── AppLaunchView.swift              # ADD: branch on isCommandPaletteMode
│   ├── AppLaunchViewModel.swift         # ADD: isCommandPaletteMode, commandResult, commandPaletteService
│   ├── AppLaunchController.swift        # ADD: clipboardMonitor injection, copyResult(), Enter routing
│   └── CommandPaletteView.swift         # NEW: result card view with toast overlay
├── Settings/
│   └── AppSettingsKeys.swift            # ADD: commandPaletteEnabled, commandPalettePrefix
├── Views/Settings/
│   └── GeneralSettingsTab.swift         # ADD: Features section entries + prefix TextField + Refresh rates
└── Resources/
    └── exchange-rates-bundled.json      # NEW: bundled static rates (USD base, ~50 currencies)
```

### Pattern 1: NSExpression Pre-Validation and Evaluation

**What:** Sanitize user input before `NSExpression(format:)` to prevent `NSInvalidArgumentException` crashes.
**When to use:** Every call to `NSExpression(format:)`. No exceptions.

```swift
// Source: Verified via REPL testing 2026-05-26
nonisolated static func evaluate(_ text: String) -> Double? {
    // Step 1: Preprocess - replace ^ with ** (XOR trap), handle sin/cos
    var expr = text.trimmingCharacters(in: .whitespaces)
    expr = preprocessPowerOperator(expr)         // "2^10" -> "2**10"
    expr = preprocessSinCos(expr)                // "sin(x)" -> evaluated Double literal

    // Step 2: Pre-validate with safe-chars regex
    // Allowed: digits, . + - * / ( ) space e E , (for modulus:by:)
    // Allowed function names are stripped before regex check
    guard isSafeExpression(expr) else { return nil }

    // Step 3: Evaluate (safe because pre-validation passed)
    let nsExpr = NSExpression(format: expr)
    guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
        return nil
    }
    let val = result.doubleValue
    guard !val.isNaN && !val.isInfinite else { return nil }
    return val
}

// Pre-validation regex (after function name stripping):
// ^[\d\s\(\)\.\+\-\*/\,eE\*]+$
// Note: ** uses two * chars, both valid in the character class
```

**Critical finding (VERIFIED):** `^` in NSExpression is bitwise XOR, NOT power. `2^10 = 8` (XOR), `2**10 = 1024` (power). Pre-process `^` → `**` before NSExpression.

### Pattern 2: NSExpression Supported Functions

**What:** Functions that work via the format string (NOT requiring `NSExpression(forFunction:arguments:)` API).
**When to use:** These can be passed directly in the format string.

```swift
// Source: Verified via REPL testing 2026-05-26
// SUPPORTED in format string (safe to pass directly):
"sqrt(16)"        // -> 4.0
"abs(-5)"         // -> 5
"ceiling(3.2)"    // -> 4.0
"floor(3.8)"      // -> 3.0
"ln(2.718...)"    // -> 1.0 (natural log)
"log(100)"        // -> 2.0 (log base 10)
"exp(1)"          // -> 2.718...
"2 ** 10"         // -> 1024 (power)
"modulus:by:(10, 3)"  // -> 1 (requires this exact form; % not supported)

// NOT SUPPORTED (throws NSInvalidArgumentException on format:):
// "sin(x)"        → use Swift.sin() as pre-processor, inject result as literal
// "cos(x)"        → use Swift.cos() as pre-processor
// "10 % 3"        → % operator throws; use modulus:by:() or skip modulo in v1
```

### Pattern 3: NSNumber Result Type Detection for D-06

**What:** Distinguish integer vs float results for display formatting.

```swift
// Source: Verified via REPL 2026-05-26
// NSExpression returns NSNumber. objCType reveals storage type:
// "q" = Int64 (integer expression: "2 + 3", "6 * 7")
// "d" = Double (any floating-point expression: "2.5 + 1.5")

// D-06 formatting algorithm (VERIFIED):
func formatResult(_ value: Double) -> String {
    // Integers (and whole-number doubles below 1e15): show with comma separators
    if value == value.rounded(.toNearestOrEven) && !value.isInfinite && abs(value) < 1e15 {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = Locale(identifier: "en_US")
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: Int64(value))) ?? "\(Int64(value))"
    }
    // Floats and very large numbers: 6 significant figures (handles temperature rounding)
    // "%.6g" auto-rounds 211.999999... -> "212", avoids scientific for normal ranges
    return String(format: "%.6g", value)
}
// Copy to clipboard: plain number WITHOUT grouping separator (paste-safe)
func copyableResult(_ value: Double) -> String {
    String(format: "%.10g", value)   // no grouping, up to 10 sig figs
}
```

**Verified:** `%.6g` correctly rounds `211.9999999999945` (Foundation temperature float error) to `"212"`. [VERIFIED: REPL 2026-05-26]

### Pattern 4: Foundation Measurement Unit Conversion

**What:** Foundation provides NO string→Unit parsing. A manual lookup table is required.

```swift
// Source: Verified via REPL testing 2026-05-26
// Foundation symbols (canonical abbreviations from .symbol property):
// UnitLength: m, km, cm, mm, mi, yd, ft, in, NM, ly, pc
// UnitMass:   kg, g, mg, µg, lb, oz, st, t, ton, ct
// UnitTemperature: °C, °F, K
// UnitVolume: L, mL, m³, gal, qt, pt, cup, fl oz, tbsp, tsp, in³, ft³

// Query parser regex (VERIFIED working):
// ^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°³/²\s]+?)\s+(?:to|in)\s+([\w°³/²\s]+?)\s*$

// Currency vs unit disambiguation: 
// If BOTH from AND to match /^[A-Z]{3}$/ -> currency
// Otherwise -> unit

// Temperature conversion accuracy:
// Foundation Measurement handles offset units (°F/°C) correctly.
// Minor float drift: "100°C -> °F" returns 211.9999..., format with %.6g for display.
```

**Full alias table (required — Foundation provides NONE):**

| User input (case-insensitive) | Maps to |
|-------------------------------|---------|
| m, meter, meters | `UnitLength.meters` |
| km, kilometer, kilometers | `UnitLength.kilometers` |
| cm, centimeter, centimeters | `UnitLength.centimeters` |
| mm, millimeter, millimeters | `UnitLength.millimeters` |
| mi, mile, miles | `UnitLength.miles` |
| yd, yard, yards | `UnitLength.yards` |
| ft, foot, feet | `UnitLength.feet` |
| in, inch, inches | `UnitLength.inches` |
| nm, nmi | `UnitLength.nauticalMiles` |
| ly, lightyear, lightyears | `UnitLength.lightyears` |
| kg, kilogram, kilograms | `UnitMass.kilograms` |
| g, gram, grams | `UnitMass.grams` |
| mg, milligram, milligrams | `UnitMass.milligrams` |
| lb, lbs, pound, pounds | `UnitMass.pounds` |
| oz, ounce, ounces | `UnitMass.ounces` |
| st, stone, stones | `UnitMass.stones` |
| t, tonne, tonnes, mt | `UnitMass.metricTons` |
| ton, tons | `UnitMass.shortTons` |
| c, celsius, degc | `UnitTemperature.celsius` |
| f, fahrenheit, degf | `UnitTemperature.fahrenheit` |
| k, kelvin | `UnitTemperature.kelvin` |
| l, liter, liters, litre, litres | `UnitVolume.liters` |
| ml, milliliter, milliliters | `UnitVolume.milliliters` |
| gal, gallon, gallons | `UnitVolume.gallons` |
| qt, quart, quarts | `UnitVolume.quarts` |
| pt, pint, pints | `UnitVolume.pints` |
| cup, cups | `UnitVolume.cups` |
| floz, tbsp, tablespoon, tablespoons | `UnitVolume.tablespoons` |
| tsp, teaspoon, teaspoons | `UnitVolume.teaspoons` |
| igal | `UnitVolume.imperialGallons` |

**Conflict:** `"t"` is both metric tons (mass) and could be confused with time. Since time units are out of scope for Phase 12, `"t"` → `UnitMass.metricTons` safely.

**Conflict:** `"in"` matches inches, but Swift's regex group `\w` will capture it; parser should prefer unit match over treating it as the preposition "in" (disambiguation: preposition appears between two quantity groups).

### Pattern 5: CurrencyService — open.er-api.com API

**What:** Free tier, no API key required, USD-base rates endpoint.
**When to use:** "Refresh rates" button press in Settings.

```swift
// Source: Verified via WebFetch of open.er-api.com 2026-05-26

// Endpoint: GET https://open.er-api.com/v6/latest/USD
// Returns:
// {
//   "result": "success",
//   "base_code": "USD",
//   "time_last_update_unix": 1234567890,
//   "time_next_update_unix": 1234654290,
//   "rates": { "EUR": 0.859106, "GBP": 0.734..., ... }
// }

struct ExchangeRateResponse: Codable {
    let result: String
    let baseCode: String
    let timeLast UpdateUnix: TimeInterval      // use for lastUpdated display
    let rates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case timeLastUpdateUnix = "time_last_update_unix"
        case rates
    }
}

// Free tier limits: 
// - No API key required
// - No documented monthly cap; update frequency is daily
// - HTTP 429 returned if rate-limited (lifts after ~20 minutes)
// - Attribution required: "Rates By Exchange Rate API" with link
// [VERIFIED: official docs + live API response 2026-05-26]

// Save path mirrors DocsetManagerService pattern:
// FileManager.default.urls(for: .applicationSupportDirectory, ...)[0]
//     .appendingPathComponent("Clipsmith/exchange-rates.json")

// Load priority: downloaded file FIRST, Bundle.main fallback
// Bundled file: Bundle.main.url(forResource: "exchange-rates-bundled", withExtension: "json")
// [VERIFIED: Bundle.main pattern matches prompts.json in PromptSyncService]
```

**Rate limits (VERIFIED):** Daily update cycle. Requesting once per "Refresh" button press (user-initiated) is well within limits. [CITED: exchangerate-api.com/docs/free]

### Pattern 6: Copy-to-Clipboard Without ClipboardMonitor Recording

**What:** Copying the command palette result must not create a new clipping in clipboard history.

```swift
// Source: BezelController.swift lines 434-447 (existing verified pattern)
// AppLaunchController needs clipboardMonitor injected (var, not in current Phase 11 code)

// In AppDelegate.applicationDidFinishLaunching (after Phase 11 setup):
// appLaunchController.clipboardMonitor = clipboardMonitor

// In AppLaunchController.copyResult():
func copyResult(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    // Block self-capture: ClipboardMonitor skips writes with known changeCount
    clipboardMonitor?.blockedChangeCount = pasteboard.changeCount
    // Show toast + dismiss
    viewModel.showCopiedToast()   // sets @State flag in CommandPaletteView
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.2))
        hide()
    }
}
```

### Pattern 7: "Copied ✓" Toast in Non-Activating Panel

**What:** Auto-dismissing overlay inside `CommandPaletteView`. Panel does not need to activate.

```swift
// Source: Standard SwiftUI pattern; verified compatible with .nonactivatingPanel
// @State works in NSHostingView inside non-activating panels — no focus steal occurs

// In CommandPaletteView:
@State private var showCopied = false

// In body (overlay on ZStack):
.overlay(alignment: .bottom) {
    if showCopied {
        Text("Copied ✓")
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
.animation(.easeInOut(duration: 0.2), value: showCopied)

// Trigger from ViewModel (called by Controller after copy):
func showCopiedToast() {
    showCopied = true
    // Auto-hide after 1.2s — controller then calls hide() at ~1.2s
}
// OR: keep toast state in ViewModel as @Observable property
```

**Note:** Toast auto-hide and `hide()` should be coordinated. The controller calls `hide()` AFTER the toast shows briefly, so the user sees "Copied ✓" before the panel disappears.

### Pattern 8: Settings — 1-Character Prefix TextField with Alphanumeric Rejection

```swift
// Source: Standard SwiftUI @AppStorage + onChange pattern used throughout Clipsmith
@AppStorage(AppSettingsKeys.commandPalettePrefix) private var prefix: String = "="

TextField("", text: $prefix)
    .frame(width: 36)
    .multilineTextAlignment(.center)
    .onChange(of: prefix) { _, newValue in
        guard !newValue.isEmpty else { prefix = "="; return }
        let trimmed = String(newValue.prefix(1))
        if let c = trimmed.first, c.isLetter || c.isNumber {
            prefix = "="   // reject alphanumeric, reset to default
        } else {
            prefix = trimmed
        }
    }
```

### Pattern 9: CommandPaletteView Integration in AppLaunchView

```swift
// In AppLaunchView body, replace the app list Group:
Group {
    if viewModel.isCommandPaletteMode {
        CommandPaletteView(viewModel: viewModel)
    } else if viewModel.isLoading && viewModel.apps.isEmpty {
        ProgressView("Scanning apps...")
            .foregroundStyle(.secondary)
    } else if viewModel.displayedApps.isEmpty {
        Text("No matches")
            .foregroundStyle(.secondary)
    } else {
        appListView
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

### Anti-Patterns to Avoid

- **Passing raw user input to `NSExpression(format:)` without pre-validation:** Throws `NSInvalidArgumentException` (ObjC exception), NOT catchable with Swift `do/catch`. App crashes immediately.
- **Using `^` for power in NSExpression:** `^` is bitwise XOR. `2^10 = 8`, not 1024. Always preprocess `^` → `**`.
- **Calling `sin(x)` in NSExpression format string:** Throws `NSInvalidArgumentException`. Only `sqrt`, `abs`, `ceiling`, `floor`, `ln`, `log`, `exp` work in format strings.
- **Calling `NSExpression(format:)` off `@MainActor`:** NSExpression is an ObjC class, not `Sendable`. Keep evaluation on `@MainActor`.
- **Assuming Foundation Unit has symbol parsing:** `UnitLength` provides NO `init(symbol:)` or lookup by abbreviation. A manual `[String: Dimension]` dictionary is mandatory.
- **Reusing PasteService for command palette copy:** PasteService does `clearContents()` + `setString()` + schedules `Cmd-V`. Command palette only needs clipboard write + `blockedChangeCount`; do NOT fire `Cmd-V` (no paste injection wanted).
- **Missing `clipboardMonitor` injection in `AppLaunchController`:** Without it, the result copy triggers ClipboardMonitor and creates a history entry for every calculator result. Add `var clipboardMonitor: ClipboardMonitor?` to `AppLaunchController` and wire in `AppDelegate`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Math expression parsing | Custom tokenizer/parser | `NSExpression(format:)` | Handles operator precedence, parentheses, unary minus, scientific notation |
| Temperature conversion | Custom °C↔°F formula | `Foundation.Measurement` / `UnitTemperature` | Handles all three units (K/°C/°F) with offset-based conversion |
| Number formatting | Custom decimal/comma logic | `NumberFormatter` + `String(format: "%.6g", ...)` | Locale awareness, grouping separators, rounding |
| HTTP download boilerplate | Custom URLSession wrapper | `URLSession.shared.data(from:)` async — same as GistService | Already established pattern |
| JSON parsing | Manual string extraction | `JSONDecoder` + `Codable` structs | Proven pattern throughout codebase |
| Regex-based unit parser | State machine | `NSRegularExpression` with capture groups | Pre-tested; handles the full `{val} {unit} to {unit}` grammar |

**Key insight:** NSExpression, Foundation.Measurement, and NumberFormatter together cover every Phase 12 computation need with zero new dependencies. Custom implementations would reintroduce known edge cases (operator precedence, temperature offsets, locale decimal separators) that these frameworks already handle.

---

## Common Pitfalls

### Pitfall 1: NSExpression `^` is XOR, Not Power

**What goes wrong:** User types `2^10`, expects 1024, gets 8 (XOR result silently returned).
**Why it happens:** NSExpression uses `^` for bitwise XOR (C semantics). The expression is valid, so no error is raised.
**How to avoid:** Pre-process the raw expression string and replace standalone `^` with `**` before passing to `NSExpression(format:)`. Use a regex like `(?<![*])(\^)(?![*])` to avoid double-replacing.
**Warning signs:** User-reported "wrong answers" for expressions with `^`.

### Pitfall 2: NSExpression Crashes on Invalid Input (No Swift Exception Handling)

**What goes wrong:** Calling `NSExpression(format: userInput)` with invalid text (e.g., `"hello world"`, `"SELECT"`, `"sin(x)"`) throws `NSInvalidArgumentException` — an ObjC exception that Swift's `do/catch` CANNOT catch. App crashes.
**Why it happens:** NSExpression uses ObjC `@throw`, not Swift `throw`. These exceptions bypass Swift's error handling entirely.
**How to avoid:** ALWAYS run a safe-chars pre-validation regex before calling `NSExpression(format:)`. Gate the call: if the expression contains anything outside `[0-9 ().+\-*/eE,]` (after stripping recognized function names), return `nil` without calling NSExpression.
**Warning signs:** Crash in `NSExpression expressionWithFormat:` during testing with free-form input.

### Pitfall 3: `sin()`/`cos()` Not Supported in NSExpression Format Strings

**What goes wrong:** `NSExpression(format: "sin(0)")` crashes with "Unable to parse function name 'sin:' into supported selector".
**Why it happens:** NSExpression's `sin:` selector is not in the allowed list for `expressionWithFormat:`.
**How to avoid:** Pre-process expression string: scan for `sin(expr)` and `cos(expr)` patterns, evaluate the inner expression, substitute with the literal numeric result, then pass to NSExpression. Alternatively, skip sin/cos in Phase 12 (they are listed in D-05 but implementation complexity is high; consider documenting as deferred in plan).
**Warning signs:** Sin/cos mentioned in D-05 but verified to NOT work in NSExpression format strings.

### Pitfall 4: Temperature Conversion Float Imprecision

**What goes wrong:** `100°C → °F` returns `211.9999999999945` instead of `212`. Displayed as "211.9999..." without special handling.
**Why it happens:** `UnitTemperature` uses floating-point offset arithmetic (adds 273.15 to convert to Kelvin as intermediate).
**How to avoid:** Always format temperature (and all) results with `String(format: "%.6g", value)` which rounds at 6 significant figures — `211.9999...` rounds to `"212"`. [VERIFIED: REPL 2026-05-26]
**Warning signs:** Test `100 C to F` and `32 F to C` explicitly.

### Pitfall 5: Currency `"t"` / `"pt"` / `"in"` Alias Collisions

**What goes wrong:** `"t"` could be metric tons (mass) or the Turkish lira ticker (TRY). `"pt"` is pints AND Portuguese escudo (PTE). `"in"` is inches AND Indian rupee (INR).
**Why it happens:** Short abbreviations overlap between unit symbols and ISO currency codes.
**How to avoid:** Apply currency detection FIRST (both from/to match `/^[A-Z]{3}$/` — exactly 3 uppercase letters). Unit detection runs second. Single-letter or two-letter abbreviations that match units are never valid ISO codes (ISO requires exactly 3 letters). The only potential overlap is `"in"` (inches) vs `"INR"` (Indian Rupee) — but INR is 3 chars and inches is 2, so no actual collision with the 3-letter ISO check.
**Warning signs:** `"5 in to cm"` interpreted as currency instead of inches.

### Pitfall 6: NSPasteboard Copy Triggers ClipboardMonitor Self-Capture

**What goes wrong:** Command palette result copy creates a spurious clipping in clipboard history.
**Why it happens:** `ClipboardMonitor` polls `NSPasteboard` every 0.5-1s. If `changeCount` changes without `blockedChangeCount` being set, the content is recorded as a new clipping.
**How to avoid:** After `pasteboard.setString(...)`, immediately set `clipboardMonitor?.blockedChangeCount = pasteboard.changeCount`. Requires `clipboardMonitor: ClipboardMonitor?` to be injected into `AppLaunchController` (currently absent — see AppDelegate wiring). [VERIFIED: PasteService.swift + BezelController.swift patterns]
**Warning signs:** Every calculator result appears in clipboard history.

### Pitfall 7: `"in"` Regex Preposition vs Unit

**What goes wrong:** Parser regex `(?:to|in)` for the preposition separator matches unit symbols like `in` (inches) in the from/to groups.
**Why it happens:** The parser uses `"in"` as the preposition keyword AND as the inches abbreviation.
**How to avoid:** The query grammar `{value} {unit} to|in {unit}` has exactly one preposition between two quantity groups. The `{unit}` capture group should be `\S+` (no spaces allowed in unit name) or `[\w°]+` to avoid greedily matching the preposition. Test edge case: `"5 in to cm"` → value=5, from=`"in"`, to=`"cm"` ✓.

### Pitfall 8: Division by Zero Returns `0` or `Inf` Silently

**What goes wrong:** `NSExpression(format: "10 / 0")` returns `Optional(0)` (integer division). `NSExpression(format: "10.0 / 0.0")` returns `Optional(inf)`. Neither crashes, but the results are wrong.
**How to avoid:** After evaluation, check `val.isInfinite && !val.isNaN` → display "Division by zero" error instead of showing `0` or `inf`.
**Warning signs:** `10 / 0` shows `"0"` in the result card.

---

## Code Examples

### ExpressionEvaluator — Complete Skeleton

```swift
// Source: Verified against REPL behavior 2026-05-26
nonisolated struct ExpressionEvaluator {

    // Safe character set after function names are stripped
    private static let safeMathRegex = try! NSRegularExpression(
        pattern: #"^[\d\s()\.\+\-\*/,eE\*]+$"#
    )
    private static let funcNames = ["sqrt", "abs", "ceiling", "floor", "ln", "log", "exp"]

    static func evaluate(_ rawText: String) -> Double? {
        var expr = rawText.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else { return nil }

        // 1. Replace ^ with ** (XOR trap)
        expr = expr.replacingOccurrences(
            of: #"(?<![*])\^(?![*])"#,
            with: "**",
            options: .regularExpression
        )

        // 2. Pre-validate: strip function names, check remaining chars are safe
        var stripped = expr.lowercased()
        for fn in funcNames { stripped = stripped.replacingOccurrences(of: fn, with: "") }
        let range = NSRange(stripped.startIndex..., in: stripped)
        guard safeMathRegex.firstMatch(in: stripped, range: range) != nil else { return nil }

        // 3. Evaluate (safe — pre-validation passed)
        let nsExpr = NSExpression(format: expr)
        guard let number = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }
        let val = number.doubleValue
        guard !val.isNaN, !val.isInfinite else { return nil }
        return val
    }
}
```

### UnitConversionService — Conversion Core

```swift
// Source: Verified Foundation Measurement behavior 2026-05-26
nonisolated struct UnitConversionService {

    // Full alias table (sample — implement all entries from Architecture Patterns table)
    private static let unitMap: [String: Dimension] = [
        "m": UnitLength.meters, "meter": UnitLength.meters, "meters": UnitLength.meters,
        "km": UnitLength.kilometers, "kilometer": UnitLength.kilometers,
        "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "ft": UnitLength.feet, "foot": UnitLength.feet, "feet": UnitLength.feet,
        "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches,
        // ... all entries from the table above ...
        "c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        // mass, volume ...
    ]

    // Regex: ^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°³/²\s]+?)\s+(?:to|in)\s+([\w°³/²\s]+?)\s*$
    private static let queryRegex = try! NSRegularExpression(
        pattern: #"^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°]+)\s+(?:to|in)\s+([\w°]+)\s*$"#,
        options: [.caseInsensitive]
    )

    static func convert(_ query: String) -> (value: Double, unit: String)? {
        let ns = query as NSString
        let range = NSRange(query.startIndex..., in: query)
        guard let match = queryRegex.firstMatch(in: query, range: range),
              match.numberOfRanges == 4 else { return nil }

        func cap(_ i: Int) -> String {
            let r = match.range(at: i)
            guard r.location != NSNotFound else { return "" }
            return ns.substring(with: r)
        }

        guard let value = Double(cap(1).replacingOccurrences(of: ",", with: "")),
              let fromUnit = unitMap[cap(2).lowercased()],
              let toUnit = unitMap[cap(3).lowercased()] else { return nil }

        let measurement = Measurement(value: value, unit: fromUnit)
        // Units must be compatible (same Dimension subtype)
        guard type(of: fromUnit) == type(of: toUnit) else { return nil }
        let converted = measurement.converted(to: toUnit)
        return (converted.value, cap(3))
    }
}
```

### CurrencyService — Load and Refresh Pattern

```swift
// Source: GistService.swift async/await pattern + PromptSyncService Bundle.main pattern
@MainActor @Observable
final class CurrencyService {
    var isRefreshing = false
    var lastError: String? = nil
    var lastUpdated: Date? = nil   // read from file modification date

    private var rates: [String: Double] = [:]

    private var downloadedRatesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Clipsmith/exchange-rates.json")
    }

    func loadRates() {
        // Try downloaded file first, then bundled fallback
        let data: Data?
        if let d = try? Data(contentsOf: downloadedRatesURL) {
            data = d
            lastUpdated = (try? FileManager.default.attributesOfItem(
                atPath: downloadedRatesURL.path))?[.modificationDate] as? Date
        } else if let url = Bundle.main.url(forResource: "exchange-rates-bundled",
                                             withExtension: "json") {
            data = try? Data(contentsOf: url)
        } else {
            data = nil
        }
        if let d = data, let response = try? JSONDecoder().decode(ExchangeRateResponse.self, from: d) {
            rates = response.rates
        }
    }

    func refreshRates() async {
        isRefreshing = true; lastError = nil
        defer { isRefreshing = false }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Validate decode before writing
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            try FileManager.default.createDirectory(at: downloadedRatesURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: downloadedRatesURL, options: .atomic)
            rates = response.rates
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func convert(amount: Double, from: String, to: String) -> Double? {
        guard !rates.isEmpty else { return nil }
        let fromUpper = from.uppercased(), toUpper = to.uppercased()
        guard let fromRate = rates[fromUpper], let toRate = rates[toUpper],
              fromRate != 0 else { return nil }
        return amount / fromRate * toRate
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| `NSExpression` for math | Still current (macOS 10.6+) | No deprecation; Apple uses it in Spotlight |
| Manual unit conversion formulas | `Foundation.Measurement` (macOS 10.12+) | Full offset support for temperature |
| Live streaming FX rates | Daily cached rates + manual refresh | Free tier; D-10 locks this approach |

**Nothing deprecated in this phase's stack.** All APIs are available on macOS 15+ (the project target).

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 12 |
|-----------|-------------------|
| Swift 6 with `SWIFT_STRICT_CONCURRENCY = complete` | `ExpressionEvaluator` and `UnitConversionService` must be `nonisolated` structs OR @MainActor. NSExpression (ObjC) is not Sendable — keep evaluation on @MainActor. |
| `@MainActor` on all UI-facing classes | `CommandPaletteService` and `CurrencyService` must be `@MainActor @Observable`. |
| `Sendable` on all model/data types | `CommandResult` struct must be `Sendable`. All fields must be value types (String, Double, enum). |
| No app sandbox | URLSession network calls to open.er-api.com are fine (no ATS restrictions). |
| No new SPM dependencies | Phase 12 adds zero new packages. All functionality via Foundation/AppKit. |
| Bundle ID: `com.github.haad.clipsmith` | No change. |
| `AppSettingsKeys` namespace for all UserDefaults keys | Add `commandPaletteEnabled` and `commandPalettePrefix` to `AppSettingsKeys.swift`. Register defaults in `AppDelegate.applicationDidFinishLaunching`. |
| Feature flag pattern | `commandPaletteEnabled` default `false`. Check flag inside handler, not at registration. |
| Bezel pattern: `.nonactivatingPanel` MUST be in `init` styleMask | `AppLaunchController` already correct. No new panels in Phase 12. |
| `@Observable @MainActor` for ViewModels | `AppLaunchViewModel` already conforms. Add `CommandPaletteService` injection to it. |
| PBX prefix scheme: AA/AF/BB/GG/SP | New files get new IDs with these prefixes in `project.pbxproj`. |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `sin(x)` throws `NSInvalidArgumentException` on macOS 15 (macOS 26.5 SDK) as it does on current Xcode | NSExpression Pitfall 3 | If sin/cos work on newer SDK, the pre-processing step is unnecessary but harmless |
| A2 | open.er-api.com free tier has no hard monthly cap (only daily rate limit) | CurrencyService pattern | If monthly limit exists, bundled fallback protects users |
| A3 | `ExchangeRateResponse.rates` contains ~150+ currencies including all major ones for bundled JSON | CurrencyService | Bundled JSON can be crafted to include any needed currencies regardless |

**If this table were empty:** All other claims in this research were verified via REPL execution or live API fetch.

---

## Open Questions (RESOLVED)

1. **Sin/cos implementation scope (D-05)**
   - What we know: D-05 explicitly names `sin()`, `cos()` as required. NSExpression does NOT support them in format strings (VERIFIED crash). Pre-processing with Swift's `sin()`/`cos()` is possible but adds complexity (nested expression evaluation for the argument).
   - What's unclear: Is a pre-processor for `sin(expr)` / `cos(expr)` in scope, or should the plan document these as deferred due to the complexity of nested evaluation?
   - Recommendation: Plan Phase 12 with a sin/cos pre-processor for simple `sin(value)` calls (constant argument), document `sin(2+3)` nested case as deferred. Most user expressions are `sin(0.5)`, not `sin(2+3)`.
   - **RESOLVED:** Constant-argument sin/cos pre-processor implemented in Plan 12-01 Task 2 via `sinCosRegex` matching `\b(sin|cos)\(\s*(-?[0-9]+(?:\.[0-9]+)?)\s*\)`. Evaluated via `Foundation.sin()`/`Foundation.cos()` and substituted as a literal before the safe-chars gate. Nested-expression forms (e.g., `sin(2+3)`) are explicitly rejected and tested via `testSinOfNestedExpressionReturnsNil`.

2. **"Copied ✓" toast ownership**
   - What we know: D-13 says "shows a brief toast overlay, then calls `hide()`". Toast state could live in CommandPaletteView (@State) or AppLaunchViewModel (@Observable).
   - Recommendation: Put `showCopiedToast: Bool` on `AppLaunchViewModel` as an `@Observable` property. Controller calls `viewModel.showCopiedToast = true`, then `Task.sleep(1.2s)`, then `hide()`. Keeps controller in control of timing.
   - **RESOLVED:** `showCopiedToast: Bool` added to `AppLaunchViewModel` in Plan 12-03 Task 2. Controller sets it on copy, CommandPaletteView reads it for the overlay. Auto-dismissed via `Task.sleep(1.2s)` in `AppLaunchController.copyResult()`.

3. **Bundled exchange rates JSON initial content**
   - What we know: Must include ~50 major currencies with USD as base.
   - Recommendation: Generate from open.er-api.com response at build time and commit as `exchange-rates-bundled.json`. Include: USD, EUR, GBP, JPY, CAD, AUD, CHF, CNY, HKD, SEK, NOK, DKK, NZD, SGD, INR, MXN, BRL, ZAR, KRW, TRY, AED, SAR, THB, MYR, IDR, PHP, CZK, HUF, PLN, RUB, ILS, EGP, NGN, PKR, BDT, VND, COP, ARS, CLP, PEN, RON, BGN, HRK, UAH, TWD.
   - **RESOLVED:** Plan 12-02 Task 2 Step A specifies committing `exchange-rates-bundled.json` with ~45 ISO currencies generated from the live API response at research time (2026-05-26). File placed in `Clipsmith/Resources/` and loaded via `Bundle.main.url(forResource:withExtension:)`.

---

## Environment Availability

All required capabilities are built into macOS (Foundation/AppKit). No external tools needed.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `NSExpression` | Math evaluation | ✓ | macOS 10.6+ / macOS 15 target | — |
| `Foundation.Measurement` | Unit conversion | ✓ | macOS 10.12+ | — |
| `URLSession` async/await | Currency refresh | ✓ | macOS 12+ (Swift concurrency) | — |
| `open.er-api.com` | Refresh rates | ✓ (live, verified) | v6 API | Bundled JSON fallback |
| Network access (no sandbox) | Currency download | ✓ (ENABLE_APP_SANDBOX=NO) | — | — |

**No missing dependencies.** All features are implementable with the current project configuration.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (native Xcode, existing) |
| Config file | `ClipsmithTests/` directory in Xcode project |
| Quick run command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/ExpressionEvaluatorTests` |
| Full suite command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| D-04 | `ExpressionEvaluator` evaluates `2+2`, `sqrt(16)`, `2**10` | unit | `xcodebuild test ... -only-testing:ClipsmithTests/ExpressionEvaluatorTests` | ❌ Wave 0 |
| D-04 | `ExpressionEvaluator` returns `nil` for invalid input `"hello"` | unit | same | ❌ Wave 0 |
| D-04/Pitfall 1 | `ExpressionEvaluator` replaces `^` → `**` (`2^10` → 1024) | unit | same | ❌ Wave 0 |
| D-04/Pitfall 8 | Division by zero returns `nil` (not 0 or inf) | unit | same | ❌ Wave 0 |
| D-06 | `formatResult(42.0)` → `"42"`, `formatResult(3.14)` → `"3.14159"` (6 sig figs) | unit | `xcodebuild test ... -only-testing:ClipsmithTests/CommandPaletteServiceTests` | ❌ Wave 0 |
| D-07/D-08 | `UnitConversionService.convert("5 km to miles")` → (3.10686, "miles") | unit | `xcodebuild test ... -only-testing:ClipsmithTests/UnitConversionServiceTests` | ❌ Wave 0 |
| D-07/Pitfall 4 | `UnitConversionService.convert("100 C to F")` → (212.0, "F") (rounded) | unit | same | ❌ Wave 0 |
| D-09/D-10 | `CurrencyService.convert(10, from: "USD", to: "EUR")` → non-nil Double | unit | `xcodebuild test ... -only-testing:ClipsmithTests/CurrencyServiceTests` | ❌ Wave 0 |
| D-11 | Parser correctly identifies `"10 USD to EUR"` as currency query | unit | same | ❌ Wave 0 |
| D-01/D-03 | `AppLaunchViewModel.isCommandPaletteMode` true when `searchText = "=2+2"` | unit | `xcodebuild test ... -only-testing:ClipsmithTests/AppLaunchViewModelTests` | ✅ (extend existing) |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/<ServiceName>Tests`
- **Per wave merge:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `ClipsmithTests/ExpressionEvaluatorTests.swift` — covers D-04, Pitfall 1, Pitfall 8
- [ ] `ClipsmithTests/UnitConversionServiceTests.swift` — covers D-07, D-08, Pitfall 4, Pitfall 5
- [ ] `ClipsmithTests/CurrencyServiceTests.swift` — covers D-09, D-11 (use bundled JSON fixture; mock URLSession for D-10)
- [ ] `ClipsmithTests/CommandPaletteServiceTests.swift` — covers D-06 formatting, query dispatch

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | **yes** | Pre-validation regex before `NSExpression(format:)` |
| V6 Cryptography | no | — |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| ObjC exception injection via `NSExpression(format:)` | Tampering / DoS | Safe-chars regex pre-validation (Pitfall 2) |
| Currency API response with malformed/malicious JSON | Tampering | `JSONDecoder` with typed `Codable` struct; rate field is `[String: Double]` — no arbitrary code |
| Prefix char `";"` or other shell-special characters stored in UserDefaults | Tampering | Prefix is only used as `String.hasPrefix()` comparison, never interpolated into shell/eval |
| Self-capture (calculator results in clipboard history) | Info Disclosure | `clipboardMonitor?.blockedChangeCount` pattern (Pitfall 6) |

---

## Sources

### Primary (HIGH confidence)

- REPL verification: `swift -e '...'` on macOS Darwin 25.5.0 / Swift 6.3.2 — NSExpression behavior, Foundation.Measurement units, NumberFormatter, regex parsing (2026-05-26)
- `Clipsmith/Services/PasteService.swift` — `blockedChangeCount` pattern for clipboard self-capture prevention
- `Clipsmith/Services/GistService.swift` — URLSession async/await, error handling, network pattern
- `Clipsmith/Services/PromptSyncService.swift` — `Bundle.main.url(forResource:withExtension:)` pattern for bundled JSON
- `Clipsmith/Views/AppLaunchController.swift`, `AppLaunchView.swift`, `AppLaunchViewModel.swift` — Phase 11 bezel implementation to extend
- `Clipsmith/Views/BezelController.swift` — `clipboardMonitor` injection pattern + `blockedChangeCount` usage
- `Clipsmith/Views/Settings/GeneralSettingsTab.swift` — Features section pattern for new settings

### Secondary (MEDIUM confidence)

- Live API response: `open.er-api.com/v6/latest/USD` — response structure confirmed via WebFetch
- [exchangerate-api.com/docs/free](https://www.exchangerate-api.com/docs/free) — free tier rate limits: no API key, daily updates, HTTP 429 on abuse

### Tertiary (LOW confidence)

- None — all claims have been REPL-verified or doc-cited.

---

## Metadata

**Confidence breakdown:**
- NSExpression behavior: HIGH — REPL-verified on Swift 6.3.2 / macOS Darwin 25.5.0
- Foundation Measurement: HIGH — REPL-verified all unit symbols and temperature offsets
- open.er-api.com API: HIGH — live response verified, free tier docs cited
- SwiftUI toast pattern: HIGH — standard pattern, non-activating panel compatibility well-established
- Clipboard monitor injection: HIGH — mirrors verified BezelController pattern in codebase

**Research date:** 2026-05-26
**Valid until:** 2026-08-26 (stable system APIs; currency API endpoint may change but fallback exists)
