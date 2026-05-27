# Phase 11: App Launcher - Pattern Map

**Mapped:** 2026-05-25
**Files analyzed:** 10 (4 new, 6 modified)
**Analogs found:** 10 / 10

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Clipsmith/Services/AppScannerService.swift` | service | batch (file-I/O + transform) | `Clipsmith/Services/PromptSyncService.swift` | role-match |
| `Clipsmith/Views/AppLaunchController.swift` | controller | request-response | `Clipsmith/Views/PromptBezelController.swift` | exact |
| `Clipsmith/Views/AppLaunchViewModel.swift` | provider/store | transform | `Clipsmith/Views/PromptBezelViewModel.swift` | exact |
| `Clipsmith/Views/AppLaunchView.swift` | component | request-response | `Clipsmith/Views/PromptBezelView.swift` | exact |
| `Clipsmith/App/AppDelegate.swift` | controller | event-driven | self (modify) | exact |
| `Clipsmith/Settings/AppSettingsKeys.swift` | config | — | self (modify) | exact |
| `Clipsmith/Settings/KeyboardShortcutNames.swift` | config | — | self (modify) | exact |
| `Clipsmith/Views/MenuBarView.swift` | component | event-driven | self (modify) | exact |
| `Clipsmith/Views/Settings/HotkeySettingsTab.swift` | component | — | self (modify) | exact |
| `Clipsmith/Views/Settings/GeneralSettingsTab.swift` | component | — | self (modify) | exact |
| `ClipsmithTests/AppLaunchViewModelTests.swift` | test | — | `ClipsmithTests/DocsetSearchServiceTests.swift` | role-match |
| `ClipsmithTests/AppScannerServiceTests.swift` | test | — | `ClipsmithTests/DocsetSearchServiceTests.swift` | role-match |

---

## Pattern Assignments

### `Clipsmith/Services/AppScannerService.swift` (service, batch file-I/O)

**Analog:** `Clipsmith/Services/PromptSyncService.swift`

**Imports pattern** (PromptSyncService.swift lines 1–7):
```swift
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "AppScannerService"          // rename from "PromptSyncService"
)
```

**Class declaration pattern** (PromptSyncService.swift lines 45–61):
```swift
// @MainActor @Observable — same as PromptSyncService; no ModelActor needed
@MainActor @Observable
final class AppScannerService {

    // MARK: - Properties

    private(set) var apps: [AppEntry] = []
    private(set) var isLoading: Bool = false

    // recentBundleIDs: max 5, ordered most-recent-first
    // Loaded from UserDefaults on init; written on every recordLaunch()
    private(set) var recentBundleIDs: [String] = []
```

**Async method structure pattern** (PromptSyncService.swift lines 119–166 — the isSyncing gate):
```swift
// Mirror the isSyncing → do { … } catch { lastError = … } pattern
// but replace network I/O with Task.detached file-system scan.
func refresh() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    let entries = await Task.detached(priority: .userInitiated) {
        await self.scanApps()
    }.value
    self.apps = entries
}
```

**UserDefaults persistence pattern** (PromptSyncService.swift line 156 — ISO timestamp write):
```swift
// Mirrors UserDefaults.standard.set(iso, forKey: AppSettingsKeys.promptLibraryLastSync)
// For AppScannerService use:
func recordLaunch(bundleID: String) {
    var recent = UserDefaults.standard.stringArray(
        forKey: AppSettingsKeys.recentAppBundleIDs) ?? []
    recent.removeAll { $0 == bundleID }
    recent.insert(bundleID, at: 0)
    if recent.count > 5 { recent = Array(recent.prefix(5)) }
    UserDefaults.standard.set(recent, forKey: AppSettingsKeys.recentAppBundleIDs)
    recentBundleIDs = recent
}
```

---

### `Clipsmith/Views/AppLaunchController.swift` (controller, request-response)

**Analog:** `Clipsmith/Views/PromptBezelController.swift`

**Imports + logger pattern** (PromptBezelController.swift lines 1–9):
```swift
import AppKit
import SwiftUI
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "AppLaunchController"
)
```

**Class declaration + stored properties** (PromptBezelController.swift lines 25–48):
```swift
@MainActor
final class AppLaunchController: NSPanel {

