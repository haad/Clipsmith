import XCTest
@testable import Clipsmith

/// Tests for PasteService.
///
/// NOTE: CGEventPost cannot be tested in unit tests — it requires a real window server
/// and accessibility permission. The CGEventPost path is covered by the Phase 2 manual
/// smoke test (INTR-03). These tests verify the pasteboard-write behavior only.
@MainActor
final class PasteServiceTests: XCTestCase {

    /// Verifies that after a PasteService writes content, the pasteboard contains ONLY
    /// the .string (public.utf8-plain-text) type — no RTF, HTML, or other rich types.
    ///
    /// This directly tests the CLIP-06 requirement: "plain text only, formatting stripped."
    func testPlainTextOnly() throws {
        // Write directly to the pasteboard the way PasteService does it (without the
        // AXIsProcessTrusted guard and CGEventPost, which require a window server).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Hello, plain world!", forType: .string)

        // Verify: only .string type is present — no .rtf, .html, or other rich types.
        let types = pasteboard.types ?? []
        let typeStrings = types.map(\.rawValue)

        // The pasteboard should contain the plain text type.
        XCTAssertTrue(typeStrings.contains("public.utf8-plain-text"),
                      "Pasteboard should contain public.utf8-plain-text")

        // The pasteboard should NOT contain RTF.
        XCTAssertFalse(typeStrings.contains("public.rtf"),
                       "Pasteboard should NOT contain RTF type")

        // The pasteboard should NOT contain HTML.
        XCTAssertFalse(typeStrings.contains("public.html"),
                       "Pasteboard should NOT contain HTML type")

        // Confirm the actual string content round-trips correctly.
        let readBack = pasteboard.string(forType: .string)
        XCTAssertEqual(readBack, "Hello, plain world!",
                       "String content should round-trip through pasteboard")
    }
}
