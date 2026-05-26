import SwiftUI

/// SwiftUI content view for the App Launcher Bezel HUD panel.
///
/// Responsibilities:
/// - Shows a header bar labeled "App Launcher"
/// - Shows an always-focused search TextField for instant filtering (CONTEXT D-03)
/// - Displays a scrollable list of app rows with icon + name (CONTEXT D-06)
/// - Shows a loading indicator while AppScannerService scans
/// - Shows a navigation counter footer
/// - Frosted glass background matching the clipboard and prompt bezel visual style
///
/// No SwiftData dependency — the launcher does not persist clippings or prompts.
/// The view receives an AppLaunchViewModel shared with AppLaunchController so that
/// keyboard events (routed by the controller) mutate the same state the view observes.
struct AppLaunchView: View {

    // MARK: - Dependencies

    @Bindable var viewModel: AppLaunchViewModel

    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25

    /// Focus state for the search TextField — always focused on bezel appear (D-03).
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Header bar — title switches to "Command Palette" in command palette mode
            HStack {
                Text(viewModel.isCommandPaletteMode ? "Command Palette" : "App Launcher")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.regularMaterial)

            Divider()

            // Search field — placeholder adapts to command palette mode (D-03)
            TextField(viewModel.isCommandPaletteMode ? "Math, units, currency..." : "Search apps...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)

            Divider()

            // App list / command palette / loading / empty states
            Group {
                if viewModel.isCommandPaletteMode {
                    CommandPaletteView(viewModel: viewModel)
                } else if viewModel.isLoading && viewModel.apps.isEmpty {
                    ProgressView("Scanning apps...")
                        .foregroundStyle(.secondary)
                } else if viewModel.displayedApps.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .font(.body)
                } else {
                    appListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation counter footer — hide in command palette mode (count is meaningless)
            HStack {
                Spacer()
                Text(viewModel.isCommandPaletteMode ? "" : viewModel.navigationLabel)
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
        .onAppear { isSearchFieldFocused = true }
    }

    // MARK: - Sub-views

    private var appListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.displayedApps.enumerated()), id: \.element.id) { index, entry in
                        appRow(entry: entry, index: index)
                            .id(entry.id)
                            .onTapGesture {
                                viewModel.navigateTo(index: index)
                            }
                    }
                }
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                let apps = viewModel.displayedApps
                guard newIndex < apps.count else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(apps[newIndex].id, anchor: .center)
                }
            }
        }
    }

    /// Renders a single app row: icon (24×24) + app name with selection highlight.
    /// CONTEXT D-06: icon ~24pt square plus app name for visual scanning.
    private func appRow(entry: AppEntry, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex

        return HStack(spacing: 10) {
            // Icon: show loaded NSImage or placeholder system image
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }

            Text(entry.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
    }
}
