import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class StorageMigrationTests: XCTestCase {

    private var dir: URL!
    private var defaults: UserDefaults!
    private let suite = "StorageMigrationTests"

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appending(path: "StorageMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSnippetsAreWrittenOnceAndRowsKept() throws {
        let container = try makeTestContainer()
        container.mainContext.insert(ClipsmithSchemaV1.Snippet(name: "Config", content: "x", language: "swift", tags: ["a"]))
        container.mainContext.insert(ClipsmithSchemaV1.Snippet(name: "config", content: "y"))
        try container.mainContext.save()
        let store = SnippetStore(folderURL: dir.appending(path: "snippets"), watches: false)
        store.load()

        StorageMigration.migrateSnippets(from: container, into: store, defaults: defaults)
        StorageMigration.migrateSnippets(from: container, into: store, defaults: defaults)

        XCTAssertEqual(Set(store.snippets.map(\.name)), ["Config", "config 2"])
        XCTAssertEqual(store.snippets.first { $0.name == "Config" }?.tags, ["a"])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ClipsmithSchemaV1.Snippet>()), 2)
    }

    func testLegacyTodoFileMoves() throws {
        let legacy = dir.appending(path: "old/todos.taskpaper")
        let target = dir.appending(path: "new/todos.taskpaper")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("- a\n".utf8).write(to: legacy)
        StorageMigration.moveLegacyTodoFile(defaults: defaults, legacy: legacy, destination: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "- a\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testCustomTodoPathOrExistingTargetIsLeftAlone() throws {
        let legacy = dir.appending(path: "old/todos.taskpaper")
        let target = dir.appending(path: "new/todos.taskpaper")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("- a\n".utf8).write(to: legacy)
        defaults.set("/somewhere/else.taskpaper", forKey: AppSettingsKeys.todoFilePath)
        StorageMigration.moveLegacyTodoFile(defaults: defaults, legacy: legacy, destination: target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        defaults.removeObject(forKey: AppSettingsKeys.todoFilePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("- keep\n".utf8).write(to: target)
        StorageMigration.moveLegacyTodoFile(defaults: defaults, legacy: legacy, destination: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "- keep\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }
}
