import AppKit
import SwiftUI
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "AppLaunchController"
)

/// Non-activating NSPanel that hosts the AppLaunchView SwiftUI content.
///
/// Design notes:
/// - `.nonactivatingPanel` MUST be in init styleMask — WindowServer does not
///   honour setting it afterwards.
/// - `canBecomeKey` returns true so the SwiftUI TextField inside can receive
///   keyboard input even though the panel does not activate the app.
/// - `level` is set above `.screenSaverWindow` so the bezel appears over
///   fullscreen apps.
/// - `collectionBehavior` includes `.canJoinAllSpaces` and `.fullScreenAuxiliary`
///   so the bezel is visible across all Spaces and in fullscreen mode.
/// - The shared AppLaunchViewModel instance bridges the controller (keyboard routing)
///   and the view (display + search).
/// - Unlike PromptBezelController, the launcher has NO SwiftData dependency,
///   NO isHotkeyHold mode, NO flagsMonitor, NO pasteService, NO appTracker.
///   The launcher is always "sticky" — it stays open until the user presses
///   Escape, Return, or clicks outside.
@MainActor
final class AppLaunchController: NSPanel {

    // MARK: - State

    /// Shared view model — controller routes key events, view reads/displays state.
    let viewModel = AppLaunchViewModel()

    /// App scanner service — injected by AppDelegate before first show() call.
    var appScannerService: AppScannerService?

    /// Global event monitor for click-outside dismissal. Removed on hide().
    private var globalMonitor: Any?

    // MARK: - Init

    /// Required forwarder — NSPanel designated init. Passes through to super.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    /// Designated init — configures the panel with non-activating bezel settings
    /// and hosts AppLaunchView in an NSHostingView.
    init() {
        // CRITICAL: .nonactivatingPanel MUST be passed to super.init styleMask.
        // Setting window.styleMask afterwards does not update the WindowServer tag,
        // so the panel would still steal focus.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Window appearance
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        // Content view — no model container needed (launcher has no SwiftData dependency)
        let hostingView = NSHostingView(rootView: AppLaunchView(viewModel: viewModel))
        hostingView.sizingOptions = []   // CRITICAL: prevents infinite constraint update loop crash
        contentView = hostingView

        logger.debug("AppLaunchController initialised — level: \(self.level.rawValue, privacy: .public)")
    }

    // MARK: - canBecomeKey / canBecomeMain

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Event interception

    /// SwiftUI's TextField consumes Escape internally and may not propagate
    /// cancelOperation up to the NSPanel. Override sendEvent to intercept
    /// Escape and navigation keys before they reach any hosted view.
    ///
    /// Launcher is always in search mode — NO Tab/j/k/digit intercepts.
    /// All typed characters must flow through to the TextField for search input.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53:                            // Escape
                hide()
                return
            case 36, 76:                        // Return, Enter (numpad)
                launchSelected()
                return
            case 125, 126, 123, 124,            // Arrow keys
                 121, 116, 119, 115:            // Page Down/Up, End, Home
                // Intercept before SwiftUI TextField consumes them for cursor movement.
                keyDown(with: event)
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    // MARK: - show / hide

    /// Shows the app launcher bezel, resets search state, and kicks off an async
    /// cache refresh (CONTEXT D-02).
    ///
    /// Flow: sync current cached state → present immediately → refresh in background
    /// so the bezel opens instantly and updates when the fresh scan completes.
    func show() {
        viewModel.selectedIndex = 0
        viewModel.searchText = ""

        // Sync current cached state so the bezel renders immediately
        if let service = appScannerService {
            viewModel.apps = service.apps
            viewModel.recentBundleIDs = service.recentBundleIDs
            viewModel.isLoading = service.isLoading
        }

        configureAndPresent()

        // Kick off async cache refresh (D-02); update viewModel when complete
        Task { [weak self] in
            guard let self else { return }
            await self.appScannerService?.refresh()
            if let service = self.appScannerService {
                self.viewModel.apps = service.apps
                self.viewModel.recentBundleIDs = service.recentBundleIDs
                self.viewModel.isLoading = service.isLoading
            }
        }

        logger.info("AppLaunchController shown")
    }

    /// Common setup — size, alpha, center, and present.
    private func configureAndPresent() {
        viewModel.wraparoundBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.wraparoundBezel)
        let width = UserDefaults.standard.double(forKey: AppSettingsKeys.bezelWidth)
        let height = UserDefaults.standard.double(forKey: AppSettingsKeys.bezelHeight)
        if width > 0 && height > 0 {
            setContentSize(NSSize(width: width, height: height))
        }
        alphaValue = 1.0
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        registerClickOutsideMonitor()
    }

    /// Hides the bezel, removes global event monitors, and resets state.
    func hide() {
        orderOut(nil)
        removeClickOutsideMonitor()
        viewModel.selectedIndex = 0
        viewModel.searchText = ""
        logger.info("AppLaunchController hidden")
    }

    // MARK: - Keyboard routing

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:                        // Escape
            hide()
        case 36, 76:                    // Return, Enter (numpad)
            launchSelected()
        case 125, 124:                  // Down arrow, Right arrow
            viewModel.navigateDown()
        case 126, 123:                  // Up arrow, Left arrow
            viewModel.navigateUp()
        case 121:                       // Page Down
            viewModel.navigateDownTen()
        case 116:                       // Page Up
            viewModel.navigateUpTen()
        case 119:                       // End
            viewModel.navigateToLast()
        case 115:                       // Home
            viewModel.navigateToFirst()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Launch

    /// Hides the bezel first, records the launch, then opens the selected app.
    ///
    /// Order is critical (CONTEXT D-09): dismiss the bezel BEFORE activating
    /// the target app so the target app receives focus properly.
    func launchSelected() {
        guard let entry = viewModel.currentApp else { hide(); return }
        hide()   // dismiss FIRST, then launch
        if let bundleID = entry.bundleID {
            appScannerService?.recordLaunch(bundleID: bundleID)
        }
        let config = NSWorkspace.OpenConfiguration()
        // config.activates = true by default — brings target app to front
        NSWorkspace.shared.openApplication(
            at: entry.url,
            configuration: config,
            completionHandler: { _, error in
                if let error {
                    logger.error("Failed to launch \(entry.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        )
    }

    // MARK: - Private helpers

    /// Centers the bezel on the main screen.
    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = frame.size
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
        setFrameOrigin(origin)
    }

    private func registerClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                Task { @MainActor in self.hide() }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
