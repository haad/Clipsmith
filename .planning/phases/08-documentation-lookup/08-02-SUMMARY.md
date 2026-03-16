---
phase: 08-documentation-lookup
plan: 02
subsystem: ui
tags: [swiftui, wkwebview, nspanel, observable, docset, documentation]

# Dependency graph
requires:
  - phase: 08-01
    provides: DocsetSearchService, DocsetManagerService, SelectedTextService, DocsetInfo, DocEntry
provides:
  - DocBezelViewModel: Observable @MainActor view model with search debounce, navigation, wraparound
  - DocBezelController: Non-activating NSPanel with keyboard routing and selected-text capture
  - DocBezelView: SwiftUI view with search bar, results list, WKWebView preview split
  - DocsetSettingsSection: Settings tab for docset download/delete/toggle management
  - DocBezelViewModelTests: 9 unit tests for navigation, wraparound, labels, currentResult
affects:
  - 08-03 (wiring: AppDelegate integration, hotkey registration, SettingsView tab)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Non-activating NSPanel with DocBezelController mirrors PromptBezelController pattern exactly
    - @Bindable viewModel in SwiftUI view bridging controller-owned state
    - NSViewRepresentable WKWebView with WKNavigationDelegate for link interception
    - DocSearchResult Identifiable Sendable struct combining DocsetInfo+DocEntry+htmlURL
    - 150ms Task.sleep debounce in searchText didSet using searchTask?.cancel()

key-files:
  created:
    - Clipsmith/Views/DocBezelViewModel.swift
    - Clipsmith/Views/DocBezelController.swift
    - Clipsmith/Views/DocBezelView.swift
    - Clipsmith/Views/Settings/DocsetSettingsSection.swift
    - ClipsmithTests/DocBezelViewModelTests.swift
  modified:
    - Clipsmith.xcodeproj/project.pbxproj

key-decisions:
  - "DocBezelController.init() is a single designated init (not convenience+designated pair) — no SwiftData container needed, simpler than PromptBezelController"
  - "DocBezelView uses HSplitView for results list + WKWebView — natural macOS split panel pattern for documentation UI"
  - "WKWebView Coordinator intercepts linkActivated navigation — external URLs open in browser, file:// links navigate in-panel"
  - "DocsetSettingsSection uses local @State DocsetManagerService — not injected, since settings view manages its own lifecycle"

patterns-established:
  - "DocBezelViewModel navigation pattern: identical to PromptBezelViewModel wraparound/clamp logic"
  - "DocSearchResult.id: composite 'docsetID-entry.id' avoids collisions across multiple docsets"

requirements-completed:
  - DOCS-01
  - DOCS-02
  - DOCS-03

# Metrics
duration: 4min
completed: 2026-03-16
---

# Phase 8 Plan 02: Documentation UI Layer Summary

**Non-activating NSPanel doc bezel with SwiftUI search+WKWebView split view, DocBezelViewModel with debounced async search and navigation, and DocsetSettingsSection for docset management**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-16T21:02:57Z
- **Completed:** 2026-03-16T21:06:57Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- DocBezelViewModel with debounced async search (150ms), filteredResults, navigation (up/down/first/last/+10/-10/wraparound), and 9 passing unit tests
- DocBezelController non-activating NSPanel mirroring PromptBezelController — keyboard routing, click-outside dismiss, flags monitor, selected-text pre-fill
- DocBezelView SwiftUI with search bar + HSplitView (results list left, WKWebView right) + ContentUnavailableView states
- DocsetSettingsSection with per-row download/delete/toggle controls and progress indicators

## Task Commits

1. **Task 1: Create DocBezelViewModel with tests** - `87027c2` (feat)
2. **Task 2: Create DocBezelController + DocBezelView + DocsetSettingsSection** - `1321d57` (feat)

## Files Created/Modified

- `Clipsmith/Views/DocBezelViewModel.swift` - Observable view model: DocSearchResult struct, searchText debounce, performSearch, navigation methods
- `Clipsmith/Views/DocBezelController.swift` - NSPanel: init with nonactivatingPanel styleMask, show() reads selected text, keyboard routing, event monitors
- `Clipsmith/Views/DocBezelView.swift` - SwiftUI: search bar, HSplitView results+WKWebView, DocResultRow type-coloring, DocWebView NSViewRepresentable
- `Clipsmith/Views/Settings/DocsetSettingsSection.swift` - Settings tab: DocsetRow with download/delete/toggle, progress indicator
- `ClipsmithTests/DocBezelViewModelTests.swift` - 9 tests: initial state, navigate clamp/wraparound (up+down), first/last, label, currentResult
- `Clipsmith.xcodeproj/project.pbxproj` - Added 5 new files to main target + tests target

## Decisions Made

- DocBezelController uses a single designated `init()` — no SwiftData container needed (docsets use JSON not SwiftData), simpler than PromptBezelController
- WKWebView link interception: `linkActivated` with non-file URLs dispatched to `NSWorkspace.shared.open()`, cancel navigation — prevents opening external docs in the in-panel web view
- DocsetSettingsSection creates its own `@State DocsetManagerService` — settings manages its own lifecycle, not injected from AppDelegate
- Project file manually patched to add 5 new Swift files to both the Clipsmith and ClipsmithTests targets

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- All four UI files exist and compile cleanly
- DocBezelController ready to be wired into AppDelegate (Plan 03)
- DocsetSettingsSection ready to be added to SettingsView tab bar (Plan 03, explicitly deferred per plan instructions)
- No blockers

---
*Phase: 08-documentation-lookup*
*Completed: 2026-03-16*
