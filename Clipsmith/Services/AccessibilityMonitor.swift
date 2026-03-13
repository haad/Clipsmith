import ApplicationServices
import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "AccessibilityMonitor"
)

@Observable @MainActor
final class AccessibilityMonitor {
    private(set) var isTrusted: Bool = false
    private var timer: Timer?

    /// Start polling accessibility trust status every 5 seconds.
    func start() {
        isTrusted = AXIsProcessTrusted()
        logger.info("AccessibilityMonitor started — trusted: \(self.isTrusted, privacy: .public)")

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isTrusted {
                    logger.info("Accessibility trust changed: \(trusted, privacy: .public)")
                }
                self.isTrusted = trusted
            }
        }
    }

    /// Stop the polling timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        logger.debug("AccessibilityMonitor stopped")
    }

    /// Request accessibility permission via the system prompt.
    /// This adds the app to the Accessibility list automatically — the user
    /// just needs to toggle it on. Only call from explicit user action (button tap).
    func requestPermission() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(opts)
    }
}
