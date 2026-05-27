import SwiftUI

/// Help tab — quick reference for all Clipsmith features and keyboard shortcuts.
struct HelpSettingsTab: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                HelpSection(title: "Clipboard History", icon: "doc.on.clipboard", color: .blue) {
                    HelpRow(keys: "Return", action: "Paste selected item")
                    HelpRow(keys: "⌘ Return", action: "Copy without pasting")
                    HelpRow(keys: "↑ / ↓", action: "Navigate items")
                    HelpRow(keys: "Type", action: "Instant fuzzy search")
                    HelpRow(keys: "Escape", action: "Dismiss")
                }

                HelpSection(title: "App Launcher", icon: "square.grid.3x3.fill", color: .orange) {
                    HelpRow(keys: "Type", action: "Search and filter apps")
                    HelpRow(keys: "Return", action: "Launch selected app")
                    HelpRow(keys: "↑ / ↓", action: "Move row up / down")
                    HelpRow(keys: "← / →", action: "Move column left / right")
                    HelpRow(keys: "Escape", action: "Dismiss")
                }

                HelpSection(title: "Command Palette", icon: "function", color: .purple) {
                    HelpRow(keys: "=2+2", action: "Math — result: 4")
                    HelpRow(keys: "=sqrt(144)", action: "Functions — result: 12")
                    HelpRow(keys: "=5 kg to lbs", action: "Unit conversion — result: 11.023 lbs")
                    HelpRow(keys: "=1000 HUF to EUR", action: "Currency conversion")
                    HelpRow(keys: "Return", action: "Copy result to clipboard")
                    HelpRow(keys: "Note", action: "Activate by typing the prefix character (default =) in App Launcher")
                }

                HelpSection(title: "Snippet Library", icon: "text.badge.star", color: .green) {
                    HelpRow(keys: "Return", action: "Paste selected snippet")
                    HelpRow(keys: "↑ / ↓", action: "Navigate snippets")
                    HelpRow(keys: "Type", action: "Fuzzy search snippets")
                    HelpRow(keys: "Escape", action: "Dismiss")
                }

                HelpSection(title: "Prompt Library", icon: "text.book.closed", color: .teal) {
                    HelpRow(keys: "Return", action: "Paste selected prompt")
                    HelpRow(keys: "Type", action: "Search prompts")
                    HelpRow(keys: "Sync URL", action: "Configure a remote JSON source in the Prompts tab")
                }

                HelpSection(title: "Documentation Browser", icon: "book", color: .brown) {
                    HelpRow(keys: "Type", action: "Search across all downloaded docsets")
                    HelpRow(keys: "python:map", action: "Prefix search to a specific docset")
                    HelpRow(keys: "Return", action: "Open entry in browser pane")
                    HelpRow(keys: "Note", action: "Enable in General > Features, then download docsets in the Docsets tab")
                }

                HelpSection(title: "Hotkeys", icon: "keyboard", color: .secondary) {
                    HelpRow(keys: "All hotkeys", action: "Configure in the Shortcuts tab — none are set by default")
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Sub-views

private struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 3) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct HelpRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            Text(action)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
