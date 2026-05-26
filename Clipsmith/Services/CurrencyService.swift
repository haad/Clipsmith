import Foundation
import OSLog
import Observation

// MARK: - Logger

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "CurrencyService"
)

// MARK: - ExchangeRateResponse

/// Strongly-typed Codable struct for the open.er-api.com v6 JSON response.
///
/// The typed decode (rates is `[String: Double]`, not `[String: Any]`) mitigates
/// T-12-03: a malicious or malformed response cannot inject arbitrary objects into
/// the in-memory rate table or the on-disk cache.
///
/// CodingKeys map snake_case JSON keys to camelCase Swift properties.
struct ExchangeRateResponse: Codable, Sendable {
    let result: String
    let baseCode: String
    let timeLastUpdateUnix: TimeInterval
    let rates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case result
        case baseCode        = "base_code"
        case timeLastUpdateUnix = "time_last_update_unix"
        case rates
    }
}

// MARK: - CurrencyService

/// Manages loading, refreshing, and querying USD-based currency exchange rates.
///
/// **Load priority (D-09, D-10):**
/// 1. Downloaded file at `~/Library/Application Support/Clipsmith/exchange-rates.json`
/// 2. Bundled fallback at `exchange-rates-bundled.json` in `Bundle.main`
///
/// **Refresh (D-10):** `refreshRates()` fetches from `open.er-api.com/v6/latest/USD`.
/// The JSON is decoded BEFORE the file is written to disk so a malformed or malicious
/// response never overwrites the cached file (T-12-03 defence-in-depth). On any error
/// the in-memory `rates` are left unchanged and `lastError` is set.
///
/// Marked `@MainActor @Observable` so SwiftUI settings views can bind to `isRefreshing`,
/// `lastError`, and `lastUpdated` without cross-actor hops.
@MainActor @Observable
final class CurrencyService {

    // MARK: - Observable State

    /// True while a network refresh is in progress.
    var isRefreshing: Bool = false

    /// Localized error message from the most recent failed operation. Nil on success.
    var lastError: String? = nil

    /// Date of the last successful rate load from the downloaded file, or nil when
    /// only bundled rates are in use.
    var lastUpdated: Date? = nil

    // MARK: - Private

    private let session: URLSession
    private var rates: [String: Double] = [:]

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Paths

    /// URL for the user-downloaded exchange rates cache in Application Support.
    ///
    /// Declared `internal` (not private) so tests can inspect the path and clean up
    /// after themselves.
    var downloadedRatesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Clipsmith/exchange-rates.json")
    }

    // MARK: - Load

    /// Synchronously loads exchange rates from the best available source.
    ///
    /// Priority:
    /// 1. Downloaded file (`downloadedRatesURL`) — uses its modification date as
    ///    `lastUpdated` so the Settings UI can display a meaningful timestamp.
    /// 2. Bundled fallback (`exchange-rates-bundled.json` in `Bundle.main`).
    /// 3. If both sources fail: logs a warning, `rates` stays empty.
    ///
    /// Called from `AppDelegate.applicationDidFinishLaunching` on the main thread.
    func loadRates() {
        // Attempt 1: user-downloaded file
        if let data = try? Data(contentsOf: downloadedRatesURL),
           let response = try? JSONDecoder().decode(ExchangeRateResponse.self, from: data) {
            rates = response.rates
            lastUpdated = (try? FileManager.default.attributesOfItem(
                atPath: downloadedRatesURL.path))?[.modificationDate] as? Date
            logger.info("loadRates: loaded \(response.rates.count, privacy: .public) rates from downloaded file")
            return
        }

        // Attempt 2: bundled fallback
        if let url = Bundle.main.url(forResource: "exchange-rates-bundled", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let response = try? JSONDecoder().decode(ExchangeRateResponse.self, from: data) {
            rates = response.rates
            // Do NOT set lastUpdated from the bundled file — it has no meaningful timestamp
            logger.info("loadRates: loaded \(response.rates.count, privacy: .public) rates from bundle fallback")
            return
        }

        logger.warning("loadRates: both downloaded file and bundled fallback failed; rates are empty")
    }

    // MARK: - Refresh

    /// Fetches the latest exchange rates from `open.er-api.com/v6/latest/USD` and
    /// persists the response to disk.
    ///
    /// **T-12-03 ordering:** `JSONDecoder().decode(_:from:)` is called on the raw
    /// `data` BEFORE `data.write(to:)`. A response that fails to decode as
    /// `ExchangeRateResponse` is discarded — the cached file is never overwritten.
    ///
    /// On any error: `lastError` is set, `rates` is preserved, no file is written.
    func refreshRates() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            lastError = "Invalid API URL"
            return
        }

        do {
            let (data, _) = try await session.data(from: url)

            // DECODE BEFORE WRITE — T-12-03 mitigation
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)

            // Ensure parent directory exists
            try FileManager.default.createDirectory(
                at: downloadedRatesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Atomic write: only succeeds if the data is already proven valid JSON above
            try data.write(to: downloadedRatesURL, options: .atomic)

            rates = response.rates
            lastUpdated = Date()
            logger.info("refreshRates: updated \(response.rates.count, privacy: .public) rates")

        } catch {
            lastError = error.localizedDescription
            logger.error("refreshRates: failed — \(error.localizedDescription, privacy: .public)")
            // rates unchanged; no file written
        }
    }

    // MARK: - Convert

    /// Converts `amount` from one currency to another using the loaded rates.
    ///
    /// All rates are USD-based. Conversion formula: `amount / fromRate * toRate`.
    ///
    /// - Parameters:
    ///   - amount: The quantity to convert.
    ///   - from:   ISO 4217 currency code (case-insensitive).
    ///   - to:     ISO 4217 currency code (case-insensitive).
    /// - Returns: Converted amount, or `nil` when rates are empty or either code is unknown.
    func convert(amount: Double, from: String, to: String) -> Double? {
        guard !rates.isEmpty else { return nil }
        let fromUpper = from.uppercased()
        let toUpper   = to.uppercased()
        guard let fromRate = rates[fromUpper],
              let toRate   = rates[toUpper],
              fromRate != 0 else { return nil }
        return amount / fromRate * toRate
    }

    // MARK: - Currency Query Detection

    /// Returns `true` iff both `from` and `to` are exactly 3 ASCII letters — the shape
    /// of an ISO 4217 currency code.
    ///
    /// Used by `UnitConversionService` (Pitfall 5 disambiguator) and
    /// `CommandPaletteService` (query router). Declared `static` so callers do not need
    /// a live `CurrencyService` instance just to classify a query string.
    static func isCurrencyQuery(from: String, to: String) -> Bool {
        let a = from.uppercased()
        let b = to.uppercased()
        return a.count == 3 && b.count == 3
            && a.allSatisfy({ $0.isLetter })
            && b.allSatisfy({ $0.isLetter })
    }
}
