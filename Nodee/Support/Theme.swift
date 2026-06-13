//
//  Theme.swift
//  Nodee
//
//  Shared layout + color constants. Centralized so the canvas, nodes and panel
//  stay visually coherent.
//

import SwiftUI

enum Theme {
    // Node geometry
    static let nodeSize = CGSize(width: 148, height: 116)
    static let nodeCornerRadius: CGFloat = 12
    static let nodeSpacing: CGFloat = 24

    // Canvas
    static let canvasBackground = Color.black
    static let minZoom: CGFloat = 0.35
    static let maxZoom: CGFloat = 2.5

    // Camera gravity — the canvas magnetises to the file mass so you can't drift
    // off into the void. Pan is free while the mass centroid stays within the
    // dead zone; past it the overscroll is damped (rubber-band), and releasing
    // springs the centroid back to the zone edge. Keeps the mass dominant and
    // central without killing the free-canvas feel.
    /// Half-extent of the free zone, as a fraction of the viewport, per axis.
    static let canvasDeadZoneFraction: CGFloat = 0.25
    /// Extra pan slack beyond centring the farthest node (screen points). Gives a
    /// breath of void past the edge nodes so they don't sit pinned to the centre.
    static let canvasPanMargin: CGFloat = Theme.nodeSize.width / 2
    /// Initial give of the rubber-band past the dead zone (0…1) — the slope at the
    /// edge. The resistance then eases up an asymptotic curve, so travel saturates
    /// near one dead-zone extent past the edge. Lower = heavier, softer far end.
    static let canvasOverscrollResistance: CGFloat = 0.3
    /// Elastic snap-back when a pan/pinch ends outside the dead zone. Long, almost
    /// critically damped — the camera glides back to the edge with no perceptible
    /// bounce, so hitting the limit reads as a soft settle rather than a recoil.
    static let canvasSnapBack: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    /// Recenter glide (Space / panel-open). Ease-out rather than a spring so the
    /// motion starts instantly at full velocity (no lazy spring ramp-up) and just
    /// decelerates into place — immediate, smooth, no overshoot.
    static let canvasRecenter: Animation = .easeOut(duration: 0.45)

    // Orbital layout — the tree arranges children in arcs around their parent
    // folder. Deeper levels orbit at a smaller radius so the tree stays compact
    // within the ~20% panel area.
    static let orbitalBaseRadius: CGFloat = 140
    /// Extra radius per child beyond 4 so wider directories fan out.
    static let orbitalRadiusPerChild: CGFloat = 18
    static let orbitalMaxRadius: CGFloat = 280
    /// Multiplicative shrink applied to the radius at each depth level.
    static let orbitalChildRadiusFactor: CGFloat = 0.60
    /// Angular extent of the arc, in degrees. 270° opens at the top.
    static let orbitalArcSpan: Double = 270
    /// Minimum centre-to-centre distance after collision resolution.
    static let orbitalMinSeparation: CGFloat = 52
    /// Dashed ring drawn behind the orbital track.
    static let orbitalRingColor = Color.white.opacity(0.06)
    /// Expand/collapse spring for the orbital bloom/implosion.
    static let orbitalExpand: Animation = .spring(response: 0.45, dampingFraction: 0.72)

    // Parent→child edges — the soft "wires" that turn the free canvas into a
    // legible descending chain. Drawn behind the nodes, in canvas space, so they
    // ride the same zoom/pan as the nodes. Kept faint so dense trees don't read as
    // a web of cables; the curve (not the color) carries the hierarchy.
    static let edgeColor = Color.white.opacity(0.16)
    static let edgeWidth: CGFloat = 1.5

    // Drag-and-drop — the ghost-node idiom: dropping is intent, no confirmation.
    /// Opacity of the dragged node while it hovers a drop target (it reads as a
    /// ghost following the cursor; the target folder shows where it will land).
    static let dropGhostOpacity: CGFloat = 0.5
    /// Border emphasis on the folder under the dragged node.
    static let dropTargetStrokeWidth: CGFloat = 3.5
    /// Slight grow on the target folder so it "accepts" the incoming node.
    static let dropTargetScale: CGFloat = 1.06

