import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "DocsetManagerService"
)

/// Metadata for a single DevDocs documentation set.
struct DocsetInfo: Codable, Identifiable, Sendable {
    var id: String           // DevDocs slug, e.g. "javascript", "python~3.12"
    var displayName: String  // e.g. "JavaScript", "Python 3.12"
    var release: String?     // Version string from DevDocs
    var dbSize: Int          // Size of db.json in bytes
    var isEnabled: Bool
    var isDownloaded: Bool

    /// Path to the downloaded index.json, or nil if not downloaded.
    var indexPath: URL? {
        guard isDownloaded else { return nil }
        return Self.docDirectory(for: id).appendingPathComponent("index.json")
    }

    /// Path to the downloaded db.json, or nil if not downloaded.
    var dbPath: URL? {
        guard isDownloaded else { return nil }
        return Self.docDirectory(for: id).appendingPathComponent("db.json")
    }

    /// Directory where this doc's files are stored.
    static func docDirectory(for slug: String) -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Clipsmith/DevDocs/\(slug)", isDirectory: true)
    }

    /// Human-readable size string.
    var sizeLabel: String {
        let mb = Double(dbSize) / 1_048_576.0
        if mb >= 1.0 { return String(format: "%.1f MB", mb) }
        let kb = Double(dbSize) / 1024.0
        return String(format: "%.0f KB", kb)
    }
}

/// Manages DevDocs documentation downloads and metadata.
///
/// Downloads `index.json` (search entries) and `db.json` (HTML content) per doc
/// from devdocs.io. Stores metadata as JSON in Application Support/Clipsmith/.
@Observable @MainActor
final class DocsetManagerService {

    /// All known docs (downloaded + available from catalog).
    var docsets: [DocsetInfo] = []

    /// Currently downloading doc slug, if any.
    var downloadingDocsetID: String?

    /// Download progress (0.0 to 1.0).
    var downloadProgress: Double = 0.0

    /// Last error message, if any.
    var lastError: String?

    /// Whether the catalog is being fetched.
    var isFetchingCatalog: Bool = false

    // MARK: - File paths

