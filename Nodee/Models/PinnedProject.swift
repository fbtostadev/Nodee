//
//  PinnedProject.swift
//  Nodee
//
//  A folder the user pinned to the sidebar. Persisted via SwiftData.
//  We store a *security-scoped bookmark*, not a raw path: the sandbox only
//  grants durable access to user-selected locations through bookmarks.
//

import Foundation
import SwiftData

@Model
final class PinnedProject {
    /// Stable identity, also used to key canvas layout (`NodeLayout`).
    var id: UUID
    var name: String
    /// Security-scoped bookmark of the pinned folder. Resolved at runtime.
    var bookmark: Data
    /// Manual order in the sidebar (customizable by drag).
    var sortIndex: Int
    var addedAt: Date

    init(id: UUID = UUID(), name: String, bookmark: Data, sortIndex: Int, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.sortIndex = sortIndex
        self.addedAt = addedAt
    }
}