    let viewModel = AppLaunchViewModel()

    // Services injected after init (set by AppDelegate before first show)
    var appScannerService: AppScannerService?

    private var globalMonitor: Any?
    // NOTE: AppLaunchController has NO isHotkeyHold — launcher is always sticky
```

**Init pattern** — use the simpler no-arg version (PromptBezelController.swift lines 73–106):
```swift
// CRITICAL differences vs. PromptBezelController:
// 1. No modelContainer parameter — no SwiftData
// 2. Plain init() — not convenience init(modelContainer:)
// 3. hostingView wraps AppLaunchView directly (no AnyView/modelContainer wrapping)
init() {
    super.init(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false

    let hostingView = NSHostingView(rootView: AppLaunchView(viewModel: viewModel))
    hostingView.sizingOptions = []   // CRITICAL: prevents infinite constraint loop crash
    contentView = hostingView
}
```

**canBecomeKey/canBecomeMain** (PromptBezelController.swift lines 110–111):
```swift
override var canBecomeKey: Bool { true }
override var canBecomeMain: Bool { false }
```

**sendEvent override** (PromptBezelController.swift lines 118–148 — simplified for search-always mode):
```swift
// Launcher is always in search mode — drop Tab/j/k intercepts from PromptBezelController
override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown {
        switch event.keyCode {
        case 53:                             // Escape
            hide(); return
        case 36, 76:                         // Return, Enter (numpad)
            launchSelected(); return
        case 125, 126, 123, 124,             // Arrow keys
             121, 116, 119, 115:             // Page Down/Up, End, Home
            keyDown(with: event); return
        default:
            break
        }
    }
    super.sendEvent(event)
}
```

**show() / configureAndPresent() / hide() pattern** (PromptBezelController.swift lines 157–191):
```swift
func show() {
    viewModel.selectedIndex = 0
    viewModel.searchText = ""
    // Trigger async cache refresh each open (CONTEXT D-02)
    Task { await appScannerService?.refresh() }
    configureAndPresent()
    logger.info("AppLaunchController shown")
}

private func configureAndPresent() {
    viewModel.wraparoundBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.wraparoundBezel)
    let width = UserDefaults.standard.double(forKey: AppSettingsKeys.bezelWidth)
    let height = UserDefaults.standard.double(forKey: AppSettingsKeys.bezelHeight)
    if width > 0 && height > 0 { setContentSize(NSSize(width: width, height: height)) }
    alphaValue = 1.0
    centerOnScreen()
    makeKeyAndOrderFront(nil)
    registerClickOutsideMonitor()
}

func hide() {
    orderOut(nil)
    removeClickOutsideMonitor()
    viewModel.selectedIndex = 0
    viewModel.searchText = ""
    logger.info("AppLaunchController hidden")
}
```

**keyDown routing** (PromptBezelController.swift lines 194–234 — stripped to navigation only):
```swift
override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:        hide()
    case 36, 76:    launchSelected()
    case 125, 124:  viewModel.navigateDown()
    case 126, 123:  viewModel.navigateUp()
    case 121:       viewModel.navigateDownTen()
    case 116:       viewModel.navigateUpTen()
    case 119:       viewModel.navigateToLast()
    case 115:       viewModel.navigateToFirst()
    default:        super.keyDown(with: event)
    }
}
```

**Click-outside monitor** (PromptBezelController.swift lines 317–332):
```swift
private func registerClickOutsideMonitor() {
    removeClickOutsideMonitor()
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
        guard let self else { return }
        if !self.frame.contains(NSEvent.mouseLocation) {
            Task { @MainActor in self.hide() }
        }
    }
}

