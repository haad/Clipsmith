import SwiftUI
import SwiftData

/// Displays the history of GitHub Gists created from Flycut.
///
/// Each row shows the filename, creation date, an "Open" button, and a
/// context menu with Open in Browser, Copy URL, and Delete actions.
/// Delete removes the Gist from GitHub (via GistService) and the local record.
struct GistHistoryView: View {

    @Query(sort: \FlycutSchemaV1.GistRecord.createdAt, order: .reverse)
    private var gistHistory: [FlycutSchemaV1.GistRecord]

    @Environment(GistService.self) private var gistService

    var body: some View {
        if gistHistory.isEmpty {
            ContentUnavailableView(
                "No Gists",
                systemImage: "link.badge.plus",
                description: Text("Share a snippet or clipping as a Gist to see it here.")
            )
        } else {
            List(gistHistory) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.filename)
                            .font(.headline)
                            .lineLimit(1)
                        Text(record.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") {
                        if let url = URL(string: record.gistURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
                .contextMenu {
                    Button("Open in Browser") {
                        if let url = URL(string: record.gistURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.gistURL, forType: .string)
                    }
                    Divider()
                    Button("Delete Gist", role: .destructive) {
                        Task {
                            try? await gistService.deleteGist(id: record.persistentModelID)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
