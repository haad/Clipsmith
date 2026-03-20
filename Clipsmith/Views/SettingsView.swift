import SwiftUI

/// Programmatic tab indices for Settings.
///
/// AppDelegate sets `UserDefaults.standard.set(SettingsTab.license.rawValue, forKey: "selectedSettingsTab")`
/// before opening the Settings window so the License tab is automatically selected.
enum SettingsTab: Int {
    case general = 0
    case shortcuts = 1
    case prompts = 2
    case gist = 3
    case docsets = 4
    case license = 5
}

/// Root preferences window — a tabbed view with all settings sections.
///
/// Opened via cmd-comma (SwiftUI Settings scene) or Preferences menu item.
/// Uses @AppStorage("selectedSettingsTab") so AppDelegate can programmatically
/// navigate to a specific tab (e.g., the License tab) by writing to UserDefaults
/// before calling NSApp.sendAction(Selector(("showSettingsWindow:")), ...).
struct SettingsView: View {
    @AppStorage("selectedSettingsTab") private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general.rawValue)

            HotkeySettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts.rawValue)

            PromptLibrarySettingsSection()
                .tabItem {
                    Label("Prompts", systemImage: "text.book.closed")
                }
                .tag(SettingsTab.prompts.rawValue)

            GistSettingsSection()
                .tabItem {
                    Label("Gist", systemImage: "link")
                }
                .tag(SettingsTab.gist.rawValue)

            DocsetSettingsSection()
                .tabItem {
                    Label("Docsets", systemImage: "book")
                }
                .tag(SettingsTab.docsets.rawValue)

            LicenseSettingsSection()
                .tabItem {
                    Label("License", systemImage: "key")
                }
                .tag(SettingsTab.license.rawValue)
        }
        .frame(minWidth: 420, minHeight: 300)
        .onDisappear {
            // Restore accessory policy when the settings window closes,
            // but only if no other regular windows remain visible.
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
}
