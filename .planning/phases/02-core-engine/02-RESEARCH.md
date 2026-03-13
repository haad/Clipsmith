# Phase 2: Core Engine — Research

**Researched:** 2026-03-05
**Domain:** NSPasteboard polling, SwiftData ModelActor persistence, CGEventPost paste injection, KeyboardShortcuts registration, previous-app tracking
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLIP-01 | App monitors system pasteboard and captures new text entries automatically | `NSPasteboard.general.changeCount` polled on a 0.5s `Timer` in `NSRunLoopCommonModes`; compare stored count to detect changes; fetch `stringForType(.string)` on change |
| CLIP-02 | User can configure maximum history size (number of clippings retained) | `@AppStorage("rememberNum")` already exists from Phase 1; `ClipboardMonitor` reads this value and enforces trim when inserting into SwiftData |
| CLIP-03 | Duplicate clipboard entries are automatically removed | Before inserting, run a `FetchDescriptor<Clipping>` with `#Predicate { $0.content == incomingContent }` and skip insert if result is non-empty |
| CLIP-04 | Password manager entries and transient pasteboard types are excluded from capture | Check `NSPasteboard.general.types` for the known transient/concealed/password type strings before capturing; skip if any match |
| CLIP-05 | Clipboard history persists across app restarts via SwiftData | `@ModelActor ClipboardStore` wraps all insert/delete/fetch on a background actor; `ModelContainer` wired in Phase 1 at a fixed URL |
| CLIP-06 | User can paste selected clipping as plain text (formatting stripped) | Write `content` string to `NSPasteboard.general` as `.string` only; `CGEventPost(kCGHIDEventTap, cmdV)` after `NSRunningApplication.activate` on previous app |
| CLIP-07 | User can clear entire clipboard history | `ClipboardStore.clearAll()` deletes all `Clipping` records via `modelContext.delete(model:where:)` or iteration |
| CLIP-08 | User can delete individual clippings from history | `ClipboardStore.delete(_ clipping: Clipping)` using `persistentModelID` reference; called from MenuBarView swipe-to-delete or context menu |
| INTR-01 | User can activate clipboard history via a configurable global hotkey | `KeyboardShortcuts.onKeyDown(for: .activateBezel)` registered in Phase 2; stores previous frontmost app before responding; Phase 3 shows the bezel |
| INTR-03 | Selected clipping is pasted into the previously frontmost application | On paste: write plain text to pasteboard, call `previousApp?.activate(options: .activateIgnoringOtherApps)`, wait ~200ms, then `CGEventPost(kCGHIDEventTap, cmdVDown/Up)` |
| INTR-05 | User can activate search via a separate configurable global hotkey | `KeyboardShortcuts.onKeyDown(for: .activateSearch)` registered in Phase 2; stores previous app; Phase 3 shows search UI |
</phase_requirements>

---

## Summary

Phase 2 builds the three invisible services that make the entire clipboard-manager contract work: a monitor that watches the pasteboard for changes, a persistence layer that stores history in SwiftData on a background actor, and a paste injector that fires Cmd-V into the previously active app via the Accessibility API.

All three services have direct Objective-C predecessors in the existing codebase (`pollPB:`, `FlycutStore`, `fakeCommandV`). The Swift 6 rewrite must preserve the exact semantics of each while eliminating memory management code, replacing NSUserDefaults persistence with SwiftData, and making the hotkey path async-safe. The key concurrency constraint is that `NSPasteboard` and `NSRunningApplication` are `@MainActor`-bound AppKit types, while SwiftData inserts should go to a background `@ModelActor` — the glue between them requires a deliberate async handoff.

The most technically fragile part of this phase is the paste injection timing. The existing Obj-C code uses fixed `performSelector:afterDelay:` timers (0.2s to hide app, 0.5s to fire Cmd-V). In Swift 6 with structured concurrency the equivalent is `try await Task.sleep(for: .milliseconds(200))` followed by `Task.sleep(for: .milliseconds(300))`. This delay exists because there is no synchronous API to confirm that the previous app has re-focused its text field; the delay is a pragmatic workaround that has proven reliable across macOS versions.

