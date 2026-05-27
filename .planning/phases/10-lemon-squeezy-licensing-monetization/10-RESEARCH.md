# Phase 10: Lemon Squeezy Licensing & Monetization - Research

**Researched:** 2026-03-20
**Domain:** License key management, monetization, macOS startup dialogs, source-available licensing
**Confidence:** HIGH (API docs verified directly; Swift integration patterns verified from official sources)

## Summary

Phase 10 adds a monetization layer to Clipsmith without blocking usage. The core work is threefold: (1) a startup nag dialog that appears periodically (every ~30 days) linking to GitHub Sponsors and Lemon Squeezy, (2) license key entry in Settings that validates against the Lemon Squeezy License API and persists the validated key + instance ID, and (3) a source-available license file plus `.github/FUNDING.yml` update.

The Lemon Squeezy License API is a simple public HTTP API — no SDK token required. The recommended flow is: activate on first entry (returns an `instance_id`), persist both the `license_key` and `instance_id` to UserDefaults/Keychain, and re-validate on subsequent launches. Security requires hard-coding `store_id` and `product_id` into the client to prevent cross-product key reuse.

The periodic nag dialog is best implemented as a standard `NSPanel` (activating, `.titled`) shown from `applicationDidFinishLaunching` after a startup delay, gated by a `lastNagShownDate` in UserDefaults. The existing project pattern for Settings tabs (e.g. `DocsetSettingsSection`) means a new `LicenseSettingsSection` view is the natural home for key entry and validation status.

**Primary recommendation:** Implement LicenseService (URLSession, no SPM dependency needed) + LicenseNagController (NSPanel subclass, same pattern as BezelController) + LicenseSettingsSection in Settings.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| URLSession (Foundation) | macOS 12+ | HTTP calls to Lemon Squeezy License API | Built-in, Swift 6 async/await ready, no dependencies |
| UserDefaults | built-in | Persist license key + instance ID + nag date | Consistent with all existing settings storage patterns |
| NSPanel | built-in | License nag dialog window | Consistent with BezelController pattern; can be activating (titled) |
| SwiftUI TabView/Section | built-in | License settings tab in SettingsView | Consistent with all other settings sections |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-lemon-squeezy-license | 1.0.1 (Oct 2024) | Thin wrapper around License API | Convenience — but NOT recommended here (see below) |
| SecItemAdd / Keychain | built-in | Optional: store license key in Keychain | If treating the key as a credential; UserDefaults acceptable for non-secret keys |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw URLSession | swift-lemon-squeezy-license SPM package | Package uses swift-tools-version 5.8, no declared Swift 6 compatibility, only 8 stars — not worth the dependency; 3 API calls in raw URLSession is simpler |
| UserDefaults for license key | Keychain | Keychain is more secure for credentials but the license key is not secret (users share it); UserDefaults is consistent with project patterns and sufficient |
| NSPanel nag dialog | SwiftUI WindowGroup | WindowGroup scene in ClipsmithApp.swift is cleaner but requires `openWindow` environment — tricky from AppDelegate context; NSPanel mirrors BezelController pattern |

**Installation:** No new SPM packages needed. This phase uses only Foundation, AppKit, and SwiftUI.

## Architecture Patterns

### Recommended Project Structure

```
Clipsmith/
├── Services/
│   └── LicenseService.swift       # URLSession calls to LS API, @MainActor @Observable
├── Views/
│   ├── LicenseNagController.swift # NSPanel subclass for startup nag dialog
│   ├── LicenseNagView.swift       # SwiftUI view hosted in nag panel
│   └── Settings/
│       └── LicenseSettingsSection.swift  # New tab in SettingsView
├── Settings/
│   └── AppSettingsKeys.swift      # Add licenseKey, licenseInstanceId, lastNagDate
.github/
└── FUNDING.yml                    # Add custom: Lemon Squeezy purchase URL
LICENSE                            # PolyForm Noncommercial 1.0.0 (recommended)
```

### Pattern 1: LicenseService — Lemon Squeezy API calls

**What:** `@MainActor @Observable` service (mirrors GistService/PromptSyncService pattern) that wraps the three License API endpoints (activate, validate, deactivate). Stores `license_key` + `instance_id` in UserDefaults. Validates `product_id` / `store_id` from response against hard-coded constants.

**When to use:** All license API calls go through this service.

**Lemon Squeezy License API reference:**

