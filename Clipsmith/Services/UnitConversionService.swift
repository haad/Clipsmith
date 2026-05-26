import Foundation

// MARK: - UnitConversionService
//
// A `nonisolated struct` per the Architectural Responsibility Map (RESEARCH.md).
// Foundation provides NO `init(symbol:)` for `UnitLength`/`UnitMass`/`UnitTemperature`/
// `UnitVolume`, so a manual `[String: Dimension]` alias table is mandatory (RESEARCH.md
// Pattern 4).
//
// Currency-vs-unit disambiguation (Pitfall 5): if BOTH the from-unit and to-unit tokens
// match `^[A-Z]{3}$` (exactly 3 uppercase letters), the query is currency — return nil so
// `CommandPaletteService` can route to `CurrencyService` instead.
//
// "in" preposition vs inches (Pitfall 7): the query grammar is
//   `{value} {unit} to|in {unit}`
// The separator word (`to` or `in`) always falls between two `\S+` groups, so `"5 in to cm"`
// correctly parses value=5, from="in" (inches), to="cm".

nonisolated struct UnitConversionService {

    // MARK: - Unit Alias Table

    /// Maps every user-facing abbreviation and full name (lowercased) to a Foundation `Dimension`.
    ///
    /// This table is the mandatory bridge between free-form user text and the Foundation
    /// Measurement API, which provides no symbol-based lookup (RESEARCH.md Pattern 4).
    private static let unitMap: [String: Dimension] = {
        var map = [String: Dimension]()

        // ── Length ──────────────────────────────────────────────────────────────────
        map["m"]            = UnitLength.meters
        map["meter"]        = UnitLength.meters
        map["meters"]       = UnitLength.meters
        map["km"]           = UnitLength.kilometers
        map["kilometer"]    = UnitLength.kilometers
        map["kilometers"]   = UnitLength.kilometers
        map["cm"]           = UnitLength.centimeters
        map["centimeter"]   = UnitLength.centimeters
        map["centimeters"]  = UnitLength.centimeters
        map["mm"]           = UnitLength.millimeters
        map["millimeter"]   = UnitLength.millimeters
        map["millimeters"]  = UnitLength.millimeters
        map["mi"]           = UnitLength.miles
        map["mile"]         = UnitLength.miles
        map["miles"]        = UnitLength.miles
        map["yd"]           = UnitLength.yards
        map["yard"]         = UnitLength.yards
        map["yards"]        = UnitLength.yards
        map["ft"]           = UnitLength.feet
        map["foot"]         = UnitLength.feet
        map["feet"]         = UnitLength.feet
        map["in"]           = UnitLength.inches
        map["inch"]         = UnitLength.inches
        map["inches"]       = UnitLength.inches
        map["nm"]           = UnitLength.nauticalMiles
        map["nmi"]          = UnitLength.nauticalMiles
        map["ly"]           = UnitLength.lightyears
        map["lightyear"]    = UnitLength.lightyears
        map["lightyears"]   = UnitLength.lightyears

        // ── Mass ─────────────────────────────────────────────────────────────────────
        map["kg"]           = UnitMass.kilograms
        map["kilogram"]     = UnitMass.kilograms
        map["kilograms"]    = UnitMass.kilograms
        map["g"]            = UnitMass.grams
        map["gram"]         = UnitMass.grams
        map["grams"]        = UnitMass.grams
        map["mg"]           = UnitMass.milligrams
        map["milligram"]    = UnitMass.milligrams
        map["milligrams"]   = UnitMass.milligrams
        map["lb"]           = UnitMass.pounds
        map["lbs"]          = UnitMass.pounds
        map["pound"]        = UnitMass.pounds
        map["pounds"]       = UnitMass.pounds
        map["oz"]           = UnitMass.ounces
        map["ounce"]        = UnitMass.ounces
        map["ounces"]       = UnitMass.ounces
        map["st"]           = UnitMass.stones
        map["stone"]        = UnitMass.stones
        map["stones"]       = UnitMass.stones
        map["t"]            = UnitMass.metricTons
        map["tonne"]        = UnitMass.metricTons
        map["tonnes"]       = UnitMass.metricTons
        map["mt"]           = UnitMass.metricTons
        map["ton"]          = UnitMass.shortTons
        map["tons"]         = UnitMass.shortTons

        // ── Temperature ───────────────────────────────────────────────────────────────
        // Note: "k" is Kelvin (temperature). UnitMass has no "k" symbol so there is no
        // collision with mass aliases.
        map["c"]            = UnitTemperature.celsius
        map["celsius"]      = UnitTemperature.celsius
        map["degc"]         = UnitTemperature.celsius
        map["f"]            = UnitTemperature.fahrenheit
        map["fahrenheit"]   = UnitTemperature.fahrenheit
        map["degf"]         = UnitTemperature.fahrenheit
        map["k"]            = UnitTemperature.kelvin
        map["kelvin"]       = UnitTemperature.kelvin

        // ── Volume ────────────────────────────────────────────────────────────────────
        map["l"]              = UnitVolume.liters
        map["liter"]          = UnitVolume.liters
        map["liters"]         = UnitVolume.liters
        map["litre"]          = UnitVolume.liters
        map["litres"]         = UnitVolume.liters
        map["ml"]             = UnitVolume.milliliters
        map["milliliter"]     = UnitVolume.milliliters
        map["milliliters"]    = UnitVolume.milliliters
        map["gal"]            = UnitVolume.gallons
        map["gallon"]         = UnitVolume.gallons
        map["gallons"]        = UnitVolume.gallons
        map["qt"]             = UnitVolume.quarts
        map["quart"]          = UnitVolume.quarts
        map["quarts"]         = UnitVolume.quarts
        map["pt"]             = UnitVolume.pints
        map["pint"]           = UnitVolume.pints
        map["pints"]          = UnitVolume.pints
        map["cup"]            = UnitVolume.cups
        map["cups"]           = UnitVolume.cups
        map["floz"]           = UnitVolume.fluidOunces
        map["tbsp"]           = UnitVolume.tablespoons
        map["tablespoon"]     = UnitVolume.tablespoons
        map["tablespoons"]    = UnitVolume.tablespoons
        map["tsp"]            = UnitVolume.teaspoons
        map["teaspoon"]       = UnitVolume.teaspoons
        map["teaspoons"]      = UnitVolume.teaspoons
        map["igal"]           = UnitVolume.imperialGallons

        return map
    }()

    // MARK: - Query Regex

    /// Parses `{value} {unit} to|in {unit}` queries.
    ///
    /// Groups:
    ///   1. Numeric value (digits, commas, scientific notation)
    ///   2. From-unit token
    ///   3. To-unit token
    ///
    /// The separator keyword (`to` or `in`) must appear between two unit tokens — this
    /// ensures that `"5 in to cm"` parses from="in" (inches) and to="cm", not treating
    /// the leading "in" as the separator (Pitfall 7).
    private static let queryRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°]+)\s+(?:to|in)\s+([\w°]+)\s*$"#,
        options: [.caseInsensitive]
    )

    // MARK: - Currency Disambiguation

    /// Returns `true` iff both tokens are exactly 3 ASCII letters — the shape of an ISO 4217
    /// currency code. When true, the query should be routed to `CurrencyService`, not unit
    /// conversion (Pitfall 5 — alias collision guard).
    ///
    /// This is `static` so it can be called without instantiating `UnitConversionService`.
    static func isCurrencyPair(_ a: String, _ b: String) -> Bool {
        let aUp = a.uppercased()
        let bUp = b.uppercased()
        return aUp.count == 3 && bUp.count == 3
            && aUp.allSatisfy({ $0.isLetter })
            && bUp.allSatisfy({ $0.isLetter })
    }

    // MARK: - Conversion

    /// Parses a natural-language unit conversion query and returns the converted value and
    /// the target unit label as typed by the user.
    ///
    /// - Parameter query: Free-form text such as `"5 km to miles"` or `"100 C in F"`.
    /// - Returns: A `(value, unit)` tuple on success, or `nil` when:
    ///   - The query does not match the `{value} {unit} to|in {unit}` grammar
    ///   - Either unit is not in the alias table
    ///   - The from/to dimensions are incompatible (e.g., mass → length)
    ///   - Both unit tokens match the 3-letter ISO code shape → routed to currency
    static func convert(_ query: String) -> (value: Double, unit: String)? {
        let ns = query as NSString
        let range = NSRange(query.startIndex..., in: query)

        guard let match = queryRegex.firstMatch(in: query, range: range),
              match.numberOfRanges == 4 else { return nil }

        // Helper: extract a capture group by index
        func cap(_ i: Int) -> String {
            let r = match.range(at: i)
            guard r.location != NSNotFound else { return "" }
            return ns.substring(with: r)
        }

        // 1. Parse numeric value
        guard let value = Double(cap(1).replacingOccurrences(of: ",", with: "")) else {
            return nil
        }

        let fromToken = cap(2)
        let toToken   = cap(3)

        // 2. Currency disambiguation FIRST (Pitfall 5)
        //    If both tokens look like ISO 4217 codes, defer to CurrencyService.
        if isCurrencyPair(fromToken, toToken) { return nil }

        // 3. Alias table lookups
        guard let fromUnit = unitMap[fromToken.lowercased()],
              let toUnit   = unitMap[toToken.lowercased()] else { return nil }

        // 4. Dimension compatibility guard
        //    Prevents converting kg → meters (would crash inside Foundation Measurement).
        guard type(of: fromUnit) == type(of: toUnit) else { return nil }

        // 5. Foundation Measurement conversion
        let measurement = Measurement(value: value, unit: fromUnit)
        let converted   = measurement.converted(to: toUnit)

        // Return the converted value and preserve the user's original casing for the
        // target unit label so the display matches what they typed.
        return (converted.value, toToken)
    }
}