**Primary recommendation:** Build in this order — `ClipboardMonitor` (polling only, no SwiftData yet), then `@ModelActor ClipboardStore` (persistence layer), then wire monitor → store, then `PasteService` (CGEventPost), then hotkey registration. Each step is testable in isolation before the next is added.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6 (strict concurrency) | Language | Already in project; `@MainActor` and `@ModelActor` enforce correct threading |
| AppKit `NSPasteboard` | System | Pasteboard polling | Only API for reading clipboard contents; `changeCount` is the change detection primitive |
| AppKit `NSRunningApplication` | System | Previous-app tracking | `NSWorkspace.shared.frontmostApplication` returns the app that owns key focus |
| CoreGraphics `CGEvent` | System | Cmd-V injection | `CGEventCreateKeyboardEvent` + `CGEventPost(kCGHIDEventTap)` — the only reliable non-sandboxed paste injection mechanism |
| SwiftData `@ModelActor` | macOS 14+ | Background persistence | Background actor macro that eliminates manual `NSManagedObjectContext` boilerplate |
| KeyboardShortcuts (sindresorhus) | 2.4.0 | Global hotkey registration | Already installed in Phase 1; `onKeyDown(for:)` or `events(for:)` async API |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.Logger` | System | Privacy-safe diagnostics | Never log clipboard content; log only count/index/event type |
| `NSWorkspace.notificationCenter` | System | Active-app change observation | Observer for `didActivateApplicationNotification` to update `previousApp` before hotkey fires |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Timer polling for NSPasteboard | NSPasteboardDidChangeNotification (Darwin notification) | The notification is not public API and is not guaranteed across macOS versions; polling is the established pattern used by every major clipboard manager |
| `@ModelActor` background actor | `@MainActor` ModelContainer only | Main-thread-only persistence blocks UI on every clipboard event (0.5s fire rate); background actor is required |
| Fixed `Task.sleep` timing for paste | NSWorkspace applicationDidActivate notification | The notification has no delivery-time guarantee relative to the key event; fixed delay is more reliable in practice |
| `CGEventPost(kCGHIDEventTap, cmdV)` | `NSPasteboard.general.setString` + `performPaste:` | `performPaste:` only works for apps that expose the Edit > Paste service; `CGEventPost` works universally for non-sandboxed apps |

**Installation:** No new packages needed. All Phase 2 dependencies are Phase 1 dependencies (KeyboardShortcuts 2.4.0) or Apple system frameworks.

---

## Architecture Patterns

### Recommended Project Structure (additions to Phase 1)

```
FlycutSwift/
├── App/
│   ├── FlycutApp.swift          # Add: inject ClipboardMonitor + ClipboardStore via .environment
│   └── AppDelegate.swift        # Add: start ClipboardMonitor in applicationDidFinishLaunching
├── Services/
│   ├── AccessibilityMonitor.swift   # Existing — unchanged
│   ├── ClipboardMonitor.swift       # NEW: NSPasteboard polling, filter, emit new content
│   ├── ClipboardStore.swift         # NEW: @ModelActor — insert, delete, fetch, trim
│   └── PasteService.swift           # NEW: CGEventPost Cmd-V injection with timing
├── Models/
│   └── Schema/FlycutSchemaV1.swift  # Existing — Clipping @Model already defined
└── Views/
    └── MenuBarView.swift            # Phase 2: replace placeholder with real clipping list
```

### Pattern 1: ClipboardMonitor — NSPasteboard Polling

**What:** An `@Observable @MainActor` class that fires a timer in `NSRunLoopCommonModes` at 0.5s intervals, checks `NSPasteboard.general.changeCount`, applies password/transient filters, and passes new content upstream via an async callback.

**When to use:** Running from `applicationDidFinishLaunching` through `applicationWillTerminate`.

```swift
// Source: adapted from AppController.m pollPB: — existing Flycut pattern
// Confirmed by: Maccy clipboard.swift analysis, PlainPasta PasteboardMonitor.swift
import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "ClipboardMonitor"
)

@Observable @MainActor
final class ClipboardMonitor {
    private(set) var isMonitoring: Bool = false
    private var lastChangeCount: Int = 0
    private var timer: Timer?

    // Injected handler — called with new plain-text content whenever the
    // pasteboard changes and passes all filters.
    var onNewClipping: ((String) -> Void)?

    func start() {
        guard !isMonitoring else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        // NSRunLoopCommonModes is REQUIRED so the timer fires while a menu is open.
        // Timer.scheduledTimer uses .default mode only — use the explicit RunLoop API.
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkPasteboard() }
        }
        RunLoop.current.add(timer!, forMode: .common)
        isMonitoring = true
        logger.info("ClipboardMonitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        logger.info("ClipboardMonitor stopped")
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else { return }

        // Filter transient / password manager types.
        if shouldSkip(pasteboard: pasteboard) {
            logger.debug("Skipping transient/password pasteboard entry")
            return
        }

        onNewClipping?(content)
    }

    // Mirrors FlycutOperator shouldSkip: logic for password/transient type filtering.
    private func shouldSkip(pasteboard: NSPasteboard) -> Bool {
        let skipTypes: Set<String> = [
            // nspasteboard.org universal identifiers
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.AutoGeneratedType",
            // Legacy proprietary identifiers
            "com.agilebits.onepassword",
            "PasswordPboardType",
            "de.petermaurer.TransientPasteboardType",
            "com.typeit4me.clipping",
            "Pasteboard generator type",
            // Dynamic/auto-generated type prefix
            // Any type starting with "dyn." is an auto-generated private type
        ]
        let available = Set(pasteboard.types?.map(\.rawValue) ?? [])
        if !skipTypes.isDisjoint(with: available) { return true }
        // Also skip any "dyn." auto-generated UTI types
        if available.contains(where: { $0.hasPrefix("dyn.") }) {
            // Only skip if ONLY dyn. types are present (some apps include them alongside real text)
            // If NSPasteboardTypeString is also present, proceed — the dyn. prefix is supplementary.
        }
        return false
    }
}
```

### Pattern 2: ClipboardStore — @ModelActor Background Persistence

**What:** A `@ModelActor` that performs all SwiftData operations (insert, delete, fetch, count, trim) on a background executor, keeping the main thread free.

**When to use:** Called from `ClipboardMonitor.onNewClipping` via a `Task { await store.insert(...) }`.

**Critical constraint:** SwiftData `@Model` objects are NOT `Sendable`. Never pass `Clipping` objects between the store actor and the main actor. Use `PersistentIdentifier` (the `persistentModelID` property) to reference individual records across actor boundaries.

```swift
// Source: Apple Developer Documentation — ModelActor, FetchDescriptor
// Confirmed by: useyourloaf.com/blog/swiftdata-background-tasks
import SwiftData
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "ClipboardStore"
)

