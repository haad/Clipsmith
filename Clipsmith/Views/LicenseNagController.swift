import AppKit
import SwiftUI

/// Activating NSPanel that hosts the LicenseNagView.
///
/// Design notes:
/// - Uses `.titled | .closable` styleMask — this is an activating dialog that intentionally
///   steals focus (unlike the clipboard bezel which uses .nonactivatingPanel).
/// - `level = .floating` so it appears above regular windows but below system UI.
/// - Activation policy is switched to `.regular` on show, and restored to `.accessory`
///   on windowWillClose — the same pattern used by SettingsView.onDisappear.
@MainActor
final class LicenseNagController: NSObject, NSWindowDelegate {

    // MARK: - Properties

    private let panel: NSPanel

    private let sponsorURL = URL(string: "https://github.com/sponsors/haad")!
    private let purchaseURL = URL(string: "https://store.lemonsqueezy.com/checkout/buy/TODO-product-slug")!

    /// Called when the user taps "I Already Have a License".
    /// AppDelegate sets this to open Settings to the License tab.
    var onOpenSettings: (() -> Void)?

    // MARK: - Init

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.title = ""

        super.init()

        panel.delegate = self

        let nagView = LicenseNagView(
            onSponsor: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.sponsorURL)
            },
            onBuy: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.purchaseURL)
            },
            onHaveKey: { [weak self] in
                guard let self else { return }
                self.close()
                self.onOpenSettings?()
            }
        )

        panel.contentView = NSHostingView(rootView: nagView)
    }

    // MARK: - Show / Close

    func showNag() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel.orderOut(nil)
        restoreAccessoryPolicy()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        restoreAccessoryPolicy()
    }

    // MARK: - Private Helpers

    private func restoreAccessoryPolicy() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let visibleRegularWindows = NSApp.windows.filter {
                $0.isVisible && !($0 is NSPanel) && $0.level == .normal
            }
            if visibleRegularWindows.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
