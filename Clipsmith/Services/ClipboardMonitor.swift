import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "ClipboardMonitor"
)

/// Metadata captured alongside clipboard content at copy time.
/// Sendable: safe to pass across actor boundaries (e.g. @MainActor → ClipboardStore actor).
struct ClipboardEntry: Sendable {
    let content: String
    let sourceAppName: String?
    let sourceAppBundleURL: String?
}

@Observable @MainActor
final class ClipboardMonitor {

    // MARK: - Properties

    private(set) var isMonitoring: Bool = false
    var isPaused: Bool = false
    var lastChangeCount: Int = 0
    private var timer: Timer?

    /// Injected handler — called with a ClipboardEntry whenever the pasteboard
    /// changes and passes all filters.
    var onNewClipping: ((ClipboardEntry) -> Void)?

    /// Set by PasteService after writing to the pasteboard to prevent self-capture.
    /// When checkPasteboard sees this value as the current changeCount, it skips
    /// that cycle to avoid re-capturing Clipsmith's own paste write.
    var blockedChangeCount: Int = Int.min

    // MARK: - Adaptive polling properties (PERF-02)

    private var activityMonitor: Any?
    private var lastActivityDate: Date = .now
    /// Effective active interval — set in start() from user config or defaultActiveInterval.
    private var activeInterval: TimeInterval = 0.5
    private let defaultActiveInterval: TimeInterval = 0.5
    private let idleInterval: TimeInterval = 3.0
    private let idleThreshold: TimeInterval = 30.0

    /// Incremented at the top of scheduleTimer(interval:) — exposed for unit tests
    /// to detect unnecessary timer recreation.
    private(set) var timerRecreationCount: Int = 0

    /// Exposes whether the NSEvent global activity monitor is currently registered.
    /// Internal (not private) so tests can verify start/stop lifecycle.
    var hasActivityMonitor: Bool { activityMonitor != nil }

    // MARK: - Lifecycle

    /// Start polling NSPasteboard at the active interval in RunLoop.common mode.
    ///
    /// Adaptive polling: starts at activeInterval (0.5s or user-configured). After
    /// idleThreshold seconds with no user activity, switches to idleInterval (3.0s).
    ///
    /// CRITICAL: Uses RunLoop.current.add(timer, forMode: .common) — NOT
    /// Timer.scheduledTimer. The .common mode ensures the timer fires while
    /// a menu is open (RunLoop.default stops during menu tracking per Pitfall 2).
    func start() {
        guard !isMonitoring else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        // Respect user-configured polling interval as activeInterval override if > 0.
        let stored = UserDefaults.standard.double(forKey: AppSettingsKeys.clipboardPollingInterval)
        activeInterval = stored > 0 ? stored : defaultActiveInterval
        scheduleTimer(interval: activeInterval)
        registerActivityMonitor()
        isMonitoring = true
        logger.info("ClipboardMonitor started (adaptive polling)")
    }