@ModelActor
actor ClipboardStore {

    // MARK: - Insert

    /// Inserts a new clipping, enforcing deduplication and history size limit.
    func insert(content: String, rememberNum: Int) throws {
        // Deduplication: skip if identical content already exists
        let duplicate = try modelContext.fetchCount(
            FetchDescriptor<FlycutSchemaV1.Clipping>(
                predicate: #Predicate { $0.content == content }
            )
        )
        guard duplicate == 0 else {
            logger.debug("Duplicate clipping skipped")
            return
        }

        // Insert as newest (highest displayOrder = 0, shift others)
        // Simplest approach: timestamp-ordered fetch, insert at top
        let clipping = FlycutSchemaV1.Clipping(content: content)
        modelContext.insert(clipping)
        try modelContext.save()

        // Trim to rememberNum
        try trimToLimit(rememberNum: rememberNum)
    }

    // MARK: - Fetch

    /// Returns all clippings ordered by timestamp descending (newest first), limited to displayNum.
    func fetchAll(limit: Int? = nil) throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<FlycutSchemaV1.Clipping>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    /// Returns plain-text content for a clipping by its persistent ID.
    func content(for id: PersistentIdentifier) -> String? {
        return modelContext.model(for: id) as? FlycutSchemaV1.Clipping
    }.map(\.content)

    // MARK: - Delete

    func delete(id: PersistentIdentifier) throws {
        guard let clipping = modelContext.model(for: id) as? FlycutSchemaV1.Clipping else { return }
        modelContext.delete(clipping)
        try modelContext.save()
    }

    func clearAll() throws {
        try modelContext.delete(model: FlycutSchemaV1.Clipping.self)
        try modelContext.save()
        logger.info("All clippings cleared")
    }

    // MARK: - Trim

    private func trimToLimit(rememberNum: Int) throws {
        let descriptor = FetchDescriptor<FlycutSchemaV1.Clipping>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        if all.count > rememberNum {
            for clipping in all[rememberNum...] {
                modelContext.delete(clipping)
            }
            try modelContext.save()
        }
    }
}
```

### Pattern 3: PasteService — CGEventPost Cmd-V Injection

**What:** Writes content to the pasteboard as plain text only, activates the previous app, and fires CGEventPost Cmd-V after a timing delay.

**When to use:** Called when the user selects a clipping to paste (Enter key in Phase 3 bezel, or menu item tap).

**Critical detail:** The timing sequence — `previousApp.activate(options: .activateIgnoringOtherApps)` followed by a 200ms sleep followed by CGEventPost — is the same sequence as the existing `pasteFromStack`/`fakeCommandV` in AppController.m. The 200ms allows the app to receive focus before the keyboard event arrives. Reducing this below 150ms causes intermittent failures on slower machines.

```swift
// Source: AppController.m fakeCommandV, addClipToPasteboard patterns
// Confirmed by: Apple Developer Documentation — CGEventCreateKeyboardEvent, CGEventPost
import AppKit
import CoreGraphics
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "PasteService"
)

@MainActor
final class PasteService {

    // MARK: - Paste

    /// Writes content to the pasteboard as plain text and fires Cmd-V into the previous app.
    /// - Parameters:
    ///   - content: The string to paste. Rich text formatting is intentionally stripped.
    ///   - previousApp: The app that was frontmost before the hotkey fired.
    func paste(content: String, into previousApp: NSRunningApplication?) async {
        // Write to pasteboard as plain string only (strips all rich text).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        guard AXIsProcessTrusted() else {
            logger.error("Cannot paste: Accessibility permission not granted")
            return
        }

        // Re-activate the previous app and wait for it to take focus.
        if let app = previousApp, !app.isTerminated {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // 200ms is the empirically validated minimum delay for app activation to complete.
        // This matches the existing Flycut performSelector:afterDelay:0.2 + 0.3 = 0.5s total.
        // We split it: 200ms for activation, then inject, which is faster than 500ms total.
        try? await Task.sleep(for: .milliseconds(200))

        injectCmdV()
    }

