//
//  NodeLayout.swift
//  Nodee
//
//  Persistent canvas position of a single node within a project. This is the
//  only place the user's spatial organization lives — the files themselves are
//  never touched by moving a node on the canvas.
//
//  Keyed by (projectID, relativePath) so positions survive across sessions and
//  follow the file even as siblings change.
//

import Foundation
import SwiftData

@Model
final class NodeLayout {
    var projectID: UUID
    /// Path relative to the project root, e.g. "src/assets/logo.png".
    var relativePath: String
    var x: Double
    var y: Double
    /// Whether this folder node is expanded on the canvas.
    var isExpanded: Bool

    init(projectID: UUID, relativePath: String, x: Double, y: Double, isExpanded: Bool = false) {
        self.projectID = projectID
        self.relativePath = relativePath
        self.x = x
        self.y = y
        self.isExpanded = isExpanded
    }

    var point: CGPoint {
        get { CGPoint(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }
}
