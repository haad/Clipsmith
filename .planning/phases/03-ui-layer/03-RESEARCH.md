# Phase 3: UI Layer — Research

**Researched:** 2026-03-05
**Domain:** NSPanel non-activating bezel HUD, SwiftUI-hosted overlay, keyboard navigation, search/filter, multi-monitor centering, Spaces/fullscreen overlay, menu bar enhancement
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BEZL-01 | Floating bezel HUD appears without activating Flycut (non-activating NSPanel) | `NSPanel` subclass with `.nonactivatingPanel` style mask, `canBecomeKey` override; `NSHostingView` wraps SwiftUI content; `makeKeyAndOrderFront` shows without activating owning app |
| BEZL-02 | Bezel displays current clipping content with navigation indicators | SwiftUI view hosted in NSPanel via `NSHostingView`; `@State selectedIndex` drives which `Clipping` is displayed; navigation counter ("3 of 47") shown via computed string |
| BEZL-03 | Bezel appears centered on the screen containing the mouse cursor | `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })` selects the correct screen; window frame set to mid-X, mid-Y of that screen's `visibleFrame` |
| BEZL-04 | Bezel works over fullscreen apps and across all Spaces | `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`; `panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)` ensures it floats above fullscreen |
| BEZL-05 | Bezel dismisses on paste, Escape key, or clicking outside | Escape handled in `keyDown`; paste calls `panel.orderOut`; click-outside detected via `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)`; `panel.hidesOnDeactivate` kept `false` (non-activating panel has no deactivate) |
| INTR-02 | User can navigate clipping history with arrow keys, jump 10, first/last | `keyDown` in NSPanel subclass or `NSEvent.addLocalMonitorForEvents`; Up/Left/PageUp/Home/End/PageDown key codes mapped to index changes; `@State var selectedIndex` drives displayed clipping |
| INTR-04 | User can search/filter clippings by text content | `@State var searchText` in bezel SwiftUI view; `TextField` inside the NSPanel receives key input via `canBecomeKey = true`; filtered clippings array derived via `.filter { $0.content.localizedCaseInsensitiveContains(searchText) }` |
| SHELL-02 | Menu bar dropdown shows recent clippings with preview text | Already partially complete from Phase 2 (`MenuBarView` with `@Query` list); Phase 3 adds: preview truncation is already implemented; no new structural work needed unless the requirement is re-read as "clickable items paste" which Phase 2 already does |
</phase_requirements>

---

## Summary

Phase 3 builds the visible, interactive UI surfaces: a floating bezel HUD that overlays every app on every Space, a search/filter capability embedded in that HUD, and the menu bar dropdown already wired in Phase 2. The phase has one dominant technical problem — the bezel must appear above fullscreen apps and Mission Control spaces without stealing focus from the user's active app — and two secondary problems: centering the bezel on the monitor that contains the mouse cursor, and routing keyboard events to the bezel when the app is non-activating.

The original Flycut Objective-C `BezelWindow` (in `UI/BezelWindow.m`) is a direct `NSPanel` subclass with `NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless`. It sets `level = NSScreenSaverWindowLevel`, overrides `canBecomeKeyWindow` to return `YES`, and routes keyboard events to its delegate via `keyDown:` and `performKeyEquivalent:`. The Swift 6 rewrite translates this pattern faithfully, hosting a SwiftUI content view via `NSHostingView` rather than hand-drawing `RoundRecTextField` widgets. The navigation model (arrow keys change `selectedIndex`, Enter pastes and hides) is a 1:1 translation of `processBezelKeyDown:`.

The search window in the original Flycut is a separate `NSWindow` (`buildSearchWindow`) with an `NSSearchField` and `NSTableView`. For the Swift rewrite, search is embedded directly in the bezel view: a `TextField` at the top with `@State var searchText`, and the displayed clipping list derives from `clippings.filter { $0.content.localizedCaseInsensitiveContains(searchText) }`. This collapses two UI surfaces into one and aligns with the requirement that "typing in the bezel filters visible clippings."

One previously noted concern in STATE.md — "NSPanel + Stage Manager interaction on macOS 15 is underdocumented" — is partially resolved by research: the combination of `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` plus window level above `screenSaverWindow` is the established pattern and is confirmed to work by multiple open-source implementations (Maccy, Raycast-style tools). Stage Manager does not fully block `.canJoinAllSpaces` panels. The residual risk is that Stage Manager may partially obscure or rearrange panels on macOS 15; the recommendation is to test early in Phase 3 Wave 0.

