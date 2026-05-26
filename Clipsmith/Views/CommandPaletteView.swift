import SwiftUI

/// SwiftUI content view for the command palette overlay.
///
/// Rendered inside `AppLaunchView` when `viewModel.isCommandPaletteMode` is true.
/// CommandPaletteView does NOT add its own frosted-glass background — it relies on
/// the outer `.background(ZStack { ... })` in `AppLaunchView` for visual consistency
/// (D-14: same frosted-glass background as the app launcher mode).
///
/// Layout (D-12):
/// - Expression label at top (secondary color, echoes the raw query)
/// - Large result in center (44pt rounded semibold, or dimmed "Invalid expression" placeholder)
/// - "Press Return to copy" hint at bottom
/// - "Copied ✓" toast overlay at bottom when `viewModel.showCopiedToast` is true
struct CommandPaletteView: View {

    @Bindable var viewModel: AppLaunchViewModel

    @AppStorage(AppSettingsKeys.bezelAlpha) private var bezelAlpha: Double = 0.25

    var body: some View {
        VStack(spacing: 16) {

            // Expression label (top, secondary) — echoes what the user typed
            Text(viewModel.commandResult?.expression ?? expressionPayloadFromSearch())
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)

            Spacer(minLength: 8)

            // Result (large, primary) or dimmed "Invalid expression" placeholder
            if let result = viewModel.commandResult {
                Text(formatDisplayedResult(result))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 24)
            } else {
                Text("Invalid expression")
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            // Helper hint (small, bottom)
            Text("Press Return to copy")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if viewModel.showCopiedToast {
                Text("Copied ✓")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showCopiedToast)
    }

    // MARK: - Private Helpers

    /// Returns the query payload (searchText minus the prefix) for the expression label
    /// while `commandResult` is still nil (e.g. the user just typed the prefix character).
    private func expressionPayloadFromSearch() -> String {
        let prefix = UserDefaults.standard.string(forKey: AppSettingsKeys.commandPalettePrefix) ?? "="
        return String(viewModel.searchText.dropFirst(prefix.count))
    }

    /// Formats the result for display: "displayValue toUnit" when toUnit is present,
    /// otherwise just "displayValue" (math results).
    private func formatDisplayedResult(_ result: CommandResult) -> String {
        if let unit = result.toUnit {
            return "\(result.displayValue) \(unit)"
        }
        return result.displayValue
    }
}
