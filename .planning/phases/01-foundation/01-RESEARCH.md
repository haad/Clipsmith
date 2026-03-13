# Phase 1: Foundation — Research

**Researched:** 2026-03-05
**Domain:** macOS menu bar app shell, SwiftData schema, AppStorage preferences, SMAppService, accessibility permission monitoring
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SHELL-01 | App lives in menu bar with status bar icon (no dock icon) | `LSUIElement = YES` in Info.plist + `NSApp.setActivationPolicy(.accessory)` via `@NSApplicationDelegateAdaptor` — both required together |
| SHELL-03 | User can launch app at login via modern ServiceManagement API | `SMAppService.mainApp.register()` / `unregister()` — replaces FlycutHelper target entirely; no helper app needed |
| SHELL-04 | App requests and monitors Accessibility permission for paste injection | `AXIsProcessTrusted()` polled on a 5s timer; `AXIsProcessTrustedWithOptions(_:prompt:true)` only on explicit user tap, never on paste path |
| SETT-01 | User can configure global hotkeys via keyboard shortcut recorder | KeyboardShortcuts SPM (v2.4.0, Swift 6 confirmed) provides `Recorder` view via `NSViewRepresentable` for SwiftUI — no custom recorder needed |
| SETT-02 | User can set history size, display length, and clipping display count | `@AppStorage` wrapping `UserDefaults` keys — scalar integer/bool values; define defaults in `AppDelegate.applicationDidFinishLaunching` |
| SETT-03 | User can toggle launch at login | `@AppStorage("launchAtLogin") var launchAtLogin: Bool` + `onChange` calling `SMAppService`; reflect current `SMAppService.mainApp.status` for accuracy |
| SETT-04 | User can toggle paste behavior (plain text default, sound, etc.) | `@AppStorage` bool flags — `plainTextPaste`, `pasteSound`; these are trivial scalar preferences |
| SETT-05 | Preferences window uses SwiftUI Settings scene | `Settings { SettingsView() }` in the `App` body — native macOS preferences window with cmd-comma shortcut; tab-based layout via `TabView` |
</phase_requirements>

---

## Summary

Phase 1 builds the invisible skeleton the entire app depends on. No clipboard monitoring, no hotkey handling, no bezel — just a correctly configured macOS app target that appears in the menu bar, stores settings persistently, declares its SwiftData schema with versioning in place from day one, monitors accessibility permission state, and can register for login launch. Every subsequent phase injects `ModelContext`, `AppSettings`, and the accessibility status into its components at init time, making this phase a hard gate.

The good news: every API involved is well-documented Apple territory with no unstable third-party dependencies. `SMAppService` is macOS 13+ and fully covers macOS 15. SwiftData `VersionedSchema` is available from macOS 17 / Xcode 15 forward. `AXIsProcessTrusted()` is stable across all macOS versions. KeyboardShortcuts (Sindre Sorhus) is confirmed Swift 6-compatible as of v2.4.0 (swift-tools-version 6.2, `MainActor` isolation, strict concurrency settings enabled) — the STATE.md blocker for this library is now resolved.

The main technical trap in this phase is the activation policy split-brain: `LSUIElement = YES` in Info.plist suppresses the dock icon at launch, but SwiftUI may still attempt to show a `WindowGroup` window and fight with the policy. The fix is `NSApp.setActivationPolicy(.accessory)` called in `applicationDidFinishLaunching` via `@NSApplicationDelegateAdaptor`. Additionally, the SwiftData schema **must** be wrapped in `VersionedSchema` from the very first commit — adding it later requires a migration plan, and skipping it on the first release leaves no migration path.