**Primary recommendation:** Build `BezelController` as an `NSPanel` subclass in `FlycutSwift/Views/BezelController.swift`, hosting a `BezelView` SwiftUI struct via `NSHostingView`. Wire it in `AppDelegate` by replacing the "log only" stub in the `activateBezel` hotkey handler. Keep the search text state inside `BezelView` and derive the filtered list there.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit `NSPanel` | System (macOS 15) | Non-activating floating overlay | Only window class with `.nonactivatingPanel` style mask; `canBecomeKey = true` allows text input while not activating the owning app |
| SwiftUI `NSHostingView` | System (macOS 15) | Embed SwiftUI content in NSPanel | `NSHostingView<Content>` sets as `contentView`; zero boilerplate; existing services already injected via environment |
| AppKit `NSEvent.addGlobalMonitorForEvents` | System | Detect clicks outside the bezel | Global event monitor for `.leftMouseDown`; checks if click is outside panel frame, then dismisses |
| AppKit `NSEvent.addLocalMonitorForEvents` | System | Intercept key events in non-activating panel | Local monitor can forward key events to the panel even when it is not the key window in the traditional sense |
| Swift 6 / SwiftUI | 6 | Language and UI framework | Already in project; `@State`, `@Query`, `@Observable` drive bezel UI |
| SwiftData `@Query` | macOS 14+ | Fetch clipping list for bezel | Same `@Query` pattern already in `MenuBarView`; filtered by `searchText` using `.filter` |
| KeyboardShortcuts (sindresorhus) | 2.4.0 | Hotkey triggers bezel show | Already registered in `AppDelegate`; Phase 3 replaces stub with `bezelController.show()` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.Logger` | System | Privacy-safe diagnostics | Log navigation events (index changes), show/hide events; never log clipping content |
| AppKit `NSScreen` | System | Multi-monitor screen selection | `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })` for centering |
| AppKit `NSApplication` | System | Activation control | `NSApp.activate()` NOT called on bezel show — activating breaks the non-activating contract |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `NSPanel` subclass | `NSWindow` + `.nonactivatingPanel` style mask | Setting `.nonactivatingPanel` on an `NSWindow` after init fails silently (WindowServer tag not updated); must use `NSPanel` from the start |
| In-bezel search (`TextField`) | Separate `NSWindow` search surface | Original Flycut has a separate `SearchWindow`; embedding in bezel is simpler, matches modern clipboard managers (Maccy), and satisfies INTR-04 without a second window |
| `NSHostingView` inside NSPanel | Pure AppKit controls (labels, custom drawing) | Original Flycut hand-draws `RoundRecTextField`; SwiftUI approach eliminates 500+ lines of drawing code while keeping all behavior |
| `NSEvent.addGlobalMonitorForEvents` for click-outside dismiss | `windowDidResignKey` notification | Non-activating panels often do not fire `windowDidResignKey` reliably; the global event monitor is the explicit pattern used by Alfred, Raycast, Maccy |

**Installation:** No new packages needed. All Phase 3 dependencies are Apple system frameworks or already-installed libraries (KeyboardShortcuts 2.4.0).

---

## Architecture Patterns

### Recommended Project Structure (additions to Phase 2)

```
FlycutSwift/
├── App/
│   ├── FlycutApp.swift          # No change
│   └── AppDelegate.swift        # Replace hotkey stubs with bezelController.show()/showSearch()
├── Services/                    # No change from Phase 2
├── Views/
│   ├── BezelController.swift    # NEW: NSPanel subclass — owns lifecycle, show/hide, keyboard routing
│   ├── BezelView.swift          # NEW: SwiftUI view — clipping display, navigation, search filter
│   ├── MenuBarView.swift        # Existing — already complete from Phase 2 (SHELL-02 done)
│   └── Settings/                # No change
└── Models/                      # No change
```

### Pattern 1: BezelController — NSPanel Subclass

**What:** An `NSPanel` subclass that sets `.nonactivatingPanel` style mask during `init`, overrides `canBecomeKey` to `true`, sets `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, and manages show/hide lifecycle.

**When to use:** Instantiated once in `AppDelegate`, shown/hidden in response to `activateBezel` hotkey.

**Critical detail:** The `.nonactivatingPanel` style mask MUST be set in the `init` call, not afterward. If you set `styleMask.insert(.nonactivatingPanel)` post-init, the WindowServer tag is not updated and the panel silently behaves as an activating window. This is the root cause noted in the STATE.md concern.

