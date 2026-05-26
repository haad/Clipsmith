import XCTest
@testable import Clipsmith

// MARK: - MockURLProtocolForCurrency

/// A URLProtocol mock scoped to `CurrencyServiceTests` to avoid a duplicate-symbol collision
/// with the `MockURLProtocol` already declared in `GistServiceTests.swift`.
final class MockURLProtocolForCurrency: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocolForCurrency.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - CurrencyServiceTests

@MainActor
final class CurrencyServiceTests: XCTestCase {

    private var mockSession: URLSession!
    private var service: CurrencyService!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocolForCurrency.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocolForCurrency.self]
        mockSession = URLSession(configuration: config)
        service = CurrencyService(session: mockSession)
        // Remove any leftover downloaded rates file from previous test runs
        try? FileManager.default.removeItem(at: service.downloadedRatesURL)
    }

    override func tearDown() async throws {
        MockURLProtocolForCurrency.requestHandler = nil
        try? FileManager.default.removeItem(at: service.downloadedRatesURL)
        service = nil
        mockSession = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        XCTAssertFalse(service.isRefreshing)
        XCTAssertNil(service.lastError)
        XCTAssertNil(service.lastUpdated)
        // Convert returns nil because rates are empty
        XCTAssertNil(service.convert(amount: 10, from: "USD", to: "EUR"))
    }

    // MARK: - D-09: Bundled JSON Load

    func testLoadRatesUsesBundledJSONWhenNoDownloadedFile() {
        service.loadRates()
        // After loading the bundled JSON, major currencies should be available
        XCTAssertNotNil(service.convert(amount: 10, from: "USD", to: "EUR"),
                        "convert should return non-nil after loading bundled rates")
        XCTAssertNotNil(service.convert(amount: 1, from: "USD", to: "GBP"))
        XCTAssertNotNil(service.convert(amount: 1, from: "USD", to: "JPY"))
    }

    // MARK: - Convert: empty rates

    func testConvertReturnsNilWhenRatesEmpty() {
        // No loadRates() call — rates map is empty
        XCTAssertNil(service.convert(amount: 10, from: "USD", to: "EUR"))
    }

    // MARK: - Convert: case insensitivity

    func testConvertIsCaseInsensitive() {
        service.loadRates()
        let upper = service.convert(amount: 10, from: "USD", to: "EUR")
        let lower = service.convert(amount: 10, from: "usd", to: "eur")
        XCTAssertNotNil(upper)
        XCTAssertNotNil(lower)
        XCTAssertEqual(upper!, lower!, accuracy: 0.0001)
    }

    // MARK: - Convert: unknown currency

    func testConvertReturnsNilForUnknownCurrency() {
        service.loadRates()
        XCTAssertNil(service.convert(amount: 10, from: "USD", to: "XYZ"))
    }

    // MARK: - D-10: refreshRates — success path

    func testRefreshRatesSuccessUpdatesStateAndDisk() async throws {
        // Prepare a minimal valid ExchangeRateResponse JSON
        let responseJSON = """
        {
          "result": "success",
          "base_code": "USD",
          "time_last_update_unix": 1748217600,
          "rates": { "USD": 1.0, "EUR": 0.92, "GBP": 0.78 }
        }
        """.data(using: .utf8)!

        MockURLProtocolForCurrency.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseJSON)
        }

        await service.refreshRates()

        XCTAssertNil(service.lastError, "lastError should be nil on success")
        XCTAssertNotNil(service.lastUpdated, "lastUpdated should be set on success")
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.downloadedRatesURL.path),
                      "downloaded rates file should exist after successful refresh")
        XCTAssertNotNil(service.convert(amount: 10, from: "USD", to: "EUR"),
                        "convert should work after successful refresh")
    }

    // MARK: - D-10: refreshRates — network failure

    func testRefreshRatesNetworkFailureKeepsBundledRates() async {
        // Load bundled rates first so we have a baseline
        service.loadRates()
        let beforeRefresh = service.convert(amount: 10, from: "USD", to: "EUR")
        XCTAssertNotNil(beforeRefresh, "Should have rates from bundled JSON before network failure")

        // Configure mock to throw a network error
        MockURLProtocolForCurrency.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await service.refreshRates()

        XCTAssertNotNil(service.lastError, "lastError should be set after network failure")
        // Rates should still be available (bundled fallback preserved)
        let afterRefresh = service.convert(amount: 10, from: "USD", to: "EUR")
        XCTAssertNotNil(afterRefresh, "Bundled rates should be preserved after network failure")
        XCTAssertEqual(beforeRefresh!, afterRefresh!, accuracy: 0.0001,
                       "Rate value should be unchanged after failed refresh")
        // Downloaded file should NOT have been created
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.downloadedRatesURL.path),
                       "No file should be written on network failure")
    }

    // MARK: - D-10: refreshRates — malformed JSON

    func testRefreshRatesMalformedJSONSetsErrorWithoutCorruptingDisk() async {
        MockURLProtocolForCurrency.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }

        await service.refreshRates()

        XCTAssertNotNil(service.lastError, "lastError should be set on malformed JSON")
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.downloadedRatesURL.path),
                       "No file should be written when JSON decode fails (T-12-03 ordering)")
    }

    // MARK: - D-11: isCurrencyQuery

    func testIsCurrencyQueryReturnsTrueForThreeLetterCodes() {
        XCTAssertTrue(CurrencyService.isCurrencyQuery(from: "USD", to: "EUR"))
        XCTAssertTrue(CurrencyService.isCurrencyQuery(from: "usd", to: "eur"))
        XCTAssertTrue(CurrencyService.isCurrencyQuery(from: "GBP", to: "JPY"))
    }

    func testIsCurrencyQueryReturnsFalseForUnits() {
        XCTAssertFalse(CurrencyService.isCurrencyQuery(from: "km", to: "miles"))
        XCTAssertFalse(CurrencyService.isCurrencyQuery(from: "kg", to: "lb"))
        XCTAssertFalse(CurrencyService.isCurrencyQuery(from: "celsius", to: "fahrenheit"))
        XCTAssertFalse(CurrencyService.isCurrencyQuery(from: "in", to: "cm"))
    }
}
