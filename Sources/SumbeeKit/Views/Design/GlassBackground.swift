import SwiftUI
import AppKit

/// Real macOS vibrancy via `NSVisualEffectView`, the genuine "glass" the UI is built on.
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var emphasized: Bool

    public init(material: NSVisualEffectView.Material = .underWindowBackground,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
                emphasized: Bool = false) {
        self.material = material
        self.blendingMode = blendingMode
        self.emphasized = emphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = emphasized
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}

/// The window-filling backdrop: vibrancy plus a faint orange aurora for the futuristic feel.
public struct AppBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            // Subtle accent aurora, very low opacity so it reads in light and dark.
            RadialGradient(
                colors: [Theme.accent.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 620
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }
}
