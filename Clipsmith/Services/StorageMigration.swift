import Foundation
import OSLog
import SwiftData

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "StorageMigration"
)

/// One-time moves into the data folder. Never runs under tests against the
/// real defaults (AppDelegate guards it); the parameters exist for tests.
@MainActor
enum StorageMigration {

    /// Copies every SwiftData snippet into `store` as a file, once. The
    /// SwiftData rows stay as a backup.
    static func migrateSnippets(from container: ModelContainer, into store: SnippetStore,
                                defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: AppSettingsKeys.snippetsMigratedToFiles) else { return }
        do {
            let rows = try container.mainContext.fetch(FetchDescriptor<ClipsmithSchemaV1.Snippet>())
            for row in rows {
                store.importSnippet(name: row.name, content: row.content, language: row.language,
                                    tags: row.tags, createdAt: row.createdAt, updatedAt: row.updatedAt)
            }
            defaults.set(true, forKey: AppSettingsKeys.snippetsMigratedToFiles)
            logger.info("Migrated \(rows.count) snippets to \(store.folderURL.path, privacy: .public)")
        } catch {
            logger.error("Snippet migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves the todo file from the old default location to the data folder
    /// when the user never chose a custom path and nothing is there yet.
    static func moveLegacyTodoFile(defaults: UserDefaults = .standard,
                                   legacy: URL = TodoStore.legacyDefaultFileURL(),
                                   destination: URL? = nil) {
        guard (defaults.string(forKey: AppSettingsKeys.todoFilePath) ?? "").isEmpty else { return }
        let target = destination ?? DataFolder.resolve(defaults: defaults).appending(path: "todos.taskpaper")
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: target.path) else { return }
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: target)
            logger.info("Moved todo file to \(target.path, privacy: .public)")
        } catch {
            logger.error("Todo file move failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
