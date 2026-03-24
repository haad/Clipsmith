import SwiftUI
import SwiftData

/// SwiftUI content view for the Bezel HUD panel.
///
/// Responsibilities:
/// - Queries SwiftData for clippings (newest-first) and maps them to
///   BezelViewModel.clippings (a plain [String])
/// - Displays the selected clipping content
/// - Shows a search TextField bound to BezelViewModel.searchText
/// - Shows the navigation counter from BezelViewModel.navigationLabel
/// - Handles empty states: no clippings vs no matches
///
/// The view receives a BezelViewModel shared with BezelController so that
/// keyboard events (routed by the controller) mutate the same state the
/// view is observing.
struct BezelView: View {

    // MARK: - Dependencies

    @Query(sort: \ClipsmithSchemaV1.Clipping.timestamp, order: .reverse)
    private var clippings: [ClipsmithSchemaV1.Clipping]

    @Bindable var viewModel: BezelViewModel

    @AppStorage(AppSettingsKeys.displayClippingSource) private var displayClippingSource: Bool = true
    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25

    /// Focus state for the search TextField — driven by isSearchMode.
    @FocusState private var isSearchFieldFocused: Bool

    // Icon cache lives on viewModel to avoid @State mutation during body evaluation.

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Search field — only shown in search mode
            if viewModel.isSearchMode {
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)

                Divider()
            }

            // Clipping content area
            Group {
                if clippings.isEmpty {
                    emptyClippingsView
                } else if viewModel.filteredClippings.isEmpty {
                    noMatchesView
                } else {
                    clippingContentView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation counter footer
            HStack {
                Spacer()
                Text(viewModel.navigationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .background(.regularMaterial)
        }
        .background(
            ZStack {
                // Frosted glass blur layer
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                // Opacity layer — controlled by Transparency slider in Preferences.
                // bezelAlpha 0.1 (least transparent) → overlay 0.9 (nearly solid)
                // bezelAlpha 0.9 (most transparent) → overlay 0.1 (mostly glass)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(1.0 - bezelAlpha))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if viewModel.isShowingCheatSheet {
                cheatSheetOverlay
            }
        }
        .onAppear {
            updateClippings()
        }
        .onChange(of: clippings) {
            updateClippings()
        }
        .onChange(of: viewModel.isSearchMode) {
            if viewModel.isSearchMode {
                isSearchFieldFocused = true
            }
        }
    }

    // MARK: - Sub-views

    private var emptyClippingsView: some View {
        Text("No clippings")
            .foregroundStyle(.secondary)
            .font(.body)
    }

    private var noMatchesView: some View {
        Text("No matches")
            .foregroundStyle(.secondary)
            .font(.body)
    }

    /// Content view showing source app header (Bug #14) above the clipping text.
    private var clippingContentView: some View {
        VStack(spacing: 0) {
            // Source app header — shown when displayClippingSource is enabled (Bug #14)
            if displayClippingSource,
               let info = viewModel.currentClippingInfo {
                HStack(spacing: 6) {
                    if let bundlePath = info.sourceAppBundleURL {
                        Image(nsImage: cachedIcon(for: bundlePath))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    if let name = info.sourceAppName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(info.timestamp, format: .dateTime
                        .weekday(.abbreviated)
                        .month(.abbreviated)
                        .day()
                        .hour()
                        .minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                Divider()
            }

            // Clipping text content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .id("clippingTop")
                }
                .onChange(of: viewModel.selectedIndex) {
                    proxy.scrollTo("clippingTop", anchor: .top)
                }
            }
        }
    }

    private var cheatSheetOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                    shortcutSection("Navigation", shortcuts: [
                        ("↑ ↓  or  j k", "Navigate up / down"),
                        ("← →", "Navigate up / down"),
                        ("Page Up / Down", "Jump 10 items"),
                        ("Home / End", "First / last item"),
                        ("1–9", "Jump to position"),
                        ("0", "Jump to position 10"),
                        ("Scroll wheel", "Navigate"),
                    ])

                    shortcutSection("Actions", shortcuts: [
                        ("Enter", "Paste and close"),
                        ("Escape", "Close"),
                        ("Delete", "Remove clipping"),
                        ("Tab  or  Right-click", "Quick actions menu"),
                        ("Double-click", "Paste and close"),
                        ("s", "Save to file"),
                        ("S", "Save and delete"),
                        ("⌘ ,", "Preferences"),
                    ])

                    shortcutSection("Search", shortcuts: [
                        ("Type", "Fuzzy search"),
                        ("Backspace", "Edit search text"),
                    ])

                    Text("Press **?** to dismiss")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(shortcuts, id: \.0) { key, desc in
                HStack(alignment: .top) {
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 140, alignment: .trailing)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Returns a cached app icon for the given bundle path, loading it on first access.
    /// Cache lives on viewModel to avoid mutating @State during body evaluation.
    private func cachedIcon(for bundlePath: String) -> NSImage {
        if let cached = viewModel.iconCache[bundlePath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        viewModel.iconCache[bundlePath] = icon
        return icon
    }

    // MARK: - Display text

    /// Maximum characters to render in the bezel preview.
    /// Full content is still used for paste — this only limits the SwiftUI Text layout cost.
    private static let displayLimit = 5_000

    /// Truncated clipping text for display. Avoids expensive full-text layout
    /// for very large clippings (copied files, log dumps, etc.).
    private var displayText: String {
        guard let content = viewModel.currentClipping else { return "" }
        if content.count <= Self.displayLimit { return content }
        let truncated = String(content.prefix(Self.displayLimit))
        return truncated + "\n\n— (\(content.count - Self.displayLimit) more characters) —"
    }

    // MARK: - Helpers

    private func updateClippings() {
        // Pass ALL clippings so search can find entries across the full history.
        // The displayNum limit only applies to the menu bar dropdown.
        // Map to ClippingInfo so BezelController can delete by PersistentIdentifier (Bug #11)
        // and source app metadata can be displayed in the header (Bug #14).
        viewModel.clippings = clippings.map { clipping in
            ClippingInfo(
                id: clipping.persistentModelID,
                content: clipping.content,
                sourceAppName: clipping.sourceAppName,
                sourceAppBundleURL: clipping.sourceAppBundleURL,
                timestamp: clipping.timestamp
            )
        }
    }
}
