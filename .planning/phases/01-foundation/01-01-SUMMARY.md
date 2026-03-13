---
phase: 01-foundation
plan: 01
subsystem: infra
tags: [swift, swiftui, swiftdata, macos, menu-bar, accessibility, xcodeproj]

# Dependency graph
requires: []
provides:
  - FlycutSwift Xcode project targeting macOS 15, Swift 6 strict concurrency
  - MenuBarExtra(.menu) app shell with no dock icon (LSUIElement + setActivationPolicy)
  - SwiftData VersionedSchema V1 wrapping Clipping, Snippet, GistRecord @Models
  - FlycutMigrationPlan with empty stages (migration baseline for all future schema changes)
  - AccessibilityMonitor polling AXIsProcessTrusted every 5s via Timer
  - ModelContainer at ~/Library/Application Support/Flycut/clipboard.sqlite
affects: [02-settings, 03-core, 04-bezel, 05-data]

# Tech tracking
tech-stack:
  added:
    - SwiftUI (MenuBarExtra, Settings scene)
    - SwiftData (VersionedSchema, ModelContainer, SchemaMigrationPlan)
    - ApplicationServices (AXIsProcessTrusted)
    - OSLog (os.Logger)
  patterns:
    - "@NSApplicationDelegateAdaptor for AppKit activation policy control"
    - "VersionedSchema from day one — FlycutSchemaV1 wraps all @Model types"
    - "@Observable @MainActor for main-thread-bound services"
    - "Environment injection of @Observable objects into SwiftUI views"

key-files:
  created:
    - FlycutSwift/App/FlycutApp.swift
    - FlycutSwift/App/AppDelegate.swift
    - FlycutSwift/Models/Schema/FlycutSchemaV1.swift
    - FlycutSwift/Models/Schema/FlycutMigrationPlan.swift
    - FlycutSwift/Services/AccessibilityMonitor.swift
    - FlycutSwift/Views/MenuBarView.swift
    - FlycutSwift/Views/SettingsView.swift
    - FlycutSwift/Info.plist
    - FlycutSwift/FlycutSwift.entitlements
    - FlycutSwift.xcodeproj/project.pbxproj
  modified: []

key-decisions:
  - "Preserved bundle ID com.generalarcade.flycut to retain existing accessibility trust grants"
  - "AppDelegate marked @MainActor to allow safe initialization of @MainActor-isolated AccessibilityMonitor"
  - "versionIdentifier changed to let (not var) to satisfy Swift 6 nonisolated global shared mutable state error"
  - "AccessibilityMonitor injected into SwiftUI environment via .environment() on both MenuBarExtra and Settings scenes"

patterns-established:
  - "Rule 1 - Bug: Fixed static var versionIdentifier -> static let to resolve Swift 6 concurrency error"
  - "Rule 1 - Bug: Added @MainActor to AppDelegate class to resolve main actor-isolated default value error"

requirements-completed: [SHELL-01, SHELL-04]

# Metrics
duration: 4min
completed: 2026-03-05
---

# Phase 1 Plan 01: App Shell and SwiftData Schema Summary

**SwiftUI macOS menu-bar-only app with SwiftData VersionedSchema V1, ModelContainer at custom path, and AccessibilityMonitor polling AXIsProcessTrusted every 5 seconds — Swift 6 strict concurrency throughout**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-05T14:50:30Z
- **Completed:** 2026-03-05T15:55:00Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments

- Created FlycutSwift Xcode project from scratch with macOS 15 deployment target, Swift 6 strict concurrency, and Hardened Runtime
- Built menu-bar-only app shell: LSUIElement=YES + setActivationPolicy(.accessory), no WindowGroup, MenuBarExtra(.menu) style
- Defined SwiftData VersionedSchema V1 wrapping Clipping, Snippet, and GistRecord @Models with FlycutMigrationPlan baseline
- Implemented AccessibilityMonitor polling AXIsProcessTrusted every 5 seconds with no focus-stealing prompt

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Xcode project, App shell, and SwiftData schema** - `2e67c65` (feat)
2. **Task 2: Add AccessibilityMonitor service and wire to app** - `50b39b5` (feat)

