import SwiftUI
import AppKit

/// Docs section of the browser window: docset sidebar, results, rendered page.
///
/// The sidebar scopes the search to one docset (or all). `prefix:` syntax
/// (`go:fmt`) still works and moves the sidebar selection. The docs hotkey
/// prefills the search field through `BrowserWindowViewModel.pendingDocsQuery`.
///
/// ## Keyboard Shortcuts
///
/// | Shortcut | Action                     |
/// |----------|----------------------------|
/// | ⌘F       | Focus search               |
/// | ↑ ↓      | Move through results       |
/// | ⌥↑ ⌥↓    | Move the docset selection  |
struct DocsSectionView: View {
    @Bindable var windowViewModel: BrowserWindowViewModel
    let searchService: DocsetSearchService
    let managerService: DocsetManagerService

    @State private var docs = DocsBrowserViewModel()
    @FocusState private var isSearchFocused: Bool

    init(windowViewModel: BrowserWindowViewModel, searchService: DocsetSearchService, managerService: DocsetManagerService) {
        self.windowViewModel = windowViewModel
        self.searchService = searchService
        self.managerService = managerService
    }

    private var enabledDocsets: [DocsetInfo] { managerService.enabledDocsets }

    var body: some View {
        HSplitView {
            sidebar
            resultsPane
            pagePane
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    openDocsetSettings()
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .help("Manage Docsets")
            }
        }
        .background {
            Group {
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { moveDocsetSelection(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: .option)
                Button("") { moveDocsetSelection(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: .option)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            refreshDocsets()
            consumePendingQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier?.rawValue.hasPrefix("browser") == true else { return }
            refreshDocsets()
        }
        .onChange(of: windowViewModel.pendingDocsQuery) { _, _ in
            consumePendingQuery()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text("Docsets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List(selection: $docs.selectedDocsetID) {
                HStack {
                    Text("All docsets")
                    Spacer()
                    Text("\(enabledDocsets.count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .tag(Optional<String>.none)

                ForEach(enabledDocsets) { docset in
                    HStack {
                        Text(docset.displayName)
                            .lineLimit(1)
                        Spacer()
                        if let count = docs.entryCounts[docset.id] {
                            Text(count.formatted(.number.notation(.compactName)))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .tag(Optional(docset.id))
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                openDocsetSettings()
            } label: {
                Label("Add docset…", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            minWidth: BrowserPaneMetrics.sidebarMinWidth,
            idealWidth: BrowserPaneMetrics.sidebarIdealWidth,
            maxWidth: BrowserPaneMetrics.sidebarMaxWidth
        )
    }

    // MARK: - Results

    private var resultsPane: some View {
        BrowserListPane {
            BrowserSearchField(
                text: $docs.searchText,
                placeholder: "Search docs… (prefix: go:fmt)",
                isFocused: $isSearchFocused
            ) {
                if docs.isSearching {
                    ProgressView().controlSize(.small)
                } else if let docset = docs.selectedDocset {
                    Text("in \(docset.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .onKeyPress(.upArrow) {
                docs.navigateUp()
                return .handled
            }
            .onKeyPress(.downArrow) {
                docs.navigateDown()
                return .handled
            }
        } filter: {
            EmptyView()
        } content: {
            if docs.filteredResults.isEmpty {
                if docs.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("Documentation Lookup", systemImage: "book")
                    } description: {
                        Text(enabledDocsets.isEmpty
                             ? "Download a docset to get started"
                             : "Type to search your downloaded docs")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !docs.isSearching {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No documentation found for \"\(docs.searchText)\"")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                }
            } else {
                List(selection: Binding(
                    get: { docs.selectedIndex },
                    set: { docs.selectedIndex = $0 }
                )) {
                    ForEach(Array(docs.filteredResults.enumerated()), id: \.element.id) { index, result in
                        DocResultRow(result: result, isSelected: index == docs.selectedIndex)
                            .tag(index)
                    }
                }
                .listStyle(.sidebar)
            }
        } footer: {
            BrowserCountsFooter(
                leading: "\(docs.filteredResults.count) results",
                trailing: docs.selectedDocset?.displayName ?? "All docsets"
            )
        }
    }

    // MARK: - Page

    @ViewBuilder
    private var pagePane: some View {
        if let result = docs.currentResult {
            BrowserDetailPane {
                HStack(spacing: 8) {
                    Text(result.entry.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(result.docsetName)
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            } body: {
                DocWebView(html: docs.currentHTML)
            } footerLeading: {
                Text("\(result.docsetID)/\(result.entry.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } footerTrailing: {
                if let url = devdocsURL(for: result) {
                    Button("Open in Browser") {
                        NSWorkspace.shared.open(url)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            BrowserEmptyDetail(systemImage: "book", message: "Select a result")
        }
    }

    // MARK: - Helpers

    private func devdocsURL(for result: DocSearchResult) -> URL? {
        URL(string: "https://devdocs.io/\(result.docsetID)/\(result.entry.path)")
    }

    /// Picks up docsets downloaded in Settings while the window was away.
    private func refreshDocsets() {
        managerService.loadMetadata()
        docs.searchService = searchService
        docs.managerService = managerService
        docs.loadEntryCounts()
    }

    private func consumePendingQuery() {
        guard let query = windowViewModel.pendingDocsQuery else { return }
        docs.open(withQuery: query)
        isSearchFocused = true
        windowViewModel.pendingDocsQuery = nil
    }

    private func moveDocsetSelection(by delta: Int) {
        let ids: [String?] = [nil] + enabledDocsets.map(\.id)
        let current = ids.firstIndex(where: { $0 == docs.selectedDocsetID }) ?? 0
        let next = max(0, min(ids.count - 1, current + delta))
        docs.selectedDocsetID = ids[next]
    }

    private func openDocsetSettings() {
        UserDefaults.standard.set(SettingsTab.docsets.rawValue, forKey: "selectedSettingsTab")
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
