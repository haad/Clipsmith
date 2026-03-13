import XCTest
@testable import FlycutSwift

/// Unit tests for FuzzyMatcher character-subsequence fuzzy scoring algorithm.
///
/// Tests validate the canonical use case from CONTEXT.md: typing "jsonpar" finds
/// "JSON.parse(...)" by matching non-contiguous characters in sequence.
final class FuzzyMatcherTests: XCTestCase {

    // MARK: - Non-subsequence (returns nil)

    func testNonSubsequenceQueryReturnsNil() {
        // "xyz" is not a subsequence of "hello"
        XCTAssertNil(FuzzyMatcher.score("hello", query: "xyz"))
    }

    func testQueryLongerThanCandidateReturnsNil() {
        // "abcdef" cannot be a subsequence of "abc"
        XCTAssertNil(FuzzyMatcher.score("abc", query: "abcdef"))
    }

    // MARK: - Valid subsequence (returns non-nil score)

    func testCanonicalJsonparMatchesJsonParse() {
        // The canonical CONTEXT.md requirement: "jsonpar" matches "JSON.parse(...)"
        let score = FuzzyMatcher.score("JSON.parse(...)", query: "jsonpar")
        XCTAssertNotNil(score, "\"jsonpar\" must match \"JSON.parse(...)\"")
    }

    func testSingleCharQueryMatchesCandidate() {
        // Single-character query "a" matches "apple"
        XCTAssertNotNil(FuzzyMatcher.score("apple", query: "a"))
    }

    // MARK: - Empty query

    func testEmptyQueryReturnsPerfectScore() {
        // Empty query returns 1.0 for any candidate
        XCTAssertEqual(FuzzyMatcher.score("anything", query: ""), 1.0)
    }

    func testEmptyQueryOnEmptyCandidateReturnsPerfectScore() {
        XCTAssertEqual(FuzzyMatcher.score("", query: ""), 1.0)
    }

    // MARK: - Perfect match

    func testPerfectConsecutiveMatchReturnsPerfectScore() {
        // "hello" matches "hello" with score 1.0
        let score = FuzzyMatcher.score("hello", query: "hello")
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 1.0, accuracy: 0.001, "Exact match should score 1.0")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveMatchWorks() {
        // "HELLO" matches query "hello"
        XCTAssertNotNil(FuzzyMatcher.score("HELLO", query: "hello"))
    }

    // MARK: - Score ranking

    func testCloserMatchScoresHigherThanFragmentedMatch() {
        // "JSON.parse" should score higher than "justSomeOddNaming_parse_results" for query "jsonpar"
        let closerScore = FuzzyMatcher.score("JSON.parse(data)", query: "jsonpar")
        let fragmentedScore = FuzzyMatcher.score("justSomeOddNaming_parse_results", query: "jsonpar")
        XCTAssertNotNil(closerScore, "JSON.parse(data) must match jsonpar")
        XCTAssertNotNil(fragmentedScore, "justSomeOddNaming_parse_results must match jsonpar")
        XCTAssertGreaterThan(closerScore!, fragmentedScore!,
            "Closer match should score higher than fragmented match")
    }
}
