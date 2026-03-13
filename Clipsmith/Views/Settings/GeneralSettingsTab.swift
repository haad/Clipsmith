import SwiftUI
import ServiceManagement
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "GeneralSettingsTab"
)

/// General preferences tab: history size, display options, paste behavior,
/// launch at login toggle, and accessibility status.
struct GeneralSettingsTab: View {
    // Read directly from @AppStorage so values persist without needing an
    // AppSettings instance in the environment (simplest correct approach).
    @AppStorage(AppSettingsKeys.rememberNum) private var rememberNum: Int = 40
    @AppStorage(AppSettingsKeys.displayNum) private var displayNum: Int = 10
    @AppStorage(AppSettingsKeys.displayLen) private var displayLen: Int = 40
    @AppStorage(AppSettingsKeys.plainTextPaste) private var plainTextPaste: Bool = false
    @AppStorage(AppSettingsKeys.pasteSound) private var pasteSound: Bool = false
    @AppStorage(AppSettingsKeys.stickyBezel) private var stickyBezel: Bool = false
    @AppStorage(AppSettingsKeys.launchAtLogin) private var launchAtLogin: Bool = false

    // Wave 4: new settings (Plan 04)
    @AppStorage(AppSettingsKeys.wraparoundBezel) private var wraparoundBezel: Bool = false
    @AppStorage(AppSettingsKeys.savePreference) private var savePreference: Int = 1
    @AppStorage(AppSettingsKeys.removeDuplicates) private var removeDuplicates: Bool = true
    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25
    @AppStorage(AppSettingsKeys.bezelWidth) private var bezelWidth: Double = 500
    @AppStorage(AppSettingsKeys.bezelHeight) private var bezelHeight: Double = 320
    @AppStorage(AppSettingsKeys.displayClippingSource) private var displayClippingSource: Bool = true

    // Wave 5: menu bar settings (Plan 05)
    @AppStorage(AppSettingsKeys.menuIcon) private var menuIcon: Int = 0
    @AppStorage(AppSettingsKeys.menuSelectionPastes) private var menuSelectionPastes: Bool = true

    // Wave 6: advanced settings (Plan 06)
    @AppStorage(AppSettingsKeys.skipPasswordLengths) private var skipPasswordLengths: Bool = true
    @AppStorage(AppSettingsKeys.skipPasswordLengthsList) private var skipPasswordLengthsList: String = "12, 20, 32"
    @AppStorage(AppSettingsKeys.saveToLocation) private var saveToLocation: String = "~/Desktop"
    @AppStorage(AppSettingsKeys.clipboardPollingInterval) private var clipboardPollingInterval: Double = 1.0

    var body: some View {
        Form {
            // MARK: - History

            Section("History") {
                Stepper(
                    "Remember up to \(rememberNum) clippings",
                    value: $rememberNum,
                    in: 1...999
                )
                Stepper(
                    "Show \(displayNum) in menu",
                    value: $displayNum,
                    in: 1...99
                )
                Stepper(
                    "Preview length: \(displayLen) characters",
                    value: $displayLen,
                    in: 1...2000
                )
            }

            // MARK: - Paste Behavior

            Section("Paste Behavior") {
                Toggle("Always paste as plain text", isOn: $plainTextPaste)
                Toggle("Play sound on paste", isOn: $pasteSound)
                Toggle("Sticky bezel (stay open until Enter/Escape)", isOn: $stickyBezel)
            }

            // MARK: - Navigation (Bug #8)

            Section("Navigation") {
                Toggle("Wraparound navigation", isOn: $wraparoundBezel)
            }

            // MARK: - Data (Bugs #9, #10)

            Section("Data") {
                Picker("Save history", selection: $savePreference) {
                    Text("Never (clear on quit)").tag(0)
                    Text("On exit").tag(1)
                    Text("After each clip").tag(2)
                }
                Toggle("Remove duplicate clippings", isOn: $removeDuplicates)
                HStack {
                    Button("Export History...") {
                        NotificationCenter.default.post(name: .flycutExportHistory, object: nil)
                    }
                    Button("Import History...") {
                        NotificationCenter.default.post(name: .flycutImportHistory, object: nil)
                    }
                }
            }

            // MARK: - Bezel Appearance (Bugs #14, #16, #17)

            Section("Bezel Appearance") {
                HStack {
                    Text("Width")
                    Slider(value: $bezelWidth, in: 200...1200)
                    Text("\(Int(bezelWidth))px").monospacedDigit()
                }
                HStack {
                    Text("Height")
                    Slider(value: $bezelHeight, in: 200...800)
                    Text("\(Int(bezelHeight))px").monospacedDigit()
                }
                HStack {
                    Text("Transparency")
                    Slider(value: $bezelAlpha, in: 0.1...0.9)
                }
                Toggle("Show clipping source app", isOn: $displayClippingSource)
            }

            // MARK: - Menu Bar (Bugs #19, BUG-26-menuSelectionPastes)

            Section("Menu Bar") {
                Picker("Menu bar icon", selection: $menuIcon) {
                    Label("Clipboard", systemImage: "doc.on.clipboard").tag(0)
                    Label("Scissors", systemImage: "scissors").tag(1)
                    Label("Scissors Circle", systemImage: "scissors.circle").tag(2)
                    Label("Documents", systemImage: "doc.on.doc").tag(3)
                }
                .pickerStyle(.inline)

                Toggle("Clicking menu item pastes (vs. copy only)", isOn: $menuSelectionPastes)
            }

            // MARK: - Advanced (Bugs #25, #33)

            Section("Advanced") {
                HStack {
                    Text("Clipboard check interval")
                    Slider(value: $clipboardPollingInterval, in: 0.1...5.0, step: 0.1)
                    Text("\(String(format: "%.1f", clipboardPollingInterval))s").monospacedDigit()
                }
                Toggle("Skip likely passwords by length", isOn: $skipPasswordLengths)
                if skipPasswordLengths {
                    TextField("Password lengths (comma-separated)", text: $skipPasswordLengthsList)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Save clippings to:")
                    TextField("Path", text: $saveToLocation)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // MARK: - Launch

            Section("Startup") {
                Toggle("Launch Clipsmith at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
                    .onAppear {
                        syncLaunchAtLogin()
                    }
            }

            // MARK: - Accessibility

            AccessibilitySettingsSection()
        }
        .formStyle(.grouped)
    }

    // MARK: - SMAppService helpers

    /// Syncs the `launchAtLogin` @AppStorage value with the system's ground truth.
    ///
    /// Always call on `.onAppear` so the toggle reflects reality even if the
    /// user toggled launch-at-login from another app or the system removed it.
    private func syncLaunchAtLogin() {
        let systemEnabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != systemEnabled {
            launchAtLogin = systemEnabled
        }
    }

    /// Registers or unregisters the app for launch at login.
    ///
    /// - Checks status before calling register/unregister to avoid the
    ///   "already registered" error (Pitfall 4 from research notes).
    /// - Logs errors via OSLog — never crashes; the toggle will be reverted
    ///   by `syncLaunchAtLogin()` on next appear.
    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Registered for launch at login")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    logger.info("Unregistered from launch at login")
                }
            }
        } catch {
            logger.error("SMAppService error: \(error.localizedDescription, privacy: .public)")
            // Revert toggle to reflect actual system state
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
