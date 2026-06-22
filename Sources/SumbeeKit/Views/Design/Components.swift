import SwiftUI

/// A filled accent (orange) button with the brand gradient and a soft glow.
public struct AccentButtonStyle: ButtonStyle {
    public var prominent: Bool
    public init(prominent: Bool = true) { self.prominent = prominent }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.uiBody.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : Theme.accent)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                        .fill(Theme.accentGradient)
                        .shadow(color: Theme.accentGlow(0.5), radius: configuration.isPressed ? 2 : 8, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1.2)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.quick, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A subtle pill button for secondary actions on glass.
public struct GhostButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.uiCallout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// A transient toast surfaced from the bottom bar.
public struct ToastView: View {
    public enum Kind { case info, error, success }
    public var kind: Kind
    public var text: String
    public var onDismiss: () -> Void

    public init(kind: Kind, text: String, onDismiss: @escaping () -> Void) {
        self.kind = kind
        self.text = text
        self.onDismiss = onDismiss
    }

    private var icon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
    private var tint: Color {
        switch kind {
        case .info: return Theme.accent
        case .error: return .red
        case .success: return .green
        }
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.uiBody).foregroundStyle(tint)
            Text(text).font(.uiBody).lineLimit(3)
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: Theme.smallCorner)
        .frame(maxWidth: 420)
    }
}

/// A flat segmented control (no native bezel/drop shadow) — matches the bottom bar's toggle style.
public struct FlatSegmented<T: Hashable>: View {
    @Binding public var selection: T
    public let options: [(value: T, label: String)]

    public init(selection: Binding<T>, options: [(value: T, label: String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let active = selection == opt.value
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.uiCallout.weight(active ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(active ? Color.white : Color.secondary)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accentGradient)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// A small status capsule (used for per-job phase, model badges, etc.).
public struct StatusChip: View {
    public var systemImage: String?
    public var text: String
    public var tint: Color

    public init(systemImage: String? = nil, text: String, tint: Color = Theme.accent) {
        self.systemImage = systemImage
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.uiCallout) }
            Text(text).font(.uiCallout.weight(.semibold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(
            Rectangle().fill(tint.opacity(0.14))
        )
    }
}
