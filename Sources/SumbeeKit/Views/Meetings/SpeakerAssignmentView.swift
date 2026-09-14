import SwiftUI

struct SpeakerAssignmentView: View {
    @ObservedObject var processing: MeetingProcessingState
    let meetingID: UUID
    let speakerID: UUID
    var onPreview: (() -> Void)? = nil
    var onStopPreview: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var newName = ""
    @State private var previewing = false

    private var meeting: MeetingDocument? { processing.documents.first { $0.id == meetingID } }
    private var speaker: MeetingSpeaker? { meeting?.speakers.first { $0.id == speakerID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(speaker?.genericLabel ?? "Speaker").font(.uiTitle)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let meeting, let speaker {
                if let onPreview {
                    Button(previewing ? "Stop sample" : "Listen to a sample",
                           systemImage: previewing ? "stop.circle" : "play.circle") {
                        if previewing { onStopPreview?() } else { onPreview() }
                        previewing.toggle()
                    }
                    .disabled(!processing.hasAudio(meetingID))
                }
                if let confirmed = speaker.confirmedParticipantID {
                    Label(processing.names[confirmed] ?? speaker.displayNameSnapshot ?? speaker.genericLabel,
                          systemImage: "person.crop.circle.badge.checkmark").font(.uiHeadline)
                    Button("Clear name") { assign(nil) }
                    let reason = ParticipantStore.enrollmentReason(meeting: meeting, speaker: speaker)
                    let remembered = processing.catalog.profiles.contains {
                        $0.sourceMeetingID == meetingID && $0.sourceClusterKeys == speaker.clusterKeys &&
                        $0.sourceAttributionRevision == meeting.attributionRevision &&
                        $0.participantID == processing.catalog.resolve(confirmed)
                    }
                    Button(remembered ? "Voice remembered" : "Remember this voice") {
                        processing.perform { store, people in
                            try await people.enroll(meetingID: meetingID, speakerID: speakerID, meetings: store)
                        }
                    }.disabled(remembered || reason != nil || processing.catalog.resolve(confirmed) == nil)
                    Text(reason ?? "Uses this speaker's original voice group to suggest their name in future meetings. Naming alone does not remember a voice.")
                        .font(.uiCallout).foregroundStyle(.secondary)
                } else if let suggested = speaker.suggestedParticipantID, let name = processing.names[suggested] {
                    Text("Suggested: \(name)").font(.uiHeadline)
                    HStack {
                        Button("Confirm \(name)") { assign(suggested) }
                        Button("Reject suggestion") {
                            processing.perform { store, _ in try await store.dismissSuggestion(meetingID, speakerID: speakerID) }
                        }
                    }
                }
                Divider()
                TextField("Search participants", text: $search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if processing.catalog.participants.isEmpty {
                            Text("No participants yet. Enter a name below to create one and confirm this speaker.")
                                .font(.uiBody).foregroundStyle(.secondary)
                        }
                        ForEach(processing.catalog.participants.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { person in
                            Button { assign(person.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(person.name).font(.uiBody)
                                        Text(processing.participantContext(person.id))
                                            .font(.uiCaption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    Text(String(person.id.uuidString.prefix(6))).font(.uiCaption).foregroundStyle(.secondary)
                                    Text("Confirm").font(.uiCallout)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }.frame(minHeight: 100)
                HStack {
                    TextField("New participant name", text: $newName).textFieldStyle(.roundedBorder)
                    Button("Create and confirm") {
                        let name = newName
                        processing.perform { store, people in
                            let person = try await people.add(name: name)
                            try await store.assignParticipant(meetingID, speakerID: speakerID, participantID: person.id, name: person.name)
                        }
                        newName = ""
                    }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Menu("Merge this speaker group into…") {
                    ForEach(meeting.speakers.filter { $0.id != speakerID }) { other in
                        Button(other.genericLabel) {
                            processing.perform { store, _ in try await store.mergeSpeakers(meetingID, from: speakerID, into: other.id) }
                            dismiss()
                        }
                    }
                }.disabled(meeting.speakers.count < 2)
            }
        }
        .padding(24).frame(width: 560, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { if previewing { onStopPreview?() } }
        .alert("Could not update speaker", isPresented: Binding(get: { processing.error != nil }, set: { if !$0 { processing.error = nil } })) {
            Button("OK") { processing.error = nil }
        } message: { Text(processing.error ?? "") }
    }

    private func assign(_ id: UUID?) {
        processing.perform { store, people in
            let catalog = try await people.load()
            let resolved = id.flatMap { catalog.resolve($0) }
            if id != nil && resolved == nil { throw ParticipantError.missingParticipant }
            let name = catalog.participants.first { $0.id == resolved }?.name
            try await store.assignParticipant(meetingID, speakerID: speakerID, participantID: resolved, name: name)
        }
    }
}
