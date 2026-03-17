import AppKit
import SwiftUI
import WebKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "DocBezelController"
)

@MainActor
final class DocBezelController: NSPanel {

    let viewModel = DocBezelViewModel()
    var appTracker: AppTracker?
    var docsetSearchService: DocsetSearchService?
    var docsetManagerService: DocsetManagerService?

    private var globalMonitor: Any?
    private var flagsMonitor: Any?
    var isHotkeyHold = false

    // designated init
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 400, height: 300)

        let bezelView = DocBezelView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: bezelView)
        contentView = hostingView

        // Remember window size/position across launches
        setFrameAutosaveName("DocBezelFrame")

        logger.debug("DocBezelController initialised")
    }

    // Required by NSPanel
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsMouseMovedEvents: Bool { get { true } set {} }

    // MARK: - Event interception (mirrors PromptBezelController)

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53: hide(); return                          // Escape
            case 36, 76: keyDown(with: event); return        // Return/Enter
            case 125, 126, 123, 124,                         // Arrow keys
                 121, 116, 119, 115:                         // Page/Home/End
                keyDown(with: event); return
            default:
                // Only intercept j/k for navigation when a text field is NOT focused
                if !isTextFieldFirstResponder,
                   let chars = event.charactersIgnoringModifiers?.lowercased(),
                   event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                    if chars == "j" || chars == "k" {
                        keyDown(with: event); return
                    }
                }
            }
        }
        super.sendEvent(event)
    }

    /// Whether the current first responder is a text input field.
    private var isTextFieldFirstResponder: Bool {
        guard let responder = firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    override func cancelOperation(_ sender: Any?) { hide() }

    // MARK: - show / hide

    /// Shows the doc bezel. Reads selected text from the frontmost app and pre-fills search.
    func show() {
        // Reload metadata to pick up docs downloaded in Settings
        docsetManagerService?.loadMetadata()

        viewModel.searchService = docsetSearchService
        viewModel.managerService = docsetManagerService
        viewModel.selectedIndex = 0
        viewModel.filteredResults = []

        // Capture selected text before showing (DOCS-01)
        let selectedText = SelectedTextService.selectedText(from: appTracker?.previousApp)
        viewModel.searchText = selectedText ?? ""

        configureAndPresent()
        if isHotkeyHold { registerFlagsMonitor() }
        logger.info("DocBezelController shown with query: '\(self.viewModel.searchText, privacy: .public)'")
    }

    func hide() {
        orderOut(nil)
        removeClickOutsideMonitor()
        removeFlagsMonitor()
        viewModel.selectedIndex = 0
        viewModel.searchText = ""
        viewModel.filteredResults = []
        isHotkeyHold = false
        logger.info("DocBezelController hidden")
    }

    // MARK: - Keyboard routing

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: hide()
        case 36, 76:
            // Enter — open current result's HTML in the WKWebView preview
            // (no paste action for doc lookup; user reads the doc)
            // If user holds Cmd+Enter, open in external browser
            if event.modifierFlags.contains(.command), let result = viewModel.currentResult {
                let url = URL(string: "https://devdocs.io/\(result.docsetID)/\(result.entry.path)")!
                NSWorkspace.shared.open(url)
                hide()
            }
            // Otherwise just keep the bezel open showing the selected result
        case 125, 124: viewModel.navigateDown()
        case 126, 123: viewModel.navigateUp()
        case 121: viewModel.navigateDownTen()
        case 116: viewModel.navigateUpTen()
        case 119: viewModel.navigateToLast()
        case 115: viewModel.navigateToFirst()
        default:
            let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
            switch chars {
            case "j": viewModel.navigateDown()
            case "k": viewModel.navigateUp()
            default: super.keyDown(with: event)
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.deltaY > 0 { viewModel.navigateUp() }
        else if event.deltaY < 0 { viewModel.navigateDown() }
    }

    // MARK: - Private helpers

    private func configureAndPresent() {
        viewModel.wraparoundBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.wraparoundBezel)
        alphaValue = 1.0
        // Only center if no saved frame (first launch or reset)
        if !setFrameUsingName(frameAutosaveName) {
            centerOnScreen()
        }
        makeKeyAndOrderFront(nil)
        registerClickOutsideMonitor()
    }

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
                    self.hide()
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
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
    }
}
