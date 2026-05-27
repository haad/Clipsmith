import SwiftUI

/// Settings section for GitHub Gist integration.
///
/// Allows the user to enter and save their GitHub Personal Access Token (PAT)
/// via a SecureField, clear an existing token, and configure the default
/// Gist visibility (public or private).
struct GistSettingsSection: View {

    @State private var tokenInput: String = ""
    @State private var hasToken: Bool = false
    @AppStorage(AppSettingsKeys.gistDefaultPublic) private var gistDefaultPublic: Bool = false

    private let tokenStore = TokenStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("GitHub Gist")
                    .font(.title2).bold()

                if hasToken {
                    HStack {
                        Label("Token saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Clear Token") {
                            tokenStore.deleteToken()
                            hasToken = false
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Access Token")
                            .font(.headline)
                        SecureField("", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        Button("Save Token") {
                            tokenStore.saveToken(tokenInput)
                            tokenInput = ""
                            hasToken = true
                        }
                        .disabled(tokenInput.isEmpty)
                        Text("Create a token at github.com/settings/tokens with the 'gist' scope.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle("Public gists by default", isOn: $gistDefaultPublic)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear {
            hasToken = tokenStore.loadToken() != nil
        }
    }
}
