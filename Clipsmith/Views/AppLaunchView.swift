import SwiftUI

/// SwiftUI content view for the App Launcher Bezel HUD panel.
///
/// Responsibilities:
/// - Shows a header bar labeled "App Launcher"
/// - Shows an always-focused search TextField for instant filtering (CONTEXT D-03)
/// - Displays a scrollable list of app rows with icon + name (CONTEXT D-06)
/// - Shows a loading indicator while AppScannerService scans
/// - Shows a navigation counter footer
/// - Liquid Glass panel on macOS 26; frosted material stack (matching the clipboard and
///   prompt bezels) on macOS 15
///
/// No SwiftData dependency — the launcher does not persist clippings or prompts.
/// The view receives an AppLaunchViewModel shared with AppLaunchController so that
/// keyboard events (routed by the controller) mutate the same state the view observes.
struct AppLaunchView: View {

    // MARK: - Dependencies

    @Bindable var viewModel: AppLaunchViewModel
    var onLaunch: (AppEntry) -> Void

    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25

    /// Focus state for the search TextField — always focused on bezel appear (D-03).
    @FocusState private var isSearchFieldFocused: Bool

    /// Lets the selection highlight slide between grid cells instead of jumping.
    @Namespace private var selectionNamespace

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
            .background(sectionBackground)

            Divider()

            // Search field — placeholder adapts to command palette mode (D-03)
            TextField(viewModel.isCommandPaletteMode ? "Math, units, currency..." : "Search apps...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(sectionBackground)

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
            .background(sectionBackground)
        }
        .modifier(LauncherChrome(bezelAlpha: bezelAlpha))
        .onAppear { isSearchFieldFocused = true }
    }

    /// Header, search and footer bands sit directly on the glass on macOS 26;
    /// on macOS 15 they keep their own material so they read against the blur.
    private var sectionBackground: AnyShapeStyle {
        if #available(macOS 26, *) { return AnyShapeStyle(.clear) }
        return AnyShapeStyle(.regularMaterial)
    }

    // MARK: - Sub-views

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    private var appListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(Array(viewModel.displayedApps.enumerated()), id: \.element.id) { index, entry in
                        appGridCell(entry: entry, index: index)
                            .id(entry.id)
                            .onTapGesture {
                                viewModel.navigateTo(index: index)
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                viewModel.navigateTo(index: index)
                                onLaunch(entry)
                            })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.snappy(duration: 0.18), value: viewModel.selectedIndex)
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

    /// Renders a single app grid cell: large icon + app name below, with selection highlight.
    private func appGridCell(entry: AppEntry, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex

        return VStack(spacing: 6) {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.secondary)
            }

            Text(entry.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.3))
                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            }
        }
    }
}

// MARK: - Chrome

/// Panel chrome for the launcher.
///
/// macOS 26: a single Liquid Glass surface — the system refracts and tints whatever is
/// behind the panel, and reacts to the pointer. The Transparency slider keeps its meaning:
/// the opaque half uses frosted `.regular` glass, the transparent half switches to `.clear`
/// glass (regular glass stays frosted however thin its tint), and the window-background
/// tint fades out as the slider moves right.
/// macOS 15: the frosted material stack shared with the clipboard and prompt bezels.
private struct LauncherChrome: ViewModifier {
    let bezelAlpha: Double

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            let base: Glass = bezelAlpha >= 0.5 ? .clear : .regular
            content
                .clipShape(.rect(cornerRadius: 24))
                .glassEffect(
                    base.tint(Color(NSColor.windowBackgroundColor).opacity(1.0 - bezelAlpha)),
                    in: .rect(cornerRadius: 24)
                )
        } else {
            content
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
        }
    }
}
