//
//  NodeCanvasView.swift
//  Nodee
//
//  The free 2D canvas. Two-finger scroll pans, pinch zooms (both read from
//  AppKit via CanvasInteractionLayer). Drag a node to reposition it, or onto a
//  folder to move it on disk — a ghost preview + folder highlight show the
//  result before you let go. Click selects, double-click a folder expands it.
//
//  Orbital rings, drawn as dashed circles behind the nodes, trace the orbital
//  tracks. Edges use the child's depth to fade/thin deeper wires.
//

import SwiftUI
import AppKit

struct NodeCanvasView: View {
    @Bindable var vm: CanvasViewModel
    @Environment(PanelPresentation.self) private var presentation

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Camera pan (trackpad scroll), behind everything. Pinch zoom is
                // a SwiftUI MagnifyGesture below — .magnify events don't reach the
                // AppKit monitor on this non-activating panel.
                CanvasInteractionLayer(
                    onPan: { dx, dy, momentum in vm.panBy(dx: dx, dy: dy, momentum: momentum) },
                    onScrollEnded: { vm.settleCamera() },
                    shouldYieldPan: notchGestureOwnsScroll
                )

                Theme.canvasBackground
                    .contentShape(Rectangle())
                    .onTapGesture { vm.selection = nil }

                content
                    .scaleEffect(vm.zoom, anchor: .center)
                    .offset(x: vm.pan.width, y: vm.pan.height)
                    .allowsHitTesting(true)
            }
            .clipped()
            // Pinch zoom. Two-finger gesture, so it coexists with the one-finger
            // node drag; magnification is cumulative (1.0 at start).
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { vm.magnify($0.magnification, anchorInViewport: $0.startLocation) }
                    .onEnded { _ in vm.endMagnify() }
            )
            .onAppear { vm.setViewport(geo.size) }
            .onChange(of: geo.size) { _, new in vm.setViewport(new) }
        }
        .overlay(alignment: .bottomTrailing) { zoomBadge }
        .overlay { if vm.rootURL == nil { emptyState } }
    }

    // MARK: - Canvas content

    private var content: some View {
        ZStack(alignment: .topLeading) {
            // Transparent spacer keeps a stable coordinate origin at top-leading.
            Color.clear.frame(width: 1, height: 1)

            // Orbital rings — dashed circles tracing each expanded folder's
            // orbital track. Drawn first (behind everything).
            ForEach(vm.orbitalRings) { ring in
                Circle()
                    .strokeBorder(
                        Theme.orbitalRingColor,
                        style: StrokeStyle(lineWidth: 0.8, dash: [4, 6])
                    )
                    .frame(width: ring.radius * 2, height: ring.radius * 2)
                    .position(ring.center)
                    .allowsHitTesting(false)
            }

            // Parent→child wires, behind the nodes. Same top-leading coordinate
            // space as the nodes (positions are used raw, no screen conversion),
            // so they ride the zoom/pan/parallax of `content` for free.
            ForEach(vm.edges) { edge in
                EdgeShape(from: edge.from, to: edge.to, parentCenter: edge.parentCenter)
                    .stroke(
                        edgeColor(depth: edge.depth),
                        style: StrokeStyle(lineWidth: edgeWidth(depth: edge.depth), lineCap: .round)
                    )
                    .allowsHitTesting(false)
            }

            ForEach(vm.nodes) { node in
                FileNodeView(
                    node: node,
                    isSelected: vm.selection == node.file.url,
                    isDropTarget: vm.dropTargetFolderID == node.file.url
                )
                .opacity(vm.draggingNodeID == node.file.url && vm.dropTargetFolderID != nil
                         ? Theme.dropGhostOpacity : 1)
                .position(node.position)
                .simultaneousGesture(nodeDrag(node))
                .onTapGesture(count: 2) { vm.toggleFolder(node) }
                .onTapGesture(count: 1) { vm.select(node.file.url) }
            }

            ghostPreview
        }
    }

    /// A translucent copy of the dragged node anchored over the target folder —
    /// the predictive "it will land here" preview.
    @ViewBuilder
    private var ghostPreview: some View {
        if let draggedID = vm.draggingNodeID,
           let targetID = vm.dropTargetFolderID,
           let dragged = vm.nodes.first(where: { $0.file.url == draggedID }),
           let target = vm.nodes.first(where: { $0.file.url == targetID }) {
            FileNodeView(node: dragged, isSelected: false)
                .scaleEffect(0.55)
                .opacity(Theme.dropGhostOpacity)
                .position(x: target.position.x, y: target.position.y - target.scale.size.height * 0.32)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Edge styling (depth-aware)

    /// Deeper edges are more transparent so the tree reads as layered, not as a
    /// web of cables.
    private func edgeColor(depth: Int) -> Color {
        let opacity = max(0.06, 0.16 - Double(depth) * 0.03)
        return Color.white.opacity(opacity)
    }

    /// Deeper edges are thinner.
    private func edgeWidth(depth: Int) -> CGFloat {
        max(0.8, 1.5 - CGFloat(depth) * 0.2)
    }

    // MARK: - Gestures

    /// Whether a Notch gesture should own the in-flight scroll instead of the
    /// camera: the pointer is over the grabber (condense swipe) or the notch
    /// hover zone (open swipe). Read in screen space so it holds through the
    /// trackpad's post-lift momentum, when the cursor is parked on the zone.
    private func notchGestureOwnsScroll() -> Bool {
        if presentation.isHoveringGrabber || presentation.grabberDragProgress > 0 { return true }
        guard let screen = NotchGeometry.activeScreen() else { return false }
        return NotchGeometry(screen: screen).hoverTargetRect.contains(NSEvent.mouseLocation)
    }

    private func nodeDrag(_ node: CanvasNode) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if vm.draggingNodeID != node.id { vm.beginDrag(node.id) }
                vm.drag(node.id, translation: value.translation)
            }
            .onEnded { _ in vm.endDrag(node.id) }
    }

    // MARK: - Overlays

    private var zoomBadge: some View {
        Text("\(Int(vm.zoom * 100))%")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text("Fixe uma pasta para começar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text("Arraste uma pasta do Finder ou use o botão +")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}

/// Edge between parent and child. When `parentCenter` is given (orbital layout),
/// the curve bows outward tangent to the orbit; otherwise falls back to the
/// adaptive S-curve from before. The result is an organic arc that hugs the
/// orbital ring rather than cutting across it.
private struct EdgeShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let parentCenter: CGPoint?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)

        if let center = parentCenter {
            // Orbital arc: control points bow outward from the centre, following
            // the curvature of the orbit. The midpoint of from→to is pushed away
            // from `center` by a fraction, creating a gentle arc.
            let midX = (from.x + to.x) / 2
            let midY = (from.y + to.y) / 2
            let dx = midX - center.x
            let dy = midY - center.y
            let dist = hypot(dx, dy)
            guard dist > 0.01 else {
                path.addLine(to: to)
                return path
            }
            // Push the control outward by 30% of the distance to centre.
            let push: CGFloat = 0.30
            let cx = midX + dx * push
            let cy = midY + dy * push
            path.addQuadCurve(to: to, control: CGPoint(x: cx, y: cy))
        } else {
            // Fallback: adaptive S-curve (dominant axis).
            let dx = to.x - from.x, dy = to.y - from.y
            if abs(dx) > abs(dy) {
                let midX = (from.x + to.x) / 2
                path.addCurve(
                    to: to,
                    control1: CGPoint(x: midX, y: from.y),
                    control2: CGPoint(x: midX, y: to.y)
                )
            } else {
                let midY = (from.y + to.y) / 2
                path.addCurve(
                    to: to,
                    control1: CGPoint(x: from.x, y: midY),
                    control2: CGPoint(x: to.x, y: midY)
                )
            }
        }
        return path
    }
}
