---
phase: 10-lemon-squeezy-licensing-monetization
verified: 2026-03-20T16:00:00Z
status: gaps_found
score: 10/12 must-haves verified
re_verification: false
gaps:
  - truth: "Users can enter a license key in Settings and see validation feedback"
    status: failed
    reason: "LicenseService.activate() throws errors but never sets lastError. LicenseSettingsSection.activateLicense() catches errors silently with a comment claiming 'LicenseService sets lastError internally' — but it does not. The lastError UI block (if let error = licenseService.lastError) will never display anything on activation failure."
    artifacts:
      - path: "Clipsmith/Services/LicenseService.swift"
        issue: "activate() sets lastError = nil on entry (line 166) but never assigns a non-nil value on any error path. On throw, lastError remains nil."
      - path: "Clipsmith/Views/Settings/LicenseSettingsSection.swift"
        issue: "activateLicense() do/catch block swallows all errors (lines 82-87) with incorrect comment. Error is neither displayed nor propagated."
    missing:
      - "LicenseService.activate() must set lastError = error.localizedDescription before re-throwing, OR LicenseSettingsSection.activateLicense() catch block must set licenseService.lastError = error.localizedDescription"
  - truth: "LIC-01 through LIC-11 requirements cross-referenced against REQUIREMENTS.md"
    status: failed
    reason: "REQUIREMENTS.md contains no LIC-* requirements at all. The 11 requirement IDs (LIC-01 through LIC-11) declared in the phase plans are orphaned — they exist in plan frontmatter and ROADMAP.md but were never added to .planning/REQUIREMENTS.md."
    artifacts:
      - path: ".planning/REQUIREMENTS.md"
        issue: "No LIC-* entries exist. The file covers v1 requirements (CLIP, INTR, BEZL, SHELL, SETT, FAVR, SNIP, GIST, DOCS) but was not updated for Phase 10 licensing requirements."
    missing:
      - "Add LIC-01 through LIC-11 entries to .planning/REQUIREMENTS.md under a new 'Licensing & Monetization' section and add them to the traceability table"
human_verification:
  - test: "Verify nag dialog appears on first launch with no license set"
    expected: "Dialog shows scissors icon, 'Enjoying Clipsmith?' title, 'Sponsor on GitHub' and 'Buy a License' buttons, and 'I Already Have a License' plain button"
    why_human: "NSPanel display and UI layout cannot be verified programmatically"
  - test: "Click 'I Already Have a License' in nag dialog"
    expected: "Nag closes, Settings opens, and the License tab is pre-selected (not General)"
    why_human: "Tab navigation is driven by @AppStorage timing; must confirm the tab selection actually works in a running app"
  - test: "Open Settings > License tab while unlicensed"
    expected: "TextField for license key is shown, Activate button is disabled when empty, becomes enabled when text is typed, ProgressView shows during validation"
    why_human: "UI state transitions require a running app to verify"
  - test: "Close nag dialog — verify activation policy"
    expected: "App returns to menu-bar-only mode (no dock icon)"
    why_human: "Activation policy restoration happens asynchronously via DispatchQueue and requires visual confirmation"
  - test: "Verify 30-day nag gating"
    expected: "Nag does not reappear within 30 days of being shown. Reappears after 30+ days."
    why_human: "Time-gated behavior requires date manipulation to test"
---

# Phase 10: Lemon Squeezy Licensing & Monetization Verification Report

