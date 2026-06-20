import AppKit

/// Ensures the app behaves as a regular GUI app (dock icon, focus) even when launched as a
/// bare SwiftPM binary, and provides a headless smoke-test path for build verification.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Headless verification: launch with SUMBEE_SMOKE=1 to confirm the app boots and
        // a window is created, then write a marker and exit. Used by scripts/verify, not users.
        if ProcessInfo.processInfo.environment["SUMBEE_SMOKE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                let windows = NSApp.windows.filter { $0.isVisible }

                // Optional self-screenshot (renders our own window — no Screen Recording perm needed).
                if let shotPath = ProcessInfo.processInfo.environment["SUMBEE_SHOT"],
                   let window = windows.first, let view = window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: shotPath))
                    }
                }

                let marker = FileManager.default.temporaryDirectory
                    .appendingPathComponent("summarizer-smoke.txt")
                try? "ok windows=\(windows.count)\n".data(using: .utf8)?.write(to: marker)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Warn before quitting while summaries are still running; on confirm, cancel in-flight work
    /// cleanly (assets are written atomically only on completion, so nothing is left partial).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = AppState.current, state.hasRunningJobs else { return .terminateNow }

        let count = state.activeJobCount
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A summary is still running"
        alert.informativeText = count == 1
            ? "Quitting now will cancel the in-progress summary. Quit anyway?"
            : "Quitting now will cancel \(count) in-progress summaries. Quit anyway?"
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Keep Working")

        if alert.runModal() == .alertFirstButtonReturn {
            state.cancelAllJobs()
            return .terminateNow
        }
        return .terminateCancel
    }
}
