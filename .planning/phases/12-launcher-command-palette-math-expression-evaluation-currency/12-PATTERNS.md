# Phase 12: Launcher Command Palette — Pattern Map

**Mapped:** 2026-05-26
**Files analyzed:** 12 (6 new, 6 modified)
**Analogs found:** 12 / 12

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Clipsmith/Services/ExpressionEvaluator.swift` | service (pure) | transform | `Clipsmith/Services/FuzzyMatcher.swift` | exact — nonisolated enum/struct, pure synchronous transform |
| `Clipsmith/Services/UnitConversionService.swift` | service (pure) | transform | `Clipsmith/Services/FuzzyMatcher.swift` | exact — nonisolated struct, pure synchronous transform |
| `Clipsmith/Services/CommandPaletteService.swift` | service | transform / request-response | `Clipsmith/Services/FuzzyMatcher.swift` | role-match — pure dispatch logic |
| `Clipsmith/Services/CurrencyService.swift` | service | CRUD / request-response | `Clipsmith/Services/PromptSyncService.swift` + `GistService.swift` | exact — @MainActor @Observable, URLSession async/await, Bundle.main fallback |
| `Clipsmith/Views/CommandPaletteView.swift` | component | request-response | `Clipsmith/Views/AppLaunchView.swift` | exact — SwiftUI bezel view, frosted glass background, @Bindable viewModel |
| `Clipsmith/Resources/exchange-rates-bundled.json` | config | — | `prompts.json` (bundle resource) | role-match — bundled JSON resource |
| `Clipsmith/Views/AppLaunchViewModel.swift` (modify) | view-model | request-response | self (existing) | self — add computed properties |
| `Clipsmith/Views/AppLaunchView.swift` (modify) | component | request-response | self (existing) | self — add branch on `isCommandPaletteMode` |
| `Clipsmith/Views/AppLaunchController.swift` (modify) | controller | request-response | `Clipsmith/Views/BezelController.swift` | exact — blockedChangeCount pattern, clipboardMonitor injection |
| `Clipsmith/Settings/AppSettingsKeys.swift` (modify) | config | — | self (existing) | self — add two static string keys |
| `Clipsmith/Views/Settings/GeneralSettingsTab.swift` (modify) | component | request-response | self (existing) | self — add Features section entries |
| `ClipsmithTests/ExpressionEvaluatorTests.swift` | test | — | `ClipsmithTests/FuzzyMatcherTests.swift` | exact — nonisolated struct, XCTest, no @MainActor |
| `ClipsmithTests/UnitConversionServiceTests.swift` | test | — | `ClipsmithTests/FuzzyMatcherTests.swift` | exact |
| `ClipsmithTests/CurrencyServiceTests.swift` | test | — | `ClipsmithTests/GistServiceTests.swift` | exact — MockURLProtocol pattern for async network service |
| `ClipsmithTests/CommandPaletteServiceTests.swift` | test | — | `ClipsmithTests/AppLaunchViewModelTests.swift` | role-match — @MainActor test class |

---

## Pattern Assignments

### `Clipsmith/Services/ExpressionEvaluator.swift` (service, transform)

**Analog:** `Clipsmith/Services/FuzzyMatcher.swift`

**Imports pattern** (FuzzyMatcher.swift lines 1-2):
```swift
import Foundation
```

**Core pattern — nonisolated enum with static methods** (FuzzyMatcher.swift lines 19-65):
```swift
// FuzzyMatcher uses `enum` as a namespace with a single static func.
// ExpressionEvaluator should use `struct` (RESEARCH.md recommendation)
// or `enum` with the same pattern: no stored state, all static methods.
enum FuzzyMatcher {
    static func score(_ candidate: String, query: String) -> Double? {
        guard !query.isEmpty else { return 1.0 }
        // ... pure computation, no side effects, no actor isolation ...
        return score / idealScore
    }
}
```

**ExpressionEvaluator adaptation** (copy this shape from FuzzyMatcher, populate from RESEARCH.md):
```swift
// nonisolated struct — pure computation, no stored state, synchronous
// Keep NSExpression calls on @MainActor (NSExpression is not Sendable)
// Mark struct itself nonisolated; mark evaluate() as @MainActor
nonisolated struct ExpressionEvaluator {
    private static let safeMathRegex = try! NSRegularExpression(
        pattern: #"^[\d\s()\.\+\-\*/,eE\*]+$"#
    )
    private static let funcNames = ["sqrt", "abs", "ceiling", "floor", "ln", "log", "exp"]

    @MainActor
    static func evaluate(_ rawText: String) -> Double? { ... }

    nonisolated static func formatResult(_ value: Double) -> String { ... }
    nonisolated static func copyableResult(_ value: Double) -> String { ... }
}
```

**No error handling pattern needed** — returns `Optional<Double>`, nil = invalid expression. Same pattern as `FuzzyMatcher.score` returning `Optional<Double>`.

---

### `Clipsmith/Services/UnitConversionService.swift` (service, transform)

**Analog:** `Clipsmith/Services/FuzzyMatcher.swift`

**Imports pattern** (FuzzyMatcher.swift lines 1-2):
```swift
import Foundation
```

**Core pattern — nonisolated struct with static NSRegularExpression + lookup table** (shape from FuzzyMatcher.swift lines 19-65, populated from RESEARCH.md Code Examples):
```swift
nonisolated struct UnitConversionService {
    private static let unitMap: [String: Dimension] = [
        "m": UnitLength.meters,
        "km": UnitLength.kilometers,
        // ... full alias table from RESEARCH.md Pattern 4 table ...
    ]
    // Regex: ^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°]+)\s+(?:to|in)\s+([\w°]+)\s*$
    private static let queryRegex = try! NSRegularExpression(
        pattern: #"^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°]+)\s+(?:to|in)\s+([\w°]+)\s*$"#,
        options: [.caseInsensitive]
    )

    static func convert(_ query: String) -> (value: Double, unit: String)? {
        // ... NSRegularExpression capture group extraction (see RESEARCH.md skeleton) ...
    }
}
```

**Disambiguation rule:** Currency detection runs first — if both from and to tokens match `/^[A-Z]{3}$/` (exactly 3 uppercase letters), route to CurrencyService, not UnitConversionService.

---

### `Clipsmith/Services/CommandPaletteService.swift` (service, request-response)

**Analog:** `Clipsmith/Services/FuzzyMatcher.swift` (pure dispatch) + `Clipsmith/Views/AppLaunchViewModel.swift` (actor isolation pattern)

**Imports pattern:**
```swift
import Foundation
import Observation
```

**Actor isolation pattern** (AppLaunchViewModel.swift lines 17-18):
```swift
// CommandPaletteService vends results to AppLaunchViewModel — must be @MainActor
@Observable @MainActor
final class CommandPaletteService {
    // Owns ExpressionEvaluator (static methods) and UnitConversionService (static methods)
    // Holds CurrencyService by reference (injected)
    var currencyService: CurrencyService?

