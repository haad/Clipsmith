# Project Research Summary

**Project:** Flycut — macOS Clipboard Manager (Swift/SwiftUI Rewrite)
**Domain:** macOS menu bar utility, system integration, clipboard management
**Researched:** 2026-03-05
**Confidence:** HIGH

## Executive Summary

Flycut is a developer-focused macOS clipboard manager with a signature bezel HUD, code snippet storage, and GitHub Gist sharing. The project is a full rewrite from an aging Objective-C/AppKit codebase to Swift 6 + SwiftUI + SwiftData, targeting macOS 15 (Sequoia) as minimum. The existing codebase provides the full behavioral specification — every Objective-C file maps to a well-understood Swift replacement — making this a high-confidence rewrite with clear scope, not exploratory development.

The recommended approach follows a strict layered architecture: SwiftData models and system permissions first (Phase 1), core engine services second (Phase 2), UI layer third (Phase 3), and extended features like snippets and Gist integration last (Phase 4). This ordering is driven by hard component dependencies — paste injection cannot be built before permissions are handled, the bezel cannot work before the core engine exists, and extended features depend on all prior infrastructure. The architecture translates the existing MVC chain (AppController → FlycutOperator → FlycutStore) into an `@Observable @MainActor ClipboardController` coordinating actor-based system services. The key architectural simplification: the three-store pattern (clippings / favorites / stashed) collapses into a single `Clipping` model with an `isFavorite: Bool` flag and SwiftData predicates.

The key risks are all in the core engine and are well-understood: paste injection timing is inherently non-deterministic and must be solved with explicit app capture and minimal delays (not the 300-500ms arbitrary delays in the current codebase); accessibility permission state goes stale silently after code signature changes; and the `pbBlockCount` pattern that prevents Flycut from re-capturing its own pastes must be reimplemented as a `blockedChangeCount` property on `PasteboardMonitor` with a timeout. None of these risks are unknown unknowns — all have confirmed solutions documented in PITFALLS.md. The app must remain unsandboxed; CGEvent paste injection is incompatible with the App Sandbox.

---

## Key Findings

### Recommended Stack

The rewrite drops all Objective-C dependencies cleanly. Swift 6 strict concurrency is the right choice for this app because most core behavior (pasteboard polling, CGEvent dispatch, hotkey callbacks) crosses concurrency boundaries — enforcing these at compile time eliminates an entire class of subtle bugs present in the current codebase. SwiftUI covers all UI surfaces except the bezel HUD, which requires a raw `NSPanel` with `NSWindowStyleMaskNonactivatingPanel`. Two SPM dependencies are introduced: `KeyboardShortcuts` (Sindre Sorhus) for global hotkeys and `Highlightr` for snippet syntax highlighting. Both need Swift 6 compatibility verification before adoption.

The largest stack decision is what NOT to use. SGHotKeysLib wraps Carbon APIs incompatible with Swift 6 strict concurrency. `MenuBarExtra(.window)` activates the application on show, which destroys the non-activating bezel flow. `WindowGroup` has the same problem. Core Data is superseded by SwiftData. The FlycutHelper launch-at-login helper app target is replaced by a single `SMAppService.mainApp.register()` call.

**Core technologies:**
- **Swift 6 (strict concurrency):** Language — compiler-enforced safety across system API concurrency boundaries
- **SwiftUI + `MenuBarExtra(.menu)`:** Primary UI + status bar — declarative, native, less boilerplate
- **`NSPanel` (`NSWindowStyleMaskNonactivatingPanel`) for bezel:** Non-activating HUD — `WindowGroup` and `MenuBarExtra(.window)` both activate the app and break the paste flow
- **SwiftData:** Persistence — replaces Core Data and three-store FlycutStore pattern with a single unified `@Model` layer
- **`CGEventTap` / `KeyboardShortcuts` SPM:** Global hotkeys — replaces Carbon `RegisterEventHotKey` which is Swift 6-incompatible
- **`NSPasteboard.changeCount` polling (0.5s `@MainActor` timer):** Clipboard monitoring — no notification API exists on macOS
- **`SMAppService.mainApp`:** Launch at login — replaces FlycutHelper helper app target entirely
- **`URLSession` async/await + Keychain Services:** GitHub Gist API and PAT storage — no HTTP client library needed

