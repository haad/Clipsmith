import XCTest
import AppKit
@testable import FlycutSwift

/// Unit tests for BezelController NSPanel configuration.
///
/// These tests verify the panel properties that are critical for correct
/// non-activating HUD behaviour. They do NOT test show/hide lifecycle
/// (which requires a running display server) or keyboard routing.
@MainActor
final class BezelControllerTests: XCTestCase {

    // MARK: - styleMask

    /// The .nonactivatingPanel bit MUST be in the init styleMask.
    /// Setting it afterwards does not update the WindowServer tag.
    func testStyleMaskContainsNonActivatingPanel() {
        let controller = BezelController()
        XCTAssertTrue(
            controller.styleMask.contains(.nonactivatingPanel),
            "styleMask must contain .nonactivatingPanel — must be set in init, not afterwards"
        )
    }

    // MARK: - Window level

    func testWindowLevelAboveScreenSaver() {
        let controller = BezelController()
        let screenSaverLevel = Int(CGWindowLevelForKey(.screenSaverWindow))
        XCTAssertGreaterThan(
            controller.level.rawValue,
            screenSaverLevel,
            "Bezel panel must appear above fullscreen apps (screenSaverWindow level)"
        )
    }

    // MARK: - collectionBehavior

    func testCollectionBehaviorContainsCanJoinAllSpaces() {
        let controller = BezelController()
        XCTAssertTrue(
            controller.collectionBehavior.contains(.canJoinAllSpaces),
            "collectionBehavior must include .canJoinAllSpaces to appear on all Spaces"
        )
    }

    func testCollectionBehaviorContainsFullScreenAuxiliary() {
        let controller = BezelController()
        XCTAssertTrue(
            controller.collectionBehavior.contains(.fullScreenAuxiliary),
            "collectionBehavior must include .fullScreenAuxiliary to appear over fullscreen apps"
        )
    }

    // MARK: - canBecomeKey / canBecomeMain

    func testCanBecomeKeyTrue() {
        let controller = BezelController()
        XCTAssertTrue(
            controller.canBecomeKey,
            "canBecomeKey must be true so the search TextField can receive keyboard input"
        )
    }

    func testCanBecomeMainFalse() {
        let controller = BezelController()
        XCTAssertFalse(
            controller.canBecomeMain,
            "canBecomeMain must be false — bezel must never become the main window"
        )
    }

    // MARK: - isReleasedWhenClosed

    func testIsReleasedWhenClosedFalse() {
        let controller = BezelController()
        XCTAssertFalse(
            controller.isReleasedWhenClosed,
            "isReleasedWhenClosed must be false so the panel can be reused across show/hide cycles"
        )
    }

    // MARK: - isHotkeyHold state (Bug #3)

    /// isHotkeyHold defaults to false — bezel starts in non-hold mode.
    func testIsHotkeyHoldDefaultsFalse() {
        let controller = BezelController()
        XCTAssertFalse(
            controller.isHotkeyHold,
            "isHotkeyHold must default to false — hold mode is opt-in per hotkey press"
        )
    }

    /// hide() must reset isHotkeyHold to false on all exit paths.
    func testHideResetsIsHotkeyHold() {
        let controller = BezelController()
        controller.isHotkeyHold = true
        controller.hide()
        XCTAssertFalse(
            controller.isHotkeyHold,
            "hide() must reset isHotkeyHold to false — prevents stale hold state on next show"
        )
    }
}