    // CommandResult is a Sendable value type
    func evaluate(_ query: String) -> CommandResult? { ... }
}
```

**CommandResult model (Sendable value type):**
```swift
// All fields must be value types (String, Double, enum) for Sendable conformance
struct CommandResult: Sendable {
    enum Kind { case math, unit, currency }
    let kind: Kind
    let displayValue: String   // formatted for display (grouping separators, %.6g)
    let copyableValue: String  // plain value for clipboard (no grouping)
    let expression: String     // original query text shown above result
    let toUnit: String?        // unit label for unit/currency results
}
```

---

### `Clipsmith/Services/CurrencyService.swift` (service, CRUD / request-response)

**Analog:** `Clipsmith/Services/PromptSyncService.swift` (primary — @MainActor @Observable, Bundle.main fallback, URLSession) + `Clipsmith/Services/GistService.swift` (secondary — URLSession async/await, error handling)

**Imports pattern** (PromptSyncService.swift lines 1-6):
```swift
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "CurrencyService"
)
```

**Observable state pattern** (PromptSyncService.swift lines 45-60):
```swift
@MainActor @Observable
final class CurrencyService {
    var isRefreshing: Bool = false   // mirrors PromptSyncService.isSyncing
    var lastError: String? = nil     // mirrors PromptSyncService.lastError
    var lastUpdated: Date? = nil     // NEW: read from file modification date

