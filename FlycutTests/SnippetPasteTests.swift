import XCTest
@testable import FlycutSwift

/// Smoke tests verifying the snippet paste code path is callable.
///
/// These tests confirm PasteService.paste(content:into:) can be called with
/// arbitrary snippet strings — including single-line, multi-line, and empty content.
/// They do NOT verify actual CGEvent injection (that requires accessibility
/// permissions and a target app). Full paste verification is done in the
/// Plan 04 human checkpoint.
///
/// SNIP-05 compliance: the paste code path is exercised without crashing,
/// and is reachable from SnippetListView's double-click/Enter handler.
final class SnippetPasteTests: XCTestCase {

    @MainActor
    func testPasteServiceCanBeCalledWithSnippetContent() async {
        // Verify PasteService.paste(content:into:) accepts arbitrary snippet strings.
        let pasteService = PasteService()
        let snippetContent = "func hello() { print(\"Hello, World!\") }"
        // Calling paste with nil previousApp exercises the code path without
        // actually switching apps or posting CGEvents (no accessibility needed).
        await pasteService.paste(content: snippetContent, into: nil)
        // If we reach here, the paste code path is callable with snippet content.
        // Actual paste-into-app behaviour is verified manually in Plan 04 checkpoint.
    }

    @MainActor
    func testPasteServiceHandlesMultilineSnippet() async {
        let pasteService = PasteService()
        let multilineSnippet = """
        import Foundation

        struct Config {
            let host: String
            let port: Int
        }
        """
        await pasteService.paste(content: multilineSnippet, into: nil)
        // Multiline snippet content does not crash the paste path.
    }

    @MainActor
    func testPasteServiceHandlesEmptySnippet() async {
        let pasteService = PasteService()
        await pasteService.paste(content: "", into: nil)
        // Empty snippet content does not crash the paste path.
    }
}
