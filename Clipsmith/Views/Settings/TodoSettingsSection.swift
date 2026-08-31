import AppKit
import SwiftUI

/// Settings > Todos: TaskPaper file location (choose, reveal, reset).
///
/// The path is a plain string in UserDefaults (empty = default location).
/// The app is not sandboxed, so no security-scoped bookmarks are needed.
struct TodoSettingsSection: View {
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false
    @AppStorage(AppSettingsKeys.todoFilePath) private var todoFilePath: String = ""

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
                        NSWorkspace.shared.activateFileViewerSelecting([effectiveURL])
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

    private func postPathChanged() {
        NotificationCenter.default.post(name: .clipsmithTodoFilePathChanged, object: nil)
    }
}
