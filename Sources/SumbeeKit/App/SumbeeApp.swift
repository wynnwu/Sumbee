import SwiftUI

/// The app scene. Defined in the library (no `@main`); the executable target calls
/// `SumbeeApp.main()` from its `main.swift`.
public struct SumbeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 620)
                .background(WindowConfigurator())
                .task { state.bootstrap() }
                .preferredColorScheme(nil)   // follow system light/dark
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { state.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
