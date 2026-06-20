import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One square drop tile per file-channel style. Dotted border by default; a valid file type
/// dragged over it turns the border solid orange with an outer glow and lifts the tile (FR-022).
struct DropZoneView: View {
    @EnvironmentObject private var state: AppState
    let style: SummaryStyle
    @State private var targeted = false

    private var activeCount: Int {
        state.jobs.filter { $0.styleID == style.id && !$0.phase.isTerminal }.count
    }

    var body: some View {
        Button(action: openPicker) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(targeted ? Theme.accent : Color.secondary.opacity(0.55))
                    Spacer()
                    if activeCount > 0 {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            StatusChip(text: "\(activeCount)")
                        }
                    }
                }
                Spacer(minLength: 10)
                Text(style.name)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(targeted ? Theme.accent : Color.primary.opacity(0.40))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
            .background(.ultraThinMaterial, in: Rectangle())
            .overlay(
                Rectangle().strokeBorder(
                    targeted ? Theme.accent : Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.4, dash: targeted ? [] : [5, 5])
                )
            )
            .shadow(color: targeted ? Theme.accentGlow(0.6) : .clear, radius: targeted ? 18 : 0, y: targeted ? 6 : 0)
            .scaleEffect(targeted ? 1.03 : 1)
            .offset(y: targeted ? -3 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(state.hasKey ? 1 : 0.55)
        .animation(Theme.spring, value: targeted)
        .onDrop(of: [UTType.fileURL], delegate: FileDropDelegate(
            highlightTypes: Self.highlightTypes,
            targeted: $targeted,
            onDrop: { providers in
                loadURLs(from: providers) { urls in
                    guard !urls.isEmpty else { return }
                    state.enqueueFiles(urls, style: style)
                }
            }
        ))
        .help("Summarize transcripts with the “\(style.name)” style")
        .accessibilityLabel("\(style.name) drop zone")
    }

    // MARK: Picker

    private func openPicker() {
        guard state.hasKey else { state.showSettings = true; return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.highlightTypes
        if panel.runModal() == .OK {
            state.enqueueFiles(panel.urls, style: style)
        }
    }

    /// Accepted content types — used for the valid-type hover highlight and the file picker.
    static let highlightTypes: [UTType] = {
        var types: [UTType] = [.plainText, .pdf, .rtf]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        return types
    }()

    // MARK: Drop loading

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? URL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

/// Drop delegate that distinguishes a *valid* file-type hover (orange highlight) from any
/// other drag, while still allowing any file to be dropped (unsupported types are rejected
/// with a message after the drop, as defense in depth).
private struct FileDropDelegate: DropDelegate {
    let highlightTypes: [UTType]
    @Binding var targeted: Bool
    let onDrop: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        // Light up only when a valid (accepted) file type is being dragged.
        targeted = info.hasItemsConforming(to: highlightTypes)
    }

    func dropExited(info: DropInfo) {
        targeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }
        onDrop(providers)
        return true
    }
}
