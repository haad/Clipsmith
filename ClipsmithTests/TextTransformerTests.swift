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
        XCTAssertEqual(TextTransformer.urlDecode("hello world"), "hello world")
    }

    func testUrlDecodeMalformedReturnsNil() {
        XCTAssertNil(TextTransformer.urlDecode("bad%zzencoding"))
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
        let result = TextTransformer.jsonPrettyPrint("{\"key\":\"value\"}")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("\n") ?? false, "Pretty-printed JSON should contain newlines")
        XCTAssertTrue(result?.contains("key") ?? false)
    }

    func testJsonPrettyPrintInvalidReturnsNil() {
        XCTAssertNil(TextTransformer.jsonPrettyPrint("not valid json { at all"))
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

    // MARK: - Base64

    func testBase64RoundTrip() {
        XCTAssertEqual(TextTransformer.base64Encode("hello"), "aGVsbG8=")
        XCTAssertEqual(TextTransformer.base64Decode("aGVsbG8="), "hello")
    }

    func testBase64DecodeInvalidReturnsNil() {
        XCTAssertNil(TextTransformer.base64Decode("!!! not base64 !!!"))
    }

    // MARK: - JWT decode

    func testJwtDecode() {
        // {"alg":"HS256","typ":"JWT"} . {"sub":"1234567890","name":"John Doe"} . fake-sig
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0."
            + "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = TextTransformer.jwtDecode(jwt)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("HS256") ?? false, "Decoded JWT should contain header alg")
        XCTAssertTrue(result?.contains("John Doe") ?? false, "Decoded JWT should contain payload claim")
    }

    func testJwtDecodeInvalidReturnsNil() {
        XCTAssertNil(TextTransformer.jwtDecode("not.a-jwt"))
        XCTAssertNil(TextTransformer.jwtDecode("plain text"))
    }

    // MARK: - Timestamp conversions

    func testTimestampToISO() {
        XCTAssertEqual(TextTransformer.timestampToISO("0"), "1970-01-01T00:00:00Z")
        // Milliseconds heuristic: 13-digit values are treated as ms.
        XCTAssertEqual(TextTransformer.timestampToISO("1700000000000"),
                       TextTransformer.timestampToISO("1700000000"))
        XCTAssertNil(TextTransformer.timestampToISO("not a number"))
    }

    func testISOToTimestamp() {
        XCTAssertEqual(TextTransformer.isoToTimestamp("1970-01-01T00:00:00Z"), "0")
        XCTAssertEqual(TextTransformer.isoToTimestamp("2023-11-14T22:13:20Z"), "1700000000")
        XCTAssertNil(TextTransformer.isoToTimestamp("14.11.2023"))
    }

    // MARK: - Extract URLs / emails

    func testExtractURLs() {
        let text = "see https://example.com/docs and http://foo.bar, mail me at a@b.com"
        let result = TextTransformer.extractURLs(text)
        XCTAssertEqual(result, "https://example.com/docs\nhttp://foo.bar")
    }

    func testExtractURLsNoneReturnsNil() {
        XCTAssertNil(TextTransformer.extractURLs("no links here"))
    }

    func testExtractEmails() {
        let text = "contact adam@lablabs.io or support@example.com via https://example.com"
        let result = TextTransformer.extractEmails(text)
        XCTAssertEqual(result, "adam@lablabs.io\nsupport@example.com")
    }

    func testExtractEmailsNoneReturnsNil() {
        XCTAssertNil(TextTransformer.extractEmails("no emails here"))
    }
}
