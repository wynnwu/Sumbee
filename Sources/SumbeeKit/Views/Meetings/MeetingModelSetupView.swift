import SwiftUI

struct MeetingModelSetupView: View {
    @ObservedObject var processing: MeetingProcessingState
    @State private var showNotices = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if processing.checkingModels {
                ProgressView("Checking local meeting models…")
            } else if processing.modelsReady && !processing.downloading {
                Label("Ready to transcribe on this Mac", systemImage: "checkmark.circle")
                    .font(.uiCallout).foregroundStyle(.secondary)
            } else {
                Text("Set up local transcription").font(.uiHeadline)
                Text("Download \(ByteCountFormatter.string(fromByteCount: processing.downloadSize, countStyle: .decimal)) of speech models once. Recordings and speaker profiles stay on this Mac.")
                    .font(.uiCallout).foregroundStyle(.secondary)
                if processing.downloading {
                    ProgressView(value: Double(processing.downloadedBytes), total: Double(max(1, processing.downloadSize)))
                    HStack {
                        Text(processing.downloadedBytes >= processing.downloadSize ? "Verifying downloaded models…" : "Downloading models…")
                            .font(.uiCaption)
                        Spacer()
                        Button("Cancel download") { processing.cancelDownload() }
                    }
                } else {
                    Button("Download meeting models") { processing.downloadModels() }
                        .buttonStyle(AccentButtonStyle())
                }
                if let error = processing.modelError { Text(error).font(.uiCaption).foregroundStyle(.secondary) }
            }
            Button("Model and software notices…") { showNotices = true }.font(.uiCaption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showNotices) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Model and software notices").font(.uiHeadline)
                    Spacer()
                    Button("Done") { showNotices = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    Text(MeetingModelManifest.notices()).font(.uiCaption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(width: 720, height: 560).background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
