import Foundation

/// The folder that holds the user's own files: `todos.taskpaper` and
/// `snippets/`. Empty setting = `~/.config/clipsmith`. The app is not
/// sandboxed, so the home directory is the real one.
enum DataFolder {

    static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/clipsmith", directoryHint: .isDirectory)
    }

    static func resolve(defaults: UserDefaults = .standard) -> URL {
        let path = defaults.string(forKey: AppSettingsKeys.dataFolderPath) ?? ""
        guard !path.isEmpty else { return defaultURL() }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func snippetsURL(defaults: UserDefaults = .standard) -> URL {
        resolve(defaults: defaults).appending(path: "snippets", directoryHint: .isDirectory)
    }

    /// Migrations touch real user data; a hosted test run must not.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