**Primary recommendation:** Build in this order — Xcode target config (Info.plist + entitlements + no-sandbox), then `FlycutApp` + `AppDelegate`, then SwiftData models + `VersionedSchema`, then `AppSettings` (`@AppStorage`), then `AccessibilityMonitor`, then `SettingsView` scaffold, then `SMAppService` toggle. Each step compiles independently and provides a verifiable checkpoint.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6 (strict concurrency) | Language | Compiler-enforced actor isolation — catches threading errors the old Obj-C codebase made at runtime |
| SwiftUI | macOS 15 SDK | All UI surfaces in this phase | `MenuBarExtra`, `Settings` scene, `@AppStorage` all require SwiftUI |
| SwiftData | macOS 17 / Xcode 15+ | Schema declaration and persistence | `@Model` macro, `VersionedSchema`, `ModelContainer` — replaces entire FlycutStore plist pattern |
| ServiceManagement | macOS 13+ | Launch at login | `SMAppService.mainApp` — no helper app target required |
| ApplicationServices | System | Accessibility permission check | `AXIsProcessTrusted()`, `AXIsProcessTrustedWithOptions` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| KeyboardShortcuts (sindresorhus) | 2.4.0 | Hotkey recorder UI in Settings | Phase 1 adds the SPM dependency and declares hotkey `Name` identifiers; actual registration happens Phase 2 |
| os.Logger | System | Privacy-safe logging | All diagnostic logging — replaces `NSLog` / `DLog` from existing codebase |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@AppStorage` | `UserDefaults` directly | `@AppStorage` binds directly to SwiftUI views; no reason to use raw UserDefaults in Swift code |
| `SMAppService.mainApp` | LaunchAgent plist | LaunchAgent requires writing to `~/Library/LaunchAgents` — `SMAppService` is the modern approved path |
| `Settings` scene | Custom `NSWindow` | `Settings` scene auto-wires cmd-comma, `NSWindowController` is unnecessary boilerplate |

**Installation (Phase 1 SPM addition):**
```bash
# In Xcode: File > Add Package Dependencies
# URL: https://github.com/sindresorhus/KeyboardShortcuts
# Version: 2.4.0 or newer
```

---

## Architecture Patterns

### Recommended Project Structure

```
FlycutSwift/
├── App/
│   ├── FlycutApp.swift          # @main, MenuBarExtra, Settings scene, modelContainer
│   └── AppDelegate.swift        # applicationDidFinishLaunching, activation policy
├── Models/
│   ├── Schema/
│   │   ├── FlycutSchemaV1.swift  # VersionedSchema V1 — Clipping, Snippet, GistRecord
│   │   └── FlycutMigrationPlan.swift  # SchemaMigrationPlan (empty stages for now)
│   ├── Clipping.swift           # @Model
│   ├── Snippet.swift            # @Model
│   └── GistRecord.swift         # @Model
├── Settings/
│   ├── AppSettings.swift        # @AppStorage keys as computed vars on an @Observable class
│   └── AppSettingsKeys.swift    # String constants for UserDefaults keys
├── Services/
│   └── AccessibilityMonitor.swift  # @Observable, polls AXIsProcessTrusted on 5s timer
└── Views/
    ├── MenuBarView.swift        # Placeholder — "Flycut" text, quit item only in Phase 1
    └── Settings/
        ├── SettingsView.swift   # TabView root
        ├── GeneralSettingsTab.swift
        └── HotkeySettingsTab.swift  # KeyboardShortcuts.Recorder stubs
```

### Pattern 1: SwiftUI App Entry Point with AppDelegate Adaptor

**What:** Combines the SwiftUI `@main` struct with an `NSApplicationDelegate` for AppKit-only setup.
**When to use:** Any time you need `applicationDidFinishLaunching` or activation policy control from a SwiftUI app.

```swift
// Source: Apple Developer Documentation — NSApplicationDelegateAdaptor
@main
struct FlycutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Flycut", image: "MenuBarIcon") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // MUST call this — LSUIElement alone is not sufficient to prevent
        // dock icon appearance when Settings window opens
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### Pattern 2: SwiftData VersionedSchema from Day One

**What:** Wraps all `@Model` types in a `VersionedSchema` enum even before any migrations exist. Required to have a migration path later.
**When to use:** First commit that introduces any `@Model` type.

```swift
// Source: Apple Developer Documentation — VersionedSchema, SchemaMigrationPlan
enum FlycutSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Clipping.self, Snippet.self, GistRecord.self]
    }

    @Model
    final class Clipping {
        var content: String = ""
        var type: String = "public.utf8-plain-text"
        var sourceAppName: String? = nil
        var sourceAppBundleURL: String? = nil
        var timestamp: Date = Date.now
        var isFavorite: Bool = false
        var displayOrder: Int = 0

        init(content: String, type: String, timestamp: Date = .now) {
            self.content = content
            self.type = type
            self.timestamp = timestamp
        }
    }

    @Model
    final class Snippet {
        var name: String = ""
        var content: String = ""
        var language: String? = nil
        var category: String? = nil
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now

        init(name: String, content: String) {
            self.name = name
            self.content = content
        }
    }

    @Model
    final class GistRecord {
        var gistID: String = ""
        var gistURL: String = ""
        var filename: String = ""
        var createdAt: Date = Date.now

        init(gistID: String, gistURL: String, filename: String) {
            self.gistID = gistID
            self.gistURL = gistURL
            self.filename = filename
        }
    }
}

// Migration plan — no stages needed for v1.0, but the type MUST exist
enum FlycutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FlycutSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []  // No migration needed — this is the first version
    }
}
```

