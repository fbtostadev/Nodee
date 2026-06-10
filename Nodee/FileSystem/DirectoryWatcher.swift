//
//  DirectoryWatcher.swift
//  Nodee
//
//  Watches a folder subtree with FSEvents and reports changes on the main
//  queue. This is what keeps the canvas a faithful mirror: when a file is
//  deleted/moved/created outside Nodee (Finder, terminal, anything), the canvas
//  re-reads and the corresponding node appears or disappears — no zombie nodes.
//

import Foundation

/// Not actor-isolated: the FSEvents C callback runs on the dispatch queue we
/// assign (main), and we keep cleanup independent of MainActor deinit rules.
nonisolated final class DirectoryWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            // We set the dispatch queue to main below, so this runs on main.
            MainActor.assumeIsolated { watcher.onChange() }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25, // latency: coalesce bursts, stay well under the 200ms feel budget
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
