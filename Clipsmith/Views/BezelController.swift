import AppKit
import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "BezelController"
)

/// Non-activating NSPanel that hosts the BezelView SwiftUI content.
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
/// - The shared BezelViewModel instance bridges the controller (keyboard routing)
///   and the view (display + search).
@MainActor
final class BezelController: NSPanel {

    // MARK: - State

    /// Shared view model — controller routes key events, view reads/displays state.
    let viewModel = BezelViewModel()

    /// Services injected after init (set by AppDelegate before first show).
    var pasteService: PasteService?
    var appTracker: AppTracker?
    var clipboardStore: ClipboardStore?
    var clipboardMonitor: ClipboardMonitor?

    /// Accumulated scroll delta for threshold-based navigation.
    /// Smooth-scrolling devices (trackpad, Magic Mouse) send many small deltas per
    /// gesture — accumulating prevents one-item-per-delta stutter.
    private var scrollAccumulator: CGFloat = 0

    /// Threshold of accumulated scroll delta before navigating one item.
    private let scrollThreshold: CGFloat = 3.0

    /// Global event monitor for click-outside dismissal. Removed on hide().
    private var globalMonitor: Any?

    /// Global event monitor for modifier-key release in hold mode. Removed on hide().
    private var flagsMonitor: Any?

    /// Local event monitor for modifier-key release when the bezel panel is key.
    /// NSEvent.addGlobalMonitorForEvents does NOT fire for events inside the app's
    /// own windows, so a local monitor is needed to detect modifier release while
    /// the bezel has focus.
    private var localFlagsMonitor: Any?

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
    /// BezelView @Query will be empty without a model container.
    convenience init() {
        self.init(modelContainer: nil)
    }

    /// Designated init used by AppDelegate — injects the shared model container
    /// so BezelView's @Query can fetch clippings from SwiftData.
    init(modelContainer: ModelContainer?) {
        // CRITICAL: .nonactivatingPanel MUST be passed to super.init styleMask.
        // Setting window.styleMask afterwards does not update the WindowServer tag,
        // so the panel would still steal focus.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
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

        // Content view — inject the model container so BezelView @Query works.
        // If no container is provided (tests/previews), @Query returns empty results.
        let bezelView = BezelView(viewModel: viewModel)
        let rootView: AnyView
        if let modelContainer {
            rootView = AnyView(bezelView.modelContainer(modelContainer))
        } else {
            rootView = AnyView(bezelView)
        }
        let hostingView = NSHostingView(rootView: rootView)
        contentView = hostingView

        logger.debug("BezelController initialised — level: \(self.level.rawValue, privacy: .public)")
    }

    // MARK: - canBecomeKey / canBecomeMain

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Event interception

    // SwiftUI's TextField consumes Escape internally and may not propagate
    // cancelOperation up to the NSPanel. Override sendEvent to intercept
    // Escape before it reaches any hosted view.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53:                            // Escape
                hide()
                return
            case 48:                            // Tab — show quick action menu
                showQuickActionMenu()
                return
            case 36, 76:                        // Return, Enter (numpad)
                // Intercept before SwiftUI TextField consumes Return in search mode.
                keyDown(with: event)
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

    /// Shows the bezel panel centered on the main screen (Bug #15).
    /// Reads bezelWidth and bezelHeight from UserDefaults to support configurable size (Bug #16).
    /// Does NOT call NSApp.activate — the panel is non-activating by design.
    func show() {
        viewModel.isSearchMode = false
        configureAndPresent()
        if isHotkeyHold { registerFlagsMonitor() }
        logger.info("BezelController shown")
    }

    /// Shows the bezel with the search field ready (search text cleared).
    func showWithSearch() {
        viewModel.searchText = ""
        viewModel.isSearchMode = true
        configureAndPresent()
        logger.info("BezelController shown (search mode)")
    }

    /// Common setup for both show modes — size, alpha, center, and present.
    private func configureAndPresent() {
        viewModel.wraparoundBezel = UserDefaults.standard.bool(forKey: AppSettingsKeys.wraparoundBezel)
        let width = UserDefaults.standard.double(forKey: AppSettingsKeys.bezelWidth)
        let height = UserDefaults.standard.double(forKey: AppSettingsKeys.bezelHeight)
        if width > 0 && height > 0 {
            setContentSize(NSSize(width: width, height: height))
        }
        // Transparency is controlled by BezelView's background layers (not window alpha).
        alphaValue = 1.0
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        registerClickOutsideMonitor()
    }

