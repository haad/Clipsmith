import SwiftUI

struct DocsetSettingsSection: View {
    @State private var managerService = DocsetManagerService()
    @State private var searchFilter: String = ""
    @State private var showDownloadedOnly: Bool = false

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

            List {
                ForEach(filteredDocsets) { docset in
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
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            managerService.loadMetadata()
        }
    }
}

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
                if docset.isDownloaded {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(docset.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 80)
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
