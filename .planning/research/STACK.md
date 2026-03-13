# Stack Research

**Domain:** macOS clipboard manager — Swift/SwiftUI rewrite
**Researched:** 2026-03-05
**Confidence:** HIGH (codebase analysis) / MEDIUM-HIGH (library versions — verify before adopting)

---

## Recommended Stack

### Language & Runtime

| Component | Choice | Rationale | Confidence |
|-----------|--------|-----------|------------|
| Language | Swift 6 (strict concurrency) | Modern, safe, required for latest Apple APIs | HIGH |
| Min Target | macOS 15 (Sequoia) | Enables SwiftData, latest SwiftUI features | HIGH |
| Build System | Xcode + Swift Package Manager | Native toolchain, SPM for dependencies | HIGH |

### UI Framework

| Component | Choice | Rationale | Confidence |
|-----------|--------|-----------|------------|
| Primary UI | SwiftUI | Declarative, less boilerplate, native MenuBarExtra | HIGH |
| Menu Bar | `MenuBarExtra` with `.menu` style | Native menu bar integration | HIGH |
| Bezel HUD | `NSPanel` + `NSHostingView` | SwiftUI WindowGroup activates app — breaks paste flow. NSPanel with `NSWindowStyleMaskNonactivatingPanel` is required | HIGH |
| Preferences | SwiftUI `Settings` scene | Native settings window integration | HIGH |
| Snippet Editor | SwiftUI + syntax highlighting | Code editing with language support | MEDIUM |

### Persistence

| Component | Choice | Rationale | Confidence |
|-----------|--------|-----------|------------|
| Data Store | SwiftData | Modern persistence, `@Model` macro, seamless SwiftUI integration | HIGH |
| Preferences | `@AppStorage` / `UserDefaults` | Scalar settings (hotkey codes, display count, etc.) | HIGH |
| Secrets | Keychain Services | GitHub PAT storage for Gist sharing | HIGH |
| DB Location | `~/Library/Application Support/Flycut/clipboard.sqlite` | Predictable path via `ModelConfiguration(url:)` | HIGH |

### System Integration

| Component | Choice | Rationale | Confidence |
|-----------|--------|-----------|------------|
| Global Hotkeys | `KeyboardShortcuts` library (Sindre Sorhus, SPM) | Wraps CGEventTap, provides SwiftUI recorder, replaces SGHotKeysLib + ShortcutRecorder | MEDIUM-HIGH |
| Paste Injection | `CGEventCreateKeyboardEvent` + `CGEventPost` | Same approach as existing Flycut — proven. No alternative API exists | HIGH |
| Clipboard Monitor | `NSPasteboard.general.changeCount` polling | No notification API exists. Poll every 0.5s via `@MainActor` timer | HIGH |
| Launch at Login | `SMAppService.mainApp.register()` | Modern API, eliminates helper app target | HIGH |
| Accessibility | `AXIsProcessTrusted()` | Required for CGEvent paste injection | HIGH |

### Dependencies (SPM)

| Package | Purpose | Replaces | Confidence |
|---------|---------|----------|------------|
| `KeyboardShortcuts` | Global hotkeys + recorder UI | SGHotKeysLib + ShortcutRecorder | MEDIUM-HIGH — verify Swift 6 compat |
| `Highlightr` | Syntax highlighting for snippet editor | N/A (new feature) | MEDIUM — verify Swift 6 compat |

### Networking

| Component | Choice | Rationale | Confidence |
|-----------|--------|-----------|------------|
| GitHub Gist API | `URLSession` async/await + `Codable` | No third-party HTTP client needed. GitHub REST API v3 is simple | HIGH |
| Auth | Personal Access Token in Keychain | Simple, secure, no OAuth complexity needed | HIGH |

---

## What NOT to Use

| Technology | Why Not |
|-----------|---------|
| SGHotKeysLib | Carbon `RegisterEventHotKey` incompatible with Swift 6 strict concurrency |
| ShortcutRecorder | Replaced by `KeyboardShortcuts` library which includes recorder UI |
| UKPrefsPanel | SwiftUI `Settings` scene handles this natively |
| Sparkle | Direct download distribution — no in-app updater needed |
| Carbon.framework | Legacy; use CoreGraphics CGEventTap instead |
| Core Data | SwiftData supersedes it for macOS 15+ targets |
| Alamofire / other HTTP libs | `URLSession` async/await sufficient for GitHub Gist API |
| `MenuBarExtra(.window)` | Activates app on show — breaks paste-to-previous-app flow |
| `WindowGroup` for bezel | Wrong lifecycle for transient non-activating overlay |

---

## Key API Patterns

### Clipboard Monitoring (replaces `pollPB:` NSTimer)
```swift
@MainActor
class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    private func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        // Read and process new content
    }
}
```

### Paste Injection (replaces `fakeCommandV`)
```swift
func pasteToFrontApp(previousApp: NSRunningApplication) {
    previousApp.activate(options: .activateIgnoringOtherApps)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)! // V key
        keyDown.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)!
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

### Launch at Login (replaces FlycutHelper target)
```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    if enabled {
        try? SMAppService.mainApp.register()
    } else {
        try? SMAppService.mainApp.unregister()
    }
}
```

---

## Build Configuration

- **Signing:** Developer ID for notarized direct distribution
- **Sandbox:** Disabled — CGEvent paste injection requires unsandboxed access
- **Hardened Runtime:** Enabled with `com.apple.security.automation.apple-events` entitlement
- **Info.plist:** `LSUIElement = YES` (no dock icon)
- **Entitlements:** Accessibility usage description for paste injection

---

*Stack research: 2026-03-05*
