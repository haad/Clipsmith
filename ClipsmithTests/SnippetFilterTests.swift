import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class SnippetFilterTests: XCTestCase {
    private func snippets(in ctx: ModelContext) -> [ClipsmithSchemaV1.Snippet] {
        let a = ClipsmithSchemaV1.Snippet(name: "Config", content: "struct Config {}", language: "swift", tags: ["model"])
        let b = ClipsmithSchemaV1.Snippet(name: "drain", content: "kubectl drain", language: "bash")
        let c = ClipsmithSchemaV1.Snippet(name: "notes", content: "plain", language: nil)
        let d = ClipsmithSchemaV1.Snippet(name: "empty-lang", content: "x", language: "")
        [a, b, c, d].forEach(ctx.insert)
        return [a, b, c, d]
    }

    /// Review Focus 4: nil / empty languages appear under "All" and create no chip.
    func testLanguagesIgnoreNilAndEmpty() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let opts = SnippetFilter.languages(in: snippets(in: ctx))
        XCTAssertEqual(opts.map(\.id), ["bash", "swift"])
    }

    func testApplyByLanguage() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let all = snippets(in: ctx)
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: "swift").map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: nil).count, 4)
    }

    func testApplyByQueryMatchesNameContentTags() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let all = snippets(in: ctx)
        XCTAssertEqual(SnippetFilter.apply(all, query: "MODEL", language: nil).map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "kubectl", language: "swift").count, 0)
    }

    // MARK: - Names

    func testDuplicateNames() {
        XCTAssertEqual(SnippetFilter.duplicateNames(["a", "A", "b", "c", "c "]), ["a"])
    }

    func testBestMatchIsCaseInsensitiveAndPrefersNewest() {
        let old = ClipsmithSchemaV1.Snippet(name: "Notes", content: "old")
        old.updatedAt = Date(timeIntervalSince1970: 100)
        let new = ClipsmithSchemaV1.Snippet(name: "NOTES", content: "new")
        new.updatedAt = Date(timeIntervalSince1970: 200)
        let other = ClipsmithSchemaV1.Snippet(name: "Notes 2", content: "x")
        XCTAssertTrue(SnippetFilter.bestMatch(named: "notes", in: [old, other, new]) === new)
        XCTAssertNil(SnippetFilter.bestMatch(named: "missing", in: [old, new]))
    }
}
