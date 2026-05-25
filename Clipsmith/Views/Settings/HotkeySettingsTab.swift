import SwiftUI
import KeyboardShortcuts

/// Shortcuts preferences tab: keyboard recorder controls for bezel and search hotkeys.
///
/// Note: Hotkeys are stored via `KeyboardShortcuts` but will not be active until
/// Phase 2 registers event taps. The recorder UI is functional now — users can
/// assign shortcuts and they will persist across launches.
struct HotkeySettingsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(
                    "Activate Clipboard",
                    name: .activateBezel
                )
                KeyboardShortcuts.Recorder(
                    "Activate Search",
                    name: .activateSearch
                )
                KeyboardShortcuts.Recorder(
                    "Open Snippets",
                    name: .activateSnippets
                )
                KeyboardShortcuts.Recorder(
                    "Prompt Library",
                    name: .activatePrompts
                )
                KeyboardShortcuts.Recorder(
                    "Doc Lookup",
                    name: .activateDocLookup
                )
                KeyboardShortcuts.Recorder(
                    "Save Clipboard as Snippet",
                    name: .saveClipboardAsSnippet
                )
            } footer: {
                Text("Assign hotkeys for clipboard, search, snippets, prompt library, documentation lookup, and saving clipboard as a snippet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
