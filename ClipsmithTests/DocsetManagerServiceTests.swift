import XCTest
@testable import Clipsmith

@MainActor
final class DocsetManagerServiceTests: XCTestCase {
    func testAvailableDocsetsManifestNotEmpty() {
        XCTAssertGreaterThanOrEqual(DocsetManagerService.availableDocsets.count, 25)
    }

    func testDocsetInfoCodableRoundTrip() throws {
        let info = DocsetInfo(
            id: "Swift",
            displayName: "Swift",
            localPath: URL(fileURLWithPath: "/tmp/Swift.docset"),
            version: "5.9",
            isEnabled: true
        )
        let data = try JSONEncoder().encode([info])
        let decoded = try JSONDecoder().decode([DocsetInfo].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "Swift")
        XCTAssertEqual(decoded[0].localPath?.path, "/tmp/Swift.docset")
        XCTAssertEqual(decoded[0].version, "5.9")
        XCTAssertTrue(decoded[0].isEnabled)
    }

    func testLoadMetadataMergesWithManifest() {
        let service = DocsetManagerService()
        service.loadMetadata()
        // Should have at least the bundled manifest entries
        XCTAssertGreaterThanOrEqual(service.docsets.count, 25)
        // All manifest entries should be present
        let ids = Set(service.docsets.map(\.id))
        XCTAssertTrue(ids.contains("Swift"))
        XCTAssertTrue(ids.contains("Python_3"))
        XCTAssertTrue(ids.contains("JavaScript"))
    }

    func testEnabledDocsetsFiltersCorrectly() {
        let service = DocsetManagerService()
        service.docsets = [
            DocsetInfo(id: "A", displayName: "A", localPath: URL(fileURLWithPath: "/tmp/A"), version: nil, isEnabled: true),
            DocsetInfo(id: "B", displayName: "B", localPath: nil, version: nil, isEnabled: true),
            DocsetInfo(id: "C", displayName: "C", localPath: URL(fileURLWithPath: "/tmp/C"), version: nil, isEnabled: false),
        ]
        let enabled = service.enabledDocsets
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled[0].id, "A")
    }
}
