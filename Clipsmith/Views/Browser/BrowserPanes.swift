import SwiftUI

// Shared building blocks for the browser window sections. The look is lifted
// from the Claude Toolkit window: a list pane with a search bar, an optional
// filter chip row, a counts footer; and a detail pane with header, body and
// an optional footer of actions.

// MARK: - Frame constants

enum BrowserPaneMetrics {
    static let listMinWidth: CGFloat = 240
    static let listIdealWidth: CGFloat = 290
    static let listMaxWidth: CGFloat = 380
    static let sidebarMinWidth: CGFloat = 160
    static let sidebarIdealWidth: CGFloat = 190
    static let sidebarMaxWidth: CGFloat = 240
}

// MARK: - Search field

struct BrowserSearchField<Trailing: View>: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    @ViewBuilder var trailing: () -> Trailing

    init(
        text: Binding<String>,
        placeholder: String,
        isFocused: FocusState<Bool>.Binding,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused(isFocused)
            trailing()
            if !text.isEmpty {
                Button {
                    text = ""
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
    }
}

// MARK: - Filter chips

struct BrowserFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

/// A wrapping row of capsule chips. The leading "All" chip is bound to `nil`.
struct BrowserFilterRow: View {
    let options: [BrowserFilterOption]
    @Binding var selection: String?

    var body: some View {
        BrowserFlowLayout(spacing: 6) {
            chip(label: "All", isSelected: selection == nil) { selection = nil }
            ForEach(options) { option in
                chip(label: option.label, isSelected: selection == option.id) {
                    selection = option.id
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                        : AnyShapeStyle(Color(NSColor.controlBackgroundColor)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

/// Minimal left-to-right wrapping layout for the chip row.
struct BrowserFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - List pane

struct BrowserListPane<Search: View, Filter: View, Content: View, Footer: View>: View {
    let search: Search
    let filter: Filter
    let content: Content
    let footer: Footer

    init(
        @ViewBuilder search: () -> Search,
        @ViewBuilder filter: () -> Filter,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.search = search()
        self.filter = filter()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            search
            Divider()
            filter
            content
            Divider()
            footer
        }
        .frame(
            minWidth: BrowserPaneMetrics.listMinWidth,
            idealWidth: BrowserPaneMetrics.listIdealWidth,
            maxWidth: BrowserPaneMetrics.listMaxWidth
        )
    }
}

struct BrowserCountsFooter: View {
    let leading: String
    let trailing: String

    var body: some View {
        HStack {
            Text(leading)
            Spacer()
            Text(trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Detail pane

struct BrowserDetailPane<Header: View, Body: View, FooterLeading: View, FooterTrailing: View>: View {
    let header: Header
    let content: Body
    let footerLeading: FooterLeading
    let footerTrailing: FooterTrailing

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> Body,
        @ViewBuilder footerLeading: () -> FooterLeading = { EmptyView() },
        @ViewBuilder footerTrailing: () -> FooterTrailing = { EmptyView() }
    ) {
        self.header = header()
        self.content = body()
        self.footerLeading = footerLeading()
        self.footerTrailing = footerTrailing()
    }

    private var hasFooter: Bool {
        !(FooterLeading.self == EmptyView.self && FooterTrailing.self == EmptyView.self)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if hasFooter {
                Divider()
                HStack(spacing: 8) {
                    footerLeading
                    Spacer()
                    footerTrailing
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(minWidth: 400)
    }
}

struct BrowserEmptyDetail: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 400)
    }
}
