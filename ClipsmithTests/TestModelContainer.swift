import SwiftData
@testable import Clipsmith

func makeTestContainer() throws -> ModelContainer {
    let schema = Schema(ClipsmithSchemaV2.models)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