```swift
// Source: AppController.m BezelWindow.m direct translation + cindori.com floating-panel pattern
// Confirmed by: philz.blog nspanel-nonactivating-style-mask-flag
import AppKit
import SwiftUI

@MainActor
final class BezelController: NSPanel {

    private var globalMonitor: Any?

    init() {
        // Step 1: init with .nonactivatingPanel in the initial styleMask call.
        // CRITICAL: cannot add this bit post-init — WindowServer tag is not updated.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Step 2: Window level above screenSaverWindow floats above fullscreen apps.
        // Original Flycut uses NSScreenSaverWindowLevel. Swift equivalent:
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)

        // Step 3: Spaces + fullscreen coverage.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Step 4: Visual properties.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false   // reuse the same panel; don't deallocate on close

        // Step 5: Inject the SwiftUI bezel content view.
        contentView = NSHostingView(rootView: BezelView())
    }

    // MUST return true so TextField and key events work inside a non-activating panel.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }  // stays false — main window is not relevant

    // MARK: - Show / Hide

    func show(clippings: [FlycutSchemaV1.Clipping]) {
        // Center on screen containing mouse cursor.
        let targetScreen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let sf = targetScreen.visibleFrame
        let x = sf.midX - frame.width / 2
        let y = sf.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))

        makeKeyAndOrderFront(nil)

        // Register global mouse monitor to dismiss on outside click.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            // If click is outside the bezel frame, dismiss.
            if !frame.contains(NSEvent.mouseLocation) {
                Task { @MainActor in self.hide() }
            }
        }
    }

    func hide() {
        orderOut(nil)
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
```

### Pattern 2: BezelView — SwiftUI Clipping Display and Navigation

**What:** A SwiftUI `View` that displays the currently selected clipping, navigation counter, and search field. State is local (`@State`). Services come via `@Environment`.

**When to use:** Set as the `NSHostingView` root view inside `BezelController`. All keyboard navigation is handled either by `keyDown` overrides in the panel or by environment action dispatch.

```swift
// Source: Original Flycut processBezelKeyDown: navigation model, translated to SwiftUI state
import SwiftUI
import SwiftData

struct BezelView: View {
    // Clipping data — @Query auto-refreshes from background SwiftData inserts.
    @Query(sort: \FlycutSchemaV1.Clipping.timestamp, order: .reverse)
    private var clippings: [FlycutSchemaV1.Clipping]

    // Navigation and search state.
    @State private var selectedIndex: Int = 0
    @State private var searchText: String = ""

    // Services from environment (injected when BezelController creates NSHostingView).
    @Environment(PasteService.self) private var pasteService
    @Environment(AppTracker.self) private var appTracker

    private var filteredClippings: [FlycutSchemaV1.Clipping] {
        guard !searchText.isEmpty else { return clippings }
        return clippings.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var currentClipping: FlycutSchemaV1.Clipping? {
        guard !filteredClippings.isEmpty,
              filteredClippings.indices.contains(selectedIndex) else { return nil }
        return filteredClippings[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 8) {
            // Search field — receives key input because canBecomeKey = true on the panel.
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onChange(of: searchText) {
                    selectedIndex = 0   // reset to top on filter change
                }

            // Clipping content display.
            if let clipping = currentClipping {
                ScrollView {
                    Text(String(clipping.content.prefix(2000)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                .frame(maxHeight: .infinity)
            } else {
                Text(clippings.isEmpty ? "No clippings" : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            }

            // Navigation counter: "3 of 47"
            if !filteredClippings.isEmpty {
                Text("\(selectedIndex + 1) of \(filteredClippings.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Expose navigation actions via environment or via key handler in BezelController.
    }

    // MARK: - Navigation (called from BezelController.keyDown)

    func navigateUp() { if selectedIndex > 0 { selectedIndex -= 1 } }
    func navigateDown() { if selectedIndex < filteredClippings.count - 1 { selectedIndex += 1 } }
    func navigateToFirst() { selectedIndex = 0 }
    func navigateToLast() { selectedIndex = max(0, filteredClippings.count - 1) }
    func navigateUpTen() { selectedIndex = max(0, selectedIndex - 10) }
    func navigateDownTen() { selectedIndex = min(filteredClippings.count - 1, selectedIndex + 10) }

    func pasteSelected() async {
        guard let clipping = currentClipping else { return }
        await pasteService.paste(content: clipping.content, into: appTracker.previousApp)
    }
}
```

### Pattern 3: Keyboard Routing in Non-Activating Panel

**What:** The bezel must receive keyboard events even though it does not activate the owning app. Two complementary techniques cover all cases.

**Technique A — Override `keyDown` in NSPanel subclass:**
When the panel is the key window (after `makeKeyAndOrderFront`), `keyDown` fires on the panel itself.

```swift
// In BezelController:
// Source: BezelWindow.m keyDown: / performKeyEquivalent: — direct translation
override func keyDown(with event: NSEvent) {
    let chars = event.charactersIgnoringModifiers ?? ""
    switch event.keyCode {
    case 53: // Escape
        hide()
    case 36, 76: // Return / Enter
        Task { @MainActor in await bezelView.pasteSelected() }
        hide()
    case 125, 124: // Down arrow, Right arrow
        bezelView.navigateDown()
    case 126, 123: // Up arrow, Left arrow
        bezelView.navigateUp()
    case 116: // Page Up
        bezelView.navigateUpTen()
    case 121: // Page Down
        bezelView.navigateDownTen()
    case 115: // Home
        bezelView.navigateToFirst()
    case 119: // End
        bezelView.navigateToLast()
    default:
        // Let the SwiftUI TextField handle printable characters.
        super.keyDown(with: event)
    }
}
```

