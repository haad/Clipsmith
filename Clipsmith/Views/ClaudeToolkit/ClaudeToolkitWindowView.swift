import SwiftUI
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "ClaudeToolkitWindowView"
)

// MARK: - ViewModel

@Observable @MainActor
final class ClaudeToolkitViewModel {

    var items: [ClaudeToolkitItem] = []
    var selectedItem: ClaudeToolkitItem?
    var searchQuery: String = ""
    var selectedKind: ClaudeToolkitItem.Kind?   // nil = show all
    var isLoading: Bool = false
    var errorMessage: String?
    var installedIDs: Set<String> = []

    private let service = ClaudeToolkitService()

    // MARK: - Derived

    var filteredItems: [ClaudeToolkitItem] {
        items.filter { item in
            let kindMatch = selectedKind == nil || item.kind == selectedKind
            let query = searchQuery.trimmingCharacters(in: .whitespaces)
            let textMatch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.description.localizedCaseInsensitiveContains(query)
                || item.category.localizedCaseInsensitiveContains(query)
            return kindMatch && textMatch
        }
    }

    var installedCount: Int { installedIDs.count }

    func isInstalled(_ item: ClaudeToolkitItem) -> Bool {
        installedIDs.contains(item.id)
    }

    // MARK: - Actions

    func reload(from toolkitPath: String) {
        isLoading = true
        errorMessage = nil

        let expanded = (toolkitPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        guard FileManager.default.fileExists(atPath: url.path) else {
            items = []
            isLoading = false
            errorMessage = """
            Toolkit not found at:
            \(toolkitPath)

            Install with:
            git clone https://github.com/rohitg00/awesome-claude-code-toolkit \\
              ~/.claude/plugins/claude-code-toolkit
            """
            return
        }

        items = service.scan(at: url)
        refreshInstalledState()
        isLoading = false

        if items.isEmpty {
            errorMessage = "No commands, agents, or skills found at:\n\(toolkitPath)"
        } else if selectedItem == nil || !filteredItems.contains(selectedItem!) {
            selectedItem = filteredItems.first
        }
    }

    func refreshInstalledState() {
        installedIDs = Set(items.filter { service.isInstalled($0) }.map(\.id))
    }

    func install(_ item: ClaudeToolkitItem) {
        do {
            try service.install(item)
            installedIDs.insert(item.id)
        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
            logger.error("Install failed for \(item.name, privacy: .public): \(error, privacy: .public)")
        }
    }

    func uninstall(_ item: ClaudeToolkitItem) {
        do {
            try service.uninstall(item)
            installedIDs.remove(item.id)
        } catch {
            errorMessage = "Uninstall failed: \(error.localizedDescription)"
            logger.error("Uninstall failed for \(item.name, privacy: .public): \(error, privacy: .public)")
        }
    }
}

// MARK: - Window View

/// Browser for installing Claude Code skills, commands, and agents from the
/// awesome-claude-code-toolkit into `~/.claude/`.
///
/// Opens as a `WindowGroup(id: "claude-toolkit")` from the menu bar.
struct ClaudeToolkitWindowView: View {

    @AppStorage(AppSettingsKeys.toolkitPath)
    private var toolkitPath: String = AppSettingsKeys.toolkitPathDefault

    @State private var viewModel = ClaudeToolkitViewModel()
    @State private var showingPathSheet = false

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 240, idealWidth: 290, maxWidth: 380)
            detailPane
                .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                kindPicker
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingPathSheet = true
                } label: {
                    Image(systemName: "folder")
                }
                .help("Configure toolkit path")
            }
        }
        .navigationTitle("Claude Toolkit")
        .onAppear {
            viewModel.reload(from: toolkitPath)
        }
        .onChange(of: toolkitPath) { _, new in
            viewModel.reload(from: new)
        }
        .sheet(isPresented: $showingPathSheet) {
            ToolkitPathSheet(toolkitPath: $toolkitPath, isPresented: $showingPathSheet)
        }
    }

    // MARK: - Kind Picker

    private var kindPicker: some View {
        Picker("Kind", selection: $viewModel.selectedKind) {
            Text("All").tag(Optional<ClaudeToolkitItem.Kind>.none)
            ForEach(ClaudeToolkitItem.Kind.allCases, id: \.self) { kind in
                Text(kind.label).tag(Optional(kind))
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        .onChange(of: viewModel.selectedKind) { _, _ in
            viewModel.selectedItem = viewModel.filteredItems.first
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List body
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    errorPlaceholder(error)
                } else {
                    List(viewModel.filteredItems, selection: $viewModel.selectedItem) { item in
                        ClaudeToolkitRowView(
                            item: item,
                            isInstalled: viewModel.isInstalled(item)
                        )
                        .tag(item)
                    }
                    .listStyle(.sidebar)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(viewModel.filteredItems.count) items")
                Spacer()
                Text("\(viewModel.installedCount) installed")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Configure Path...") {
                showingPathSheet = true
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let item = viewModel.selectedItem {
            ClaudeToolkitDetailView(
                item: item,
                isInstalled: viewModel.isInstalled(item),
                onInstall: { viewModel.install(item) },
                onUninstall: { viewModel.uninstall(item) }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)
                Text("Select an item to preview")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Row View

struct ClaudeToolkitRowView: View {
    let item: ClaudeToolkitItem
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kindIcon)
                .foregroundStyle(kindColor)
                .frame(width: 20)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                Text(item.category.replacingOccurrences(of: "-", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var kindIcon: String {
        switch item.kind {
        case .command: return "terminal"
        case .agent:   return "person.fill.badge.plus"
        case .skill:   return "brain"
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .command: return .blue
        case .agent:   return .purple
        case .skill:   return .orange
        }
    }
}

// MARK: - Detail View

struct ClaudeToolkitDetailView: View {
    let item: ClaudeToolkitItem
    let isInstalled: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void

    private var kindColor: Color {
        switch item.kind {
        case .command: return .blue
        case .agent:   return .purple
        case .skill:   return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.title2.bold())

                    HStack(spacing: 6) {
                        Text(item.kind.rawValue.capitalized)
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(kindColor.opacity(0.12))
                            .foregroundStyle(kindColor)
                            .clipShape(Capsule())

                        Text(item.category.replacingOccurrences(of: "-", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    installButton

                    if isInstalled {
                        Text("Installed to ~/.claude/\(item.kind.installSubdirectory)/")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content preview
            ScrollView {
                Text(item.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalled {
            Button(role: .destructive, action: onUninstall) {
                Label("Uninstall", systemImage: "trash")
                    .frame(minWidth: 100)
            }
        } else {
            Button(action: onInstall) {
                Label("Install", systemImage: "arrow.down.circle.fill")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Path Configuration Sheet

private struct ToolkitPathSheet: View {
    @Binding var toolkitPath: String
    @Binding var isPresented: Bool

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Toolkit Path")
                .font(.headline)

            Text("Path to your local clone of the awesome-claude-code-toolkit repository.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Path", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = "Select toolkit directory"
                    if panel.runModal() == .OK, let url = panel.url {
                        draft = url.path
                    }
                }

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    toolkitPath = draft
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            draft = toolkitPath
        }
    }
}
