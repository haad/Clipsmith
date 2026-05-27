import XCTest
@testable import Clipsmith

/// Unit tests for `ExpressionEvaluator` — covers D-04, D-05, D-06 requirements.
///
/// Tests: basic arithmetic, invalid free-form input, caret-to-power preprocessing,
/// integer and float division by zero, and result display formatting.
@MainActor
final class ExpressionEvaluatorTests: XCTestCase {

    // MARK: - Basic arithmetic

    /// D-04: Basic addition must evaluate to the correct numeric result.
    func testBasicAdditionEvaluatesToFour() {
        XCTAssertEqual(ExpressionEvaluator.evaluate("2 + 2"), 4.0)
    }

    // MARK: - Safety gate

    /// T-12-01: Free-form text that is not a math expression must be rejected
    /// by the safe-chars regex gate without calling NSExpression.
    func testInvalidFreeFormInputReturnsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("hello world"))
    }

    // MARK: - Caret preprocessing (Pitfall 1 mitigation)

    /// NSExpression treats `^` as bitwise XOR. ExpressionEvaluator must preprocess
    /// `^` to `**` so `2^10` evaluates as 2 to the power of 10 = 1024.
    func testCaretPreprocessedToPowerYields1024() {
        XCTAssertEqual(ExpressionEvaluator.evaluate("2^10"), 1024.0)
    }

    // MARK: - Division by zero

    /// D-04: Integer division by zero must return nil (not crash or produce NaN/Infinity).
    func testIntegerDivisionByZeroReturnsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("10 / 0"))
    }

    /// D-04: Float division by zero must return nil (Infinity is rejected).
    func testFloatDivisionByZeroReturnsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("10.0 / 0.0"))
    }

    // MARK: - Float division (integer-literal promotion)

    /// NSExpression performs integer division when both operands are integer literals.
    /// ExpressionEvaluator must promote bare integers to doubles so 70000/640 = 109.375.
    func testIntegerDivisionProducesFractionalResult() {
        let result = ExpressionEvaluator.evaluate("70000/640")
        XCTAssertEqual(result ?? 0, 109.375, accuracy: 1e-9)
    }

    func testMixedIntFloatDivisionPreservesDecimals() {
        XCTAssertEqual(ExpressionEvaluator.evaluate("1/3") ?? 0, 1.0/3.0, accuracy: 1e-9)
        XCTAssertEqual(ExpressionEvaluator.evaluate("7/2") ?? 0, 3.5, accuracy: 1e-9)
    }

    // MARK: - Trailing-operator gate (T-12-01 extension)

    /// Incomplete expressions ending with a dangling operator must return nil
    /// without calling NSExpression (which would throw an uncaught ObjC exception).
    func testTrailingOperatorReturnsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("2+"))
        XCTAssertNil(ExpressionEvaluator.evaluate("250/"))
        XCTAssertNil(ExpressionEvaluator.evaluate("5*"))
        XCTAssertNil(ExpressionEvaluator.evaluate("3-"))
    }

    // MARK: - Result formatting (D-06)

    /// D-06: Whole-number results must be displayed without a decimal point.
    /// `formatResult(42.0)` must return `"42"`, not `"42.0"`.
    func testFormatResultWholeNumberDropsDecimal() {
        XCTAssertEqual(ExpressionEvaluator.formatResult(42.0), "42")
    }
}
