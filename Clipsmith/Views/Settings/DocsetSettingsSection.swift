import SwiftUI

// MARK: - Grouping Model

private struct DocsetGroup: Identifiable {
    let id: String          // base slug (e.g. "angular")
    let name: String        // group display name (e.g. "Angular")
    let latest: DocsetInfo  // unversioned entry = latest
    let versions: [DocsetInfo] // all versions, newest first

    var isMultiVersion: Bool { versions.count > 1 }
    var olderVersions: [DocsetInfo] { versions.filter { $0.id != latest.id } }
    var downloadedCount: Int { versions.filter(\.isDownloaded).count }
}

// MARK: - Settings Section

struct DocsetSettingsSection: View {
    @State private var managerService = DocsetManagerService()
    @State private var searchFilter: String = ""
    @State private var showDownloadedOnly: Bool = false
    @State private var selectedDocset: DocsetInfo?
    @State private var expandedGroups: Set<String> = []

    /// Derive a clean group display name from member displayNames via longest common prefix.
    private static func groupName(from names: [String]) -> String {
        guard let first = names.first else { return "" }
        if names.count == 1 { return first }

        var prefix = first
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        // Trim trailing partial version numbers (e.g. "Python 3.1" → "Python")
        if let lastSpace = trimmed.lastIndex(of: " ") {
            let afterSpace = trimmed[trimmed.index(after: lastSpace)...]
            if afterSpace.contains(where: \.isNumber) {
                return String(trimmed[..<lastSpace])
            }
        }
        return trimmed.isEmpty ? first : trimmed
    }

    private var groupedDocsets: [DocsetGroup] {
        // Group all docsets by base slug
        var groupMap: [String: [DocsetInfo]] = [:]
        for docset in managerService.docsets {
            let baseSlug = String(docset.id.split(separator: "~").first ?? Substring(docset.id))
            groupMap[baseSlug, default: []].append(docset)
        }

        var groups = groupMap.map { baseSlug, members -> DocsetGroup in
            // Sort: unversioned (latest) first, then by displayName descending
            let sorted = members.sorted { a, b in
                if !a.id.contains("~") { return true }
                if !b.id.contains("~") { return false }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedDescending
            }
            let latest = sorted[0]
            let name = Self.groupName(from: sorted.map(\.displayName))
            return DocsetGroup(id: baseSlug, name: name, latest: latest, versions: sorted)
        }

        // Apply filters at the group level
        if showDownloadedOnly {
            groups = groups.filter { $0.versions.contains(where: \.isDownloaded) }
        }
        if !searchFilter.isEmpty {
            groups = groups.filter {
                $0.name.localizedCaseInsensitiveContains(searchFilter) ||
                $0.versions.contains { $0.displayName.localizedCaseInsensitiveContains(searchFilter) }
            }
        }

        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                List(selection: $selectedDocset) {
                    ForEach(groupedDocsets) { group in
                        if group.isMultiVersion {
                            // Grouped entry — header represents latest version
                            DocsetGroupRow(
                                group: group,
                                isExpanded: expandedGroups.contains(group.id),
                                isDownloading: managerService.downloadingDocsetID == group.latest.id,
                                progress: managerService.downloadProgress,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedGroups.contains(group.id) {
                                            expandedGroups.remove(group.id)
                                        } else {
                                            expandedGroups.insert(group.id)
                                        }
                                    }
                                },
                                onDownload: {
                                    Task { await managerService.downloadDocset(group.latest) }
                                },
                                onDelete: {
                                    managerService.deleteDocset(group.latest)
                                },
                                onToggle: {
                                    managerService.toggleEnabled(group.latest)
                                }
                            )
                            .tag(group.latest)

                            // Older versions (expanded)
                            if expandedGroups.contains(group.id) {
                                ForEach(group.olderVersions) { docset in
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
                                    .padding(.leading, 24)
                                }
                            }
                        } else {
                            // Single-version entry — show as flat row
                            DocsetRow(
                                docset: group.latest,
                                isDownloading: managerService.downloadingDocsetID == group.latest.id,
                                progress: managerService.downloadProgress,
                                onDownload: {
                                    Task { await managerService.downloadDocset(group.latest) }
                                },
                                onDelete: {
                                    managerService.deleteDocset(group.latest)
                                },
                                onToggle: {
                                    managerService.toggleEnabled(group.latest)
                                }
                            )
                            .tag(group.latest)
                        }
                    }
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

// MARK: - Group Row (multi-version header)

private struct DocsetGroupRow: View {
    let group: DocsetGroup
    let isExpanded: Bool
    let isDownloading: Bool
    let progress: Double
    let onToggleExpand: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { group.latest.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .disabled(!group.latest.isDownloaded)

            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .frame(width: 10)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(group.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text("\(group.versions.count) versions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if group.downloadedCount > 0 {
                        Text("\(group.downloadedCount) installed")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let release = group.latest.release, !release.isEmpty {
                        Text("latest v\(release)")
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
            } else if group.latest.isDownloaded {
                Button("Delete", role: .destructive) { onDelete() }
                    .controlSize(.small)
            } else {
                Button("Get Latest") { onDownload() }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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

// MARK: - Row View (single version)

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
