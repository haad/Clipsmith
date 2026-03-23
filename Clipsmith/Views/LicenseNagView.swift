import SwiftUI

/// SwiftUI view hosted in LicenseNagController's activating NSPanel.
///
/// Presents a friendly monetization prompt with two CTAs:
/// - Sponsor on GitHub (opens browser)
/// - Dismiss
struct LicenseNagView: View {
    let onSponsor: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scissors")
                .font(.system(size: 48))

            Text("Enjoying Clipsmith?")
                .font(.title2.bold())

            Text("Clipsmith is free and open source. If you find it useful, please consider sponsoring development on GitHub.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Sponsor on GitHub") { onSponsor() }
                .buttonStyle(.borderedProminent)

            Button("Maybe Later") { onDismiss() }
                .buttonStyle(.plain)
                .font(.footnote)
        }
        .padding(24)
        .frame(width: 380)
    }
}
