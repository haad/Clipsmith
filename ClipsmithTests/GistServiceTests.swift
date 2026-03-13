import XCTest
import SwiftData
import AppKit
@testable import Clipsmith

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
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

// MARK: - Helpers

private func makeTestTokenStore(token: String?) -> TokenStore {
    let service = "com.generalarcade.flycut.github-pat.gist-service-test"
    let account = "github-personal-access-token-gist-service-test"
    let store = TokenStore(service: service, account: account)
    store.deleteToken()
    if let token {
        store.saveToken(token)
    }
    return store
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeGistSuccessResponse(id: String = "abc123", htmlURL: String = "https://gist.github.com/user/abc123") -> (HTTPURLResponse, Data) {
    let json = """
    {"id":"\(id)","html_url":"\(htmlURL)","description":"test","public":false}
    """.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/gists")!,
        statusCode: 201,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json)
}

// MARK: - GistServiceTests

@MainActor
final class GistServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var mockSession: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        mockSession = makeMockSession()
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() async throws {
        makeTestTokenStore(token: nil).deleteToken()
        MockURLProtocol.requestHandler = nil
        container = nil
        mockSession = nil
        try await super.tearDown()
    }

    // MARK: - testCreateGistSuccessReturnsResponse

    func testCreateGistSuccessReturnsResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            makeGistSuccessResponse(id: "aa5a315d", htmlURL: "https://gist.github.com/user/aa5a315d")
        }
        let tokenStore = makeTestTokenStore(token: "ghp_validtoken")
        let service = GistService(modelContext: container.mainContext, tokenStore: tokenStore, session: mockSession)

        let response = try await service.createGist(
            filename: "snippet.swift",
            content: "let x = 42",
            description: "Test snippet",
            isPublic: false
        )

        XCTAssertEqual(response.id, "aa5a315d")
        XCTAssertEqual(response.htmlURL, "https://gist.github.com/user/aa5a315d")
    }

    // MARK: - testCreateGistWithNoTokenThrowsNoToken

    func testCreateGistWithNoTokenThrowsNoToken() async throws {
        let tokenStore = makeTestTokenStore(token: nil)
        let service = GistService(modelContext: container.mainContext, tokenStore: tokenStore, session: mockSession)

        do {
            _ = try await service.createGist(
                filename: "snippet.swift",
                content: "let x = 42",
                description: "Test",
                isPublic: false
            )
            XCTFail("Expected GistError.noToken to be thrown")
        } catch GistError.noToken {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - testCreateGistHTTPErrorThrowsHTTPError

    func testCreateGistHTTPErrorThrowsHTTPError() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.github.com/gists")!,
                statusCode: 422,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let tokenStore = makeTestTokenStore(token: "ghp_validtoken")
        let service = GistService(modelContext: container.mainContext, tokenStore: tokenStore, session: mockSession)

        do {
            _ = try await service.createGist(
                filename: "snippet.swift",
                content: "let x = 42",
                description: "Test",
                isPublic: false
            )
            XCTFail("Expected GistError.httpError(422) to be thrown")
        } catch GistError.httpError(let code) {
            XCTAssertEqual(code, 422)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - testCreateGistPersistsGistRecord

    func testCreateGistPersistsGistRecord() async throws {
        MockURLProtocol.requestHandler = { _ in
            makeGistSuccessResponse(id: "persist123", htmlURL: "https://gist.github.com/user/persist123")
        }
        let tokenStore = makeTestTokenStore(token: "ghp_validtoken")
        let service = GistService(modelContext: container.mainContext, tokenStore: tokenStore, session: mockSession)

        _ = try await service.createGist(
            filename: "snippet.swift",
            content: "let x = 42",
            description: "Persist test",
            isPublic: false
        )

        // Verify GistRecord was persisted
        let records = try container.mainContext.fetch(FetchDescriptor<ClipsmithSchemaV1.GistRecord>())
        XCTAssertEqual(records.count, 1, "One GistRecord should be persisted after createGist")
        XCTAssertEqual(records[0].gistID, "persist123")
        XCTAssertEqual(records[0].gistURL, "https://gist.github.com/user/persist123")
        XCTAssertEqual(records[0].filename, "snippet.swift")
    }

    // MARK: - testDeleteGistCallsAPIAndRemovesRecord

    func testDeleteGistCallsAPIAndRemovesRecord() async throws {
        // Insert a GistRecord to be deleted
        let context = container.mainContext
        let record = ClipsmithSchemaV1.GistRecord(
            gistID: "delete123",
            gistURL: "https://gist.github.com/user/delete123",
            filename: "test.swift"
        )
        context.insert(record)
        try context.save()
        let recordID = record.persistentModelID

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("delete123") == true, "DELETE request should target the gist ID")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let tokenStore = makeTestTokenStore(token: "ghp_validtoken")
        let service = GistService(modelContext: context, tokenStore: tokenStore, session: mockSession)

        try await service.deleteGist(id: recordID)

        // Verify record was removed
        let remaining = try context.fetch(FetchDescriptor<ClipsmithSchemaV1.GistRecord>())
        XCTAssertEqual(remaining.count, 0, "GistRecord should be removed after deleteGist")
    }

    // MARK: - testLanguageExtension

    func testLanguageExtension() {
        XCTAssertEqual(GistService.languageExtension(for: "swift"), "swift")
        XCTAssertEqual(GistService.languageExtension(for: "python"), "py")
        XCTAssertEqual(GistService.languageExtension(for: "javascript"), "js")
        XCTAssertEqual(GistService.languageExtension(for: "bash"), "sh")
        XCTAssertEqual(GistService.languageExtension(for: "markdown"), "md")
        XCTAssertEqual(GistService.languageExtension(for: nil), "txt")
        XCTAssertEqual(GistService.languageExtension(for: "unknown"), "txt")
        // Case-insensitive
        XCTAssertEqual(GistService.languageExtension(for: "Swift"), "swift")
    }
}
