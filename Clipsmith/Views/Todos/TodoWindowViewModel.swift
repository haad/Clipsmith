import Foundation
import Observation

/// Pure UI state for the todo window: tab selection, search, show-completed,
/// selection. Filtering operates on a passed-in document — no store, no I/O —
/// so every behavior is unit-testable.
@MainActor
@Observable
final class TodoWindowViewModel {

    enum Tab: Hashable {
        case today
        case all
        case project(String)

        var label: String {
            switch self {
            case .today: "Today"
            case .all: "All"
            case .project(let name): name
            }
        }
    }

    var selectedTab: Tab = .today
    var searchText = ""
    var selectedItemID: UUID?

    var showCompleted: Bool = UserDefaults.standard.bool(forKey: AppSettingsKeys.todoShowCompleted) {
        didSet {
            UserDefaults.standard.set(showCompleted, forKey: AppSettingsKeys.todoShowCompleted)
        }
    }

    // MARK: - Tabs

    /// Today, All, then projects in file order. Inbox has no tab of its own:
    /// its tasks (those outside any project) show under All.
    /// Legal TaskPaper can have two projects with the same name; those
    /// collapse into a single tab (first occurrence wins the position).
    func tabs(for document: TaskPaperDocument) -> [Tab] {
        var tabs: [Tab] = [.today, .all]
        var seenNames = Set<String>()
        for project in document.projects {
            if project.isInbox { continue }
            guard seenNames.insert(project.name).inserted else { continue }
            tabs.append(.project(project.name))
        }
        return tabs
    }

    /// ⇧⌘[ / ⇧⌘]: step through `tabs`, clamped at both ends. A selected tab
    /// that no longer exists (project removed externally) lands on Today.
    func moveTab(by delta: Int, in tabs: [Tab]) {
        guard let current = tabs.firstIndex(of: selectedTab) else {
            selectedTab = .today
            return
        }
        selectedTab = tabs[max(0, min(tabs.count - 1, current + delta))]
    }

    /// Target project for a new task: nil (→ Inbox) on Today and All tabs.
    func currentProjectName() -> String? {
        if case .project(let name) = selectedTab, name != "Inbox" { return name }
        return nil
    }

    // MARK: - Filtering

    /// `today` is "YYYY-MM-DD"; due-date comparison is lexicographic, which
    /// is correct for that format.
    func visibleItems(in document: TaskPaperDocument,
                      today: String = TodoDates.dateString()) -> [TodoItem] {
        let base: [TodoItem]
        switch selectedTab {
        case .today:
            base = document.allTasks.filter { item in
                item.isToday || (item.dueDateString.map { $0 <= today } ?? false)
            }
        case .all:
            base = document.allTasks
        case .project(let name):
            // Aggregate across ALL projects with this name (file order):
            // legal TaskPaper can repeat a project name, and every one of
            // them must stay reachable from its single tab.
            base = document.projects.filter { $0.name == name }.flatMap(\.tasks)
        }
        return base
            .filter { showCompleted || !$0.isDone }
            .filter { matchesSearch($0) }
    }

    private func matchesSearch(_ item: TodoItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        for term in query.split(whereSeparator: \.isWhitespace) {
            if term.hasPrefix("@"), term.count > 1 {
                let name = term.dropFirst().lowercased()
                guard item.tags.contains(where: { $0.name.lowercased().hasPrefix(name) })
                else { return false }
            } else {
                guard FuzzyMatcher.score(item.title, query: String(term)) != nil
                else { return false }
            }
        }
        return true
    }

    // MARK: - Selection navigation

    func selectNext(in items: [TodoItem]) {
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = items[0].id
            return
        }
        selectedItemID = items[min(current + 1, items.count - 1)].id
    }

    func selectPrevious(in items: [TodoItem]) {
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = items[0].id
            return
        }
        selectedItemID = items[max(current - 1, 0)].id
    }
}
