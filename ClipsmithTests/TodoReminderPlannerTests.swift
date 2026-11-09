import XCTest
@testable import Clipsmith

final class TodoReminderPlannerTests: XCTestCase {

    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testPlansOpenTasksAtTheReminderTimeOnTheDueDay() {
        let tasks = [
            TodoItem(rawLine: "- later @due(2026-11-12)"),
            TodoItem(rawLine: "- soon @due(2026-11-10)"),
            TodoItem(rawLine: "- done @due(2026-11-10) @done(2026-11-09)"),
            TodoItem(rawLine: "- no date"),
            TodoItem(rawLine: "- past @due(2026-11-01)"),
        ]
        let plan = TodoReminderPlanner.plan(tasks: tasks, minutesAfterMidnight: 9 * 60, now: date(2026, 11, 9, 12))
        XCTAssertEqual(plan.map(\.title), ["soon", "later"])
        XCTAssertEqual(plan.first?.fireDate, date(2026, 11, 10, 9))
        XCTAssertEqual(plan.first?.identifier, "clipsmith.todo.2026-11-10.soon")
    }

    func testTodayAfterTheReminderTimeIsSkipped() {
        let tasks = [TodoItem(rawLine: "- today @due(2026-11-09)")]
        XCTAssertTrue(TodoReminderPlanner.plan(tasks: tasks, minutesAfterMidnight: 9 * 60, now: date(2026, 11, 9, 10)).isEmpty)
        XCTAssertEqual(TodoReminderPlanner.plan(tasks: tasks, minutesAfterMidnight: 9 * 60, now: date(2026, 11, 9, 8)).count, 1)
    }

    func testLimitAndDuplicates() {
        let tasks = (1...5).map { TodoItem(rawLine: "- t\($0) @due(2026-12-0\($0))") }
            + [TodoItem(rawLine: "- t1 @due(2026-12-01)")]
        let plan = TodoReminderPlanner.plan(tasks: tasks, minutesAfterMidnight: 0, now: date(2026, 11, 9), limit: 3)
        XCTAssertEqual(plan.map(\.title), ["t1", "t2"])
    }
}