    /// Stop the polling timer and remove the activity monitor.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let m = activityMonitor {
            NSEvent.removeMonitor(m)
            activityMonitor = nil
        }
        isMonitoring = false
        logger.info("ClipboardMonitor stopped")
    }

    // MARK: - Adaptive timer management

    /// Creates a new repeating timer at the given interval and adds it to RunLoop.common.
    /// Increments timerRecreationCount for test observability.
    ///
    /// CRITICAL: Always uses RunLoop.common mode so the timer fires during
    /// NSMenu tracking — do not change to .default or scheduledTimer.
    private func scheduleTimer(interval: TimeInterval) {
        timerRecreationCount += 1
        timer?.invalidate()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkPasteboardAdaptive() }
        }
        RunLoop.current.add(timer!, forMode: .common)
        logger.debug("ClipboardMonitor timer scheduled at \(interval, privacy: .public)s interval")
    }

    /// Registers the NSEvent global monitor that tracks user activity for adaptive polling.
    ///
    /// Uses Task { @MainActor } hop for Swift 6 Sendable compliance — the same pattern
    /// used for flagsMonitor in BezelController.
    private func registerActivityMonitor() {
        if let existing = activityMonitor {
            NSEvent.removeMonitor(existing)
            activityMonitor = nil
        }
        activityMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastActivityDate = .now
            }
        }
    }

    // MARK: - Pasteboard Check

    /// Adaptive poll tick: computes whether we are idle, adjusts the timer interval if
    /// needed (only when abs(difference) > 0.01 to avoid churn), then calls checkPasteboard().
    ///
    /// Internal (not private) so tests can call it directly — same pattern as checkPasteboard().
    func checkPasteboardAdaptive() {
        let sinceActivity = Date.now.timeIntervalSince(lastActivityDate)
        let isIdle = sinceActivity > idleThreshold
        let expectedInterval = isIdle ? idleInterval : activeInterval

        // Only recreate the timer when the interval needs to change (RESEARCH.md Pitfall 5).
        if let currentInterval = timer?.timeInterval,
           abs(currentInterval - expectedInterval) > 0.01 {
            scheduleTimer(interval: expectedInterval)
            logger.debug("ClipboardMonitor interval switched to \(expectedInterval, privacy: .public)s (idle: \(isIdle, privacy: .public))")
        }

        checkPasteboard()
    }

    /// Called on each timer tick to detect and filter new pasteboard content.
    /// Internal (not private) so tests can call it directly.
    func checkPasteboard() {
        guard !isPaused else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Debug: log all pasteboard types when revealPasteboardTypes is enabled (Bug #33).
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.revealPasteboardTypes) {
            let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
            logger.info("Pasteboard types: \(types, privacy: .public)")
        }

        // Self-capture prevention (Pitfall 1): if this changeCount was written by
        // PasteService, skip it so we don't re-capture our own paste output.
        guard lastChangeCount != blockedChangeCount else {
            logger.debug("Skipping self-capture — blocked changeCount \(self.blockedChangeCount, privacy: .public)")
            return
        }

        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else { return }

        if shouldSkip(pasteboard: pasteboard) {
            logger.debug("Skipping transient/password pasteboard entry")
            return
        }

        // Capture source app metadata at copy time (Bug #1).
        // Self-capture prevention (Pitfall 2 from RESEARCH.md): if frontmostApplication
        // is Clipsmith itself (e.g. during bezel transition), leave metadata nil to avoid
        // recording "Clipsmith" as the source of a clipping.
        let frontApp = NSWorkspace.shared.frontmostApplication
        let isSelf = frontApp?.bundleIdentifier == Bundle.main.bundleIdentifier
        let entry = ClipboardEntry(
            content: content,
            sourceAppName: isSelf ? nil : frontApp?.localizedName,
            sourceAppBundleURL: isSelf ? nil : frontApp?.bundleURL?.path
        )
        onNewClipping?(entry)
    }

    // MARK: - Filter

    /// Returns true if the pasteboard contains any known transient or password-manager type.
    ///
    /// Type strings from nspasteboard.org and ClipsmithOperator.m shouldSkip: logic.
    /// Internal (not private) so tests can call it directly.
    func shouldSkip(pasteboard: NSPasteboard) -> Bool {
        let skipTypes: Set<String> = [
            // nspasteboard.org universal transient/concealed identifiers
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.AutoGeneratedType",
            // Password manager proprietary identifiers
            "com.agilebits.onepassword",
            "PasswordPboardType",
            "de.petermaurer.TransientPasteboardType",
            "com.typeit4me.clipping",
            "Pasteboard generator type",
        ]
        let available = Set(pasteboard.types?.map(\.rawValue) ?? [])
        if !skipTypes.isDisjoint(with: available) { return true }

        // Password-length heuristic filter (Bug #33 area): skip single-word strings
        // whose character count matches common password lengths. This is a best-effort
        // filter matching the ObjC Clipsmith behaviour.
        if UserDefaults.standard.bool(forKey: AppSettingsKeys.skipPasswordLengths),
           let content = pasteboard.string(forType: .string) {
            let rawLengths = UserDefaults.standard.string(forKey: AppSettingsKeys.skipPasswordLengthsList) ?? "12, 20, 32"
            let lengths = rawLengths
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if lengths.contains(content.count) && content.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                return true
            }
        }

        return false
    }
}
