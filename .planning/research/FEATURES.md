# Features Research

**Domain:** macOS clipboard manager with code snippet support
**Researched:** 2026-03-05
**Confidence:** MEDIUM-HIGH (competitor analysis based on training data through 2025)

---

## Table Stakes

Features users expect from any clipboard manager. Missing these and users leave.

| Feature | Description | Complexity | Dependencies |
|---------|-------------|------------|--------------|
| Clipboard capture | Monitor system pasteboard, capture text entries | LOW | Pasteboard polling |
| Configurable history size | Set max number of clippings to retain | LOW | Persistence |
| Global hotkey | System-wide keyboard shortcut to activate | MEDIUM | CGEventTap / KeyboardShortcuts |
| Keyboard navigation | Navigate through history with arrow keys | LOW | Hotkey system |
| Paste injection | Paste selected clipping into frontmost app | MEDIUM | CGEvent, Accessibility permission |
| Search / filter | Find clippings by text content | LOW | In-memory filtering |
| Deduplication | Prevent duplicate entries in history | LOW | Content comparison |
| Menu bar presence | Status bar icon with dropdown menu | LOW | MenuBarExtra |
| Launch at login | Start automatically on macOS login | LOW | SMAppService |
| Persistent history | History survives app restart | MEDIUM | SwiftData |
| Password exclusion | Skip clipboard entries from password managers | LOW | Pasteboard type filtering |
| Content preview | See clipping content before pasting | LOW | UI display |
| Preferences UI | Configure app behavior | MEDIUM | SwiftUI Settings |
| Plain text paste | Strip formatting, paste as plain text | LOW | String processing |

**Total:** 14 table stakes features

---

## Differentiators

Features that set Flycut apart from competitors like Maccy, CopyClip, Paste.

| Feature | Description | Complexity | Value | Dependencies |
|---------|-------------|------------|-------|--------------|
| Bezel HUD | Floating non-activating overlay for clipping selection — unique to Flycut | HIGH | HIGH | NSPanel, SwiftUI hosting |
| Code snippet editor | Full editor with syntax highlighting, categories, naming | HIGH | HIGH | Highlightr, SwiftData models |
| GitHub Gist sharing | Create gists from clipboard entries or snippets | MEDIUM | HIGH | GitHub API, Keychain |
| Favorites / pinned items | Pin frequently used clippings for quick access | LOW | MEDIUM | SwiftData flag |
| Source app attribution | Show which app the clipping came from | LOW | LOW | NSRunningApplication |
| Category / tag organization | Organize snippets by language, project, or custom tags | MEDIUM | MEDIUM | SwiftData relations |
| Snippet search | Search across saved snippets by name, content, or tag | LOW | MEDIUM | SwiftData queries |
| Rich content preview | Preview images, RTF, HTML in history (defer to v2) | HIGH | MEDIUM | NSAttributedString |
| Auto-clear on lock | Clear sensitive clipboard on screen lock | LOW | LOW | NSNotificationCenter |
| Import / export | Backup and restore snippets and settings | MEDIUM | LOW | Codable + file system |

**Total:** 10 differentiating features

---

## Anti-Features

Things to deliberately NOT build. Documented to prevent scope creep.

| Feature | Why NOT | Risk if Built |
|---------|---------|---------------|
| iCloud sync | High complexity, privacy concerns, existing Flycut had it disabled | Months of additional work, sync conflicts, data loss edge cases |
| iOS companion app | macOS-only focus per PROJECT.md | Splits focus, requires Universal Clipboard integration |
| Mac App Store distribution | Sandbox restrictions break CGEvent paste injection | Core functionality would not work |
| Sparkle auto-updates | Direct download model, no update framework needed | Dependency management, update UI complexity |
| Generic paste services | GitHub Gist covers the developer audience | Multiple API integrations, maintenance burden |
| Analytics / telemetry | Privacy-first app, no network calls except Gist | User trust violation |
| OCR text extraction | Image clipboard processing out of scope | Vision framework complexity, accuracy issues |
| Password manager integration | We skip passwords, not manage them | Security liability |
| Team / shared clipboard | Single-user tool | Networking, auth, sync infrastructure |
| Snippet template variables | Placeholders like `{{name}}` that prompt before paste | Over-engineering for v1, defer if demand exists |

---

## Feature Dependencies

```
Clipboard capture ──→ History storage ──→ Persistent history
       │                    │
       ▼                    ▼
Password exclusion    Deduplication

Global hotkey ──→ Keyboard navigation ──→ Bezel HUD
                         │
                         ▼
                   Paste injection ──→ Plain text paste

Menu bar presence ──→ Content preview ──→ Search/filter

Persistent history ──→ Favorites ──→ Snippet editor ──→ GitHub Gist
                                          │
                                          ▼
                                    Category/tags ──→ Snippet search
```

---

## Competitive Landscape

| Competitor | Strengths | Weaknesses | Flycut Advantage |
|-----------|-----------|------------|------------------|
| Maccy | Fast, lightweight, open source | No snippet editor, no sharing, basic UI | Bezel HUD + snippets + Gist |
| Paste | Beautiful UI, iCloud sync, rich preview | Expensive subscription, heavy, App Store only | Free, keyboard-first, developer-focused |
| CopyClip | Simple, free | Minimal features, no search, no snippets | Full-featured with code focus |
| Alfred clipboard | Part of Alfred powerpack | Requires Alfred, no standalone, no code features | Standalone, purpose-built |

**Unique positioning:** No competitor combines keyboard-driven bezel HUD + code snippet editor + GitHub Gist sharing. Flycut occupies unique developer-tool space.

---

## v1 vs v1.1 Recommendation

**v1 (rewrite core + new features):**
- All 14 table stakes
- Bezel HUD
- Code snippet editor with syntax highlighting
- GitHub Gist sharing
- Favorites / pinned items

**v1.1 (refinements):**
- Category / tag organization for snippets
- Source app attribution display
- Import / export
- Auto-clear on screen lock
- Rich content preview

---

*Features research: 2026-03-05*
