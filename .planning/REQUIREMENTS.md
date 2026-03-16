# Requirements: Flycut Swift

**Defined:** 2026-03-05
**Core Value:** Instant keyboard-driven access to clipboard history — press a hotkey, navigate clippings, paste without touching the mouse.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Clipboard Core

- [x] **CLIP-01**: App monitors system pasteboard and captures new text entries automatically
- [x] **CLIP-02**: User can configure maximum history size (number of clippings retained)
- [x] **CLIP-03**: Duplicate clipboard entries are automatically removed
- [x] **CLIP-04**: Password manager entries and transient pasteboard types are excluded from capture
- [x] **CLIP-05**: Clipboard history persists across app restarts via SwiftData
- [x] **CLIP-06**: User can paste selected clipping as plain text (formatting stripped)
- [x] **CLIP-07**: User can clear entire clipboard history
- [x] **CLIP-08**: User can delete individual clippings from history

### Interaction

- [x] **INTR-01**: User can activate clipboard history via a configurable global hotkey
- [x] **INTR-02**: User can navigate through clipping history using keyboard (arrow keys, jump 10, first/last)
- [x] **INTR-03**: Selected clipping is pasted into the previously frontmost application
- [x] **INTR-04**: User can search/filter clippings by text content
- [x] **INTR-05**: User can activate search via a separate configurable global hotkey

### Bezel UI

- [x] **BEZL-01**: Floating bezel HUD appears without activating Flycut (non-activating NSPanel)
- [x] **BEZL-02**: Bezel displays current clipping content with navigation indicators
- [x] **BEZL-03**: Bezel appears centered on the screen containing the mouse cursor
- [x] **BEZL-04**: Bezel works over fullscreen apps and all Spaces
- [x] **BEZL-05**: Bezel dismisses on paste, Escape key, or clicking outside

### App Shell

- [x] **SHELL-01**: App lives in menu bar with status bar icon (no dock icon)
- [x] **SHELL-02**: Menu bar dropdown shows recent clippings with preview text
- [x] **SHELL-03**: User can launch app at login via modern ServiceManagement API
- [x] **SHELL-04**: App requests and monitors Accessibility permission for paste injection

### Settings

- [x] **SETT-01**: User can configure global hotkeys via keyboard shortcut recorder
- [x] **SETT-02**: User can set history size, display length, and clipping display count
- [x] **SETT-03**: User can toggle launch at login
- [x] **SETT-04**: User can toggle paste behavior (plain text default, sound, etc.)
- [x] **SETT-05**: Preferences window uses SwiftUI Settings scene

### Favorites

- [ ] **FAVR-01**: User can pin clippings as favorites for permanent quick access
- [ ] **FAVR-02**: User can switch between clipboard history and favorites via hotkey
- [ ] **FAVR-03**: Favorites persist independently and are not affected by history clearing

### Snippets

- [x] **SNIP-01**: User can create named code snippets with a dedicated editor
- [x] **SNIP-02**: Snippet editor provides syntax highlighting for common languages
- [x] **SNIP-03**: User can organize snippets by category/language
- [x] **SNIP-04**: User can search snippets by name, content, or category
- [x] **SNIP-05**: User can paste a snippet into the frontmost app via the same paste mechanism

### GitHub Gist

- [x] **GIST-01**: User can share any clipping or snippet as a GitHub Gist
- [x] **GIST-02**: User can authenticate with GitHub via Personal Access Token stored in Keychain
- [x] **GIST-03**: User can choose public or private gist when sharing
- [x] **GIST-04**: Gist URL is copied to clipboard after creation
- [x] **GIST-05**: User can view history of previously created gists

### Documentation Lookup

- [x] **DOCS-01**: User can trigger a quick documentation search for selected/highlighted text via hotkey
- [x] **DOCS-02**: Lightweight popup shows documentation results from offline docsets
- [x] **DOCS-03**: User can download and manage docsets for their preferred languages/frameworks

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Rich Content

- **RICH-01**: App captures and previews image clipboard entries
- **RICH-02**: App captures and previews RTF/HTML clipboard entries

### Organization

- **ORGN-01**: Clippings show source application attribution (icon + name)
- **ORGN-02**: User can import/export snippets and settings

### Security

- **SECR-01**: Clipboard history auto-clears on screen lock (configurable)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| iCloud sync | High complexity, privacy concerns, disabled in original Flycut |
| iOS companion app | macOS-only focus |
| Mac App Store distribution | Sandbox breaks CGEvent paste injection |
| Sparkle auto-updates | Direct download model |
| Generic paste services (Pastebin, etc.) | GitHub Gist covers developer audience |
| Analytics / telemetry | Privacy-first, no network except Gist |
| OCR text extraction | Out of scope for clipboard manager |
| Team / shared clipboard | Single-user tool |
| Snippet template variables | Over-engineering for v1 |
| Full embedded doc browser | Quick lookup sufficient; Dash exists for full browsing |
| Real-time chat / messaging | Not relevant to clipboard management |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SHELL-01 | Phase 1 | Pending |
| SHELL-03 | Phase 1 | Complete |
| SHELL-04 | Phase 1 | Pending |
| SETT-01 | Phase 1 | Complete |
| SETT-02 | Phase 1 | Complete |
| SETT-03 | Phase 1 | Complete |
| SETT-04 | Phase 1 | Complete |
| SETT-05 | Phase 1 | Complete |
| CLIP-01 | Phase 2 | Complete |
| CLIP-02 | Phase 2 | Complete |
| CLIP-03 | Phase 2 | Complete |
| CLIP-04 | Phase 2 | Complete |
| CLIP-05 | Phase 2 | Complete |
| CLIP-06 | Phase 2 | Complete |
| CLIP-07 | Phase 2 | Complete |
| CLIP-08 | Phase 2 | Complete |
| INTR-01 | Phase 2 | Complete |
| INTR-03 | Phase 2 | Complete |
| INTR-05 | Phase 2 | Complete |
| BEZL-01 | Phase 3 | Complete |
| BEZL-02 | Phase 3 | Complete |
| BEZL-03 | Phase 3 | Complete |
| BEZL-04 | Phase 3 | Complete |
| BEZL-05 | Phase 3 | Complete |
| INTR-02 | Phase 3 | Complete |
| INTR-04 | Phase 3 | Complete |
| SHELL-02 | Phase 3 | Complete |
| FAVR-01 | Phase 4 | Pending |
| FAVR-02 | Phase 4 | Pending |
| FAVR-03 | Phase 4 | Pending |
| SNIP-01 | Phase 4 | Complete |
| SNIP-02 | Phase 4 | Complete |
| SNIP-03 | Phase 4 | Complete |
| SNIP-04 | Phase 4 | Complete |
| SNIP-05 | Phase 4 | Complete |
| GIST-01 | Phase 4 | Complete |
| GIST-02 | Phase 4 | Complete |
| GIST-03 | Phase 4 | Complete |
| GIST-04 | Phase 4 | Complete |
| GIST-05 | Phase 4 | Complete |
| DOCS-01 | Phase 4 | Complete |
| DOCS-02 | Phase 4 | Complete |
| DOCS-03 | Phase 4 | Complete |

**Coverage:**
- v1 requirements: 43 total
- Mapped to phases: 43
- Unmapped: 0

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 — traceability populated after roadmap creation*
