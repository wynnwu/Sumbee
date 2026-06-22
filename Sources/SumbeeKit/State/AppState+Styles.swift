import Foundation

/// Style CRUD, mediated through the on-disk StyleStore and reflected live in the UI.
@MainActor
public extension AppState {
    private var root: URL { settings.libraryRootURL }

    /// Create a new style (channel + prompt). Name must be unique.
    func createStyle(name: String, channel: StyleChannel, prompt: String,
                     modelOverride: ModelOverride? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { present(.error, "Name can’t be empty."); return }
        let nextOrder = (library.styles.map(\.order).max() ?? 0) + 1
        let style = SummaryStyle(name: trimmed, channel: channel, prompt: prompt, order: nextOrder,
                                 modelOverride: modelOverride)
        do {
            try styleStore.create(style, root: root)
            reloadLibrary()
            present(.success, "Created “\(trimmed)”.")
        } catch {
            present(.error, "\(error)")
        }
    }

    /// Save edits to an existing style. Handles a rename (folder move) plus definition rewrite.
    func saveStyle(original: SummaryStyle, edited: SummaryStyle) {
        do {
            if edited.name != original.name {
                try styleStore.rename(original, to: edited.name, root: root)
            }
            try styleStore.update(edited, root: root)
            reloadLibrary()
            present(.success, "Saved “\(edited.name)”.")
        } catch {
            present(.error, "\(error)")
        }
    }

    func setStyleEnabled(_ style: SummaryStyle, _ enabled: Bool) {
        var s = style; s.enabled = enabled
        do { try styleStore.update(s, root: root); reloadLibrary() }
        catch { present(.error, "\(error)") }
    }

    /// Delete a style definition (keeps the folder + its summaries; spec FR-10).
    func deleteStyle(_ style: SummaryStyle) {
        do {
            try styleStore.delete(style, root: root)
            reloadLibrary()
            present(.info, "Removed style “\(style.name)”. Its summaries were kept.")
        } catch {
            present(.error, "\(error)")
        }
    }

    /// Move a style up/down in order among styles of the same channel.
    func moveStyle(_ style: SummaryStyle, up: Bool) {
        let sameChannel = library.styles
            .filter { $0.channel == style.channel }
            .sorted { $0.order < $1.order }
        guard let idx = sameChannel.firstIndex(where: { $0.id == style.id }) else { return }
        let swapIdx = up ? idx - 1 : idx + 1
        guard swapIdx >= 0, swapIdx < sameChannel.count else { return }
        var a = sameChannel[idx]
        var b = sameChannel[swapIdx]
        swap(&a.order, &b.order)
        do {
            try styleStore.update(a, root: root)
            try styleStore.update(b, root: root)
            reloadLibrary()
        } catch { present(.error, "\(error)") }
    }

    /// Drag-to-reorder: apply the new visual order from the styles list and persist `order`.
    /// `current` is the displayed (sorted) array; after the move, `order` is reassigned by index.
    func reorderStyles(from source: IndexSet, to destination: Int, current: [SummaryStyle]) {
        var arr = current
        arr.move(fromOffsets: source, toOffset: destination)
        for (i, style) in arr.enumerated() where style.order != i {
            var u = style
            u.order = i
            try? styleStore.update(u, root: root)
        }
        reloadLibrary()
    }

    /// Restore the seeded default styles (additive, never deletes user content).
    func resetStylesToDefaults() {
        do {
            try styleStore.seedDefaults(root: root)
            reloadLibrary()
            present(.success, "Default styles restored.")
        } catch {
            present(.error, "\(error)")
        }
    }
}
