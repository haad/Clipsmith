import XCTest
@testable import Clipsmith

@MainActor
final class TodoStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "TodoStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore(initialContent: String? = nil,
                           saveDelay: Duration = .milliseconds(10)) -> TodoStore {
        let url = tempDir.appending(path: "todos.taskpaper")
        if let initialContent {
            try? Data(initialContent.utf8).write(to: url)
        }
        let store = TodoStore(fileURL: url, saveDelay: saveDelay)
        store.load()
        return store
    }

    private func fileContent(of store: TodoStore) -> String {
        (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? "<missing>"
    }

    // MARK: - Load

    func testMissingFileLoadsEmptyDocumentWithoutCreatingFile() {
        let store = makeStore()
        XCTAssertEqual(store.document.allTasks.count, 0)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testLoadParsesExistingFile() {
        let store = makeStore(initialContent: "Home:\n- buy milk @today\n")
        XCTAssertEqual(store.document.projects[1].tasks[0].title, "buy milk")
    }

    // MARK: - CRUD + save

    func testAddTaskToInboxAndSaveCreatesFile() {
        let store = makeStore()
        store.addTask(text: "loose task", projectName: nil, tags: [])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- loose task\n")
    }

    func testAddTaskWithTagsAndNewProject() {
        let store = makeStore(initialContent: "")
        store.addTask(text: "Fix pricing page",
                      projectName: "lara",
                      tags: [TodoTag(name: "due", value: "2026-09-05"),
                             TodoTag(name: "today", value: nil)])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store),
                       "lara:\n- Fix pricing page @due(2026-09-05) @today\n")
    }

    func testAddTaskMatchesProjectCaseInsensitively() {
        let store = makeStore(initialContent: "LARA:\n")
        store.addTask(text: "x", projectName: "lara", tags: [])
        XCTAssertEqual(store.document.projects.count, 2) // Inbox + LARA, no new project
        XCTAssertEqual(store.document.projects[1].tasks.count, 1)
    }

    func testToggleDoneAddsAndRemovesDoneTag() {
        let store = makeStore(initialContent: "- task one\n")
        let id = store.document.allTasks[0].id
        store.toggleDone(id: id)
        let today = TodoDates.dateString()
        XCTAssertEqual(store.document.allTasks[0].rawLine, "- task one @done(\(today))")
        store.toggleDone(id: id)
        XCTAssertEqual(store.document.allTasks[0].rawLine, "- task one")
    }

    func testEditTaskPreservesIndent() {
        let store = makeStore(initialContent: "Home:\n\t- old text @today\n")
        let id = store.document.allTasks[0].id
        store.editTask(id: id, text: "new text @today")
        XCTAssertEqual(store.document.allTasks[0].rawLine, "\t- new text @today")
    }

    func testDeleteTask() {
        let store = makeStore(initialContent: "- a\n- b\n")
        store.deleteTask(id: store.document.allTasks[0].id)
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- b\n")
    }

    func testMoveTask() {
        let store = makeStore(initialContent: "- a\nWork:\n")
        store.moveTask(id: store.document.allTasks[0].id, toProject: "Work")
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "Work:\n- a\n")
    }

    func testAddRenameDeleteProject() {
        let store = makeStore(initialContent: "")
        store.addProject(name: "Alpha")
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "Alpha:\n")
        let id = store.document.projects[1].id
        store.renameProject(id: id, to: "Beta")
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "Beta:\n")
        store.deleteProject(id: id)
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "")
    }

    // MARK: - Debounce

    func testDebouncedSaveWritesAfterDelay() async throws {
        let store = makeStore(saveDelay: .milliseconds(20))
        store.addTask(text: "a", projectName: nil, tags: [])
        store.addTask(text: "b", projectName: nil, tags: [])
        XCTAssertTrue(store.hasPendingChanges)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(store.hasPendingChanges)
        XCTAssertEqual(fileContent(of: store), "- a\n- b\n")
    }

    // MARK: - External changes (last-write-wins)

    func testExternalChangeReloadsWhenClean() throws {
        let store = makeStore(initialContent: "- a\n")
        try Data("- edited outside\n".utf8).write(to: store.fileURL)
        store.handleFileChanged()
        XCTAssertEqual(store.document.allTasks[0].title, "edited outside")
    }

    func testExternalChangeIgnoredWhenDirty() throws {
        let store = makeStore(initialContent: "- a\n", saveDelay: .seconds(60))
        store.addTask(text: "in-app", projectName: nil, tags: [])
        try Data("- edited outside\n".utf8).write(to: store.fileURL)
        store.handleFileChanged()
        // In-app state wins; next save overwrites the external edit.
        XCTAssertEqual(store.document.allTasks.map(\.title), ["a", "in-app"])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- a\n- in-app\n")
    }

    func testFileDeletedExternallyRecreatedOnNextSave() throws {
        let store = makeStore(initialContent: "- a\n")
        try FileManager.default.removeItem(at: store.fileURL)
        store.handleFileChanged() // file gone: keep memory state
        XCTAssertEqual(store.document.allTasks.count, 1)
        store.addTask(text: "b", projectName: nil, tags: [])
        store.saveNow()
        XCTAssertEqual(fileContent(of: store), "- a\n- b\n")
    }

    // MARK: - Path switching

    func testUpdateFileURLFlushesThenLoadsNewFile() throws {
        let store = makeStore(initialContent: "- a\n", saveDelay: .seconds(60))
        store.addTask(text: "b", projectName: nil, tags: [])
        let oldURL = store.fileURL
        let newURL = tempDir.appending(path: "other.taskpaper")
        try Data("Other:\n- z\n".utf8).write(to: newURL)
        store.updateFileURL(newURL)
        XCTAssertEqual((try String(contentsOf: oldURL, encoding: .utf8)), "- a\n- b\n")
        XCTAssertEqual(store.document.projects[1].name, "Other")
    }
}
