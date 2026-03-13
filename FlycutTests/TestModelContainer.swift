import SwiftData
@testable import FlycutSwift

func makeTestContainer() throws -> ModelContainer {
    let schema = Schema(FlycutSchemaV2.models)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
