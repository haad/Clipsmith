import XCTest
@testable import Clipsmith

@MainActor
final class BrowserWindowViewModelTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "BrowserWindowViewModelTests-\(UUID().uuidString)")
    }

    func testDefaultsToSnippets() {
        XCTAssertEqual(BrowserWindowViewModel(defaults: defaults).selectedSection, .snippets)
    }

    func testRemembersLastSection() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.selectedSection = .toolkit
        XCTAssertEqual(BrowserWindowViewModel(defaults: defaults).selectedSection, .toolkit)
    }

    func testApplySelectsSectionAndStoresDocsQuery() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.apply(BrowserOpenRequest(section: .docs, query: "map"), docLookupEnabled: true)
        XCTAssertEqual(vm.selectedSection, .docs)
        XCTAssertEqual(vm.pendingDocsQuery, "map")
    }

    func testApplyIgnoresQueryForOtherSections() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.apply(BrowserOpenRequest(section: .prompts, query: "x"), docLookupEnabled: true)
        XCTAssertNil(vm.pendingDocsQuery)
    }

    /// Review Focus 3: Docs was the last section, the flag is now off.
    func testApplyFallsBackWhenDocsDisabled() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.selectedSection = .docs
        vm.apply(BrowserOpenRequest(section: nil, query: nil), docLookupEnabled: false)
        XCTAssertEqual(vm.selectedSection, .snippets)
        vm.apply(BrowserOpenRequest(section: .docs, query: "q"), docLookupEnabled: false)
        XCTAssertEqual(vm.selectedSection, .snippets)
        XCTAssertNil(vm.pendingDocsQuery)
    }

    /// Review fix: the docs hotkey with nothing selected must still clear and focus the field.
    func testApplyDocsWithNilQueryYieldsEmptyPrefill() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.apply(BrowserOpenRequest(section: .docs, query: nil), docLookupEnabled: true)
        XCTAssertEqual(vm.pendingDocsQuery, "")
    }

    /// A section-less request (flag toggles, onAppear) must not touch a Docs field.
    func testApplyWithoutSectionLeavesPrefillAlone() {
        let vm = BrowserWindowViewModel(defaults: defaults)
        vm.selectedSection = .docs
        vm.apply(BrowserOpenRequest(section: nil, query: nil), docLookupEnabled: true)
        XCTAssertNil(vm.pendingDocsQuery)
    }
}
