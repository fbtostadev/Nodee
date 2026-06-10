//
//  SecurityScopedBookmark.swift
//  Nodee
//
//  Sandbox bridge. The app only keeps durable access to user-selected folders
//  through app-scoped security bookmarks (see Nodee.entitlements). Pinning a
//  folder stores its bookmark; opening a project resolves it and starts access.
//

import Foundation

enum SecurityScopedBookmark {
    /// Create an app-scoped bookmark for a user-selected folder.
    static func make(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a stored bookmark back into a URL. `isStale` signals the bookmark
    /// should be re-created (the folder moved/renamed).
    static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return (url, stale)
    }
}
