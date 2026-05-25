import AppKit
import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "AppScannerService"
)

// MARK: - AppEntry

/// A value type representing an installed macOS application bundle.
///
/// `@unchecked Sendable` rationale: `NSImage` is not `Sendable` in Swift 6. The
/// `icon` property is set only from the `@MainActor`-isolated `AppScannerService`
/// after the background scan completes, so no concurrent mutation occurs in
/// practice. We accept this compromise to allow `AppEntry` to cross the
/// `@MainActor` boundary cleanly (consistent with `ClippingInfo` pattern).
struct AppEntry: @unchecked Sendable, Identifiable {
    /// Stable identifier derived from the bundle URL (unique per installed app).
    var id: URL { url }

    /// Display name: `CFBundleName` from `Info.plist`, falling back to the
    /// filename without the `.app` extension for malformed bundles.
    let name: String

    /// Absolute URL to the `.app` bundle on disk.
    let url: URL

    /// `CFBundleIdentifier` from the bundle. May be `nil` for malformed bundles.
    let bundleID: String?

    /// Application icon. `nil` until loaded asynchronously by Plan 02.
    var icon: NSImage?
}

// MARK: - AppScannerService

/// Scans installed macOS applications and tracks recently launched apps.
///
/// - Scanning: Enumerates `.app` bundles in the five whitelisted search paths
///   (CONTEXT D-01) one level deep. Deduplicates by `CFBundleIdentifier`.
/// - Recency tracking: Persists the last 5 launched bundle IDs to `UserDefaults`
///   under `AppSettingsKeys.recentAppBundleIDs` (CONTEXT D-04).
/// - Threading: `@MainActor @Observable` — properties are main-thread-only.
///   Scanning runs on a `Task.detached` background task and updates `apps` on
///   the main actor.
@MainActor @Observable
final class AppScannerService {

    // MARK: - Published State

    /// Full list of installed apps, sorted alphabetically by name.
    /// Populated by `refresh()`.
    private(set) var apps: [AppEntry] = []

    /// Bundle IDs of the most recently launched apps, ordered most-recent-first.
    /// Maximum 5 entries, persisted to `UserDefaults`.
    private(set) var recentBundleIDs: [String] = []

    /// `true` while a scan is in progress.
    private(set) var isLoading: Bool = false

    // MARK: - Init

    init() {
        recentBundleIDs = UserDefaults.standard.stringArray(
            forKey: AppSettingsKeys.recentAppBundleIDs
        ) ?? []
    }

    // MARK: - Public Methods

    /// Warm-up called once at app startup. Idempotent — delegates to `refresh()`.
    func loadInitially() async {
        await refresh()
    }

    /// Rescans all five search paths and updates `apps`.
    /// Guards against concurrent scans; safe to call multiple times.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let entries = await Task.detached(priority: .userInitiated) {
            await self.scanApps()
        }.value

        self.apps = entries
        logger.info("AppScannerService scanned \(entries.count) apps")
    }

    /// Records that an app was launched.
    ///
    /// Prepends `bundleID` to `recentBundleIDs`, removes any prior copy of the
    /// same ID (dedup), caps the list at 5, writes to `UserDefaults`, and
    /// updates the in-memory `recentBundleIDs`.
    func recordLaunch(bundleID: String) {
        var recent = UserDefaults.standard.stringArray(
            forKey: AppSettingsKeys.recentAppBundleIDs
        ) ?? []
        recent.removeAll { $0 == bundleID }
        recent.insert(bundleID, at: 0)
        if recent.count > 5 { recent = Array(recent.prefix(5)) }
        UserDefaults.standard.set(recent, forKey: AppSettingsKeys.recentAppBundleIDs)
        recentBundleIDs = recent
        logger.debug("Recorded launch: \(bundleID); recents=\(recent)")
    }

    // MARK: - Private Scan

    /// Enumerates the five whitelisted search paths one level deep, builds
    /// `AppEntry` values, deduplicates by bundle ID (fallback: resolved URL path),
    /// and returns entries sorted alphabetically by lowercased name.
    ///
    /// Marked `nonisolated` so it can be called from `Task.detached` without
    /// compiler warnings about capturing `self` across actor isolation.
    nonisolated func scanApps() async -> [AppEntry] {
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")

        // D-01: exactly these five search paths
        let searchPaths: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            homeApps,
        ]

        var seen: Set<String> = []
        var result: [AppEntry] = []

        for dirURL in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier

                // Deduplicate by bundle ID; fall back to resolved URL path (Pitfall 7)
                let dedupeKey = bundleID ?? url.resolvingSymlinksInPath().path

                guard !seen.contains(dedupeKey) else { continue }
                seen.insert(dedupeKey)

                // Prefer CFBundleName; fall back to filename sans .app (Pitfall 5)
                let name = (bundle?.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                result.append(AppEntry(name: name, url: url, bundleID: bundleID, icon: nil))
            }
        }

        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