## Files Created/Modified

- `FlycutSwift.xcodeproj/project.pbxproj` - Xcode project: macOS 15, Swift 6, SWIFT_STRICT_CONCURRENCY=complete
- `FlycutSwift/App/FlycutApp.swift` - @main entry: MenuBarExtra(.menu), Settings scene, sharedModelContainer, environment injection
- `FlycutSwift/App/AppDelegate.swift` - NSApplicationDelegate: setActivationPolicy(.accessory), UserDefaults defaults, AccessibilityMonitor lifecycle
- `FlycutSwift/Models/Schema/FlycutSchemaV1.swift` - VersionedSchema V1: Clipping, Snippet, GistRecord @Model classes
- `FlycutSwift/Models/Schema/FlycutMigrationPlan.swift` - SchemaMigrationPlan with empty stages (v1.0 baseline)
- `FlycutSwift/Services/AccessibilityMonitor.swift` - @Observable @MainActor class, 5s Timer, AXIsProcessTrusted, openAccessibilitySettings URL
- `FlycutSwift/Views/MenuBarView.swift` - Placeholder: "No clippings yet" + Quit button
- `FlycutSwift/Views/SettingsView.swift` - Placeholder: "Settings coming soon"
- `FlycutSwift/Info.plist` - LSUIElement=YES, bundle ID com.generalarcade.flycut
- `FlycutSwift/FlycutSwift.entitlements` - app-sandbox=false, apple-events entitlement

## Decisions Made

- **Bundle ID preserved as com.generalarcade.flycut** — retains existing accessibility trust grants from the Obj-C Flycut installation; new ID would require users to re-grant permission
- **AppDelegate marked @MainActor** — required to safely initialize `AccessibilityMonitor` (which is @MainActor-isolated) as a stored property default value
- **AccessibilityMonitor injected via .environment()** — both MenuBarExtra and Settings scenes receive the monitor so future views can observe it with @Environment without prop-drilling

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed static var versionIdentifier to static let in FlycutSchemaV1**
- **Found during:** Task 1 (initial build verification)
- **Issue:** `static var versionIdentifier = Schema.Version(1, 0, 0)` triggers Swift 6 error: "static property 'versionIdentifier' is not concurrency-safe because it is nonisolated global shared mutable state"
- **Fix:** Changed to `static let versionIdentifier = Schema.Version(1, 0, 0)` — the value never changes, so let is correct
- **Files modified:** FlycutSwift/Models/Schema/FlycutSchemaV1.swift
- **Verification:** Build succeeded after fix
- **Committed in:** 2e67c65 (Task 1 commit)

**2. [Rule 1 - Bug] Added @MainActor to AppDelegate to resolve actor isolation error**
- **Found during:** Task 1 (initial build verification)
- **Issue:** Swift 6 error: "main actor-isolated default value in a nonisolated context" — `AccessibilityMonitor` is @MainActor but AppDelegate wasn't
- **Fix:** Added `@MainActor` attribute to AppDelegate class declaration
- **Files modified:** FlycutSwift/App/AppDelegate.swift
- **Verification:** Build succeeded after fix
- **Committed in:** 2e67c65 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs — both Swift 6 strict concurrency errors)
**Impact on plan:** Both auto-fixes required for Swift 6 compilation. No scope creep. The VersionedSchema protocol requires versionIdentifier to conform; using let is correct since schema versions never mutate. AppDelegate needs @MainActor to host @MainActor-isolated services as stored properties.

## Issues Encountered

None beyond the two auto-fixed Swift 6 concurrency errors above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- App shell is complete; Phase 2 (Settings) can inject `@Environment(AccessibilityMonitor.self)` in any view
- `FlycutSchemaV1.models` is the definitive model list; Phase 3+ adds no new @Model types without adding FlycutSchemaV2
- `AppDelegate.accessibilityMonitor` is the single source of truth for permission state
- KeyboardShortcuts SPM dependency not yet added — Phase 2 plan should add it before implementing hotkey settings UI

---
*Phase: 01-foundation*
*Completed: 2026-03-05*
