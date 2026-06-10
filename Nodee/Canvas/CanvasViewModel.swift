//
//  CanvasViewModel.swift
//  Nodee
//
//  The brain of the canvas. Builds the visible nodes from disk + the user's
//  spatial state, persists positions/expansion (NodeLayout), and reconciles
//  with disk on every FSEvents change so the canvas stays a faithful mirror.
//
//  Nodes are arranged using an orbital layout: expanded folders act as
//  gravitational centres and their children orbit in a 270° arc. The focal
//  node (the most recently expanded folder) gets full-scale children; the rest
//  of the tree condenses to compact/dot scale to fit the ~20% Notch panel.
//

import SwiftUI
import SwiftData

@MainActor
@Observable
final class CanvasViewModel {
    private let container: ModelContainer

    private(set) var projectID: UUID?
    private(set) var rootURL: URL?
    private(set) var nodes: [CanvasNode] = []
    var selection: URL?

    // View transform
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    @ObservationIgnored var committedZoom: CGFloat = 1
    @ObservationIgnored var committedPan: CGSize = .zero
    /// Zoom at the start of the in-flight pinch, so MagnifyGesture's cumulative
    /// magnification maps onto an absolute zoom. nil between gestures.
    @ObservationIgnored private var zoomGestureBaseline: CGFloat?
    /// Pan and cursor captured at pinch start so each frame can recompute the
    /// pan that keeps the canvas point under the cursor fixed.
    @ObservationIgnored private var panAtZoomStart: CGSize?
    @ObservationIgnored private var zoomAnchorRel: CGSize? // cursor − viewport_center
    /// True once inertia has hit the limit and been clamped, so we animate the
    /// spring-to-edge only on that first contact, not on every momentum event.
    @ObservationIgnored private var momentumClamped = false

    // Auto-center ("attract the camera to the file mass"). Live viewport size,
    // fed by the canvas view. `autoCenterArmed` keeps the camera magnetised to
    // the centroid until the user pans/zooms by hand; Space (or opening a project)
    // re-arms it. See centerOnContent().
    @ObservationIgnored var viewportSize: CGSize = .zero
    @ObservationIgnored private var autoCenterArmed = true

    // Drag state — observable so the canvas can dim the dragged node (ghost) and
    // highlight the folder it would drop into (predictive feedback).
    private(set) var draggingNodeID: URL?
    private(set) var dropTargetFolderID: URL?

    // Orbital state
    /// The folder the user most recently expanded — its children get full/compact
    /// scale; the rest of the tree condenses. nil = root level is focal.
    private(set) var focalNode: URL?
    /// Dashed rings drawn behind nodes to visualise orbital tracks.
    private(set) var orbitalRings: [OrbitalRing] = []

    // Runtime spatial state
    @ObservationIgnored private var expanded: Set<URL> = []
    @ObservationIgnored private var layouts: [String: NodeLayout] = [:] // relativePath -> layout
    @ObservationIgnored private var dragStart: [URL: CGPoint] = [:]
    @ObservationIgnored private var watcher: DirectoryWatcher?

    init(container: ModelContainer) {
        self.container = container
    }

    var selectedNode: CanvasNode? {
        guard let selection else { return nil }
        return nodes.first { $0.file.url == selection }
    }

    /// Centre of the viewport in canvas coordinates — the anchor for the first
    /// orbital level (root children orbit around this point).
    private var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    /// Parent→child edges for the visible nodes. Each edge runs from the parent's
    /// edge to the child's edge along the dominant axis between them. Carries
    /// `parentCenter` (the orbital centre) so the view can draw arcs, and `depth`
    /// so deeper wires can be thinner/more transparent.
    var edges: [CanvasEdge] {
        let byURL = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return nodes.compactMap { child in
            guard let parentURL = child.parentURL, let parent = byURL[parentURL] else { return nil }
            let pSize = parent.scale.size
            let cSize = child.scale.size
            let pHalf = CGSize(width: pSize.width / 2, height: pSize.height / 2)
            let cHalf = CGSize(width: cSize.width / 2, height: cSize.height / 2)
            let p = parent.position, c = child.position
            let dx = c.x - p.x, dy = c.y - p.y
            let horizontal = abs(dx) > abs(dy)
            let from: CGPoint, to: CGPoint
            if horizontal {
                let sign: CGFloat = dx >= 0 ? 1 : -1
                from = CGPoint(x: p.x + sign * pHalf.width, y: p.y)
                to = CGPoint(x: c.x - sign * cHalf.width, y: c.y)
            } else {
                let sign: CGFloat = dy >= 0 ? 1 : -1
                from = CGPoint(x: p.x, y: p.y + sign * pHalf.height)
                to = CGPoint(x: c.x, y: c.y - sign * cHalf.height)
            }
            return CanvasEdge(
                id: child.id,
                from: from,
                to: to,
                parentCenter: parent.position,
                depth: child.depth
            )
        }
    }

