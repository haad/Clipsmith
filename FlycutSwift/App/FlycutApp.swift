import SwiftUI
import SwiftData

@main
struct FlycutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Shared AppSettings instance — injected into the environment so all
    /// settings views can read and write via @Environment(AppSettings.self).
    private let appSettings = AppSettings()

    /// Menu bar icon selection — persisted in UserDefaults.
    @AppStorage(AppSettingsKeys.menuIcon) private var menuIcon: Int = 0

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema(FlycutSchemaV2.models)
        let storeURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Flycut/clipboard.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Failed to create Application Support/Flycut directory: \(error)")
        }
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FlycutMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.accessibilityMonitor)
                .environment(appDelegate.clipboardMonitor)
                .environment(appDelegate.pasteService)
                .environment(appDelegate.appTracker)
                .environment(appSettings)
        } label: {
            Image(systemName: menuBarIconName)
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(FlycutApp.sharedModelContainer)

        Settings {
            SettingsView()
                .environment(appDelegate.accessibilityMonitor)
                .environment(appDelegate.clipboardMonitor)
                .environment(appDelegate.pasteService)
                .environment(appDelegate.appTracker)
                .environment(appSettings)
        }

        WindowGroup(id: "snippets") {
            SnippetWindowView()
                .environment(appDelegate.pasteService)
                .environment(appDelegate.appTracker)
                .environment(appDelegate.gistService)
                .frame(minWidth: 700, minHeight: 500)
        }
        .modelContainer(FlycutApp.sharedModelContainer)
        .windowResizability(.contentSize)
    }

    /// Returns the SF Symbol name for the current menu bar icon selection.
    private var menuBarIconName: String {
        switch menuIcon {
        case 1: return "scissors"
        case 2: return "scissors.circle"
        case 3: return "doc.on.doc"
        default: return "doc.on.clipboard"
        }
    }
}
