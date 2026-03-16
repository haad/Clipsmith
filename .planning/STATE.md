---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 08-documentation-lookup-08-01-PLAN.md
last_updated: "2026-03-16T21:00:53.726Z"
last_activity: 2026-03-05 — Plan 01-01 complete
progress:
  total_phases: 10
  completed_phases: 8
  total_plans: 29
  completed_plans: 27
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-05)

**Core value:** Instant keyboard-driven access to clipboard history — press a hotkey, navigate clippings, paste without touching the mouse.
**Current focus:** Phase 1 — Foundation

## Current Position

Phase: 1 of 4 (Foundation)
Plan: 1 of 2 in current phase
Status: Executing
Last activity: 2026-03-05 — Plan 01-01 complete

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 1
- Average duration: 4 min
- Total execution time: 0.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation | 1/2 | 4 min | 4 min |

**Recent Trend:**
- Last 5 plans: 01-01 (4 min)
- Trend: -

*Updated after each plan completion*
| Phase 01-foundation P02 | 4 | 2 tasks | 9 files |
| Phase 01-foundation P02 | 4 min | 2 tasks | 9 files |
| Phase 02-core-engine P01 | 3 | 1 tasks | 4 files |
| Phase 02-core-engine P02 | 7 | 2 tasks | 6 files |
| Phase 02-core-engine P03 | checkpoint-verified | 3 tasks | 5 files |
| Phase 03-ui-layer P01 | 7 | 2 tasks | 6 files |
| Phase 03-ui-layer P02 | 5 | 2 tasks | 2 files |
| Phase 03.1-objc-parity-bug-fixes P01 | 8 | 2 tasks | 5 files |
| Phase 03.1-objc-parity-bug-fixes P02 | 4 min | 2 tasks | 6 files |
| Phase 03.1-objc-parity-bug-fixes P03 | 5 min | 2 tasks | 9 files |
| Phase 03.1-objc-parity-bug-fixes P04 | 8 | 2 tasks | 10 files |
| Phase 03.1-objc-parity-bug-fixes P05 | 3 | 2 tasks | 4 files |
| Phase 03.1-objc-parity-bug-fixes P06 | 4 | 2 tasks | 9 files |
| Phase 04-code-snippets-gist-sharing P01 | 6 | 1 tasks | 5 files |
| Phase 04-code-snippets-gist-sharing P02 | 7 | 2 tasks | 6 files |
| Phase 04-code-snippets-gist-sharing P03 | 35 min | 2 tasks | 10 files |
| Phase 04-code-snippets-gist-sharing P04 | 7 | 3 tasks | 10 files |
| Phase 05-prompt-library P01 | 9 | 2 tasks | 12 files |
| Phase 05-prompt-library P02 | 5 | 2 tasks | 7 files |
| Phase 05-prompt-library P03 | 10 | 2 tasks | 4 files |
| Phase 05-prompt-library P04 | 4 | 2 tasks | 3 files |
| Phase 05-prompt-library P05 | 2 | 1 tasks | 5 files |
| Phase 06-quick-actions-performance P01 | 6 | 2 tasks | 5 files |
| Phase 06-quick-actions-performance P03 | 1 min | 2 tasks | 3 files |
| Phase 06-quick-actions-performance P02 | 6 min | 2 tasks | 4 files |
| Phase 07-intelligent-search-ai P01 | 4 | 2 tasks | 6 files |
| Phase 08-documentation-lookup P01 | 8 | 2 tasks | 10 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Full rewrite (not migration): Clean break enables Swift 6 strict concurrency — no Obj-C/Swift bridging
- SwiftUI + MenuBarExtra(.menu): `.window` variant activates the app and breaks non-activating bezel flow
- NSPanel for bezel: Only non-activating HUD option; WindowGroup and MenuBarExtra(.window) both break paste flow
- SwiftData with background ModelActor: Clipboard monitor fires every 0.5s; synchronous saves block main thread
- Bundle ID preserved as com.generalarcade.flycut: retains existing accessibility trust grants; new ID would require re-granting
- AppDelegate marked @MainActor: required to safely initialize AccessibilityMonitor as a stored property default value
- VersionedSchema versionIdentifier as let not var: Swift 6 requires immutable global shared state
- [Phase 01-02]: @AppStorage used directly in views instead of via @Bindable AppSettings — simpler binding chain, avoids Swift 6 @Observable + @Bindable complexity
- [Phase 01-02]: KeyboardShortcuts.Recorder shown in Phase 1 as placeholder; actual CGEventTap registration deferred to Phase 2
- [Phase 01-02]: SMAppService.status checked before register/unregister — avoids double-registration error; syncLaunchAtLogin() on .onAppear reads system ground truth
- [Phase 01-02]: @AppStorage used directly in views instead of via @Bindable AppSettings — simpler binding chain, avoids Swift 6 @Observable + @Bindable complexity
- [Phase 01-02]: KeyboardShortcuts.Recorder shown in Phase 1 as placeholder; actual CGEventTap registration deferred to Phase 2
- [Phase 01-02]: SMAppService.status checked before register/unregister — avoids double-registration error; syncLaunchAtLogin() on .onAppear reads system ground truth
- [Phase 02-core-engine]: @ModelActor used for ClipboardStore — macro auto-synthesizes modelExecutor and modelContainer init boilerplate, no nonisolated(unsafe) needed
- [Phase 02-core-engine]: fetchAll returns [PersistentIdentifier] not [@Model] objects — @Model is not Sendable; PersistentIdentifier is the safe cross-actor reference
- [Phase 02-core-engine]: [Phase 02-01]: GENERATE_INFOPLIST_FILE=YES on FlycutTests target — eliminates need for a hand-crafted test bundle Info.plist
- [Phase 02-core-engine]: CGEventPost obsoleted in Swift 3 — use CGEvent.post(tap: CGEventTapLocation(rawValue: 0)!) instance method for kCGHIDEventTap
- [Phase 02-core-engine]: activateIgnoringOtherApps deprecated macOS 14 — use activate(from: NSRunningApplication.current, options: []) instead
- [Phase 02-core-engine]: AppTracker notification closure uses Task { @MainActor } hop for Swift 6 Sendable compliance — queue: .main alone is insufficient
- [Phase 02-core-engine]: @Query in MenuBarView auto-refreshes from SwiftData background actor inserts — no manual binding needed
- [Phase 02-core-engine]: @Environment(\.openSettings) replaces SettingsLink for programmatic Settings open in MenuBarExtra
- [Phase 02-core-engine]: AXIsProcessTrustedWithOptions(prompt:true) called only from explicit user tap — avoids focus-stealing on startup
- [Phase 03-ui-layer]: BezelViewModel uses [String] not [@Model] — stays pure-Swift, testable without model container; BezelView maps @Query results
- [Phase 03-ui-layer]: BezelController shares viewModel instance with BezelView — controller routes keyDown, view observes same state
- [Phase 03-ui-layer]: .nonactivatingPanel MUST be in NSPanel init styleMask — WindowServer does not honour post-init changes
- [Phase 03-ui-layer]: BezelControllerTests use per-test local controller vars — avoids Swift 6 Sendable error from nonisolated XCTestCase setUp
- [Phase 03-ui-layer]: BezelController.init(modelContainer:) with no-arg convenience init — test/preview compatibility preserved while production path injects SwiftData model container
- [Phase 03-ui-layer]: AnyView wrapping in NSHostingView rootView for conditional .modelContainer() — SwiftUI opaque 'some View' types don't unify across conditional branches without type erasure
- [Phase 03.1-objc-parity-bug-fixes]: ClipboardEntry Sendable struct defined in ClipboardMonitor.swift — cross-actor callback contract for clipboard events; nil-defaulted metadata params in insert() ensure backward-compat
- [Phase 03.1-objc-parity-bug-fixes]: ClipboardStore dedup changed from silent-drop to move-to-top (fetch+update timestamp/metadata) — matches ObjC Flycut behaviour where re-copying promotes clipping to position 0
- [Phase 03.1-objc-parity-bug-fixes]: ClipboardStore test accessor methods (sourceAppName/sourceAppBundleURL/timestamp) added for Swift 6-safe test verification — avoids container.mainContext access from non-@MainActor tests
- [Phase 03.1-objc-parity-bug-fixes]: pasteAndHide() changed from private to internal — required by flags monitor closure and future double-click paste (Bug #13)
- [Phase 03.1-objc-parity-bug-fixes]: Flags monitor uses NSEvent.addGlobalMonitorForEvents(.flagsChanged) not flagsChanged override — non-activating panels don't reliably receive flagsChanged events via NSPanel override
- [Phase 03.1-objc-parity-bug-fixes]: stickyBezel read from UserDefaults.standard in AppDelegate hotkey handler — AppDelegate has no AppSettings instance; consistent with existing settings read pattern
- [Phase 03.1-objc-parity-bug-fixes]: ClippingInfo Sendable struct bridges BezelView @Query and BezelViewModel — carries PersistentIdentifier for delete-by-ID, avoids @Model cross-actor exposure
- [Phase 03.1-objc-parity-bug-fixes]: makeClippingInfos() Option A: in-memory SwiftData container provides valid PersistentIdentifiers for ViewModel unit tests
- [Phase 03.1-objc-parity-bug-fixes]: pasteMovesToTop reads UserDefaults.standard in BezelController pasteAndHide — consistent with stickyBezel pattern, AppDelegate has no AppSettings instance
- [Phase 03.1-objc-parity-bug-fixes]: BezelViewModel navigateUp/Down read UserDefaults.standard directly — consistent with stickyBezel/pasteMovesToTop pattern; @AppStorage requires SwiftUI view context
- [Phase 03.1-objc-parity-bug-fixes]: removeDuplicates guard wraps full dedup block in ClipboardStore — existing dedup logic unchanged when enabled, simply skipped when disabled
- [Phase 03.1-objc-parity-bug-fixes]: bezelAlpha stored 0.1-0.9 applied as 1.0-bezelAlpha to opacity — higher alpha value maps to more transparency, intuitive for a Transparency slider
- [Phase 03.1-objc-parity-bug-fixes]: savePreference=0 uses mainContext.delete(model:) synchronously in applicationWillTerminate — background ModelActor unavailable after process termination begins
- [Phase 03.1-objc-parity-bug-fixes]: NSAlert used for Clear All confirmation in MenuBarView — SwiftUI confirmationDialog not reliable in MenuBarExtra .menu style
- [Phase 03.1-objc-parity-bug-fixes]: MenuBarExtra label-closure variant for dynamic icon — systemImage: parameter read once at creation, label closure re-evaluates on @AppStorage changes
- [Phase 03.1-objc-parity-bug-fixes]: kAXTrustedCheckOptionPrompt accessed as string literal 'AXTrustedCheckOptionPrompt' as CFString — avoids Swift 6 shared-mutable-state error on the global Unmanaged<CFString>
- [Phase 03.1-objc-parity-bug-fixes]: s/S key handling extracted before lowercased() switch in BezelController keyDown — case-sensitive distinction required for save vs save+delete
- [Phase 04-code-snippets-gist-sharing]: [Phase 04-01]: tags:[String] added to Snippet model (additive SwiftData field, category retained for backward compat)
- [Phase 04-code-snippets-gist-sharing]: [Phase 04-01]: Tag search uses in-memory post-SQL filter — #Predicate does not support [String].contains()
- [Phase 04-code-snippets-gist-sharing]: [Phase 04-01]: SnippetInfo Sendable struct transfers data cross-actor (mirrors ClippingInfo pattern)
- [Phase 04-code-snippets-gist-sharing]: TokenStore accepts injectable service/account params — test isolation via distinct keychain service strings; production defaults preserved
- [Phase 04-code-snippets-gist-sharing]: GistService @MainActor @Observable — ModelContext MainActor-isolated; @Observable for SwiftUI environment injection; nonisolated for languageExtension pure function
- [Phase 04-code-snippets-gist-sharing]: MockURLProtocol.requestHandler nonisolated(unsafe) — test-only serial global; GistServiceTests @MainActor — container.mainContext accessible throughout all test methods
- [Phase 04-code-snippets-gist-sharing]: [Phase 04-03]: HighlightLanguage uses camelCase enum names: javaScript/typeScript/cPlusPlus; XML not supported in HighlightSwift 1.1.0
- [Phase 04-code-snippets-gist-sharing]: [Phase 04-03]: AppDelegate cannot use @Environment(\.openWindow) — notification bridge via .flycutOpenSnippets dispatches openSnippetWindow() in MenuBarView
- [Phase 04-code-snippets-gist-sharing]: UNUserNotificationCenterDelegate methods marked nonisolated — AppDelegate is @MainActor but UNUserNotificationCenter delegates receive non-Sendable params; nonisolated + await MainActor.run is Swift 6 compliant
- [Phase 04-code-snippets-gist-sharing]: .flycutOpenGistSettings notification bridge for Settings navigation from non-SwiftUI contexts — mirrors .flycutOpenSnippets pattern; MenuBarView observes and calls openSettings()
- [Phase 05-prompt-library]: [Phase 05-01]: FlycutSchemaV2 uses typealias to re-export V1 models — ensures migration plan lists all 4 models, prevents data loss during lightweight migration
- [Phase 05-prompt-library]: [Phase 05-01]: TemplateSubstitutor uses computed var Regex (not static let) — avoids Swift 6 Sendable error; Regex<(Substring, variable: Substring)> is not Sendable
- [Phase 05-prompt-library]: [Phase 05-01]: PromptLibraryStore upsert guard order: isUserCustomized first, then version comparison — user protection always takes priority over version conflicts
- [Phase 05-prompt-library]: [Phase 05-02]: PromptSyncService @MainActor @Observable — consistent with GistService pattern; isSyncing/lastError observable directly by SwiftUI settings views
- [Phase 05-prompt-library]: [Phase 05-02]: syncFromURL stores lastSync as ISO 8601 string in UserDefaults — readable by @AppStorage String binding; Date.formatted(.relative) for user-friendly display
- [Phase 05-prompt-library]: [Phase 05-02]: Template variables stored as JSON array of {key, value} dicts in @AppStorage — preserves ordering, handles empty values, survives app restarts
- [Phase 05-03]: [Phase 05-03]: sendEvent override intercepts Tab (keyCode 48) to cycle categories — without this, Tab moves focus out of the search TextField
- [Phase 05-03]: [Phase 05-03]: pasteAndHide reads clipboard at paste time — ensures {{clipboard}} variable reflects what user copied AFTER selecting the prompt, not at open time
- [Phase 05-prompt-library]: [Phase 05-04]: Debounced auto-save uses Task.sleep + saveTask?.cancel() — 0.75s debounce balances responsiveness with SwiftData write frequency; cancel on selection change prevents stale saves
- [Phase 05-prompt-library]: [Phase 05-04]: pastePrompt reads NSPasteboard.general at paste time — ensures {{clipboard}} reflects current clipboard at moment of use, not at view load time
- [Phase 05-prompt-library]: [Phase 05-05]: Browse Prompts... calls openSnippetWindowOnPromptsTab() directly — avoids notification observer loop (MenuBarView posting to itself)
- [Phase 05-prompt-library]: [Phase 05-05]: SnippetWindowView observes .flycutOpenPrompts for selectedTab=1 — same onReceive pattern used throughout; tab-switch owner is SnippetWindowView not MenuBarView
- [Phase 06-quick-actions-performance]: [Phase 06-01]: TextTransformer uses .capitalized for titleCase — known apostrophe edge case accepted per RESEARCH.md Pitfall 6
- [Phase 06-quick-actions-performance]: [Phase 06-01]: ClipboardExportService is a no-case enum namespace with static async functions taking ClipboardStore as parameter
- [Phase 06-quick-actions-performance]: [Phase 06-01]: ClipboardStore.insert() timestamp parameter placed before sourceAppName to match Clipping init signature ordering; rememberNum: Int.max used during import to avoid trimming
- [Phase 06-quick-actions-performance]: Notification bridge used for export/import in GeneralSettingsTab — SwiftUI view has no access to AppDelegate clipboardStore; mirrors .flycutShareAsGist pattern
- [Phase 06-quick-actions-performance]: withCheckedContinuation wraps NSSavePanel/NSOpenPanel .begin for clean async/await usage in Task { @MainActor }
- [Phase 06-quick-actions-performance]: NSMenuItem.target = self set explicitly on every item — non-activating NSPanel does not route actions through responder chain without explicit target
- [Phase 06-quick-actions-performance]: activeInterval stored as var in ClipboardMonitor — set in start() from UserDefaults so checkPasteboardAdaptive comparison uses same interval as running timer
- [Phase 06-quick-actions-performance]: applyTransform does NOT auto-paste — user reviews transformed content and presses Enter (RESEARCH.md Open Question 1)
- [Phase 07-intelligent-search-ai]: FuzzyMatcher uses consecutive-bonus scoring: bonus increments by 1.0 per consecutive hit, decays by 0.5 on miss, normalized by n*(n+1)/2 ideal score
- [Phase 07-intelligent-search-ai]: PromptBezelViewModel scores title and content separately, uses max(titleScore, contentScore) as ranking key
- [Phase 07-intelligent-search-ai]: SRCH-02 (source app filtering), SRCH-03 (date filtering), AINT-01 (on-device AI) deferred/descoped per user decision in CONTEXT.md
- [Phase 08-01]: GRDB.swift 7.10.0 added as SPM dependency; struct DocEntry with Codable + FetchableRecord + Sendable for Swift 6
- [Phase 08-01]: DocsetManagerService stores metadata as Codable JSON not SwiftData — avoids migration complexity
- [Phase 08-01]: Test fixture path uses #filePath not #file — #filePath gives absolute compile-time path; #file returns relative path causing SQLite error 14

### Pending Todos

None.

### Roadmap Evolution

- Phase 03.1 inserted after Phase 03: ObjC Parity Bug Fixes (URGENT) — 30+ behavioral gaps across clipboard capture, hotkey hold-navigate-release, bezel keyboard/mouse, bezel appearance/settings, menu bar, and polish

### Blockers/Concerns

- KeyboardShortcuts SPM library Swift 6 compatibility is unverified — must check before Phase 2 planning; fallback is direct CGEventTap wrapper (RESEARCH.md notes this is now resolved as of v2.4.0 — verify at plan time)
- Highlightr SPM library Swift 6 compatibility is unverified — must check before Phase 4 planning; fallbacks: SyntaxKit or custom NSAttributedString approach
- NSPanel + Stage Manager interaction on macOS 15 is underdocumented — test early in Phase 3 before committing to panel level and collectionBehavior values

## Session Continuity

Last session: 2026-03-16T21:00:53.723Z
Stopped at: Completed 08-documentation-lookup-08-01-PLAN.md
Resume file: None