    // MARK: - Open / close a project

    func load(projectID: UUID, root: URL) {
        guard projectID != self.projectID else { return }
        watcher?.stop()

        self.projectID = projectID
        self.rootURL = root
        self.selection = nil
        self.focalNode = nil
        self.zoom = 1; self.committedZoom = 1
        self.pan = .zero; self.committedPan = .zero

        loadLayouts()
        restoreExpansion(root: root)
        // One-shot latch: if the viewport size isn't known yet (first launch /
        // discovery), centre once it lands via setViewport. Otherwise centre now.
        autoCenterArmed = (viewportSize == .zero)
        rebuild()
        // First frame: snap (no animation) so the project opens already centred.
        centerOnContent(animated: false)

        let w = DirectoryWatcher(url: root) { [weak self] in self?.reconcile() }
        w.start()
        watcher = w
    }

    func clear() {
        watcher?.stop(); watcher = nil
        projectID = nil; rootURL = nil
        nodes = []; selection = nil
        focalNode = nil; orbitalRings = []
        expanded.removeAll(); layouts.removeAll()
    }

    // MARK: - Camera (two-finger pan + pinch zoom, driven from AppKit)

    /// Two-finger scroll. Pan lives in view-space (applied as `.offset` after the
    /// zoom scale), so deltas are added straight, not divided by zoom. The camera
    /// is magnetised to the file mass: pan is free while the centroid stays inside
    /// the dead zone; past it the overscroll is damped (rubber-band), and
    /// settleCamera() springs it back when the gesture ends.
    func panBy(dx: CGFloat, dy: CGFloat, momentum: Bool) {
        // committedPan is the *raw* intent — deltas accumulate here unclamped. The
        // visible `pan` is always its damped projection, recomputed from scratch, so
        // resistance never feeds back on itself: reversing at the limit unwinds the
        // raw offset directly and the camera responds on the very next event.
        committedPan = CGSize(width: committedPan.width + dx, height: committedPan.height + dy)
        guard let centered = centeredPan() else {
            pan = committedPan; return
        }
        let maxDev = maxDeviation()
        let devX = committedPan.width - centered.width
        let devY = committedPan.height - centered.height

        guard momentum else {
            // Finger down: free up to the limit, soft rubber-band past it.
            momentumClamped = false
            pan = CGSize(
                width: centered.width + resisted(devX, max: maxDev.width),
                height: centered.height + resisted(devY, max: maxDev.height)
            )
            return
        }

        // Post-lift inertia: hard-clamp to the limit instead of rubber-banding.
        // A flick can glide the camera up to the edge but its momentum can never
        // hold it past the edge — that overscroll-then-decay was the ~2s stall
        // before the camera returned. committedPan is collapsed onto the clamp so
        // the inertia can't keep accumulating into the void.
        let cx = min(max(devX, -maxDev.width), maxDev.width)
        let cy = min(max(devY, -maxDev.height), maxDev.height)
        committedPan = CGSize(width: centered.width + cx, height: centered.height + cy)
        let target = committedPan
        let hitLimit = cx != devX || cy != devY
        if hitLimit && !momentumClamped {
            // First inertia frame that meets the edge: spring there smoothly.
            momentumClamped = true
            withAnimation(Theme.canvasSnapBack) { pan = target }
        } else {
            pan = target
        }
    }

