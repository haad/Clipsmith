import SwiftUI
import SwiftData

/// SwiftUI content view for the Prompt Library Bezel HUD panel.
///
/// Responsibilities:
/// - Queries SwiftData for all PromptLibraryItem entries and maps them to
///   PromptBezelViewModel.prompts (a plain [PromptInfo])
/// - Shows a category header bar with Tab cycling hint
/// - Shows an always-visible search TextField for filtering
/// - Displays a scrollable list of prompt rows with category badges
/// - Shows a navigation counter footer
/// - Frosted glass background matching the clipboard bezel visual style
///
/// The view receives a PromptBezelViewModel shared with PromptBezelController so that
/// keyboard events (routed by the controller) mutate the same state the view is observing.
struct PromptBezelView: View {

    // MARK: - Dependencies

    @Query(sort: \ClipsmithSchemaV2.PromptLibraryItem.title)
    private var allPromptItems: [ClipsmithSchemaV2.PromptLibraryItem]

    @Bindable var viewModel: PromptBezelViewModel

    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25

    /// Focus state for the search TextField — always focused in prompt bezel.
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Category header bar
            HStack {
                Text(viewModel.categoryLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text("Tab to cycle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.regularMaterial)

            Divider()

            // Search field — always visible in prompt bezel
            TextField("Search prompts...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)

            Divider()

            // Prompt list
            Group {
                if allPromptItems.isEmpty {
                    emptyPromptsView
                } else if viewModel.filteredPrompts.isEmpty {
                    noMatchesView
                } else {
                    promptListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation counter footer
            HStack {
                Spacer()
                Text(viewModel.navigationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .background(.regularMaterial)
        }
        .background(
            ZStack {
                // Frosted glass blur layer
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                // Opacity layer — controlled by Transparency slider in Preferences.
                // bezelAlpha 0.1 (least transparent) → overlay 0.9 (nearly solid)
                // bezelAlpha 0.9 (most transparent) → overlay 0.1 (mostly glass)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(1.0 - bezelAlpha))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            updatePrompts()
            isSearchFieldFocused = true
        }
        .onChange(of: allPromptItems) {
            updatePrompts()
        }
    }

    // MARK: - Sub-views

    private var emptyPromptsView: some View {
        Text("No prompts in library")
            .foregroundStyle(.secondary)
            .font(.body)
    }

    private var noMatchesView: some View {
        Text("No matches")
            .foregroundStyle(.secondary)
            .font(.body)
    }

    private var promptListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredPrompts.enumerated()), id: \.element.id) { index, prompt in
                        promptRow(prompt: prompt, index: index)
                            .id(index)
                            .onTapGesture {
                                viewModel.navigateTo(index: index)
                            }
                    }
                }
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func promptRow(prompt: PromptInfo, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(prompt.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // "edited" indicator for user-customized (but not user-created) prompts
                if prompt.isUserCustomized && !prompt.isUserCreated {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            // Category badge
            categoryBadge(for: prompt)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    private func categoryBadge(for prompt: PromptInfo) -> some View {
        Text(prompt.isUserCreated ? "My Prompts" : prompt.category)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(badgeColor(for: prompt))
            )
    }

    private func badgeColor(for prompt: PromptInfo) -> Color {
        if prompt.isUserCreated { return .gray }
        switch prompt.category {
        case "coding":   return .blue
        case "writing":  return .green
        case "analysis": return .purple
        case "creative": return .orange
        default:         return .gray
        }
    }

    // MARK: - Helpers

    private func updatePrompts() {
        viewModel.prompts = allPromptItems.map { item in
            PromptInfo(
                id: item.persistentModelID,
                promptID: item.id,
                title: item.title,
                content: item.content,
                category: item.category,
                version: item.version,
                isUserCustomized: item.isUserCustomized,
                isUserCreated: item.isUserCreated
            )
        }
    }
}