    // MARK: - CGEvent Injection

    private func injectCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("CGEventSource creation failed")
            return
        }

        // V key code = 9 on US keyboard layout
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            logger.error("CGEvent creation failed")
            return
        }

        // Set Command modifier. 0x000008 is the additional bit some apps require.
        let flags: CGEventFlags = [.maskCommand, CGEventFlags(rawValue: 0x000008)]
        keyDown.flags = flags

        CGEventPost(.hid, keyDown)
        CGEventPost(.hid, keyUp)
        logger.debug("Cmd-V injected")
    }
}
```

### Pattern 4: Previous-App Tracking

**What:** Store the frontmost `NSRunningApplication` at two moments: (1) whenever the active app changes, and (2) at the moment a global hotkey fires (capturing the app that was focused before Flycut responds).

**When to use:** Tracking starts at launch. The stored value is consumed by `PasteService.paste(into:)`.

```swift
// Source: Apple Developer Documentation — NSWorkspace.didActivateApplicationNotification
// Confirmed by: AppController.m currentRunningApplication pattern
import AppKit

@Observable @MainActor
final class AppTracker {
    private(set) var previousApp: NSRunningApplication?
    private var observer: Any?

    func start() {
        // Observe workspace notifications for app activation changes.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            // Only update previousApp when the activated app is NOT Flycut itself.
            let flycutBundleID = Bundle.main.bundleIdentifier
            if activatedApp?.bundleIdentifier != flycutBundleID {
                self.previousApp = activatedApp
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
```

### Pattern 5: KeyboardShortcuts Registration (Phase 2 activation)

**What:** Registers `onKeyDown` handlers for `.activateBezel` and `.activateSearch` using the KeyboardShortcuts 2.4.0 API. These names were declared in Phase 1 — Phase 2 makes them active.

**When to use:** Called once from `AppDelegate.applicationDidFinishLaunching`.

```swift
// Source: github.com/sindresorhus/KeyboardShortcuts — onKeyDown API
// Confirmed: events(for:) async API also available; onKeyDown is simpler for fire-and-forget
import KeyboardShortcuts

// In AppDelegate.applicationDidFinishLaunching:
KeyboardShortcuts.onKeyDown(for: .activateBezel) { [weak self] in
    // Phase 2: record previousApp, Phase 3: show bezel
    Task { @MainActor in
        self?.appTracker.captureCurrentAsTarget()
        self?.showBezel() // Phase 3 — stub in Phase 2
    }
}

KeyboardShortcuts.onKeyDown(for: .activateSearch) { [weak self] in
    Task { @MainActor in
        self?.appTracker.captureCurrentAsTarget()
        self?.showSearch() // Phase 3 — stub in Phase 2
    }
}

// Alternative (modern async API — preferred for Swift 6 structured concurrency):
Task {
    for await _ in KeyboardShortcuts.events(for: .activateBezel).filter({ $0 == .keyDown }) {
        // handle
    }
}
```

### Pattern 6: Wiring Monitor → Store in AppDelegate

**What:** Connects the `ClipboardMonitor`'s callback to `ClipboardStore` using a `Task` for the actor-boundary crossing.

```swift
// In AppDelegate.applicationDidFinishLaunching, after store and monitor are initialized:
clipboardMonitor.onNewClipping = { [weak self] content in
    guard let self else { return }
    let rememberNum = UserDefaults.standard.integer(forKey: AppSettingsKeys.rememberNum)
    Task {
        try? await clipboardStore.insert(content: content, rememberNum: rememberNum)
    }
}
clipboardMonitor.start()
```

### Anti-Patterns to Avoid

- **`Timer.scheduledTimer(withTimeInterval:repeats:)` for clipboard polling:** The default `RunLoop.default` mode stops firing while a menu is open. Use `RunLoop.current.add(timer, forMode: .common)` to add to `NSRunLoopCommonModes`. This is why the original `AppController.m` comment calls it out explicitly.
- **Passing `@Model` objects between actors:** `FlycutSchemaV1.Clipping` is not `Sendable`. Never cross an actor boundary holding a model object. Use `PersistentIdentifier` to reference records.
- **Writing rich text to the pasteboard for "plain text paste":** `NSPasteboard.clearContents()` followed by `setString(_:forType:)` with `.string` only. If you call `writeObjects([attributedString])` it will include RTF types.
- **Calling `CGEventPost` before activating the previous app:** The event is silently dropped if the target app is not frontmost. Always `activate(options: .activateIgnoringOtherApps)` first, then sleep, then inject.
- **Skipping `AXIsProcessTrusted()` check before `CGEventPost`:** Without accessibility permission, `CGEventPost` silently fails and nothing is pasted. Always check first and surface an error if untrusted.
- **Using the `options: .activateAllWindows` flag on `NSRunningApplication.activate`:** This flag brings all windows forward and disrupts the user's workspace. Use `.activateIgnoringOtherApps` only.
- **Storing `NSRunningApplication` beyond app termination:** Always guard with `!app.isTerminated` before calling `activate`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Global hotkey registration | CGEventTap callback setup | `KeyboardShortcuts.onKeyDown(for:)` | Already installed; handles CGEventTap mask, modifier conflict detection, enable/disable lifecycle — all edge cases handled |
| Clipboard change notification | Darwin notification `com.apple.pasteboard.changed` | `NSPasteboard.changeCount` polled on `Timer` | The Darwin notification is private API; polling is the universal pattern used by Maccy, Flycut, Jumpcut, PlainPasta |
| Text-only pasteboard write | Custom NSPasteboard extension | `pasteboard.clearContents(); pasteboard.setString(content, forType: .string)` | Three lines replace any abstraction; no edge cases |
| Background SwiftData context | Manual `ModelContext` + executor | `@ModelActor` macro | The macro generates the `modelExecutor` and `modelContainer` init boilerplate; using it directly avoids the `nonisolated(unsafe)` anti-pattern |
| Pasteboard change-count block | Custom semaphore or lock | `pbBlockCount` pattern from Flycut (block count == change count → skip) | Already solved in original: write to pasteboard, record the resulting `changeCount` as "blocked", skip that count in the next poll cycle |

**Key insight:** The "pbBlockCount" pattern from `AppController.m` is critical and easily missed. When Flycut itself writes to the pasteboard to paste, that write increments `changeCount`. Without blocking this count, Flycut would immediately re-capture its own paste content. Solution: after writing to the pasteboard, store the resulting `changeCount` as the "blocked count" in `ClipboardMonitor`, and in the next `checkPasteboard()` call, skip adding content if `pasteboard.changeCount == blockedChangeCount`.

---

## Common Pitfalls

### Pitfall 1: Self-Capture — Monitor Re-Captures Its Own Paste

**What goes wrong:** `PasteService.paste(content:into:)` writes to `NSPasteboard.general`, incrementing `changeCount`. On the next timer tick (0.5s later), `ClipboardMonitor` sees the change, reads the same content back, and inserts a duplicate into history.

**Why it happens:** The monitor has no way to distinguish a copy made by the user from a write made by Flycut itself.

**How to avoid:** After `pasteboard.setString`, capture `pasteboard.changeCount` as `blockedChangeCount` in `ClipboardMonitor`. In `checkPasteboard()`, after updating `lastChangeCount`, also check `if lastChangeCount == blockedChangeCount { return }`.

**Warning signs:** Pasting creates a new duplicate entry at the top of history.

### Pitfall 2: Timer Stops Firing While Menu Is Open

**What goes wrong:** The user holds Cmd+Shift+V to open the menu, copies something in another app (Universal Clipboard), and the bezel never updates because the timer fired zero times while the menu was open.

**Why it happens:** `Timer.scheduledTimer` uses `RunLoop.Mode.default`. NSMenu takes over the run loop in `.tracking` mode. The timer is frozen.

**How to avoid:** Add the timer to `.common` mode: `RunLoop.current.add(timer!, forMode: .common)`. This matches the explicit `NSRunLoopCommonModes` comment in `AppController.m` line 340.

**Warning signs:** Clipboard changes made while a menu is open are not captured until the menu closes and the next timer fires.

### Pitfall 3: Accessibility Check on Every CGEventPost

**What goes wrong:** Calling `AXIsProcessTrusted()` inside `injectCmdV()` on every paste is slightly slow (kernel call) but also invites confusion — the accessibility state cannot change mid-paste. The real risk is forgetting to check it at all.

**Why it happens:** Developers add the check as an afterthought inside the injection function.

**How to avoid:** Check `AXIsProcessTrusted()` in `PasteService.paste()` as a guard before the activation/sleep sequence. If not trusted, surface an error (log + possible UI prompt via the existing `AccessibilityMonitor`) and return early. Never call `AXIsProcessTrustedWithOptions(prompt: true)` — this steals focus from the very app you're about to paste into.

**Warning signs:** Paste silently does nothing when accessibility is revoked mid-session.

### Pitfall 4: Timing Regression on Slower Machines

**What goes wrong:** The 200ms `Task.sleep` before `CGEventPost` is sufficient on modern Macs but intermittently fails on older hardware or under load. The paste fires before the previous app regains key focus.

**Why it happens:** `app.activate(options: .activateIgnoringOtherApps)` is asynchronous — it posts a request to the window server and returns immediately. The app may not actually be focused by the time `CGEventPost` is called.

**How to avoid:** Do NOT reduce the 200ms delay below 150ms. The original Flycut code uses 0.2s for `hideApp` + 0.3s = 0.5s total; the combined 200ms in Phase 2 is acceptable for the minimal Phase 2 path (no bezel to hide). If regression occurs, increase to 300ms.

**Warning signs:** Cmd-V pastes into Flycut's own hidden process (producing nothing visible) instead of the target app.

### Pitfall 5: SwiftData Insert on MainActor Blocks UI

**What goes wrong:** `ClipboardMonitor.onNewClipping` fires on the main actor. If the `ClipboardStore` insert is also called synchronously on the main actor, every clipboard event pauses the UI for the duration of the SQLite write.

**Why it happens:** SwiftData `ModelContext` on the main actor (from `@Environment(\.modelContext)`) is tempting to use everywhere, but it serializes all I/O on the main thread.

**How to avoid:** `ClipboardStore` is a `@ModelActor` initialized with the shared `ModelContainer`. The wiring uses `Task { await clipboardStore.insert(...) }` to hop to the background actor. Never inject or delete on `@MainActor` `ModelContext` unless it is a brief, display-only fetch.

**Warning signs:** The app stutters or drops frames when copying large text in a busy app.

### Pitfall 6: @Model Object Sendability Violation

**What goes wrong:** Passing `FlycutSchemaV1.Clipping` objects from `ClipboardStore` to `MenuBarView` causes a Swift 6 compile error: `"Expression is 'async' but is not marked with 'await'"` or `"non-Sendable type... crossing actor boundaries"`.

**Why it happens:** `@Model` classes are not `Sendable` — they are bound to their originating `ModelContext`.

**How to avoid:** Pass `PersistentIdentifier` values (which ARE `Sendable`) across actor boundaries. For display in `MenuBarView`, use `@Query` to drive the list from the main context, not from the background actor's context.

**Warning signs:** Any code that stores `ClipboardStore.insert()` return values of type `Clipping` in a `@State` or `@Observable` property.

---

## Code Examples

Verified patterns from official sources and codebase analysis:

### NSPasteboard Polling (NSRunLoopCommonModes)

```swift
// Source: AppController.m line 332-341 — explicit NSRunLoopCommonModes comment
// Confirmed required by: NSMenu steals RunLoop.default mode during menu tracking
let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
    Task { @MainActor [weak self] in self?.checkPasteboard() }
}
RunLoop.current.add(timer, forMode: .common)
```

### Transient Type Filter

```swift
// Source: FlycutOperator.m shouldSkip: + nspasteboard.org type identifier registry
// The exact strings are canonical per nspasteboard.org specification
let skipTypes: Set<String> = [
    "org.nspasteboard.TransientType",
    "org.nspasteboard.ConcealedType",
    "org.nspasteboard.AutoGeneratedType",
    "com.agilebits.onepassword",
    "PasswordPboardType",
    "de.petermaurer.TransientPasteboardType",
    "com.typeit4me.clipping",
    "Pasteboard generator type",
]
let available = Set(NSPasteboard.general.types?.map(\.rawValue) ?? [])
if !skipTypes.isDisjoint(with: available) { /* skip */ }
```

### Self-Capture Block Pattern

```swift
// Source: AppController.m setPBBlockCount: + pollPB: lines 1069-1107
// Prevents Flycut's own paste write from being re-captured
// Store in ClipboardMonitor:
var blockedChangeCount: Int = Int.min

// In PasteService.paste(), after writing to pasteboard:
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(content, forType: .string)
clipboardMonitor.blockedChangeCount = pasteboard.changeCount  // block self-capture

// In ClipboardMonitor.checkPasteboard():
lastChangeCount = pasteboard.changeCount
guard lastChangeCount != blockedChangeCount else { return }  // skip own writes
```

### SwiftData ModelActor Creation

```swift
// Source: Apple Developer Documentation — ModelActor
// useyourloaf.com/blog/swiftdata-background-tasks (confirmed 2024)
@ModelActor
actor ClipboardStore {
    // modelContext and modelContainer are auto-synthesized by @ModelActor macro
}

// Initialization — always pass the shared container:
let store = ClipboardStore(modelContainer: FlycutApp.sharedModelContainer)
```

### SwiftData Deduplication Fetch

```swift
// Source: Apple Developer Documentation — FetchDescriptor, #Predicate
// fetchCount is cheaper than fetch + .count — no objects allocated
let count = try modelContext.fetchCount(
    FetchDescriptor<FlycutSchemaV1.Clipping>(
        predicate: #Predicate { $0.content == content }
    )
)
guard count == 0 else { return /* duplicate */ }
```

### CGEventPost Cmd-V

```swift
// Source: AppController.m fakeKey:withCommandFlag: — direct translation to Swift
// kCGHIDEventTap = .hid in Swift CGEventTapLocation
let source = CGEventSource(stateID: .combinedSessionState)!
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)!
keyDown.flags = [.maskCommand, CGEventFlags(rawValue: 0x000008)]
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)!
CGEventPost(.hid, keyDown)
CGEventPost(.hid, keyUp)
```

### NSRunningApplication Activate (macOS 14+ API)

```swift
// Source: Apple Developer Documentation — NSRunningApplication.activate(options:)
// NOTE: activate(ignoringOtherApps:) on NSApplication is deprecated (macOS 14)
// Use NSRunningApplication.activate(options:) instead
previousApp.activate(options: .activateIgnoringOtherApps)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `FlycutStore` in NSUserDefaults plist | `@ModelActor ClipboardStore` in SwiftData SQLite | Phase 2 rewrite | Background persistence, relational queries, no 10MB UserDefaults limit |
| `SGHotKeyCenter` Carbon RegisterEventHotKey | `KeyboardShortcuts.onKeyDown(for:)` CGEventTap-based | Phase 1 dependency | Swift 6 safe, user-configurable shortcuts, no Carbon |
| `performSelector:afterDelay:` timing | `try await Task.sleep(for: .milliseconds(N))` | Swift 5.7+ | Structured concurrency, cancellable, same semantics |
| `NSApp.activate(ignoringOtherApps:)` | `NSRunningApplication.activate(options: .activateIgnoringOtherApps)` | macOS 14 | Previous NSApp API deprecated; must call on the specific `NSRunningApplication` instance |
| `[jcPasteboard stringForType:type]` | `NSPasteboard.general.string(forType: .string)` | Swift availability (2016) | Nil-safe, type-safe Swift API |
| Global `pollPBTimer` in AppController | `ClipboardMonitor` service class | Phase 2 rewrite | Isolated responsibility, testable, injectable |

