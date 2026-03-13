import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hotkey that shows the bezel (clipboard picker overlay).
    /// Actual registration with CGEventTap happens in Phase 2.
    static let activateBezel = Self("activateBezel")

    /// Hotkey that activates the search/filter interface.
    /// Actual registration with CGEventTap happens in Phase 2.
    static let activateSearch = Self("activateSearch")

    /// Hotkey that opens the snippet editor window (Plan 04-03).
    static let activateSnippets = Self("activateSnippets")

    /// Hotkey that opens the prompt bezel for quick prompt access.
    static let activatePrompts = Self("activatePrompts")
}
