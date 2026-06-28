import SwiftUI

/// Thin left navigation rail switching the main panel's input mode (FR-068). Global nav, present in
/// both modes; surfaces the existing file-vs-YouTube style split.
struct ModeRailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(InputMode.allCases) { mode in
                railItem(mode)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private func railItem(_ mode: InputMode) -> some View {
        let active = state.inputMode == mode
        return Button {
            state.inputMode = mode
        } label: {
            VStack(spacing: 5) {
                Image(systemName: mode.icon).font(.system(size: 19))
                Text(mode.displayName).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? Theme.accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? Theme.accent.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(mode.displayName)
        .accessibilityLabel(mode.displayName)
    }
}
