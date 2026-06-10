//
//  FileAction.swift
//  Nodee
//
//  A record of one disk mutation, enough to undo it. The undo/redo stacks in
//  BrowserViewModel hold these. `reverted()` performs the inverse on disk and
//  hands back the action that would replay it, so undo and redo are the same
//  call from opposite stacks. Best-effort like the rest of FileSystemService:
//  items that vanished out from under us are skipped, never surfaced as errors.
//

import Foundation

enum FileAction {
    /// Items moved (or renamed) from → to.
    case move(items: [(from: URL, to: URL)])
    /// Items sent to the Trash, paired with where they landed there.
    case trash(items: [(original: URL, trashed: URL)])
    /// Items freshly materialized (new folder/file, duplicate, paste). Undo
    /// trashes them; redo restores them from the Trash.
    case create(urls: [URL])

    /// On-disk URLs the action leaves in place — what to re-select after it runs.
    var resultingURLs: [URL] {
        switch self {
        case .move(let items):  return items.map(\.to)
        case .trash(let items): return items.map(\.trashed)
        case .create(let urls): return urls
        }
    }

    /// Perform the inverse on disk and return the action that would replay this
    /// one (to push onto the opposite stack). Returns nil when nothing could be
    /// reverted (every target already gone).
    func reverted() -> FileAction? {
        switch self {
        case .move(let items):
            var done: [(from: URL, to: URL)] = []
            for item in items {
                if let landed = FileSystemService.move(item.to, to: item.from) {
                    done.append((from: item.to, to: landed))
                }
            }
            return done.isEmpty ? nil : .move(items: done)

        case .trash(let items):
            // Restore each item from the Trash to its original spot. Replaying the
            // resulting move puts it back at the Trash path (it lands in ~/.Trash).
            var restored: [(from: URL, to: URL)] = []
            for item in items {
                if let landed = FileSystemService.move(item.trashed, to: item.original) {
                    restored.append((from: item.trashed, to: landed))
                }
            }
            return restored.isEmpty ? nil : .move(items: restored)

        case .create(let urls):
            let pairs = FileSystemService.moveToTrash(urls.filter(FileSystemService.exists))
            return pairs.isEmpty ? nil : .trash(items: pairs)
        }
    }
}
