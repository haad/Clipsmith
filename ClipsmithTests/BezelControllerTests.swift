import XCTest
import AppKit
import SwiftData
@testable import Clipsmith

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

    // MARK: - Transform picker helpers

    /// Builds a controller whose view model holds one real clipping.
    /// ClippingInfo needs a valid PersistentIdentifier — obtained via an
    /// in-memory container (same "Option A" pattern as BezelViewModelTests).
    private func makeControllerWithClipping(_ content: String = "hello world") throws -> BezelController {
        let container = try makeTestContainer()
        let context = container.mainContext
        let clipping = ClipsmithSchemaV1.Clipping(content: content)
        context.insert(clipping)
        try context.save()

        let controller = BezelController()
        controller.viewModel.clippings = [
            ClippingInfo(
                id: clipping.persistentModelID,
                content: content,
                sourceAppName: nil,
                sourceAppBundleURL: nil,
                timestamp: clipping.timestamp
            )
        ]
        return controller
    }

    /// Builds a synthetic keyDown NSEvent for routing tests.
    private func makeKeyEvent(characters: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    // MARK: - Transform picker

    func testTabTogglesTransformPicker() throws {
        let controller = try makeControllerWithClipping()
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
        controller.toggleTransformPicker()
        XCTAssertTrue(controller.viewModel.isShowingTransformPicker)
        controller.toggleTransformPicker()
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
    }

    func testTransformPickerNoOpWithoutClipping() {
        let controller = BezelController()   // no clippings
        controller.toggleTransformPicker()
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
    }

    func testPickerKeyRoutingFilterAndNavigation() throws {
        let controller = try makeControllerWithClipping()
        controller.toggleTransformPicker()

        // j with empty filter navigates down.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "j", keyCode: 38))
        XCTAssertEqual(controller.viewModel.transformSelectedIndex, 1)

        // First typed letter starts the filter and resets selection.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "b", keyCode: 11))
        XCTAssertEqual(controller.viewModel.transformFilterText, "b")
        XCTAssertEqual(controller.viewModel.transformSelectedIndex, 0)

        // With a non-empty filter, j is filter text — not navigation.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "j", keyCode: 38))
        XCTAssertEqual(controller.viewModel.transformFilterText, "bj")

        // Backspace edits the filter.
        controller.handleTransformPickerKey(makeKeyEvent(characters: "\u{7F}", keyCode: 51))
        XCTAssertEqual(controller.viewModel.transformFilterText, "b")
    }

    func testPickerEscapeClosesPickerOnly() throws {
        let controller = try makeControllerWithClipping()
        controller.toggleTransformPicker()
        controller.handleTransformPickerKey(makeKeyEvent(characters: "\u{1B}", keyCode: 53))
        XCTAssertFalse(controller.viewModel.isShowingTransformPicker)
    }

    func testPickerEnterOnFailableTransformShowsErrorAndStaysOpen() async throws {
        let controller = try makeControllerWithClipping("not valid json { at all")
        controller.toggleTransformPicker()
        // Filter down to JSON Pretty Print deterministically.
        controller.viewModel.transformFilterText = "json pretty"
        guard let transform = controller.viewModel.currentTransform, transform.id == "format.jsonpretty" else {
            return XCTFail("Expected format.jsonpretty as top match")
        }
        // Await the apply path directly (Enter routing spawns the same call in a Task).
        await controller.applyTransformAndPaste(transform)
        XCTAssertEqual(controller.viewModel.transformError, "Not valid JSON")
        XCTAssertTrue(controller.viewModel.isShowingTransformPicker, "Picker stays open on failure")
    }
}