    // Panel — the expanded size is derived per-screen (see NotchGeometry.panelSize)
    // so it occupies a fixed slice of the display instead of a hard 1040×660 that
    // dominated small screens. `panelReferenceSize` only fixes the *proportion*
    // (width / height) and is the basis everything scales against.
    static let panelReferenceSize = CGSize(width: 1040, height: 660)
    static var panelAspectRatio: CGFloat { panelReferenceSize.width / panelReferenceSize.height }
    /// Expanded panel area as a fraction of the full screen.
    static let panelScreenAreaFraction: CGFloat = 0.25
    static let panelMargin: CGFloat = 20
    static let panelCornerRadius: CGFloat = 22
    static let panelBackground = Color.black

    // Side panes — fractions of the *panel* width (not the screen), so the canvas
    // stays the dominant, central pane at any panel size. Clamped to a floor so
    // they never collapse to unusable slivers on the smallest notch screens.
    static let sidebarWidthFraction: CGFloat = 0.19
    static let sidebarMinWidth: CGFloat = 132
    static let previewWidthFraction: CGFloat = 0.25
    static let previewMinWidth: CGFloat = 168

    /// Resolved sidebar width for a given panel width.
    static func sidebarWidth(panelWidth: CGFloat) -> CGFloat {
        max(sidebarMinWidth, panelWidth * sidebarWidthFraction)
    }
    /// Resolved preview-pane width for a given panel width.
    static func previewWidth(panelWidth: CGFloat) -> CGFloat {
        max(previewMinWidth, panelWidth * previewWidthFraction)
    }

    /// Extra inset a content edge opens, at full handle proximity, so a
    /// `PaneDivider`'s chevron (18 pt wide) lands in whitespace instead of over
    /// content (buttonWidth/2 + breathing room). Scaled by the live reveal (0…1).
    static let paneHandleGutter: CGFloat = 18

    /// Extra vertical room in the host window, below the expanded panel, so the
    /// drop shadow and the open "stretch" overshoot are never clipped.
    static let panelHostVerticalHeadroom: CGFloat = 96

    // Motion — the panel must read as "emerging from the Notch" in < 200ms.
    // Well-damped springs: smooth, deliberate expansion with no vertical overshoot.
    // The notch grows steadily rather than snapping past its target.
    static let panelOpen: Animation = .spring(response: 0.48, dampingFraction: 0.82)
    static let panelClose: Animation = .spring(response: 0.34, dampingFraction: 0.90)
    static let panelCloseDuration: TimeInterval = 0.36
    /// Delays for the phased reveal: content and shadow appear after the shape
    /// has already begun expanding, so the panel reads as a single solid block
    /// rather than three layers opening simultaneously.
    static let panelContentRevealDelay: TimeInterval = 0.15
    static let panelShadowRevealDelay:  TimeInterval = 0.20
    /// Fast fade used to dismiss content and shadow at the start of a close,
    /// before the shape begins contracting — keeps the retraction clean.
    static let panelOverlayDismiss: Animation = .easeOut(duration: 0.12)
    /// Spring the closed-state notch uses while it grows on hover / live drag.
    static let notchStretch: Animation = .spring(response: 0.36, dampingFraction: 0.80)

