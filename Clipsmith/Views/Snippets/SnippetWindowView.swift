import SwiftUI

/// Root view for the snippet WindowGroup.
///
/// Contains a segmented control that switches between the Snippets list
/// and the Prompts management tab.
/// - Snippets tab: SnippetListView for browsing and editing code snippets
/// - Prompts tab: PromptLibraryView for browsing and editing library prompts
///
/// ## Keyboard Shortcuts
///
/// | Shortcut       | Action                                    |
/// |----------------|-------------------------------------------|
/// | ⌘1             | Switch to Snippets tab                    |
/// | ⌘2             | Switch to Prompts tab                     |
/// | ⌘N             | Create new snippet / new prompt           |
/// | ⌘F             | Focus search field                        |
/// | ⌘⌫             | Delete selected snippet / user prompt     |
/// | ↩ (Return)     | Paste selected item and close window      |
/// | ↑↓ (Arrows)    | Navigate list                             |
/// | ⇥ (Tab)        | Cycle focus between controls              |
/// | ⎋ (Escape)     | Close snippet window                      |
struct SnippetWindowView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("Snippets").tag(0)
                    Text("Prompts").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Spacer()
            }
            .padding()

            if selectedTab == 0 {
                SnippetListView()
            } else {
                PromptLibraryView()
            }
        }
        // ⎋ Escape closes the snippet window (yields to text fields)
        .onExitCommand {
            NSApp.keyWindow?.close()
        }
        // Hidden buttons for tab-switching keyboard shortcuts
        .background {
            Group {
                Button("") { selectedTab = 0 }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = 1 }
                    .keyboardShortcut("2", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipsmithOpenPrompts)) { _ in
            selectedTab = 1
        }
        .onDisappear {
            // Restore accessory policy when the snippet window closes,
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
