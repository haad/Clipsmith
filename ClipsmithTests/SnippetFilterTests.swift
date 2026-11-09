import XCTest
@testable import Clipsmith

@MainActor
final class SnippetFilterTests: XCTestCase {
    private func make(_ name: String, _ content: String, _ language: String?, _ tags: [String] = []) -> Snippet {
        Snippet(id: UUID(), name: name, content: content, language: language, tags: tags,
                createdAt: .now, updatedAt: .now, fileURL: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func snippets() -> [Snippet] {
        [make("Config", "struct Config {}", "swift", ["model"]),
         make("drain", "kubectl drain", "bash"),
         make("notes", "plain", nil),
         make("empty-lang", "x", "")]
    }

    /// Review Focus 4: nil / empty languages appear under "All" and create no chip.
    func testLanguagesIgnoreNilAndEmpty() throws {
        let opts = SnippetFilter.languages(in: snippets())
        XCTAssertEqual(opts.map(\.id), ["bash", "swift"])
    }

    func testApplyByLanguage() throws {
        let all = snippets()
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: "swift").map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: nil).count, 4)
    }

    func testApplyByQueryMatchesNameContentTags() throws {
        let all = snippets()
        XCTAssertEqual(SnippetFilter.apply(all, query: "MODEL", language: nil).map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "kubectl", language: "swift").count, 0)
    }

    // MARK: - Names

    func testDuplicateNames() {
        XCTAssertEqual(SnippetFilter.duplicateNames(["a", "A", "b", "c", "c "]), ["a"])
    }
}