**Technique B — Local event monitor (fallback for when panel is not key):**
```swift
// In BezelController.show():
localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    self?.handleKey(event)
    return event  // return nil to consume, or event to pass through
}
```

**Critical note on `makeKeyAndOrderFront` vs `orderFront + makeKey`:**
The original Flycut calls `[bezel makeKeyAndOrderFront:self]`. In Swift, this is `panel.makeKeyAndOrderFront(nil)`. For a non-activating panel, this makes the panel key (allowing it to receive `keyDown`) without activating the app. Do NOT call `NSApp.activate()` before showing the bezel — this defeats the non-activating contract and would send the paste to Flycut instead of the target app.

### Pattern 4: Multi-Monitor Centering

**What:** Center the bezel on the screen that contains the mouse cursor at hotkey press time.

**When to use:** Called inside `BezelController.show()` before `makeKeyAndOrderFront`.

```swift
// Source: PITFALLS.md Pitfall 14 + NSWindow+TrueCenter.m conceptual translation
// Note: original Flycut uses [NSScreen mainScreen].visibleFrame — WRONG for multi-monitor.
// Correct approach: screen containing the mouse cursor.
let targetScreen = NSScreen.screens.first(where: {
    $0.frame.contains(NSEvent.mouseLocation)
}) ?? NSScreen.main ?? NSScreen.screens[0]

let sf = targetScreen.visibleFrame
let origin = NSPoint(
    x: sf.midX - frame.width / 2,
    y: sf.midY - frame.height / 2
)
setFrameOrigin(origin)
```

**Why:** The original `AppController.m showBezel` uses `[NSScreen mainScreen]`, which returns the screen with the key window — not the screen with the mouse. On a two-monitor setup where the user is working on monitor B, the bezel appears on monitor A (wrong). The fix is `NSEvent.mouseLocation` with `NSScreen.screens.first(where:)`.

### Pattern 5: Click-Outside Dismiss

**What:** Detect left mouse down events in other apps, check if the click is outside the bezel frame, and if so dismiss.

**When to use:** Registered when the bezel shows, removed when it hides.

```swift
// Source: Common pattern for overlay panels; confirmed by Maccy/Alfred implementations
globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
    guard let self else { return }
    if !frame.contains(NSEvent.mouseLocation) {
        Task { @MainActor in self.hide() }
    }
}
```

**Critical:** `NSEvent.addGlobalMonitorForEvents` does NOT fire for events in the calling application. This is intentional — clicks inside the Flycut bezel are handled by local event handling. The global monitor only fires for clicks in other apps, which is the "click outside" scenario.

### Pattern 6: Wiring BezelController in AppDelegate

**What:** Replace the Phase 2 logging stubs in the `activateBezel` and `activateSearch` hotkey handlers with real show calls.

```swift
// In AppDelegate.applicationDidFinishLaunching — replace existing stubs:
let bezelController = BezelController()   // stored as AppDelegate property

KeyboardShortcuts.onKeyDown(for: .activateBezel) { [weak self] in
    Task { @MainActor in
        guard let self else { return }
        if bezelController.isVisible {
            bezelController.hide()
        } else {
            bezelController.show()
        }
    }
}

KeyboardShortcuts.onKeyDown(for: .activateSearch) { [weak self] in
    Task { @MainActor in
        guard let self else { return }
        // Same bezel, but with search field pre-focused.
        bezelController.showWithSearch()
    }
}
```

### Anti-Patterns to Avoid

