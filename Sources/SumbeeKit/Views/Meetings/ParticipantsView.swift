import SwiftUI

struct ParticipantsView: View {
    @ObservedObject var processing: MeetingProcessingState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var newName = ""
    @State private var editing: UUID?
    @State private var editedName = ""
    @State private var deleting: Participant?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Participants").font(.uiTitle)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(editing == nil ? .cancelAction : nil)
            }
            Text("Names belong to this library. Remembered voices help suggest speakers in future meetings.")
                .font(.uiCallout).foregroundStyle(.secondary)
            TextField("Search participants", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                TextField("New participant name", text: $newName).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let name = newName
                    processing.perform { _, people in _ = try await people.add(name: name) }
                    newName = ""
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(processing.catalog.participants.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { person in
                        participant(person)
                    }
                    if processing.catalog.participants.isEmpty {
                        Text("Add the people you meet with, or name a speaker while reviewing a transcript.")
                            .font(.uiBody).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24).frame(width: 620, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Delete participant?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let person = deleting { processing.perform { _, people in try await people.delete(person.id) } }
                deleting = nil
            }
        } message: { Text("Their remembered voices will be removed. Saved meeting wording and existing exports remain readable.") }
        .alert("Could not update participants", isPresented: Binding(get: { processing.error != nil }, set: { if !$0 { processing.error = nil } })) {
            Button("OK") { processing.error = nil }
        } message: { Text(processing.error ?? "") }
    }

    private func participant(_ person: Participant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if editing == person.id {
                    TextField("Participant name", text: $editedName).textFieldStyle(.roundedBorder)
                    Button("Save") {
                        let name = editedName
                        processing.perform { _, people in try await people.rename(person.id, name: name) }
                        editing = nil
                    }
                    Button("Cancel") { editing = nil }.keyboardShortcut(.cancelAction)
                } else {
                    Text(person.name).font(.uiHeadline)
                    Spacer()
                    Button("Rename") { editedName = person.name; editing = person.id }
                    Menu("Merge into…") {
                        ForEach(processing.catalog.participants.filter { $0.id != person.id }) { other in
                            Button("\(other.name) (\(other.id.uuidString.prefix(6)))") {
                                processing.perform { _, people in try await people.merge(person.id, into: other.id) }
                            }
                        }
                    }.disabled(processing.catalog.participants.count < 2)
                    Button("Delete…", role: .destructive) { deleting = person }
                }
            }
            Text("Added \(person.createdAt.formatted(date: .abbreviated, time: .omitted)) • \(person.id.uuidString.prefix(6))")
                .font(.uiCaption).foregroundStyle(.secondary)
            Text(processing.participantContext(person.id)).font(.uiCaption).foregroundStyle(.secondary)
            let profiles = processing.catalog.profiles.filter { $0.participantID == person.id }
            if profiles.isEmpty {
                Text("No remembered voice").font(.uiCaption).foregroundStyle(.secondary)
            }
            ForEach(profiles) { profile in
                HStack {
                    let meeting = processing.documents.first { $0.id == profile.sourceMeetingID }
                    Text("Voice from \(meeting?.title ?? "unavailable meeting") · \(profile.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.uiCaption)
                    Spacer()
                    Button("Remove voice") { processing.perform { _, people in try await people.removeProfile(profile.id) } }
                }
            }
            Divider()
        }
    }
}
