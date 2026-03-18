import SwiftUI
import WebKit

struct DocBezelView: View {
    @Bindable var viewModel: DocBezelViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle bar
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .frame(height: 14)
            .background(.ultraThinMaterial)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)

                // Doc filter pill
                if let filter = viewModel.activeDocFilter, !viewModel.activeDocFilterNames.isEmpty {
                    HStack(spacing: 3) {
                        Text(viewModel.activeDocFilterNames.first ?? filter)
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .onTapGesture {
                                // Remove the filter prefix from search text
                                if let colonIdx = viewModel.searchText.firstIndex(of: ":") {
                                    viewModel.searchText = String(viewModel.searchText[viewModel.searchText.index(after: colonIdx)...])
                                        .trimmingCharacters(in: .whitespaces)
                                }
                            }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                TextField(
                    viewModel.activeDocFilter != nil ? "Search in \(viewModel.activeDocFilterNames.first ?? "")..." : "Search docs... (prefix: go:fmt)",
                    text: $viewModel.searchText
                )
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
                        Text("Type to search your downloaded docs")
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
                    DocWebView(html: viewModel.currentHTML)
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
    let html: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let html else {
            webView.loadHTMLString(
                "<html><body style='font-family:system-ui;color:#888;text-align:center;padding-top:40px;'><p>Select a result to view documentation</p></body></html>",
                baseURL: nil
            )
            return
        }
        // Wrap DevDocs HTML fragment in a styled page with proper dark/light mode
        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="dark light">
        <style>
            :root {
                color-scheme: dark light;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
                font-size: 14px;
                line-height: 1.7;
                color: #d4d4d4;
                background: #1e1e1e;
                padding: 20px 24px;
                margin: 0;
                -webkit-font-smoothing: antialiased;
            }
            h1 { font-size: 1.6em; font-weight: 600; margin: 0 0 0.8em 0; padding-bottom: 0.3em; border-bottom: 1px solid #333; }
            h2 { font-size: 1.3em; font-weight: 600; margin: 1.4em 0 0.5em 0; }
            h3 { font-size: 1.1em; font-weight: 600; margin: 1.2em 0 0.4em 0; }
            h4 { font-size: 1em; font-weight: 600; margin: 1em 0 0.3em 0; }
            p { margin: 0.6em 0; }
            a { color: #6cb6ff; text-decoration: none; }
            a:hover { text-decoration: underline; }
            code, pre {
                font-family: ui-monospace, Menlo, "Cascadia Code", monospace;
                font-size: 12.5px;
            }
            code {
                background: #2d2d2d;
                padding: 2px 6px;
                border-radius: 4px;
                color: #e8c97a;
            }
            pre {
                background: #161616;
                padding: 14px 16px;
                border-radius: 8px;
                border: 1px solid #2d2d2d;
                overflow-x: auto;
                line-height: 1.5;
            }
            pre code { background: none; padding: 0; color: #d4d4d4; border-radius: 0; }
            table { border-collapse: collapse; width: 100%; margin: 0.8em 0; }
            th, td { border: 1px solid #333; padding: 8px 12px; text-align: left; }
            th { background: #252525; font-weight: 600; }
            tr:nth-child(even) { background: #1a1a1a; }
            blockquote { border-left: 3px solid #444; margin: 0.8em 0; padding: 0.4em 1em; color: #999; }
            ul, ol { padding-left: 1.5em; }
            li { margin: 0.3em 0; }
            hr { border: none; border-top: 1px solid #333; margin: 1.5em 0; }
            dt { font-weight: 600; margin-top: 0.8em; }
            dd { margin-left: 1.5em; margin-bottom: 0.5em; }
            img { max-width: 100%; }

            @media (prefers-color-scheme: light) {
                body { color: #24292f; background: #ffffff; }
                h1 { border-bottom-color: #d8dee4; }
                a { color: #0969da; }
                code { background: #f0f2f5; color: #9a6700; }
                pre { background: #f6f8fa; border-color: #d8dee4; }
                pre code { color: #24292f; }
                th, td { border-color: #d8dee4; }
                th { background: #f6f8fa; }
                tr:nth-child(even) { background: #f6f8fa; }
                blockquote { border-left-color: #d8dee4; color: #656d76; }
                hr { border-top-color: #d8dee4; }
            }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Intercepts link clicks — opens external links in default browser.
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
                return .cancel
            }
            return .allow
        }
    }
}
