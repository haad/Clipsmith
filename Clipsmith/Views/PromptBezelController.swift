import AppKit
import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "PromptBezelController"
)

/// Non-activating NSPanel that hosts the PromptBezelView SwiftUI content.
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
/// - The shared PromptBezelViewModel instance bridges the controller (keyboard routing)
///   and the view (display + search).
/// - Tab key cycles categories; search text supports #category prefix syntax.
@MainActor
final class PromptBezelController: NSPanel {

    // MARK: - State

    /// Shared view model — controller routes key events, view reads/displays state.
    let viewModel = PromptBezelViewModel()

    /// Services injected after init (set by AppDelegate before first show).
    var pasteService: PasteService?
    var appTracker: AppTracker?
    var promptLibraryStore: PromptLibraryStore?

    /// Global event monitor for click-outside dismissal. Removed on hide().
    private var globalMonitor: Any?

    /// Global event monitor for modifier-key release in hold mode. Removed on hide().
    private var flagsMonitor: Any?

    /// Track whether the bezel was opened via hotkey hold (not sticky mode).
    /// When true, releasing all modifier keys triggers paste-and-hide.
    var isHotkeyHold = false

    // MARK: - Init

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

    /// Convenience init used in tests and previews — no model container injected.
    /// PromptBezelView @Query will be empty without a model container.
    convenience init() {
        self.init(modelContainer: nil)
    }

    /// Designated init used by AppDelegate — injects the shared model container
    /// so PromptBezelView's @Query can fetch prompt items from SwiftData.
    init(modelContainer: ModelContainer?) {
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

        // Content view — inject the model container so PromptBezelView @Query works.
        // If no container is provided (tests/previews), @Query returns empty results.
        let bezelView = PromptBezelView(viewModel: viewModel)
        let rootView: AnyView
        if let modelContainer {
            rootView = AnyView(bezelView.modelContainer(modelContainer))
        } else {
            rootView = AnyView(bezelView)
        }
        let hostingView = NSHostingView(rootView: rootView)
        contentView = hostingView

        logger.debug("PromptBezelController initialised — level: \(self.level.rawValue, privacy: .public)")
    }

    // MARK: - canBecomeKey / canBecomeMain

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Event interception

    // SwiftUI's TextField consumes Escape internally and may not propagate
    // cancelOperation up to the NSPanel. Override sendEvent to intercept
    // Escape and navigation keys before they reach any hosted view.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53:                            // Escape
                hide()
                return
            case 36, 76:                        // Return, Enter (numpad)
                keyDown(with: event)
                return
            case 125, 126, 123, 124,            // Arrow keys
                 121, 116, 119, 115:            // Page Down/Up, End, Home
                // Intercept before SwiftUI TextField consumes them for cursor movement.
                keyDown(with: event)
                return
            case 48:                            // Tab
                // Intercept Tab for category cycling (prevent focus change).
                keyDown(with: event)
                return
            default:
                // Intercept j/k for vim-style navigation before TextField consumes them.
                if let chars = event.charactersIgnoringModifiers?.lowercased(),
                   event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                    if chars == "j" || chars == "k" {
                        keyDown(with: event)
                        return
                    }
                }
            }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    // MARK: - show / hide

    /// Shows the prompt bezel panel, resetting to "All" category and clearing search.
    func show() {
        viewModel.selectedIndex = 0
        viewModel.searchText = ""
        viewModel.selectedCategory = "All"
        configureAndPresent()
        if isHotkeyHold { registerFlagsMonitor() }
        logger.info("PromptBezelController shown")
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
        removeFlagsMonitor()
        viewModel.selectedIndex = 0
        viewModel.searchText = ""
        viewModel.selectedCategory = "All"
        isHotkeyHold = false
        logger.info("PromptBezelController hidden")
    }

    // MARK: - Keyboard routing

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""

        switch event.keyCode {
        case 53:                        // Escape
            hide()
        case 36, 76:                    // Return, Enter (numpad)
            Task { @MainActor in await self.pasteAndHide() }
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
        case 48:                        // Tab — cycle categories
            viewModel.cycleCategory()
        default:
            // j/k vi-style navigation
            switch chars.lowercased() {
            case "j":
                viewModel.navigateDown()
            case "k":
                viewModel.navigateUp()
            case "0":
                viewModel.navigateTo(index: 9)   // Key "0" jumps to position 10 (0-indexed = 9)
            case "1"..."9":
                if let n = Int(chars) {
                    viewModel.navigateTo(index: n - 1)   // 1-indexed to 0-indexed
                }
            default:
                // Pass other characters to SwiftUI TextField for search input
                super.keyDown(with: event)
            }
        }
    }

    // MARK: - Scroll wheel navigation

    override func scrollWheel(with event: NSEvent) {
        if event.deltaY > 0 {
            viewModel.navigateUp()
        } else if event.deltaY < 0 {
            viewModel.navigateDown()
        }
    }

    // MARK: - Double-click paste

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            Task { @MainActor in await pasteAndHide() }
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: - Paste with template substitution

    /// Reads the selected prompt, substitutes {{variable}} tokens, and pastes into the frontmost app.
    ///
    /// Variable sources:
    /// 1. `{{clipboard}}` — the current clipboard string at paste time
    /// 2. User-defined variables from UserDefaults (promptLibraryVariables JSON)
    func pasteAndHide() async {
        guard let prompt = viewModel.currentPrompt else {
            hide()
            return
        }
        // Read clipboard content at paste time (not at selection time)
        let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""

        // Build variables dict: clipboard + user-defined variables from UserDefaults
        var variables: [String: String] = ["clipboard": clipboardContent]
        if let varsJSON = UserDefaults.standard.string(forKey: AppSettingsKeys.promptLibraryVariables),
           let varsData = varsJSON.data(using: .utf8),
           let userVars = try? JSONDecoder().decode([String: String].self, from: varsData) {
            variables.merge(userVars) { _, new in new }
        }

        let substituted = TemplateSubstitutor.substitute(in: prompt.content, variables: variables)
        logger.info("Pasting prompt: \(prompt.title, privacy: .public)")
        pasteService?.paste(content: substituted, into: appTracker?.previousApp)
        hide()
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

    private func registerFlagsMonitor() {
        removeFlagsMonitor()
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.isHotkeyHold else { return }
            let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if event.modifierFlags.intersection(modifiers).isEmpty {
                Task { @MainActor in
                    await self.pasteAndHide()
                    self.isHotkeyHold = false
                }
            }
        }
    }

    private func removeFlagsMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
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
