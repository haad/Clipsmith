import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "DocsetManagerService"
)

/// Metadata for a single docset (downloaded or available for download).
struct DocsetInfo: Codable, Identifiable, Sendable {
    var id: String           // e.g. "Swift", "Python_3"
    var displayName: String  // e.g. "Swift", "Python 3"
    var localPath: URL?      // nil if not yet downloaded
    var version: String?
    var isEnabled: Bool

    /// Whether this docset has been downloaded and is available for search.
    var isDownloaded: Bool { localPath != nil }
}

/// Known CDN mirror hostnames for Kapeli docset downloads.
enum DocsetCDNMirror: String, CaseIterable {
    case sanfrancisco = "sanfrancisco"
    case london = "london"
    case newyork = "newyork"
    case tokyo = "tokyo"
    case frankfurt = "frankfurt"

    var baseURL: String { "https://\(rawValue).kapeli.com/feeds" }
}

/// Manages docset downloads, extraction, and metadata persistence.
///
/// Stores metadata as JSON in Application Support/Clipsmith/docsets.json.
/// No SwiftData models — simple Codable persistence avoids migration complexity.
@Observable @MainActor
final class DocsetManagerService {

    /// All known docsets (downloaded + available).
    var docsets: [DocsetInfo] = []

    /// Currently downloading docset ID, if any.
    var downloadingDocsetID: String?

    /// Download progress (0.0 to 1.0) for the current download.
    var downloadProgress: Double = 0.0

    /// Last error message, if any.
    var lastError: String?

    // MARK: - File paths

    /// Directory where extracted docsets live.
    private var docsetsDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Clipsmith/Docsets", isDirectory: true)
    }

    /// Path to the metadata JSON file.
    private var metadataPath: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Clipsmith/docsets.json")
    }

    // MARK: - Bundled manifest

    /// Curated list of popular docsets available for download.
    static let availableDocsets: [DocsetInfo] = [
        DocsetInfo(id: "Swift", displayName: "Swift", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Python_3", displayName: "Python 3", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "JavaScript", displayName: "JavaScript", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "TypeScript", displayName: "TypeScript", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "React", displayName: "React", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Go", displayName: "Go", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Rust", displayName: "Rust", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Ruby", displayName: "Ruby", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "PHP", displayName: "PHP", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "CSS", displayName: "CSS", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "HTML", displayName: "HTML", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Java_SE17", displayName: "Java SE 17", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "C", displayName: "C", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "C++", displayName: "C++", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "NodeJS", displayName: "Node.js", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Django", displayName: "Django", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Laravel", displayName: "Laravel", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Vue", displayName: "Vue.js", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Angular", displayName: "Angular", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Bash", displayName: "Bash", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "PostgreSQL", displayName: "PostgreSQL", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "MySQL", displayName: "MySQL", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Docker", displayName: "Docker", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Kubernetes", displayName: "Kubernetes", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Git", displayName: "Git", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Ruby_on_Rails_7", displayName: "Ruby on Rails 7", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Dart", displayName: "Dart", localPath: nil, version: nil, isEnabled: true),
        DocsetInfo(id: "Kotlin", displayName: "Kotlin", localPath: nil, version: nil, isEnabled: true),
    ]

    // MARK: - Persistence

    /// Load metadata from disk, merging with the bundled manifest.
    func loadMetadata() {
        var saved: [DocsetInfo] = []
        if FileManager.default.fileExists(atPath: metadataPath.path) {
            if let data = try? Data(contentsOf: metadataPath),
               let decoded = try? JSONDecoder().decode([DocsetInfo].self, from: data) {
                saved = decoded
            }
        }

        // Merge: saved state takes precedence for known IDs; add new manifest entries
        var byID: [String: DocsetInfo] = [:]
        for d in Self.availableDocsets { byID[d.id] = d }
        for d in saved { byID[d.id] = d }   // saved overwrites manifest defaults

        docsets = Array(byID.values).sorted { $0.displayName < $1.displayName }
    }

    /// Save current metadata to disk.
    func saveMetadata() {
        do {
            let dir = metadataPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(docsets)
            try data.write(to: metadataPath, options: .atomic)
        } catch {
            logger.error("Failed to save docset metadata: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Download + Extract

    /// Download and extract a docset from Kapeli CDN.
    func downloadDocset(_ docset: DocsetInfo) async {
        downloadingDocsetID = docset.id
        downloadProgress = 0.0
        lastError = nil

        do {
            // Ensure destination directory exists
            try FileManager.default.createDirectory(at: docsetsDirectory, withIntermediateDirectories: true)

            // Try each CDN mirror in order
            var downloadedURL: URL?
            for mirror in DocsetCDNMirror.allCases {
                let tgzURL = URL(string: "\(mirror.baseURL)/\(docset.id).tgz")!
                do {
                    let (localURL, _) = try await URLSession.shared.download(from: tgzURL)
                    downloadedURL = localURL
                    break
                } catch {
                    logger.warning("Mirror \(mirror.rawValue, privacy: .public) failed for \(docset.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }

            guard let localURL = downloadedURL else {
                throw DocsetError.downloadFailed("All CDN mirrors failed for \(docset.id)")
            }
            defer { try? FileManager.default.removeItem(at: localURL) }

            // Extract with /usr/bin/tar
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", localURL.path, "-C", docsetsDirectory.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw DocsetError.extractionFailed("tar exited with status \(process.terminationStatus)")
            }

            // Find the extracted .docset bundle
            let extractedPath = docsetsDirectory.appendingPathComponent("\(docset.id).docset")
            guard FileManager.default.fileExists(atPath: extractedPath.path) else {
                // Some docsets extract with different names — scan for any .docset
                let contents = try FileManager.default.contentsOfDirectory(at: docsetsDirectory, includingPropertiesForKeys: nil)
                if let found = contents.first(where: { $0.pathExtension == "docset" && $0.lastPathComponent.contains(docset.id) }) {
                    updateDocsetPath(id: docset.id, path: found)
                } else {
                    throw DocsetError.extractionFailed("No .docset bundle found after extraction")
                }
                downloadingDocsetID = nil
                return
            }

            updateDocsetPath(id: docset.id, path: extractedPath)
            logger.info("Downloaded and extracted docset: \(docset.id, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            logger.error("Docset download failed: \(error.localizedDescription, privacy: .public)")
        }

        downloadingDocsetID = nil
    }

    /// Delete a downloaded docset from disk and clear its local path.
    func deleteDocset(_ docset: DocsetInfo) {
        if let localPath = docset.localPath {
            try? FileManager.default.removeItem(at: localPath)
        }
        if let idx = docsets.firstIndex(where: { $0.id == docset.id }) {
            docsets[idx].localPath = nil
            docsets[idx].version = nil
        }
        saveMetadata()
    }

    /// Toggle enabled state for a docset.
    func toggleEnabled(_ docset: DocsetInfo) {
        if let idx = docsets.firstIndex(where: { $0.id == docset.id }) {
            docsets[idx].isEnabled.toggle()
            saveMetadata()
        }
    }

    /// Returns only downloaded and enabled docsets.
    var enabledDocsets: [DocsetInfo] {
        docsets.filter { $0.isDownloaded && $0.isEnabled }
    }

    // MARK: - Private

    private func updateDocsetPath(id: String, path: URL) {
        if let idx = docsets.firstIndex(where: { $0.id == id }) {
            docsets[idx].localPath = path
        }
        saveMetadata()
    }
}

/// Errors specific to docset operations.
enum DocsetError: LocalizedError {
    case downloadFailed(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        }
    }
}
