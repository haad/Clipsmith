import SwiftUI

/// SwiftUI view hosted in LicenseNagController's activating NSPanel.
///
/// Presents a friendly monetization prompt with three CTAs:
/// - Sponsor on GitHub (opens browser)
/// - Buy a License (opens Lemon Squeezy store)
/// - I Already Have a License (opens Settings > License tab)
struct LicenseNagView: View {
    let onSponsor: () -> Void
    let onBuy: () -> Void
    let onHaveKey: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scissors")
                .font(.system(size: 48))

            Text("Enjoying Clipsmith?")
                .font(.title2.bold())

            Text("Clipsmith is free for personal use. If you use it for work, please consider supporting development.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Sponsor on GitHub") { onSponsor() }
                    .buttonStyle(.bordered)
                Button("Buy a License") { onBuy() }
                    .buttonStyle(.borderedProminent)
            }

            Button("I Already Have a License") { onHaveKey() }
                .buttonStyle(.plain)
                .font(.footnote)
        }
        .padding(24)
        .frame(width: 380)
    }
}
