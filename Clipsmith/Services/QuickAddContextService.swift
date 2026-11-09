import AppKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "QuickAddContext"
)

/// What the quick-add hotkey attaches to a new task: the current browser
/// tab's URL and the selected text in the frontmost app.
@MainActor
enum QuickAddContextService {

    /// AppleScript per browser. Chromium browsers share one dictionary.
    private static let urlScripts: [String: String] = {
        let chromium = "tell application id \"%@\" to get URL of active tab of front window"
        var scripts = ["com.apple.Safari": "tell application id \"com.apple.Safari\" to get URL of front document"]
        for id in ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
                   "company.thebrowser.Browser", "com.vivaldi.Vivaldi"] {
            scripts[id] = String(format: chromium, id)
        }
        return scripts
    }()

    /// Must run before the panel becomes key: the selection fallback sends
    /// ⌘C to whatever is focused.
    static func capture(from app: NSRunningApplication?) -> String? {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let url = browserURL(of: app)
        let selection = SelectedTextService.selectedText(from: app)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [url, selection == url ? nil : selection]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func browserURL(of app: NSRunningApplication) -> String? {
        guard let id = app.bundleIdentifier, let source = urlScripts[id],
              let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: the user hasn't allowed Clipsmith to control this browser.
            logger.info("Browser URL unavailable: \(error, privacy: .public)")
            return nil
        }
        return result.stringValue
    }
}
