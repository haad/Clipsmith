import SwiftUI

struct DocsetSettingsSection: View {
    @State private var managerService = DocsetManagerService()
    @State private var searchFilter: String = ""
    @State private var showDownloadedOnly: Bool = false
    @State private var selectedDocset: DocsetInfo?

    private var filteredDocsets: [DocsetInfo] {
        var list = managerService.docsets
        if showDownloadedOnly {
            list = list.filter { $0.isDownloaded }
        }
        if !searchFilter.isEmpty {
            list = list.filter { $0.displayName.localizedCaseInsensitiveContains(searchFilter) }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documentation (DevDocs)")
                .font(.headline)

            Text("Download offline documentation for quick lookup via hotkey. Powered by devdocs.io.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = managerService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                TextField("Filter docs...", text: $searchFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Toggle("Downloaded only", isOn: $showDownloadedOnly)

                Spacer()

                Button {
                    Task { await managerService.fetchCatalog() }
                } label: {
                    if managerService.isFetchingCatalog {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .disabled(managerService.isFetchingCatalog)
            }

            HSplitView {
                // Doc list
                List(filteredDocsets, selection: $selectedDocset) { docset in
                    DocsetRow(
                        docset: docset,
                        isDownloading: managerService.downloadingDocsetID == docset.id,
                        progress: managerService.downloadProgress,
                        onDownload: {
                            Task { await managerService.downloadDocset(docset) }
                        },
                        onDelete: {
                            managerService.deleteDocset(docset)
                        },
                        onToggle: {
                            managerService.toggleEnabled(docset)
                        }
                    )
                    .tag(docset)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minWidth: 280)

                // Detail panel
                DocsetDetailView(
                    docset: selectedDocset,
                    isDownloading: selectedDocset.map { managerService.downloadingDocsetID == $0.id } ?? false,
                    progress: managerService.downloadProgress,
                    onDownload: {
                        if let d = selectedDocset {
                            Task { await managerService.downloadDocset(d) }
                        }
                    },
                    onDelete: {
                        if let d = selectedDocset {
                            managerService.deleteDocset(d)
                        }
                    }
                )
                .frame(minWidth: 220, maxWidth: 300)
            }
        }
        .padding()
        .frame(minWidth: 550, minHeight: 350)
        .onAppear {
            managerService.loadMetadata()
        }
    }
}

// MARK: - Detail View

struct DocsetDetailView: View {
    let docset: DocsetInfo?
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if let docset {
            VStack(alignment: .leading, spacing: 12) {
                Text(docset.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("Slug:")
                            .foregroundStyle(.secondary)
                        Text(docset.id)
                            .textSelection(.enabled)
                    }
                    if let release = docset.release, !release.isEmpty {
                        GridRow {
                            Text("Release:")
                                .foregroundStyle(.secondary)
                            Text(release)
                        }
                    }
                    GridRow {
                        Text("Size:")
                            .foregroundStyle(.secondary)
                        Text(docset.sizeLabel)
                    }
                    GridRow {
                        Text("Status:")
                            .foregroundStyle(.secondary)
                        if docset.isDownloaded {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Not installed")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let type = docset.docType {
                        GridRow {
                            Text("Type:")
                                .foregroundStyle(.secondary)
                            Text(type)
                        }
                    }
                }
                .font(.callout)

                if let home = docset.homeURL, let url = URL(string: home) {
                    Link(destination: url) {
                        Label("Homepage", systemImage: "globe")
                    }
                    .font(.callout)
                }
                if let code = docset.codeURL, let url = URL(string: code) {
                    Link(destination: url) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .font(.callout)
                }

                Spacer()

                // Search hint
                Text("Search filter: **\(docset.id.split(separator: "~").first.map(String.init) ?? docset.id):query**")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Action button
                if isDownloading {
                    ProgressView(value: progress)
                        .controlSize(.regular)
                } else if docset.isDownloaded {
                    Button("Delete", role: .destructive) { onDelete() }
                        .controlSize(.regular)
                } else {
                    Button("Download") { onDownload() }
                        .controlSize(.regular)
                }
            }
            .padding()
        } else {
            ContentUnavailableView {
                Label("Select a Doc", systemImage: "doc.text")
            } description: {
                Text("Choose a documentation set to see details")
            }
        }
    }
}

// MARK: - Row View

struct DocsetRow: View {
    let docset: DocsetInfo
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { docset.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .disabled(!docset.isDownloaded)

            VStack(alignment: .leading) {
                Text(docset.displayName)
                    .font(.body)
                HStack(spacing: 4) {
                    if docset.isDownloaded {
                        Text("Installed")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text(docset.sizeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let release = docset.release, !release.isEmpty {
                        Text("v\(release)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .controlSize(.small)
            } else if docset.isDownloaded {
                Button("Delete", role: .destructive) { onDelete() }
                    .controlSize(.small)
            } else {
                Button("Download") { onDownload() }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
