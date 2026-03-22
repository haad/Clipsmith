import AppKit
import CoreGraphics
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "PasteService"
)

/// Writes clipboard content as plain text and injects Cmd-V into the previously active app.
///
/// Plain-text-only design: clearContents() + setString(_:forType: .string) ensures no RTF,
/// HTML, or other rich types are written (CLIP-06). The paste sequence follows the original
/// Flycut AppController.m pasteFromStack + fakeCommandV timing pattern.
///
/// @Observable is required so the instance can be injected via SwiftUI's .environment(_:) API.
@Observable @MainActor
final class PasteService {

    // MARK: - Dependencies

    /// Set during wiring so PasteService can update blockedChangeCount after writing to the
    /// pasteboard, preventing ClipboardMonitor from re-capturing its own paste output (Pitfall 1).
    var clipboardMonitor: ClipboardMonitor?

    /// The currently pending FakeKeyHelper, if any. Held so `cancelPendingPaste()` can
    /// cancel the scheduled Cmd-V (e.g. when the user presses Escape after modifier release).
    private var pendingHelper: FakeKeyHelper?

    // MARK: - Paste

    /// Writes content to the pasteboard as plain text and fires Cmd-V into the previous app.
    ///
    /// Timing follows the original Flycut pattern:
    ///   1. Write to pasteboard immediately
    ///   2. Caller hides the bezel at ~0.2s (BezelController.pasteAndHide calls hide())
    ///   3. Cmd-V is injected at ~0.5s via performSelector afterDelay
    ///
    /// The delay between hide and paste is critical — the bezel panel must be fully
    /// dismissed before the synthetic Cmd-V is posted, otherwise the panel (which is
    /// canBecomeKey) can intercept the event.
    ///
    /// - Parameters:
    ///   - content: The string to paste. Rich text formatting is intentionally stripped.
    ///   - previousApp: The app that was frontmost before the hotkey fired.
    func paste(content: String, into previousApp: NSRunningApplication?) {
        // 1. Check accessibility permission first — do NOT call AXIsProcessTrustedWithOptions(prompt:true)
        //    because that steals focus from the app we're about to paste into (Pitfall 3).
        guard AXIsProcessTrusted() else {
            logger.error("Cannot paste: Accessibility permission not granted")
            // Copy content to pasteboard so the user can manually Cmd-V.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            clipboardMonitor?.blockedChangeCount = pasteboard.changeCount
            logger.info("Content copied to clipboard — user can paste manually with Cmd-V")
            return
        }

        // 2. Write plain text only to the pasteboard (no RTF/HTML — CLIP-06).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        // 3. Block self-capture: record the changeCount from our own write so
        //    ClipboardMonitor skips this cycle and doesn't re-capture our paste content.
        clipboardMonitor?.blockedChangeCount = pasteboard.changeCount

        // 4. Schedule Cmd-V injection after 0.5s delay (matching original Flycut timing).
        //    Uses performSelector:afterDelay: which schedules on the run loop, exactly
        //    like the original ObjC implementation. This ensures the bezel has been
        //    hidden (at ~0.2s) before the keystroke is posted (at 0.5s).
        let helper = FakeKeyHelper(previousApp: previousApp)
        pendingHelper = helper
        helper.scheduleCommandV()
    }

    /// Cancels any pending Cmd-V injection that hasn't fired yet.
    /// Called when the bezel is dismissed without paste intent (e.g. Escape key).
    func cancelPendingPaste() {
        if let helper = pendingHelper {
            helper.cancelScheduledCommandV()
            pendingHelper = nil
            logger.info("Cancelled pending Cmd-V injection")
        }
    }
}

// MARK: - FakeKeyHelper

/// Bridges to performSelector:afterDelay: for scheduling the synthetic Cmd-V.
///
/// Mirrors the original Flycut AppController.m fakeKey:withCommandFlag: implementation
/// exactly: CGEventSourceStateCombinedSessionState, kCGHIDEventTap, and the 0x000008
/// secondary command bit.
@MainActor
final class FakeKeyHelper: NSObject {

    private let previousApp: NSRunningApplication?

    init(previousApp: NSRunningApplication?) {
        self.previousApp = previousApp
        super.init()
    }

    func scheduleCommandV() {
        // Matches original Flycut: [self performSelector:@selector(fakeCommandV) withObject:nil afterDelay:0.5]
        perform(#selector(fakeCommandV), with: nil, afterDelay: 0.5)
    }

    func cancelScheduledCommandV() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fakeCommandV), object: nil)
    }

    @objc private func fakeCommandV() {
        // Activate the previous app right before injecting the keystroke.
        if let app = previousApp, !app.isTerminated {
            app.activate(from: NSRunningApplication.current, options: [])
        }

        // Direct translation of Flycut AppController.m fakeKey:withCommandFlag:
        guard let sourceRef = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("CGEventSource creation failed")
            return
        }

        // V key code = 9 on US keyboard layout (virtual key, not character code).
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: sourceRef, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: sourceRef, virtualKey: vKeyCode, keyDown: false)
        else {
            logger.error("CGEvent creation failed")
            return
        }

        // Set Command modifier + secondary command bit (0x000008).
        // Some apps want the bit set for one of the command keys — per original Flycut source.
        keyDown.flags = [.maskCommand, CGEventFlags(rawValue: 0x000008)]

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.info("Cmd-V injected")
    }
}