    /// Hides the bezel, removes the global event monitors, and resets state.
    ///
    /// Reset viewModel state BEFORE orderOut so that mutations happen while the
    /// view is still in a stable state — ordering out can trigger a SwiftUI layout
    /// pass, and mutating @Observable properties during that pass causes
    /// "Modifying state during view update" faults.
    func hide(cancelPaste: Bool = true) {
        if cancelPaste {
            pasteService?.cancelPendingPaste()
        }
        removeClickOutsideMonitor()
        removeFlagsMonitor()
        viewModel.selectedIndex = 0
        viewModel.searchText = ""
        viewModel.isSearchMode = false
        viewModel.isShowingCheatSheet = false
        isHotkeyHold = false
        orderOut(nil)
        logger.info("BezelController hidden")
    }

    // MARK: - Keyboard routing

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        let hasCmd = event.modifierFlags.contains(.command)

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
        case 51:                        // Delete/Backspace
            if viewModel.isSearchMode && !viewModel.searchText.isEmpty {
                // In search mode with text, let backspace edit the search field
                super.keyDown(with: event)
            } else {
                // Otherwise, remove current clipping (Bug #11)
                Task { @MainActor in await self.deleteCurrentClipping() }
            }
        case 43 where hasCmd:           // Cmd+, → open preferences
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        default:
            // Handle s/S separately (case-sensitive): s = save, S = save and delete (Bug #25)
            if chars == "s" {
                saveCurrentToFile(deleteAfter: false)
            } else if chars == "S" {
                saveCurrentToFile(deleteAfter: true)
            } else {
                // Character-based shortcuts (Bug #11: j/k navigation, 0-9 index jumps)
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
                case "?":
                    if !viewModel.isSearchMode {
                        viewModel.isShowingCheatSheet.toggle()
                    } else {
                        super.keyDown(with: event)
                    }
                default:
                    // Pass other characters to SwiftUI TextField for search (only in search mode)
                    if viewModel.isSearchMode {
                        super.keyDown(with: event)
                    }
                }
            }
        }
    }

    // MARK: - Scroll wheel navigation (Bug #12)

    override func scrollWheel(with event: NSEvent) {
        // Ignore momentum (inertial) scrolling — only respond to direct user input.
        if event.momentumPhase != [] { return }

        // Line-based (discrete) scroll devices: navigate one item per click.
        if !event.hasPreciseScrollingDeltas {
            if event.scrollingDeltaY > 0 {
                viewModel.navigateUp()
            } else if event.scrollingDeltaY < 0 {
                viewModel.navigateDown()
            }
            return
        }

        // Smooth-scrolling (trackpad / Magic Mouse): accumulate deltas and
        // navigate only when the threshold is crossed to prevent stutter.
        scrollAccumulator += event.scrollingDeltaY

        while scrollAccumulator >= scrollThreshold {
            viewModel.navigateUp()
            scrollAccumulator -= scrollThreshold
        }
        while scrollAccumulator <= -scrollThreshold {
            viewModel.navigateDown()
            scrollAccumulator += scrollThreshold
        }

        // Reset accumulator when the gesture ends so the next swipe starts fresh.
        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumulator = 0
        }
    }

    // MARK: - Double-click paste (Bug #13)

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            Task { @MainActor in await pasteAndHide() }
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: - Right-click quick action menu (QACT-01, QACT-02, QACT-03)

    override func rightMouseDown(with event: NSEvent) {
        showQuickActionMenu(with: event)
    }

    /// Builds and presents the quick action NSMenu.
    ///
    /// Uses `NSMenu.popUpContextMenu(_:with:for:)` for reliable display from a
    /// non-activating NSPanel. When triggered by keyboard (no event), falls back
    /// to `popUp(positioning:at:in:)` with the contentView.
    ///
    /// CRITICAL: item.target MUST be set to self explicitly for every NSMenuItem —
    /// NSPanel does not participate in the normal responder chain (RESEARCH.md Pitfall 1).
    /// Without this, menu items appear greyed out.
    private func showQuickActionMenu(with event: NSEvent? = nil) {
        guard viewModel.currentClipping != nil else { return }

        let menu = NSMenu(title: "Quick Actions")

        // MARK: Transform submenu (QACT-01)
        let transformMenu = NSMenu(title: "Transform")

        let uppercaseItem = NSMenuItem(title: "UPPERCASE", action: #selector(actionUppercase), keyEquivalent: "")
        uppercaseItem.target = self
        transformMenu.addItem(uppercaseItem)

        let lowercaseItem = NSMenuItem(title: "lowercase", action: #selector(actionLowercase), keyEquivalent: "")
        lowercaseItem.target = self
        transformMenu.addItem(lowercaseItem)

        let titleCaseItem = NSMenuItem(title: "Title Case", action: #selector(actionTitleCase), keyEquivalent: "")
        titleCaseItem.target = self
        transformMenu.addItem(titleCaseItem)

        let trimItem = NSMenuItem(title: "Trim Whitespace", action: #selector(actionTrimWhitespace), keyEquivalent: "")
        trimItem.target = self
        transformMenu.addItem(trimItem)

        let urlEncodeItem = NSMenuItem(title: "URL Encode", action: #selector(actionUrlEncode), keyEquivalent: "")
        urlEncodeItem.target = self
        transformMenu.addItem(urlEncodeItem)

        let urlDecodeItem = NSMenuItem(title: "URL Decode", action: #selector(actionUrlDecode), keyEquivalent: "")
        urlDecodeItem.target = self
        transformMenu.addItem(urlDecodeItem)

        let transformParent = NSMenuItem(title: "Transform", action: nil, keyEquivalent: "")
        transformParent.submenu = transformMenu
        menu.addItem(transformParent)

        // MARK: Format submenu (QACT-02)
        let formatMenu = NSMenu(title: "Format")

        let quotesItem = NSMenuItem(title: "Wrap in Quotes", action: #selector(actionWrapInQuotes), keyEquivalent: "")
        quotesItem.target = self
        formatMenu.addItem(quotesItem)

        let codeBlockItem = NSMenuItem(title: "Markdown Code Block", action: #selector(actionMarkdownCodeBlock), keyEquivalent: "")
        codeBlockItem.target = self
        formatMenu.addItem(codeBlockItem)

        let jsonItem = NSMenuItem(title: "JSON Pretty Print", action: #selector(actionJsonPrettyPrint), keyEquivalent: "")
        jsonItem.target = self
        formatMenu.addItem(jsonItem)

        let formatParent = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        formatParent.submenu = formatMenu
        menu.addItem(formatParent)

        // MARK: Share submenu (QACT-03)
        let shareMenu = NSMenu(title: "Share")

        let rtfItem = NSMenuItem(title: "Copy as RTF", action: #selector(actionCopyAsRTF), keyEquivalent: "")
        rtfItem.target = self
        shareMenu.addItem(rtfItem)

        let gistItem = NSMenuItem(title: "Create Gist...", action: #selector(actionShareAsGist), keyEquivalent: "")
        gistItem.target = self
        shareMenu.addItem(gistItem)

        let shareParent = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        shareParent.submenu = shareMenu
        menu.addItem(shareParent)

        // Use popUpContextMenu for reliable display from a non-activating NSPanel.
        // When triggered by keyboard (Tab), create a synthetic mouse event at panel center.
        if let event, let view = contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let view = contentView {
            let localCenter = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            menu.popUp(positioning: nil, at: localCenter, in: view)
        }
    }

    // MARK: - Transform action handlers

    /// Shared helper: applies a text transform to the current clipping, writes result
    /// to pasteboard, sets blockedChangeCount to prevent self-capture, and inserts
    /// the transformed content into clipboard history.
    ///
    /// Does NOT auto-paste — user reviews the transformed result and presses Enter.
    private func applyTransform(_ transform: (String) -> String) {
        guard let content = viewModel.currentClipping else { return }
        let result = transform(content)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)

        // Prevent self-capture: set blockedChangeCount so ClipboardMonitor skips this write.
        clipboardMonitor?.blockedChangeCount = pasteboard.changeCount

        // Insert transformed content into history with "Clipsmith (transformed)" source.
        let rememberNum = UserDefaults.standard.integer(forKey: AppSettingsKeys.rememberNum)
        Task {
            try? await clipboardStore?.insert(
                content: result,
                sourceAppName: "Clipsmith (transformed)",
                rememberNum: rememberNum
            )
        }

        logger.info("Applied transform — result written to pasteboard")
    }

    @objc private func actionUppercase() {
        applyTransform(TextTransformer.uppercase)
    }

    @objc private func actionLowercase() {
        applyTransform(TextTransformer.lowercase)
    }

    @objc private func actionTitleCase() {
        applyTransform(TextTransformer.titleCase)
    }

    @objc private func actionTrimWhitespace() {
        applyTransform(TextTransformer.trimWhitespace)
    }

    @objc private func actionUrlEncode() {
        applyTransform(TextTransformer.urlEncode)
    }

    @objc private func actionUrlDecode() {
        applyTransform(TextTransformer.urlDecode)
    }

    // MARK: - Format action handlers

    @objc private func actionWrapInQuotes() {
        applyTransform(TextTransformer.wrapInQuotes)
    }

    @objc private func actionMarkdownCodeBlock() {
        applyTransform(TextTransformer.markdownCodeBlock)
    }

    @objc private func actionJsonPrettyPrint() {
        applyTransform(TextTransformer.jsonPrettyPrint)
    }

    // MARK: - Share action handlers

    /// Writes the current clipping as RTF to the pasteboard, sets blockedChangeCount
    /// to prevent self-capture, and hides the bezel (RTF is on pasteboard, user Cmd-V).
    @objc private func actionCopyAsRTF() {
        guard let content = viewModel.currentClipping else { return }
        guard let rtfData = TextTransformer.copyAsRTF(content) else {
            logger.error("RTF encoding failed")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
        // Prevent self-capture for the RTF write.
        clipboardMonitor?.blockedChangeCount = pasteboard.changeCount
        hide()
        logger.info("Copied as RTF to pasteboard")
    }

    /// Posts .clipsmithShareAsGist notification reusing the existing AppDelegate handler.
    /// Zero new Gist code needed — AppDelegate already handles this notification from MenuBarView.
    @objc private func actionShareAsGist() {
        guard let content = viewModel.currentClipping else { return }
        NotificationCenter.default.post(
            name: .clipsmithShareAsGist,
            object: nil,
            userInfo: ["content": content]
        )
        hide()
        logger.info("Posted clipsmithShareAsGist notification")
    }

    // MARK: - Private helpers

    /// Centers the bezel on the main screen (Bug #15: use main screen, not mouse screen).
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

        // Handler shared by both monitors.
        let handleFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isHotkeyHold else { return }
            let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if event.modifierFlags.intersection(modifiers).isEmpty {
                // Set immediately (before Task) to prevent both global and local
                // monitors from each firing pasteAndHide() for the same release.
                self.isHotkeyHold = false
                Task { @MainActor in
                    await self.pasteAndHide()
                }
            }
        }

        // Global monitor catches modifier release when another app has focus.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handleFlags)

        // Local monitor catches modifier release when the bezel panel is key.
        // addGlobalMonitorForEvents does NOT fire for events inside the app's
        // own windows, so without this the release is missed.
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlags(event)
            return event
        }
    }

    private func removeFlagsMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
    }

    private func registerClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            // Dismiss if the click landed outside our panel frame
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

    /// Pastes the selected clipping and hides the bezel.
    ///
    /// Follows the original Flycut timing pattern:
    ///   1. Write content to pasteboard immediately
    ///   2. Hide the bezel immediately (so it's gone before Cmd-V fires)
    ///   3. Cmd-V is injected ~0.5s later via performSelector:afterDelay:
    ///
    /// The bezel MUST be hidden before the synthetic Cmd-V is posted — otherwise
    /// the panel (canBecomeKey) can intercept the keystroke.
    func pasteAndHide() async {
        // If the bezel was already dismissed (e.g. user pressed Escape after modifier
        // release but before this Task ran), skip the paste entirely.
        guard isVisible else { return }
        guard let content = viewModel.currentClipping else {
            hide()
            return
        }
        // NEVER log clipping content — privacy requirement
        logger.info("Pasting selected clipping")

        // 1. Write to pasteboard and schedule delayed Cmd-V (fires in 0.5s).
        pasteService?.paste(content: content, into: appTracker?.previousApp)

        // 2. Hide the bezel IMMEDIATELY — before any await suspension points.
        //    This must happen before moveToTop() because during the await, other
        //    event monitors (click-outside, flags) could fire hide(cancelPaste: true)
        //    and cancel the pending Cmd-V injection.
        hide(cancelPaste: false)

        // 3. Bug #23: move pasted clipping to top of history when pasteMovesToTop is enabled.
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.pasteMovesToTop) {
            try? await clipboardStore?.moveToTop(content: content)
        }
    }

    /// Saves the current clipping to a timestamped .txt file on the configured save location (Bug #25).
    ///
    /// - Parameter deleteAfter: If true, deletes the clipping from history after saving (S key behaviour).
    private func saveCurrentToFile(deleteAfter: Bool = false) {
        guard let content = viewModel.currentClipping else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let filename = "Clipping \(formatter.string(from: .now)).txt"
        let saveDir = UserDefaults.standard.string(forKey: AppSettingsKeys.saveToLocation)
            ?? (NSHomeDirectory() + "/Desktop")
        let expandedDir = NSString(string: saveDir).expandingTildeInPath
        let path = (expandedDir as NSString).appendingPathComponent(filename)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            logger.info("Saved clipping to \(path, privacy: .public)")
        } catch {
            logger.error("Failed to save clipping: \(error.localizedDescription, privacy: .public)")
        }
        if deleteAfter {
            Task { @MainActor in await self.deleteCurrentClipping() }
        }
    }

    /// Deletes the currently selected clipping from SwiftData and removes it from the local list.
    /// Called by the Delete key handler (Bug #11).
    func deleteCurrentClipping() async {
        guard let info = viewModel.currentClippingInfo else { return }
        try? await clipboardStore?.delete(id: info.id)
        viewModel.removeCurrentClipping()
    }
}

// MARK: - NSRect center helper

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