    // Gestures
    /// Accumulated downward two-finger scroll (points) needed to commit an open.
    static let openGestureDistance: CGFloat = 42
    /// How long the cursor must rest over the Notch hover area to commit an open
    /// without any swipe — a second, dwell-based way in alongside the swipe down.
    static let holdToOpenDuration: TimeInterval = 0.5
    /// How far the closed notch peeks down at the moment the open commits, for
    /// the rubber-band feel before the full expansion takes over.
    static let notchHoverGrowth: CGFloat = 5
    static let notchPeekGrowth: CGFloat = 16
    /// Normalized vertical travel (0…1 of the trackpad) of a two/three-finger
    /// swipe up — only honored while the pointer is over the bottom grabber — to
    /// commit a condense. Gating on the grabber keeps it clear of the system's
    /// multi-finger gestures (Mission Control / App Exposé) and the canvas pan.
    static let condenseGestureTravel: CGFloat = 0.10
    /// Normalized horizontal travel (0…1 of the trackpad) of a three-finger swipe
    /// to toggle a side panel (Projects sidebar / Preview). Three fingers keeps it
    /// clear of the two-finger folder-depth navigation and the column pan.
    static let panelSwipeTravel: CGFloat = 0.16
    /// How long the cursor must hover the Notch zone during a system-wide drag
    /// before the panel auto-reveals. Shorter than the idle dwell to feel
    /// responsive during the intentional act of dragging toward a target.
    static let dragRevealDelay: TimeInterval = 0.3

    // Grabber — the bottom handle that pulls the expanded panel home to the
    // Notch (bottom-sheet idiom). Lives away from the canvas so it never
    // competes with the two-finger pan.
    static let grabberWidth: CGFloat = 92
    static let grabberHeight: CGFloat = 5
    /// Taller invisible zone around the visible pill for comfortable hover/drag.
    static let grabberHitHeight: CGFloat = 38
    static let grabberBottomInset: CGFloat = 0
    /// Upward click-drag distance (points) on the grabber that commits a condense.
    static let grabberDragCommit: CGFloat = 46

    // Progressive blur — the footer band where the browser content scrolls
    // edge-to-edge and dissolves into the panel's black above the grabber. Blurs
    // the real content via a Metal layer effect (see ProgressiveBlur.metal), so
    // there is no grey material cast. The header is a solid black bar instead.
    /// Band above the grabber where content ramps through the blur into black.
    static let footerBlurHeight: CGFloat = 80
    /// Blur radius at the very bottom edge (ramps from 0 at the top of the band).
    static let progressiveBlurMaxRadius: CGFloat = 18

    // DotMatrixIndicator — data-driven pixel grid for system status feedback.
    // A fixed 3×3 grid of squares whose per-pixel *intensity* (0…1 brightness) is
    // driven by injected float matrices. Same geometry, many behaviours — each a
    // "verb of light" (orbit, converge, lift, cascade, dissolve, breathe, …).
    // Intensity (not boolean on/off) is what lets the light flow rather than blink.
    /// Total side of the component — held constant across grid densities, so a
    /// denser grid (5×5, 7×7) just yields smaller pixels, not a bigger component.
    static let dotMatrixExtent: CGFloat = 14
    /// Gap between adjacent pixels, as a fraction of a pixel's side.
    static let dotMatrixGapRatio: CGFloat = 0.18
    /// Corner radius of each pixel square, as a fraction of its side (.continuous).
    static let dotMatrixCornerRatio: CGFloat = 0.30
    /// Side length of each pixel square (legacy 3×3 default; sizing now derives
    /// the pixel from `dotMatrixExtent` ÷ grid dimension).
    static let dotMatrixPixelSize: CGFloat = 4
    /// Duration of each animation frame in a sequence (sequences usually override).
    static let dotMatrixFrameInterval: TimeInterval = 0.18
    /// Spring for per-pixel intensity transitions — the tween that makes discrete
    /// frames read as continuous flow. Snappy, minimal overshoot.
    static let dotMatrixPixelSpring: Animation = .spring(response: 0.26, dampingFraction: 0.80)
    /// Glow radius behind the grid, colored by the semantic accent. The halo's
    /// opacity is modulated by the grid's peak intensity, so it breathes.
    static let dotMatrixGlowRadius: CGFloat = 14
    /// Peak opacity of a fully-lit (intensity 1.0) pixel.
    static let dotMatrixActiveOpacity: Double = 1.0
    /// Trail decay per cell for comet-style motion (head 1.0 → 0.45 → 0.20 → …).
    static let dotMatrixTrailDecay: Double = 0.45
}
