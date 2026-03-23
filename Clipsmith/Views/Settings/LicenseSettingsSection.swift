import SwiftUI

/// Settings tab showing sponsorship information.
///
/// Lemon Squeezy licensing has been removed. This section now points
/// users to GitHub Sponsors as the sole way to support development.
struct LicenseSettingsSection: View {

    private let sponsorURL = URL(string: "https://github.com/sponsors/haad")!

    var body: some View {
        Form {
            Section("Support Clipsmith") {
                Text("Clipsmith is free and open source. If you find it useful, please consider sponsoring development on GitHub.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link("Sponsor on GitHub ->", destination: sponsorURL)
                    .font(.footnote)
            }
        }
        .frame(minWidth: 350)
    }
}
