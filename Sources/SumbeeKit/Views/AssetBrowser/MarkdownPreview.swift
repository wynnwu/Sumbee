import SwiftUI

/// Read-only preview of a selected summary plus its action toolbar.
struct PreviewPane: View {
    let asset: Asset?
    var onReveal: (Asset) -> Void
    var onOpen: (Asset) -> Void
    var onCopy: (Asset) -> Void
    var onDelete: (Asset) -> Void

    @EnvironmentObject private var state: AppState
    @State private var content: String = ""

    private static let minFont: Double = 11
    private static let maxFont: Double = 28

    var body: some View {
        VStack(spacing: 0) {
            if let asset {
                toolbar(asset)
                Divider().overlay(Theme.hairline)
                ScrollView {
                    MarkdownText(raw: content, baseSize: state.settings.previewFontSize)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                placeholder
            }
        }
        .task(id: asset?.url) { load() }
    }

    private func toolbar(_ asset: Asset) -> some View {
        HStack(spacing: 6) {
            Text(asset.title)
                .font(.uiBody.weight(.semibold))
                .lineLimit(1)
            Spacer()
            iconButton("textformat.size.smaller", "Decrease font size") { adjustFont(-1) }
                .disabled(state.settings.previewFontSize <= Self.minFont)
            iconButton("textformat.size.larger", "Increase font size") { adjustFont(1) }
                .disabled(state.settings.previewFontSize >= Self.maxFont)
            Divider().frame(height: 16).overlay(Theme.hairline)
            iconButton("arrow.up.forward.app", "Open") { onOpen(asset) }
            iconButton("folder", "Reveal in Finder") { onReveal(asset) }
            iconButton("doc.on.doc", "Copy") { onCopy(asset) }
            iconButton("trash", "Delete") { onDelete(asset) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        guard let asset else { content = ""; return }
        guard let raw = try? String(contentsOf: asset.url, encoding: .utf8) else {
            content = "_Couldn’t read this file._"
            return
        }
        switch asset.format {
        case .markdown:
            content = FrontmatterCodec.parse(raw).body
        case .html:
            content = "HTML summary — use **Open** to view it styled in your browser.\n\n"
                + VTTParser.stripTags(raw)   // reuse tag stripper for a plain-text fallback
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(for: line)
            }
        }
        .font(.system(size: baseSize, design: .rounded))   // base size for inline body lines
        .textSelection(.enabled)
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
