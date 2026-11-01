import Foundation

/// The sections of the unified browser window, in toolbar order.
///
/// ⌘1–⌘4 map to `keyboardIndex`. `.docs` is hidden while the
/// `docLookupEnabled` feature flag is off.
enum BrowserSection: String, CaseIterable, Identifiable, Sendable {
    case snippets
    case prompts
    case docs
    case toolkit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snippets: return "Snippets"
        case .prompts: return "Prompts"
        case .docs: return "Docs"
        case .toolkit: return "Toolkit"
        }
    }

    /// 1-based position used for the ⌘N shortcut.
    var keyboardIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static func available(docLookupEnabled: Bool) -> [BrowserSection] {
        docLookupEnabled ? allCases : allCases.filter { $0 != .docs }
    }
}

/// What a caller wants the browser window to show.
///
/// Travels through `Notification.userInfo` so AppKit code (hotkeys,
/// `AppDelegate`) can address the SwiftUI window without `@Environment`.
struct BrowserOpenRequest: Sendable {
    var section: BrowserSection?
    var query: String?

    init(section: BrowserSection?, query: String?) {
        self.section = section
        self.query = query
    }

    /// Returns nil when neither key is present.
    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return nil }
        let rawSection = userInfo[Self.sectionKey] as? String
        let query = userInfo[Self.queryKey] as? String
        guard rawSection != nil || query != nil else { return nil }
        self.section = rawSection.flatMap(BrowserSection.init(rawValue:))
        self.query = query
    }

    var userInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let section { info[Self.sectionKey] = section.rawValue }
        if let query { info[Self.queryKey] = query }
        return info
    }

    private static let sectionKey = "section"
    private static let queryKey = "query"
}

extension Notification.Name {
    /// Posted by any caller (hotkey, menu, AppDelegate) that wants the browser
    /// window shown. `MenuBarView` observes it, activates the app, opens the
    /// window, then re-posts as `.clipsmithOpenBrowser`.
    static let clipsmithRequestBrowser = Notification.Name("clipsmithRequestBrowser")
    /// Posted once the window exists; `BrowserWindowView` applies the request.
    static let clipsmithOpenBrowser = Notification.Name("clipsmithOpenBrowser")
}
