import Foundation

// MARK: - Codable types

/// Top-level export envelope.
struct ClippingExport: Codable {
    let version: Int
    let exportedAt: Date
    let clippings: [ClippingRecord]
}

/// A single exported clipping record.
struct ClippingRecord: Codable {
    let content: String
    let sourceAppName: String?
    let sourceAppBundleURL: String?
    let timestamp: Date
}

// MARK: - ClipboardExportService

/// Pure-logic clipboard history export/import service.
///
/// Implemented as a no-case enum namespace — all functions are static async, taking
/// `ClipboardStore` as a parameter. No actor or class wrapper needed.
enum ClipboardExportService {

    // MARK: - Export

    /// Exports all clippings from the store to JSON Data.
    ///
    /// Encoding uses ISO 8601 dates and pretty-printed output.
    ///
    /// - Parameter store: The clipboard store to export from.
    /// - Returns: JSON-encoded `ClippingExport` data.
    static func exportHistory(from store: ClipboardStore) async throws -> Data {
        let ids = try await store.fetchAll()

        var records: [ClippingRecord] = []
        for id in ids {
            guard let content = await store.content(for: id) else { continue }
            let sourceAppName = await store.sourceAppName(for: id)
            let sourceAppBundleURL = await store.sourceAppBundleURL(for: id)
            let timestamp = await store.timestamp(for: id) ?? Date()
            records.append(ClippingRecord(
                content: content,
                sourceAppName: sourceAppName,
                sourceAppBundleURL: sourceAppBundleURL,
                timestamp: timestamp
            ))
        }

        let envelope = ClippingExport(
            version: 1,
            exportedAt: Date(),
            clippings: records
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    // MARK: - Import

    /// Imports clippings from JSON data into the store.
    ///
    /// - Parameters:
    ///   - store: The clipboard store to import into.
    ///   - data: JSON data previously produced by `exportHistory(from:)`.
    ///   - merge: When `false`, clears all existing clippings before importing.
    ///     When `true`, skips records whose content already exists.
    /// - Returns: The number of records actually imported (duplicates are skipped).
    static func importHistory(
        into store: ClipboardStore,
        from data: Data,
        merge: Bool
    ) async throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(ClippingExport.self, from: data)

        if !merge {
            try await store.clearAll()
        }

        // Build O(1) lookup of existing content to skip duplicates
        var existingContents: Set<String> = []
        if merge {
            let existingIDs = try await store.fetchAll()
            for id in existingIDs {
                if let c = await store.content(for: id) {
                    existingContents.insert(c)
                }
            }
        }

        var imported = 0
        for record in envelope.clippings {
            // Skip duplicates when merging
            if merge && existingContents.contains(record.content) {
                continue
            }

            try await store.insert(
                content: record.content,
                sourceAppName: record.sourceAppName,
                sourceAppBundleURL: record.sourceAppBundleURL,
                timestamp: record.timestamp,
                rememberNum: Int.max
            )
            imported += 1
        }
        return imported
    }
}