private func removeClickOutsideMonitor() {
    if let monitor = globalMonitor {
        NSEvent.removeMonitor(monitor)
        globalMonitor = nil
    }
}
```

**centerOnScreen helper** (PromptBezelController.swift lines 288–297):
```swift
private func centerOnScreen() {
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame
    let panelSize = frame.size
    let origin = NSPoint(
        x: screenFrame.midX - panelSize.width / 2,
        y: screenFrame.midY - panelSize.height / 2
    )
    setFrameOrigin(origin)
}
```

**launchSelected() — new method, no analog in PromptBezelController:**
```swift
// Source: RESEARCH.md Pattern 5 (verified NSWorkspace API)
func launchSelected() {
    guard let entry = viewModel.currentApp else { hide(); return }
    hide()   // dismiss FIRST, then launch
    if let bundleID = entry.bundleID {
        appScannerService?.recordLaunch(bundleID: bundleID)
    }
    let config = NSWorkspaceOpenConfiguration()
    // config.activates = true by default — no override needed
    NSWorkspace.shared.openApplication(
        at: entry.url,
        configuration: config,
        completionHandler: { _, error in
            if let error {
                logger.error("Failed to launch app: \(error.localizedDescription)")
            }
        }
    )
}
```

---

### `Clipsmith/Views/AppLaunchViewModel.swift` (provider, transform)

**Analog:** `Clipsmith/Views/PromptBezelViewModel.swift`

**Imports + class declaration** (PromptBezelViewModel.swift lines 1–18):
```swift
import Foundation
import Observation

@Observable @MainActor
final class AppLaunchViewModel {
```

**State properties** (PromptBezelViewModel.swift lines 27–57):
```swift
/// Full app list — set by AppScannerService after each scan.
var apps: [AppEntry] = [] {
    didSet { recomputeDisplayedApps() }
}

var selectedIndex: Int = 0

var searchText: String = "" {
    didSet {
        selectedIndex = 0
        recomputeDisplayedApps()
    }
}

/// Always true — launcher is always in instant-search mode (CONTEXT D-03).
var isSearchMode: Bool = true

/// Loading placeholder: true while AppScannerService is scanning.
var isLoading: Bool = false

/// Wrap-around navigation setting (read from UserDefaults in configureAndPresent).
var wraparoundBezel: Bool = false

private(set) var displayedApps: [AppEntry] = []
```

**Filtering / ranking** (PromptBezelViewModel.swift lines 72–130 — recomputeFilteredPrompts pattern):
```swift
// Replace PromptBezelViewModel.recomputeFilteredPrompts() with:
func recomputeDisplayedApps() {
    // CONTEXT D-04: empty query → show up to 5 most recently launched apps
    guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
        displayedApps = recentApps()
        return
    }
    // CONTEXT D-05: FuzzyMatcher score + recency boost within 0.1
    let recentIDs = Set(recentBundleIDs)
    let q = searchText.trimmingCharacters(in: .whitespaces)
    let scored: [(AppEntry, Double)] = apps.compactMap { app in
        guard var score = FuzzyMatcher.score(app.name, query: q) else { return nil }
        if let bid = app.bundleID, recentIDs.contains(bid) { score += 0.1 }
        return (app, score)
    }
    displayedApps = scored.sorted { $0.1 > $1.1 }.map(\.0)
}

/// recentBundleIDs injected from AppScannerService before each call.
var recentBundleIDs: [String] = [] {
    didSet { recomputeDisplayedApps() }
}

private func recentApps() -> [AppEntry] {
    var result: [AppEntry] = []
    for id in recentBundleIDs.prefix(5) {
        if let app = apps.first(where: { $0.bundleID == id }) {
            result.append(app)
        }
    }
    return result
}
```

**currentApp computed property** (mirrors PromptBezelViewModel.swift lines 135–139):
```swift
var currentApp: AppEntry? {
    let list = displayedApps
    guard !list.isEmpty, selectedIndex >= 0, selectedIndex < list.count else { return nil }
    return list[selectedIndex]
}

