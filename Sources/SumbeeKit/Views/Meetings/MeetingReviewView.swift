import SwiftUI
import AVFoundation
import AppKit

@MainActor
private final class MeetingPlayback: ObservableObject {
    @Published var position = 0.0
    @Published var playing = false
    private var player: AVPlayer?
    private var observer: Any?

    func open(_ url: URL) {
        stop()
        let player = AVPlayer(url: url)
        self.player = player
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.seconds.isFinite { self.position = time.seconds }
                self.playing = self.player?.rate != 0
            }
        }
    }
    func toggle() {
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }
    func pause() {
        player?.pause()
        playing = false
    }
    func seek(_ seconds: Double, play: Bool = true) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = seconds
        if play { player?.play(); playing = true }
    }
    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player = nil
        playing = false
    }
}

struct MeetingReviewView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var processing: MeetingProcessingState
    let meetingID: UUID
    @StateObject private var playback = MeetingPlayback()
    @State private var selectedSpeaker: MeetingSpeaker?
    @State private var editingTurn: UUID?
    @State private var editedText = ""
    @FocusState private var focusedTurn: UUID?
    @State private var audioURL: URL?
    @State private var showAttendees = false
    @State private var selectedStyle: UUID?
    @State private var confirmSummary = false

    private var meeting: MeetingDocument? { processing.documents.first { $0.id == meetingID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(meeting?.title ?? "Meeting").font(.uiHeadline).lineLimit(2)
                Spacer()
                if let meeting {
                    DeleteMeetingAudioButton(processing: processing, meeting: meeting) {
                        playback.stop()
                        audioURL = nil
                    }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(editingTurn == nil ? .cancelAction : nil)
            }
            if let meeting {
                playbackControls(meeting)
                if !processing.hasAudio(meetingID) {
                    Text("Audio is no longer available. Your transcript and speaker information are kept; you can still edit, export, and summarize.")
                        .font(.uiCallout).foregroundStyle(.secondary)
                }
                if let failure = meeting.failureMessage {
                    Text(failure).font(.uiBody).foregroundStyle(.secondary)
                }
                if meeting.status == .noSpeech {
                    Text(processing.hasAudio(meetingID) ? "No speech was found. You can play the recording to check it." : "No speech was found in this recording.").font(.uiBody)
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(meeting.speakers) { speaker in
                            Button(speakerLabel(speaker)) { selectedSpeaker = speaker }
                        }
                        Button("Attendees…") { showAttendees = true }
                    }
                }
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(meeting.turns.enumerated()), id: \.element.id) { index, turn in
                            turnView(turn, index: index, meeting: meeting)
                        }
                    }.padding(.vertical, 8).padding(.trailing, 12)
                }
                if meeting.status == .ready {
                    Divider()
                    HStack {
                        Button("Export transcript") { state.exportMeeting(meetingID) }
                        Spacer()
                        Picker("Style", selection: $selectedStyle) {
                            Text("Choose style").tag(nil as UUID?)
                            ForEach(state.fileStyles) { style in Text(style.name).tag(Optional(style.id)) }
                        }.frame(maxWidth: 250)
                        Button("Summarize…") { confirmSummary = true }
                            .disabled(selectedStyle == nil)
                    }
                }
            } else {
                Text("This meeting is no longer available in the selected library.")
                Spacer()
            }
        }
        .padding(24).frame(minWidth: 780, idealWidth: 900, minHeight: 600, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedSpeaker) { speaker in
            SpeakerAssignmentView(processing: processing, meetingID: meetingID, speakerID: speaker.id, onPreview: {
                let start = meeting?.turns.first(where: { $0.speakerID == speaker.id && $0.start != nil })?.start ?? 0
                playback.seek(start)
            }, onStopPreview: { playback.pause() })
        }
        .sheet(isPresented: $showAttendees) { attendees }
        .task(id: meetingID) {
            guard processing.hasAudio(meetingID) else { return }
            do {
                let store = try processing.meetingStore()
                let url = try await store.audioURL(meetingID)
                audioURL = url
                playback.open(url)
            } catch { processing.error = error.localizedDescription }
        }
        .onDisappear { playback.stop() }
        .onChange(of: processing.hasAudio(meetingID)) { _, available in
            if !available { playback.stop(); audioURL = nil }
        }
        .confirmationDialog("Send this reviewed transcript for summarization?", isPresented: $confirmSummary, titleVisibility: .visible) {
            Button("Send transcript and summarize") {
                if let style = state.fileStyles.first(where: { $0.id == selectedStyle }) {
                    state.summarizeMeeting(meetingID, style: style)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A new transcript export uses the latest confirmed names. Its text is sent to your configured summary model. Audio and voice profiles stay on this Mac.")
        }
        .alert("Meeting needs attention", isPresented: Binding(get: { processing.error != nil && selectedSpeaker == nil }, set: { if !$0 { processing.error = nil } })) {
            Button("OK") { processing.error = nil }
        } message: { Text(processing.error ?? "") }
    }

    private func playbackControls(_ meeting: MeetingDocument) -> some View {
        HStack(spacing: 12) {
            Button(playback.playing ? "Pause" : "Play", systemImage: playback.playing ? "pause.fill" : "play.fill") { playback.toggle() }
                .disabled(audioURL == nil)
            Text(MeetingStore.timestamp(playback.position)).monospacedDigit().font(.uiCaption)
            Slider(value: Binding(get: { min(playback.position, max(1, meeting.durationSeconds)) }, set: { playback.seek($0, play: false) }),
                   in: 0...max(1, meeting.durationSeconds)).accessibilityLabel("Recording position")
            Text(MeetingStore.timestamp(meeting.durationSeconds)).monospacedDigit().font(.uiCaption)
            Button("Reveal audio") { if let audioURL { NSWorkspace.shared.activateFileViewerSelecting([audioURL]) } }
                .disabled(audioURL == nil)
        }
    }

    private func turnView(_ turn: MeetingTurn, index: Int, meeting: MeetingDocument) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Button(turn.start.map(MeetingStore.timestamp) ?? "Untimed") {
                let nearby = turn.start ?? meeting.turns.prefix(index).reversed().compactMap(\.start).first ?? 0
                playback.seek(nearby)
            }
            .font(.uiCaption).monospacedDigit().frame(width: 74, alignment: .leading)
            .help(turn.start == nil ? "Play nearby audio; this paragraph has no exact timestamp" : "Play from this timestamp")
            .accessibilityLabel(turn.start.map { "Play from \(MeetingStore.timestamp($0))" } ?? "Play nearby audio for untimed paragraph")
            .disabled(audioURL == nil)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let speaker = meeting.speakers.first(where: { $0.id == turn.speakerID }) {
                        Button(speakerLabel(speaker)) { selectedSpeaker = speaker }.font(.uiBody.weight(.semibold)).buttonStyle(.plain)
                    }
                    Spacer()
                    Menu("Assign turn") {
                        ForEach(meeting.speakers) { speaker in
                            Button(speakerLabel(speaker)) {
                                processing.perform { store, _ in try await store.reassignTurn(meetingID, turnID: turn.id, to: speaker.id) }
                            }
                        }
                        Button("New speaker") {
                            processing.perform { store, _ in try await store.reassignTurn(meetingID, turnID: turn.id, to: nil) }
                        }
                    }.fixedSize()
                    Button("Edit") { editingTurn = turn.id; editedText = turn.text }
                }
                if editingTurn == turn.id {
                    TextEditor(text: $editedText).font(.uiBody).frame(minHeight: 110)
                        .accessibilityLabel("Transcript paragraph")
                        .focused($focusedTurn, equals: turn.id)
                        .onAppear { focusedTurn = turn.id }
                    HStack {
                        Button("Save") {
                            let text = editedText
                            processing.perform { store, _ in try await store.editText(meetingID, turnID: turn.id, text: text) }
                            editingTurn = nil
                        }.keyboardShortcut("s", modifiers: .command)
                        Button("Cancel") { editingTurn = nil }.keyboardShortcut(.cancelAction)
                    }
                } else {
                    Text(turn.text).font(.uiBody).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func speakerLabel(_ speaker: MeetingSpeaker) -> String {
        if let confirmed = speaker.confirmedParticipantID { return processing.names[confirmed] ?? speaker.displayNameSnapshot ?? speaker.genericLabel }
        if let suggested = speaker.suggestedParticipantID, let name = processing.names[suggested] { return "Suggested: \(name)" }
        return speaker.genericLabel
    }

    private var attendees: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Expected attendees").font(.uiHeadline)
                Spacer()
                Button("Done") { showAttendees = false }.keyboardShortcut(.cancelAction)
            }
            Text("Optional. Choose people to narrow voice suggestions. Leave all unchecked to search your catalog.")
                .font(.uiCallout).foregroundStyle(.secondary)
            ScrollView {
                ForEach(processing.catalog.participants) { person in
                    Toggle("\(person.name) (\(person.id.uuidString.prefix(6)))", isOn: Binding(get: {
                        meeting?.expectedParticipantIDs.contains(person.id) ?? false
                    }, set: { enabled in
                        Task { await processing.updateAttendee(meetingID, participantID: person.id, included: enabled) }
                    }))
                }
            }
        }.padding(24).frame(width: 480, height: 400).background(Color(nsColor: .windowBackgroundColor))
    }
}
