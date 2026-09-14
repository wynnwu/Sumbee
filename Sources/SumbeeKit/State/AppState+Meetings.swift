import Foundation
import AppKit

enum MeetingFileRouting {
    static func classify(_ urls: [URL]) -> (audio: [URL], documents: [URL], unsupported: [URL]) {
        var audio: [URL] = [], documents: [URL] = [], unsupported: [URL] = []
        for url in urls {
            if ["wav", "mp3", "m4a"].contains(url.pathExtension.lowercased()) { audio.append(url) }
            else if TextExtractor.isSupported(url) { documents.append(url) }
            else { unsupported.append(url) }
        }
        return (audio, documents, unsupported)
    }
}

@MainActor
extension AppState {
    func importMeetingAudio(_ urls: [URL]) {
        inputMode = .meetings
        let root = settings.libraryRootURL
        Task {
            if meetings.root != root.standardizedFileURL { await meetings.selectRoot(root) }
            meetings.importAudio(urls)
        }
    }

    func exportMeeting(_ id: UUID) {
        meetings.perform { [weak self] store, people in
            let names = try await people.resolvedNames()
            let export = try await store.export(id, participantNames: names)
            let url = store.root.appendingPathComponent(export.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            self?.reloadLibrary()
        }
    }

    func summarizeMeeting(_ id: UUID, style: SummaryStyle) {
        guard requireKey() else { return }
        meetings.perform { [weak self] store, people in
            let prepared = try await MeetingSummaryInputBuilder.prepare(id, meetings: store, people: people)
            guard let self else { return }
            try self.enqueueMeetingSnapshot(prepared, style: style)
            self.reloadLibrary()
        }
    }

    func addMeetingNotesStyle() {
        let root = settings.libraryRootURL
        do { try DefaultStyles.installMeetingNotes(root: root, store: styleStore); reloadLibrary() }
        catch { present(.error, error.localizedDescription) }
    }
}
