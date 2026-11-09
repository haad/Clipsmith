import SwiftUI
import SwiftData

extension Notification.Name {
    static let clipsmithOpenSearch = Notification.Name("clipsmithOpenSearch")
    /// Posted by the menu bar "App Launcher..." button to open the app launcher bezel (Phase 11).
    static let clipsmithOpenAppLauncher = Notification.Name("clipsmithOpenAppLauncher")
    static let clipsmithExportHistory = Notification.Name("clipsmithExportHistory")
    /// Posted to trigger clipboard history import via NSOpenPanel.
    static let clipsmithImportHistory = Notification.Name("clipsmithImportHistory")
    /// Posted by LicenseNagView "I Already Have a License" to open Settings > License tab.
    static let clipsmithOpenLicenseSettings = Notification.Name("clipsmithOpenLicenseSettings")
    /// Posted by Settings > Features "Refresh exchange rates" on successful refresh (Phase 12).
    /// AppDelegate observes this to reload its CurrencyService instance from disk so the live
    /// bezel sees fresh rates without app restart.
    static let clipsmithCurrencyRatesRefreshed = Notification.Name("clipsmithCurrencyRatesRefreshed")
    /// Posted by TodoSettingsSection when the todo file path changes;
    /// AppDelegate observes it and re-points TodoStore at the new file.
    static let clipsmithTodoFilePathChanged = Notification.Name("clipsmithTodoFilePathChanged")
    static let clipsmithDataFolderChanged = Notification.Name("clipsmithDataFolderChanged")
}

struct MenuBarView: View {
    /// Manual fetch instead of @Query — the `.menu` style MenuBarExtra renders
    /// as an NSMenu, which doesn't reliably propagate the SwiftData model
    /// container to @Query. Fetching from the shared mainContext on each render
    /// ensures clippings are always visible when the menu opens.
    @State private var clippings: [ClipsmithSchemaV1.Clipping] = []

    @Environment(PasteService.self) private var pasteService
    @Environment(AppTracker.self) private var appTracker
    @Environment(ClipboardMonitor.self) private var clipboardMonitor

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @AppStorage(AppSettingsKeys.displayNum) private var displayNum: Int = 10
    @AppStorage(AppSettingsKeys.displayLen) private var displayLen: Int = 40
    @AppStorage(AppSettingsKeys.menuSelectionPastes) private var menuSelectionPastes: Bool = true
    @AppStorage(AppSettingsKeys.appLauncherEnabled) private var appLauncherEnabled: Bool = false

    private var modelContext: ModelContext {
        ClipsmithApp.sharedModelContainer.mainContext
    }

    var body: some View {
        // Show clippings up to displayNum limit
        if clippings.isEmpty {
            Text("No clippings yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(clippings.prefix(displayNum)) { clipping in
                Button {
                    if menuSelectionPastes {
                        pasteService.paste(
                            content: clipping.content,
                            into: appTracker.previousApp
                        )
                    } else {
                        // Copy to clipboard without pasting
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(clipping.content, forType: .string)
                    }
                } label: {
                    Text(clipping.content.prefix(displayLen))
                        .lineLimit(1)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        modelContext.delete(clipping)
                        try? modelContext.save()
                    }
                }
            }
        }

        Divider()

        // One entry for the browser window; it opens on the last-used section
        // and ⌘1–⌘5 switch between Snippets, Prompts, Docs, Toolkit and Todos.
        Button("Browser...") {
            openBrowser(BrowserOpenRequest(section: nil, query: nil))
        }

        Button("Search Clippings...") {
            NotificationCenter.default.post(name: .clipsmithOpenSearch, object: nil)
        }

        if appLauncherEnabled {
            Button("App Launcher...") {
                NotificationCenter.default.post(name: .clipsmithOpenAppLauncher, object: nil)
            }
        }

        Divider()

        if !clippings.isEmpty {
            Button("Clear All") {
                let alert = NSAlert()
                alert.messageText = "Clear all clippings?"
                alert.informativeText = "This cannot be undone."
                alert.addButton(withTitle: "Clear All")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    for clipping in clippings {
                        modelContext.delete(clipping)
                    }
                    try? modelContext.save()
                }
            }
        }

        Button("Export History...") {
            NotificationCenter.default.post(name: .clipsmithExportHistory, object: nil)
        }

        Button("Import History...") {
            NotificationCenter.default.post(name: .clipsmithImportHistory, object: nil)
        }

        Divider()

        Button(clipboardMonitor.isPaused ? "Resume Monitoring" : "Pause Monitoring") {
            clipboardMonitor.isPaused.toggle()
        }

        Divider()

        Button("About Clipsmith") {
            activateAsRegularApp()
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Button("Preferences...") {
            activateAsRegularApp()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .onAppear {
            fetchClippings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipsmithRequestBrowser)) { notification in
            openBrowser(BrowserOpenRequest(userInfo: notification.userInfo) ?? BrowserOpenRequest(section: nil, query: nil))
        }
    }

    private func fetchClippings() {
        let descriptor = FetchDescriptor<ClipsmithSchemaV1.Clipping>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        clippings = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Activation Policy

    /// Switches to `.regular` so the app icon appears in Cmd-Tab,
    /// then activates the app so the window comes to front.
    private func activateAsRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = NSImage(named: NSImage.applicationIconName)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Browser Window

    /// Opens the unified browser window and routes the request to it.
    ///
    /// Same activation dance as the other windows. The request goes into
    /// `BrowserOpenMailbox` before the window opens: a new window takes it in
    /// `onAppear`, an already open one on `.clipsmithOpenBrowser`.
    private func openBrowser(_ request: BrowserOpenRequest) {
        Task { @MainActor in
            BrowserOpenMailbox.shared.post(request)
            activateAsRegularApp()
            try? await Task.sleep(for: .milliseconds(100))
            openWindow(id: "browser")
            NotificationCenter.default.post(name: .clipsmithOpenBrowser, object: nil)
        }
    }
}