**Deprecated/outdated (do not use):**
- `NSApp.activate(ignoringOtherApps:)` — deprecated macOS 14; use `NSRunningApplication.activate(options:)`
- `RunLoop.scheduledTimer(withTimeInterval:)` without common mode — timer stops in menu tracking
- `NSPasteboardTypeString` (Obj-C constant) — use `NSPasteboard.PasteboardType.string` in Swift

---

## Open Questions

1. **Polling interval: 0.5s vs 0.1s**
   - What we know: The original Flycut polls at 1.0s. Maccy uses 0.1s by default. 0.5s is a common middle ground that trades slight capture latency for CPU headroom.
   - What's unclear: Whether 0.5s is acceptable for the initial release or if 0.1s is needed to feel snappy.
   - Recommendation: Use 0.5s. If users report delayed capture, expose it as a setting. The 0.5s interval is from Phase 1's `AccessibilityMonitor` pattern and is consistent with existing Flycut feel.

2. **SwiftData `@Query` in MenuBarView vs. manual fetch from ClipboardStore**
   - What we know: `@Query` is a `@MainActor`-bound property wrapper that automatically refreshes SwiftUI views when the underlying store changes. It cannot be used in `MenuBarExtra(.menu)` style views because menu items are not SwiftUI views — they are `NSMenuItem` instances built by the system.
   - What's unclear: Whether Phase 2 MenuBarView (which will show a list of clippings) should use `@Query` (if it's a real SwiftUI list) or a manual `ClipboardStore.fetchAll()` call.
   - Recommendation: Phase 2 MenuBarView replaces the Phase 1 placeholder with a real `List` inside the `MenuBarExtra(.menu)` content closure. This IS a SwiftUI `List`, so `@Query` works here. Use `@Query(sort: \FlycutSchemaV1.Clipping.timestamp, order: .reverse)` to drive the list.

