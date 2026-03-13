# Clipsmith

A keyboard-first clipboard, snippet, and prompt library manager for macOS.

Clipsmith keeps your clipboard history, code snippets, and AI prompts one shortcut away. Built natively in Swift for macOS 15+.

## Features

- **Clipboard History** — automatically saves everything you copy, scroll back and paste any previous item
- **Fuzzy Search** — find any clipping instantly by typing, even with partial or misspelled queries
- **Code Snippets** — save frequently used code as named snippets organized into folders
- **Prompt Library** — built-in collection of curated AI prompts, searchable and pasteable
- **Quick Actions** — transform text: uppercase, lowercase, trim, sort lines, URL encode, and more
- **GitHub Gist Sharing** — share any clipping as a Gist with one keystroke
- **Privacy First** — all data stays on your Mac, no cloud sync, no analytics, no tracking

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Open Clipsmith | `⇧⌘V` |
| Navigate clippings | `↑` `↓` |
| Paste selected | `⏎` |
| Search | `/` |
| Delete clipping | `⌫` |
| Star / unstar | `S` |
| Share as Gist | `G` |
| Quick actions | `Tab` |
| All / Starred / Snippets / Prompts | `⌘1` `⌘2` `⌘3` `⌘4` |

## Requirements

- macOS 15 (Sequoia) or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Building from Source

Open `Clipsmith.xcodeproj` in Xcode 16+ and build the `Clipsmith` target.

## License

MIT

## Credits

Clipsmith is a ground-up Swift rewrite inspired by the original [Flycut](https://github.com/TermiT/Flycut) clipboard manager.
