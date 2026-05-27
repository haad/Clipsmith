import Foundation

// MARK: - ExpressionEvaluator

/// Pure-Swift math expression evaluator backed by `NSExpression`.
///
/// Design rationale (D-04, D-05, D-06):
/// - Uses `NSExpression(format:)` for arithmetic per Decision D-04.
/// - The safe-chars regex gate is **mandatory** because `NSExpression` raises an
///   uncatchable ObjC `NSInvalidArgumentException` for malformed input (T-12-01
///   mitigation). Every code path that reaches `NSExpression(format:)` is guarded
///   by the regex check.
/// - The `^` character is preprocessed to `**` before evaluation because
///   NSExpression treats `^` as bitwise XOR, not exponentiation (Pitfall 1).
/// - `@MainActor` on `evaluate(_:)` matches the Architectural Responsibility Map:
///   the App Launcher bezel calls this from the main actor.
///
/// Note: sin()/cos() are listed in D-05 but require a separate pre-processor
/// (RESEARCH.md Open Question 1). Deferred; not implemented in Phase 12 unless
/// Plan 03 adds them.
nonisolated struct ExpressionEvaluator {

    // MARK: - Private constants

    /// Compiled safe-chars regex. Characters permitted after function names are
    /// stripped: digits, whitespace, grouping parens, decimal point, arithmetic
    /// operators (+  -  *  /), comma (for multi-arg functions), and scientific
    /// notation exponent markers (e, E).
    ///
    /// `^` is intentionally NOT in the class — it is stripped by preprocessing
    /// before the regex runs.  `*` and `/` cover both regular and `**` (power)
    /// since `**` is two adjacent `*` characters, both already in the class.
    private static let safeMathRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^[\d\s()\.\+\-\*/,eE]+$"#
    )

    /// Detects integer division by zero: `/` followed by optional whitespace then `0`
    /// that is NOT followed by a digit or decimal point (i.e., not `0.0` or `0.5`).
    ///
    /// NSExpression silently returns `0.0` for integer `10 / 0` instead of producing
    /// Infinity/NaN, so this regex catches it before evaluation.
    private static let intDivByZeroRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"/\s*0(?![.\d])"#
    )

    /// Matches bare integer literals not adjacent to a decimal point.
    /// Used to inject `.0` so NSExpression uses floating-point arithmetic.
    /// e.g. `70000/640` → `70000.0/640.0` → 109.375 instead of 109.
    private static let bareIntRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?<![.\d])(\d+)(?![.\d])"#
    )

    /// NSExpression built-in function names accepted in expressions (D-05).
    /// These names are stripped from the expression before the safe-chars regex
    /// is applied so that e.g. `sqrt(16)` passes the gate.
    private static let funcNames: [String] = [
        "sqrt", "abs", "ceiling", "floor", "ln", "log", "exp"
    ]

    // MARK: - Public interface

    /// Evaluates a raw math expression string and returns the result, or `nil`
    /// if the expression is invalid, unsafe, or results in a non-finite value.
    ///
    /// Pipeline:
    /// 1. Trim → empty returns nil.
    /// 2. Preprocess `^` → `**` (caret-to-power; Pitfall 1 mitigation).
    /// 3. Strip known function names and apply safe-chars regex gate (T-12-01).
    /// 4. Evaluate with `NSExpression(format:)`.
    /// 5. Reject NaN and Infinity (division-by-zero / overflow guard, Pitfall 8).
    ///
    /// - Parameter rawText: The free-form text typed by the user.
    /// - Returns: The evaluated `Double`, or `nil` on any failure.
    @MainActor
    static func evaluate(_ rawText: String) -> Double? {
        // 1. Trim and reject empty input.
        let trimmed = rawText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 2. Preprocess: replace `^` (not part of an existing `**`) with `**`.
        //    The look-behind/ahead avoids double-replacing if user already typed `**`.
        let expr = trimmed.replacingOccurrences(
            of: #"(?<![*])\^(?![*])"#,
            with: "**",
            options: .regularExpression
        )

        // 3. Build stripped copy: lowercase the expression then remove all
        //    accepted function names. What remains must match safeMathRegex.
        var stripped = expr.lowercased()
        for fn in funcNames {
            stripped = stripped.replacingOccurrences(of: fn, with: "")
        }

        let range = NSRange(stripped.startIndex..., in: stripped)
        guard safeMathRegex.firstMatch(in: stripped, range: range) != nil else {
            // Input contains characters outside the allowed set — reject without
            // calling NSExpression (T-12-01 mitigation).
            return nil
        }

        // 3b. Detect integer division by zero (NSExpression returns 0.0 silently instead
        //     of producing Infinity/NaN, so we must reject it pre-evaluation).
        let exprRange = NSRange(expr.startIndex..., in: expr)
        if intDivByZeroRegex.firstMatch(in: expr, range: exprRange) != nil {
            return nil
        }

        // 3c. Reject incomplete expressions ending with a dangling operator or open paren.
        //     NSExpression(format:) throws an uncaught ObjC exception for these (T-12-01).
        //     e.g. "2+" → NSExpression tries to parse "2+ == 1" and crashes.
        if let last = expr.last(where: { !$0.isWhitespace }), "+-*/,(".contains(last) {
            return nil
        }

        // 3d. Promote bare integer literals to doubles so NSExpression uses
        //     floating-point arithmetic. Without this, `70000/640` evaluates as
        //     integer division (= 109) instead of 109.375.
        let floatExpr = bareIntRegex.stringByReplacingMatches(
            in: expr,
            range: NSRange(expr.startIndex..., in: expr),
            withTemplate: "$1.0"
        )

        // 4. Evaluate with NSExpression.
        //    The safe-chars gate above ensures we never reach here with untrusted input.
        let nsExpr = NSExpression(format: floatExpr)
        guard let nsNumber = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }

        // 5. Extract Double and reject non-finite values.
        let result = nsNumber.doubleValue
        guard !result.isNaN && !result.isInfinite else { return nil }

        return result
    }

    /// Returns a human-readable display string for a math result (D-06).
    ///
    /// Whole numbers are shown without a decimal point; fractional values use
    /// up to 6 significant figures via `%.6g` to avoid floating-point noise
    /// (e.g. `211.9999999999945` formats as `"212"`).
    ///
    /// Uses `en_US` locale for deterministic grouping separator in tests. The
    /// `NumberFormatter` applies decimal grouping (e.g. `1,000`) for readability.
    ///
    /// - Parameter value: The evaluated `Double` to format.
    /// - Returns: A locale-formatted string suitable for display in the bezel.
    nonisolated static func formatResult(_ value: Double) -> String {
        // Treat values that are effectively whole numbers as integers.
        if value == value.rounded(.toNearestOrEven) && !value.isInfinite && abs(value) < 1e15 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "en_US")
            formatter.maximumFractionDigits = 0
            let intValue = Int64(value)
            return formatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)"
        }
        return String(format: "%.6g", value)
    }

    /// Returns a clipboard-safe string for a math result (D-06).
    ///
    /// Uses `%.10g` with no thousands grouping so the value is paste-safe in
    /// code editors, spreadsheets, and terminal commands.
    ///
    /// - Parameter value: The evaluated `Double` to format.
    /// - Returns: A plain numeric string without grouping separators.
    nonisolated static func copyableResult(_ value: Double) -> String {
        String(format: "%.10g", value)
    }
}
