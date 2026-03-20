import SwiftUI

/// Settings tab for managing Lemon Squeezy license activation.
///
/// Shows:
/// - Unlicensed state: TextField for key entry, Activate button, ProgressView while validating,
///   inline error message, and Buy link.
/// - Licensed state: Green checkmark with "License active", customer email, Deactivate button.
///
/// Validates the persisted license key on .onAppear via a background Task.
struct LicenseSettingsSection: View {

    @State private var licenseService = LicenseService()
    @State private var licenseKeyInput = ""

    var body: some View {
        Form {
            Section("License") {
                if licenseService.isLicensed {
                    // MARK: Licensed state
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("License active")
                    }

                    if let email = licenseService.customerEmail {
                        Text("Licensed to: \(email)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Deactivate License") {
                        Task { await licenseService.deactivate() }
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.link)
                } else {
                    // MARK: Unlicensed state
                    TextField("License Key", text: $licenseKeyInput)
                        .onSubmit { activateLicense() }

                    Button("Activate License") {
                        activateLicense()
                    }
                    .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || licenseService.isValidating)

                    if licenseService.isValidating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let error = licenseService.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Link("Buy a License ->",
                         destination: URL(string: "https://store.lemonsqueezy.com/checkout/buy/TODO-product-slug")!)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("One-time purchase — supports indie development.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 350)
        .onAppear {
            Task { await licenseService.validate() }
        }
    }

    // MARK: - Private Helpers

    private func activateLicense() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        Task {
            do {
                try await licenseService.activate(key: key)
            } catch {
                // LicenseService sets lastError internally; no need to handle here.
            }
        }
    }
}