**What to drop entirely:** SGHotKeysLib, ShortcutRecorder, UKPrefsPanel, Sparkle, Carbon.framework, Core Data, FlycutHelper target, App Sandbox entitlement.

### Expected Features

Research identified 14 table stakes features (users leave without them), 10 differentiators (competitive advantage), and 10 anti-features (documented scope creep to avoid). Flycut's unique market positioning is the combination of keyboard-driven bezel HUD + code snippet editor + GitHub Gist sharing — no competitor offers all three. The table stakes are all existing Flycut capabilities; the differentiators are new in this rewrite.

**Must have (table stakes — all existing Flycut functionality):**
- Clipboard capture with pasteboard polling, configurable history size, persistent history, deduplication
- Global hotkey activation, keyboard navigation in bezel, paste injection to frontmost app
- Password manager exclusion (security requirement — exact denylist, not optional)
- Search/filter, content preview, plain text paste (strip formatting)
- Menu bar icon + dropdown, launch at login, preferences UI

**Should have (differentiators for v1):**
- Bezel HUD — keyboard-driven floating overlay unique to Flycut; HIGH competitive value
- Code snippet editor with syntax highlighting — developer-specific; no competitor matches this
- GitHub Gist sharing with PAT auth via Keychain — closes the developer workflow loop
- Favorites / pinned items — fast access to permanent clippings

**Defer to v1.1:**
- Category/tag organization UI for snippets
- Source app attribution display
- Import/export (backup and restore)
- Auto-clear clipboard on screen lock
- Rich content preview (images, RTF, HTML)

**Anti-features (do not build, reasons documented):**
- Mac App Store distribution — App Sandbox is incompatible with CGEvent paste injection
- iCloud sync — months of work, sync conflict edge cases, existing Flycut had it disabled
- iOS companion app — macOS-only focus per project constraints
- Analytics/telemetry — trust violation for a privacy-first developer tool
- Snippet template variables — over-engineering for v1

### Architecture Approach

The architecture is an Observable Controller pattern with actor-based system services. SwiftUI views observe a central `ClipboardController` (`@Observable @MainActor`), which coordinates four system services (`PasteboardMonitor`, `PasteService`, `HotkeyManager`, `GistService`) and a SwiftData persistence layer. This is a direct translation of the existing three-tier MVC (AppController → FlycutOperator → FlycutStore), not a novel design. All `NSPasteboard` access is pinned to `@MainActor`. SwiftData writes go through a background `ModelActor` with debouncing to avoid blocking the main thread on the 0.5s polling path.

