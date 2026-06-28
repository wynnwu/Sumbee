import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ModeRailView()                          // thin left mode rail (FR-068)
                    HSplitView {
                        MainPanelView()
                            .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity)
                        AssetBrowserView()
                            .frame(minWidth: 340, idealWidth: 440, maxWidth: .infinity)
                    }
                }
                BottomBarView()
            }

            if let toast = state.toast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ToastView(kind: toastKind(toast.kind), text: toast.text) {
                            state.dismissToast()
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 44)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if state.showSettings {
                SettingsView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: Binding(
            get: { state.previewPhase != nil },
            set: { if !$0 { state.cancelPendingPreview() } }
        )) {
            PromptPreviewSheet(onSend: { state.confirmPendingPreview() },
                               onCancel: { state.cancelPendingPreview() })
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showShare) {
            ShareSheet(onClose: { state.showShare = false })
                .environmentObject(state)
        }
        .animation(Theme.spring, value: state.showSettings)
        .animation(Theme.quick, value: state.toast?.id)
        .dynamicTypeSize(.xLarge)          // bump the whole app's text up a notch (FR-027)
        .frame(minWidth: 960, minHeight: 620)
        .task(id: state.toast?.id) {
            guard state.toast != nil else { return }
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            state.dismissToast()
        }
    }

    private func toastKind(_ k: ToastItem.Kind) -> ToastView.Kind {
        switch k {
        case .info: return .info
        case .error: return .error
        case .success: return .success
        }
    }
}
