---
phase: 03-ui-layer
verified: 2026-03-05T21:50:00Z
status: human_needed
score: 10/10 must-haves verified (automated); 5 behaviors require human
re_verification: false
human_verification:
  - test: "Non-activating behavior (BEZL-01)"
    expected: "Open TextEdit, press bezel hotkey — bezel appears as floating overlay; TextEdit title bar stays active (not dimmed); Flycut does NOT become the frontmost app"
    why_human: "Non-activating NSPanel behavior is a WindowServer-level property that cannot be verified programmatically without a running display server and focus state inspection"
  - test: "Arrow key navigation and Enter paste (INTR-02, BEZL-05 partial)"
    expected: "Down/Up arrow navigate clippings; Page Down/Up jump 10; Home/End jump to first/last; clipping content and N-of-M counter update; pressing Enter pastes selected clipping as plain text into previously active app and dismisses bezel"
    why_human: "CGEvent-based paste injection requires Accessibility permission and a real app to receive the paste; navigation visual feedback requires display"
  - test: "Bezel over fullscreen apps and all Spaces (BEZL-04)"
    expected: "Enter fullscreen in any app, press hotkey — bezel appears above the fullscreen app; bezel visible after switching Spaces"
    why_human: "CGWindowLevel and collectionBehavior effects only manifest with a real display server in fullscreen mode"
  - test: "Search filtering and search hotkey (INTR-04)"
    expected: "Typing in bezel filters clippings case-insensitively; clearing search shows all; pressing search hotkey opens bezel with search field already focused"
    why_human: "Search field focus behavior and real-time filter rendering require visual inspection in a running app"
  - test: "Menu bar dropdown clippings with preview (SHELL-02)"
    expected: "Clicking Flycut menu bar icon shows recent clippings truncated to displayLen characters; clicking a clipping pastes it into the frontmost app"
    why_human: "Menu bar interaction and paste injection require runtime verification with Accessibility permission granted"
---

# Phase 3: UI Layer Verification Report

**Phase Goal:** Users can navigate and use clipboard history through the keyboard-driven bezel HUD, menu bar dropdown, and search — the full interaction model is visible and functional
**Verified:** 2026-03-05T21:50:00Z
**Status:** human_needed — all automated checks passed; 5 behaviors require human verification
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

All truths derived from the Phase 3 ROADMAP.md success criteria and both PLAN frontmatter `must_haves` sections.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | BezelViewModel navigation methods mutate selectedIndex correctly for up/down/first/last/upTen/downTen | VERIFIED | `BezelViewModel.swift` lines 57–86: all 6 methods implemented with clamp logic; 12 dedicated unit tests pass (testNavigateDown*, testNavigateUp*, testNavigateTo*, testNavigate*Ten*) |
| 2 | BezelViewModel filteredClippings returns only matching items when searchText is non-empty | VERIFIED | `BezelViewModel.swift` line 37: `localizedCaseInsensitiveContains`; 4 filter tests pass |
| 3 | BezelViewModel resets selectedIndex to 0 when searchText changes | VERIFIED | `BezelViewModel.swift` line 29: `didSet { selectedIndex = 0 }`; `testSearchTextResetsSelectedIndex` passes |
| 4 | BezelController is an NSPanel with .nonactivatingPanel in init styleMask | VERIFIED | `BezelController.swift` line 69: `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]` in `super.init`; `testStyleMaskContainsNonActivatingPanel` passes |
| 5 | BezelController.level is above screenSaverWindow level | VERIFIED | `BezelController.swift` line 75: `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)`; `testWindowLevelAboveScreenSaver` passes |
| 6 | BezelController.collectionBehavior includes canJoinAllSpaces and fullScreenAuxiliary | VERIFIED | `BezelController.swift` line 76: `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`; both collection behavior tests pass |
| 7 | BezelController centers on the screen containing NSEvent.mouseLocation | VERIFIED | `BezelController.swift` lines 163–176: `centerOnMouseScreen()` uses `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })` with fallback to `NSScreen.main` |
| 8 | BezelController.hide() removes the global event monitor and orders out the panel | VERIFIED | `BezelController.swift` lines 121–127: `orderOut(nil)`, `removeClickOutsideMonitor()`, state reset — `removeClickOutsideMonitor()` calls `NSEvent.removeMonitor(monitor); globalMonitor = nil` |
| 9 | BezelView displays selected clipping content and N-of-M counter | VERIFIED | `BezelView.swift` line 96: `Text(viewModel.currentClipping ?? "")` in ScrollView; line 59: `Text(viewModel.navigationLabel)` in footer |
| 10 | BezelView includes a search TextField that binds to BezelViewModel.searchText | VERIFIED | `BezelView.swift` line 34: `TextField("Search...", text: $viewModel.searchText)` |