**Phase Goal:** Add startup license dialog prompting users to sponsor on GitHub or buy a commercial license via Lemon Squeezy. Add license key validation in Settings to dismiss the prompt. Add .github/FUNDING.yml for GitHub Sponsors. Add a source-available license file. The startup dialog should be non-blocking, show periodically (every 30 days), and link to both GitHub Sponsors and Lemon Squeezy purchase page. License key entry in Settings should validate against Lemon Squeezy API and persist to UserDefaults.
**Verified:** 2026-03-20T16:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Plan 01)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | LicenseService.activate(key:) calls Lemon Squeezy /activate endpoint and persists license_key + instance_id on success | VERIFIED | Lines 172-204 of LicenseService.swift: POSTs to `/activate`, persists to UserDefaults on `activated==true` |
| 2 | LicenseService.activate(key:) rejects keys from wrong store/product | VERIFIED | Lines 194-197: guard checks `meta.storeId == expectedStoreId && meta.productId == expectedProductId` |
| 3 | LicenseService.validate() re-uses persisted instance_id, does not re-activate | VERIFIED | Lines 212-249: reads `AppSettingsKeys.licenseInstanceId`, POSTs to `/validate` with `instance_id` param |
| 4 | Network errors during validate do not revoke an already-licensed state | VERIFIED | Lines 230-233: `catch is URLError { return }` — exits without modifying `isLicensed` |
| 5 | LicenseService.deactivate() clears persisted license_key and instance_id | VERIFIED | Lines 271-275: `removeObject` for both keys, `isLicensed = false` |
| 6 | Nag gating logic correctly determines whether 30 days have passed since last nag | VERIFIED | Lines 282-287: `shouldShowNag()` compares `timeIntervalSinceNow < -(30 * 24 * 3600)` |

### Observable Truths (Plan 02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 7 | Unlicensed users see a nag dialog on launch after 30 days with links to Sponsor and Buy | VERIFIED | AppDelegate lines 178-183: checks `!licenseService.isLicensed && LicenseService.shouldShowNag()` then shows nag after 1s delay |
| 8 | Clicking "I Already Have a License" opens Settings to the License tab | VERIFIED (wiring) | LicenseNagController.onHaveKey → onOpenSettings closure → AppDelegate posts `.clipsmithOpenLicenseSettings` → `handleOpenLicenseSettings` writes `SettingsTab.license.rawValue` to UserDefaults before `showSettingsWindow:` |
| 9 | Users can enter a license key in Settings and see validation feedback | FAILED | `licenseService.lastError` is never set on activation failure — error display is broken (see Gaps Summary) |
| 10 | Licensed users see a green checkmark and customer email in Settings | VERIFIED | LicenseSettingsSection lines 19-36: `if licenseService.isLicensed` shows `checkmark.circle.fill` + `customerEmail` |
| 11 | Nag dialog never appears for licensed users | VERIFIED | AppDelegate line 178: `if !licenseService.isLicensed` gate. LicenseService.init() reads persisted keys and sets `isLicensed=true` if both present. |
| 12 | App activation policy returns to .accessory after nag dialog closes | VERIFIED (code) | LicenseNagController lines 84-93: `restoreAccessoryPolicy()` called from `windowWillClose` and `close()`. Defers 100ms then checks for visible non-panel windows. |

**Score:** 10/12 truths verified (1 failed, 1 REQUIREMENTS.md orphan)

### Required Artifacts

