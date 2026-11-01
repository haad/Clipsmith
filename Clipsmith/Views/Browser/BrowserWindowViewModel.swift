import Foundation
import Observation

/// Section selection and deep-link state for the unified browser window.
@Observable @MainActor
final class BrowserWindowViewModel {

    /// The visible section. Persisted so the window reopens where it was left.
    var selectedSection: BrowserSection {
        didSet { defaults.set(selectedSection.rawValue, forKey: AppSettingsKeys.browserLastSection) }
    }

    /// Query handed over by the docs hotkey. The Docs section consumes it and
    /// sets it back to nil.
    var pendingDocsQuery: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: AppSettingsKeys.browserLastSection)
        selectedSection = stored.flatMap(BrowserSection.init(rawValue:)) ?? .snippets
    }

    func sections(docLookupEnabled: Bool) -> [BrowserSection] {
        BrowserSection.available(docLookupEnabled: docLookupEnabled)
    }

    /// Applies an open request: switch to the requested section when it is
    /// available, otherwise keep the current one (falling back to Snippets if
    /// that is hidden too). A request that explicitly asked for Docs always
    /// prefills the search field: with the query, or empty when nothing was
    /// selected, so the field is cleared and focused either way.
    func apply(_ request: BrowserOpenRequest, docLookupEnabled: Bool) {
        let available = sections(docLookupEnabled: docLookupEnabled)
        if let requested = request.section, available.contains(requested) {
            selectedSection = requested
        } else if !available.contains(selectedSection) {
            selectedSection = .snippets
        }
        if request.section == .docs, selectedSection == .docs {
            pendingDocsQuery = request.query ?? ""
        } else {
            pendingDocsQuery = nil
        }
    }
}