**ModelContainer wiring in FlycutApp:**
```swift
// Source: Apple Developer Documentation — ModelContainer
var sharedModelContainer: ModelContainer = {
    let schema = Schema(FlycutSchemaV1.models)
    let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appending(path: "Flycut/clipboard.sqlite")
    let config = ModelConfiguration(schema: schema, url: url)
    return try! ModelContainer(for: schema, migrationPlan: FlycutMigrationPlan.self, configurations: [config])
}()

// In FlycutApp.body:
.modelContainer(sharedModelContainer)
```

### Pattern 3: AppSettings with @AppStorage

**What:** Centralizes all `UserDefaults`-backed settings as properties on an `@Observable` class so SwiftUI views can bind to them in one place.
**When to use:** Any scalar setting (integer, bool, string) that needs to persist across app restarts.

```swift
// Source: Apple Developer Documentation — AppStorage, Observable
@Observable
final class AppSettings {
    // History settings
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.rememberNum) var rememberNum: Int = 99

    @ObservationIgnored
    @AppStorage(AppSettingsKeys.displayNum) var displayNum: Int = 10

    @ObservationIgnored
    @AppStorage(AppSettingsKeys.displayLen) var displayLen: Int = 40

    // Paste behavior
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.plainTextPaste) var plainTextPaste: Bool = false

    @ObservationIgnored
    @AppStorage(AppSettingsKeys.pasteSound) var pasteSound: Bool = false

    // Launch behavior
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.launchAtLogin) var launchAtLogin: Bool = false

    // Accessibility suppression (mirrors existing Flycut behavior)
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.suppressAccessibilityAlert) var suppressAccessibilityAlert: Bool = false
}

enum AppSettingsKeys {
    static let rememberNum = "rememberNum"
    static let displayNum = "displayNum"
    static let displayLen = "displayLen"
    static let plainTextPaste = "plainTextPaste"
    static let pasteSound = "pasteSound"
    static let launchAtLogin = "launchAtLogin"
    static let suppressAccessibilityAlert = "suppressAccessibilityAlert"
}
```

### Pattern 4: SMAppService Launch at Login

**What:** Registers or unregisters the app as a login item using the modern ServiceManagement API.
**When to use:** When the launchAtLogin toggle changes in Settings.

```swift
// Source: Apple Developer Documentation — SMAppService
import ServiceManagement

@MainActor
func setLaunchAtLogin(_ enabled: Bool) {
    do {
        if enabled {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    } catch {
        // Log with os.Logger; surface error in Settings UI
        logger.error("SMAppService toggle failed: \(error.localizedDescription, privacy: .public)")
    }
}

// To reflect the actual current state (not just the stored bool):
func isCurrentlyRegisteredForLogin() -> Bool {
    SMAppService.mainApp.status == .enabled
}
```

**Key detail:** The Settings toggle must reflect `SMAppService.mainApp.status` (the live system state), not just the stored `@AppStorage` bool. These can diverge if the user disables the login item via System Settings directly.

### Pattern 5: Accessibility Permission Monitor

**What:** Polls `AXIsProcessTrusted()` on a timer and publishes the result for Settings UI to display. Never prompts for permission automatically.
**When to use:** Running the entire time the app is active.

