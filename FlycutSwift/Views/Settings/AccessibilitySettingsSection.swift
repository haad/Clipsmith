import SwiftUI

/// Shows current accessibility permission status and a button to open System Settings.
///
/// NEVER calls `AXIsProcessTrustedWithOptions(prompt: true)` — that steals
/// focus. Instead, it opens System Settings to the Accessibility pane and lets
/// the user grant permission there. `AccessibilityMonitor` polls in the
/// background and updates `isTrusted` automatically.
struct AccessibilitySettingsSection: View {
    @Environment(AccessibilityMonitor.self) private var accessibilityMonitor

    var body: some View {
        Section("Accessibility") {
            HStack(spacing: 8) {
                if accessibilityMonitor.isTrusted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Accessibility: Granted")
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Accessibility: Not Granted")
                        .foregroundStyle(.primary)
                    Button("Grant Permission…") {
                        accessibilityMonitor.requestPermission()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}
