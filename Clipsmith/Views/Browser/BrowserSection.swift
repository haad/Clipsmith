import Foundation

/// The sections of the unified browser window, in toolbar order.
///
/// ⌘1–⌘5 map to `keyboardIndex`. `.docs` is hidden while the
/// `docLookupEnabled` feature flag is off, `.todos` while
/// `todoTrackingEnabled` is off.
enum BrowserSection: String, CaseIterable, Identifiable, Sendable {
    case snippets
    case prompts
    case docs
    case toolkit
    case todos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snippets: return "Snippets"
        case .prompts: return "Prompts"
        case .docs: return "Docs"
        case .toolkit: return "Toolkit"
        case .todos: return "Todos"
        }
    }

    /// 1-based position used for the ⌘N shortcut.
    var keyboardIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static func available(docLookupEnabled: Bool, todoTrackingEnabled: Bool) -> [BrowserSection] {
        allCases.filter { section in
            switch section {
            case .docs: return docLookupEnabled
            case .todos: return todoTrackingEnabled
            default: return true
            }
        }
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

/// Hands a `BrowserOpenRequest` from `MenuBarView.openBrowser` to
/// `BrowserWindowView` whether or not the window exists yet.
///
/// The request is posted before `openWindow`; a freshly created window takes
/// it in `onAppear`, an already open one takes it when `.clipsmithOpenBrowser`
/// arrives. Whichever runs first consumes it, so no timing delay is needed.
@MainActor
final class BrowserOpenMailbox {
    static let shared = BrowserOpenMailbox()

    private var pending: BrowserOpenRequest?

    func post(_ request: BrowserOpenRequest) {
        pending = request
    }

    /// Returns the pending request and clears it.
    func take() -> BrowserOpenRequest? {
        defer { pending = nil }
        return pending
    }
}

extension Notification.Name {
    /// Posted by any caller (hotkey, menu, AppDelegate) that wants the browser
    /// window shown. `MenuBarView` observes it, activates the app, opens the
    /// window, then nudges it with `.clipsmithOpenBrowser`.
    static let clipsmithRequestBrowser = Notification.Name("clipsmithRequestBrowser")
    /// Posted after `openWindow`; an already open `BrowserWindowView` takes
    /// the request from `BrowserOpenMailbox`. Carries no payload.
    static let clipsmithOpenBrowser = Notification.Name("clipsmithOpenBrowser")
}
