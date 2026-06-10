//
//  CanvasNode.swift
//  Nodee
//
//  A file/folder placed on the canvas: the disk truth (`FileNode`) plus its
//  spatial state (position, depth, expansion) and its visual scale within the
//  orbital layout.
//

import Foundation
import CoreGraphics

struct CanvasNode: Identifiable {
    let file: FileNode
    var position: CGPoint
    let depth: Int
    /// Parent folder URL, or nil for top-level nodes (direct children of root).
    let parentURL: URL?
    var isExpanded: Bool
    /// Visual scale assigned by the orbital layout (full/compact/dot).
    var scale: NodeScale

    var id: URL { file.url }
}

/// A drawn parent→child link. Derived from the visible nodes (never persisted).
/// `parentCenter` is the orbital centre the child orbits — when present, the edge
/// draws as an arc tangent to the orbit; when nil, falls back to the adaptive
/// S-curve. `depth` is the child's depth, used to fade/thin deeper wires.
struct CanvasEdge: Identifiable {
    let id: URL
    let from: CGPoint
    let to: CGPoint
    let parentCenter: CGPoint?
    let depth: Int
}
