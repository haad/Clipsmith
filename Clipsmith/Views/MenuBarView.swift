import SwiftUI
import SwiftData

extension Notification.Name {
    static let flycutOpenSearch = Notification.Name("flycutOpenSearch")
    static let flycutOpenSnippets = Notification.Name("flycutOpenSnippets")
    /// Posted to open the snippet window on the Prompts tab (tab index 1).
    static let flycutOpenPrompts = Notification.Name("flycutOpenPrompts")
    static let flycutShareAsGist = Notification.Name("flycutShareAsGist")
    static let flycutOpenGistSettings = Notification.Name("flycutOpenGistSettings")
    static let flycutShareSnippetAsGist = Notification.Name("flycutShareSnippetAsGist")
    /// Posted to trigger clipboard history export via NSSavePanel.
    static let flycutExportHistory = Notification.Name("flycutExportHistory")
    /// Posted to trigger clipboard history import via NSOpenPanel.
    static let flycutImportHistory = Notification.Name("flycutImportHistory")
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
                        Task {
                            await pasteService.paste(
                                content: clipping.content,
                                into: appTracker.previousApp
                            )
                        }
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
                    Button("Share as Gist...") {
                        NotificationCenter.default.post(
                            name: .flycutShareAsGist,
                            object: nil,
                            userInfo: ["content": clipping.content]
                        )
                    }
                }
            }
        }

        Divider()

        Button("Snippets...") {
            openSnippetWindow()
        }

        Button("Browse Prompts...") {
            openSnippetWindowOnPromptsTab()
        }

        Button("Search Clippings...") {
            NotificationCenter.default.post(name: .flycutOpenSearch, object: nil)
        }

        if clippings.count > 1 {
            Button("Merge All Clippings") {
                let merged = clippings.map(\.content).joined(separator: "\n")
                let mergedClipping = ClipsmithSchemaV1.Clipping(
                    content: merged,
                    sourceAppName: "Merged"
                )
                modelContext.insert(mergedClipping)
                try? modelContext.save()
            }
        }

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
            NotificationCenter.default.post(name: .flycutExportHistory, object: nil)
        }

        Button("Import History...") {
            NotificationCenter.default.post(name: .flycutImportHistory, object: nil)
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
        .onReceive(NotificationCenter.default.publisher(for: .flycutOpenSnippets)) { _ in
            openSnippetWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flycutOpenGistSettings)) { _ in
            NSApp.activate()
            openSettings()
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

    // MARK: - Snippet Window

    /// Opens the snippet window with proper activation policy switch.
    ///
    /// PITFALL (RESEARCH.md): Without switching to .regular first, the window opens
    /// behind other windows. The 100ms sleep allows the policy change to propagate
    /// before activating and opening the window.
    private func openSnippetWindow() {
        Task { @MainActor in
            activateAsRegularApp()
            try? await Task.sleep(for: .milliseconds(100))
            openWindow(id: "snippets")
        }
    }

    /// Opens the snippet window and navigates to the Prompts tab (tab index 1).
    ///
    /// Opens the window first (with the same activation policy dance as openSnippetWindow),
    /// then posts .flycutOpenPrompts after a brief delay so SnippetWindowView can switch
    /// to the Prompts tab once the window has appeared.
    private func openSnippetWindowOnPromptsTab() {
        Task { @MainActor in
            activateAsRegularApp()
            try? await Task.sleep(for: .milliseconds(100))
            openWindow(id: "snippets")
            // Brief delay ensures SnippetWindowView has appeared before tab switch fires.
            try? await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(name: .flycutOpenPrompts, object: nil)
        }
    }
}