**Major components:**
1. **`FlycutApp` + `AppDelegate` (App Shell)** — SwiftUI entry point; configures `MenuBarExtra`, SwiftData container, activation policy (`LSUIElement = YES`, no dock icon)
2. **`ClipboardController` (`@Observable @MainActor`)** — Central state; owns clippings array, stack position, bezel visibility, search query; replaces FlycutOperator + AppController coordination
3. **`PasteboardMonitor` (`@MainActor`)** — 0.5s polling loop; exact denylist filtering; `blockedChangeCount` for self-paste exclusion with 1s timeout
4. **`PasteService` (`@MainActor`)** — Captures frontmost app at hotkey press, writes to pasteboard, posts CGEvent Cmd-V with 50ms yield
5. **`HotkeyManager`** — `KeyboardShortcuts` SPM library wrapping CGEventTap; dispatches to `@MainActor`
6. **`BezelWindowController`** — `NSPanel` with `NSWindowStyleMaskNonactivatingPanel`; `level = .screenSaver + 1`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`; hosts `BezelView` via `NSHostingView`
7. **`GistService`** — `URLSession` async/await; PAT from Keychain; `Codable` models for GitHub REST API v3
8. **SwiftData models:** `Clipping` (content, isFavorite, sourceApp, timestamp), `Snippet` (name, content, language, category), `GistRecord` (gistID, gistURL, createdAt)

### Critical Pitfalls

1. **Paste timing is non-deterministic** — Capture `NSWorkspace.shared.frontmostApplication` at hotkey press (before bezel opens). After writing to `NSPasteboard`, call `previousApp.activate()` explicitly, then post CGEvent after exactly 50ms. Never use delays over 100ms. The existing codebase papers over this with 300-500ms delays at 5+ call sites — reproduce this and the bug travels with you.

2. **`MenuBarExtra(.window)` and `WindowGroup` activate the app** — Use `MenuBarExtra(.menu)` only for the status bar dropdown. Build bezel as standalone `NSPanel` with `NSWindowStyleMaskNonactivatingPanel`. Detection: open TextEdit, trigger hotkey, type — if characters appear in Flycut instead of TextEdit, activation policy is broken.

3. **SwiftData synchronous saves block the main thread on a hot path** — The clipboard monitor fires every 0.5s. All SwiftData writes must go through a background `ModelActor` with debouncing (batch write after 2-3s of inactivity). The in-memory `clippings` array in `ClipboardController` is the UI source of truth; persistence is async catch-up.

4. **Accessibility permission goes stale silently** — `AXIsProcessTrusted()` returns `true` at launch but becomes `false` if the binary moves or macOS refreshes the trust cache. Check before every paste (the call is cheap). Poll in a 5s timer, reflect status in menu bar. Do not pass `kAXTrustedCheckOptionPrompt: true` in the paste path — it steals focus.

5. **Password denylist must be exact and checked before reading clipboard content** — The full set (`PasswordPboardType`, `org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`, `org.nspasteboard.AutoGeneratedType`, `com.agilebits.onepassword`) must be evaluated against `NSPasteboard.general.types` before any string read. This is a security requirement, not a nice-to-have.

---

## Implications for Roadmap

Based on combined research, the component dependency graph is unambiguous. Each phase is a hard gate for the next. The ARCHITECTURE.md suggested build order is confirmed as correct.

### Phase 1: Foundation

**Rationale:** Everything else has runtime dependencies on this phase. `ModelContext` and `AppSettings` are injected into engine services at init time. The activation policy must be set correctly before any UI can work. `VersionedSchema` must be defined before any data is written, or future migrations will cause silent data loss. This phase produces no user-visible features except a menu bar icon that appears.

**Delivers:** Compilable app target; `LSUIElement = YES` + correct activation policy; SwiftData schema with `VersionedSchema` defined from v1.0; `@AppStorage` preferences; `SMAppService` launch-at-login; accessibility permission checker.

**Addresses features:** Launch at login, Preferences UI (scaffolding), Menu bar presence (icon only).

**Avoids pitfalls:** Activation policy conflict with SwiftUI (Pitfall 11), SwiftData schema migration trap (Pitfall 12), privacy-safe debug logging established (Pitfall 15).

**Research flag:** Standard patterns — skip research-phase. All APIs are fully documented Apple territory.

---

### Phase 2: Core Engine

**Rationale:** Clipboard capture and paste injection are the entire product. Until these work correctly under real system conditions, nothing else matters. This phase must be built and validated before UI because timing bugs in the paste flow are invisible in isolation — they only manifest when a real app is in the foreground and the bezel is dismissed. All 6 critical pitfalls live in this phase.

**Delivers:** Working clipboard history capture with deduplication, password exclusion, and correct `blockedChangeCount` self-paste blocking; working paste injection with correct timing and frontmost-app tracking; global hotkey registration; async persistence write path; all without activating the app.

**Addresses features:** Clipboard capture, deduplication, password exclusion, global hotkey, paste injection, plain text paste, persistent history.

**Avoids pitfalls:** Paste timing (Pitfall 1), accessibility staleness (Pitfall 2), Carbon API incompatibility (Pitfall 3), `pbBlockCount` race (Pitfall 6), `NSPasteboard` threading (Pitfall 7), password denylist exactness (Pitfall 8).

**Research flag:** Standard patterns for all APIs. Working code samples provided in STACK.md and ARCHITECTURE.md. Verify `KeyboardShortcuts` Swift 6 compatibility before starting; if incompatible, implement `CGEventTap` directly using the documented pattern.

---

### Phase 3: UI Layer

**Rationale:** UI is built on a proven, tested engine. The bezel HUD requires the paste flow to be correct; the menu bar requires clipboard history to exist; the settings window requires the hotkey system to be in place. Building UI first is the common trap — it looks right but breaks at every system integration seam. The bezel HUD is the most technically complex UI component and carries the most pitfall risk.

**Delivers:** Bezel HUD with keyboard navigation, arrow-key scroll, paste-on-enter; menu bar dropdown showing recent clippings with click-to-paste; search/filter within bezel; settings window with hotkey recorder, history size configuration, accessibility permission status indicator.

**Addresses features:** Keyboard navigation, content preview, search/filter, configurable history size, menu bar dropdown, full preferences UI.

**Avoids pitfalls:** `MenuBarExtra` activation (Pitfall 4), large history menu rebuild (Pitfall 10), hotkey recorder in SwiftUI (Pitfall 9), multi-monitor bezel centering (Pitfall 14).

**Research flag:** The bezel `NSPanel` + SwiftUI hosting interaction on macOS 15 with Stage Manager has underdocumented edge cases — panel level and collection behavior may need tuning. Recommend a brief research-phase on this specific interaction before implementation planning. The remaining UI (MenuBarView, SettingsView) follows standard patterns.

---

### Phase 4: Extended Features

**Rationale:** Developer-facing differentiators that justify Flycut over simpler alternatives. These are additive with no circular dependencies on Phase 3 UI patterns. Gist sharing needs the persistence layer (Phase 1) and working clipboard (Phase 2) but can be developed in parallel with Phase 3 if resourcing allows.

**Delivers:** Code snippet editor with syntax highlighting (Highlightr), snippet categories and search; GitHub Gist creation from clipboard entries or snippets with PAT authentication via Keychain; favorites/pinning of clippings; Gist history records in SwiftData.

**Addresses features:** Code snippet editor, GitHub Gist sharing, favorites/pinned items; sets up the category/tag work deferred to v1.1.

**Uses stack elements:** `Highlightr` SPM, `URLSession` async/await, Keychain Services.

**Research flag:** Verify `Highlightr` Swift 6 strict concurrency compatibility before adopting — not verified during stack research. If incompatible, evaluate `SyntaxKit` or a custom regex-based approach before committing. GitHub Gist REST API v3 is simple and stable — no research needed.

---

### Phase Ordering Rationale

- **Foundation before Core:** `ModelContext` and `AppSettings` are injected into engine services at initialization — they must exist first.
- **Core before UI:** All SwiftUI views observe `ClipboardController` state that only exists after the engine is running. Building UI on a stubbed controller produces misleading results.
- **UI before Extended Features:** The snippet editor and Gist UI reuse BezelView and MenuBarView patterns established in Phase 3. Attempting to build them without that foundation means rebuilding those patterns twice.
- **All 6 critical pitfalls (Pitfalls 1-6) are addressed in Phases 1-2:** By the time Phase 3 ships user-visible UI, the behavioral safety guarantees are already in place.
- **Anti-features are firm constraints, not deferrals:** Mac App Store and App Sandbox are incompatible with the core product function. iCloud sync is excluded by prior decision in the existing codebase. These do not become scope candidates in later phases.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3 (Bezel HUD — NSPanel + Stage Manager):** The interaction of `NSPanel` at `.screenSaver + 1` level with Stage Manager and fullscreen apps on macOS 15 has underdocumented edge cases. Research before implementation planning for this component specifically.
- **Phase 4 (Highlightr Swift 6 compat):** Must be verified before committing to the snippet editor approach. The library was not checked against Swift 6 strict concurrency during stack research.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Foundation):** SwiftData `VersionedSchema`, `SMAppService`, `LSUIElement`, `@NSApplicationDelegateAdaptor` — all well-documented Apple APIs with clear patterns.
- **Phase 2 (Core Engine):** All API patterns provided in STACK.md with working code samples. `KeyboardShortcuts` is mature and well-documented (verify Swift 6 compat, not behavior).
- **Phase 4 (GitHub Gist API):** REST API v3 gists endpoint is simple, stable, and well-documented. No research needed.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Derived from direct Flycut codebase analysis and Apple API documentation. `KeyboardShortcuts` and `Highlightr` Swift 6 compatibility is MEDIUM — verify at project start before each phase. |
| Features | MEDIUM-HIGH | Table stakes and anti-features are well-established for this app category (HIGH). Differentiator value assessment is inference from competitor analysis based on training data through 2025 (MEDIUM). |
| Architecture | HIGH | Direct translation of existing Flycut MVC with well-documented Swift 6 idioms. All component boundaries, data flows, and critical patterns are fully specified with code samples. |
| Pitfalls | HIGH | Derived from direct analysis of Flycut CONCERNS.md, specific Objective-C code patterns (pbBlockCount, fakeCommandV), and known macOS API constraints. Not speculative — all grounded in the existing codebase. |

**Overall confidence:** HIGH

### Gaps to Address

- **`KeyboardShortcuts` Swift 6 compat:** Verify at project start before Phase 2 planning. If incompatible, implement `CGEventTap` wrapper directly — the pattern is documented in STACK.md and ARCHITECTURE.md.
- **`Highlightr` Swift 6 compat:** Verify before Phase 4 planning. If incompatible, evaluate alternatives (`SyntaxKit`, custom NSAttributedString approach) before committing to the snippet editor implementation.
- **NSPanel + Stage Manager on macOS 15:** Actual behavior not empirically verified. Test early in Phase 3 — panel level and `collectionBehavior` may need adjustment.
- **Existing user data migration:** The current Flycut stores clipboard history in a plist-based `FlycutStore` format. Whether to offer a migration path to SwiftData is a product decision not addressed in this research. Resolve during Phase 1 requirements.

---

## Sources

### Primary (HIGH confidence)
- Flycut Objective-C source (AppController, FlycutOperator, FlycutStore, BezelWindow, AppDelegate) — direct behavioral specification, architectural patterns, pitfall identification
- Flycut CONCERNS.md — documented known bugs, accessibility issues, timing problems driving rewrite decisions
- Apple Developer Documentation — `NSPasteboard`, `CGEventTap`, `NSPanel`, SwiftData, `SMAppService`, `MenuBarExtra`, `AXIsProcessTrusted`, `NSRunningApplication`, `CGEventCreateKeyboardEvent`

### Secondary (MEDIUM confidence)
- `KeyboardShortcuts` library (github.com/sindresorhus/KeyboardShortcuts) — SPM package for global hotkey management; Swift 6 status unverified
- `Highlightr` library — SPM package for syntax highlighting on macOS; Swift 6 status unverified
- Competitor analysis (Maccy, Paste, CopyClip, Alfred) — feature landscape and positioning; based on training data through 2025

### Tertiary (LOW confidence — needs validation)
- NSPanel + Stage Manager interaction on macOS 15 — inferred from panel collection behavior documentation; not empirically tested
- `Highlightr` performance at large file sizes and available theme options — not verified; validate during Phase 4

---

*Research completed: 2026-03-05*
*Ready for roadmap: yes*
