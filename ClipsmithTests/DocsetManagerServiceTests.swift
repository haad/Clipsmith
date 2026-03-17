import XCTest
@testable import Clipsmith

@MainActor
final class DocsetManagerServiceTests: XCTestCase {
    func testDocsetInfoCodableRoundTrip() throws {
        let info = DocsetInfo(
            id: "javascript",
            displayName: "JavaScript",
            release: "ES2024",
            dbSize: 5_242_880,
            isEnabled: true,
            isDownloaded: true
        )
        let data = try JSONEncoder().encode([info])
        let decoded = try JSONDecoder().decode([DocsetInfo].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "javascript")
        XCTAssertEqual(decoded[0].release, "ES2024")
        XCTAssertEqual(decoded[0].dbSize, 5_242_880)
        XCTAssertTrue(decoded[0].isEnabled)
        XCTAssertTrue(decoded[0].isDownloaded)
    }

    func testSizeLabel() {
        let small = DocsetInfo(id: "a", displayName: "A", release: nil, dbSize: 512_000, isEnabled: true, isDownloaded: false)
        XCTAssertEqual(small.sizeLabel, "500 KB")

        let large = DocsetInfo(id: "b", displayName: "B", release: nil, dbSize: 5_242_880, isEnabled: true, isDownloaded: false)
        XCTAssertEqual(large.sizeLabel, "5.0 MB")
    }

    func testEnabledDocsetsFiltersCorrectly() {
        let service = DocsetManagerService()
        service.docsets = [
            DocsetInfo(id: "a", displayName: "A", release: nil, dbSize: 100, isEnabled: true, isDownloaded: true),
            DocsetInfo(id: "b", displayName: "B", release: nil, dbSize: 100, isEnabled: true, isDownloaded: false),
            DocsetInfo(id: "c", displayName: "C", release: nil, dbSize: 100, isEnabled: false, isDownloaded: true),
        ]
        let enabled = service.enabledDocsets
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled[0].id, "a")
    }

    func testDocDirectoryPath() {
        let dir = DocsetInfo.docDirectory(for: "javascript")
        XCTAssertTrue(dir.path.contains("Clipsmith/DevDocs/javascript"))
    }
}
