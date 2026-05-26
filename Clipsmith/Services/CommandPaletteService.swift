import Foundation
import Observation

// MARK: - CommandResult

/// A value type representing the result of a single command-palette evaluation.
///
/// Sendable + Equatable so it can cross actor boundaries and be compared in tests
/// without issues.
struct CommandResult: Sendable, Equatable {

    /// The category of conversion that produced this result.
    enum Kind: String, Sendable {
        case math
        case unit
        case currency
    }

    /// Which kind of evaluation produced this result.
    let kind: Kind

    /// Human-readable display value (e.g., "4" or "3.10686").
    /// Delegates to `ExpressionEvaluator.formatResult(_:)`.
    let displayValue: String

    /// Clipboard-safe numeric string without thousands grouping.
    /// Delegates to `ExpressionEvaluator.copyableResult(_:)`.
    let copyableValue: String

    /// The raw query string echoed above the large result in `CommandPaletteView`.
    let expression: String

    /// The target unit or currency code (e.g., "miles" or "EUR"); nil for math results.
    let toUnit: String?
}

// MARK: - CommandPaletteService

/// Orchestration layer that dispatches a user query to the correct converter service
/// and returns a `CommandResult`.
///
/// **Dispatch order is critical (Pitfall 5):**
/// 1. Currency check runs FIRST. Queries like "10 USD to EUR" match the conversion
///    regex AND both tokens are 3-letter ISO codes. Routing them to
///    `UnitConversionService` would return nil (it has a currency disambiguator) — but
///    the intent is unambiguously currency conversion. Running `CurrencyService.isCurrencyQuery`
///    first short-circuits the ambiguity cleanly.
/// 2. Unit conversion runs SECOND. After ruling out currency, we try
///    `UnitConversionService.convert(_:)` for physical-unit queries like "5 km to miles".
/// 3. Bare math expression runs LAST. Expressions like "2+2" or "sqrt(16)" never contain
///    " to " or " in ", so they fail the conversion regex immediately and only
///    `ExpressionEvaluator` can handle them.
///
/// `CommandPaletteService` adds no new validation or NSExpression call sites — all
/// security gates live inside the services it calls (T-12-01b).
@MainActor @Observable
final class CommandPaletteService {

    // MARK: - Injected Dependencies

    /// Weak reference to the `CurrencyService` owned by `AppDelegate`.
    ///
    /// Declared `weak` to avoid a retain cycle: AppDelegate → CommandPaletteService →
    /// CurrencyService → (back to AppDelegate-owned state). In Plan 04 AppDelegate will
    /// call `setCurrencyService(_:)` after instantiating both services.
    private weak var currencyService: CurrencyService?

    // MARK: - Init

    init(currencyService: CurrencyService? = nil) {
        self.currencyService = currencyService
    }

    // MARK: - Dependency Injection

    /// Allows AppDelegate (Plan 04) to inject the shared `CurrencyService` after both
    /// services are created. Called separately from `init` because `AppLaunchViewModel`
    /// may create `CommandPaletteService` before `AppDelegate` finishes wiring.
    func setCurrencyService(_ service: CurrencyService?) {
        self.currencyService = service
    }

    // MARK: - Conversion Shape Regex

    /// Same grammar as `UnitConversionService.queryRegex` — matches
    /// `{value} {unit} to|in {unit}` — used here to decide whether to attempt
    /// currency or unit dispatch before falling through to bare math.
    ///
    /// Groups:
    ///   1. Numeric value (digits, commas, scientific notation)
    ///   2. From-unit / from-currency token
    ///   3. To-unit / to-currency token
    private static let conversionRegex = try! NSRegularExpression(
        pattern: #"^([\d.,]+(?:[eE][+-]?\d+)?)\s+([\w°]+)\s+(?:to|in)\s+([\w°]+)\s*$"#,
        options: [.caseInsensitive]
    )

    // MARK: - Evaluate

    /// Evaluates a user query and returns a `CommandResult`, or `nil` if the query
    /// is empty, whitespace-only, or cannot be evaluated.
    ///
    /// - Parameter query: The raw text after stripping the command-palette prefix.
    /// - Returns: A `CommandResult` on success, or `nil` on failure.
    func evaluate(_ query: String) -> CommandResult? {
        // 1. Trim and reject empty / whitespace-only input.
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 2. Attempt conversion-shape dispatch (currency or unit).
        let ns = trimmed as NSString
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = Self.conversionRegex.firstMatch(in: trimmed, range: range),
           match.numberOfRanges == 4 {

            // Extract capture groups.
            func cap(_ i: Int) -> String {
                let r = match.range(at: i)
                guard r.location != NSNotFound else { return "" }
                return ns.substring(with: r)
            }

            let valueStr   = cap(1).replacingOccurrences(of: ",", with: "")
            let fromToken  = cap(2)
            let toToken    = cap(3)

            guard let amount = Double(valueStr) else { return nil }

            // 2a. Currency check FIRST (Pitfall 5).
            if CurrencyService.isCurrencyQuery(from: fromToken, to: toToken) {
                // If we recognise the shape as currency but have no service or no rates,
                // return nil — do NOT fall through to unit conversion.
                guard let value = currencyService?.convert(amount: amount, from: fromToken, to: toToken) else {
                    return nil
                }
                return CommandResult(
                    kind: .currency,
                    displayValue: ExpressionEvaluator.formatResult(value),
                    copyableValue: ExpressionEvaluator.copyableResult(value),
                    expression: trimmed,
                    toUnit: toToken.uppercased()
                )
            }

            // 2b. Unit conversion SECOND.
            if let (value, unit) = UnitConversionService.convert(trimmed) {
                return CommandResult(
                    kind: .unit,
                    displayValue: ExpressionEvaluator.formatResult(value),
                    copyableValue: ExpressionEvaluator.copyableResult(value),
                    expression: trimmed,
                    toUnit: unit
                )
            }

            // Matched the conversion shape but couldn't convert — return nil.
            return nil
        }

        // 3. Bare math expression LAST.
        if let value = ExpressionEvaluator.evaluate(trimmed) {
            return CommandResult(
                kind: .math,
                displayValue: ExpressionEvaluator.formatResult(value),
                copyableValue: ExpressionEvaluator.copyableResult(value),
                expression: trimmed,
                toUnit: nil
            )
        }

        return nil
    }
}
