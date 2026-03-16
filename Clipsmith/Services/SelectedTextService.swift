import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "SelectedTextService"
)

/// Reads the selected text from the frontmost application.
///
/// Strategy (RESEARCH.md Pattern 2):
/// 1. Try AXUIElement kAXSelectedTextAttribute (non-destructive, fast)
/// 2. If AX returns nil/empty, fall back to Cmd-C (saves/restores clipboard)
/// 3. If still empty, return nil (popup opens with empty search for manual entry)
@MainActor
enum SelectedTextService {

    /// Attempt to read selected text from the given app.
    /// Returns nil if no text could be captured.
    static func selectedText(from app: NSRunningApplication?) -> String? {
        guard let app else { return nil }

        // Strategy 1: AXUIElement (non-destructive)
        if AXIsProcessTrusted() {
            if let text = axSelectedText(from: app), !text.isEmpty {
                logger.debug("Got selected text via AX (\(text.count) chars)")
                return text
            }
        }

        // Strategy 2: Cmd-C fallback
        // Save current clipboard, synthesize Cmd-C, read result, restore clipboard
        let fallbackText = cmdCFallback()
        if let text = fallbackText, !text.isEmpty {
            logger.debug("Got selected text via Cmd-C fallback (\(text.count) chars)")
            return text
        }

        logger.debug("No selected text captured")
        return nil
    }

    // MARK: - AXUIElement

    private static func axSelectedText(from app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focused = focusedRef else { return nil }

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &textRef
        ) == .success else { return nil }

        return textRef as? String
    }

    // MARK: - Cmd-C fallback

    private static func cmdCFallback() -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        let oldContents = pasteboard.string(forType: .string)

        // Synthesize Cmd-C
        let source = CGEventSource(stateID: .combinedSessionState)
        // Key code 8 = 'C' on QWERTY
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Wait briefly for the copy to complete
        Thread.sleep(forTimeInterval: 0.15)

        // Check if clipboard changed
        guard pasteboard.changeCount != oldChangeCount else { return nil }
        let newText = pasteboard.string(forType: .string)

        // Restore original clipboard contents
        if let old = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }

        return newText
    }
}
