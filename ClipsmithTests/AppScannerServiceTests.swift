import XCTest
@testable import Clipsmith

@MainActor
final class AppScannerServiceTests: XCTestCase {

    private var service: AppScannerService!

    override func setUp() {
        super.setUp()
        // Clear recency state before each test to avoid cross-test pollution.
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.recentAppBundleIDs)
        service = AppScannerService()
    }

    override func tearDown() {
        // Restore clean state after each test.
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.recentAppBundleIDs)
        service = nil
        super.tearDown()
    }

    // MARK: - recordLaunch tests

    func testRecordLaunchPrependsBundleID() {
        service.recordLaunch(bundleID: "com.apple.Safari")
        XCTAssertEqual(service.recentBundleIDs.first, "com.apple.Safari",
                       "recordLaunch should prepend the bundle ID so it is first in recentBundleIDs")
    }

    func testRecordLaunchDeduplicates() {
        service.recordLaunch(bundleID: "A")
        service.recordLaunch(bundleID: "B")
        service.recordLaunch(bundleID: "A")  // re-record A — should move to front, not duplicate

        XCTAssertEqual(service.recentBundleIDs, ["A", "B"],
                       "Re-recording an existing bundle ID should move it to the front without duplicating")
    }

    func testRecordLaunchCapsAtFive() {
        let ids = ["id1", "id2", "id3", "id4", "id5", "id6", "id7"]
        for id in ids {
            service.recordLaunch(bundleID: id)
        }

        XCTAssertEqual(service.recentBundleIDs.count, 5,
                       "recentBundleIDs should never exceed 5 entries")
        XCTAssertEqual(service.recentBundleIDs.first, "id7",
                       "The most recently recorded bundle ID should be first")
    }

    func testRecordLaunchPersistsToUserDefaults() {
        service.recordLaunch(bundleID: "com.apple.Terminal")

        let stored = UserDefaults.standard.stringArray(forKey: AppSettingsKeys.recentAppBundleIDs)
        XCTAssertEqual(stored?.first, "com.apple.Terminal",
                       "recordLaunch should persist the bundle ID to UserDefaults")
    }
}
