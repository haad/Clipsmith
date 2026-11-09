import XCTest
@testable import Clipsmith

final class TodoNaturalDatesTests: XCTestCase {

    private let cal = Calendar.current
    /// Monday 2026-11-09, mid-day.
    private var monday: Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14))!
    }

    func testRelativeWords() {
        XCTAssertEqual(TodoNaturalDates.resolve("today", today: monday), "2026-11-09")
        XCTAssertEqual(TodoNaturalDates.resolve("Tomorrow", today: monday), "2026-11-10")
        XCTAssertEqual(TodoNaturalDates.resolve("+3d", today: monday), "2026-11-12")
        XCTAssertEqual(TodoNaturalDates.resolve("+2w", today: monday), "2026-11-23")
        XCTAssertEqual(TodoNaturalDates.resolve("+1m", today: monday), "2026-12-09")
    }

    func testWeekdaysAreTheNextOneAfterToday() {
        XCTAssertEqual(TodoNaturalDates.resolve("fri", today: monday), "2026-11-13")
        XCTAssertEqual(TodoNaturalDates.resolve("Friday", today: monday), "2026-11-13")
        XCTAssertEqual(TodoNaturalDates.resolve("mon", today: monday), "2026-11-16")
        XCTAssertEqual(TodoNaturalDates.resolve("sun", today: monday), "2026-11-15")
    }

    func testUnknownAndISOAreLeftAlone() {
        XCTAssertNil(TodoNaturalDates.resolve("2026-12-01", today: monday))
        XCTAssertNil(TodoNaturalDates.resolve("someday", today: monday))
        XCTAssertNil(TodoNaturalDates.resolve("fr", today: monday))
    }

    func testNormalizingDueInLine() {
        XCTAssertEqual(TodoNaturalDates.normalizingDue(in: "- ship @due(fri) @today", today: monday),
                       "- ship @due(2026-11-13) @today")
        XCTAssertEqual(TodoNaturalDates.normalizingDue(in: "- x @due(2026-01-01) @due(soon)", today: monday),
                       "- x @due(2026-01-01) @due(soon)")
    }

    func testAdvance() {
        XCTAssertEqual(TodoNaturalDates.advance("2026-11-09", every: "week"), "2026-11-16")
        XCTAssertEqual(TodoNaturalDates.advance("2026-01-31", every: "month"), "2026-02-28")
        XCTAssertEqual(TodoNaturalDates.advance("2026-11-09", every: "3d"), "2026-11-12")
        XCTAssertNil(TodoNaturalDates.advance("2026-11-09", every: "sometimes"))
        XCTAssertNil(TodoNaturalDates.advance("nope", every: "day"))
    }
}
