import XCTest
@testable import Clipsmith

/// Unit tests for `AppLaunchViewModel` — ranking, recency boost, empty-query behavior,
/// and navigation clamping.
@MainActor
final class AppLaunchViewModelTests: XCTestCase {

    private var viewModel: AppLaunchViewModel!

    override func setUp() {
        super.setUp()
        viewModel = AppLaunchViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEntry(name: String, bundleID: String) -> AppEntry {
        AppEntry(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleID: bundleID,
            icon: nil
        )
    }

    // MARK: - Tests

    /// D-05: FuzzyMatcher ranks apps by score — prefix/consecutive matches score higher
    /// than non-consecutive matches.
    ///
    /// Query "fi":
    ///  - "Finder"  scores 1.0 (f-i are the first two characters, perfect consecutive match)
    ///  - "FaceTime" scores ~0.67 (F matches at 0, i matches at 5 — non-consecutive)
    ///  - "Safari"  scores ~0.67 (f at index 2, i at index 5 — non-consecutive)
    ///  - "Notes"   has no 'i', so scores nil → excluded
    func testFuzzyFilterReturnsRankedMatches() {
        let finder = makeEntry(name: "Finder", bundleID: "com.apple.Finder")
        let faceTime = makeEntry(name: "FaceTime", bundleID: "com.apple.FaceTime")
        let safari = makeEntry(name: "Safari", bundleID: "com.apple.Safari")
        let notes = makeEntry(name: "Notes", bundleID: "com.apple.Notes")

        viewModel.apps = [finder, faceTime, safari, notes]
        viewModel.searchText = "fi"

        // Notes must not appear (no 'i' → no subsequence match)
        let names = viewModel.displayedApps.map(\.name)
        XCTAssertFalse(names.contains("Notes"), "Notes should not match query 'fi'")

        // Finder, FaceTime, and Safari all match
        XCTAssertTrue(names.contains("Finder"), "Finder must appear for query 'fi'")
        XCTAssertTrue(names.contains("FaceTime"), "FaceTime must appear for query 'fi'")
        XCTAssertTrue(names.contains("Safari"), "Safari must appear for query 'fi'")

        // Finder must rank first (score 1.0 vs ~0.67 for the others)
        let finderIndex = names.firstIndex(of: "Finder")!
        let faceTimeIndex = names.firstIndex(of: "FaceTime")!
        let safariIndex = names.firstIndex(of: "Safari")!
        XCTAssertEqual(finderIndex, 0,
            "Finder must rank first for query 'fi' (perfect consecutive score 1.0)")
        // FaceTime and Safari tie at ~0.67; tie-break alphabetically: FaceTime < Safari
        XCTAssertLessThan(faceTimeIndex, safariIndex,
            "FaceTime must rank before Safari for equal scores (tie-break alphabetical)")
    }

    /// D-05: When two apps both match, the one with a matching bundleID in recentBundleIDs
    /// gets a +0.1 recency boost that can promote it above the other.
    func testRecencyBoostPromotesRecentApp() {
        let terminal = makeEntry(name: "Terminal", bundleID: "com.apple.Terminal")
        let textEdit = makeEntry(name: "TextEdit", bundleID: "com.apple.TextEdit")

        viewModel.apps = [terminal, textEdit]

        // Without recency boost: neither app has recency advantage.
        // Both "Terminal" and "TextEdit" match "te"; compare pure fuzzy scores.
        viewModel.recentBundleIDs = []
        viewModel.searchText = "te"

        let namesNoBoost = viewModel.displayedApps.map(\.name)
        // Both should appear
        XCTAssertTrue(namesNoBoost.contains("Terminal"), "Terminal must match 'te'")
        XCTAssertTrue(namesNoBoost.contains("TextEdit"), "TextEdit must match 'te'")

        // With recency boost on TextEdit: TextEdit gets +0.1 and must rank first.
        viewModel.recentBundleIDs = ["com.apple.TextEdit"]
        viewModel.searchText = "te"  // Re-trigger recompute (searchText set, didSet fires)

        let namesBoosted = viewModel.displayedApps.map(\.name)
        XCTAssertTrue(namesBoosted.contains("TextEdit"), "TextEdit must appear when boosted")
        XCTAssertTrue(namesBoosted.contains("Terminal"), "Terminal must still appear")

        let textEditIndex = namesBoosted.firstIndex(of: "TextEdit")!
        let terminalIndex = namesBoosted.firstIndex(of: "Terminal")!
        XCTAssertLessThan(textEditIndex, terminalIndex,
            "TextEdit must rank above Terminal due to +0.1 recency boost")
    }

    /// D-04: Empty query shows up to 5 most recently launched apps in recency order.
    func testEmptyQueryShowsRecentApps() {
        // Create 10 apps
        var tenApps: [AppEntry] = []
        for i in 1...10 {
            tenApps.append(makeEntry(name: "App\(i)", bundleID: "com.test.app\(i)"))
        }
        viewModel.apps = tenApps

        // Test with 3 recents: displayedApps == [Safari, Terminal, Calendar] in recency order
        let safariEntry = makeEntry(name: "Safari", bundleID: "com.apple.Safari")
        let terminalEntry = makeEntry(name: "Terminal", bundleID: "com.apple.Terminal")
        let calendarEntry = makeEntry(name: "Calendar", bundleID: "com.apple.Calendar")
        viewModel.apps = tenApps + [safariEntry, terminalEntry, calendarEntry]
        viewModel.recentBundleIDs = ["com.apple.Safari", "com.apple.Terminal", "com.apple.Calendar"]
        viewModel.searchText = ""

        XCTAssertEqual(viewModel.displayedApps.count, 3,
            "Empty query with 3 recents should show exactly 3 apps")
        XCTAssertEqual(viewModel.displayedApps[0].name, "Safari",
            "First recent should be Safari (most recent)")
        XCTAssertEqual(viewModel.displayedApps[1].name, "Terminal",
            "Second recent should be Terminal")
        XCTAssertEqual(viewModel.displayedApps[2].name, "Calendar",
            "Third recent should be Calendar")

        // Test with 7 recents: only first 5 should appear
        var sevenRecents: [AppEntry] = []
        for i in 1...7 {
            let entry = makeEntry(name: "Recent\(i)", bundleID: "com.test.recent\(i)")
            sevenRecents.append(entry)
        }
        viewModel.apps = sevenRecents
        viewModel.recentBundleIDs = sevenRecents.map { $0.bundleID! }
        viewModel.searchText = ""

        XCTAssertEqual(viewModel.displayedApps.count, 5,
            "Empty query with 7 recents should show only first 5 (D-04 cap)")
        XCTAssertEqual(viewModel.displayedApps[0].bundleID, "com.test.recent1",
            "Most recent app must be first")
        XCTAssertEqual(viewModel.displayedApps[4].bundleID, "com.test.recent5",
            "Fifth most recent must be last in the capped list")
    }

    /// Navigation methods must clamp to displayedApps bounds and never crash on empty lists.
    func testNavigationClampsToList() {
        let app1 = makeEntry(name: "Alpha", bundleID: "com.test.alpha")
        let app2 = makeEntry(name: "Beta", bundleID: "com.test.beta")
        let app3 = makeEntry(name: "Gamma", bundleID: "com.test.gamma")

        viewModel.apps = [app1, app2, app3]
        viewModel.searchText = "" // empty search — no recents so displayedApps is empty here
        // Use a search that matches all three
        viewModel.searchText = "a" // "a" matches Alpha, Beta, Gamma (all have 'a')

        XCTAssertEqual(viewModel.displayedApps.count, 3, "All three apps should match query 'a'")

        // navigateDown 10 times from index 0 — should clamp at last index (2)
        viewModel.selectedIndex = 0
        for _ in 0..<10 { viewModel.navigateDown() }
        XCTAssertEqual(viewModel.selectedIndex, 2,
            "navigateDown clamped at last index (2) after 10 calls from 0")

        // navigateToFirst
        viewModel.navigateToFirst()
        XCTAssertEqual(viewModel.selectedIndex, 0, "navigateToFirst sets index to 0")

        // navigateToLast
        viewModel.navigateToLast()
        XCTAssertEqual(viewModel.selectedIndex, 2, "navigateToLast sets index to last (2)")

        // navigateTo(index: 99) — should clamp to 2
        viewModel.navigateTo(index: 99)
        XCTAssertEqual(viewModel.selectedIndex, 2, "navigateTo(99) clamps to last index (2)")

        // Empty displayedApps — navigate calls must not crash, selectedIndex stays 0
        viewModel.apps = []
        viewModel.searchText = "xyz_no_match_$$"
        XCTAssertTrue(viewModel.displayedApps.isEmpty, "displayedApps must be empty for no-match query")
        viewModel.selectedIndex = 0
        viewModel.navigateDown()   // must not crash
        viewModel.navigateUp()     // must not crash
        viewModel.navigateToFirst() // must not crash
        viewModel.navigateToLast()  // must not crash
        viewModel.navigateTo(index: 5) // must not crash
        XCTAssertEqual(viewModel.selectedIndex, 0,
            "selectedIndex remains 0 when displayedApps is empty")
    }
}
