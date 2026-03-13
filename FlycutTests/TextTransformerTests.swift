import XCTest
@testable import FlycutSwift

final class TextTransformerTests: XCTestCase {

    // MARK: - testUppercase

    func testUppercase() {
        XCTAssertEqual(TextTransformer.uppercase("hello world"), "HELLO WORLD")
    }

    // MARK: - testLowercase

    func testLowercase() {
        XCTAssertEqual(TextTransformer.lowercase("HELLO WORLD"), "hello world")
    }

    // MARK: - testTitleCase

    func testTitleCase() {
        XCTAssertEqual(TextTransformer.titleCase("hello world"), "Hello World")
    }

    // MARK: - testTrimWhitespace

    func testTrimWhitespace() {
        XCTAssertEqual(TextTransformer.trimWhitespace("  hello  \n"), "hello")
    }

    // MARK: - testUrlEncode

    func testUrlEncode() {
        let result = TextTransformer.urlEncode("hello world & more")
        XCTAssertNotNil(result)
        XCTAssertTrue(result.contains("%20") || result.contains("+"),
                      "URL encoded string should encode spaces")
    }

    // MARK: - testUrlDecode

    func testUrlDecode() {
        XCTAssertEqual(TextTransformer.urlDecode("hello%20world"), "hello world")
    }

    // MARK: - testUrlDecodeNonEncoded

    func testUrlDecodeNonEncoded() {
        let input = "hello world"
        XCTAssertEqual(TextTransformer.urlDecode(input), input)
    }

    // MARK: - testWrapInQuotes

    func testWrapInQuotes() {
        XCTAssertEqual(TextTransformer.wrapInQuotes("hello"), "\"hello\"")
    }

    // MARK: - testMarkdownCodeBlock

    func testMarkdownCodeBlock() {
        XCTAssertEqual(TextTransformer.markdownCodeBlock("code"), "```\ncode\n```")
    }

    // MARK: - testJsonPrettyPrintValid

    func testJsonPrettyPrintValid() {
        let input = "{\"key\":\"value\"}"
        let result = TextTransformer.jsonPrettyPrint(input)
        // Should produce indented output
        XCTAssertTrue(result.contains("\n"), "Pretty-printed JSON should contain newlines")
        XCTAssertTrue(result.contains("key"), "Pretty-printed JSON should contain the key")
        XCTAssertTrue(result.contains("value"), "Pretty-printed JSON should contain the value")
    }

    // MARK: - testJsonPrettyPrintInvalid

    func testJsonPrettyPrintInvalid() {
        let input = "not valid json { at all"
        let result = TextTransformer.jsonPrettyPrint(input)
        XCTAssertEqual(result, input, "Invalid JSON should be returned unchanged")
    }

    // MARK: - testCopyAsRTFProducesData

    func testCopyAsRTFProducesData() {
        let result = TextTransformer.copyAsRTF("hello")
        XCTAssertNotNil(result, "copyAsRTF should return non-nil Data")
        XCTAssertFalse(result!.isEmpty, "RTF data should not be empty")
    }
}