    /// Rubber-band a single-axis deviation: free up to `max`, then the excess is
    /// damped on an asymptotic curve (iOS UIScrollView style) so the pan grows ever
    /// slower and never runs away — the past-the-edge travel saturates near `maxDev`.
    /// `canvasOverscrollResistance` sets the initial give (slope at the edge); the
    /// curve eases it toward the limit, which is what makes the far end feel soft.
    private func resisted(_ dev: CGFloat, max maxDev: CGFloat) -> CGFloat {
        let over = abs(dev) - maxDev
        guard over > 0, maxDev > 0 else { return dev }
        let c = Theme.canvasOverscrollResistance
        let damped = maxDev + (over * c * maxDev) / (maxDev + c * over)
        return dev < 0 ? -damped : damped
    }

    /// End of a pan/pinch: spring the camera back so the centroid sits at the edge
    /// of the dead zone (or stays put if already inside it). No-op without mass.
    func settleCamera() {
        guard let centered = centeredPan() else { return }
        let maxDev = maxDeviation()
        let devX = committedPan.width - centered.width
        let devY = committedPan.height - centered.height
        let clampedX = min(max(devX, -maxDev.width), maxDev.width)
        let clampedY = min(max(devY, -maxDev.height), maxDev.height)
        let target = CGSize(width: centered.width + clampedX, height: centered.height + clampedY)
        // Collapse the raw intent back onto the settled position so the next pan
        // starts from where we actually are, not from the overscrolled accumulator.
        committedPan = target
        guard target != pan else { return }
        withAnimation(Theme.canvasSnapBack) { pan = target }
    }

    /// Pinch zoom from SwiftUI's MagnifyGesture. `magnification` is cumulative
    /// (1.0 at the gesture's start). `anchorInViewport` is the pinch centre in
    /// viewport coordinates (top-left origin), captured once from startLocation.
    /// The canvas point under the cursor stays fixed: the pan is recomputed each
    /// frame so `viewport_center + newPan + newZoom * canvasAnchor == cursor`.
    func magnify(_ magnification: CGFloat, anchorInViewport anchor: CGPoint) {
        let baseline = zoomGestureBaseline ?? zoom
        if zoomGestureBaseline == nil {
            zoomGestureBaseline = baseline
            panAtZoomStart = pan
            let vc = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
            zoomAnchorRel = CGSize(width: anchor.x - vc.x, height: anchor.y - vc.y)
        }
        guard let pan0 = panAtZoomStart, let rel = zoomAnchorRel else { return }

        let newZoom = min(max(baseline * magnification, Theme.minZoom), Theme.maxZoom)
        // Keep canvas point fixed: newPan = rel - newZoom * (rel - pan0) / baseline
        let scale = newZoom / baseline
        pan = CGSize(
            width:  rel.width  - scale * (rel.width  - pan0.width),
            height: rel.height - scale * (rel.height - pan0.height)
        )
        committedPan = pan
        zoom = newZoom
        committedZoom = newZoom
    }

    /// Pinch ended: drop the baseline and reseattle the camera, since zooming can
    /// push the mass out of the dead zone.
    func endMagnify() {
        zoomGestureBaseline = nil
        panAtZoomStart = nil
        zoomAnchorRel = nil
        settleCamera()
    }

    // MARK: - Auto-center (camera attracted to the file mass)

    /// Fed by the canvas view as the panel resizes. If a project loaded before the
    /// geometry existed (first launch / discovery), recentre once the size lands.
    func setViewport(_ size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        if autoCenterArmed {
            centerOnContent(animated: false)
            autoCenterArmed = false // initial centring done; resizes won't yank
        }
    }