var navigationLabel: String {
    let list = displayedApps
    guard !list.isEmpty else { return "" }
    return "\(selectedIndex + 1) of \(list.count)"
}
```

**Navigation methods** (PromptBezelViewModel.swift lines 176–223 — copy verbatim, swap `filteredPrompts` → `displayedApps`):
```swift
func navigateUp() { /* same logic as PromptBezelViewModel.navigateUp() */ }
func navigateDown() { /* same logic as PromptBezelViewModel.navigateDown() */ }
func navigateToFirst() { selectedIndex = 0 }
func navigateToLast() { selectedIndex = max(0, displayedApps.count - 1) }
func navigateUpTen() { selectedIndex = max(0, selectedIndex - 10) }
func navigateDownTen() { selectedIndex = min(max(0, displayedApps.count - 1), selectedIndex + 10) }
func navigateTo(index: Int) {
    guard !displayedApps.isEmpty else { return }
    selectedIndex = max(0, min(index, displayedApps.count - 1))
}
```

---

### `Clipsmith/Views/AppLaunchView.swift` (component, request-response)

**Analog:** `Clipsmith/Views/PromptBezelView.swift`

**Imports + struct declaration** (PromptBezelView.swift lines 1–30):
```swift
import SwiftUI
// NOTE: No SwiftData import — no @Query needed

struct AppLaunchView: View {

    @Bindable var viewModel: AppLaunchViewModel

    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25

    @FocusState private var isSearchFieldFocused: Bool
```

**Body layout** (PromptBezelView.swift lines 33–107 — VStack(spacing: 0) shell with frosted glass):
```swift
var body: some View {
    VStack(spacing: 0) {
        // Header (no Tab-cycling hint — launcher has no category concept)
        HStack {
            Text("App Launcher")
                .font(.caption.bold())
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.regularMaterial)

        Divider()

        // Search field — always focused (CONTEXT D-03)
        TextField("Search apps...", text: $viewModel.searchText)
            .textFieldStyle(.plain)
            .focused($isSearchFieldFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)

        Divider()

        // App list / loading / empty states
        Group {
            if viewModel.isLoading && viewModel.apps.isEmpty {
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

        Divider()

        // Navigation counter footer
        HStack {
            Spacer()
            Text(viewModel.navigationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
    .background(                             // frosted glass — copy verbatim
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor).opacity(1.0 - bezelAlpha))
        }
    )
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .onAppear { isSearchFieldFocused = true }
}
```

**App row sub-view** (icon + name, mirrors PromptBezelView.swift lines 144–170):
```swift
// CONTEXT D-06: icon ~24pt square + app name; no category badge needed
private func appRow(entry: AppEntry, index: Int) -> some View {
    let isSelected = index == viewModel.selectedIndex
    return HStack(spacing: 10) {
        // Icon: show NSImage or placeholder
        if let icon = entry.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        }
        Text(entry.name)
            .font(.body)
            .foregroundStyle(.primary)
            .lineLimit(1)
        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
}
```

**ScrollViewReader list** (PromptBezelView.swift lines 123–141 — copy verbatim, swap type):
```swift
private var appListView: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.displayedApps.enumerated()), id: \.element.id) { index, entry in
                    appRow(entry: entry, index: index)
                        .id(index)
                        .onTapGesture { viewModel.navigateTo(index: index) }
                }
            }
        }
        .onChange(of: viewModel.selectedIndex) { _, newIndex in
            withAnimation(.easeInOut(duration: 0.1)) {
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }
}
```

---

### `Clipsmith/App/AppDelegate.swift` (modify)

**Analog:** self — existing docLookupEnabled block + PromptBezelController wiring

**Property declaration** (AppDelegate.swift lines 40–43 — add after phase 10 block):
```swift
// Phase 11 — App Launcher
var appScannerService: AppScannerService!
var appLaunchController: AppLaunchController!
```

**Controller initialization in applicationDidFinishLaunching** (AppDelegate.swift lines 168–172 — mirror docBezelController block):
```swift
// Initialize App Launcher components (Phase 11).
appScannerService = AppScannerService()
appLaunchController = AppLaunchController()
appLaunchController.appScannerService = appScannerService
// Warm the cache asynchronously at startup (CONTEXT D-02).
Task { await appScannerService.refresh() }
```

**UserDefaults register(defaults:) addition** (AppDelegate.swift lines 58–86 — add entry):
```swift
AppSettingsKeys.appLauncherEnabled: false,
```

**Hotkey registration** (AppDelegate.swift lines 346–365 — docLookupEnabled guard is the exact pattern to copy):
```swift
// Register global hotkey for app launcher (Phase 11).
// Always registered; checks feature flag at invocation time (CONTEXT D-10).
KeyboardShortcuts.onKeyDown(for: .appLauncher) { [weak self] in
    Task { @MainActor in
        guard let self else { return }
        guard UserDefaults.standard.bool(forKey: AppSettingsKeys.appLauncherEnabled) else {
            return
        }
        if self.appLaunchController.isVisible {
            self.appLaunchController.viewModel.navigateDown()
        } else {
            self.appLaunchController.show()
        }
    }
}
```

**Notification observer** (AppDelegate.swift lines 218–223 — openSearchFromMenu pattern):
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(openAppLauncherFromMenu),
    name: .clipsmithOpenAppLauncher,
    object: nil
)
```

