import XCTest
@testable import Clipsmith

@MainActor
final class ClipboardMonitorTests: XCTestCase {

    // MARK: - shouldSkip tests

    /// shouldSkip returns true when pasteboard contains "org.nspasteboard.TransientType"
    func testShouldSkipTransientType() throws {
        let monitor = ClipboardMonitor()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([NSPasteboard.PasteboardType("org.nspasteboard.TransientType"), .string], owner: nil)
        pb.setString("secret", forType: .string)

        XCTAssertTrue(monitor.shouldSkip(pasteboard: pb), "TransientType should be skipped")
    }

    /// shouldSkip returns true when pasteboard contains "org.nspasteboard.ConcealedType"
    func testShouldSkipConcealedType() throws {
        let monitor = ClipboardMonitor()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"), .string], owner: nil)
        pb.setString("secret", forType: .string)

        XCTAssertTrue(monitor.shouldSkip(pasteboard: pb), "ConcealedType should be skipped")
    }

    /// shouldSkip returns true when pasteboard contains "com.agilebits.onepassword"
    func testShouldSkipOnePasswordType() throws {
        let monitor = ClipboardMonitor()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([NSPasteboard.PasteboardType("com.agilebits.onepassword"), .string], owner: nil)
        pb.setString("secretpassword", forType: .string)

        XCTAssertTrue(monitor.shouldSkip(pasteboard: pb), "1Password type should be skipped")
    }

    /// shouldSkip returns false when pasteboard contains only "public.utf8-plain-text"
    func testShouldNotSkipNormalText() throws {
        let monitor = ClipboardMonitor()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("Hello, world!", forType: .string)

        XCTAssertFalse(monitor.shouldSkip(pasteboard: pb), "Normal plain text should NOT be skipped")
    }

    /// When blockedChangeCount matches current changeCount, onNewClipping is NOT called
    func testBlockedChangeCountSkipsSelfCapture() throws {
        let monitor = ClipboardMonitor()

        // Write to pasteboard and capture the resulting changeCount
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("test content for blocking", forType: .string)

        // Block this changeCount — simulates what PasteService does after its write
        monitor.blockedChangeCount = pb.changeCount

        // Set up the callback to detect if it's called
        var callbackFired = false
        monitor.onNewClipping = { _ in
            callbackFired = true
        }

        // Fake that lastChangeCount is behind so checkPasteboard thinks there is a change
        monitor.lastChangeCount = pb.changeCount - 1

        // Trigger the check — should NOT call onNewClipping because blockedChangeCount matches
        monitor.checkPasteboard()

        XCTAssertFalse(callbackFired, "onNewClipping should NOT be called when blockedChangeCount matches")
    }

    // MARK: - ClipboardEntry struct tests (Bug #1)

    /// ClipboardEntry struct is Sendable and has content, sourceAppName, sourceAppBundleURL fields
    func testClipboardEntryStructFields() throws {
        let entry = ClipboardEntry(
            content: "test content",
            sourceAppName: "Safari",
            sourceAppBundleURL: "/Applications/Safari.app"
        )
        XCTAssertEqual(entry.content, "test content")
        XCTAssertEqual(entry.sourceAppName, "Safari")
        XCTAssertEqual(entry.sourceAppBundleURL, "/Applications/Safari.app")
    }

    /// ClipboardEntry supports nil metadata fields
    func testClipboardEntryNilMetadata() throws {
        let entry = ClipboardEntry(
            content: "hello",
            sourceAppName: nil,
            sourceAppBundleURL: nil
        )
        XCTAssertEqual(entry.content, "hello")
        XCTAssertNil(entry.sourceAppName)
        XCTAssertNil(entry.sourceAppBundleURL)
    }

    /// onNewClipping callback receives ClipboardEntry (not raw String)
    func testOnNewClippingReceivesClipboardEntry() throws {
        let monitor = ClipboardMonitor()

        var receivedEntry: ClipboardEntry?
        monitor.onNewClipping = { entry in
            receivedEntry = entry
        }

        // Write to pasteboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("entry content", forType: .string)

        // Fake lastChangeCount so checkPasteboard detects change
        monitor.lastChangeCount = pb.changeCount - 1

        monitor.checkPasteboard()

        XCTAssertNotNil(receivedEntry, "onNewClipping callback should have fired")
        XCTAssertEqual(receivedEntry?.content, "entry content", "ClipboardEntry.content should match pasteboard string")
    }

    // MARK: - Adaptive polling tests (PERF-02)

    /// After start(), activityMonitor must be non-nil (NSEvent global monitor registered).
    func testActivityMonitorRegistered() throws {
        let monitor = ClipboardMonitor()
        monitor.start()
        // activityMonitor is private — expose via an internal computed property
        // `var hasActivityMonitor: Bool` that returns activityMonitor != nil
        XCTAssertTrue(monitor.hasActivityMonitor,
                      "activityMonitor should be registered after start()")
        monitor.stop()
        XCTAssertFalse(monitor.hasActivityMonitor,
                       "activityMonitor should be nil after stop()")
    }

    /// When the timer interval matches the expected interval (delta < 0.01),
    /// scheduleTimer should NOT be called again (avoid unnecessary timer churn).
    func testTimerNotRecreatedWhenIntervalUnchanged() throws {
        let monitor = ClipboardMonitor()
        monitor.start()
        // After start(), timer is set to activeInterval. Simulate an "active" tick
        // by calling checkPasteboardAdaptive() — the timer should NOT be recreated
        // because the interval is already correct.
        // Expose `var currentTimerInterval: TimeInterval?` (returns timer?.timeInterval)
        // and `var timerRecreationCount: Int` (incremented in scheduleTimer, test-only).
        let initialCount = monitor.timerRecreationCount
        monitor.checkPasteboardAdaptive()
        XCTAssertEqual(monitor.timerRecreationCount, initialCount,
                       "Timer should not be recreated when interval is unchanged")
        monitor.stop()
    }
}
