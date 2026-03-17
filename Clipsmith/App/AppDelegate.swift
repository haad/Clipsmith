import AppKit
import OSLog
import SwiftData
import KeyboardShortcuts
import UserNotifications
import UniformTypeIdentifiers

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "AppDelegate"
)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let accessibilityMonitor = AccessibilityMonitor()
    let clipboardMonitor = ClipboardMonitor()
    let appTracker = AppTracker()
    let pasteService = PasteService()
    var clipboardStore: ClipboardStore!
    var snippetStore: SnippetStore!
    var gistService: GistService!
    var bezelController: BezelController!

    // Phase 5 — Prompt Library
    var promptLibraryStore: PromptLibraryStore!
    var promptSyncService: PromptSyncService!
    var promptBezelController: PromptBezelController!

    // Phase 8 — Documentation Lookup
    var docsetSearchService: DocsetSearchService!
    var docsetManagerService: DocsetManagerService!
    var docBezelController: DocBezelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CRITICAL: Both LSUIElement=YES and setActivationPolicy(.accessory) are
        // required. LSUIElement suppresses the dock icon at cold launch, but
        // SwiftUI's Settings scene can promote the app back to .regular when
        // a window opens. Explicitly setting .accessory here prevents that.
        NSApp.setActivationPolicy(.accessory)

        // Register UserDefaults defaults. register(defaults:) does NOT overwrite
        // values already set by the user — it only provides fallback defaults.
        UserDefaults.standard.register(defaults: [
            "rememberNum": 40,
            "displayNum": 10,
            "displayLen": 40,
            "plainTextPaste": false,
            "pasteSound": false,
            "launchAtLogin": false,
            "suppressAccessibilityAlert": false,
            "stickyBezel": false,
            "pasteMovesToTop": true,
            // Wave 4 additions (Plan 04 — ObjC parity settings)
            "wraparoundBezel": false,
            "savePreference": 1,
            "removeDuplicates": true,
            "menuSelectionPastes": true,
            "bezelAlpha": 0.25,
            "bezelWidth": 500.0,
            "bezelHeight": 320.0,
            "displayClippingSource": true,
            "menuIcon": 0,
            // Phase 4 additions (Plan 04 — Gist sharing)
            AppSettingsKeys.gistDefaultPublic: false,
            // Wave 6 additions (Plan 06 — final parity polish)
            "skipPasswordLengths": true,
            "skipPasswordLengthsList": "12, 20, 32",
            "revealPasteboardTypes": false,
            "saveToLocation": NSHomeDirectory() + "/Desktop",
            "clipboardPollingInterval": 1.0
        ])

        accessibilityMonitor.start()
        logger.info("Clipsmith launched — accessibility trusted: \(self.accessibilityMonitor.isTrusted, privacy: .public)")

        // Show accessibility alert if not trusted and not suppressed (Bug #29).
        if !AXIsProcessTrusted() &&
           !UserDefaults.standard.bool(forKey: AppSettingsKeys.suppressAccessibilityAlert) {
            showAccessibilityAlert()
        }

        // 1. Initialize ClipboardStore, SnippetStore, and GistService with the shared model container.
        clipboardStore = ClipboardStore(modelContainer: ClipsmithApp.sharedModelContainer)
        snippetStore = SnippetStore(modelContainer: ClipsmithApp.sharedModelContainer)
        gistService = GistService(modelContext: ClipsmithApp.sharedModelContainer.mainContext)

        // Pre-warm the main model context so @Query in MenuBarView/BezelView
        // is instant on first open. Without this, the SQLite connection opens
        // lazily on first @Query which delays clipping display.
        let mainContext = ClipsmithApp.sharedModelContainer.mainContext
        _ = try? mainContext.fetchCount(FetchDescriptor<ClipsmithSchemaV1.Clipping>())

        // 2. Wire ClipboardMonitor -> ClipboardStore (Pattern 6 from 02-RESEARCH.md).
        //    The callback fires on @MainActor (ClipboardMonitor is @MainActor), then
        //    crosses to the background actor via Task for the SwiftData insert.
        //    ClipboardEntry carries source app metadata captured at copy time (Bug #1).
        clipboardMonitor.onNewClipping = { [weak self] entry in
            guard let self else { return }
            let rememberNum = UserDefaults.standard.integer(forKey: AppSettingsKeys.rememberNum)
            Task {
                try? await self.clipboardStore.insert(
                    content: entry.content,
                    sourceAppName: entry.sourceAppName,
                    sourceAppBundleURL: entry.sourceAppBundleURL,
                    rememberNum: rememberNum
                )
            }
        }

        // 3. Wire PasteService -> ClipboardMonitor for self-capture prevention.
        //    PasteService writes blockedChangeCount after each paste so ClipboardMonitor
        //    skips that cycle and doesn't re-capture Clipsmith's own paste output.
        pasteService.clipboardMonitor = clipboardMonitor

        // 4. Start services — order matters: appTracker must start first so
        //    previousApp is populated before any hotkey can fire.
        appTracker.start()
        clipboardMonitor.start()

        // 5. Create BezelController and inject service dependencies.
        //    The model container is injected so @Query inside BezelView works.
        bezelController = BezelController(modelContainer: ClipsmithApp.sharedModelContainer)
        bezelController.pasteService = pasteService
        bezelController.appTracker = appTracker
        bezelController.clipboardStore = clipboardStore
        bezelController.clipboardMonitor = clipboardMonitor

        // 5b. Initialize Prompt Library components (Phase 5).
        promptLibraryStore = PromptLibraryStore(modelContainer: ClipsmithApp.sharedModelContainer)
        promptSyncService = PromptSyncService()

        // Load bundled prompts on first launch if no prompts exist yet.
        // Also deduplicate to clean up any duplicate entries.
        Task {
            try? await promptLibraryStore.deduplicate()
            let existing = try? await promptLibraryStore.fetchAll()
            if existing?.isEmpty ?? true {
                try? await promptSyncService.loadBundledPrompts(store: promptLibraryStore)
                logger.info("Loaded bundled default prompts")
            }
        }

        // Create PromptBezelController and inject service dependencies.
        promptBezelController = PromptBezelController(modelContainer: ClipsmithApp.sharedModelContainer)
        promptBezelController.pasteService = pasteService
        promptBezelController.appTracker = appTracker

        // 7. Initialize Documentation Lookup components (Phase 8).
        docsetSearchService = DocsetSearchService()
        docsetManagerService = DocsetManagerService()
        docsetManagerService.loadMetadata()

        docBezelController = DocBezelController()
        docBezelController.appTracker = appTracker
        docBezelController.docsetSearchService = docsetSearchService
        docBezelController.docsetManagerService = docsetManagerService

        // 6. Register global hotkeys (KeyboardShortcuts library, Pattern 5).
        KeyboardShortcuts.onKeyDown(for: .activateBezel) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let stickyBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.stickyBezel)
                if self.bezelController.isVisible {
                    // Already showing — navigate down (hotkey repress while holding).
                    self.bezelController.viewModel.navigateDown()
                } else {
                    // First press — show bezel and set hold mode based on stickyBezel.
                    // Hold mode: releasing all modifiers auto-pastes selected clipping.
                    // Sticky mode: bezel stays open until Enter or Escape.
                    self.bezelController.isHotkeyHold = !stickyBezel
                    self.bezelController.show()
                }
            }
        }
        // Wire "Search Clippings..." menu item (Bug #21) — MenuBarView posts
        // this notification since it can't access BezelController directly.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSearchFromMenu),
            name: .clipsmithOpenSearch,
            object: nil
        )

        // Wire "Share as Gist" from menu bar clipping context menu.
        // MenuBarView posts .clipsmithShareAsGist with userInfo["content"]; AppDelegate
        // handles it here so that GistService (owned by AppDelegate) can be called.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShareAsGist(_:)),
            name: .clipsmithShareAsGist,
            object: nil
        )

        // Wire Export/Import History buttons (Plan 06-03).
        // GeneralSettingsTab and MenuBarView post these notifications; AppDelegate
        // handles them here so ClipboardStore and file panels can be accessed.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExportHistory),
            name: .clipsmithExportHistory,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleImportHistory),
            name: .clipsmithImportHistory,
            object: nil
        )

        // Wire "Documentation Lookup..." menu bar button.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openDocLookupFromMenu),
            name: .clipsmithOpenDocLookup,
            object: nil
        )

        // Request notification authorization for Gist creation alerts.
        // Delivers silently if the user denies (no sound by default).
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        // Observe keyboard layout changes (Bug #30) so PasteService can
        // adapt the V keycode for non-QWERTY layouts in the future.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardLayoutChanged),
            name: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
            object: nil
        )

        KeyboardShortcuts.onKeyDown(for: .activateSearch) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.bezelController.showWithSearch()
            }
        }

        // Register global hotkey for the snippet window (Plan 04-03).
        // MenuBarView observes .clipsmithOpenSnippets and calls openSnippetWindow()
        // because AppDelegate cannot use @Environment(\.openWindow).
        KeyboardShortcuts.onKeyDown(for: .activateSnippets) {
            Task { @MainActor in
                // Activation policy switch and icon refresh are handled by
                // MenuBarView.openSnippetWindow() via the notification below.
                NotificationCenter.default.post(name: .clipsmithOpenSnippets, object: nil)
            }
        }

        // Register global hotkey for the prompt bezel (Phase 5).
        KeyboardShortcuts.onKeyDown(for: .activatePrompts) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let stickyBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.stickyBezel)
                if self.promptBezelController.isVisible {
                    // Already showing — navigate down (hotkey repress while holding).
                    self.promptBezelController.viewModel.navigateDown()
                } else {
                    // First press — show bezel and set hold mode based on stickyBezel.
                    self.promptBezelController.isHotkeyHold = !stickyBezel
                    self.promptBezelController.show()
                }
            }
        }

        // Register global hotkey for documentation lookup (Phase 8).
        // Always registered, but checks feature flag at invocation time
        // so toggling the setting works without app restart.
        KeyboardShortcuts.onKeyDown(for: .activateDocLookup) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard UserDefaults.standard.bool(forKey: AppSettingsKeys.docLookupEnabled) else { return }
                let stickyBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.stickyBezel)
                if self.docBezelController.isVisible {
                    self.docBezelController.viewModel.navigateDown()
                } else {
                    self.docBezelController.isHotkeyHold = !stickyBezel
                    self.docBezelController.show()
                }
            }
        }
    }

    // MARK: - In-menu search (Bug #21)

    @objc private func openSearchFromMenu() {
        bezelController?.showWithSearch()
    }

    // MARK: - Documentation Lookup (from menu bar)

    @objc private func openDocLookupFromMenu() {
        docBezelController?.show()
    }

    // MARK: - Share as Gist (from menu bar clipping context menu)

    @objc private func handleShareAsGist(_ notification: Notification) {
        guard let content = notification.userInfo?["content"] as? String else { return }
        Task { @MainActor in
            let ext = GistService.languageExtension(for: nil)
            let filename = "clipping.\(ext)"
            do {
                let response = try await gistService.createGist(
                    filename: filename,
                    content: content,
                    description: "Shared from Clipsmith",
                    isPublic: UserDefaults.standard.bool(forKey: AppSettingsKeys.gistDefaultPublic)
                )
                sendGistNotification(url: response.htmlURL, filename: filename)
            } catch GistError.noToken {
                showGistNoTokenAlert()
            } catch {
                showGistErrorAlert(error)
            }
        }
    }

    // MARK: - Export/Import History (Plan 06-03)

    @objc private func handleExportHistory() {
        Task { @MainActor in
            // Export all clippings to JSON data
            let data: Data
            do {
                data = try await ClipboardExportService.exportHistory(from: clipboardStore)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            // Show NSSavePanel for the user to choose a file location
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "clipsmith-history.json"
            panel.canCreateDirectories = true
            panel.title = "Export Clipboard History"

            let response = await withCheckedContinuation { continuation in
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }

            guard response == .OK, let url = panel.url else { return }

            do {
                try data.write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not write file: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func handleImportHistory() {
        Task { @MainActor in
            // Show NSOpenPanel for the user to choose an import file
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.title = "Import Clipboard History"

            let response = await withCheckedContinuation { continuation in
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }

            guard response == .OK, let url = panel.urls.first else { return }

            // Read the selected file
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = "Could not read file: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            // Ask the user whether to merge or replace
            let mergeAlert = NSAlert()
            mergeAlert.messageText = "How would you like to import?"
            mergeAlert.informativeText = "Merge adds new clippings while keeping existing ones. Replace removes all existing clippings first."
            mergeAlert.addButton(withTitle: "Merge with existing")    // .alertFirstButtonReturn
            mergeAlert.addButton(withTitle: "Replace all history")    // .alertSecondButtonReturn
            mergeAlert.addButton(withTitle: "Cancel")                 // .alertThirdButtonReturn
            mergeAlert.alertStyle = .informational

            let mergeResponse = mergeAlert.runModal()
            guard mergeResponse != .alertThirdButtonReturn else { return }

            let isMerge = (mergeResponse == .alertFirstButtonReturn)

            // Perform the import
            let imported: Int
            do {
                imported = try await ClipboardExportService.importHistory(
                    into: clipboardStore,
                    from: data,
                    merge: isMerge
                )
            } catch {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            // Show success summary
            let successAlert = NSAlert()
            successAlert.messageText = "Import Complete"
            successAlert.informativeText = "Imported \(imported) clipping\(imported == 1 ? "" : "s")."
            successAlert.alertStyle = .informational
            successAlert.addButton(withTitle: "OK")
            successAlert.runModal()
        }
    }

    // MARK: - Gist Notifications

    /// Sends a macOS system notification after a Gist is created.
    /// Clicking the notification opens the Gist URL in the browser.
    func sendGistNotification(url: String, filename: String) {
        let content = UNMutableNotificationContent()
        content.title = "Gist Created"
        content.body = filename
        content.userInfo = ["url": url]
        // No sound — consistent with CONTEXT.md preference for non-intrusive notifications

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Gist Error Alerts

    private func showGistNoTokenAlert() {
        let alert = NSAlert()
        alert.messageText = "No GitHub Token Configured"
        alert.informativeText = "Add your GitHub Personal Access Token in Preferences > Gist to enable Gist sharing."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApp.activate()
            // Open Settings — post the settings notification (AppDelegate has no openSettings env)
            NotificationCenter.default.post(name: .clipsmithOpenGistSettings, object: nil)
        }
    }

    private func showGistErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Gist Sharing Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Keyboard layout observer (Bug #30)

    @objc private func keyboardLayoutChanged() {
        logger.info("Keyboard layout changed — input source updated")
    }

    // MARK: - Accessibility alert (Bug #29)

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Clipsmith needs Accessibility access"
        alert.informativeText = "Clipsmith uses Accessibility to paste clippings into other apps. Without it, paste won't work.\n\nGrant access in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show again"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Request Permission")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: AppSettingsKeys.suppressAccessibilityAlert)
        }
        switch response {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            // kAXTrustedCheckOptionPrompt string value — avoids Swift 6 shared-mutable-state warning
            // on the global Unmanaged<CFString> reference.
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        default:
            break
        }
    }

    // MARK: - Application Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        bezelController?.hide()
        promptBezelController?.hide()
        docBezelController?.hide()
        clipboardMonitor.stop()
        appTracker.stop()
        accessibilityMonitor.stop()
        DistributedNotificationCenter.default().removeObserver(self)

        // Save preference: if savePreference == 0 (never), clear all clippings on quit (Bug #10).
        // Pitfall 5 from RESEARCH.md: delete synchronously on the mainContext before the process exits.
        let savePref = UserDefaults.standard.integer(forKey: AppSettingsKeys.savePreference)
        if savePref == 0 {
            let mainContext = ClipsmithApp.sharedModelContainer.mainContext
            try? mainContext.delete(model: ClipsmithSchemaV1.Clipping.self)
            try? mainContext.save()
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Called when user clicks a delivered notification.
    /// Opens the Gist URL stored in the notification's userInfo.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString) {
            _ = await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Allows notifications to display while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner]
    }
}
