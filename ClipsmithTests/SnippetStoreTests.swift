import XCTest
@testable import Clipsmith

@MainActor
final class SnippetStoreTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appending(path: "SnippetStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeStore() -> SnippetStore {
        let store = SnippetStore(folderURL: dir, watches: false)
        store.load()
        return store
    }

    private func file(_ name: String) -> String? {
        try? String(contentsOf: dir.appending(path: name), encoding: .utf8)
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    // MARK: - Files

    func testInsertWritesFileNamedAfterSnippet() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "Config", content: "let x = 1", language: "swift", tags: []))
        XCTAssertEqual(file("Config.swift"), "let x = 1")
        XCTAssertEqual(store.snippet(id: id)?.name, "Config")
    }

    func testTagsGoInHeaderAndLoadBack() {
        let store = makeStore()
        store.insert(base: "Notes", content: "# Hi", language: "markdown", tags: ["work", "blog"])
        XCTAssertEqual(file("Notes.md"), "---\ntags: [work, blog]\n---\n# Hi")
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.snippets.map(\.tags), [["work", "blog"]])
        XCTAssertEqual(reloaded.snippets.map(\.content), ["# Hi"])
        XCTAssertEqual(reloaded.snippets.map(\.language), ["markdown"])
    }

    func testLoadsFilesWrittenByAnEditor() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("echo hi".utf8).write(to: dir.appending(path: "greet.sh"))
        try Data("a = 1".utf8).write(to: dir.appending(path: "conf.toml"))
        try Data("x".utf8).write(to: dir.appending(path: ".hidden.md"))
        let store = makeStore()
        XCTAssertEqual(Set(store.snippets.map(\.name)), ["greet", "conf"])
        XCTAssertEqual(store.snippets.first { $0.name == "greet" }?.language, "bash")
        XCTAssertNil(store.snippets.first { $0.name == "conf" }?.language)
    }

    func testRescanPicksUpExternalEditKeepingId() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "a", content: "old", language: nil, tags: []))
        let url = dir.appending(path: "a.txt")
        try Data("new".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)],
                                              ofItemAtPath: url.path)
        store.rescan()
        XCTAssertEqual(store.snippet(id: id)?.content, "new")
    }

    func testRescanDropsDeletedFiles() throws {
        let store = makeStore()
        store.insert(base: "gone", content: "", language: nil, tags: [])
        try FileManager.default.removeItem(at: dir.appending(path: "gone.txt"))
        store.rescan()
        XCTAssertTrue(store.snippets.isEmpty)
    }

    // MARK: - Save

    func testSaveRenamesFileAndReportsPreviousName() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "xyz", content: "", language: "markdown", tags: []))
        let result = store.save(id: id, requestedName: "Blog notes", content: "body", language: "markdown", tags: [])
        XCTAssertEqual(result, SnippetSaveResult(previousName: "xyz", savedName: "Blog notes", nameRefused: false))
        XCTAssertEqual(files(), ["Blog notes.md"])
        XCTAssertEqual(file("Blog notes.md"), "body")
    }

    func testCaseOnlyRename() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "foo", content: "x", language: nil, tags: []))
        _ = store.save(id: id, requestedName: "Foo", content: "x", language: nil, tags: [])
        XCTAssertEqual(files(), ["Foo.txt"])
    }

    func testLanguageChangeChangesExtension() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "s", content: "x", language: nil, tags: []))
        _ = store.save(id: id, requestedName: "s", content: "x", language: "python", tags: [])
        XCTAssertEqual(files(), ["s.py"])
    }

    func testPlainTextKeepsUnknownExtension() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("a = 1".utf8).write(to: dir.appending(path: "conf.toml"))
        let store = makeStore()
        let id = try XCTUnwrap(store.snippets.first?.id)
        _ = store.save(id: id, requestedName: "conf", content: "a = 2", language: nil, tags: [])
        XCTAssertEqual(files(), ["conf.toml"])
    }

    func testSaveRefusesTakenNameButSavesOtherFields() throws {
        let store = makeStore()
        store.insert(base: "Taken", content: "", language: nil, tags: [])
        let id = try XCTUnwrap(store.insert(base: "Mine", content: "", language: nil, tags: []))
        let result = store.save(id: id, requestedName: "taken", content: "new", language: nil, tags: [])
        XCTAssertTrue(result.nameRefused)
        XCTAssertEqual(result.savedName, "Mine")
        XCTAssertEqual(file("Mine.txt"), "new")
    }

    func testSaveWithBlankNameKeepsName() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "Keep", content: "", language: nil, tags: []))
        XCTAssertEqual(store.save(id: id, requestedName: "  ", content: "", language: nil, tags: []).savedName, "Keep")
    }

    func testSaveSanitizesName() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "a", content: "", language: nil, tags: []))
        XCTAssertEqual(store.save(id: id, requestedName: "a/b", content: "", language: nil, tags: []).savedName, "a-b")
        XCTAssertEqual(files(), ["a-b.txt"])
    }

    // MARK: - Names

    func testInsertNeverRepeatsAName() {
        let store = makeStore()
        for _ in 0..<3 { store.insert(base: "Untitled Snippet", content: "", language: nil, tags: []) }
        XCTAssertEqual(Set(store.snippets.map(\.name)), ["Untitled Snippet", "Untitled Snippet 2", "Untitled Snippet 3"])
    }

    func testNameTakenIsCaseInsensitiveAndIgnoresSelf() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "Deploy", content: "", language: nil, tags: []))
        XCTAssertTrue(store.isNameTaken("deploy", excluding: nil))
        XCTAssertFalse(store.isNameTaken("deploy", excluding: id))
    }

    func testFindOrCreateReturnsExistingOrCreatesOnce() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.findOrCreate(name: "xyz", language: "markdown"))
        let second = try XCTUnwrap(store.findOrCreate(name: "XYZ", language: "markdown"))
        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(files(), ["xyz.md"])
    }

    // MARK: - Delete / import

    func testDeleteRemovesFile() throws {
        let store = makeStore()
        let id = try XCTUnwrap(store.insert(base: "bye", content: "", language: nil, tags: []))
        store.delete(id: id)
        XCTAssertTrue(store.snippets.isEmpty)
        XCTAssertEqual(files(), [])
    }

    func testImportKeepsDatesAndOrder() {
        let store = makeStore()
        let old = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        store.importSnippet(name: "old", content: "", language: nil, tags: [], createdAt: old, updatedAt: old)
        store.importSnippet(name: "new", content: "", language: nil, tags: [], createdAt: newer, updatedAt: newer)
        XCTAssertEqual(store.snippets.map(\.name), ["new", "old"])
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.snippets.map(\.name), ["new", "old"])
        XCTAssertEqual(reloaded.snippets.last?.updatedAt, old)
    }
}