- **Setting `.nonactivatingPanel` after NSPanel init:** WindowServer tag is not updated; panel silently becomes activating. Always include in the `init` `styleMask` argument.
- **Calling `NSApp.activate()` or `NSApp.activate(ignoringOtherApps:)` before showing the bezel:** Activates Flycut; focus is pulled away from the target paste app; paste lands in Flycut's process.
- **Using `NSWindow.Level.floating` instead of `screenSaverWindow + 1`:** `.floating` does not appear above fullscreen apps. The original Flycut uses `NSScreenSaverWindowLevel` for this reason.
- **Using `[NSScreen mainScreen]` for bezel centering:** Returns screen with key window, not mouse cursor screen. Wrong monitor on multi-monitor setups.
- **Forgetting to remove the global event monitor on hide:** Leaked monitors keep firing indefinitely, wasting CPU and causing spurious dismiss events.
- **Passing `@Model` Clipping objects to BezelController:** `FlycutSchemaV1.Clipping` is not `Sendable`; use `@Query` inside `BezelView` directly, or pass `PersistentIdentifier` values.
- **Reducing `isReleasedWhenClosed` to `true`:** The BezelController should be reused across show/hide cycles; setting `isReleasedWhenClosed = true` deallocates it on `close()`, causing a crash on the second show.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Search field with clear button | Custom `TextField` + `Button` overlay | SwiftUI `TextField` with `.searchable` or plain `TextField` + binding clear | `TextField` with `searchText.isEmpty` conditional clear button is 3 lines; building magnifying glass + clear from scratch is 50+ lines with no benefit |
| Keyboard event routing to non-activating panel | CGEventTap for key events | Override `keyDown(with:)` in NSPanel subclass | `canBecomeKey = true` + `makeKeyAndOrderFront` gives the panel key window status without activating the app; `keyDown` fires naturally; CGEventTap is heavier and requires broader permissions |
| Click-outside detection | NSTrackingArea with global coverage | `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` | Global event monitor is the documented API for receiving events from other processes |
| Multi-monitor screen selection | Comparing NSWindow frames | `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })` | One line; correct on all macOS configurations including Sidecar and AirPlay displays |
| Clipping text truncation | Manual `.prefix()` + "..." append | SwiftUI `Text(clipping.content).lineLimit(N)` | SwiftUI handles truncation with `.lineLimit` and `.truncationMode`; no manual string slicing needed for display |
| Filtered clippings | Separate `@Query` with predicate | `clippings.filter { $0.content.localizedCaseInsensitiveContains(searchText) }` in-memory | `@Query` predicates cannot use dynamic runtime strings with `localizedCaseInsensitiveContains`; in-memory filter on the display-limited array (max `displayNum`) is instant |

**Key insight:** The original Flycut's `BezelWindow` is ~470 lines of AppKit drawing code (`RoundRecTextField`, `RoundRecBezierPath`, manual layout) that can be replaced by ~50 lines of SwiftUI inside an NSPanel. The navigation model from `processBezelKeyDown:` maps cleanly to `@State var selectedIndex` mutations.

---

## Common Pitfalls

### Pitfall 1: Non-Activating Panel Activates the App

**What goes wrong:** The bezel appears but Flycut becomes the frontmost app. The user cannot paste because `PasteService` calls `previousApp.activate()` and then fires Cmd-V, but `previousApp` is now Flycut itself.

**Why it happens:** `.nonactivatingPanel` was not in the initial `styleMask` argument; or `NSApp.activate()` was called before showing the panel; or `canBecomeMain` returns `true`.

**How to avoid:** Include `.nonactivatingPanel` in `init`. Set `canBecomeMain` to `false`. Do NOT call any `NSApp.activate` variant on the show path. Verify by opening TextEdit, triggering the hotkey — Flycut's menu bar icon should NOT be highlighted (not frontmost).

**Warning signs:** Cmd-V after bezel paste inserts "v" in the user's document instead of pasting, or pastes into the wrong app.

### Pitfall 2: Bezel Does Not Appear Above Fullscreen Apps

**What goes wrong:** The bezel appears on the desktop or Mission Control space but is invisible when the user is in a fullscreen app.

**Why it happens:** Window level is `.floating` (level 3) or `.normal` (level 0). Fullscreen app windows use a higher level.

**How to avoid:** Use `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)`. Also set `collectionBehavior` to include `.fullScreenAuxiliary` — this tells Mission Control to display the window alongside the fullscreen app's space. Both are required.

**Warning signs:** Open Safari in fullscreen, press hotkey — bezel is invisible.

### Pitfall 3: Stage Manager Displaces or Obscures the Bezel

**What goes wrong:** On macOS 13+ with Stage Manager enabled, the bezel window is treated as an application window and pushed to the side when switching apps.

**Why it happens:** Stage Manager organizes windows by application. A panel without the right collection behavior is treated as part of the app's window group.

**How to avoid:** Set `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`. The `.transient` flag signals to Stage Manager that this is a temporary overlay, not a persistent document window. This is the underdocumented concern from STATE.md — test early.

**Warning signs:** On macOS 15 with Stage Manager enabled, the bezel appears in the Stage Manager sidebar instead of floating over the current app.

### Pitfall 4: Global Event Monitor Leaks

**What goes wrong:** The bezel dismisses correctly on Escape, but after 10 show/hide cycles the app starts consuming excessive CPU. The mouse click listener fires on every click in every app continuously.

**Why it happens:** `globalMonitor` is a stored `Any?` that is registered in `show()` but never removed in `hide()`. Each `show()` call stacks a new monitor.

**How to avoid:** Always call `NSEvent.removeMonitor(globalMonitor)` in `hide()` and set `globalMonitor = nil`. Add an `assert(globalMonitor == nil)` guard at the top of `show()` during development.

**Warning signs:** Memory usage increases monotonically as the user uses the hotkey.

### Pitfall 5: `@Query` Predicate Cannot Use Dynamic Search String

**What goes wrong:** Developer tries to use `@Query(filter: #Predicate { $0.content.localizedCaseInsensitiveContains(searchText) })` and gets a compile error: `"Unsupported predicate"` or `"Expression is not supported in filter predicates"`.

