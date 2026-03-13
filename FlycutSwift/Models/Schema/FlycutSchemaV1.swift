import SwiftData
import Foundation

enum FlycutSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Clipping.self, Snippet.self, GistRecord.self]
    }

    @Model
    final class Clipping {
        #Index<Clipping>([\.timestamp])

        var content: String = ""
        var type: String = "public.utf8-plain-text"
        var sourceAppName: String? = nil
        var sourceAppBundleURL: String? = nil
        var timestamp: Date = Date.now
        var isFavorite: Bool = false
        var displayOrder: Int = 0

        init(
            content: String,
            type: String = "public.utf8-plain-text",
            timestamp: Date = .now,
            sourceAppName: String? = nil,
            sourceAppBundleURL: String? = nil,
            isFavorite: Bool = false,
            displayOrder: Int = 0
        ) {
            self.content = content
            self.type = type
            self.timestamp = timestamp
            self.sourceAppName = sourceAppName
            self.sourceAppBundleURL = sourceAppBundleURL
            self.isFavorite = isFavorite
            self.displayOrder = displayOrder
        }
    }

    @Model
    final class Snippet {
        var name: String = ""
        var content: String = ""
        var language: String? = nil
        var category: String? = nil  // Retained for backward compatibility; use tags for multi-tag support
        var tags: [String] = []
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now

        init(
            name: String,
            content: String,
            language: String? = nil,
            category: String? = nil,
            tags: [String] = []
        ) {
            self.name = name
            self.content = content
            self.language = language
            self.category = category
            self.tags = tags
        }
    }

    @Model
    final class GistRecord {
        var gistID: String = ""
        var gistURL: String = ""
        var filename: String = ""
        var createdAt: Date = Date.now

        init(gistID: String, gistURL: String, filename: String) {
            self.gistID = gistID
            self.gistURL = gistURL
            self.filename = filename
        }
    }
}
