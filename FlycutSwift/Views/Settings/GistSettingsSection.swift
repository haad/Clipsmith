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
        Form {
            Section("GitHub Gist") {
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
                    SecureField("Personal Access Token", text: $tokenInput)
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

                Toggle("Public gists by default", isOn: $gistDefaultPublic)
            }
        }
        .onAppear {
            hasToken = tokenStore.loadToken() != nil
        }
    }
}