```
Base URL: https://api.lemonsqueezy.com/v1/licenses/

Headers (all requests):
  Accept: application/json
  Content-Type: application/x-www-form-urlencoded

POST /activate
  Body: license_key=<key>&instance_name=<name>
  Response: { activated: Bool, error: String?, license_key: {...}, instance: { id, name, created_at }, meta: { store_id, product_id, ... } }

POST /validate
  Body: license_key=<key>&instance_id=<id>   (instance_id optional)
  Response: { valid: Bool, error: String?, license_key: {...}, instance: {...}|null, meta: { store_id, product_id, ... } }

POST /deactivate
  Body: license_key=<key>&instance_id=<id>
  Response: { deactivated: Bool, error: String?, license_key: {...}, meta: {...} }
```

**Example Swift service skeleton:**

```swift
// Source: https://docs.lemonsqueezy.com/api/license-api
@MainActor
@Observable
final class LicenseService {
    // Hard-code to prevent cross-product key reuse (security requirement per LS docs)
    private static let expectedStoreId: Int = 0     // fill in at store creation
    private static let expectedProductId: Int = 0   // fill in at product creation

    var isLicensed: Bool = false
    var isValidating: Bool = false
    var lastError: String? = nil

    private let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    func activate(key: String) async throws {
        // POST to /activate, verify meta.store_id + product_id, persist key + instance.id
    }

    func validate() async throws {
        // Read persisted key + instanceId, POST to /validate, update isLicensed
    }

    func deactivate() async throws {
        // POST to /deactivate, clear persisted key + instanceId
    }
}
```

**Key security check (verified from official LS docs):**
```swift
guard response.meta.storeId == LicenseService.expectedStoreId,
      response.meta.productId == LicenseService.expectedProductId else {
    throw LicenseError.wrongProduct
}
```

### Pattern 2: LicenseNagController — startup nag dialog

**What:** Activating NSPanel (`.titled` style, unlike bezels which are `.nonactivatingPanel`). Shown from `applicationDidFinishLaunching` after a brief delay, gated by 30-day UserDefaults check. Contains two buttons: "Sponsor on GitHub" and "Buy License" (both open URLs via `NSWorkspace`), plus "Already have a key" that opens Settings to the License tab.

**When to use:** Shown on launch when `isLicensed == false` AND `Date() - lastNagShownDate > 30 days`.

```swift
// Source: AppDelegate pattern from existing BezelController
// Show with activation so it appears in front on launch
controller.makeKeyAndOrderFront(nil)
NSApp.setActivationPolicy(.regular)  // temporarily, like SnippetWindowView pattern
```

**Instance name convention:** Use the Mac's host name as the instance name so users can identify it in their LS dashboard:
```swift
let instanceName = Host.current().localizedName ?? "Mac"
```

### Pattern 3: Periodic nag gating

```swift
// In AppDelegate.applicationDidFinishLaunching, after services are wired:
if !licenseService.isLicensed {
    let lastNag = UserDefaults.standard.object(forKey: AppSettingsKeys.lastNagShownDate) as? Date
    let shouldShow = lastNag == nil || Date().timeIntervalSince(lastNag!) > (30 * 24 * 3600)
    if shouldShow {
        UserDefaults.standard.set(Date(), forKey: AppSettingsKeys.lastNagShownDate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.licenseNagController.showNag()
        }
    }
}
```

### Pattern 4: LicenseSettingsSection tab

New tab in `SettingsView` following existing tab pattern. Contains:
- Status indicator (licensed / not licensed)
- TextField for license key entry
- "Activate" button (calls `licenseService.activate`)
- "Deactivate" link (visible when licensed)
- Link to purchase page

### Pattern 5: AppSettingsKeys additions

```swift
// Phase 10 additions (Licensing & Monetization)
static let licenseKey = "licenseKey"
static let licenseInstanceId = "licenseInstanceId"
static let lastNagShownDate = "lastNagShownDate"
```

Note: `lastNagShownDate` stores a `Date` object (not String) in UserDefaults via `set(_:forKey:)` / `object(forKey:) as? Date`.

### Pattern 6: FUNDING.yml update

```yaml
# .github/FUNDING.yml
github: haad
custom:
  - "https://store.lemonsqueezy.com/..."   # fill in at store creation
```

Lemon Squeezy is not a first-class supported platform in FUNDING.yml. Use the `custom:` field with the direct purchase URL (HIGH confidence — verified from GitHub docs).

