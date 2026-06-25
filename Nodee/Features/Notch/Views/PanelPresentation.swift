//
//  PanelPresentation.swift
//  Nodee
//
//  Shared open/closed state the SwiftUI surface animates against. The
//  controller flips `isExpanded` inside `withAnimation`; the root view reads it
//  to scale/fade from the Notch anchor.
//

import SwiftUI

@MainActor
@Observable
final class PanelPresentation {
    /// Committed state: the panel is fully expanded into the canvas.
    var isExpanded: Bool = false

    /// The pointer is hovering the closed notch's hit area. Drives a subtle
    /// grow that invites the open gesture.
    var isHoveringNotch: Bool = false

    /// True when the active display should hide the compact Notch until the
    /// pointer approaches the top-centre: external monitors (no hardware notch)
    /// and any display showing a fullscreen app (menu bar hidden). On the
    /// built-in notched display in windowed mode this stays false and the Notch
    /// is always visible, exactly as before.
    var concealsNotch: Bool = false

    /// Reveal amount for the concealed Notch: 0 = tucked above the top edge,
    /// 1 = peeked fully into view. Driven by pointer proximity to the
    /// top-centre. Ignored while `concealsNotch` is false.
    var notchReveal: CGFloat = 0

    /// Live progress of the in-flight two-finger open gesture, 0…1. Only
    /// meaningful while `isExpanded == false`; lets the closed notch peek down
    /// under the finger (rubber band) before the open commits.
    var openProgress: CGFloat = 0

    /// The pointer is over the bottom grabber's hit area while expanded. Drives
    /// the grabber highlight and gates the finger-swipe condense so it never
    /// competes with the canvas pan.
    var isHoveringGrabber: Bool = false

    /// Live upward drag progress on the grabber, 0…1, for the rubber-band pull
    /// before a drag commits a condense.
    var grabberDragProgress: CGFloat = 0

    /// Invoked by the SwiftUI grabber (tap or drag-up commit) to condense. The
    /// controller wires this to `close()`.
    var requestCondense: () -> Void = {}

    /// Source of truth for the Projects sidebar collapse state, shared between
    /// the SwiftUI surface (toolbar toggle, transitions) and the controller's
    /// three-finger swipe (which collapses / expands it).
    var isSidebarCollapsed: Bool = false

    // MARK: - Pane-handle gutter reveal

    /// Which collapsible pane reserves empty edge space as its divider's handle
    /// nears. Only the two between-pane dividers (sidebar, preview) drive this —
    /// the pane *widens* into reserved whitespace while its content stays pinned to
    /// its base width, so directory text never reflows or resizes on hover. The
    /// edge expand-handles use a static inset keyed to collapse state instead.
    enum GutterEdge { case sidebarTrailing, previewLeading }

    /// Proximity-driven reveal amounts (0…1), published by the between-pane
    /// dividers and read by the adjacent pane to widen by the gutter. 0 = relaxed.
    var sidebarTrailingReveal: CGFloat = 0
    var previewLeadingReveal: CGFloat = 0

    /// Route a divider's proximity into its gutter slot. Nil = the divider drives
    /// no inset (the edge expand-handles).
    func setGutterReveal(_ edge: GutterEdge?, _ value: CGFloat) {
        switch edge {
        case .sidebarTrailing: if sidebarTrailingReveal != value { sidebarTrailingReveal = value }
        case .previewLeading:  if previewLeadingReveal  != value { previewLeadingReveal  = value }
        case .none: break
        }
    }

    /// Set the side Preview pane's visibility. Wired by the browser surface so the
    /// controller's three-finger swipe can toggle it — the controller can't reach
    /// the BrowserViewModel directly.
    var setPreviewVisible: ((Bool) -> Void)?

    /// The screen the panel is currently anchored to — the display under the
    /// pointer, resolved by the controller when opening and on display
    /// reconfiguration. The SwiftUI surface derives its Notch geometry (size,
    /// `panelScale`, Notch-vs-pill shape) from this so it always agrees with the
    /// display the host window was placed on. Without a shared source of truth the
    /// window and content disagree about the screen when moving between the
    /// built-in display and an external monitor, producing a wrong-sized /
    /// clipped panel.
    var activeScreen: NSScreen? = NotchGeometry.activeScreen()

    /// Return first responder to the Notch gesture view. SwiftUI buttons (toolbar,
    /// breadcrumb) steal it on click, which silences the indirect-touch gestures
    /// (three-finger panel toggle, grabber condense) until the panel reopens. The
    /// controller wires this to `makeFirstResponder(gestureView)`; call it after
    /// any control that may have grabbed focus.
    var reclaimGestureFocus: () -> Void = {}
}
