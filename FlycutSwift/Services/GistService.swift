import SwiftData
import AppKit
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "GistService"
)

// MARK: - GistError

enum GistError: Error, LocalizedError {
    case noToken
    case httpError(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No GitHub Personal Access Token configured. Please add your PAT in Settings."
        case .httpError(let code):
            return "GitHub API returned HTTP \(code). Check your token permissions."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - GistService

@MainActor @Observable
final class GistService {

    // MARK: - Nested Types

    struct CreateGistRequest: Encodable {
        let description: String
        let `public`: Bool
        let files: [String: FileContent]

        struct FileContent: Encodable {
            let content: String
        }
    }

    struct GistResponse: Decodable {
        let id: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case id
            case htmlURL = "html_url"
        }
    }

    // MARK: - Language Extension Map

    nonisolated static let languageExtensions: [String: String] = [
        "swift": "swift", "python": "py", "javascript": "js",
        "typescript": "ts", "ruby": "rb", "go": "go",
        "rust": "rs", "kotlin": "kt", "java": "java",
        "bash": "sh", "c": "c", "cpp": "cpp",
        "sql": "sql", "html": "html", "css": "css",
        "json": "json", "yaml": "yaml", "xml": "xml",
        "markdown": "md"
    ]

    // MARK: - Properties

    private let tokenStore: TokenStore
    private let session: URLSession
    private let modelContext: ModelContext

    // MARK: - Init

    init(
        modelContext: ModelContext,
        tokenStore: TokenStore = TokenStore(),
        session: URLSession = .shared
    ) {
        self.modelContext = modelContext
        self.tokenStore = tokenStore
        self.session = session
    }

    // MARK: - Public API

    /// Creates a GitHub Gist from the given content.
    ///
    /// Flow:
    /// 1. Load token from TokenStore — throw `GistError.noToken` if absent
    /// 2. POST to https://api.github.com/gists
    /// 3. Verify HTTP 201 — throw `GistError.httpError(statusCode)` otherwise
    /// 4. Copy gist URL to clipboard
    /// 5. Persist GistRecord in SwiftData
    /// 6. Return GistResponse
    func createGist(
        filename: String,
        content: String,
        description: String,
        isPublic: Bool
    ) async throws -> GistResponse {
        guard let token = tokenStore.loadToken() else {
            throw GistError.noToken
        }

        let body = CreateGistRequest(
            description: description,
            public: isPublic,
            files: [filename: .init(content: content)]
        )

        let request = try buildCreateRequest(body: body, token: token)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GistError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GistError.httpError(0)
        }
        guard http.statusCode == 201 else {
            throw GistError.httpError(http.statusCode)
        }

        let gistResponse = try JSONDecoder().decode(GistResponse.self, from: data)

        // Copy URL to clipboard (GIST-04)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(gistResponse.htmlURL, forType: .string)
        logger.info("Gist created: \(gistResponse.htmlURL, privacy: .public)")

        // Persist GistRecord in SwiftData
        let record = FlycutSchemaV1.GistRecord(
            gistID: gistResponse.id,
            gistURL: gistResponse.htmlURL,
            filename: filename
        )
        modelContext.insert(record)
        try modelContext.save()

        return gistResponse
    }

    /// Deletes a GitHub Gist by its GistRecord PersistentIdentifier.
    ///
    /// Flow:
    /// 1. Fetch GistRecord from modelContext
    /// 2. DELETE https://api.github.com/gists/{gistID} with Bearer token
    /// 3. On HTTP 204, delete local GistRecord
    func deleteGist(id: PersistentIdentifier) async throws {
        guard let record = modelContext.model(for: id) as? FlycutSchemaV1.GistRecord else { return }
        guard let token = tokenStore.loadToken() else {
            throw GistError.noToken
        }

        let request = buildDeleteRequest(gistID: record.gistID, token: token)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw GistError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GistError.httpError(0)
        }
        guard http.statusCode == 204 else {
            throw GistError.httpError(http.statusCode)
        }

        modelContext.delete(record)
        try modelContext.save()
        logger.info("Gist deleted: \(record.gistID, privacy: .public)")
    }

    /// Returns the file extension for a given language name.
    ///
    /// Falls back to "txt" for unrecognised languages.
    nonisolated static func languageExtension(for language: String?) -> String {
        guard let language else { return "txt" }
        return languageExtensions[language.lowercased()] ?? "txt"
    }

    // MARK: - Private Helpers

    private func buildCreateRequest(body: CreateGistRequest, token: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/gists")!)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func buildDeleteRequest(gistID: String, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/gists/\(gistID)")!)
        request.httpMethod = "DELETE"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }
}