```swift
// Source: Apple Developer Documentation — AXIsProcessTrusted, AXIsProcessTrustedWithOptions
import ApplicationServices

@Observable @MainActor
final class AccessibilityMonitor {
    private(set) var isTrusted: Bool = false
    private var timer: Timer?

    func start() {
        isTrusted = AXIsProcessTrusted()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isTrusted = AXIsProcessTrusted()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Open System Settings directly to the Accessibility pane.
    /// Use this instead of kAXTrustedCheckOptionPrompt — the prompt steals focus.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

### Pattern 6: KeyboardShortcuts Name Declarations (Phase 1 stub)

**What:** Declares the `KeyboardShortcuts.Name` extension so names are available project-wide. Actual registration is Phase 2.
**When to use:** Add in Phase 1 so Settings recorder views can reference names without Phase 2 code.

```swift
// Source: KeyboardShortcuts documentation (github.com/sindresorhus/KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activateBezel = Self("activateBezel")
    static let activateSearch = Self("activateSearch")
}
```

### Pattern 7: Settings Scene with TabView

**What:** Native macOS preferences window using the `Settings` scene and a `TabView` for multiple panes.
**When to use:** macOS 13+ (which is covered by the macOS 15 minimum).

```swift
// Source: Apple Developer Documentation — Settings scene
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeySettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(minWidth: 420, minHeight: 300)
    }
}
```

### Anti-Patterns to Avoid

- **`WindowGroup` for any non-document window:** Activates the app on show — breaks the non-activating bezel in Phase 3. Use `Settings` for preferences, `NSPanel` for bezel.
- **`MenuBarExtra(.window)` style:** Also activates the app. Phase 1 uses `.menu` style only.
- **`AXIsProcessTrustedWithOptions(prompt: true)` on startup or auto-poll:** Steals focus from the user's current app. Only call on explicit user tap ("Request Permission" button).
- **Calling `SMAppService` without checking current status first:** `register()` throws if already registered; always check `.status` before calling.
- **`@Observable` class with `@AppStorage` without `@ObservationIgnored`:** The observation macro and property wrappers conflict. `@AppStorage` properties on `@Observable` classes require `@ObservationIgnored` to compile.
- **`ModelContainer` created with bare `Schema(models)` (no `VersionedSchema`):** Produces an un-versioned container that cannot be migrated cleanly later.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Login item management | Write LaunchAgent plist to `~/Library/LaunchAgents` | `SMAppService.mainApp` | Modern API, no file I/O, handles edge cases (user removes via Settings, multiple user accounts) |
| Settings window wiring | Custom `NSWindowController` + xib | `Settings` scene in `App.body` | Auto-wires cmd-comma, handles window lifecycle, zero boilerplate |
| Hotkey recorder UI | Custom `NSView` keyboard capture | `KeyboardShortcuts.Recorder` | Handles modifier-only keys that SwiftUI `onKeyPress` silently drops; conflict detection built in |
| UserDefaults migration | Custom migration code | Register defaults in `applicationDidFinishLaunching` | `NSUserDefaults.register(defaults:)` provides fallback values without overwriting existing values |
| Accessibility URL construction | Build the URL string manually per OS version | Use `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` | The macOS 13+ URL is stable through macOS 15 |

**Key insight:** Phase 1 is almost entirely Apple first-party APIs. The only SPM dependency added in this phase (`KeyboardShortcuts`) is used only to stub the Name declarations — the library does no work until Phase 2. Resist adding any other dependencies.

---

## Common Pitfalls

### Pitfall 1: Activation Policy Split-Brain

**What goes wrong:** `LSUIElement = YES` in Info.plist suppresses the dock icon at cold launch, but when the `Settings` scene opens a window, the app may briefly flicker a dock icon or fail to regain correct `.accessory` status.

**Why it happens:** SwiftUI's `Settings` scene internally calls `NSApp.activate()` when the window opens. Without explicitly setting the activation policy in `applicationDidFinishLaunching`, this can promote the app to `.regular` (showing dock icon).

**How to avoid:** Always call `NSApp.setActivationPolicy(.accessory)` in `AppDelegate.applicationDidFinishLaunching`, even if `LSUIElement = YES` is already set. Both are required.

**Warning signs:** Run the app, open preferences, quit, relaunch — if a dock icon appears at any point, the policy is broken.

### Pitfall 2: SwiftData Schema Without VersionedSchema

**What goes wrong:** If `@Model` types are defined without `VersionedSchema` in v1.0 and then a property is added in v1.1, SwiftData will attempt a lightweight migration but will fail because it has no version baseline to migrate from. This results in the container failing to load and all user data becoming inaccessible.

**Why it happens:** SwiftData needs to know what the schema looked like before the change. Without a `VersionedSchema` wrapping v1.0, there is no "before" record.

**How to avoid:** Wrap all `@Model` types in `FlycutSchemaV1` (a `VersionedSchema` enum) from the first commit. The `SchemaMigrationPlan` can have empty `stages` for v1.0 — it just needs to exist.

**Warning signs:** Any `@Model` class defined directly in a file without a `VersionedSchema` wrapping.

### Pitfall 3: @Observable + @AppStorage Compile Error

**What goes wrong:** Defining an `@Observable` class with `@AppStorage` properties causes a compile error: `"@AppStorage" cannot be applied to stored properties of a property wrapper type`.

**Why it happens:** The `@Observable` macro generates observation tracking code that conflicts with `@AppStorage`'s property wrapper.

**How to avoid:** Add `@ObservationIgnored` to every `@AppStorage` property within an `@Observable` class. This tells the observation system to skip those properties (they get their own change tracking via `UserDefaults`).

**Warning signs:** Any `@Observable` class with `@AppStorage` properties that lack `@ObservationIgnored`.

### Pitfall 4: SMAppService Status Mismatch

**What goes wrong:** The `@AppStorage` bool for `launchAtLogin` says `true`, but `SMAppService.mainApp.status` returns `.notRegistered` because the user removed the login item via System Settings. The Settings toggle appears "on" but the app won't actually launch at login.

**Why it happens:** `@AppStorage` reflects what the user set via the in-app toggle; `SMAppService.mainApp.status` reflects system ground truth. They can diverge.

**How to avoid:** When the Settings view for launch-at-login appears, sync `@AppStorage` with `SMAppService.mainApp.status == .enabled` on `onAppear`. Always check status before calling `register()` or `unregister()`.

### Pitfall 5: AXIsProcessTrustedWithOptions Focus Theft

**What goes wrong:** Calling `AXIsProcessTrustedWithOptions(prompt: true)` on the polling timer (or in `applicationDidFinishLaunching`) pops up the accessibility permission dialog, which steals focus from whatever app the user is typing in.

**Why it happens:** The `prompt: true` option triggers the system alert immediately.

**How to avoid:** The polling timer always calls bare `AXIsProcessTrusted()` (no options, no prompt). Only call `AXIsProcessTrustedWithOptions(prompt: true)` on an explicit user-initiated action (button tap in Settings). In practice, opening System Settings directly via URL is preferable to the system prompt — it gives the user control without focus theft.

---

## Code Examples

Verified patterns from official sources and codebase analysis:

### Accessibility Settings URL (macOS 13+)

```swift
// Source: Apple Developer Documentation, confirmed in existing Flycut AppController.m
// (openAccessibilitySettings method verified in codebase)
let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
NSWorkspace.shared.open(url)
```

### os.Logger with Privacy (replaces NSLog)

```swift
// Source: Apple Developer Documentation — os.Logger
import OSLog

