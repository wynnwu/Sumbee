import SwiftUI
import AppKit

/// The right column: a live, grouped library browser with a read-only preview and actions.
struct AssetBrowserView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmingDelete: Asset?
    @State private var tab: LibraryTab = .summaries

    enum LibraryTab: String, CaseIterable, Identifiable {
        case summaries = "Summaries"
        case source = "Source"
        var id: String { rawValue }
    }

    private var visibleGroups: [StyleGroup] {
        state.library.groups.filter { tab == .source ? $0.isSourceFolder : !$0.isSourceFolder }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            VSplitView {
                groupList
                    .frame(minHeight: 180)
                PreviewPane(asset: state.selectedAsset,
                            onReveal: reveal, onOpen: open, onCopy: copy,
                            onDelete: { confirmingDelete = $0 })
                    .frame(minHeight: 160)
            }
        }
        .background(.ultraThinMaterial.opacity(0.5))
        .alert("Delete this summary?", isPresented: Binding(
            get: { confirmingDelete != nil },
            set: { if !$0 { confirmingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let a = confirmingDelete { delete(a) }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: {
            Text(confirmingDelete?.title ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Theme.sectionLabel("Library").foregroundStyle(.secondary)
            Spacer()
            Button { state.reloadLibrary() } label: { Image(systemName: "arrow.clockwise").font(.uiBody) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh").accessibilityLabel("Refresh library")
            Button { revealInFinder() } label: { Image(systemName: "folder").font(.uiBody) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(state.selectedAsset != nil ? "Reveal selected summary in Finder" : "Open library in Finder")
                .accessibilityLabel(state.selectedAsset != nil ? "Reveal selected summary in Finder" : "Open library in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(LibraryTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: List

    private var groupList: some View {
        Group {
            if visibleGroups.allSatisfy({ $0.assets.isEmpty }) {
                emptyState
            } else {
                List(selection: Binding<Asset.ID?>(
                    get: { state.selectedAsset?.id },
                    set: { newID in
                        // Resolve by stable id (URL) so selection survives a rescan that
                        // rebuilds Asset values with a different `created` instant.
                        state.selectedAsset = newID.flatMap { id in
                            state.library.groups.flatMap { $0.assets }.first { $0.id == id }
                        }
                    }
                )) {
                    ForEach(visibleGroups) { group in
                        if !group.assets.isEmpty {
                            Section {
                                ForEach(group.assets) { asset in
                                    AssetRowView(asset: asset).tag(asset.id)
                                }
                            } header: {
                                Label(group.name, systemImage: group.isSourceFolder ? "archivebox" : "doc.text")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: tab == .source ? "archivebox" : "tray").font(.system(size: 38)).foregroundStyle(.secondary)
            Text(tab == .source ? "No archived sources yet" : "No summaries yet").font(.uiHeadline)
            Text(tab == .source
                 ? "Originals you summarize are archived here."
                 : "Drop a transcript on a style to create your first one.")
                .font(.uiBody).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Actions

    /// Header folder button: reveal the selected summary if one is selected; otherwise reveal
    /// the library root folder.
    private func revealInFinder() {
        revealURL(state.selectedAsset?.url ?? state.settings.libraryRootURL)
    }

    private func reveal(_ asset: Asset) {
        revealURL(asset.url)
    }

    /// Reveal an item in Finder. We diagnosed (selectFile returned `true`) that *selecting* the
    /// file succeeds but a stale Home window stays frontmost, hiding it. So instead we OPEN the
    /// containing folder as a window — opening a folder brings *that* folder's window to the
    /// front (over Home) — which is also the original ask ("open Finder at the path"). The modern
    /// `open(_:configuration:)` with `activates = true` foregrounds Finder; the completion handler
    /// surfaces any real failure.
    private func revealURL(_ url: URL) {
        // Open the item's containing folder as a Finder window (for a file, its parent).
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let folder = isDir.boolValue ? url : url.deletingLastPathComponent()

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(folder, configuration: config) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                state.present(.error, "Couldn’t open folder: \(error.localizedDescription)")
            }
        }
    }
    private func open(_ asset: Asset) {
        NSWorkspace.shared.open(asset.url)
    }
    private func copy(_ asset: Asset) {
        guard let content = try? String(contentsOf: asset.url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        state.present(.success, "Copied to clipboard.")
    }
    private func delete(_ asset: Asset) {
        do {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            if state.selectedAsset == asset { state.selectedAsset = nil }
            state.reloadLibrary()
            state.present(.info, "Moved to Trash.")
        } catch {
            state.present(.error, "Couldn’t delete: \(error.localizedDescription)")
        }
    }
}

/// One row in the library list — a single line: title left, date-time right.
struct AssetRowView: View {
    let asset: Asset

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.uiBody)
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(asset.title)
                .font(.uiBody)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 10)
            if let created = asset.created {
                Text(created, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch asset.format {
        case .markdown: return "doc.richtext"
        case .html: return "globe"
        }
    }
}