    /// Bounding box of the node mass in canvas space: centre and per-axis
    /// half-extent (centroid → farthest node centre). nil when there are no nodes.
    private func contentBounds() -> (center: CGPoint, halfExtent: CGSize)? {
        guard !nodes.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for node in nodes {
            minX = min(minX, node.position.x); maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y); maxY = max(maxY, node.position.y)
        }
        return (
            CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            CGSize(width: (maxX - minX) / 2, height: (maxY - minY) / 2)
        )
    }

    /// Max deviation of the centroid from centre before the rubber-band kicks in,
    /// per axis. Grows with the node mass: the floor is the viewport dead zone;
    /// past that it allows panning the farthest node all the way to the centre
    /// (zoom·halfExtent, screen-space), plus a margin of slack. So expanding more
    /// subfolders spreads the mass → larger half-extent → wider pan range; zooming
    /// in widens it too (the mass spans more pixels), zooming out tightens it.
    private func maxDeviation() -> CGSize {
        let floorX = viewportSize.width * Theme.canvasDeadZoneFraction
        let floorY = viewportSize.height * Theme.canvasDeadZoneFraction
        guard let bounds = contentBounds() else {
            return CGSize(width: floorX, height: floorY)
        }
        let margin = Theme.canvasPanMargin
        return CGSize(
            width: max(floorX, zoom * bounds.halfExtent.width + margin),
            height: max(floorY, zoom * bounds.halfExtent.height + margin)
        )
    }

    /// The pan that frames the centroid dead-centre. Derivation: a canvas point C
    /// lands on screen at `centre + zoom·(C − centre) + pan`, so centring C means
    /// `pan = zoom·(centre − C)`. nil when there's no mass or viewport yet.
    private func centeredPan() -> CGSize? {
        guard let centroid = contentBounds()?.center, viewportSize != .zero else { return nil }
        let viewCentre = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGSize(
            width: zoom * (viewCentre.x - centroid.x),
            height: zoom * (viewCentre.y - centroid.y)
        )
    }

    /// Pan the camera so the centroid of the node mass sits at the viewport centre.
    /// Never moves a node or touches disk — pure camera math.
    func centerOnContent(animated: Bool) {
        guard let target = centeredPan() else { return }
        if animated {
            withAnimation(Theme.canvasRecenter) { pan = target }
        } else {
            pan = target
        }
        committedPan = target
    }

    /// Space bar / panel-open: bring the mass home to the exact centre.
    func recenterRequested() {
        centerOnContent(animated: true)
    }

    // MARK: - Interaction

    func select(_ url: URL) { selection = url }

    func toggleFolder(_ node: CanvasNode) {
        guard node.file.isDirectory else { return }

        if expanded.contains(node.file.url) {
            // COLLAPSE: retract children toward parent, then remove.
            focalNode = node.parentURL
            withAnimation(Theme.orbitalExpand) {
                expanded.remove(node.file.url)
                rebuild()
            }
        } else {
            // EXPAND: children bloom outward from the parent centre.
            expanded.insert(node.file.url)
            focalNode = node.file.url

            // Pre-position: place children at the parent's position so the
            // animation starts from there (bloom effect).
            rebuild()
            let parentPos = node.position
            for i in 0..<nodes.count where nodes[i].parentURL == node.file.url {
                nodes[i].position = parentPos
            }

            // Now animate to the real orbital positions.
            withAnimation(Theme.orbitalExpand) {
                rebuild()
            }
        }
        persist(node: node, isExpandedOverride: expanded.contains(node.file.url))
    }

    func beginDrag(_ id: URL) {
        draggingNodeID = id
        dragStart[id] = nodes.first { $0.id == id }?.position
    }

    func drag(_ id: URL, translation: CGSize) {
        guard let start = dragStart[id],
              let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        // The gesture lives inside the zoom-scaled `content` with the default
        // `.local` coordinate space, so SwiftUI already reports `translation` in
        // canvas units (it divides the on-screen finger delta by the scale for us).
        // Dividing by `zoom` again double-compensates and the node drifts behind
        // the cursor, the gap widening with distance.
        nodes[index].position = CGPoint(
            x: start.x + translation.width,
            y: start.y + translation.height
        )
        dropTargetFolderID = folderUnderDraggedNode(id)
    }

    func endDrag(_ id: URL) {
        defer {
            dragStart[id] = nil
            draggingNodeID = nil
            dropTargetFolderID = nil
        }
        guard let node = nodes.first(where: { $0.id == id }) else { return }
        if let targetURL = dropTargetFolderID,
           let target = nodes.first(where: { $0.id == targetURL }) {
            moveOnDisk(node, into: target)
        } else {
            persist(node: node, isExpandedOverride: nil)
        }
    }

    /// The folder node whose frame contains the centre of the dragged node — the
    /// drop target. Excludes the node itself, its current parent (dropping where
    /// it already lives is a no-op) and any of its descendants. Pure canvas-space
    /// math: positions already live there, so no screen conversion is needed.
    private func folderUnderDraggedNode(_ id: URL) -> URL? {
        guard let dragged = nodes.first(where: { $0.id == id }) else { return nil }
        let centre = dragged.position

        return nodes.first { candidate in
            guard candidate.file.isDirectory,
                  candidate.id != dragged.id,
                  candidate.id != dragged.parentURL,
                  !isDescendant(candidate.file.url, of: dragged.file.url)
            else { return false }
            let s = candidate.scale.size
            let frame = CGRect(
                x: candidate.position.x - s.width / 2,
                y: candidate.position.y - s.height / 2,
                width: s.width,
                height: s.height
            )
            return frame.contains(centre)
        }?.file.url
    }

    private func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(ancestor.standardizedFileURL.path + "/")
    }

    /// Move the dragged file into the target folder on disk. The old NodeLayout
    /// is dropped (its relativePath changes); FSEvents then fires reconcile() and
    /// the canvas re-mirrors itself — no manual repositioning.
    private func moveOnDisk(_ node: CanvasNode, into folder: CanvasNode) {
        guard let root = rootURL else { return }
        let oldRelative = FileSystemService.relativePath(of: node.file.url, root: root)
        guard let newURL = FileSystemService.move(node.file.url, into: folder.file.url) else {
            // Move failed: snap the node back by persisting nothing new and
            // rebuilding from the (unchanged) disk truth.
            rebuild()
            return
        }
        if let layout = layouts.removeValue(forKey: oldRelative) {
            container.mainContext.delete(layout)
            try? container.mainContext.save()
        }
        if selection == node.file.url { selection = newURL }
        // FSEvents will reconcile; rebuild now so the node lands immediately.
        rebuild()
    }

    // MARK: - Disk reconciliation

    /// Re-read disk and rebuild. New files appear, deleted files vanish — no
    /// zombie nodes, no error states.
    private func reconcile() {
        guard let root = rootURL else { return }
        if !FileSystemService.exists(root) { clear(); return }
        rebuild()
    }

    // MARK: - Layout building (orbital)

    private func rebuild() {
        guard let root = rootURL else { nodes = []; orbitalRings = []; return }

        let tree = OrbitalLayout.buildVisibleTree(projectRoot: root, expanded: expanded)
        let result = OrbitalLayout.apply(
            tree: tree,
            viewportCenter: viewportCenter,
            savedLayouts: layouts,
            focalNode: focalNode
        )

        nodes = result.nodes
        orbitalRings = result.rings

        if let selection, !nodes.contains(where: { $0.file.url == selection }) {
            self.selection = nil
        }

        // While armed, keep the camera glued to the file mass as it changes
        // (FSEvents/reconcile, expand/collapse, move-on-disk). load() re-snaps
        // without animation right after, so the first frame won't animate.
        if autoCenterArmed { centerOnContent(animated: true) }
    }

    // MARK: - Persistence

    private func loadLayouts() {
        guard let projectID else { layouts = [:]; return }
        let all = (try? container.mainContext.fetch(FetchDescriptor<NodeLayout>())) ?? []
        layouts = Dictionary(
            all.filter { $0.projectID == projectID }.map { ($0.relativePath, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func restoreExpansion(root: URL) {
        expanded = Set(
            layouts.values
                .filter(\.isExpanded)
                .map { root.appendingPathComponent($0.relativePath) }
        )
    }

    private func persist(node: CanvasNode, isExpandedOverride: Bool?) {
        guard let projectID, let root = rootURL else { return }
        let relativePath = FileSystemService.relativePath(of: node.file.url, root: root)
        let isExpanded = isExpandedOverride ?? node.isExpanded

        if let existing = layouts[relativePath] {
            existing.point = node.position
            existing.isExpanded = isExpanded
        } else {
            let layout = NodeLayout(
                projectID: projectID,
                relativePath: relativePath,
                x: node.position.x,
                y: node.position.y,
                isExpanded: isExpanded
            )
            container.mainContext.insert(layout)
            layouts[relativePath] = layout
        }
        try? container.mainContext.save()
    }
}
