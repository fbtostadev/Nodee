//
//  OrbitalLayout.swift
//  Nodee
//
//  Pure layout engine: receives a visible tree of FileNodes + expansion state
//  and returns positioned CanvasNodes in an orbital arrangement.
//
//  Each expanded folder acts as a gravitational centre. Its direct children
//  orbit in a 270° arc (open at the top, where the parent edge arrives). Sub-
//  folders that are themselves expanded become smaller orbital centres, with
//  the radius shrinking per level so deep trees stay compact.
//
//  Nodes with a saved position (NodeLayout) keep it — the engine only assigns
//  initial placement for unsaved nodes.
//

import Foundation
import CoreGraphics

enum OrbitalLayout {

    // MARK: - Public

    /// Intermediate tree representation built from disk before flattening.
    struct TreeNode {
        let file: FileNode
        let relativePath: String
        let depth: Int
        let parentURL: URL?
        let isExpanded: Bool
        var children: [TreeNode]
    }

    struct LayoutResult {
        var nodes: [CanvasNode]
        var rings: [OrbitalRing]
    }



    static func buildVisibleTree(
        projectRoot: URL,
        expanded: Set<URL>
    ) -> [TreeNode] {
        func walk(container: URL, depth: Int, parent: URL?) -> [TreeNode] {
            FileSystemService.children(of: container).map { file in
                let relativePath = FileSystemService.relativePath(of: file.url, root: projectRoot)
                let isExp = file.isDirectory && expanded.contains(file.url)
                let kids = isExp ? walk(container: file.url, depth: depth + 1, parent: file.url) : []
                return TreeNode(
                    file: file,
                    relativePath: relativePath,
                    depth: depth,
                    parentURL: parent,
                    isExpanded: isExp,
                    children: kids
                )
            }
        }
        return walk(container: projectRoot, depth: 0, parent: nil)
    }

    /// Lay out the tree using orbital placement for nodes without saved positions.
    static func apply(
        tree: [TreeNode],
        viewportCenter: CGPoint,
        savedLayouts: [String: NodeLayout],
        focalNode: URL?
    ) -> LayoutResult {
        var nodes: [CanvasNode] = []
        var rings: [OrbitalRing] = []

        let focalDepth = focalDepth(in: tree, focal: focalNode)

        layoutLevel(
            children: tree,
            center: viewportCenter,
            depth: 0,
            focalNode: focalNode,
            focalDepth: focalDepth,
            savedLayouts: savedLayouts,
            nodes: &nodes,
            rings: &rings
        )

        resolveCollisions(&nodes)
        return LayoutResult(nodes: nodes, rings: rings)
    }

    // MARK: - Core algorithm

    private static func layoutLevel(
        children: [TreeNode],
        center: CGPoint,
        depth: Int,
        focalNode: URL?,
        focalDepth: Int?,
        savedLayouts: [String: NodeLayout],
        nodes: inout [CanvasNode],
        rings: inout [OrbitalRing]
    ) {
        let count = children.count
        guard count > 0 else { return }

        // Radius for this orbit
        let radius = orbitalRadius(childCount: count, depth: depth)

        // Arc: 270° open at the top. Start at 135° (SW), sweep clockwise through
        // S, E, N to 45° (NE). Angles in radians, 0° = east, 90° = south (screen).
        let arcSpan = Theme.orbitalArcSpan * .pi / 180
        let startAngle = (135.0 * .pi / 180.0) // SW
        let angularStep = count > 1 ? arcSpan / Double(count - 1) : 0

        // Emit the orbital ring for expanded parent nodes (depth > 0 means there's
        // a parent centre to ring around; depth 0 rings around the viewport centre).
        if count > 1 {
            if let parentURL = children.first?.parentURL {
                rings.append(OrbitalRing(id: parentURL, center: center, radius: radius))
            } else {
                // Root level: ring around viewport centre, keyed by a stable sentinel.
                rings.append(OrbitalRing(id: URL(string: "nodee://root-orbit")!, center: center, radius: radius))
            }
        }

        for (index, child) in children.enumerated() {
            let scale = nodeScale(depth: child.depth, focalNode: focalNode, focalDepth: focalDepth, node: child)

            // Position: saved layout wins; otherwise, orbital placement.
            let position: CGPoint
            if let saved = savedLayouts[child.relativePath] {
                position = saved.point
            } else {
                let angle = startAngle + Double(index) * angularStep
                position = CGPoint(
                    x: center.x + radius * cos(angle),
                    y: center.y + radius * sin(angle)
                )
            }

            let canvasNode = CanvasNode(
                file: child.file,
                position: position,
                depth: child.depth,
                parentURL: child.parentURL,
                isExpanded: child.isExpanded,
                scale: scale
            )
            nodes.append(canvasNode)

            // Recurse into expanded sub-folders
            if child.isExpanded && !child.children.isEmpty {
                layoutLevel(
                    children: child.children,
                    center: position,
                    depth: child.depth + 1,
                    focalNode: focalNode,
                    focalDepth: focalDepth,
                    savedLayouts: savedLayouts,
                    nodes: &nodes,
                    rings: &rings
                )
            }
        }
    }

