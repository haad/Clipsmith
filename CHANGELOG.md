# Changelog

All notable changes to Clipsmith are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Updated Lemon Squeezy product ID and checkout URL

## [5.0.1] - 2026-03-21

### Fixed
- Restored `com.apple.security.network.client` entitlement that was accidentally stripped, which invalidated TCC accessibility grants after rebuild
- Improved site spacing and visual hierarchy

## [5.0.0] - 2026-03-21

### Added
- **Lemon Squeezy licensing** — startup nag dialog (every 30 days) with "Buy a License", "Sponsor on GitHub", and "I Already Have a License" CTAs
- **License key validation** — Settings > License tab with key entry, Lemon Squeezy API activation/validation/deactivation, and licensed status display
- **LicenseService** — wraps Lemon Squeezy activate, validate, and deactivate endpoints with offline tolerance (network errors don't revoke license)
- **PolyForm Noncommercial license** — free for personal use, commercial use requires a license
- `.github/FUNDING.yml` for GitHub Sponsors + Lemon Squeezy
- `SettingsTab` enum with `@AppStorage` for programmatic tab selection — "I Already Have a License" navigates directly to the License tab
- Group versioned docs into collapsible entries in the DevDocs catalog list

### Fixed
- `LicenseService.activate()` now sets `lastError` before re-throwing so error messages display in Settings UI

## [4.2.0] - 2026-03-16

### Improved
- Documentation browser: fuzzy search across all enabled docs, doc prefix filter (`python:map`), detail panel with slug/release/size/status, download progress indicators

## [4.1.0] - 2026-03-14

### Added
- **Documentation browser** (Phase 8) — search 789+ DevDocs documentation sets from a hotkey, download for offline use, HTML rendering in WKWebView with dark/light CSS
- DocsetSearchService with fuzzy search across index.json entries
- DocsetManagerService for downloading and managing doc catalogs
- SelectedTextService for reading selected text via AXUIElement
- DocBezelController/View/ViewModel — split-pane UI with search results and rendered docs
- DocsetSettingsSection in Settings for managing downloaded docs
- Behind feature flag `docLookupEnabled` (Settings > Features)

### Fixed
- ESC not cancelling paste after modifier key release

## [4.0.2] - 2026-03-10

### Changed
- Renamed bundle ID from `com.generalarcade.flycut` to `com.github.haad.clipsmith`

## [4.0.1] - 2026-03-08

### Fixed
- Paste not working: matched original Flycut hide-then-paste timing
- Bezel paste: intercept Enter key in search mode, add local flags monitor

## [1.0.2] - 2026-03-06

### Fixed
- Disabled upload-artifact step that caused builds to hang

## [1.0.1] - 2026-03-06

### Fixed
- GitHub release 403 error by adding `contents:write` permission to workflow

## [1.0.0] - 2026-03-06

### Added
- Initial release — clipboard history, code snippets, prompt library, fuzzy search, quick actions, GitHub Gist sharing
- Keyboard-first bezel UI with non-activating NSPanel
- SwiftData persistence with schema migration
- Adaptive clipboard polling
- Password filtering for credential managers
- Export/import clipboard history as JSON
- 40+ built-in AI prompts with template variable substitution
- Syntax-highlighted snippet editor (20+ languages)
- Menu bar app with configurable hotkeys

[Unreleased]: https://github.com/haad/Clipsmith/compare/v5.0.1...HEAD
[5.0.1]: https://github.com/haad/Clipsmith/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/haad/Clipsmith/compare/v4.2.0...v5.0.0
[4.2.0]: https://github.com/haad/Clipsmith/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/haad/Clipsmith/compare/v4.0.2...v4.1.0
[4.0.2]: https://github.com/haad/Clipsmith/compare/v4.0.1...v4.0.2
[4.0.1]: https://github.com/haad/Clipsmith/compare/v1.0.2...v4.0.1
[1.0.2]: https://github.com/haad/Clipsmith/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/haad/Clipsmith/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/haad/Clipsmith/releases/tag/v1.0.0