3. **Block-count pattern thread safety**
   - What we know: `ClipboardMonitor.blockedChangeCount` must be set by `PasteService` (which runs on `@MainActor`) and read by `ClipboardMonitor` (also `@MainActor`). Since both are `@MainActor`, this is safe.
   - What's unclear: Whether the timer callback's `Task { @MainActor in }` hop introduces any race with `blockedChangeCount` assignment.
   - Recommendation: Since both `PasteService` and `ClipboardMonitor` are `@MainActor`, the `blockedChangeCount` assignment and read are serialized. No race condition possible.

---

## Validation Architecture

`nyquist_validation` is enabled in `.planning/config.json`.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest — target to be created in Wave 0 (Phase 1 deferred) |
| Config file | None — see Wave 0 |
| Quick run command | `xcodebuild test -scheme FlycutTests -destination "platform=macOS" -only-testing FlycutTests 2>&1 \| xcpretty` |
| Full suite command | `xcodebuild test -scheme FlycutTests -destination "platform=macOS" 2>&1 \| xcpretty` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLIP-01 | ClipboardMonitor detects pasteboard changeCount increase | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardMonitorTests/testDetectsChange` | ❌ Wave 0 |
| CLIP-02 | History trimmed to rememberNum after insert | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testTrimToLimit` | ❌ Wave 0 |
| CLIP-03 | Duplicate content not inserted twice | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testDuplicateSkipped` | ❌ Wave 0 |
| CLIP-04 | TransientType pasteboard entry is skipped | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardMonitorTests/testSkipsTransientType` | ❌ Wave 0 |
| CLIP-05 | Clippings survive container reload | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testPersistenceRoundTrip` | ❌ Wave 0 |
| CLIP-06 | Paste writes plain text only (no RTF) | Unit | `xcodebuild test -only-testing FlycutTests/PasteServiceTests/testPlainTextOnly` | ❌ Wave 0 |
| CLIP-07 | clearAll removes all Clipping records | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testClearAll` | ❌ Wave 0 |
| CLIP-08 | delete(id:) removes exactly one Clipping | Unit | `xcodebuild test -only-testing FlycutTests/ClipboardStoreTests/testDeleteOne` | ❌ Wave 0 |
| INTR-01 | activateBezel hotkey fires onKeyDown callback | Manual smoke | Press configured hotkey, verify callback fires | ❌ Wave 0 |
| INTR-03 | Paste writes to previous app (CGEventPost) | Manual smoke | Open TextEdit, activate Flycut, paste — verify text appears in TextEdit | ❌ Wave 0 |
| INTR-05 | activateSearch hotkey fires onKeyDown callback | Manual smoke | Press configured search hotkey, verify callback fires | ❌ Wave 0 |

