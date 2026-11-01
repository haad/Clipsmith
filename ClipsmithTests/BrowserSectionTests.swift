import XCTest
@testable import Clipsmith

final class BrowserSectionTests: XCTestCase {
    func testOrderAndKeyboardIndex() {
        XCTAssertEqual(BrowserSection.allCases, [.snippets, .prompts, .docs, .toolkit])
        XCTAssertEqual(BrowserSection.docs.keyboardIndex, 3)
        XCTAssertEqual(BrowserSection.toolkit.title, "Toolkit")
    }

    func testAvailableHidesDocsWhenFlagOff() {
        XCTAssertEqual(BrowserSection.available(docLookupEnabled: false), [.snippets, .prompts, .toolkit])
        XCTAssertEqual(BrowserSection.available(docLookupEnabled: true), BrowserSection.allCases)
    }

    func testOpenRequestRoundTripsThroughUserInfo() {
        let req = BrowserOpenRequest(section: .docs, query: "map")
        let parsed = BrowserOpenRequest(userInfo: req.userInfo)
        XCTAssertEqual(parsed?.section, .docs)
        XCTAssertEqual(parsed?.query, "map")
    }

    func testOpenRequestNilWhenEmpty() {
        XCTAssertNil(BrowserOpenRequest(userInfo: nil))
        XCTAssertNil(BrowserOpenRequest(userInfo: ["unrelated": 1]))
        XCTAssertNil(BrowserOpenRequest(userInfo: ["section": "nope"])?.section)
    }
}
