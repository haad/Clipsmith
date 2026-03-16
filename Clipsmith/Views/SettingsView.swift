import SwiftUI

/// Root preferences window — a tabbed view with General and Shortcuts tabs.
///
/// Opened via cmd-comma (SwiftUI Settings scene) or Preferences menu item.
/// Hosts all user-configurable settings for Phase 1. Phase 2 and beyond will
/// add additional tabs (e.g., Appearance, Advanced).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            HotkeySettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            PromptLibrarySettingsSection()
                .tabItem {
                    Label("Prompts", systemImage: "text.book.closed")
                }

            GistSettingsSection()
                .tabItem {
                    Label("Gist", systemImage: "link")
                }

            DocsetSettingsSection()
                .tabItem {
                    Label("Docsets", systemImage: "book")
                }
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