// Define module-level loggers, never log raw clipboard content
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityMonitor")

logger.info("Accessibility trusted: \(trusted, privacy: .public)")
logger.debug("Polling timer fired")
// NEVER: logger.debug("Clipboard content: \(rawClipboardString)") — privacy violation
```

### ModelContainer with Custom URL

```swift
// Source: Apple Developer Documentation — ModelConfiguration
let url = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "Flycut/clipboard.sqlite")
try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
let config = ModelConfiguration(schema: schema, url: url)
```

### NSUserDefaults Default Registration

```swift
// Source: Apple Developer Documentation — UserDefaults.register(defaults:)
// Called once in applicationDidFinishLaunching; does NOT overwrite existing values
UserDefaults.standard.register(defaults: [
    AppSettingsKeys.rememberNum: 99,
    AppSettingsKeys.displayNum: 10,
    AppSettingsKeys.displayLen: 40,
    AppSettingsKeys.plainTextPaste: false,
    AppSettingsKeys.pasteSound: false,
    AppSettingsKeys.launchAtLogin: false,
    AppSettingsKeys.suppressAccessibilityAlert: false
])
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FlycutHelper login item target | `SMAppService.mainApp.register()` | macOS 13 (2022) | Eliminates entire helper app target — one less build target, no inter-process communication |
| Carbon `RegisterEventHotKey` (SGHotKeysLib) | `KeyboardShortcuts` SPM (CGEventTap-based) | Ongoing; SGHotKeysLib last updated 2014 | Swift 6-safe; provides recorder UI; no Carbon dependency |
| `NSUserDefaults` plist store for clippings | SwiftData `@Model` with SQLite | macOS 17/Xcode 15 (2023) | Proper relational queries, migrations, background writes |
| UKPrefsPanel + NIB files | `Settings` scene + SwiftUI | SwiftUI availability (2019) | Native window lifecycle, zero xib boilerplate |
| Manual `dealloc` / retain/release | ARC + Swift value types | ARC since 2012 | Not applicable in Swift rewrite — noted as "don't reproduce" |
| `activate(ignoringOtherApps:)` | `NSRunningApplication.activate(options:)` | macOS 14 | Previous API deprecated — use `activate(options: .activateIgnoringOtherApps)` on `NSRunningApplication` |