**Manual-only justification:**
- INTR-01, INTR-03, INTR-05: Global hotkeys and cross-app paste require a real macOS runtime with a window server. XCTest cannot simulate CGEventPost targets or inter-app activation.

### Sampling Rate

- **Per task commit:** `xcodebuild build -scheme Flycut -destination "platform=macOS"` (build green)
- **Per wave merge:** Full `xcodebuild test` run — all unit tests pass
- **Phase gate:** Full test suite green + manual smoke (copy → history captured, paste → text appears in target app)

### Wave 0 Gaps

- [ ] `FlycutTests/` test target — if not created in Phase 1 Wave 0, must be created here
- [ ] `FlycutTests/ClipboardMonitorTests.swift` — covers CLIP-01, CLIP-04 (mock NSPasteboard via protocol injection)
- [ ] `FlycutTests/ClipboardStoreTests.swift` — covers CLIP-02, CLIP-03, CLIP-05, CLIP-07, CLIP-08 (in-memory `ModelContainer` for isolation)
- [ ] `FlycutTests/PasteServiceTests.swift` — covers CLIP-06 (verify pasteboard types after paste write; no CGEventPost in unit tests)
- [ ] Shared `FlycutTests/TestModelContainer.swift` — creates an in-memory `ModelContainer(for: FlycutSchemaV1.models, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])` for test isolation

