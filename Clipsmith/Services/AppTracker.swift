import AppKit

/// Tracks the previously frontmost application (excluding Clipsmith itself) so PasteService
/// knows where to inject the Cmd-V event after the user selects a clipping.
///
/// Source: AppController.m currentRunningApplication pattern.
/// Workspace notification approach confirmed by Pattern 4 in 02-RESEARCH.md.
@Observable @MainActor
final class AppTracker {

    // MARK: - Properties

    /// The most recent frontmost application that is NOT Clipsmith itself.
    private(set) var previousApp: NSRunningApplication?

    private var observer: Any?

    // MARK: - Lifecycle

    /// Start observing NSWorkspace.didActivateApplicationNotification.
    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The closure is dispatched on .main queue so it is safe to dispatch
            // to the @MainActor via Task. Swift 6 requires the explicit hop even
            // when queue: .main is specified, because the closure itself is Sendable.
            let capturedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let activatedApp = capturedApp else { return }
                // Only update previousApp when the activated app is NOT Clipsmith itself.
                // This ensures we always have a reference to the user's actual target app.
                let flycutBundleID = Bundle.main.bundleIdentifier
                if activatedApp.bundleIdentifier != flycutBundleID {
                    self.previousApp = activatedApp
                }
            }
        }
    }

    /// Stop observing and release the observer token.
    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
