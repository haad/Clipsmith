import XCTest
@testable import Clipsmith

@MainActor
final class TodoWindowViewModelTests: XCTestCase {

    private var vm: TodoWindowViewModel!

    override func setUp() {
        super.setUp()
        vm = TodoWindowViewModel()
        vm.showCompleted = false
    }

    private let sample = TaskPaperParser.parse("""
    - inbox task @today
    Home:
    - overdue chore @due(2020-01-01)
    - future chore @due(2099-12-31)
    - done chore @done(2026-08-30)
    Work:
    - ship feature @today @done(2026-08-30)
    - review PR @urgent
    """ + "\n")

    private let noInbox = TaskPaperParser.parse("Home:\n- chore\n")

    // MARK: - Tabs

    func testTabsTodayFirstThenProjectsInFileOrder() {
        XCTAssertEqual(vm.tabs(for: sample), [
            .today, .project("Inbox"), .project("Home"), .project("Work"),
        ])
    }

    func testEmptyInboxTabHidden() {
        XCTAssertEqual(vm.tabs(for: noInbox), [.today, .project("Home")])
    }

    // MARK: - Today view

    func testTodayViewIncludesTodayTagAndOverdueDue() {
        vm.selectedTab = .today
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        // @today item + overdue @due item; done @today item hidden; future due hidden
        XCTAssertEqual(titles, ["inbox task", "overdue chore"])
    }

    func testTodayViewIncludesItemsDueExactlyToday() {
        vm.selectedTab = .today
        let doc = TaskPaperParser.parse("- due today @due(2026-08-31)\n")
        XCTAssertEqual(vm.visibleItems(in: doc, today: "2026-08-31").count, 1)
    }

    func testShowCompletedRevealsDoneItemsInToday() {
        vm.selectedTab = .today
        vm.showCompleted = true
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        XCTAssertTrue(titles.contains("ship feature"))
    }

    // MARK: - Project tabs

    func testProjectTabShowsItsTasksHidingDone() {
        vm.selectedTab = .project("Home")
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        XCTAssertEqual(titles, ["overdue chore", "future chore"])
    }

    func testCurrentProjectName() {
        vm.selectedTab = .today
        XCTAssertNil(vm.currentProjectName())
        vm.selectedTab = .project("Inbox")
        XCTAssertNil(vm.currentProjectName())
        vm.selectedTab = .project("Home")
        XCTAssertEqual(vm.currentProjectName(), "Home")
    }

    // MARK: - Search

    func testSearchFuzzyMatchesTitle() {
        vm.selectedTab = .project("Work")
        vm.searchText = "revpr"
        let titles = vm.visibleItems(in: sample, today: "2026-08-31").map(\.title)
        XCTAssertEqual(titles, ["review PR"])
    }

    func testSearchAtTermMatchesTags() {
        vm.selectedTab = .project("Work")
        vm.searchText = "@urgent"
        XCTAssertEqual(vm.visibleItems(in: sample, today: "2026-08-31").map(\.title),
                       ["review PR"])
        vm.searchText = "@nosuchtag"
        XCTAssertTrue(vm.visibleItems(in: sample, today: "2026-08-31").isEmpty)
    }

    // MARK: - Selection navigation

    func testSelectNextAndPrevious() {
        vm.selectedTab = .project("Home")
        let items = vm.visibleItems(in: sample, today: "2026-08-31")
        vm.selectNext(in: items)
        XCTAssertEqual(vm.selectedItemID, items[0].id)
        vm.selectNext(in: items)
        XCTAssertEqual(vm.selectedItemID, items[1].id)
        vm.selectNext(in: items) // clamps at end
        XCTAssertEqual(vm.selectedItemID, items[1].id)
        vm.selectPrevious(in: items)
        XCTAssertEqual(vm.selectedItemID, items[0].id)
    }
}