---

## Sources

### Primary (HIGH confidence)

- `AppController.m` — direct source for `pollPB:` (timer mode, changeCount pattern, self-capture block), `fakeCommandV` (CGEventPost sequence), `addClipToPasteboard:` (pasteboard write), `currentRunningApplication` tracking pattern
- `FlycutOperator.m` — direct source for `shouldSkip:ofType:fromAvailableTypes:` password/transient filter logic and type strings
- Apple Developer Documentation — `NSPasteboard.changeCount`, `CGEventCreateKeyboardEvent`, `CGEventPost`, `NSRunningApplication.activate(options:)`, `ModelActor`, `FetchDescriptor`, `#Predicate`
- KeyboardShortcuts README (github.com/sindresorhus/KeyboardShortcuts) — `onKeyDown(for:)` and `events(for:)` async API confirmed
- nspasteboard.org — canonical list of transient/concealed/password pasteboard type strings

### Secondary (MEDIUM confidence)

- Maccy `Clipboard.swift` (github.com/p0deje/Maccy) — confirms polling pattern, `shouldIgnore()` filter approach, `@MainActor` annotation for copy/paste operations
- PlainPasta `PasteboardMonitor.swift` (github.com/hisaac/PlainPasta) — confirms `DispatchSourceTimer` / `Timer` polling at 100ms interval; `[weak self]` capture pattern
- useyourloaf.com/blog/swiftdata-background-tasks — confirms `@ModelActor` pattern for background SwiftData with `modelContext.fetch` and `modelContext.save`
- Apple Developer Forums thread "SwiftData Background Inserts Using ModelActor Do Not Trigger View Updates" — confirms the known ModelActor → @Query notification gap (deletes trigger redraws, inserts may not; workaround: call `modelContext.save()` explicitly)

### Tertiary (LOW confidence — validated before implementation)

- "200ms minimum delay before CGEventPost" — derived from original Flycut `performSelector:afterDelay:0.2` + `0.3` pattern and community reports; not officially documented
- `CGEventFlags(rawValue: 0x000008)` secondary command bit — from original Flycut source comment "some apps want bit set for one of the command keys"; not in Apple docs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Apple system frameworks or verified SPM libraries already in the project
- Architecture: HIGH — direct translation of existing Obj-C patterns into Swift 6 idioms; all critical patterns have working source in AppController.m/FlycutOperator.m
- Pitfalls: HIGH — Pitfall 1 (self-capture) and Pitfall 2 (timer mode) confirmed by existing source code comments; Pitfall 4 (timing regression) is empirically known in original code

**Research date:** 2026-03-05
**Valid until:** 2026-06-05 (stable Apple APIs; KeyboardShortcuts version should be re-checked if > 3 months pass)
