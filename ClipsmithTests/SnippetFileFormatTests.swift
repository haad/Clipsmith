import XCTest
@testable import Clipsmith

final class SnippetFileFormatTests: XCTestCase {

    func testExtensionsRoundTrip() {
        XCTAssertEqual(SnippetFileFormat.fileExtension(for: "markdown"), "md")
        XCTAssertEqual(SnippetFileFormat.fileExtension(for: "python"), "py")
        XCTAssertEqual(SnippetFileFormat.fileExtension(for: nil), "txt")
        XCTAssertEqual(SnippetFileFormat.fileExtension(for: ""), "txt")
        XCTAssertEqual(SnippetFileFormat.language(forExtension: "md"), "markdown")
        XCTAssertEqual(SnippetFileFormat.language(forExtension: "YML"), "yaml")
        XCTAssertNil(SnippetFileFormat.language(forExtension: "txt"))
        XCTAssertNil(SnippetFileFormat.language(forExtension: "toml"))
    }

    func testSanitizedName() {
        XCTAssertEqual(SnippetFileFormat.sanitizedName(" a/b:c "), "a-b-c")
        XCTAssertEqual(SnippetFileFormat.sanitizedName("..hidden"), "hidden")
        XCTAssertEqual(SnippetFileFormat.sanitizedName("   "), "")
    }

    func testEncodeWithoutTagsIsJustContent() {
        XCTAssertEqual(SnippetFileFormat.encode(content: "body", tags: []), "body")
    }

    func testTagsHeaderRoundTrip() {
        let text = SnippetFileFormat.encode(content: "# Title\ntext", tags: ["work", "blog"])
        XCTAssertEqual(text, "---\ntags: [work, blog]\n---\n# Title\ntext")
        let decoded = SnippetFileFormat.decode(text)
        XCTAssertEqual(decoded.content, "# Title\ntext")
        XCTAssertEqual(decoded.tags, ["work", "blog"])
    }

    func testYAMLDocumentIsNotAHeader() {
        let yaml = "---\nname: app\nreplicas: 2\n---\n"
        XCTAssertEqual(SnippetFileFormat.decode(yaml).content, yaml)
        XCTAssertEqual(SnippetFileFormat.decode(yaml).tags, [])
    }

    func testHeaderWithEmptyBody() {
        let decoded = SnippetFileFormat.decode("---\ntags: [x]\n---")
        XCTAssertEqual(decoded.content, "")
        XCTAssertEqual(decoded.tags, ["x"])
    }
}
