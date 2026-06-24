import SwiftUI
import AppKit

/// Read-only preview of a selected summary plus its action toolbar.
struct PreviewPane: View {
    let asset: Asset?
    var onReveal: (Asset) -> Void
    var onOpen: (Asset) -> Void
    var onCopy: (Asset) -> Void
    var onDelete: (Asset) -> Void

    @EnvironmentObject private var state: AppState
    @State private var content: String = ""
    @State private var htmlRaw: String = ""
    @State private var htmlFeatures = HTMLFeatureScanner.Result(hasAdvancedFeatures: false, features: [])
    @State private var keyMonitor: Any?
    @State private var showRegenerate = false

    private static let minFont: Double = 11
    private static let maxFont: Double = 28

    var body: some View {
        VStack(spacing: 0) {
            if state.streamingJobID != nil && state.watchingStream {
                streamingView
            } else if let asset {
                toolbar(asset)
                Divider().overlay(Theme.hairline)
                if asset.format == .html {
                    // Basic, static, private in-app HTML viewer (FR-047/048); it scrolls internally.
                    HTMLWebView(html: htmlRaw, baseSize: state.settings.previewFontSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        MarkdownText(raw: content, baseSize: state.settings.previewFontSize)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                placeholder
            }
        }
        .task(id: asset?.url) { load() }
        .onAppear { installSpaceMonitor() }
        .onDisappear { removeSpaceMonitor() }
    }

    /// Space bar Quick Looks the selected summary (FR-042), unless typing in a field.
    private func installSpaceMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 else { return event }                  // space
            if NSApp.keyWindow?.firstResponder is NSText { return event }     // typing → don't hijack
            // Allow Quick Look of the selected item during a generation, but not while the live
            // stream is on screen (FR-056).
            guard !(state.streamingJobID != nil && state.watchingStream),
                  let url = state.selectedAsset?.url else { return event }
            QuickLookCoordinator.shared.show(url)
            return nil
        }
    }

    private func removeSpaceMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Header label for the live stream; names the item being generated when known.
    private var streamingTitle: String {
        if let id = state.streamingJobID,
           let job = state.jobs.first(where: { $0.id == id }) {
            return "Generating \(job.displayName)…"
        }
        return "Generating…"
    }

