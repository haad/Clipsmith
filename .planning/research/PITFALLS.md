# Domain Pitfalls

**Domain:** macOS clipboard manager — Swift/SwiftUI rewrite from Objective-C
**Researched:** 2026-03-05
**Confidence:** HIGH — based on direct analysis of existing Flycut Objective-C codebase, known bugs in CONCERNS.md, and documented macOS API constraints

---

## Critical Pitfalls

Mistakes that cause rewrites, silent data loss, or fundamental user-facing breakage.

---

### Pitfall 1: Paste Injection Timing Is Not Deterministic

**What goes wrong:** After setting NSPasteboard content, synthesizing Cmd-V via `CGEventPost` immediately is too fast. The target application has not yet processed focus restoration, and the paste lands in the wrong app or doesn't fire at all. The existing codebase papers over this with `performSelector:afterDelay:0.3` and `performSelector:afterDelay:0.5` scattered at 5+ call sites — delays that are arbitrary and fragile under load.

**Why it happens:** The sequence is: (1) bezel shows, (2) user selects, (3) bezel hides, (4) previous app regains focus, (5) Cmd-V fires. Steps 3–4 are asynchronous with no API to know when the previous app has finished activating.

**Prevention:**
- Capture `NSWorkspace.shared.frontmostApplication` at hotkey press (before bezel opens)
- After writing to NSPasteboard, call `previousApp.activate()` explicitly
- Post CGEvent after 50ms yield (not arbitrary 300-500ms delays)
- Never use `Task.sleep` as a substitute for explicit sequencing

**Detection:** Any `Task.sleep` or `asyncAfter` with delay > 100ms in the paste flow.

**Phase:** Core Functionality — must be solved from day one.

---

### Pitfall 2: Accessibility Permission State Goes Stale Silently

**What goes wrong:** `AXIsProcessTrustedWithOptions` returns `true` at launch, but becomes `false` if the app binary moves, macOS updates its trust cache, or the code signature changes. Current Flycut checks only at startup.

**Prevention:**
- Check `AXIsProcessTrusted()` before every paste operation (the call is cheap)
- Do NOT pass `kAXTrustedCheckOptionPrompt: true` in the paste path — it steals focus
- Poll permission state with a 5-second timer and reflect status in menu bar icon
- Provide "Re-authorize" button in preferences that opens System Settings directly

**Phase:** Core Functionality — infrastructure.

---

### Pitfall 3: Carbon Hotkey API Is Swift 6-Incompatible

**What goes wrong:** SGHotKeysLib wraps `RegisterEventHotKey` / `InstallEventHandler` — Carbon APIs not annotated for Swift concurrency. Calling them from an actor context produces compilation errors; suppressing with `@preconcurrency` creates real data races.

**Prevention:**
- Use `CGEventTap` or `KeyboardShortcuts` library instead of Carbon
- Drop SGHotKeysLib entirely — do not bridge it
- Dispatch all hotkey callbacks to `@MainActor` explicitly

**Phase:** Core Functionality.

---

### Pitfall 4: MenuBarExtra(.window) Breaks Non-Activating Bezel

**What goes wrong:** `MenuBarExtra` with `.window` style activates the application when shown. The bezel HUD must appear without changing the active application — otherwise paste is sent to Flycut instead of the target app.