**Score: 10/10 truths verified (automated)**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FlycutSwift/Views/BezelViewModel.swift` | Pure-Swift @Observable navigation/search state | VERIFIED | 87 lines; all 6 nav methods + filteredClippings + currentClipping + navigationLabel; no SwiftData import |
| `FlycutSwift/Views/BezelController.swift` | NSPanel subclass with non-activating behavior, keyboard routing, show/hide lifecycle | VERIFIED | 206 lines; init with .nonactivatingPanel; keyDown routes 10 key codes; show/hide/showWithSearch/pasteAndHide all implemented |
| `FlycutSwift/Views/BezelView.swift` | SwiftUI view displaying clipping content, navigation counter, search field | VERIFIED | 109 lines; @Query for SwiftData clippings; search TextField; content ScrollView; nav label; empty/no-matches states |
| `FlycutTests/BezelViewModelTests.swift` | Unit tests for navigation index mutations and search filter | VERIFIED | 173 lines; 21 test methods covering all nav methods, filter, reset, currentClipping, navigationLabel |
| `FlycutTests/BezelControllerTests.swift` | Unit tests for panel configuration (styleMask, level, collectionBehavior, hide cleanup) | VERIFIED | 82 lines; 7 test methods; all configuration properties covered |
| `FlycutSwift/App/AppDelegate.swift` | BezelController instantiation and hotkey wiring | VERIFIED | `bezelController = BezelController(modelContainer: FlycutApp.sharedModelContainer)` at line 68; hotkeys wired at lines 73–88; terminate cleanup at line 92 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `BezelView.swift` | `BezelViewModel.swift` | `@Bindable var viewModel: BezelViewModel` | WIRED | Line 24: `@Bindable var viewModel: BezelViewModel`; searchText TextField at line 34; filteredClippings at line 46; currentClipping at line 96; navigationLabel at line 59 |
| `BezelController.swift` | `BezelView.swift` | `NSHostingView(rootView: BezelView())` | WIRED | Line 85: `let bezelView = BezelView(viewModel: viewModel)`; line 92: `let hostingView = NSHostingView(rootView: rootView)` with optional model container wrapping |
| `BezelController.swift` | keyDown override | keyCode switch routing to viewModel navigation | WIRED | Lines 131–158: full switch on event.keyCode routing to all 6 viewModel navigation methods + Escape + Return/Enter + super.keyDown |
| `AppDelegate.swift` | `BezelController.swift` | `KeyboardShortcuts.onKeyDown -> bezelController.show()/hide()` | WIRED | Lines 73–88: activateBezel toggles `bezelController.hide()`/`bezelController.show()`; activateSearch calls `bezelController.showWithSearch()` |
| `BezelController.swift` | `PasteService.swift` | `pasteAndHide()` calls `pasteService?.paste()` | WIRED | Line 203: `await pasteService?.paste(content: content, into: appTracker?.previousApp)` |
| `MenuBarView.swift` | `PasteService.swift` | Button action calls `pasteService.paste()` | WIRED | Lines 24–28: `await pasteService.paste(content: clipping.content, into: appTracker.previousApp)` inside ForEach button |
| `MenuBarView.swift` | Preview text | `clipping.content.prefix(displayLen)` | WIRED | Line 32: `Text(clipping.content.prefix(displayLen))` with `@AppStorage(AppSettingsKeys.displayLen)` at line 15 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BEZL-01 | 03-01, 03-02 | Floating bezel HUD appears without activating Flycut (non-activating NSPanel) | AUTOMATED VERIFIED / HUMAN NEEDED | `.nonactivatingPanel` in init styleMask confirmed; `canBecomeKey=true`, `canBecomeMain=false`; non-activating runtime behavior needs human check |
| BEZL-02 | 03-01, 03-02 | Bezel displays current clipping content with navigation indicators | VERIFIED | `Text(viewModel.currentClipping ?? "")` + `Text(viewModel.navigationLabel)` in BezelView; "N of M" format confirmed in tests |
| BEZL-03 | 03-01, 03-02 | Bezel appears centered on the screen containing the mouse cursor | VERIFIED | `centerOnMouseScreen()` uses `NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })` |
| BEZL-04 | 03-01, 03-02 | Bezel works over fullscreen apps and all Spaces | AUTOMATED VERIFIED / HUMAN NEEDED | `level` above `.screenSaverWindow`; `collectionBehavior` includes `.canJoinAllSpaces` + `.fullScreenAuxiliary`; fullscreen overlay needs human check |
| BEZL-05 | 03-01, 03-02 | Bezel dismisses on paste, Escape key, or clicking outside | AUTOMATED VERIFIED / HUMAN NEEDED | keyCode 53=Escape calls `hide()`; keyCode 36/76=Enter calls `pasteAndHide()`; global monitor fires `hide()` on click outside panel frame; paste injection needs human check |
| INTR-02 | 03-01, 03-02 | User can navigate through clipping history using keyboard (arrow keys, jump 10, first/last) | VERIFIED (logic) / HUMAN NEEDED (UX) | All 6 nav methods tested; keyDown routes arrow/PageUp/Down/Home/End; 21 tests pass; visual feedback needs human check |
| INTR-04 | 03-01, 03-02 | User can search/filter clippings by text content | VERIFIED (logic) / HUMAN NEEDED (UX) | `localizedCaseInsensitiveContains` filter; searchText TextField bound; selectedIndex resets on search change; focus behavior needs human check |
| SHELL-02 | 03-02 | Menu bar dropdown shows recent clippings with preview text | VERIFIED (automated) / HUMAN NEEDED (runtime) | `MenuBarView.swift`: `clipping.content.prefix(displayLen)` in ForEach; `pasteService.paste()` on button tap; runtime menu bar interaction needs human check |

**No orphaned requirements.** All 8 requirement IDs from both plan frontmatter sections (03-01 and 03-02) are accounted for. REQUIREMENTS.md traceability table maps BEZL-01 through BEZL-05, INTR-02, INTR-04, SHELL-02 to Phase 3 — all match plan declarations.

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| None | — | — | No TODO/FIXME/HACK/placeholder comments found in any Phase 3 file. No empty return stubs. No console-log-only handlers. Stub hotkey log lines (`logger.info("Bezel hotkey fired")`) confirmed replaced by real show/hide calls. |

---

### Human Verification Required

The following 5 behaviors require a human to run the app with Accessibility permission granted and hotkeys assigned in Preferences.

**Prerequisites:**
1. Grant Accessibility permission to FlycutSwift in System Settings > Privacy & Security > Accessibility
2. Assign hotkeys for "Activate Bezel" and "Activate Search" in Flycut Preferences > Shortcuts tab

---

#### 1. Non-Activating Panel Behavior (BEZL-01)

**Test:** Open TextEdit. Press the bezel hotkey.
**Expected:** The bezel appears as a floating overlay. TextEdit title bar stays active (not dimmed) — Flycut must NOT become the frontmost app.
**Why human:** The non-activating behavior is a WindowServer-level effect determined by the `.nonactivatingPanel` styleMask bit set at init time. The bit is verified programmatically in tests, but the actual focus-stealing behavior can only be observed with a live display server, a real frontmost application, and a human verifier watching the title bar state.

---

#### 2. Full Interaction Flow — Navigation and Paste (INTR-02, BEZL-05)

**Test:** With multiple clippings in history, open bezel, navigate with Down/Up arrow keys, Page Down/Up, Home, End. Observe content and counter update. Press Enter on a selected clipping.
**Expected:** Each navigation key moves selection correctly. The clipping content area updates to show the selected clipping. The "N of M" counter updates. Pressing Enter pastes the selected clipping as plain text into the previously active app (e.g., TextEdit) and dismisses the bezel.
**Why human:** CGEvent-based paste injection (`pasteService.paste()`) requires Accessibility permission, a real pasteboard write cycle, and a receiving application. Navigation visual feedback requires a displayed panel.

---

#### 3. Fullscreen Overlay and All Spaces (BEZL-04)

**Test:** Enter fullscreen in any app. Press bezel hotkey. Then switch Spaces and press hotkey again.
**Expected:** The bezel appears above the fullscreen application. The bezel is visible on all Spaces after Space switching.
**Why human:** NSWindow level and collectionBehavior effects (`.canJoinAllSpaces`, `.fullScreenAuxiliary`) only manifest with a real display server in fullscreen mode and across Space boundaries.

---

#### 4. Search Filtering and Search Hotkey (INTR-04)

**Test:** Open bezel, type characters. Observe filtering. Clear text. Then press the search hotkey.
**Expected:** Typing filters clippings case-insensitively in real time. Clearing search shows all clippings. Pressing the search hotkey opens the bezel with the search field already focused (cursor in field, ready to type).
**Why human:** Search field focus behavior (first responder assignment through NSPanel/NSHostingView chain) and real-time SwiftUI state rendering require visual inspection.

---

#### 5. Menu Bar Dropdown with Clipping Previews (SHELL-02)

**Test:** Click the Flycut menu bar icon. Observe the clipping list. Click a clipping.
**Expected:** Recent clippings appear in the dropdown, each truncated to `displayLen` characters (default 40). Clicking a clipping pastes it into the previously frontmost app as plain text.
**Why human:** Menu bar dropdown rendering and click-to-paste require runtime verification with Accessibility permission.

---

### Test Run Results

```
BezelViewModelTests: 21/21 PASSED
  - testNavigateDownIncrementsIndex
  - testNavigateDownNoOpAtLastItem
  - testNavigateUpDecrementsIndex
  - testNavigateUpNoOpAtFirstItem
  - testNavigateToFirstSetsIndexToZero
  - testNavigateToLastSetsIndexToLastItem
  - testNavigateToLastOnEmptyReturnsZero
  - testNavigateUpTenDecrementsBy10
  - testNavigateUpTenClampsAtZero
  - testNavigateDownTenIncrementsBy10
  - testNavigateDownTenClampsAtLastIndex
  - testFilteredClippingsReturnsAllWhenSearchTextEmpty
  - testFilteredClippingsFiltersWhenSearchTextSet
  - testFilteredClippingsCaseInsensitive
  - testFilteredClippingsReturnsEmptyWhenNoMatch
  - testSearchTextResetsSelectedIndex
  - testCurrentClippingReturnsNilWhenEmpty
  - testCurrentClippingReturnsItemAtSelectedIndex
  - testCurrentClippingWithSearchFilter
  - testNavigationLabelEmptyWhenNoClippings
  - testNavigationLabelFormat

