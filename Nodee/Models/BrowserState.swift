//
//  BrowserState.swift
//  Nodee
//
//  Persists the last browsed directory so reopening the panel lands where the
//  user left off. A single row — the broad Home grant makes the stored path
//  reachable again, revalidated on restore against a granted root.
//

import Foundation
import SwiftData

@Model
final class BrowserState {
    /// POSIX path of the last visited directory.
    var directoryPath: String
    var updatedAt: Date

    init(directoryPath: String) {
        self.directoryPath = directoryPath
        self.updatedAt = Date()
    }
}