**Why it happens:** SwiftData `#Predicate` macros require compile-time-constant operations for filter expressions. `localizedCaseInsensitiveContains` is not a supported predicate operation in SwiftData.

**How to avoid:** Use `@Query` without a predicate to fetch all (limited to `displayNum`), then apply `.filter` in-memory: `clippings.filter { $0.content.localizedCaseInsensitiveContains(searchText) }`. With a display limit of 99 clippings, this is instantaneous.

**Warning signs:** Build error on any `@Query` with `.localizedCaseInsensitiveContains` in the predicate.

### Pitfall 6: Bezel Centering Uses Wrong Screen (Multi-Monitor)

**What goes wrong:** On a two-monitor setup, the bezel always appears on the primary monitor regardless of which monitor the user is working on.

**Why it happens:** Original Flycut uses `[NSScreen mainScreen]`, which returns the screen containing the key window or menu bar — not the mouse cursor screen. The Swift rewrite must NOT replicate this bug.

**How to avoid:** Always use `NSEvent.mouseLocation` with `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })`. Fall back to `NSScreen.main` if no screen matches (rare edge case during monitor sleep).

**Warning signs:** User reports "bezel appears on wrong monitor."

### Pitfall 7: NSPanel Not Reused Causes Crash on Second Show

**What goes wrong:** Second press of the hotkey crashes with `EXC_BAD_ACCESS` or `Unexpectedly found nil`.

**Why it happens:** `isReleasedWhenClosed = true` (the default for panels) causes the panel to be deallocated when `close()` or `orderOut()` is called. The `AppDelegate` still holds the `bezelController` reference but it points to freed memory.

**How to avoid:** Set `isReleasedWhenClosed = false` during `BezelController.init`. Use `orderOut(nil)` rather than `close()` to hide the panel without triggering its release cycle.

---

## Code Examples

Verified patterns from original Flycut source and Apple developer resources:

### NSPanel Init with Non-Activating Style Mask

```swift
// Source: BezelWindow.h/.m — NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless
// Confirmed by: philz.blog/nspanel-nonactivating-style-mask-flag — must be in init
super.init(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
    styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
```

### Window Level Above Fullscreen Apps

```swift
// Source: BezelWindow.m — [self setLevel:NSScreenSaverWindowLevel]
// Swift equivalent using CGWindowLevelForKey
level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

### Multi-Monitor Centering on Mouse Screen

```swift
// Source: NSWindow+TrueCenter.m conceptual — fixed for multi-monitor
// PITFALLS.md Pitfall 14: use mouseLocation, not mainScreen
let targetScreen = NSScreen.screens.first(where: {
    $0.frame.contains(NSEvent.mouseLocation)
}) ?? NSScreen.main ?? NSScreen.screens[0]

let sf = targetScreen.visibleFrame
setFrameOrigin(NSPoint(
    x: sf.midX - frame.width / 2,
    y: sf.midY - frame.height / 2
))
```

### Click-Outside Global Monitor

```swift
// Source: Common AppKit pattern for non-activating overlay dismissal
// Used by Maccy, Alfred, Raycast — confirmed by Apple developer docs
globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
    guard let self else { return }
    if !frame.contains(NSEvent.mouseLocation) {
        Task { @MainActor in self.hide() }
    }
}
// In hide():
if let monitor = globalMonitor {
    NSEvent.removeMonitor(monitor)
    globalMonitor = nil
}
```

### Key Navigation in NSPanel keyDown

```swift
// Source: AppController.m processBezelKeyDown: — direct translation of key codes
// Key code reference: USB HID Usage tables (consistent across keyboard layouts)
override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:        hide()                              // Escape
    case 36, 76:    Task { @MainActor in await pasteAndHide() }  // Return, Enter
    case 125, 124:  bezelViewRef?.navigateDown()        // Down, Right
    case 126, 123:  bezelViewRef?.navigateUp()          // Up, Left
    case 121:       bezelViewRef?.navigateDownTen()     // Page Down
    case 116:       bezelViewRef?.navigateUpTen()       // Page Up
    case 119:       bezelViewRef?.navigateToLast()      // End
    case 115:       bezelViewRef?.navigateToFirst()     // Home
    default:        super.keyDown(with: event)          // pass to SwiftUI TextField
    }
}
```

### In-Memory Search Filter (not @Query predicate)

```swift
// Source: Apple Developer Forums — confirmed @Query cannot use localizedCaseInsensitiveContains
// Simple in-memory filter is correct approach for bounded display list
private var filteredClippings: [FlycutSchemaV1.Clipping] {
    guard !searchText.isEmpty else { return Array(clippings.prefix(displayNum)) }
    return clippings
        .filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        .prefix(displayNum)
        .map { $0 }
}
```

### NSHostingView with Environment Injection

```swift
// In BezelController.init — inject existing services from AppDelegate
// Must inject before setting as contentView so environment is available on first render
let bezelView = BezelView()
let hostingView = NSHostingView(rootView: bezelView
    .environment(pasteService)
    .environment(appTracker))
