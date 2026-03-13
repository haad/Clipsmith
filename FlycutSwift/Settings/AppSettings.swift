import SwiftUI

/// Observable settings class backed by UserDefaults via @AppStorage.
///
/// CRITICAL: @Observable + @AppStorage requires @ObservationIgnored on each
/// property. Without it, the compiler emits: "Cannot use @AppStorage on a
/// stored property of an @Observable class" in Swift 6 strict concurrency mode.
///
/// Inject into the environment at the app level and observe with @Environment
/// in any view that needs settings access.
@Observable
final class AppSettings {

    /// Maximum number of clippings to retain in history (1–999).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.rememberNum)
    var rememberNum: Int = 40

    /// Number of clippings to show in the menu (1–99).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.displayNum)
    var displayNum: Int = 10

    /// Maximum characters shown in each clipping preview (10–200).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.displayLen)
    var displayLen: Int = 40

    /// When true, paste is always performed as plain text regardless of original format.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.plainTextPaste)
    var plainTextPaste: Bool = false

    /// When true, a sound plays each time a clipping is pasted.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.pasteSound)
    var pasteSound: Bool = false

    /// Reflects whether the app is registered for launch at login via SMAppService.
    /// On appear, views must sync this with `SMAppService.mainApp.status`.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.launchAtLogin)
    var launchAtLogin: Bool = false

    /// When true, the accessibility permission alert is suppressed on launch.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.suppressAccessibilityAlert)
    var suppressAccessibilityAlert: Bool = false

    /// When true, the bezel stays open after releasing modifier keys.
    /// User must press Enter to paste or Escape to dismiss.
    /// When false (default), releasing all modifiers auto-pastes the selected clipping.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.stickyBezel)
    var stickyBezel: Bool = false

    /// When true, pasting a clipping moves it to the top of the history (Bug #23).
    /// Matches ObjC Flycut behaviour where the most recently used clipping is at position 0.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.pasteMovesToTop)
    var pasteMovesToTop: Bool = true

    // MARK: - Wave 4 additions (Plan 04 — ObjC parity settings)

    /// When true, navigating past the last/first clipping wraps to the other end (Bug #8).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.wraparoundBezel)
    var wraparoundBezel: Bool = false

    /// Controls when clipping history is saved to disk (Bug #10).
    /// 0 = never (clear on quit), 1 = on exit, 2 = after each clip.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.savePreference)
    var savePreference: Int = 1

    /// When true (default), inserting an identical clipping moves it to top instead of
    /// creating a duplicate. When false, duplicates are allowed (Bug #9).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.removeDuplicates)
    var removeDuplicates: Bool = true

    /// When true, selecting a menu item pastes it immediately.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.menuSelectionPastes)
    var menuSelectionPastes: Bool = true

    /// Background transparency for the bezel (0.1 = almost opaque, 0.9 = very transparent).
    /// Applied as 1.0 - bezelAlpha to the material opacity (Bug #17).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.bezelAlpha)
    var bezelAlpha: Double = 0.25

    /// Width of the bezel panel in points (Bug #16).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.bezelWidth)
    var bezelWidth: Double = 500

    /// Height of the bezel panel in points (Bug #16).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.bezelHeight)
    var bezelHeight: Double = 320

    /// When true, the bezel displays source app icon, name, and timestamp (Bug #14).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.displayClippingSource)
    var displayClippingSource: Bool = true

    /// Menu bar icon style (0 = default scissors icon).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.menuIcon)
    var menuIcon: Int = 0

    // MARK: - Wave 6 additions (Plan 06 — final parity polish)

    /// When true, skips clipboard entries whose length matches common password lengths
    /// and contain no whitespace (heuristic password filter, Bug #33 area).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.skipPasswordLengths)
    var skipPasswordLengths: Bool = true

    /// Comma-separated list of character counts treated as likely password lengths.
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.skipPasswordLengthsList)
    var skipPasswordLengthsList: String = "12, 20, 32"

    /// When true, logs all pasteboard types to OSLog on each clipboard change (Bug #33).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.revealPasteboardTypes)
    var revealPasteboardTypes: Bool = false

    /// Directory path where clippings are saved when using the save-to-file feature (Bug #25).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.saveToLocation)
    var saveToLocation: String = "~/Desktop"

    /// Clipboard polling interval in seconds (0.1–5.0).
    @ObservationIgnored
    @AppStorage(AppSettingsKeys.clipboardPollingInterval)
    var clipboardPollingInterval: Double = 1.0
}
