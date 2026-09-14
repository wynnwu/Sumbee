import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MeetingModePanel: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var processing: MeetingProcessingState
    @State private var selected: MeetingDocument?
    @State private var showParticipants = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Meetings").font(.uiHeadline)
                Spacer()
                Button("Participants…") { showParticipants = true }
            }
            Text("Transcribe and review audio locally. Only the transcript text is sent when you choose to summarize.")
                .font(.uiCallout).foregroundStyle(.secondary)
            Button(action: chooseAudio) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Import recordings…", systemImage: "waveform.badge.plus").font(.uiHeadline)
                    Text("Drop WAV, MP3, or M4A files here").font(.uiCallout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(targeted ? Theme.accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                .overlay(Rectangle().strokeBorder(targeted ? Theme.accent : Theme.hairline, style: .init(lineWidth: 1, dash: [5, 5])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dropDestination(for: URL.self) { urls, _ in
                let classified = MeetingFileRouting.classify(urls)
                state.importMeetingAudio(classified.audio)
                if !classified.documents.isEmpty || !classified.unsupported.isEmpty {
                    processing.error = "Choose WAV, MP3, or M4A recordings here. Use Transcripts for document summaries."
                }
                return !classified.audio.isEmpty
            } isTargeted: { targeted = $0 }
            MeetingModelSetupView(processing: processing)
            if !state.library.styles.contains(where: { $0.id == DefaultStyles.meetingNotesID || $0.name == "Meeting Notes" }) {
                Button("Add Meeting Notes summary style") { state.addMeetingNotesStyle() }
            }
            ForEach(processing.imports) { item in
                HStack {
                    ProgressView().controlSize(.small)
                    Text("\(item.cancelling ? "Cancelling import" : "Copying audio"): \(item.filename)")
                        .font(.uiCallout).lineLimit(2)
                    Spacer()
                    Button("Cancel") { processing.cancelImport(item.id) }.disabled(item.cancelling)
                }
            }
            if processing.finishingCancelledCall {
                Text("Stopping. The current audio operation is finishing; the next recording will wait.")
                    .font(.uiCallout).foregroundStyle(.secondary)
            }
            Divider()
            if processing.unreadableMeetingCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(processing.unreadableMeetingCount) meeting file(s) could not be read. Their files have been preserved; your other meetings are available below.")
                        .font(.uiCallout).foregroundStyle(.secondary)
                    Button("Reveal meeting files") {
                        if let root = processing.root { NSWorkspace.shared.open(root.appendingPathComponent(".meetings")) }
                    }
                }
            }
            if processing.documents.isEmpty {
                Text("Your imported meetings will appear here. You can reopen and correct a transcript at any time.")
                    .font(.uiBody).foregroundStyle(.secondary)
            }
            ForEach(processing.documents) { meeting in
                HStack(alignment: .top, spacing: 12) {
                    Button { selected = meeting } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(meeting.title).font(.uiBody.weight(.semibold)).lineLimit(2)
                            Text("\(MeetingStore.timestamp(meeting.durationSeconds)) • \(status(meeting))")
                                .font(.uiCaption).foregroundStyle(.secondary)
                            if !processing.hasAudio(meeting.id) {
                                Text("Audio unavailable").font(.uiCaption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if processing.canStart(meeting) {
                        Button("Start") { Task { await processing.enqueue(meeting.id) } }
                    } else if processing.isScheduled(meeting.id) || meeting.status.isProcessing || meeting.status == .awaitingModels {
                        Button("Cancel") { Task { await processing.cancel(meeting.id) } }
                            .disabled(meeting.id == processing.activeID && processing.finishingCancelledCall)
                    } else if [.failed, .interrupted, .cancelled].contains(meeting.status) {
                        Button("Retry") { Task { await processing.enqueue(meeting.id) } }
                            .disabled(!processing.hasAudio(meeting.id))
                    }
                    DeleteMeetingAudioButton(processing: processing, meeting: meeting)
                }.padding(.vertical, 6)
            }
        }
        .sheet(item: $selected) { meeting in
            MeetingReviewView(processing: processing, meetingID: meeting.id).environmentObject(state)
        }
        .sheet(isPresented: $showParticipants) { ParticipantsView(processing: processing) }
        .onChange(of: processing.root) { _, _ in selected = nil; showParticipants = false }
        .alert("Meeting needs attention", isPresented: Binding(get: { processing.error != nil && selected == nil && !showParticipants },
            set: { if !$0 { processing.error = nil } })) {
                Button("OK") { processing.error = nil }
            } message: { Text(processing.error ?? "") }
    }

    private func status(_ meeting: MeetingDocument) -> String {
        if meeting.id == processing.activeID, !processing.finishingCancelledCall { return processing.stage?.title ?? "Preparing" }
        switch meeting.status {
        case .queued: return "Queued"
        case .awaitingModels: return "Waiting for model setup"
        case .transcribing: return "Transcribing"
        case .diarizing: return "Identifying speakers"
        case .assembling: return "Preparing transcript"
        case .ready: return "Ready to review"
        case .noSpeech: return "No speech found"
        case .failed: return "Could not transcribe"
        case .cancelled: return "Cancelled"
        case .interrupted: return "Interrupted"
        }
    }

    private func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["wav", "mp3", "m4a"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { state.importMeetingAudio(panel.urls) }
    }
}
