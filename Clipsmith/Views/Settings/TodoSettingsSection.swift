import AppKit
import SwiftUI

/// Settings > Todos: TaskPaper file location (choose, reveal, reset).
///
/// The path is a plain string in UserDefaults (empty = default location).
/// The app is not sandboxed, so no security-scoped bookmarks are needed.
struct TodoSettingsSection: View {
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false
    @AppStorage(AppSettingsKeys.todoFilePath) private var todoFilePath: String = ""
    @AppStorage(AppSettingsKeys.todoRemindersEnabled) private var remindersEnabled: Bool = true
    @AppStorage(AppSettingsKeys.todoReminderMinutes) private var reminderMinutes: Int = 9 * 60
    @AppStorage(AppSettingsKeys.todoCaptureContext) private var captureContext: Bool = true

    /// DatePicker works on Dates; the setting is minutes after midnight.
    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: reminderMinutes,
                                  to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
            remindersChanged()
        }
    }

    private var effectiveURL: URL { TodoStore.resolveFileURL() }

    var body: some View {
        Form {
            Section("Todo File") {
                if !todoTrackingEnabled {
                    Text("Todo Tracking is disabled — enable it in General > Features.")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Location") {
                    Text(effectiveURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Choose…") { chooseFile() }
                    Button("Reveal in Finder") {
                        if FileManager.default.fileExists(atPath: effectiveURL.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([effectiveURL])
                        } else {
                            // File not created yet (store writes it on first save) — show its folder.
                            NSWorkspace.shared.activateFileViewerSelecting([effectiveURL.deletingLastPathComponent()])
                        }
                    }
                    Button("Reset to Default") {
                        todoFilePath = ""
                        postPathChanged()
                    }
                    .disabled(todoFilePath.isEmpty)
                }

                Text("Plain-text TaskPaper format — the file stays yours; edit it with any editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Toggle("Notify on the due day", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in remindersChanged() }
                DatePicker("At", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .disabled(!remindersEnabled)
                Text("Open tasks with @due(…) get a notification at this time on their due day. @due(fri), @due(tomorrow) or @due(+3d) are saved as dates; @every(week) repeats a task when you complete it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quick Add") {
                Toggle("Attach selected text and browser URL as a note", isOn: $captureContext)
                Text("The quick-add hotkey reads the selection in the frontmost app and, in Safari or a Chromium browser, the current tab's URL. The first time, macOS asks to let Clipsmith control the browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// NSSavePanel so the user can pick an existing file OR name a new one.
    private func chooseFile() {
        let panel = NSSavePanel()
        panel.title = "Choose Todo File"
        panel.nameFieldStringValue = "todos.taskpaper"
        panel.canCreateDirectories = true
        panel.directoryURL = effectiveURL.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            todoFilePath = url.path
            postPathChanged()
        }
    }

    private func remindersChanged() {
        NotificationCenter.default.post(name: .clipsmithTodoRemindersChanged, object: nil)
    }

    private func postPathChanged() {
        NotificationCenter.default.post(name: .clipsmithTodoFilePathChanged, object: nil)
    }
}
