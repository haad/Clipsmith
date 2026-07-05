import XCTest
import SwiftData
@testable import Clipsmith

/// Tests for the version-gated bundled prompt load.
///
/// Tests are hosted in Clipsmith.app, so Bundle.main contains the real
/// Resources/prompts.json catalog.
@MainActor
final class PromptSyncServiceTests: XCTestCase {

    /// Isolated UserDefaults per test — avoids polluting UserDefaults.standard.
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "PromptSyncServiceTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - loadBundledPromptsIfNeeded

    func testLoadsBundleWhenNoVersionStored() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)
        let defaults = makeDefaults()
        let service = PromptSyncService()

        try await service.loadBundledPromptsIfNeeded(store: store, defaults: defaults)

        let ids = try await store.fetchAll()
        XCTAssertGreaterThan(ids.count, 11, "Full bundled catalog should load, not just the legacy 11")
        XCTAssertGreaterThan(
            defaults.integer(forKey: AppSettingsKeys.bundledPromptsVersion), 0,
            "Loaded catalog version should be persisted"
        )
    }

    func testSkipsLoadWhenStoredVersionCurrent() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)
        let defaults = makeDefaults()
        let service = PromptSyncService()

        // First load persists the catalog version.
        try await service.loadBundledPromptsIfNeeded(store: store, defaults: defaults)
        let version = defaults.integer(forKey: AppSettingsKeys.bundledPromptsVersion)

        // Delete everything, then load again — the gate must skip (deleted prompts
        // must NOT resurrect while the catalog version is unchanged).
        for id in try await store.fetchAll() {
            try await store.delete(id: id)
        }
        try await service.loadBundledPromptsIfNeeded(store: store, defaults: defaults)

        let ids = try await store.fetchAll()
        XCTAssertTrue(ids.isEmpty, "Same catalog version must not re-load prompts")
        XCTAssertEqual(defaults.integer(forKey: AppSettingsKeys.bundledPromptsVersion), version)
    }

    func testLoadRunsWhenStoredVersionOlder() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)
        let defaults = makeDefaults()
        defaults.set(1, forKey: AppSettingsKeys.bundledPromptsVersion)
        let service = PromptSyncService()

        try await service.loadBundledPromptsIfNeeded(store: store, defaults: defaults)

        let ids = try await store.fetchAll()
        XCTAssertGreaterThan(ids.count, 11, "Newer bundled catalog should load over stored version 1")
    }
}