**Handler method** (AppDelegate.swift lines 376–378 — openDocLookupFromMenu pattern):
```swift
@objc private func openAppLauncherFromMenu() {
    appLaunchController?.show()
}
```

---

### `Clipsmith/Settings/AppSettingsKeys.swift` (modify)

**Analog:** self — existing phase-comment pattern (lines 43–44)

**Addition pattern** (AppSettingsKeys.swift lines 43–44):
```swift
// Phase 11 additions (App Launcher)
static let appLauncherEnabled = "appLauncherEnabled"
static let recentAppBundleIDs = "recentAppBundleIDs"
```

---

### `Clipsmith/Settings/KeyboardShortcutNames.swift` (modify)

**Analog:** self — existing Name extension pattern (lines 19–22)

**Addition pattern** (KeyboardShortcutNames.swift lines 19–22):
```swift
/// Hotkey that opens the app launcher bezel. No default binding (CONTEXT D-07).
static let appLauncher = Self("appLauncher")
```

---

### `Clipsmith/Views/MenuBarView.swift` (modify)

**Analog:** self

**Notification.Name extension addition** (MenuBarView.swift lines 4–19 — add to existing extension):
```swift
static let clipsmithOpenAppLauncher = Notification.Name("clipsmithOpenAppLauncher")
```

**@AppStorage addition** (MenuBarView.swift line 39 — mirror docLookupEnabled):
```swift
@AppStorage(AppSettingsKeys.appLauncherEnabled) private var appLauncherEnabled: Bool = false
```

**Menu button** (MenuBarView.swift lines 96–100 — docLookupEnabled conditional button pattern):
```swift
if appLauncherEnabled {
    Button("App Launcher...") {
        NotificationCenter.default.post(name: .clipsmithOpenAppLauncher, object: nil)
    }
}
```

---

### `Clipsmith/Views/Settings/HotkeySettingsTab.swift` (modify)

**Analog:** self — existing Recorder pattern (lines 29–34)

**Addition** (HotkeySettingsTab.swift lines 29–34 — add after Doc Lookup recorder):
```swift
KeyboardShortcuts.Recorder(
    "App Launcher",
    name: .appLauncher
)
```

Also update footer text to mention app launcher.

---

### `Clipsmith/Views/Settings/GeneralSettingsTab.swift` (modify)

**Analog:** self — docLookupEnabled toggle pattern (lines 43, 156–159)

**@AppStorage addition** (GeneralSettingsTab.swift line 43):
```swift
// Phase 11: feature flag
@AppStorage(AppSettingsKeys.appLauncherEnabled) private var appLauncherEnabled: Bool = false
```

**Toggle in Features section** (GeneralSettingsTab.swift lines 156–159 — add after docLookupEnabled Toggle):
```swift
Toggle("App Launcher", isOn: $appLauncherEnabled)
    .help("Enable keyboard-driven app launcher (no default hotkey — configure in Shortcuts tab).")
```

---

### `ClipsmithTests/AppLaunchViewModelTests.swift` (new)

