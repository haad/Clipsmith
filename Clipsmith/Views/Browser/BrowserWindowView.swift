import SwiftUI

/// Root view of the unified browser window (`WindowGroup(id: "browser")`).
///
/// A segmented picker in the toolbar switches between Snippets, Prompts,
/// Docs (feature-flagged), Toolkit and Todos (feature-flagged). Each
/// section owns its own panes;
/// this view only hosts them and applies `BrowserOpenRequest`s from the mailbox.
///
/// ## Keyboard Shortcuts
///
/// | Shortcut | Action                          |
/// |----------|---------------------------------|
/// | ⌘1–⌘5    | Switch section                  |
/// | ⌘F       | Focus the section's search field|
/// | ⎋        | Close the window                |
struct BrowserWindowView: View {
    let docsetSearchService: DocsetSearchService
    let docsetManagerService: DocsetManagerService

    @State private var viewModel = BrowserWindowViewModel()
    // Section view models live here so switching sections keeps their state.
    @State private var docsViewModel = DocsBrowserViewModel()
    @State private var toolkitViewModel = ClaudeToolkitViewModel()
    @State private var todosViewModel = TodoWindowViewModel()
    @AppStorage(AppSettingsKeys.docLookupEnabled) private var docLookupEnabled: Bool = false
    @AppStorage(AppSettingsKeys.todoTrackingEnabled) private var todoTrackingEnabled: Bool = false

    init(docsetSearchService: DocsetSearchService, docsetManagerService: DocsetManagerService) {
        self.docsetSearchService = docsetSearchService
        self.docsetManagerService = docsetManagerService
    }

    private var sections: [BrowserSection] {
        viewModel.sections(docLookupEnabled: docLookupEnabled, todoTrackingEnabled: todoTrackingEnabled)
    }

    var body: some View {
        Group {
            switch viewModel.selectedSection {
            case .snippets:
                SnippetsSectionView(windowViewModel: viewModel)
            case .prompts:
                PromptsSectionView()
            case .docs:
                DocsSectionView(
                    windowViewModel: viewModel,
                    docs: docsViewModel,
                    searchService: docsetSearchService,
                    managerService: docsetManagerService
                )
            case .toolkit:
                ToolkitSectionView(viewModel: toolkitViewModel)
            case .todos:
                TodosSectionView(viewModel: todosViewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Clipsmith")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $viewModel.selectedSection) {
                    ForEach(sections) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
            }
        }
        // ⎋ closes the window (yields to text fields)
        .onExitCommand {
            NSApp.keyWindow?.close()
        }
        // Hidden buttons for ⌘1–⌘5 section switching
        .background {
            Group {
                ForEach(sections) { section in
                    Button("") { viewModel.selectedSection = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(section.keyboardIndex))), modifiers: .command)
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onAppear {
            // Apply the request that opened us; with none, this still drops a
            // hidden section if the flag was switched off while it was selected.
            let request = BrowserOpenMailbox.shared.take() ?? BrowserOpenRequest(section: nil, query: nil)
            viewModel.apply(request, docLookupEnabled: docLookupEnabled, todoTrackingEnabled: todoTrackingEnabled)
        }
        .onChange(of: docLookupEnabled) { _, enabled in
            viewModel.apply(BrowserOpenRequest(section: nil, query: nil), docLookupEnabled: enabled, todoTrackingEnabled: todoTrackingEnabled)
        }
        .onChange(of: todoTrackingEnabled) { _, enabled in
            viewModel.apply(BrowserOpenRequest(section: nil, query: nil), docLookupEnabled: docLookupEnabled, todoTrackingEnabled: enabled)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipsmithOpenBrowser)) { _ in
            guard let request = BrowserOpenMailbox.shared.take() else { return }
            viewModel.apply(request, docLookupEnabled: docLookupEnabled, todoTrackingEnabled: todoTrackingEnabled)
        }
        .onDisappear {
            // Restore accessory policy when the window closes,
            // but only if no other regular windows remain visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let visibleRegularWindows = NSApp.windows.filter {
                    $0.isVisible && !($0 is NSPanel) && $0.level == .normal
                }
                if visibleRegularWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
