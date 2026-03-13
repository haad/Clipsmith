import SwiftUI
import SwiftData

/// Settings tab for the Prompt Library feature.
///
/// Three sections:
/// - **Sync:** JSON URL field, Sync Now button, last-synced status, inline error display
/// - **Template Variables:** User-defined key=value pairs substituted in prompt content on paste
/// - **Security:** Clipboard variable warning for privacy-conscious users
struct PromptLibrarySettingsSection: View {

    // MARK: - Sync State

    @AppStorage(AppSettingsKeys.promptLibraryURL)
    private var promptLibraryURL: String = "https://haad.github.io/Clipsmith/prompts/prompts.json"

    @AppStorage(AppSettingsKeys.promptLibraryLastSync)
    private var lastSyncISO: String = ""

    @State private var syncService = PromptSyncService()

    // MARK: - Template Variables State

    @AppStorage(AppSettingsKeys.promptLibraryVariables)
    private var variablesJSON: String = ""

    /// Transient in-memory list of (key, value) pairs. Loaded from and saved to `variablesJSON`.
    @State private var variables: [(key: String, value: String)] = []

    // MARK: - SwiftData

    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        Form {
            syncSection
            templateVariablesSection
            securitySection
        }
        .onAppear {
            loadVariables()
        }
    }

    // MARK: - Sections

    private var syncSection: some View {
        Section("Sync") {
            TextField("JSON URL", text: $promptLibraryURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(syncService.isSyncing ? "Syncing..." : "Sync Now") {
                    Task {
                        let store = PromptLibraryStore(modelContainer: modelContext.container)
                        do {
                            try await syncService.syncFromURL(promptLibraryURL, store: store)
                        } catch {
                            // Error is already captured in syncService.lastError
                        }
                    }
                }
                .disabled(syncService.isSyncing || promptLibraryURL.isEmpty)
            }

            if let errorText = syncService.lastError {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !lastSyncISO.isEmpty, let lastSyncDate = ISO8601DateFormatter().date(from: lastSyncISO) {
                Text("Last synced \(lastSyncDate.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var templateVariablesSection: some View {
        Section("Template Variables") {
            Text("Define custom variables for use in prompts. Variables like {{name}} in prompt content will be replaced with the value you set here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(variables.indices, id: \.self) { index in
                HStack {
                    TextField("Key", text: Binding(
                        get: { variables[index].key },
                        set: { variables[index].key = $0; saveVariables() }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("Value", text: Binding(
                        get: { variables[index].value },
                        set: { variables[index].value = $0; saveVariables() }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        variables.remove(at: index)
                        saveVariables()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                variables.append((key: "", value: ""))
            } label: {
                Label("Add Variable", systemImage: "plus.circle")
            }

            Text("{{clipboard}} is built-in and always contains the current clipboard content.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var securitySection: some View {
        Section("Security") {
            Text("Prompts containing {{clipboard}} will include whatever is on your clipboard when pasted, including passwords or sensitive data.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Variables Persistence

    /// Loads user-defined template variables from the JSON string stored in UserDefaults.
    private func loadVariables() {
        guard !variablesJSON.isEmpty,
              let data = variablesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return
        }
        variables = decoded.compactMap { dict in
            guard let key = dict["key"], let value = dict["value"] else { return nil }
            return (key: key, value: value)
        }
    }

    /// Serialises current variables to JSON and persists via @AppStorage.
    private func saveVariables() {
        let dicts = variables.map { ["key": $0.key, "value": $0.value] }
        if let data = try? JSONEncoder().encode(dicts),
           let json = String(data: data, encoding: .utf8) {
            variablesJSON = json
        }
    }
}
