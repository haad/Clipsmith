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
    ///
    /// After setting the initial (icon-nil) list, spawns a second Task.detached
    /// to load icons via NSWorkspace on a background thread (Pitfall 2 — never
    /// load icons on @MainActor during scan). Updates `apps` again when icons
    /// are ready.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let entries = await Task.detached(priority: .userInitiated) {
            await self.scanApps()
        }.value

        // Publish the icon-nil list immediately so the bezel can show app names
        self.apps = entries
        logger.info("AppScannerService scanned \(entries.count) apps")

        // Load icons on a background thread — NSWorkspace.icon(forFile:) is
        // documented as thread-safe (read-only file system access).
        let withIcons = await Task.detached(priority: .userInitiated) {
            self.loadIcons(for: entries)
        }.value
        self.apps = withIcons
        logger.debug("AppScannerService icon loading complete")
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

    // MARK: - Private Icon Loading

    /// Loads the app icon for each entry using `NSWorkspace.shared.icon(forFile:)`.
    ///
    /// `nonisolated` so it can be called from `Task.detached` without Swift 6
    /// compiler warnings about capturing `self` across actor isolation.
    ///
    /// `NSWorkspace.icon(forFile:)` is documented as thread-safe — it performs
    /// read-only file system access to load the icon from the bundle. No UI
    /// mutation occurs on the calling thread; results are batched and the returned
    /// array is assigned to `self.apps` on @MainActor after the Task completes.
    nonisolated private func loadIcons(for entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var copy = entry
            copy.icon = NSWorkspace.shared.icon(forFile: entry.url.path)
            return copy
        }
    }

    // MARK: - Private Scan

    /// Enumerates the five whitelisted search paths, builds `AppEntry` values,
    /// deduplicates by resolved URL path, and returns entries sorted
    /// alphabetically by lowercased name.
    ///
    /// Top-level `.app` bundles are picked up directly. Non-`.app` sub-folders
    /// (e.g. game installers like
    /// `/Applications/Baldur's Gate Enhanced Edition/Baldur's Gate - Enhanced Edition.app`)
    /// are descended one level so apps nested inside a container folder are
    /// discovered. When the container holds exactly one `.app`, the container
    /// folder name is used as the display name — these installers often set a
    /// generic `CFBundleName` like `BaldursGate-macOS`, and the folder name is
    /// what the user thinks of as the app.
    ///
    /// Dedup is by resolved URL path (not bundle ID) so that distinct installs
    /// which happen to share a `CFBundleIdentifier` — e.g. Beamdog's Baldur's
    /// Gate and Baldur's Gate II both ship as
    /// `com.beamdog.baldursgateenhancededition` — both survive. Symlinked
    /// duplicates across search paths still collapse correctly.
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

        // Search paths reachable as one-level subdirectories of another search
        // path (e.g. `/Applications/Utilities`). We must not descend into these
        // during container-folder scanning — the dedicated iteration handles
        // them with the right display-name semantics (no folder-name override).
        let searchPathSet: Set<String> = Set(searchPaths.map { $0.standardizedFileURL.path })

        var seen: Set<String> = []
        var result: [AppEntry] = []

        func appendIfApp(_ url: URL, displayNameOverride: String? = nil) {
            guard url.pathExtension == "app" else { return }

            let dedupeKey = url.resolvingSymlinksInPath().path
            guard !seen.contains(dedupeKey) else { return }
            seen.insert(dedupeKey)

            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier

            // Prefer caller-supplied override (container folder name) over
            // CFBundleName, with filename sans .app as final fallback.
            let name = displayNameOverride
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent

            result.append(AppEntry(name: name, url: url, bundleID: bundleID, icon: nil))
        }

        for dirURL in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                if url.pathExtension == "app" {
                    appendIfApp(url)
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          !searchPathSet.contains(url.standardizedFileURL.path) {
                    guard let subContents = try? FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    let nestedApps = subContents.filter { $0.pathExtension == "app" }
                    // Use the container folder name only when it unambiguously
                    // represents a single app. Multi-app containers fall back
                    // to each .app's own CFBundleName.
                    let override = nestedApps.count == 1 ? url.lastPathComponent : nil
                    for subURL in nestedApps {
                        appendIfApp(subURL, displayNameOverride: override)
                    }
                }
            }
        }

        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