| Artifact | Min Lines | Actual Lines | Status | Details |
|----------|-----------|--------------|--------|---------|
| `Clipsmith/Services/LicenseService.swift` | — | 304 | VERIFIED | @MainActor @Observable LicenseService with all 6 Codable types, LicenseError enum, activate/validate/deactivate/shouldShowNag |
| `ClipsmithTests/LicenseServiceTests.swift` | 100 | 426 | VERIFIED | 11 tests, no duplicate MockURLProtocol declaration, uses makeMockSession() pattern from GistServiceTests |
| `Clipsmith/Views/LicenseNagController.swift` | 40 | 94 | VERIFIED | Activating NSPanel, showNag/close, restoreAccessoryPolicy via NSWindowDelegate |
| `Clipsmith/Views/LicenseNagView.swift` | 25 | 40 | VERIFIED | SwiftUI view with onSponsor/onBuy/onHaveKey callbacks |
| `Clipsmith/Views/Settings/LicenseSettingsSection.swift` | 40 | 89 | VERIFIED | License key entry, unlicensed/licensed states, onAppear validate |
| `LICENSE` | — | — | VERIFIED | PolyForm Noncommercial License 1.0.0 — first line confirmed |
| `.github/FUNDING.yml` | — | — | VERIFIED | `github: haad`, Lemon Squeezy custom URL |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `LicenseService.swift` | `api.lemonsqueezy.com/v1/licenses` | URLSession POST form-encoded | VERIFIED | `baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!` line 141 |
| `LicenseService.swift` | UserDefaults | `AppSettingsKeys.licenseKey` | VERIFIED | `UserDefaults.standard.set(key, forKey: AppSettingsKeys.licenseKey)` line 200 |
| `AppDelegate.swift` | `LicenseNagController.swift` | `licenseNagController.showNag()` after 1s | VERIFIED | AppDelegate line 181: `self?.licenseNagController.showNag()` in asyncAfter |
| `LicenseSettingsSection.swift` | `LicenseService.swift` | `licenseService.activate(key:)` | PARTIAL | Wired — but error path is broken: `activate()` throws but `lastError` is never set, so UI error display is dead |
| `LicenseNagView.swift` | Settings (License tab) | NotificationCenter + onOpenSettings closure | VERIFIED | LicenseNagController.onHaveKey closure → `self.onOpenSettings?()` → AppDelegate post → `handleOpenLicenseSettings` |
| `AppDelegate.swift` | `SettingsView.swift` | Sets `selectedSettingsTab` to 5 before `showSettingsWindow:` | VERIFIED | AppDelegate line 347: `UserDefaults.standard.set(SettingsTab.license.rawValue, ...)` before `sendAction` |

### Requirements Coverage

LIC-01 through LIC-11 are declared in plan frontmatter and ROADMAP.md but are **not present in .planning/REQUIREMENTS.md**. This is an orphaned requirements scenario.

| Requirement | Source Plan | Evidence in Code | Status |
|-------------|------------|-----------------|--------|
| LIC-01 | 10-01-PLAN.md | `func activate(key: String) async throws` in LicenseService.swift | SATISFIED (code) |
| LIC-02 | 10-01-PLAN.md | `guard response.meta.storeId == LicenseService.expectedStoreId` | SATISFIED (code) |
| LIC-03 | 10-01-PLAN.md | `func validate() async` using `instance_id` param | SATISFIED (code) |
| LIC-04 | 10-01-PLAN.md | `catch is URLError { return }` in validate() — no revocation | SATISFIED (code) |
| LIC-05 | 10-01-PLAN.md | `func deactivate() async` clears both UserDefaults keys | SATISFIED (code) |
| LIC-06 | 10-01-PLAN.md | `static func shouldShowNag() -> Bool` with 30-day gate | SATISFIED (code) |
| LIC-07 | 10-02-PLAN.md | LicenseNagController + LicenseNagView with Sponsor/Buy/HaveKey | SATISFIED (code) |
| LIC-08 | 10-02-PLAN.md | AppDelegate nag gating: `if !licenseService.isLicensed && LicenseService.shouldShowNag()` | SATISFIED (code) |
| LIC-09 | 10-02-PLAN.md | LicenseSettingsSection with TextField + Activate button + licensed state display | PARTIAL — error feedback broken |
| LIC-10 | 10-02-PLAN.md | LICENSE (PolyForm Noncommercial), FUNDING.yml (github: haad) | SATISFIED (code) |
| LIC-11 | 10-02-PLAN.md | handleOpenLicenseSettings writes selectedSettingsTab before showSettingsWindow | SATISFIED (code) |

