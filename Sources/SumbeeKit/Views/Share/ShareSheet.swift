import SwiftUI
import AppKit

/// "Enjoying Sumbee?" share modal (FR: viral share). Gives one-click ways to spread the word:
/// copy the repo link, post to X, email a friend, or hand off to any macOS share service.
struct ShareSheet: View {
    @EnvironmentObject private var state: AppState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            messageCard
            linkRow
            actions
            nativeShareRow
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .onExitCommand { onClose() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Theme.accentGradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: Theme.accentGlow(0.5), radius: 8, y: 2)
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Love Sumbee? Tell a friend.")
                    .font(.uiHeadline)
                Text(ShareContent.tagline)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.callout.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Prewritten message

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A ready-to-share message")
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(ShareContent.message)
                .font(.uiBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: Copyable link

    private var linkRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").font(.uiBody).foregroundStyle(.secondary)
            Text(ShareContent.repoURLString)
                .font(.system(size: 14, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Copy") { state.copyShareLink() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Primary actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                if let url = ShareContent.twitterShareURL { NSWorkspace.shared.open(url) }
            } label: {
                Label("Post on X", systemImage: "bubble.left.and.text.bubble.right.fill")
            }
            .buttonStyle(AccentButtonStyle())

            Button {
                if let url = ShareContent.mailtoURL { NSWorkspace.shared.open(url) }
            } label: {
                Label("Email a friend", systemImage: "envelope.fill")
            }
            .buttonStyle(AccentButtonStyle(prominent: false))

            Spacer()
        }
    }

    // MARK: Native macOS share services

    private var nativeShareRow: some View {
        HStack(spacing: 10) {
            Text("Or share via")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
            SharePickerButton(items: [ShareContent.message, ShareContent.repoURL])
            Spacer()
        }
    }
}

/// AppKit bridge that pops the system `NSSharingServicePicker` anchored to its own button - the
/// reliable way to surface Messages / Mail / AirDrop / etc. from SwiftUI. Kept as a dedicated
/// control (not on a movable background) per the repo's AppKit-interop learnings.
struct SharePickerButton: NSViewRepresentable {
    let items: [Any]

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "More…", target: context.coordinator, action: #selector(Coordinator.present(_:)))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        button.imagePosition = .imageLeading
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.items = items
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var items: [Any]
        weak var button: NSButton?

        init(items: [Any]) { self.items = items }

        @objc func present(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