**Deprecated/outdated (do not use in Phase 1):**
- `SMLoginItemSetEnabled` — deprecated since macOS 13; use `SMAppService`
- `NSRegisterServicesProvider` / old login item approach — replaced entirely
- `NSMainNibFile` in Info.plist — SwiftUI apps do not use NIB files

---

## Open Questions

1. **Existing user data migration (plist → SwiftData)**
   - What we know: The existing Flycut stores clipboard history in `FlycutStore` NSUserDefaults plist format under the key `"store"`. `AppController.m` has a `checkAndPerformSandboxDataMigration` method.
   - What's unclear: Whether to offer a one-time plist-to-SwiftData migration for existing Flycut users, or start fresh. The existing migration code handles sandbox container migration, not a format migration.
   - Recommendation: Scope decision — RESEARCH.md documents the concern but leaves it to the planner. If migration is in scope for Phase 1, add a `LegacyMigrationService` that reads the old plist and inserts `Clipping` objects. If not in scope, document as a known data loss for existing users.

2. **Menu bar icon asset**
   - What we know: The existing app has `flycut.icns`. SwiftUI `MenuBarExtra` needs a template image (PDF or PNG with template rendering mode, or a named asset in the asset catalog).
   - What's unclear: Whether to reuse `flycut.icns` or create a new SF Symbol–based icon.
   - Recommendation: Phase 1 can use `systemImage: "doc.on.clipboard"` as a placeholder. A custom icon asset can be added in Phase 3 when polish is in scope.

3. **Bundle identifier continuity**
   - What we know: The existing Flycut bundle ID is `com.generalarcade.flycut`. A new bundle ID would mean new `SMAppService` registration and loss of existing accessibility trust.
   - What's unclear: Whether the Swift rewrite should preserve `com.generalarcade.flycut` or use a new identifier.
   - Recommendation: Preserve the existing bundle ID (`com.generalarcade.flycut`) to retain accessibility trust and avoid confusing users who already granted permissions.

---

## Validation Architecture

`nyquist_validation` is enabled in `.planning/config.json`.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Swift) — to be created in Phase 1 |
| Config file | None currently — Wave 0 creates the test target |
| Quick run command | `xcodebuild test -scheme FlycutTests -destination "platform=macOS" -only-testing FlycutTests 2>&1 \| xcpretty` |
| Full suite command | `xcodebuild test -scheme FlycutTests -destination "platform=macOS" 2>&1 \| xcpretty` |

**Note:** The existing Obj-C codebase has `ENABLE_TESTABILITY = YES` but no test target. The Swift rewrite must create the test target from scratch.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SHELL-01 | App has no dock icon (`LSUIElement`) | Manual smoke | Launch app, verify no dock icon appears | ❌ Wave 0 |
| SHELL-03 | `SMAppService` registers/unregisters correctly | Unit | `xcodebuild test -only-testing FlycutTests/LaunchAtLoginTests` | ❌ Wave 0 |
| SHELL-04 | `AccessibilityMonitor` polls `AXIsProcessTrusted` on 5s timer | Unit | `xcodebuild test -only-testing FlycutTests/AccessibilityMonitorTests` | ❌ Wave 0 |
| SETT-01 | `KeyboardShortcuts.Name` identifiers are declared | Unit (compile-time) | Build succeeds with `activateBezel` and `activateSearch` names | ❌ Wave 0 |
| SETT-02 | `@AppStorage` defaults are registered | Unit | `xcodebuild test -only-testing FlycutTests/AppSettingsTests` | ❌ Wave 0 |
| SETT-03 | Settings toggle syncs to `SMAppService` status | Unit | `xcodebuild test -only-testing FlycutTests/LaunchAtLoginTests` | ❌ Wave 0 |
| SETT-04 | Plain text and sound toggles persist via `@AppStorage` | Unit | `xcodebuild test -only-testing FlycutTests/AppSettingsTests` | ❌ Wave 0 |
| SETT-05 | `Settings` scene opens on cmd-comma | Manual smoke | Press cmd-comma with app running, preferences window appears | ❌ Wave 0 |