    // MARK: - Radius calculation

    private static func orbitalRadius(childCount: Int, depth: Int) -> CGFloat {
        // Start with base, grow by child count, shrink by depth.
        let base = Theme.orbitalBaseRadius
        let extra = CGFloat(max(0, childCount - 4)) * Theme.orbitalRadiusPerChild
        let raw = base + extra

        // Shrink for deeper levels
        let depthFactor = pow(Theme.orbitalChildRadiusFactor, CGFloat(depth))
        let scaled = raw * depthFactor

        return min(scaled, Theme.orbitalMaxRadius)
    }

    // MARK: - Scale determination

    private static func focalDepth(in tree: [TreeNode], focal: URL?) -> Int? {
        guard let focal else { return nil }
        func search(_ nodes: [TreeNode]) -> Int? {
            for node in nodes {
                if node.file.url == focal { return node.depth }
                if let found = search(node.children) { return found }
            }
            return nil
        }
        return search(tree)
    }

    private static func nodeScale(
        depth: Int,
        focalNode: URL?,
        focalDepth: Int?,
        node: TreeNode
    ) -> NodeScale {
        // No focal node: everything at depth 0 is full, depth 1 compact, depth 2+ dot.
        guard let focalDepth else {
            switch depth {
            case 0:  return .full
            case 1:  return .compact
            default: return .dot
            }
        }

        let relativeDepth = depth - focalDepth

        // The focal node itself and its direct children
        if node.file.url == focalNode {
            return .full
        }

        switch relativeDepth {
        case ...(-1): return .compact  // ancestors
        case 0:       return .full     // siblings of focal / focal's children
        case 1:       return .compact  // grandchildren
        default:      return .dot
        }
    }

    // MARK: - Collision resolution

    /// Light repulsion pass: push overlapping nodes apart along the vector between
    /// their centres. Deterministic — at most 3 iterations, each settling more.
    private static func resolveCollisions(_ nodes: inout [CanvasNode]) {
        let iterations = 3
        for _ in 0..<iterations {
            for i in 0..<nodes.count {
                for j in (i+1)..<nodes.count {
                    let minDist = Theme.orbitalMinSeparation
                    let dx = nodes[j].position.x - nodes[i].position.x
                    let dy = nodes[j].position.y - nodes[i].position.y
                    let dist = hypot(dx, dy)

                    guard dist < minDist, dist > 0.01 else { continue }

                    let overlap = (minDist - dist) / 2
                    let nx = dx / dist
                    let ny = dy / dist

                    nodes[i].position.x -= nx * overlap
                    nodes[i].position.y -= ny * overlap
                    nodes[j].position.x += nx * overlap
                    nodes[j].position.y += ny * overlap
                }
            }
        }
    }
}

/// A dashed ring drawn behind the nodes to visualise the orbital track.
struct OrbitalRing: Identifiable {
    let id: URL
    let center: CGPoint
    let radius: CGFloat
}