    private var metadataPath: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Clipsmith/devdocs-meta.json")
    }

    // MARK: - Catalog

    /// Fetch the full DevDocs catalog from devdocs.io/docs.json.
    func fetchCatalog() async {
        isFetchingCatalog = true
        defer { isFetchingCatalog = false }

        do {
            let url = URL(string: "https://devdocs.io/docs.json")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DocsetError.downloadFailed("Failed to fetch DevDocs catalog")
            }
            let catalog = try JSONDecoder().decode([DevDocsCatalogEntry].self, from: data)

            // Merge catalog with saved state
            var byID: [String: DocsetInfo] = [:]
            for entry in catalog {
                byID[entry.slug] = DocsetInfo(
                    id: entry.slug,
                    displayName: entry.name + (entry.version.isEmpty ? "" : " \(entry.version)"),
                    release: entry.release,
                    dbSize: entry.db_size,
                    isEnabled: true,
                    isDownloaded: false
                )
            }
            // Overlay saved state (preserves isDownloaded, isEnabled)
            for saved in docsets where byID[saved.id] != nil {
                byID[saved.id]?.isEnabled = saved.isEnabled
                byID[saved.id]?.isDownloaded = saved.isDownloaded
            }

            docsets = Array(byID.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            saveMetadata()
            logger.info("DevDocs catalog loaded: \(catalog.count) docs available")
        } catch {
            logger.error("Failed to fetch DevDocs catalog: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Persistence

    /// Load saved metadata from disk.
    func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataPath.path) else {
            // First launch — trigger catalog fetch
            Task { await fetchCatalog() }
            return
        }
        if let data = try? Data(contentsOf: metadataPath),
           let decoded = try? JSONDecoder().decode([DocsetInfo].self, from: data) {
            docsets = decoded.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    /// Save current metadata to disk.
    func saveMetadata() {
        do {
            let dir = metadataPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(docsets)
            try data.write(to: metadataPath, options: .atomic)
        } catch {
            logger.error("Failed to save metadata: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Download

    /// Download a doc's index.json and db.json from DevDocs.
    func downloadDocset(_ docset: DocsetInfo) async {
        downloadingDocsetID = docset.id
        downloadProgress = 0.0
        lastError = nil

        do {
            let docDir = DocsetInfo.docDirectory(for: docset.id)
            try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)

            // 1. Download index.json
            let indexURL = URL(string: "https://devdocs.io/docs/\(docset.id)/index.json")!
            let (indexData, indexResp) = try await URLSession.shared.data(from: indexURL)
            guard let http = indexResp as? HTTPURLResponse, http.statusCode == 200 else {
                throw DocsetError.downloadFailed("index.json returned non-200 for \(docset.id)")
            }
            try indexData.write(to: docDir.appendingPathComponent("index.json"), options: .atomic)
            downloadProgress = 0.3

            // 2. Download db.json (can be large — use download task for disk-based transfer)
            let dbURL = URL(string: "https://documents.devdocs.io/\(docset.id)/db.json")!
            let (dbTempURL, dbResp) = try await URLSession.shared.download(from: dbURL)
            guard let dbHTTP = dbResp as? HTTPURLResponse, dbHTTP.statusCode == 200 else {
                throw DocsetError.downloadFailed("db.json returned non-200 for \(docset.id)")
            }
            let destDB = docDir.appendingPathComponent("db.json")
            if FileManager.default.fileExists(atPath: destDB.path) {
                try FileManager.default.removeItem(at: destDB)
            }
            try FileManager.default.moveItem(at: dbTempURL, to: destDB)
            downloadProgress = 1.0

            // Mark as downloaded
            if let idx = docsets.firstIndex(where: { $0.id == docset.id }) {
                docsets[idx].isDownloaded = true
            }
            saveMetadata()
            logger.info("Downloaded DevDocs: \(docset.id, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            logger.error("Download failed for \(docset.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        downloadingDocsetID = nil
    }

    /// Delete a downloaded doc from disk.
    func deleteDocset(_ docset: DocsetInfo) {
        let docDir = DocsetInfo.docDirectory(for: docset.id)
        try? FileManager.default.removeItem(at: docDir)
        if let idx = docsets.firstIndex(where: { $0.id == docset.id }) {
            docsets[idx].isDownloaded = false
        }
        saveMetadata()
    }

    /// Toggle enabled state for a doc.
    func toggleEnabled(_ docset: DocsetInfo) {
        if let idx = docsets.firstIndex(where: { $0.id == docset.id }) {
            docsets[idx].isEnabled.toggle()
            saveMetadata()
        }
    }

    /// Returns only downloaded and enabled docs.
    var enabledDocsets: [DocsetInfo] {
        docsets.filter { $0.isDownloaded && $0.isEnabled }
    }
}

// MARK: - DevDocs catalog JSON structure

private struct DevDocsCatalogEntry: Codable {
    let name: String
    let slug: String
    let version: String
    let release: String
    let db_size: Int
    // Extra fields from docs.json that we don't need but must accept
    let type: String?
    let mtime: Int?
    let attribution: String?
    let alias: String?

    private enum CodingKeys: String, CodingKey {
        case name, slug, version, release, db_size, type, mtime, attribution, alias
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        slug = try c.decode(String.self, forKey: .slug)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        release = try c.decodeIfPresent(String.self, forKey: .release) ?? ""
        db_size = try c.decodeIfPresent(Int.self, forKey: .db_size) ?? 0
        type = try c.decodeIfPresent(String.self, forKey: .type)
        mtime = try c.decodeIfPresent(Int.self, forKey: .mtime)
        attribution = try c.decodeIfPresent(String.self, forKey: .attribution)
        alias = try c.decodeIfPresent(String.self, forKey: .alias)
    }
}

/// Errors specific to doc operations.
enum DocsetError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        }
    }
}