**Manual-only justification:**
- SHELL-01 and SETT-05 require visual observation of macOS window chrome — not automatable in XCTest without UI testing infrastructure that is out of scope for Phase 1.

### Sampling Rate

- **Per task commit:** `xcodebuild build -scheme Flycut -destination "platform=macOS"` (build succeeds, no regressions)
- **Per wave merge:** Full `xcodebuild test` run (all unit tests green)
- **Phase gate:** Full test suite green + manual smoke (no dock icon, preferences window opens, settings persist across restart)

### Wave 0 Gaps

- [ ] `FlycutTests/` test target — create in Xcode, add to scheme
- [ ] `FlycutTests/AppSettingsTests.swift` — covers SETT-02, SETT-04 (`@AppStorage` defaults and persistence)
- [ ] `FlycutTests/LaunchAtLoginTests.swift` — covers SHELL-03, SETT-03 (SMAppService registration state; must mock `SMAppService` or use a test double to avoid actual system login item changes)
- [ ] `FlycutTests/AccessibilityMonitorTests.swift` — covers SHELL-04 (timer fires, publishes `isTrusted`; mock `AXIsProcessTrusted` via dependency injection)
- [ ] `FlycutTests/SwiftDataSchemaTests.swift` — covers CLIP-05 contract (ModelContainer loads without error, Clipping inserts and fetches round-trip correctly)

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation — `SMAppService` — `register()`, `unregister()`, `.status` — verified current for macOS 13+, stable through macOS 15
- Apple Developer Documentation — `AXIsProcessTrusted()`, `AXIsProcessTrustedWithOptions` — stable API, confirmed behavior in existing Flycut `AppController.m`
- Apple Developer Documentation — SwiftData `VersionedSchema`, `SchemaMigrationPlan`, `ModelConfiguration(url:)` — WWDC23 introduced, confirmed available macOS 17/Xcode 15+
- Apple Developer Documentation — `MenuBarExtra`, `Settings` scene, `@NSApplicationDelegateAdaptor` — SwiftUI macOS APIs
- Flycut `AppController.m` — direct source for `openAccessibilitySettings` URL pattern, `NSUserDefaults` key names, activation policy requirements
- Flycut `Info.plist` — confirmed `LSUIElement = 1` is already the pattern; bundle ID `com.generalarcade.flycut`

### Secondary (MEDIUM confidence)

- KeyboardShortcuts Package.swift (github.com/sindresorhus/KeyboardShortcuts) — confirmed swift-tools-version 6.2, `MainActor` default isolation, strict concurrency settings; v2.4.0 is current
- SwiftData VersionedSchema pattern — HackingWithSwift tutorial cross-referenced with Apple WWDC23 session "Model your schema with SwiftData"
- Swift Forums — `SwiftData SchemaMigrationPlan and VersionedSchema not Sendable` thread — confirms the `@ObservationIgnored` + `@AppStorage` interaction is a known pattern in the community

### Tertiary (LOW confidence — validated before implementation)

- `@Observable` + `@AppStorage` requires `@ObservationIgnored` — widespread community report (multiple forums, SO), but no official Apple documentation link found confirming it. Verify by compiling the pattern; the compiler error is self-documenting.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Phase 1 APIs are Apple first-party with stable documentation; KeyboardShortcuts Swift 6 compat confirmed
- Architecture: HIGH — direct translation of existing Flycut patterns into Swift idioms; all patterns have working code samples
- Pitfalls: HIGH — Pitfall 1 (activation policy) confirmed by Flycut existing code; Pitfall 2 (VersionedSchema) confirmed by Apple docs; Pitfall 3 (`@ObservationIgnored`) widely reported; Pitfalls 4-5 confirmed by existing `AppController.m` patterns

**Research date:** 2026-03-05
**Valid until:** 2026-06-05 (stable Apple APIs; KeyboardShortcuts version should be re-checked if > 3 months pass)
