import Foundation

// MARK: - FuzzyMatcher

/// Character-subsequence fuzzy matching algorithm with consecutive-bonus scoring.
///
/// Implements the "Pattern 1" algorithm from RESEARCH.md:
/// - A query matches a candidate if all query characters appear in the candidate in order
/// - Consecutive character matches receive a bonus that grows with each consecutive hit
/// - The bonus decays by half on non-matching characters
/// - The final score is normalized to [0.0, 1.0] relative to a perfect consecutive match
///
/// Usage:
/// ```swift
/// FuzzyMatcher.score("JSON.parse(...)", query: "jsonpar")  // non-nil (matches)
/// FuzzyMatcher.score("hello world",     query: "xyz")      // nil (no match)
/// FuzzyMatcher.score("hello",           query: "hello")    // 1.0 (perfect match)
/// ```
enum FuzzyMatcher {

    /// Returns a normalized match score in [0.0, 1.0], or nil if the query
    /// is not a subsequence of the candidate.
    ///
    /// - Parameters:
    ///   - candidate: The string to search within.
    ///   - query: The user-typed search string.
    /// - Returns: A score in (0.0, 1.0], or nil if `query` is not a subsequence
    ///   of `candidate`. Returns 1.0 for an empty query.
    static func score(_ candidate: String, query: String) -> Double? {
        // Empty query is a match for any candidate (score = perfect)
        guard !query.isEmpty else { return 1.0 }

        let lowerCandidate = candidate.lowercased()
        let lowerQuery = query.lowercased()

        let n = lowerQuery.count

        // Ideal score: sum of (1 + 2 + ... + n) = n*(n+1)/2
        // Each consecutive position i contributes bonus of i (1-indexed)
        let idealScore = Double(n * (n + 1)) / 2.0

        var score = 0.0
        var consecutiveBonus = 0.0
        var queryIndex = lowerQuery.startIndex

        for char in lowerCandidate {
            if char == lowerQuery[queryIndex] {
                // Matched: increment consecutive bonus and add to score
                consecutiveBonus += 1.0
                score += consecutiveBonus
                queryIndex = lowerQuery.index(after: queryIndex)
                // All query characters consumed — this is a match
                if queryIndex == lowerQuery.endIndex {
                    return score / idealScore
                }
            } else {
                // No match: decay consecutive bonus (min 0)
                consecutiveBonus = max(0.0, consecutiveBonus - 0.5)
            }
        }

        // Not all query characters were found — not a subsequence
        return nil
    }
}