contentView = hostingView
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `BezelWindow` with `RoundRecTextField` hand-drawn AppKit views | `NSPanel` + `NSHostingView(rootView: BezelView())` | Swift rewrite | Eliminates ~500 lines of manual drawing; layout handled by SwiftUI |
| `[NSScreen mainScreen].visibleFrame` for centering | `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })` | Known bug fix | Correct monitor on multi-monitor setups |
| `NSWindowStyleMaskNonactivatingPanel` in Obj-C | `.nonactivatingPanel` in Swift NSWindow.StyleMask | Swift naming | Same underlying behavior; Swift name is `.nonactivatingPanel` |
| Separate `SearchWindow` with `NSTableView` | Inline `TextField` + `@State searchText` in `BezelView` | Phase 3 design | Eliminates second window class; simpler state management |
| `NSLog` for debug output | `os.Logger` with privacy: `.private` | Already in Phase 1/2 | Privacy-safe; clipboard content never in logs |
| Carbon `RegisterEventHotKey` | `KeyboardShortcuts.onKeyDown(for:)` | Phase 1 | Already in place; Phase 3 replaces stubs with real handlers |

**Deprecated/outdated (do not use):**
- `NSWindowStyleMaskNonactivatingPanel` set via `setStyleMask:` after init — silently broken
- `[NSScreen mainScreen]` for bezel centering — wrong screen on multi-monitor
- `NSApp.activate(ignoringOtherApps:)` before bezel show — defeats non-activating contract
- `level = .floating` for above-fullscreen visibility — insufficient level

---

## Open Questions

1. **Stage Manager + `.transient` behavior on macOS 15**
   - What we know: `.transient` signals to Stage Manager that a window is ephemeral; combining with `.canJoinAllSpaces` + `.fullScreenAuxiliary` is the recommended combo per developer community
   - What's unclear: Whether macOS 15 Sequoia changed Stage Manager behavior in ways that break this combination (STATE.md blocker: "NSPanel + Stage Manager interaction on macOS 15 is underdocumented")
   - Recommendation: Add `.transient` to `collectionBehavior` from the start; test manually on a macOS 15 machine with Stage Manager enabled as a Wave 0 priority task

2. **SHELL-02 completion status**
   - What we know: Phase 2 already built `MenuBarView` with `@Query`-driven clipping list, per-item delete, and click-to-paste. SHELL-02 requires "menu bar dropdown shows recent clippings with preview text that can be clicked to paste"
   - What's unclear: Whether this is already complete or if Phase 3 planning needs a dedicated plan for SHELL-02 changes
   - Recommendation: Treat SHELL-02 as complete from Phase 2. If the planner disagrees, the task is trivial (verify `displayLen` truncation is applied, which it already is)

3. **Environment injection into BezelView via NSHostingView**
   - What we know: `NSHostingView(rootView: someView.environment(service))` correctly injects environment objects into the SwiftUI hierarchy
   - What's unclear: Whether the `@Query` inside `BezelView` works correctly when the view is hosted in an `NSPanel` (not a SwiftUI `WindowGroup`) and the `ModelContainer` is not injected via a `Scene`
   - Recommendation: The `sharedModelContainer` is the source of truth; inject it explicitly via `.modelContainer(FlycutApp.sharedModelContainer)` on the `BezelView` root, or set it on the `NSHostingView` using the `modelContainer` modifier

---

## Validation Architecture

`nyquist_validation` is enabled in `.planning/config.json`.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest — `FlycutTests` target exists (created in Phase 2) |
| Config file | None — uses Xcode project scheme |
| Quick run command | `xcodebuild test -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS" -only-testing FlycutTests 2>&1 \| xcpretty` |
| Full suite command | `xcodebuild test -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS" 2>&1 \| xcpretty` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BEZL-01 | BezelController init does not activate the app | Unit (build verify) | `xcodebuild build -scheme FlycutSwift` — panel instantiation with correct styleMask | ✅ build |
| BEZL-02 | selectedIndex maps to correct clipping content | Unit | `xcodebuild test -only-testing FlycutTests/BezelViewModelTests/testSelectedIndexMapsToClipping` | ❌ Wave 0 |
| BEZL-03 | Centering logic selects screen containing mouse | Unit | `xcodebuild test -only-testing FlycutTests/BezelControllerTests/testCenterOnMouseScreen` | ❌ Wave 0 |
| BEZL-04 | collectionBehavior includes canJoinAllSpaces + fullScreenAuxiliary | Unit | `xcodebuild test -only-testing FlycutTests/BezelControllerTests/testCollectionBehavior` | ❌ Wave 0 |
| BEZL-05 | hide() removes global monitor + orders out panel | Unit | `xcodebuild test -only-testing FlycutTests/BezelControllerTests/testHideRemovesMonitor` | ❌ Wave 0 |
| INTR-02 | navigateDown/Up/First/Last/DownTen/UpTen mutate selectedIndex correctly | Unit | `xcodebuild test -only-testing FlycutTests/BezelViewModelTests/testNavigation` | ❌ Wave 0 |
| INTR-04 | filteredClippings returns only matches when searchText non-empty | Unit | `xcodebuild test -only-testing FlycutTests/BezelViewModelTests/testSearchFilter` | ❌ Wave 0 |
| SHELL-02 | MenuBarView shows clippings with truncated preview (already done in Phase 2) | Manual smoke | Open menu bar, verify clipping list with preview text | ✅ exists |

