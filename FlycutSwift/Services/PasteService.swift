import AppKit
import CoreGraphics
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "PasteService"
)

/// Writes clipboard content as plain text and injects Cmd-V into the previously active app.
///
/// Plain-text-only design: clearContents() + setString(_:forType: .string) ensures no RTF,
/// HTML, or other rich types are written (CLIP-06). The paste sequence follows the original
/// Flycut AppController.m fakeCommandV + addClipToPasteboard: pattern.
///
/// @Observable is required so the instance can be injected via SwiftUI's .environment(_:) API.
@Observable @MainActor
final class PasteService {

    // MARK: - Dependencies

    /// Set during wiring so PasteService can update blockedChangeCount after writing to the
    /// pasteboard, preventing ClipboardMonitor from re-capturing its own paste output (Pitfall 1).
    var clipboardMonitor: ClipboardMonitor?

    // MARK: - Paste

    /// Writes content to the pasteboard as plain text and fires Cmd-V into the previous app.
    ///
    /// - Parameters:
    ///   - content: The string to paste. Rich text formatting is intentionally stripped.
    ///   - previousApp: The app that was frontmost before the hotkey fired.
    func paste(content: String, into previousApp: NSRunningApplication?) async {
        // 1. Check accessibility permission first — do NOT call AXIsProcessTrustedWithOptions(prompt:true)
        //    because that steals focus from the app we're about to paste into (Pitfall 3).
        guard AXIsProcessTrusted() else {
            logger.error("Cannot paste: Accessibility permission not granted")
            return
        }

        // 2. Write plain text only to the pasteboard (no RTF/HTML — CLIP-06).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        // 3. Block self-capture: record the changeCount from our own write so
        //    ClipboardMonitor skips this cycle and doesn't re-capture our paste content.
        clipboardMonitor?.blockedChangeCount = pasteboard.changeCount

        // 4. Activate the previous app so it receives key focus before we inject Cmd-V.
        // Use activate(from:options:) — the macOS 14+ replacement for the deprecated
        // activateWithOptions(.activateIgnoringOtherApps). We pass NSRunningApplication.current
        // (Flycut) as the "from" app so the system knows we are explicitly delegating focus.
        if let app = previousApp, !app.isTerminated {
            app.activate(from: NSRunningApplication.current, options: [])
        }

        // 5. Wait 500ms for app activation to complete before injecting the key event.
        //    This matches ObjC Flycut timing (0.2s + 0.3s = 500ms total) and ensures reliable
        //    paste on slower hardware (Bug #28). Do NOT reduce — intermittent failures below 500ms.
        try? await Task.sleep(for: .milliseconds(500))

        // 6. Fire Cmd-V via CGEventPost.
        injectCmdV()
    }

    // MARK: - CGEvent Injection

    /// Injects a Cmd-V key down + up event via CGEvent.post(tap: .cgHIDEventTap).
    ///
    /// Source: AppController.m fakeKey:withCommandFlag: — direct Swift translation.
    /// Uses CGEvent.post(tap:) instance method (CGEventPost was obsoleted in Swift 3).
    private func injectCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("CGEventSource creation failed")
            return
        }

        // V key code = 9 on US keyboard layout (virtual key, not character code).
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            logger.error("CGEvent creation failed")
            return
        }

        // Set Command modifier + secondary command bit (0x000008).
        // The secondary bit is required by some apps per original Flycut source comment.
        let flags: CGEventFlags = [.maskCommand, CGEventFlags(rawValue: 0x000008)]
        keyDown.flags = flags

        // CGEventTapLocation.hid / .cgHIDEventTap do not exist as Swift named members.
        // kCGHIDEventTap == 0. Use rawValue initializer which is the correct Swift approach.
        let hidTap = CGEventTapLocation(rawValue: 0)!
        keyDown.post(tap: hidTap)
        keyUp.post(tap: hidTap)
        logger.debug("Cmd-V injected")
    }
}
