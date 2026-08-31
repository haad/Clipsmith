import AppKit
import SwiftUI
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "TodoQuickAddController"
)

/// Text state shared between the panel (commit/reset) and the SwiftUI field.
@MainActor
@Observable
final class TodoQuickAddModel {
    var text = ""
}

/// Single-field quick-add view hosted inside the panel.
struct TodoQuickAddView: View {
    @Bindable var model: TodoQuickAddModel
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            TextField(
                "Add todo — e.g. Fix pricing #lara @due(2026-09-05) @today",
                text: $model.text
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .onSubmit(onCommit)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Stripped-down non-activating quick-add panel (BezelController pattern):
/// `.nonactivatingPanel` so the frontmost app keeps focus, high window level,
/// Escape and click-outside dismiss, Enter saves via TodoStore.
@MainActor
final class TodoQuickAddController: NSPanel {

    /// Injected by AppDelegate before first show().
    var todoStore: TodoStore?

    private let model = TodoQuickAddModel()
    private var globalMonitor: Any?

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

    init() {
        // CRITICAL: .nonactivatingPanel MUST be in the init styleMask —
        // WindowServer does not honour setting it afterwards.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 56),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let hostingView = NSHostingView(
            rootView: TodoQuickAddView(model: model) { [weak self] in self?.commit() })
        hostingView.sizingOptions = []   // CRITICAL: prevents constraint-loop crash
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Intercept Escape/Return before the hosted TextField swallows them.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53:            // Escape
                hide()
                return
            case 36, 76:        // Return, Enter (numpad)
                commit()
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

    func show() {
        todoStore?.loadIfNeeded()
        model.text = ""
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        registerClickOutsideMonitor()
        logger.info("Todo quick-add shown")
    }

    func hide() {
        orderOut(nil)
        removeClickOutsideMonitor()
        model.text = ""
    }

    // MARK: - Commit

    /// Enter: parse the inline syntax and save. Unmatched #project names
    /// create the project (TodoStore matches case-insensitively); no
    /// #project → Inbox. Empty input just dismisses. Project-only input
    /// (e.g. "#lara", no title or tags) creates the project instead of
    /// silently dropping the input.
    private func commit() {
        let input = model.text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { hide(); return }
        let result = TodoQuickAddParser.parse(input)
        if result.title.isEmpty && result.tags.isEmpty {
            if let projectName = result.projectName {
                todoStore?.addProject(name: projectName)
            }
            hide()
            return
        }
        todoStore?.addTask(
            text: result.title,
            projectName: result.projectName,
            tags: result.tags)
        hide()
    }

    // MARK: - Placement / dismissal

    /// Upper third of the main screen — quick-add is glanceable, not modal.
    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.minY + screenFrame.height * 0.66
        )
        setFrameOrigin(origin)
    }

    private func registerClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
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
