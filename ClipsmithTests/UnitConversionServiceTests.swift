import XCTest
@testable import Clipsmith

/// Test suite for `UnitConversionService`.
///
/// Covers D-07 (Foundation Measurement unit conversion), D-08 (natural query syntax),
/// Pitfall 4 (temperature float drift), Pitfall 5 (alias collisions / currency
/// disambiguation), and Pitfall 7 ("in" preposition vs inches unit).
final class UnitConversionServiceTests: XCTestCase {

    // MARK: - Length Conversions

    func testKilometersToMilesReturnsCorrectValue() {
        let result = UnitConversionService.convert("5 km to miles")
        XCTAssertNotNil(result, "5 km to miles should return a result")
        XCTAssertEqual(result!.value, 3.10686, accuracy: 0.001)
        XCTAssertEqual(result!.unit, "miles")
    }

    // MARK: - Temperature Conversions (Pitfall 4: float drift)

    func testCelsiusToFahrenheitReturnsTwoHundredTwelve() {
        let result = UnitConversionService.convert("100 C to F")
        XCTAssertNotNil(result, "100 C to F should return a result")
        // Foundation temperature conversion has minor float drift; allow 0.001 accuracy
        XCTAssertEqual(result!.value, 212.0, accuracy: 0.001)
        XCTAssertEqual(result!.unit, "F")
    }

    func testFahrenheitToCelsiusReturnsZero() {
        let result = UnitConversionService.convert("32 F to C")
        XCTAssertNotNil(result, "32 F to C should return a result")
        XCTAssertEqual(result!.value, 0.0, accuracy: 0.001)
        XCTAssertEqual(result!.unit, "C")
    }

    // MARK: - Volume Conversions

    func testLitersToCupsInRange() {
        let result = UnitConversionService.convert("2 liters in cups")
        XCTAssertNotNil(result, "2 liters in cups should return a result")
        XCTAssertGreaterThan(result!.value, 8.0)
        XCTAssertLessThan(result!.value, 9.0)
    }

    // MARK: - Pitfall 7: "in" preposition vs "in" (inches)

    func testInchesToCentimetersHandlesPrepositionCollision() {
        // "5 in to cm" — "in" before "to" is the unit (inches), not the separator
        let result = UnitConversionService.convert("5 in to cm")
        XCTAssertNotNil(result, "5 in to cm should return a result")
        XCTAssertEqual(result!.value, 12.7, accuracy: 0.001)
        XCTAssertEqual(result!.unit, "cm")
    }

    // MARK: - Mass Conversions

    func testKilogramsToPoundsReturnsValue() {
        let result = UnitConversionService.convert("5 kg to lb")
        XCTAssertNotNil(result, "5 kg to lb should return a result")
        XCTAssertEqual(result!.value, 11.0231, accuracy: 0.001)
    }

    // MARK: - Invalid and Edge Cases

    func testInvalidQueryReturnsNil() {
        XCTAssertNil(UnitConversionService.convert("hello world"))
    }

    func testEmptyQueryReturnsNil() {
        XCTAssertNil(UnitConversionService.convert(""))
    }

    func testIncompatibleDimensionsReturnsNil() {
        // kg → meters: mass → length is not allowed
        XCTAssertNil(UnitConversionService.convert("5 kg to m"))
    }

    // MARK: - Pitfall 5: Currency disambiguation (3-letter ISO codes)

    func testCurrencyPairReturnsNilForRoutingToCurrencyService() {
        // Both USD and EUR match ^[A-Z]{3}$, so unit service should return nil
        // and route to CurrencyService
        XCTAssertNil(UnitConversionService.convert("5 USD to EUR"))
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitiveUnitNames() {
        // Mixed case unit names should still work
        XCTAssertNotNil(UnitConversionService.convert("5 KM to MILES"))
    }

    // MARK: - "in" preposition variant (D-08)

    func testKilometersToMilesUsingInPreposition() {
        // "in" and "to" should both work as separators (D-08)
        let resultTo = UnitConversionService.convert("5 km to miles")
        let resultIn = UnitConversionService.convert("5 km in miles")
        XCTAssertNotNil(resultTo)
        XCTAssertNotNil(resultIn)
        XCTAssertEqual(resultTo!.value, resultIn!.value, accuracy: 0.0001)
    }
}