    private var rates: [String: Double] = [:]
    // ...
}
```

**Bundle.main fallback pattern** (PromptSyncService.swift lines 74-99):
```swift
// PromptSyncService pattern for reading bundled JSON:
guard let url = Bundle.main.url(forResource: "prompts", withExtension: "json") else {
    throw PromptSyncError.bundleNotFound
}
let data = try Data(contentsOf: url)
let catalog = try JSONDecoder().decode(PromptCatalog.self, from: data)
// CurrencyService adaptation:
// Bundle.main.url(forResource: "exchange-rates-bundled", withExtension: "json")
// JSONDecoder().decode(ExchangeRateResponse.self, from: data)
```

**Network fetch + error pattern** (PromptSyncService.swift lines 119-165):
```swift
func syncFromURL(_ urlString: String, store: ...) async throws {
    isSyncing = true
    lastError = nil
    do {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard http.statusCode == 200 else {
                throw PromptSyncError.httpError(http.statusCode)
            }
        }
        // decode + persist ...
        isSyncing = false
    } catch {
        lastError = error.localizedDescription
        isSyncing = false
        throw error
    }
}
// CurrencyService.refreshRates() async follows this exact shape:
// - isRefreshing = true; defer { isRefreshing = false }
// - URLSession.shared.data(from: URL(string: "https://open.er-api.com/v6/latest/USD")!)
// - JSONDecoder().decode(ExchangeRateResponse.self, from: data)
// - data.write(to: downloadedRatesURL, options: .atomic)
// - lastError = error.localizedDescription on failure
```

**File persistence path** (mirrors DocsetManagerService pattern per RESEARCH.md):
```swift
private var downloadedRatesURL: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Clipsmith/exchange-rates.json")
}
```

**Codable response struct:**
```swift
struct ExchangeRateResponse: Codable {
    let result: String
    let baseCode: String
    let timeLastUpdateUnix: TimeInterval
    let rates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case timeLastUpdateUnix = "time_last_update_unix"
        case rates
    }
}
```

---

### `Clipsmith/Views/CommandPaletteView.swift` (component, request-response)

**Analog:** `Clipsmith/Views/AppLaunchView.swift`

**Imports pattern** (AppLaunchView.swift lines 1-2):
```swift
import SwiftUI
```

**Frosted glass background** (AppLaunchView.swift lines 83-95):
```swift
.background(
    ZStack {
        // Frosted glass blur layer
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
        // Opacity layer — controlled by Transparency slider
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(NSColor.windowBackgroundColor).opacity(1.0 - bezelAlpha))
    }
)
.clipShape(RoundedRectangle(cornerRadius: 16))
```

**@AppStorage + @Bindable pattern** (AppLaunchView.swift lines 21-25):
```swift
@Bindable var viewModel: AppLaunchViewModel
@AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25
```

**"Copied ✓" toast pattern** (RESEARCH.md Pattern 7 — standard SwiftUI, verified compatible with .nonactivatingPanel):
```swift
// In CommandPaletteView body ZStack overlay:
.overlay(alignment: .bottom) {
    if viewModel.showCopiedToast {
        Text("Copied ✓")
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
.animation(.easeInOut(duration: 0.2), value: viewModel.showCopiedToast)
// Toast state owned by AppLaunchViewModel as @Observable property
```

**Empty/invalid state pattern** (AppLaunchView.swift lines 56-67):
```swift
// When in command palette mode, mirror this Group branching pattern:
Group {
    if viewModel.isCommandPaletteMode {
        CommandPaletteView(viewModel: viewModel)
    } else if viewModel.isLoading && viewModel.apps.isEmpty {
        ProgressView("Scanning apps...")
            .foregroundStyle(.secondary)
    } else if viewModel.displayedApps.isEmpty {
        Text("No matches")
            .foregroundStyle(.secondary)
            .font(.body)
    } else {
        appListView
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

---

### `Clipsmith/Views/AppLaunchViewModel.swift` (modify — add command palette state)

**File:** `Clipsmith/Views/AppLaunchViewModel.swift`

**Existing @Observable @MainActor pattern** (lines 17-18):
```swift
@Observable @MainActor
final class AppLaunchViewModel {
```

**Existing searchText didSet pattern** (lines 37-41) — ADD `isCommandPaletteMode` check here:
```swift
var searchText: String = "" {
    didSet {
        selectedIndex = 0
        recomputeDisplayedApps()   // extend to short-circuit when isCommandPaletteMode
    }
}
```

**Properties to ADD** (same declaration style as existing state vars):
```swift
// Phase 12: Command palette state
var commandResult: CommandResult? = nil
var showCopiedToast: Bool = false
var commandPaletteService: CommandPaletteService?

// Computed from searchText + AppSettingsKeys.commandPalettePrefix
var isCommandPaletteMode: Bool {
    guard UserDefaults.standard.bool(forKey: AppSettingsKeys.commandPaletteEnabled) else {
        return false
    }
    let prefix = UserDefaults.standard.string(forKey: AppSettingsKeys.commandPalettePrefix) ?? "="
    return searchText.hasPrefix(prefix)
}
```

**recomputeDisplayedApps() extension** (lines 71-93) — add early return at top:
```swift
func recomputeDisplayedApps() {
    // Phase 12: short-circuit app ranking when in command palette mode
    if isCommandPaletteMode {
        let query = String(searchText.dropFirst(1))
        commandResult = commandPaletteService?.evaluate(query)
        displayedApps = []   // hide app list
        return
    }
    // ... existing ranking logic unchanged ...
}
```

---

### `Clipsmith/Views/AppLaunchController.swift` (modify — add clipboardMonitor + copyResult)

**Analog:** `Clipsmith/Views/BezelController.swift` lines 36-37 and 443-447

**clipboardMonitor injection pattern** (BezelController.swift lines 36-37):
```swift
// In AppLaunchController, add alongside existing appScannerService:
var clipboardMonitor: ClipboardMonitor?
```

**blockedChangeCount pattern** (BezelController.swift lines 442-447):
```swift
// BezelController.applyTransform (lines 442-447) — exact pattern to copy:
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(result, forType: .string)
// Prevent self-capture: set blockedChangeCount so ClipboardMonitor skips this write.
clipboardMonitor?.blockedChangeCount = pasteboard.changeCount
```

**sendEvent extension** (AppLaunchController.swift lines 101-119) — ADD routing in Return/Enter case:
```swift
case 36, 76:   // Return, Enter (numpad)
    if viewModel.isCommandPaletteMode {
        copyResult()
    } else {
        launchSelected()
    }
    return
```

**copyResult() method to ADD** (shape mirrors launchSelected() lines 214-231):
```swift
func copyResult() {
    guard let result = viewModel.commandResult else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(result.copyableValue, forType: .string)
    clipboardMonitor?.blockedChangeCount = pasteboard.changeCount
    viewModel.showCopiedToast = true
    Task { @MainActor [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: .seconds(1.2))
        self.viewModel.showCopiedToast = false
        self.hide()
    }
    logger.info("Command palette result copied to clipboard")
}
```

---

### `Clipsmith/Settings/AppSettingsKeys.swift` (modify — add 2 keys)

**Analog:** Self (existing file lines 51-52 — Phase 11 additions pattern)

**Pattern to follow** (AppSettingsKeys.swift lines 50-52):
```swift
// Phase 11 additions (App Launcher)
static let appLauncherEnabled = "appLauncherEnabled"
static let recentAppBundleIDs = "recentAppBundleIDs"

// Phase 12 additions (Command Palette)
static let commandPaletteEnabled = "commandPaletteEnabled"
static let commandPalettePrefix = "commandPalettePrefix"
```

---

### `Clipsmith/Views/Settings/GeneralSettingsTab.swift` (modify — add Features entries)

**Analog:** Self (existing file lines 43-47 and 159-164)

**@AppStorage declaration pattern** (GeneralSettingsTab.swift lines 43-46):
```swift
// Phase 11 pattern to copy for Phase 12:
// Phase 11: App Launcher feature flag
@AppStorage(AppSettingsKeys.appLauncherEnabled) private var appLauncherEnabled: Bool = false

// Phase 12 additions (add alongside Phase 11):
@AppStorage(AppSettingsKeys.commandPaletteEnabled) private var commandPaletteEnabled: Bool = false
@AppStorage(AppSettingsKeys.commandPalettePrefix) private var commandPalettePrefix: String = "="
```

**Features section pattern** (GeneralSettingsTab.swift lines 159-164):
```swift
Section("Features") {
    Toggle("Documentation Lookup (experimental)", isOn: $docLookupEnabled)
        .help("Enable the documentation browser.")
    Toggle("App Launcher", isOn: $appLauncherEnabled)
        .help("Enable keyboard-driven app launcher.")
    // Phase 12 additions:
    Toggle("Command Palette", isOn: $commandPaletteEnabled)
        .help("Enable math, unit, and currency evaluation in the App Launcher (type = prefix).")
    if commandPaletteEnabled {
        HStack {
            Text("Prefix character")
            TextField("", text: $commandPalettePrefix)
                .frame(width: 36)
                .multilineTextAlignment(.center)
                .onChange(of: commandPalettePrefix) { _, newValue in
                    guard !newValue.isEmpty else { commandPalettePrefix = "="; return }
                    let trimmed = String(newValue.prefix(1))
                    if let c = trimmed.first, c.isLetter || c.isNumber {
                        commandPalettePrefix = "="
                    } else {
                        commandPalettePrefix = trimmed
                    }
                }
        }
        // CurrencyService refresh button — injected via environment or @Environment
        // or passed as a closure; exact injection TBD in planning phase
    }
}
```

---

### Test Files

#### `ClipsmithTests/ExpressionEvaluatorTests.swift`

**Analog:** `ClipsmithTests/FuzzyMatcherTests.swift`

**Test file structure** (FuzzyMatcherTests.swift lines 1-8):
```swift
import XCTest
@testable import Clipsmith

final class ExpressionEvaluatorTests: XCTestCase {
    // No setUp/tearDown needed — ExpressionEvaluator is stateless
    // No @MainActor — evaluate() is @MainActor, call with await in async test
}
```

**Test naming and assertion pattern** (FuzzyMatcherTests.swift lines 12-73):
```swift
func testBasicArithmeticEvaluates() {
    // ... XCTAssertEqual, XCTAssertNil, XCTAssertNotNil pattern
}
func testInvalidInputReturnsNil() {
    XCTAssertNil(ExpressionEvaluator.evaluate("hello world"))
}
func testCaretPreprocessedToPower() {
    // 2^10 must yield 1024, not 8 (XOR)
}
```

#### `ClipsmithTests/CurrencyServiceTests.swift`

**Analog:** `ClipsmithTests/GistServiceTests.swift` (MockURLProtocol pattern)

**MockURLProtocol pattern** (GistServiceTests.swift lines 8-29):
```swift
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
```

**@MainActor test class pattern** (AppLaunchViewModelTests.swift lines 7-19):
```swift
@MainActor
final class CurrencyServiceTests: XCTestCase {
    private var service: CurrencyService!
    override func setUp() { super.setUp(); service = CurrencyService() }
    override func tearDown() { service = nil; super.tearDown() }
}
```

#### `ClipsmithTests/UnitConversionServiceTests.swift` and `ClipsmithTests/CommandPaletteServiceTests.swift`

**Analog:** `ClipsmithTests/FuzzyMatcherTests.swift` (for UnitConversionService — stateless struct) and `ClipsmithTests/AppLaunchViewModelTests.swift` (for CommandPaletteService — @MainActor)

Follow FuzzyMatcherTests structure verbatim for UnitConversionService (no setUp/tearDown, direct static method calls).

Follow AppLaunchViewModelTests structure for CommandPaletteService (@MainActor, setUp/tearDown with service instance).

---

## Shared Patterns

### Feature Flag Guard Pattern
**Source:** `Clipsmith/Views/Settings/GeneralSettingsTab.swift` lines 43-46 and 159-164, `Clipsmith/Settings/AppSettingsKeys.swift` lines 50-52
**Apply to:** `AppSettingsKeys.swift` (declare keys), `GeneralSettingsTab.swift` (UI toggle), `AppLaunchViewModel.isCommandPaletteMode` (runtime check)
```swift
// Pattern: @AppStorage with static key, default false, check inside handler
@AppStorage(AppSettingsKeys.commandPaletteEnabled) private var commandPaletteEnabled: Bool = false
// At evaluation site:
guard UserDefaults.standard.bool(forKey: AppSettingsKeys.commandPaletteEnabled) else { return }
```

### Clipboard Write Without Self-Capture
**Source:** `Clipsmith/Views/BezelController.swift` lines 442-447
**Apply to:** `AppLaunchController.copyResult()`
```swift
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(result, forType: .string)
clipboardMonitor?.blockedChangeCount = pasteboard.changeCount
```

### @Observable @MainActor Service Pattern
**Source:** `Clipsmith/Services/GistService.swift` lines 32-33, `Clipsmith/Services/PromptSyncService.swift` lines 45-46
**Apply to:** `CurrencyService`, `CommandPaletteService`
```swift
@MainActor @Observable
final class CurrencyService { ... }
```

### Logger Declaration Pattern
**Source:** Every service file (`GistService.swift` lines 6-9, `PromptSyncService.swift` lines 4-8)
**Apply to:** All new non-trivial service and controller files
```swift
private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "CurrencyService"  // replace with file's class name
)
```

### Bundle.main Bundled Resource Pattern
**Source:** `Clipsmith/Services/PromptSyncService.swift` lines 75-76
**Apply to:** `CurrencyService.loadRates()` for bundled fallback
```swift
guard let url = Bundle.main.url(forResource: "exchange-rates-bundled", withExtension: "json") else {
    // log and return; bundled rates missing is non-fatal if downloaded rates exist
    return
}
let data = try Data(contentsOf: url)
```

### nonisolated Static Method Pattern
**Source:** `Clipsmith/Services/FuzzyMatcher.swift` lines 19-65
**Apply to:** `ExpressionEvaluator` (static methods), `UnitConversionService` (static methods)
```swift
// Pattern: caseless enum or nonisolated struct, all static methods, return Optional
enum FuzzyMatcher {
    static func score(_ candidate: String, query: String) -> Double? { ... }
}
// ExpressionEvaluator maps to:
nonisolated struct ExpressionEvaluator {
    @MainActor static func evaluate(_ rawText: String) -> Double? { ... }
    nonisolated static func formatResult(_ value: Double) -> String { ... }
}
```

### SwiftUI Bezel Frosted Glass Pattern
**Source:** `Clipsmith/Views/AppLaunchView.swift` lines 83-95
**Apply to:** `CommandPaletteView` — copy the `.background(ZStack { ... })` + `.clipShape(...)` verbatim; read `@AppStorage(AppSettingsKeys.bezelAlpha)` for opacity.

### NSRegularExpression Static Property Pattern
**Source:** RESEARCH.md Code Examples (verified against FuzzyMatcher's use of Swift stdlib); `UnitConversionService` and `ExpressionEvaluator` both need static regex properties
```swift
// Use try! for regex patterns that are compile-time constants (same approach
// as the codebase's other static regex usage):
private static let queryRegex = try! NSRegularExpression(
    pattern: #"^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°]+)\s+(?:to|in)\s+([\w°]+)\s*$"#,
    options: [.caseInsensitive]
)
```

---

## No Analog Found

All files have close analogs in the codebase. No entries.

---

## Metadata

**Analog search scope:** `Clipsmith/Services/`, `Clipsmith/Views/`, `Clipsmith/Views/Settings/`, `Clipsmith/Settings/`, `ClipsmithTests/`
**Files scanned:** 15 source files, 5 test files
**Pattern extraction date:** 2026-05-26
