/// Namespace for all UserDefaults keys used by Clipsmith.
///
/// Use these constants instead of raw strings to avoid typos and enable
/// refactoring. Do NOT add cases — this is a namespace enum only.
enum AppSettingsKeys {
    static let rememberNum = "rememberNum"
    static let displayNum = "displayNum"
    static let displayLen = "displayLen"
    static let plainTextPaste = "plainTextPaste"
    static let pasteSound = "pasteSound"
    static let launchAtLogin = "launchAtLogin"
    static let suppressAccessibilityAlert = "suppressAccessibilityAlert"
    static let stickyBezel = "stickyBezel"
    static let pasteMovesToTop = "pasteMovesToTop"

    // Wave 4 additions (Plan 04 — ObjC parity settings)
    static let wraparoundBezel = "wraparoundBezel"
    static let savePreference = "savePreference"
    static let removeDuplicates = "removeDuplicates"
    static let menuSelectionPastes = "menuSelectionPastes"
    static let bezelAlpha = "bezelAlpha"
    static let bezelWidth = "bezelWidth"
    static let bezelHeight = "bezelHeight"
    static let displayClippingSource = "displayClippingSource"
    static let menuIcon = "menuIcon"

    // Phase 4 additions (Plan 04 — Gist sharing)
    static let gistDefaultPublic = "gistDefaultPublic"

    // Wave 6 additions (Plan 06 — final parity polish)
    static let skipPasswordLengths = "skipPasswordLengths"
    static let skipPasswordLengthsList = "skipPasswordLengthsList"
    static let revealPasteboardTypes = "revealPasteboardTypes"
    static let saveToLocation = "saveToLocation"
    static let clipboardPollingInterval = "clipboardPollingInterval"

    // Phase 5 additions (Plan 05 — Prompt Library)
    static let promptLibraryURL = "promptLibraryURL"
    static let promptLibraryLastSync = "promptLibraryLastSync"
    static let promptLibraryVariables = "promptLibraryVariables"
}