### Anti-Patterns to Avoid

- **Blocking app launch on license check:** Never await license validation before showing the menu bar. Validation is best-effort background work; the app should be fully usable while validation is in-flight or the network is offline.
- **swift-lemon-squeezy-license SPM dependency:** Adds a 5.8 tools version package with no Swift 6 declaration to a Swift 6 strict codebase. The API is 3 POST endpoints — implement directly with URLSession.
- **Storing license key in Keychain:** Adds Keychain entitlement complexity (the app doesn't currently use the Keychain directly — TokenStore uses it via KeychainSwift-style logic, but the license key is not a secret). UserDefaults is acceptable. If added to Keychain, use `kSecClassGenericPassword` without an app group (no sandbox).
- **Hard-coding Lemon Squeezy store/product IDs as 0:** The `expectedStoreId` and `expectedProductId` must be set to real values before shipping; leave as `// TODO: fill in` placeholders in the plan, not zero.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| URL percent-encoding for form body | Custom string building | `URLComponents` with `.percentEncodedQuery` or Foundation's `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` | Handles special characters in license keys |
| JSON decoding of LS API response | Manual dictionary parsing | `Codable` structs + `JSONDecoder` | Type-safe, handles optional fields correctly |
| 30-day timer in-process | `Timer` polling | UserDefaults `Date` + check at launch | Process may not run continuously; check at launch is reliable |
| Source-available license text | Write from scratch | PolyForm Noncommercial 1.0.0 (pre-written, lawyer-reviewed) | Standard, well-known, easy for users to evaluate |

**Key insight:** The Lemon Squeezy License API is intentionally simple (3 endpoints, form encoding, no auth token). Don't over-engineer — a single `LicenseService.swift` of ~150 lines covers the entire integration.

## Common Pitfalls

### Pitfall 1: Cross-product license key acceptance
**What goes wrong:** A user with a Lemon Squeezy key for a different product can unlock your app.
**Why it happens:** The License API validates the key format but not the product unless the client checks.
**How to avoid:** Always verify `response.meta.storeId == expectedStoreId && response.meta.productId == expectedProductId` after activation AND validation.
**Warning signs:** License key accepted even when purchased for unrelated product.

### Pitfall 2: Network failure treated as "not licensed"
**What goes wrong:** Offline user loses access after key was previously validated.
**Why it happens:** `validate()` fails with a network error and `isLicensed` is set to `false`.
**How to avoid:** Keep `isLicensed = true` if there is already a persisted key + instanceId; only revoke on explicit API rejection (e.g., `valid == false`), not on network errors. Use `URLError` type checking to distinguish network errors from API rejections.
**Warning signs:** Licensed users reported losing access when offline.

### Pitfall 3: LicenseNagController activation policy not restored
**What goes wrong:** After closing the nag dialog, app stays in `.regular` activation policy — appears in dock and app switcher.
**Why it happens:** `NSApp.setActivationPolicy(.regular)` called to show the nag panel but never reversed.
**How to avoid:** Follow the `SnippetWindowView.onDisappear` pattern: set `.accessory` in `windowWillClose` delegate or after `orderOut`.
**Warning signs:** Clipsmith icon appears in dock after showing nag.

### Pitfall 4: Nag date gating uses `TimeInterval` truncation
**What goes wrong:** Date comparison uses integer days and triggers nag one day early due to time-of-day difference.
**Why it happens:** Storing as calendar day instead of `Date` interval.
**How to avoid:** Store raw `Date` via `UserDefaults.standard.set(Date(), forKey:...)` and compare with `timeIntervalSince`.

### Pitfall 5: License key TextField triggering clipboard monitor
**What goes wrong:** Pasting a license key into the TextField gets captured by ClipboardMonitor as a new clipping.
**Why it happens:** TextField paste writes to NSPasteboard, which ClipboardMonitor polls.
**How to avoid:** This is inherent to the app's clipboard monitoring behavior — it's expected and acceptable. No special handling needed (PasteService's blockedChangeCount pattern only applies to programmatic Cmd-V paste, not user paste in a text field).

### Pitfall 6: instance_name must be stable
**What goes wrong:** Each launch creates a new activation instance (hits activation limit).
**Why it happens:** `instance_name` is generated fresh each launch and a new `/activate` is called every time.
**How to avoid:** Only call `/activate` once (when the user enters and submits the key). On subsequent launches, call `/validate` with the persisted `instance_id`. Never call activate if `instanceId` is already persisted.

## Code Examples

### Codable response types for LS License API

```swift
// Source: https://docs.lemonsqueezy.com/api/license-api/activate-license-key
struct LSActivateResponse: Codable, Sendable {
    let activated: Bool
    let error: String?
    let licenseKey: LSLicenseKey
    let instance: LSInstance
    let meta: LSMeta

    enum CodingKeys: String, CodingKey {
        case activated, error
        case licenseKey = "license_key"
        case instance, meta
    }
}

struct LSValidateResponse: Codable, Sendable {
    let valid: Bool
    let error: String?
    let licenseKey: LSLicenseKey
    let instance: LSInstance?     // null when no instance_id provided
    let meta: LSMeta

    enum CodingKeys: String, CodingKey {
        case valid, error
        case licenseKey = "license_key"
        case instance, meta
    }
}

struct LSLicenseKey: Codable, Sendable {
    let id: Int
    let status: String            // "inactive" | "active" | "expired" | "disabled"
    let key: String
    let activationLimit: Int
    let activationUsage: Int
    let createdAt: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct LSInstance: Codable, Sendable {
    let id: String
    let name: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct LSMeta: Codable, Sendable {
    let storeId: Int
    let orderId: Int
    let productId: Int
    let variantId: Int
    let customerName: String
    let customerEmail: String

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case orderId = "order_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
    }
}
```

### URLSession form-encoded POST helper

```swift
// Source: Apple Foundation docs — standard URLRequest form body pattern
private func post<T: Decodable>(path: String, params: [String: String]) async throws -> T {
    let url = baseURL.appending(path: path)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = params
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        .data(using: .utf8)
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(T.self, from: data)
}
```

### LicenseNagView structure

```swift
// Non-blocking startup nag — informational, not modal
struct LicenseNagView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scissors")
                .font(.system(size: 48))
            Text("Enjoying Clipsmith?")
                .font(.title2.bold())
            Text("Clipsmith is free for personal use. If you use it for work, please consider supporting development.")
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Sponsor on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/haad")!)
                }
                Button("Buy a License") {
                    NSWorkspace.shared.open(URL(string: "https://store.lemonsqueezy.com/...")!)
                }
                .buttonStyle(.borderedProminent)
            }
            Button("I Already Have a License") {
                // Post notification to open Settings > License tab
            }
            .buttonStyle(.plain)
            .font(.footnote)
        }
        .padding(24)
        .frame(width: 380)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Paddle / FastSpring for Mac licensing | Lemon Squeezy (simpler, lower fees) | ~2022 onward | Indie-preferred; no SDK required, public REST API |
| Blocking license check at launch | Non-blocking nag + background validation | Industry norm for goodwill | Prevents offline frustration, better UX |
| GPL/MIT for source-available indie apps | PolyForm Noncommercial | 2019 (PolyForm launch) | Lawyer-reviewed template; non-commercial users can use freely |
| Storing license keys in Keychain | UserDefaults (for non-secret data) | N/A | License keys are not secret — users share them; Keychain adds unnecessary entitlement complexity |

**Deprecated/outdated:**
- Paddle SDK: Requires sandbox exception + separate license validation infrastructure; Lemon Squeezy has no SDK requirement.
- LicenseKit (Swift package): Adds complexity; the LS License API is 3 HTTP calls.

## Open Questions

1. **Lemon Squeezy store_id and product_id values**
   - What we know: These IDs are assigned when you create a store and product on lemonsqueezy.com
   - What's unclear: The actual numeric IDs are not known until the store is created; they are required to be hard-coded before shipping
   - Recommendation: Use placeholder constants (`// TODO: set before shipping`) in the LicenseService implementation; the planner should note this as a Wave 0 prerequisite

2. **Lemon Squeezy purchase page URL**
   - What we know: The URL format is `https://store.lemonsqueezy.com/buy/<product-slug>`
   - What's unclear: The slug is not known until the product is created
   - Recommendation: Same placeholder approach; the FUNDING.yml and nag view both need this URL

3. **License tier model (one-time vs subscription)**
   - What we know: Lemon Squeezy supports both one-time payment and subscriptions
   - What's unclear: Whether the phase should handle subscription expiry/renewal (the `expires_at` field)
   - Recommendation: Start with one-time purchase only; `expires_at` null = perpetual. Check `license_key.status != "expired"` during validation as a hedge.

4. **Activation limit per license**
   - What we know: Lemon Squeezy supports configurable activation limits per product
   - What's unclear: What the limit should be (1 machine vs N machines per license)
   - Recommendation: 3 activations per license is industry standard for indie apps; handle `activation_limit` exceeded error gracefully with user-facing message

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (native — no separate install needed) |
| Config file | Xcode scheme targets ClipsmithTests |
| Quick run command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/LicenseServiceTests` |
| Full suite command | `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LIC-01 | Startup nag shows after 30 days, not before | unit | `...LicenseServiceTests/testNagGating` | Wave 0 |
| LIC-02 | Activate returns licensed=true on valid key | unit (mock URLSession) | `...LicenseServiceTests/testActivateSuccess` | Wave 0 |
| LIC-03 | Activate rejects key from wrong product | unit (mock URLSession) | `...LicenseServiceTests/testActivateWrongProduct` | Wave 0 |
| LIC-04 | Validate re-uses persisted instance_id, not re-activating | unit | `...LicenseServiceTests/testValidateUsesInstanceId` | Wave 0 |
| LIC-05 | Network error during validate does not revoke license | unit (mock URLSession) | `...LicenseServiceTests/testValidateNetworkErrorKeepsLicense` | Wave 0 |
| LIC-06 | Deactivate clears persisted key + instanceId | unit | `...LicenseServiceTests/testDeactivateClearsState` | Wave 0 |

**MockURLProtocol pattern:** Project uses `MockURLProtocol` already in `GistServiceTests.swift` — reuse the same pattern for `LicenseServiceTests`.

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS' -only-testing:ClipsmithTests/LicenseServiceTests`
- **Per wave merge:** `xcodebuild test -scheme Clipsmith -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `ClipsmithTests/LicenseServiceTests.swift` — covers LIC-01 through LIC-06
- [ ] `LicenseService.swift` must be injectable with a `URLSession` to enable mocking (mirrors `GistService` pattern)

## Sources

### Primary (HIGH confidence)
- [https://docs.lemonsqueezy.com/api/license-api/activate-license-key](https://docs.lemonsqueezy.com/api/license-api/activate-license-key) — endpoint, parameters, response structure
- [https://docs.lemonsqueezy.com/api/license-api/validate-license-key](https://docs.lemonsqueezy.com/api/license-api/validate-license-key) — validate endpoint, full response JSON schema
- [https://docs.lemonsqueezy.com/api/license-api/deactivate-license-key](https://docs.lemonsqueezy.com/api/license-api/deactivate-license-key) — deactivate endpoint
- [https://docs.lemonsqueezy.com/guides/tutorials/license-keys](https://docs.lemonsqueezy.com/guides/tutorials/license-keys) — security best practices, recommended flow
- [https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository) — FUNDING.yml `custom:` field syntax, supported platforms
- [https://polyformproject.org/licenses/](https://polyformproject.org/licenses/) — PolyForm license options
- Project source: `Clipsmith/Settings/AppSettingsKeys.swift`, `Clipsmith/App/AppDelegate.swift`, `Clipsmith/Views/SettingsView.swift`, `Clipsmith/App/ClipsmithApp.swift` — verified existing patterns

### Secondary (MEDIUM confidence)
- [https://github.com/kevinhermawan/swift-lemon-squeezy-license](https://github.com/kevinhermawan/swift-lemon-squeezy-license) — Swift package API surface and Package.swift requirements (verified: swift-tools-version 5.8, no Swift 6 declaration — **do not use**)

### Tertiary (LOW confidence)
- Community convention: 30-day nag period for indie apps — widely observed but no authoritative source
- Community convention: 3-machine activation limit as industry norm — unverified count, use LS dashboard setting

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified from official docs; URLSession/UserDefaults are established project patterns
- Architecture: HIGH — patterns derived directly from existing project patterns (BezelController, GistService, DocsetSettingsSection, SnippetWindowView)
- Pitfalls: HIGH (cross-product key, network failure handling, activation limit) / MEDIUM (nag date gating edge cases)
- License choice: MEDIUM — PolyForm Noncommercial is appropriate but the specific text and "free for personal, paid for commercial" framing needs final user decision

**Research date:** 2026-03-20
**Valid until:** 2026-09-20 (Lemon Squeezy API is stable; PolyForm licenses are versioned)