**Manual-only justification:**
- BEZL-01 (non-activation): Requires a window server and human observation — XCTest cannot verify that the owning app was not activated
- BEZL-04 (fullscreen overlay): Requires a fullscreen app and window server to verify visual overlay
- BEZL-05 (click-outside dismiss): Requires simulated click in another process — global event monitors cannot be unit-tested without a real window server

### Sampling Rate

- **Per task commit:** `xcodebuild build -project FlycutSwift.xcodeproj -scheme FlycutSwift -destination "platform=macOS"` (build green)
- **Per wave merge:** Full `xcodebuild test` run — all unit tests pass (Phases 1+2+3)
- **Phase gate:** Full suite green + manual smoke: (1) hotkey shows bezel without activating Flycut, (2) arrow navigation works, (3) Enter pastes and dismisses, (4) Escape dismisses, (5) typing filters, (6) works above a fullscreen app

### Wave 0 Gaps

- [ ] `FlycutTests/BezelControllerTests.swift` — covers BEZL-03 (centering), BEZL-04 (collectionBehavior), BEZL-05 (hide/monitor cleanup)
- [ ] `FlycutTests/BezelViewModelTests.swift` — covers BEZL-02 (selectedIndex), INTR-02 (navigation), INTR-04 (search filter); this tests a pure-Swift view model extracted from `BezelView` if direct `@State` testing is infeasible

---

## Sources

### Primary (HIGH confidence)

- `UI/BezelWindow.m` — original Flycut bezel: window level `NSScreenSaverWindowLevel`, `NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless`, `canBecomeKeyWindow: YES`, `keyDown:` delegation model, `makeKeyAndOrderFront:`
- `AppController.m` — `showBezel` (centering on `mainScreen`), `hideBezel` (`orderOut:`), `processBezelKeyDown:` (key codes: 0x1B=Escape, 0xD=Return, NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey), `collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces`
- `.planning/research/PITFALLS.md` — Pitfall 4 (MenuBarExtra focus theft), Pitfall 14 (bezel centering multi-monitor) — both confirmed by direct codebase analysis
- Apple Developer Documentation — `NSPanel`, `NSWindow.StyleMask.nonactivatingPanel`, `NSEvent.addGlobalMonitorForEvents(matching:handler:)`, `NSScreen.screens`, `NSEvent.mouseLocation`
- `philz.blog/nspanel-nonactivating-style-mask-flag` — confirms the init-only constraint for `.nonactivatingPanel` and the WindowServer tag behavior (MEDIUM confidence — third-party blog, corroborated by Electron bug report)

### Secondary (MEDIUM confidence)

- `cindori.com/developer/floating-panel` — `NSPanel` subclass pattern with `NSHostingView`, `isFloatingPanel = true`, `collectionBehavior.insert(.fullScreenAuxiliary)`, `canBecomeKey = true`
- `markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/` — `.nonactivatingPanel` in init, `NSHostingView` as contentView, `orderFront + makeKey` show pattern
- Apple Developer Forums thread — `canJoinAllSpaces` + `fullScreenAuxiliary` for all-spaces + fullscreen overlay
- WebSearch findings on `.transient` for Stage Manager compatibility

### Tertiary (LOW confidence — validate during implementation)

- Stage Manager + `.transient` collection behavior interaction on macOS 15 — from WebSearch; no official Apple documentation found; recommended to test early

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Apple system frameworks or already-installed SPM libraries; `NSPanel` + `NSHostingView` pattern confirmed by multiple sources
- Architecture: HIGH — direct translation from original Flycut `BezelWindow.m` + `processBezelKeyDown:` into Swift 6; patterns verified against cindori.com and markusbodner.com implementations
- Pitfalls: HIGH — Pitfalls 1-4 confirmed by original source code, PITFALLS.md codebase analysis, and philz.blog investigation; Pitfall 3 (Stage Manager) is MEDIUM — underdocumented for macOS 15

**Research date:** 2026-03-05
**Valid until:** 2026-06-05 (stable Apple APIs; Stage Manager behavior should be re-verified if targeting macOS 16+)
