import XCTest
@testable import Clipsmith

final class TransformRegistryTests: XCTestCase {

    // MARK: - Registry integrity

    func testAllIDsUnique() {
        let ids = TransformRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Transform ids must be unique")
    }

    func testRegistryContainsExpectedCount() {
        // 10 original-era transforms (minus copyAsRTF which is Data, not text,
        // so 9 make it into the registry) + 16 new + extraction = 26 total:
        // 7 case + 4 trim/lines + 6 encode/escape + 4 format + 3 dev + 2 extract.
        XCTAssertEqual(TransformRegistry.all.count, 26)
    }

    func testTransformWithID() {
        XCTAssertNotNil(TransformRegistry.transform(withID: "case.upper"))
        XCTAssertNil(TransformRegistry.transform(withID: "does.not.exist"))
    }

    func testApplyThroughRegistry() {
        let upper = TransformRegistry.transform(withID: "case.upper")
        XCTAssertEqual(upper?.apply("hi"), "HI")

        let json = TransformRegistry.transform(withID: "format.jsonpretty")
        XCTAssertNil(json?.apply("not json"), "Failable transform must surface nil through the registry")
        XCTAssertFalse(json?.failureMessage.isEmpty ?? true, "Failable transforms need a failure message")
    }

    // MARK: - Fuzzy discoverability

    func testKeywordsEnableFuzzyMatch() {
        // "b64" should match the Base64 transforms via keywords.
        let matches = TransformRegistry.all.filter {
            FuzzyMatcher.score($0.displayName + " " + $0.keywords, query: "b64") != nil
        }
        XCTAssertTrue(matches.contains { $0.id == "encode.base64" }, "b64 should match Base64 Encode")
        XCTAssertTrue(matches.contains { $0.id == "decode.base64" }, "b64 should match Base64 Decode")
    }
}
