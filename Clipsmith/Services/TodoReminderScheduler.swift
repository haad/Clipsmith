import Foundation
import OSLog
import UserNotifications

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "TodoReminders"
)

/// One planned notification: an open task, at the reminder time on its due day.
struct TodoReminder: Equatable, Sendable {
    let identifier: String
    let taskID: UUID
    let title: String
    let fireDate: Date
}

/// Pure planning: which tasks get a reminder and when.
enum TodoReminderPlanner {
    static let identifierPrefix = "clipsmith.todo."

    /// Open tasks whose due day at `minutesAfterMidnight` is still ahead,
    /// soonest first, capped below macOS's 64 pending-notification limit.
    static func plan(tasks: [TodoItem], minutesAfterMidnight: Int, now: Date = .now,
                     calendar: Calendar = .current, limit: Int = 60) -> [TodoReminder] {
        tasks.compactMap { task -> TodoReminder? in
            guard !task.isDone, let due = task.dueDate, let day = task.dueDateString,
                  let fire = calendar.date(byAdding: .minute, value: minutesAfterMidnight,
                                           to: calendar.startOfDay(for: due)),
                  fire > now
            else { return nil }
            return TodoReminder(identifier: "\(identifierPrefix)\(day).\(task.title)",
                                taskID: task.id, title: task.title, fireDate: fire)
        }
        .sorted { $0.fireDate < $1.fireDate }
        .prefix(limit)
        .reduce(into: []) { result, r in
            if !result.contains(where: { $0.identifier == r.identifier }) { result.append(r) }
        }
    }
}

/// Keeps the pending notifications in step with the todo file. Rescheduled
/// (debounced) on every document change and when the settings change.
/// Clicking a notification opens the task in the Todos section.
@MainActor
final class TodoReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let store: TodoStore
    private var pending: Task<Void, Never>?

    init(store: TodoStore) {
        self.store = store
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func reschedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.apply()
        }
    }

    private func apply() async {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: AppSettingsKeys.todoTrackingEnabled)
            && defaults.bool(forKey: AppSettingsKeys.todoRemindersEnabled)
        let plan = enabled
            ? TodoReminderPlanner.plan(tasks: store.document.allTasks,
                                       minutesAfterMidnight: defaults.integer(forKey: AppSettingsKeys.todoReminderMinutes))
            : []
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(TodoReminderPlanner.identifierPrefix) }
        let wanted = Set(plan.map(\.identifier))
        center.removePendingNotificationRequests(withIdentifiers: ours.filter { !wanted.contains($0) })
        guard !plan.isEmpty else { return }

        // Asked once, the first time there is something to remind about.
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            logger.info("Notifications not authorized; reminders skipped")
            return
        }
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = "Due today"
            content.body = reminder.title
            content.sound = .default
            content.userInfo = ["taskID": reminder.taskID.uuidString]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: reminder.identifier, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request) // same identifier replaces
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = (response.notification.request.content.userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            if let id { openTodo(id) }
        }
    }
}