**Prevention:**
- Use `MenuBarExtra(.menu)` for the status bar dropdown only
- Build bezel as standalone `NSPanel` with `NSWindowStyleMaskNonactivatingPanel`
- Set `panel.level = .screenSaver + 1` and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`

**Detection:** Open TextEdit, trigger hotkey, type — if characters appear in Flycut, activation policy is broken.

**Phase:** UI/Bezel.

---

### Pitfall 5: SwiftData Not Suitable for Sub-Second Writes Without Architecture

**What goes wrong:** Clipboard monitoring fires every 0.5s. If `ModelContext.save()` is called synchronously on `@MainActor` on every change, the main thread blocks during SQLite I/O. No built-in write coalescing exists.

**Prevention:**
- All SwiftData writes via background `ModelActor`, never on `@MainActor`
- Debounce saves: accumulate in-memory for 2-3 seconds of inactivity, then batch-write
- In-memory buffer is source of truth for UI; persistence is async catch-up
- Store DB at predictable path via `ModelConfiguration(url:)`
- Define `VersionedSchema` from first release

**Phase:** Data/Persistence.

---

### Pitfall 6: pbBlockCount Pattern Reproduces as Race in Swift

**What goes wrong:** The existing `pbBlockCount` prevents re-capturing Flycut's own paste writes. In Swift async/await, if multiple tasks touch the pasteboard concurrently, the block count races — either duplicating pasted items or swallowing legitimate copies.

**Prevention:**
- Implement as a `PasteboardMonitor` with isolated `blockedChangeCount: Int?` property
- Set before paste write, clear after next polling cycle confirms consumption
- Include 1-second timeout to prevent permanently blocking legitimate copies

**Phase:** Core Functionality.

---

## Moderate Pitfalls

### Pitfall 7: NSPasteboard Off Main Thread Is Undefined Behavior

`NSPasteboard` has no `@MainActor` annotation. Reading inside a bare `Task {}` is undefined behavior. All pasteboard access must be `@MainActor` or on `DispatchQueue.main`.

**Phase:** Core Functionality.

### Pitfall 8: Password Denylist Must Be Exact

The existing filter rejects: `PasswordPboardType`, `org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`, `org.nspasteboard.AutoGeneratedType`, `com.agilebits.onepassword`. Omitting even one captures passwords in plaintext history.

**Prevention:** Check `NSPasteboard.general.types` against denylist BEFORE reading content. Unit test with mock pasteboard states.

**Phase:** Core Functionality — security requirement.

### Pitfall 9: SwiftUI Settings Cannot Host Hotkey Recorder Natively

SwiftUI's keyboard event handling filters out modifier-only keypresses. Use `KeyboardShortcuts.Recorder` via `NSViewRepresentable`.

**Phase:** Settings.

### Pitfall 10: MenuBarExtra Menu Rebuilds with Large Histories

`@Query` in `MenuBarExtra(.menu)` body re-evaluates on every SwiftData change. With 1000+ clippings, the menu rebuilds continuously.

**Prevention:** Use `FetchDescriptor` limited to display count (e.g., 20 items). Snapshot array when menu opens.

**Phase:** UI/Menu.

### Pitfall 11: App Activation Policy Conflicts with SwiftUI

`LSUIElement = YES` suppresses dock icon but SwiftUI `WindowGroup` tries to show a window on launch. Use `@NSApplicationDelegateAdaptor` to call `NSApp.setActivationPolicy(.accessory)`. Toggle to allow focus when preferences window opens.

**Phase:** Foundation.

---

## Minor Pitfalls

### Pitfall 12: SwiftData Schema Migrations Not Automatic
Adding/renaming/removing `@Model` properties without `VersionedSchema` + `MigrationPlan` causes silent data loss. Define from v1.0.

### Pitfall 13: `activate(ignoringOtherApps:)` Deprecated on macOS 14+
Use `NSApp.activate()` (no parameter) and `NSRunningApplication.activate(options:)`.

### Pitfall 14: Bezel Centering Fails on Multi-Monitor / Stage Manager
Center on screen containing mouse cursor: `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })`.

### Pitfall 15: Debug Logging Must Never Include Raw Clipboard Content
Use `os.log` with `.private` classification. Never `print()` clipboard content.

---

## Phase-Specific Warning Summary

| Phase | Pitfall | Mitigation |
|-------|---------|------------|
| Foundation | Activation policy | `LSUIElement = YES`, `@NSApplicationDelegateAdaptor`, policy toggle |
| Core | `pbBlockCount` race | `PasteboardMonitor` with isolated blockedChangeCount |
| Core | NSPasteboard threading | All reads `@MainActor` |
| Core | Paste timing | Capture previousApp, explicit activate, 50ms yield |
| Core | Accessibility staleness | Check before every paste, poll separately |
| Core | Carbon API | CGEventTap or KeyboardShortcuts, drop SGHotKeysLib |
| Core | Password filtering | Exact denylist, check types before reading content |
| Bezel | MenuBarExtra focus theft | Standalone NSPanel, MenuBarExtra(.menu) only |
| Bezel | Multi-monitor centering | Mouse cursor screen detection |
| Data | SwiftData write frequency | Background ModelActor, debounce, in-memory buffer |
| Data | Schema migrations | VersionedSchema from v1.0 |
| Settings | Hotkey recorder | KeyboardShortcuts.Recorder via NSViewRepresentable |
| All | Debug logging | os.log .private, no raw clipboard in logs |

---

*Pitfalls research: 2026-03-05*
