import XCTest
@testable import Clipsmith

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

    // MARK: - Case conversions (transform picker)

    func testCamelCase() {
        XCTAssertEqual(TextTransformer.camelCase("user name"), "userName")
        XCTAssertEqual(TextTransformer.camelCase("user_id"), "userId")
        XCTAssertEqual(TextTransformer.camelCase("some-long-name"), "someLongName")
        XCTAssertEqual(TextTransformer.camelCase("alreadyCamel"), "alreadyCamel")
    }

    func testPascalCase() {
        XCTAssertEqual(TextTransformer.pascalCase("user name"), "UserName")
        XCTAssertEqual(TextTransformer.pascalCase("user_id"), "UserId")
    }

    func testSnakeCase() {
        XCTAssertEqual(TextTransformer.snakeCase("user name"), "user_name")
        XCTAssertEqual(TextTransformer.snakeCase("userId"), "user_id")
        XCTAssertEqual(TextTransformer.snakeCase("some-long-name"), "some_long_name")
    }

    func testKebabCase() {
        XCTAssertEqual(TextTransformer.kebabCase("user name"), "user-name")
        XCTAssertEqual(TextTransformer.kebabCase("userId"), "user-id")
    }

    func testCaseConversionEmptyAndSymbolsOnly() {
        XCTAssertEqual(TextTransformer.snakeCase(""), "")
        XCTAssertEqual(TextTransformer.camelCase("!!!"), "!!!")
    }

    // MARK: - Line operations (transform picker)

    func testSortLines() {
        XCTAssertEqual(TextTransformer.sortLines("banana\napple\ncherry"), "apple\nbanana\ncherry")
    }

    func testDedupeLines() {
        XCTAssertEqual(TextTransformer.dedupeLines("a\nb\na\nc\nb"), "a\nb\nc")
    }

    func testReverseLines() {
        XCTAssertEqual(TextTransformer.reverseLines("1\n2\n3"), "3\n2\n1")
    }

    // MARK: - Slugify

    func testSlugify() {
        XCTAssertEqual(TextTransformer.slugify("Hello World!"), "hello-world")
        XCTAssertEqual(TextTransformer.slugify("Čaučí, díky"), "cauci-diky")
    }

    // MARK: - Escape / Unescape

    func testEscape() {
        XCTAssertEqual(TextTransformer.escape("say \"hi\"\nnew line"), "say \\\"hi\\\"\\nnew line")
    }

    func testUnescapeRoundTrip() {
        let original = "say \"hi\"\nnew\tline \\ backslash"
        XCTAssertEqual(TextTransformer.unescape(TextTransformer.escape(original)), original)
    }
}
