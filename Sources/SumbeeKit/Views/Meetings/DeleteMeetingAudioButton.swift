import SwiftUI

struct DeleteMeetingAudioButton: View {
    @ObservedObject var processing: MeetingProcessingState
    let meeting: MeetingDocument
    var onDeleted: () -> Void = {}
    @State private var confirming = false
    @State private var confirmedRoot: URL?

    var body: some View {
        Button("Delete audio…", systemImage: "trash", role: .destructive) {
            confirmedRoot = processing.root
            confirming = true
        }
        .disabled(!processing.canDeleteAudio(meeting))
        .accessibilityLabel("Delete saved audio for \(meeting.title)")
        .help(processing.canDeleteAudio(meeting) ? "Delete only the saved audio file" : "Audio is unavailable, or meeting work must finish first")
        .alert("Delete audio for \(meeting.title)?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { }
            Button("Delete audio", role: .destructive) {
                guard let confirmedRoot else { return }
                Task {
                    if await processing.deleteAudio(meeting.id, root: confirmedRoot) { onDeleted() }
                }
            }
        } message: {
            Text("This permanently deletes only Sumbee’s saved audio file. The transcript, participant names, remembered voices, models, exports, summaries, and your original audio file are kept. Playback will no longer be available.")
        }
        .onChange(of: processing.root) { _, _ in confirming = false; confirmedRoot = nil }
    }
}