**Analog:** `ClipsmithTests/DocsetSearchServiceTests.swift`

**Test file structure pattern** (DocsetSearchServiceTests.swift lines 1–10):
```swift
import XCTest
@testable import Clipsmith

final class AppLaunchViewModelTests: XCTestCase {
    private var viewModel: AppLaunchViewModel!
    private var sampleApps: [AppEntry]!

    override func setUp() {
        viewModel = AppLaunchViewModel()
        sampleApps = [
            AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"),
                     bundleID: "com.apple.Safari", icon: nil),
            AppEntry(name: "Terminal", url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                     bundleID: "com.apple.Terminal", icon: nil),
            // ... more fixtures
        ]
        viewModel.apps = sampleApps
    }
    // Tests: fuzzy filter, recency boost, empty-query→recent-apps, navigation
}
```

---

### `ClipsmithTests/AppScannerServiceTests.swift` (new)

**Analog:** `ClipsmithTests/DocsetSearchServiceTests.swift`

**Test file structure pattern** (DocsetSearchServiceTests.swift lines 1–10):
```swift
import XCTest
@testable import Clipsmith

final class AppScannerServiceTests: XCTestCase {
    private var service: AppScannerService!

    override func setUp() {
        service = AppScannerService()
    }
    // Tests: recordLaunch ordering, max-5 truncation, dedup by bundleID
}
```

---

## Shared Patterns

### Non-activating NSPanel Init (CRITICAL)

**Source:** `Clipsmith/Views/PromptBezelController.swift` lines 73–82
**Apply to:** `AppLaunchController.swift` init
```swift
// .nonactivatingPanel MUST be in super.init styleMask — cannot be set afterwards.
super.init(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
    styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
```

### NSHostingView sizingOptions = [] (CRITICAL)

**Source:** `Clipsmith/Views/PromptBezelController.swift` line 102
**Apply to:** `AppLaunchController.swift` init
```swift
hostingView.sizingOptions = []   // prevents infinite constraint update loop crash
contentView = hostingView
```

### OSLog Logger Declaration

**Source:** `Clipsmith/Views/PromptBezelController.swift` lines 6–9 and `Clipsmith/Services/PromptSyncService.swift` lines 4–7
**Apply to:** All new `.swift` files (`AppScannerService`, `AppLaunchController`)
```swift
private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "FileName"
)
```

### Feature Flag Guard in AppDelegate Hotkey Handler

**Source:** `Clipsmith/App/AppDelegate.swift` lines 346–365 (activateDocLookup block)
**Apply to:** `AppDelegate.swift` — appLauncher hotkey handler
```swift
guard UserDefaults.standard.bool(forKey: AppSettingsKeys.appLauncherEnabled) else { return }
```

### Frosted Glass Background

**Source:** `Clipsmith/Views/PromptBezelView.swift` lines 87–99
**Apply to:** `AppLaunchView.swift` body background modifier — copy verbatim
```swift
.background(
    ZStack {
        RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(NSColor.windowBackgroundColor).opacity(1.0 - bezelAlpha))
    }
)
.clipShape(RoundedRectangle(cornerRadius: 16))
```

### @MainActor @Observable Service Declaration

**Source:** `Clipsmith/Services/PromptSyncService.swift` line 45
**Apply to:** `AppScannerService.swift`
```swift
@MainActor @Observable
final class AppScannerService {
```

### Conditional Menu Button with Feature Flag

**Source:** `Clipsmith/Views/MenuBarView.swift` lines 96–100
**Apply to:** `MenuBarView.swift` — appLauncher button addition
```swift
if appLauncherEnabled {
    Button("App Launcher...") { ... }
}
```

---

## No Analog Found

All files have close analogs. No files require falling back to RESEARCH.md patterns exclusively.

---

## Metadata

**Analog search scope:** `Clipsmith/Views/`, `Clipsmith/Services/`, `Clipsmith/App/`, `Clipsmith/Settings/`, `ClipsmithTests/`
**Files scanned:** 12 source files read in full
**Pattern extraction date:** 2026-05-25
