import SwiftUI

/// Native completion popup (macOS 15 `textInputSuggestions`) for a
/// trailing `[[partial`: picking a name completes it to `[[Name]] `.
private struct SnippetLinkSuggestions: ViewModifier {
    @Environment(SnippetStore.self) private var snippetStore
    let text: String

    func body(content: Content) -> some View {
        content.textInputSuggestions {
            ForEach(SnippetReference.suggestions(for: text, names: snippetStore.snippets.map(\.name)),
                    id: \.self) { name in
                Label(name, systemImage: "doc.text")
                    .textInputCompletion(SnippetReference.completing(text, with: name))
            }
        }
    }
}

extension View {
    func snippetLinkSuggestions(for text: String) -> some View {
        modifier(SnippetLinkSuggestions(text: text))
    }
}
