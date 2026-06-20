import Foundation
import CoreServices

/// Watches the library root recursively via FSEvents and fires `onChange` (coalesced) when
/// anything is added/removed/modified — so the asset browser stays in sync with Finder.
public final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "com.summarizer.fswatch")

    public init() {}

    public func start(root: URL, onChange: @escaping () -> Void) {
        stop()
        // onChange is read on `queue` (the FSEvents callback runs there); set it there too.
        queue.sync { self.onChange = onChange }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.fire()
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,                       // coalesce bursts over 0.5s
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)   // no further callbacks after this returns
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        queue.sync { self.onChange = nil }
    }

    private func fire() {
        onChange?()
    }

    deinit { stop() }
}