**ORPHANED:** All 11 LIC-* requirement IDs exist in plan frontmatter but not in `.planning/REQUIREMENTS.md`. The file must be updated.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `LicenseService.swift` | 127, 129 | `expectedStoreId = 0`, `expectedProductId = 0` (TODO placeholders) | Info | Known pre-ship placeholder — documented. With these at 0, any real Lemon Squeezy key for a different product will pass the store/product check (since most real store IDs won't be 0). Must be set before shipping. |
| `LicenseNagController.swift` | 20 | `TODO-product-slug` in purchase URL | Info | Nag dialog "Buy a License" button will navigate to an invalid URL until set |
| `LicenseSettingsSection.swift` | 60 | `TODO-product-slug` in Buy link | Info | Same — Settings "Buy a License" link will be invalid until set |
| `.github/FUNDING.yml` | 3 | `TODO-product-slug` in custom URL | Info | Affects GitHub Sponsors button display |
| `LicenseSettingsSection.swift` | 84-85 | Error catch block swallows all errors silently | Blocker | Users get no error feedback when activation fails (wrong key, network error, wrong product) |

### Human Verification Required

#### 1. Nag Dialog Appearance

**Test:** Build and run app with no license key set and `lastNagShownDate` cleared from UserDefaults. Wait ~1 second.
**Expected:** Floating dialog appears with scissors icon, "Enjoying Clipsmith?" title, description text, "Sponsor on GitHub" (bordered) and "Buy a License" (borderedProminent) buttons side by side, and "I Already Have a License" plain footnote button below.
**Why human:** NSPanel display and visual layout require a running app.

#### 2. "I Already Have a License" Navigation

**Test:** Click the "I Already Have a License" button in the nag dialog.
**Expected:** Nag dialog closes, Settings window opens, and the License tab is immediately selected (not General tab).
**Why human:** `@AppStorage` timing and tab programmatic selection require runtime verification.

#### 3. Activation Policy After Nag Close

**Test:** Show the nag dialog, then close it via the window close button (not "I Already Have a License").
**Expected:** App dock icon disappears within ~100ms of the window closing. App returns to menu-bar-only mode.
**Why human:** `setActivationPolicy(.accessory)` and its 100ms deferred execution require runtime verification.

#### 4. 30-Day Nag Gate Behavior

**Test:** After first launch (nag shown), quit and relaunch immediately.
**Expected:** Nag does NOT appear on second launch because `lastNagShownDate` was set to today.
**Why human:** Requires running app with UserDefaults inspection.

#### 5. Settings License Tab — Error Display (EXPECTED TO FAIL)

**Test:** Open Settings > License tab, enter an invalid license key (e.g. "INVALID-KEY-12345"), click "Activate License".
**Expected:** ProgressView appears briefly, then an error message in red is displayed below the button (e.g. "License key not found. Check your key and try again.").
**Why human:** This is also flagged as a code gap — the error display will not work until `lastError` is set in `activate()`. This test is expected to fail.

## Gaps Summary

### Gap 1: Activation Error Feedback is Broken (Blocker)

The truth "Users can enter a license key in Settings and see validation feedback" fails because the error display path has a broken wire.

**Root cause:** `LicenseService.activate()` declares `var lastError: String? = nil` as an observable property and clears it at entry, but never assigns an error message when it throws. The design intention (visible in the Settings section comment "LicenseService sets lastError internally") was to have the service own the error state, but the implementation was never completed.

**Fix options:**

Option A (Service owns error state — matches the comment): Add `lastError = error.localizedDescription` before each `throw` in `activate()`, or add `do { ... } catch { lastError = error.localizedDescription; throw error }` wrapping.

Option B (View owns error state): In `LicenseSettingsSection.activateLicense()`, change the catch block to set a local `@State var errorMessage: String?` and display that instead. Remove the dead `if let error = licenseService.lastError` block.

Option A is recommended for consistency with the existing `lastError` property and Settings UI.

### Gap 2: LIC Requirements Absent from REQUIREMENTS.md

All 11 LIC-* requirement IDs exist only in plan frontmatter and ROADMAP.md phase description. They were never added to `.planning/REQUIREMENTS.md`. The traceability table at the bottom of REQUIREMENTS.md does not include Phase 10 rows.

This does not affect code functionality but breaks requirements traceability for the project.

---

_Verified: 2026-03-20T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
