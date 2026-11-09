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
    var text = "" {
        didSet { if text != oldValue { highlighted = 0 } }
    }
    /// Snippet names for `[[` completion (set by the controller).
    @ObservationIgnored var snippetNames: () -> [String] = { [] }
    /// Selected text / browser URL captured when the panel opened; saved
    /// as a note under the task. Cleared with the × button.
    var context: String? {
        didSet { onResize?() }
    }
    @ObservationIgnored var onResize: (() -> Void)?
    var highlighted = 0

    var suggestions: [String] {
        SnippetReference.suggestions(for: text, names: snippetNames())
    }

    /// Completes the trailing `[[partial` with the highlighted name.
    func acceptSuggestion() -> Bool {
        let list = suggestions
        guard !list.isEmpty else { return false }
        text = SnippetReference.completing(text, with: list[min(highlighted, list.count - 1)])
        return true
    }

    func moveHighlight(by delta: Int) {
        let count = suggestions.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }
}

/// Single-field quick-add view hosted inside the panel.
struct TodoQuickAddView: View {
    @Bindable var model: TodoQuickAddModel
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if let context = model.context {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote")
                    Text(context)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.context = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .help("Don't attach this note")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: TodoQuickAddController.contextHeight, alignment: .top)
            }
            // `[[` completion: ↑/↓ pick, Tab or Return completes.
            ForEach(Array(model.suggestions.enumerated()), id: \.element) { index, name in
                Label(name, systemImage: "doc.text")
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: TodoQuickAddController.suggestionRowHeight,
                           alignment: .leading)
                    .background(index == model.highlighted ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
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
    var snippetStore: SnippetStore? {
        didSet {
            model.snippetNames = { [weak store = snippetStore] in store?.snippets.map(\.name) ?? [] }
        }
    }

    static let baseHeight: CGFloat = 56
    static let suggestionRowHeight: CGFloat = 24
    static let contextHeight: CGFloat = 36

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
        model.onResize = { [weak self] in self?.fitToContent() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Intercept Escape/Return before the hosted TextField swallows them.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { super.sendEvent(event); return }
        if !model.suggestions.isEmpty {
            switch event.keyCode {
            case 48, 36, 76:    // Tab, Return, Enter: complete [[name]]
                _ = model.acceptSuggestion()
                fitToContent()
                return
            case 126:           // Up
                model.moveHighlight(by: -1)
                return
            case 125:           // Down
                model.moveHighlight(by: 1)
                return
            default:
                break
            }
        }
        defer { fitToContent() }
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

    /// Grows downward for the suggestion rows, keeping the top edge put.
    private func fitToContent() {
        let rows = CGFloat(model.suggestions.count)
        let height = Self.baseHeight
            + (rows > 0 ? rows * (Self.suggestionRowHeight + 6) : 0)
            + (model.context != nil ? Self.contextHeight + 6 : 0)
        guard abs(frame.height - height) > 0.5 else { return }
        var f = frame
        f.origin.y = frame.maxY - height
        f.size.height = height
        setFrame(f, display: true)
    }

    // MARK: - show / hide

    func show() {
        todoStore?.loadIfNeeded()
        model.text = ""
        model.context = UserDefaults.standard.bool(forKey: AppSettingsKeys.todoCaptureContext)
            ? QuickAddContextService.capture(from: NSWorkspace.shared.frontmostApplication)
            : nil
        fitToContent()
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        registerClickOutsideMonitor()
        logger.info("Todo quick-add shown")
    }

    func hide() {
        orderOut(nil)
        removeClickOutsideMonitor()
        model.text = ""
        model.context = nil
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
            tags: result.tags,
            note: model.context)
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