BezelControllerTests: 7/7 PASSED
  - testStyleMaskContainsNonActivatingPanel
  - testWindowLevelAboveScreenSaver
  - testCollectionBehaviorContainsCanJoinAllSpaces
  - testCollectionBehaviorContainsFullScreenAuxiliary
  - testCanBecomeKeyTrue
  - testCanBecomeMainFalse
  - testIsReleasedWhenClosedFalse

Total: 28/28 unit tests passing
```

---

### Commit Verification

All commits referenced in SUMMARY files exist in git history:
- `7f8d458` — feat(03-01): BezelViewModel navigation/search with TDD — 21 tests green
- `793b846` — feat(03-01): BezelController NSPanel + BezelView SwiftUI + 7 controller tests
- `e99e00c` — feat(03-02): wire BezelController into AppDelegate hotkey handlers

---

### Summary

Phase 3 automated verification is complete with all 10 must-haves verified. The implementation is substantive (not stubs), fully wired (not orphaned), and has zero anti-patterns. All 28 unit tests pass. All 8 requirement IDs (BEZL-01 through BEZL-05, INTR-02, INTR-04, SHELL-02) are implemented and the REQUIREMENTS.md traceability table matches.

Five behaviors cannot be verified without running the app: non-activating focus behavior (BEZL-01), paste injection end-to-end (BEZL-05/INTR-02), fullscreen overlay (BEZL-04), search field focus (INTR-04), and menu bar paste (SHELL-02). These require a human to run the app with Accessibility permission and assigned hotkeys.

---

_Verified: 2026-03-05T21:50:00Z_
_Verifier: Claude (gsd-verifier)_
