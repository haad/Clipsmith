import SwiftUI
import WebKit

struct DocBezelView: View {
    @Bindable var viewModel: DocBezelViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search documentation...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                if !viewModel.navigationLabel.isEmpty {
                    Text(viewModel.navigationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            if viewModel.filteredResults.isEmpty {
                if viewModel.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("Documentation Lookup", systemImage: "book")
                    } description: {
                        Text("Type to search your downloaded docsets")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.isSearching {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No documentation found for \"\(viewModel.searchText)\"")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HSplitView {
                    // Results list
                    List(selection: Binding(
                        get: { viewModel.selectedIndex },
                        set: { viewModel.selectedIndex = $0 }
                    )) {
                        ForEach(Array(viewModel.filteredResults.enumerated()), id: \.element.id) { index, result in
                            DocResultRow(result: result, isSelected: index == viewModel.selectedIndex)
                                .tag(index)
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 200, maxWidth: 240)

                    // WKWebView preview
                    DocWebView(result: viewModel.currentResult)
                        .frame(minWidth: 260)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Result Row

struct DocResultRow: View {
    let result: DocSearchResult
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.entry.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(result.entry.type)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(typeColor(result.entry.type).opacity(0.15))
                    .foregroundStyle(typeColor(result.entry.type))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(result.docsetName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "class", "struct", "enum": return .blue
        case "function", "method": return .purple
        case "property", "constant": return .green
        case "protocol", "interface": return .orange
        default: return .secondary
        }
    }
}

// MARK: - WKWebView wrapper

struct DocWebView: NSViewRepresentable {
    let result: DocSearchResult?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let result, let htmlURL = result.htmlURL else {
            webView.loadHTMLString(
                "<html><body style='font-family:system-ui;color:#888;text-align:center;padding-top:40px;'><p>Select a result to view documentation</p></body></html>",
                baseURL: nil
            )
            return
        }
        // allowingReadAccessTo: parent Documents directory so CSS/JS resolve
        let docsDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: docsDir)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Intercepts link clicks — opens external links in default browser (Pitfall 6).
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if url.isFileURL {
                    return .allow  // Internal doc navigation
                } else {
                    await MainActor.run { NSWorkspace.shared.open(url) }
                    return .cancel
                }
            }
            return .allow
        }
    }
}