    /// Live summary as it streams in (FR-040); auto-scrolls to the bottom.
    private var streamingView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(streamingTitle).font(.uiBody.weight(.semibold)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(Theme.hairline)
            ScrollViewReader { proxy in
                ScrollView {
                    MarkdownText(raw: state.streamingText, baseSize: state.settings.previewFontSize)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("streamBottom")
                }
                .onChange(of: state.streamingText) {
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("streamBottom", anchor: .bottom) }
                }
            }
        }
    }

    private func toolbar(_ asset: Asset) -> some View {
        HStack(spacing: 6) {
            Text(asset.title)
                .font(.uiBody.weight(.semibold))
                .lineLimit(1)
            Spacer()
            // For HTML with interactive/dynamic features the static viewer can't run, offer the
            // browser (FR-051). Kept top-right and clearly labeled.
            if asset.format == .html && htmlFeatures.hasAdvancedFeatures {
                viewInBrowserButton(asset)
                Divider().frame(height: 16).overlay(Theme.hairline)
            }
            iconButton("textformat.size.smaller", "Decrease font size") { adjustFont(-1) }
                .disabled(state.settings.previewFontSize <= Self.minFont)
            iconButton("textformat.size.larger", "Increase font size") { adjustFont(1) }
                .disabled(state.settings.previewFontSize >= Self.maxFont)
            Divider().frame(height: 16).overlay(Theme.hairline)
            iconButton("arrow.triangle.2.circlepath", "Regenerate") { showRegenerate = true }
                .popover(isPresented: $showRegenerate, arrowEdge: .bottom) {
                    RegeneratePopover(asset: asset) { style, override in
                        state.regenerate(asset, style: style, override: override)
                        showRegenerate = false
                    }
                    .environmentObject(state)
                }
            iconButton("eye", "Quick Look (space)") { QuickLookCoordinator.shared.show(asset.url) }
            iconButton("arrow.up.forward.app", "Open") { onOpen(asset) }
            iconButton("folder", "Reveal in Finder") { onReveal(asset) }
            iconButton("doc.on.doc", "Copy") { onCopy(asset) }
            iconButton("trash", "Delete") { onDelete(asset) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// A labeled, accent "View in Browser" action shown for HTML summaries with advanced features.
    private func viewInBrowserButton(_ asset: Asset) -> some View {
        Button { NSWorkspace.shared.open(asset.url) } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text("View in Browser")
            }
            .font(.uiCallout.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .help(browserHelp)
        .accessibilityLabel("View in Browser")
    }

    /// Tooltip naming the detected features so the user knows why the escape hatch is offered.
    private var browserHelp: String {
        let f = htmlFeatures.features
        guard !f.isEmpty else { return "Open this summary in your browser" }
        let list = f.map { $0.lowercased() }.joined(separator: ", ")
        return "This summary uses \(list); open it in your browser for the full experience."
    }

    /// Adjust the sticky preview base font size (FR-036) and persist it.
    private func adjustFont(_ delta: Double) {
        let v = min(max(state.settings.previewFontSize + delta, Self.minFont), Self.maxFont)
        state.settings.previewFontSize = v
        state.scheduleSave()
    }

    private func iconButton(_ system: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: system).font(.system(size: 15)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(help)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Select a summary to preview").font(.uiBody).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        htmlRaw = ""
        htmlFeatures = HTMLFeatureScanner.Result(hasAdvancedFeatures: false, features: [])
        guard let asset else { content = ""; return }
        guard let raw = try? String(contentsOf: asset.url, encoding: .utf8) else {
            content = "_Couldn’t read this file._"
            return
        }
        switch asset.format {
        case .markdown:
            content = FrontmatterCodec.parse(raw).body
        case .html:
            // Render the document itself in the in-app web viewer (FR-047) and decide whether to
            // surface "View in Browser" based on its features (FR-050/051).
            content = ""
            htmlRaw = raw
            htmlFeatures = HTMLFeatureScanner.scan(raw)
        }
    }
}

/// A minimal, pleasant Markdown renderer (headings, bullets, checkboxes, quotes, inline emphasis).
struct MarkdownText: View {
    let raw: String
    /// Base body font size; headings scale proportionally (FR-036).
    var baseSize: Double = 16

    private var lines: [String] { raw.components(separatedBy: "\n") }
    private var scale: Double { baseSize / 16 }

    private enum Block { case line(String); case table(header: [String], rows: [[String]]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            ForEach(Array(Self.parse(lines).enumerated()), id: \.offset) { _, block in
                switch block {
                case .line(let l): row(for: l)
                case .table(let header, let rows): tableView(header, rows)
                }
            }
        }
        .font(.system(size: baseSize, design: .rounded))   // base size for inline body lines
        .tint(Theme.accent)                                // clickable links use the accent (FR-043)
        .textSelection(.enabled)
    }

    /// Render a GitHub-style table as a Grid (FR-043).
    @ViewBuilder
    private func tableView(_ header: [String], _ rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6 * scale) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, h in inline(h).bold() }
            }
            Divider().gridCellColumns(max(header.count, 1))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                GridRow {
                    ForEach(Array(r.enumerated()), id: \.offset) { _, cell in inline(cell) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Block parsing (tables vs lines)

    private static func parse(_ lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            if isTableHeader(lines[i]), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                let header = cells(lines[i])
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count,
                      lines[j].contains("|"),
                      !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(normalize(cells(lines[j]), to: header.count))
                    j += 1
                }
                blocks.append(.table(header: header, rows: rows))
                i = j
            } else {
                blocks.append(.line(lines[i]))
                i += 1
            }
        }
        return blocks
    }

    private static func isTableHeader(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.contains("|") && !t.hasPrefix(">") && !t.hasPrefix("- ")
    }
    private static func isTableSeparator(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }
    private static func cells(_ s: String) -> [String] {
        var parts = s.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }
    private static func normalize(_ cells: [String], to count: Int) -> [String] {
        var c = cells
        if c.count < count { c += Array(repeating: "", count: count - c.count) }
        if c.count > count { c = Array(c.prefix(count)) }
        return c
    }

    @ViewBuilder
    private func row(for line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 5 * scale)
        } else if trimmed.hasPrefix("### ") {
            Text(String(trimmed.dropFirst(4))).font(.system(size: 17 * scale, weight: .bold, design: .rounded))
        } else if trimmed.hasPrefix("## ") {
            Text(String(trimmed.dropFirst(3))).font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("# ") {
            Text(String(trimmed.dropFirst(2))).font(.system(size: 26 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            let checked = !trimmed.hasPrefix("- [ ] ")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Theme.accent : .secondary)
                    .font(.caption)
                inline(String(trimmed.dropFirst(6)))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.accent)
                inline(String(trimmed.dropFirst(2)))
            }
        } else if trimmed.hasPrefix("> ") {
            inline(String(trimmed.dropFirst(2)))
                .italic().foregroundStyle(.secondary)
                .padding(.leading, 8)
        } else {
            inline(line)
        }
    }

    private func inline(_ s: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(s)
    }
}

/// Regenerate a summary from its archived source with a chosen style + optional override (FR-037).
private struct RegeneratePopover: View {
    @EnvironmentObject private var state: AppState
    let asset: Asset
    let onGo: (SummaryStyle, ModelOverride?) -> Void

    @State private var styleID: UUID?
    @State private var changeModel = false
    @State private var model = ModelCatalog.defaultModelID
    @State private var changeFormat = false
    @State private var format: OutputFormat = .markdown

    private var styles: [SummaryStyle] {
        state.library.styles.sorted { $0.order < $1.order }
    }
    private var chosen: SummaryStyle? { styles.first { $0.id == styleID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Regenerate").font(.uiHeadline)
            Text("Re-runs from the archived original into a new summary. The current one is kept.")
                .font(.uiCaption).foregroundStyle(.secondary)

            Picker("Style", selection: $styleID) {
                ForEach(styles) { Text($0.name).tag(Optional($0.id)) }
            }

            Toggle("Use a different model", isOn: $changeModel)
            if changeModel {
                Picker("Model", selection: $model) {
                    ForEach(state.modelsForPicker) { Text($0.displayName).tag($0.id) }
                }.labelsHidden()
            }

            Toggle("Use a different output format", isOn: $changeFormat)
            if changeFormat {
                Picker("Output", selection: $format) {
                    ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            HStack {
                Spacer()
                Button("Regenerate") {
                    guard let style = chosen else { return }
                    var override: ModelOverride?
                    if changeModel || changeFormat {
                        override = ModelOverride(model: changeModel ? model : nil,
                                                 outputFormat: changeFormat ? format : nil)
                    }
                    onGo(style, override)
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(chosen == nil)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            // Default to the style whose folder this summary lives in.
            let folder = asset.url.deletingLastPathComponent().lastPathComponent
            styleID = styles.first { $0.name == folder }?.id ?? styles.first?.id
        }
    }
}
