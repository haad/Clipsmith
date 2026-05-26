import XCTest
@testable import Clipsmith

/// Full test coverage for `CommandPaletteService`.
///
/// Covers dispatch ordering (currency → unit → math), edge cases (empty query,
/// whitespace, division by zero), and `CommandResult` Sendable + Equatable conformance.
@MainActor
final class CommandPaletteServiceTests: XCTestCase {

    private var service: CommandPaletteService!

    override func setUp() {
        super.setUp()
        service = CommandPaletteService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Empty / Whitespace

    func testEmptyQueryReturnsNil() {
        XCTAssertNil(service.evaluate(""))
    }

    func testWhitespaceOnlyQueryReturnsNil() {
        XCTAssertNil(service.evaluate("   "))
    }

    // MARK: - Bare Math (dispatches to ExpressionEvaluator)

    func testBareMathDispatchesToExpressionEvaluator() {
        let result = service.evaluate("2+2")
        XCTAssertNotNil(result, "2+2 must return a CommandResult")
        XCTAssertEqual(result?.kind, .math)
        XCTAssertEqual(result?.displayValue, "4")
        XCTAssertEqual(result?.expression, "2+2")
        XCTAssertNil(result?.toUnit, "Math results have no toUnit")
    }

    func testSqrtDispatchesToMath() {
        let result = service.evaluate("sqrt(16)")
        XCTAssertNotNil(result, "sqrt(16) must return a CommandResult")
        XCTAssertEqual(result?.kind, .math)
        XCTAssertEqual(result?.displayValue, "4")
    }

    func testCaretPowerDispatchesToMath() {
        let result = service.evaluate("2^10")
        XCTAssertNotNil(result, "2^10 must return a CommandResult")
        XCTAssertEqual(result?.kind, .math)
        XCTAssertEqual(result?.displayValue, "1,024")
    }

    // MARK: - Unit Conversion (dispatches to UnitConversionService)

    func testUnitConversionDispatchesToUnit() {
        let result = service.evaluate("5 km to miles")
        XCTAssertNotNil(result, "5 km to miles must return a CommandResult")
        XCTAssertEqual(result?.kind, .unit)
        XCTAssertEqual(result?.toUnit, "miles")
        // ~3.10686 formatted via %.6g
        let displayValue = result?.displayValue ?? ""
        XCTAssertTrue(displayValue.hasPrefix("3.10"),
            "5 km to miles should format to ~3.10686, got '\(displayValue)'")
    }

    func testCelsiusToFahrenheitFormattedAs212() {
        let result = service.evaluate("100 C to F")
        XCTAssertNotNil(result, "100 C to F must return a CommandResult")
        XCTAssertEqual(result?.kind, .unit)
        XCTAssertEqual(result?.toUnit, "F")
        // 100°C → 212°F, which rounds to 212 via %.6g smoothing
        XCTAssertEqual(result?.displayValue, "212",
            "100 C to F must display as 212 (Pitfall 4 %.6g smoothing)")
    }

    // MARK: - Invalid / Unrecognised

    func testInvalidExpressionReturnsNil() {
        XCTAssertNil(service.evaluate("hello"))
    }

    func testDivisionByZeroReturnsNil() {
        XCTAssertNil(service.evaluate("10 / 0"))
    }

    // MARK: - Currency (dispatches to CurrencyService)

    func testCurrencyQueryWithRatesReturnsResult() {
        // Create a CurrencyService backed by the bundled rates JSON.
        let currencyService = CurrencyService()
        currencyService.loadRates()
        service.setCurrencyService(currencyService)

        let result = service.evaluate("10 USD to EUR")
        XCTAssertNotNil(result, "10 USD to EUR must return a result when rates are loaded")
        XCTAssertEqual(result?.kind, .currency)
        XCTAssertEqual(result?.toUnit, "EUR")
        // The converted value should be a positive number (EUR is ~0.92 USD)
        if let displayValue = result?.displayValue {
            let numericValue = Double(displayValue.replacingOccurrences(of: ",", with: ""))
            XCTAssertNotNil(numericValue, "displayValue must be a number, got '\(displayValue)'")
            XCTAssertGreaterThan(numericValue ?? 0.0, 0.0, "Converted EUR amount must be positive")
        }
    }

    func testCurrencyQueryWithoutRatesReturnsNil() {
        // No currencyService injected — no fallthrough to unit conversion
        XCTAssertNil(service.evaluate("10 USD to EUR"),
            "Currency query without a CurrencyService must return nil (no fallthrough)")
    }

    func testCurrencyQueryWithInvalidPairReturnsNil() {
        // USD is a currency code, KM is not — currency lookup fails; unit lookup also fails
        // (USD is not in the unit alias table). Should return nil.
        let currencyService = CurrencyService()
        currencyService.loadRates()
        service.setCurrencyService(currencyService)

        XCTAssertNil(service.evaluate("5 USD to KM"),
            "5 USD to KM must return nil (USD-KM is not a valid currency or unit pair)")
    }

    // MARK: - CommandResult Sendable + Equatable

    func testCommandResultIsSendableAndEquatable() {
        // Compile-time check: constructing two identical results and asserting equality.
        let r1 = CommandResult(
            kind: .math,
            displayValue: "42",
            copyableValue: "42",
            expression: "6*7",
            toUnit: nil
        )
        let r2 = CommandResult(
            kind: .math,
            displayValue: "42",
            copyableValue: "42",
            expression: "6*7",
            toUnit: nil
        )
        XCTAssertEqual(r1, r2, "Two identical CommandResults must be equal")

        let r3 = CommandResult(
            kind: .unit,
            displayValue: "42",
            copyableValue: "42",
            expression: "6*7",
            toUnit: "miles"
        )
        XCTAssertNotEqual(r1, r3, "CommandResults with different kind/toUnit must not be equal")
    }
}
