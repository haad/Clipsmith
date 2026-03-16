import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "PromptSyncService"
)

// MARK: - PromptSyncError

enum PromptSyncError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)
    case networkError(Error)
    case decodingError(Error)
    case bundleNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The prompt library URL is invalid. Please enter a valid HTTPS URL in Settings."
        case .httpError(let code):
            return "Server returned HTTP \(code). Check the URL and try again."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .decodingError(let underlying):
            return "Failed to parse prompts: \(underlying.localizedDescription)"
        case .bundleNotFound:
            return "Bundled prompts.json not found in app bundle."
        }
    }
}

// MARK: - PromptSyncService

/// Loads and syncs prompt library data from bundled JSON and remote HTTP sources.
///
/// Responsibilities:
/// - `loadBundledPrompts(store:)` — offline first-launch path: reads prompts.json from Bundle.main
/// - `syncFromURL(_:store:)` — manual sync path: fetches prompts.json via URLSession HTTP GET
///
/// Marked @MainActor @Observable so SwiftUI settings views can observe `isSyncing` and
/// `lastError` without cross-actor hops. The async methods yield the main thread during
/// network I/O so the UI remains responsive.
@MainActor @Observable
final class PromptSyncService {

    // MARK: - Properties

    private let session: URLSession

    /// True while a sync is in progress. Drives the "Sync Now" button disabled state.
    var isSyncing: Bool = false

    /// Localized error message from the most recent failed sync. Nil on success.
    var lastError: String? = nil

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Bundled Prompts (First Launch)

    /// Loads prompts from the bundled prompts.json resource.
    ///
    /// Called on first launch when the local store is empty to give users immediate
    /// access to default prompts without a network request (PMPT-01).
    ///
    /// - Parameter store: The PromptLibraryStore actor to upsert prompts into.
    /// - Throws: `PromptSyncError.bundleNotFound` if prompts.json is missing from the bundle.
    ///           `PromptSyncError.decodingError` if the JSON structure is invalid.
    func loadBundledPrompts(store: PromptLibraryStore) async throws {
        guard let url = Bundle.main.url(forResource: "prompts", withExtension: "json") else {
            logger.error("loadBundledPrompts: prompts.json not found in bundle")
            throw PromptSyncError.bundleNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PromptSyncError.decodingError(error)
        }

        let catalog: PromptCatalog
        do {
            catalog = try JSONDecoder().decode(PromptCatalog.self, from: data)
        } catch {
            throw PromptSyncError.decodingError(error)
        }

        for prompt in catalog.prompts {
            try await store.upsert(remote: prompt)
        }

        logger.info("loadBundledPrompts: loaded \(catalog.prompts.count, privacy: .public) prompts from bundle")
    }

    // MARK: - Remote Sync

    /// Fetches prompts from a remote JSON URL and upserts them into the store.
    ///
    /// Flow:
    /// 1. Set isSyncing=true, clear lastError
    /// 2. Validate URL — throw `.invalidURL` if malformed
    /// 3. HTTP GET via URLSession — wrap errors in `.networkError`
    /// 4. Verify HTTP 200 — throw `.httpError(statusCode)` otherwise
    /// 5. Decode response as PromptCatalog — wrap errors in `.decodingError`
    /// 6. Upsert each prompt via `store.upsert(remote:)`
    /// 7. Persist last-sync timestamp to UserDefaults
    /// 8. Set isSyncing=false
    ///
    /// On error: records `lastError`, sets isSyncing=false, rethrows.
    ///
    /// - Parameter urlString: The remote prompts.json URL from Settings.
    /// - Parameter store: The PromptLibraryStore actor to upsert prompts into.
    func syncFromURL(_ urlString: String, store: PromptLibraryStore) async throws {
        isSyncing = true
        lastError = nil

        do {
            guard let url = URL(string: urlString), url.scheme != nil else {
                throw PromptSyncError.invalidURL
            }

            let request = URLRequest(url: url)

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw PromptSyncError.networkError(error)
            }

            if let http = response as? HTTPURLResponse {
                guard http.statusCode == 200 else {
                    throw PromptSyncError.httpError(http.statusCode)
                }
            }

            let catalog: PromptCatalog
            do {
                catalog = try JSONDecoder().decode(PromptCatalog.self, from: data)
            } catch {
                throw PromptSyncError.decodingError(error)
            }

            for prompt in catalog.prompts {
                try await store.upsert(remote: prompt)
            }

            // Persist last-sync timestamp as ISO 8601 string
            let iso = ISO8601DateFormatter().string(from: .now)
            UserDefaults.standard.set(iso, forKey: AppSettingsKeys.promptLibraryLastSync)

            isSyncing = false
            logger.info("syncFromURL: synced \(catalog.prompts.count, privacy: .public) prompts from \(urlString, privacy: .public)")

        } catch {
            lastError = error.localizedDescription
            isSyncing = false
            throw error
        }
    }
}
