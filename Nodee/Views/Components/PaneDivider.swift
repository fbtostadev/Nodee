//
//  PaneDivider.swift
//  Nodee
//
//  An interactive separator / edge affordance for a side panel. A proximity
//  tracker watches the cursor within ~110 pt: as it approaches, a chevron handle
//  glides vertically to meet the cursor's height inside the shelf, particles
//  drift toward it, and (between two visible panes) the line brightens with a
//  shimmer band. The handle is an explicit CTA:
//
//    • .collapse — sits on the line between two panes; clicking hides the pane.
//    • .expand   — sits on the pane's edge while it's hidden; clicking reveals it.
//
//  The chevron always points the direction the pane will move, and the button
//  itself is the click target — what you see is what you click.
//

import SwiftUI
import AppKit

struct PaneDivider: View {
    /// Which side of the divider the collapsible pane sits (or would sit) on.
    enum PaneSide { case leading, trailing }
    /// Whether the handle hides the pane (between two visible panes) or reveals it
    /// (on the edge while the pane is hidden).
    enum Mode { case collapse, expand }

    let paneSide: PaneSide
    var mode: Mode = .collapse
    /// Which neighbouring content edge breathes open as this handle nears, so the
    /// chevron lands in cleared whitespace. Nil = drive no gutter.
    var gutter: PanelPresentation.GutterEdge? = nil
    /// Perform the action — hide the pane (`.collapse`) or reveal it (`.expand`).
    let action: () -> Void

    @Environment(PanelPresentation.self) private var presentation

    // Soft teal aura radiating behind the handle button.
    private let handleGlow = Color(red: 0.36, green: 0.74, blue: 0.69)

    // Geometry — the frame width is the single source; everything derives from it.
    private let frameWidth: CGFloat = 14
    private var frameHalf: CGFloat { frameWidth / 2 }
    private let buttonWidth: CGFloat = 18
    private let buttonHeight: CGFloat = 36
    private let buttonCorner: CGFloat = 10

    @State private var tracker = DividerProximity()
    /// True while the cursor is directly over the button — activates the glow.
    @State private var isButtonHovered = false
    /// Divider height, read from a correctly-sized background reader (not the
    /// content), so horizontal layout never depends on a greedy GeometryReader.
    @State private var dividerHeight: CGFloat = 1

    /// Chevron points the way the pane will move: collapse pushes it toward its
    /// side; expand pulls it out from that side.
    private var chevron: String {
        switch (paneSide, mode) {
        case (.leading, .collapse), (.trailing, .expand): return "chevron.compact.left"
        case (.trailing, .collapse), (.leading, .expand): return "chevron.compact.right"
        }
    }

    /// The real dividing line + shimmer only exist between two visible panes.
    private var showsLine: Bool { mode == .collapse }

    /// Center X so the button sits *tangent* to the reference margin — the dividing
    /// line (collapse) or the pane edge (expand).
    private var anchorX: CGFloat {
        let buttonHalf = buttonWidth / 2
        switch (paneSide, mode) {
        // Shift 1 pt toward the line so the button covers its full 1-pt width
        // (previously the right/left edge landed on the line's centre, leaving
        // half the line visible beside the button — a visible overlap artefact).
        case (.leading, .collapse):  return -(buttonHalf - 1)       // juts left over the sidebar
        case (.trailing, .collapse): return   buttonHalf - 1        // juts right over the preview
        case (.leading, .expand):    return -frameHalf + buttonHalf  // juts inward from the left edge
        case (.trailing, .expand):   return  frameHalf - buttonHalf  // juts inward from the right edge
        }
    }

    /// The button's tangent edge — it grows from here, so it appears to emerge from
    /// the margin rather than scaling about its own center.
    private var scaleAnchor: UnitPoint {
        switch (paneSide, mode) {
        case (.leading, .collapse), (.trailing, .expand): return .trailing
        case (.trailing, .collapse), (.leading, .expand): return .leading
        }
    }

    /// Button shape: rounded only on the pane side, square (flush) on the margin
    /// side, so it fuses into the edge like a tab rather than floating as a pill.
    /// Pane is on the leading side when collapsing a leading pane or expanding a trailing one.
    private var buttonShape: UnevenRoundedRectangle {
        let r = buttonCorner
        let paneOnLeading = (paneSide == .leading && mode == .collapse)
                         || (paneSide == .trailing && mode == .expand)
        return paneOnLeading
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r,
                                     bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                     bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    var body: some View {
        let prox = tracker.proximity
        let h = dividerHeight
        // Keep the chevron handle fully on screen as it tracks the cursor.
        let halfTravel = max(0, h / 2 - 18)
        let handleY = min(max((tracker.cursorNorm - 0.5) * h, -halfTravel), halfTravel)

        ZStack {
            clickTarget

            if showsLine {
                shimmerBand(prox: prox)
                // Base separator line — brightens with proximity.
                Rectangle()
                    .fill(Color.white.opacity(0.08 + prox * 0.30))
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }

            // Chevron handle — the click target itself, gliding to the cursor and
            // anchored flush to the margin. Glow comes from colored shadows on the
            // button shape itself — no masked blurred layer, no compositing artefact.
            handleButton(prox: prox)
                .offset(x: anchorX, y: handleY)
                .animation(.smooth(duration: 0.40), value: tracker.cursorNorm)
        }
        // Width is fixed on the content itself — never on a greedy GeometryReader,
        // which reports the full overlay width and throws the anchor off.
        .frame(width: frameWidth)
        .background(frameReader)
        .background(WindowAccessor { tracker.hostWindow = $0 })
        .onAppear { tracker.start() }
        .onDisappear {
            tracker.stop()
            // Relax the neighbour's gutter so a hidden handle never leaves it stuck open.
            presentation.setGutterReveal(gutter, 0)
        }
        // Publish proximity so the adjacent content opens a matching gutter.
        .onChange(of: tracker.proximity) { _, value in
            presentation.setGutterReveal(gutter, value)
        }
        // Soft fade of every proximity-driven element on enter/leave.
        .animation(.smooth(duration: 0.35), value: tracker.proximity)
    }

    /// Reads the divider's true (20-pt-wide) frame for height + the proximity
    /// tracker's reference, decoupled from horizontal layout.
    private var frameReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    dividerHeight = geo.size.height
                    tracker.dividerFrame = geo.frame(in: .global)
                }
                .onChange(of: geo.size.height) { _, value in dividerHeight = value }
                .onChange(of: geo.frame(in: .global)) { _, frame in tracker.dividerFrame = frame }
        }
    }

    /// A soft ice-blue spot tracking the cursor's height along the line.
    private func shimmerBand(prox: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, tracker.cursorNorm - 0.28)),
                .init(color: handleGlow.opacity(prox * 0.22), location: tracker.cursorNorm),
                .init(color: .clear, location: min(1, tracker.cursorNorm + 0.28))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .blur(radius: 4)
        .allowsHitTesting(false)
    }

    /// Dark squircle + bold chevron. Glow activates only on direct button hover
    /// (CTA precision) via layered teal shadows from the button shape.
    private func handleButton(prox: CGFloat) -> some View {
        ZStack {
            buttonShape
                .fill(Color.black)
                .frame(width: buttonWidth, height: buttonHeight)
                // Soft, diffuse aura — low opacity over wide radii so it reads as a
                // gentle bloom rather than a hard halo.
                .shadow(color: handleGlow.opacity(isButtonHovered ? 0.30 : 0), radius: 10)
                .shadow(color: handleGlow.opacity(isButtonHovered ? 0.18 : 0), radius: 22)
                .animation(.easeInOut(duration: 0.22), value: isButtonHovered)

            Image(systemName: chevron)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .opacity(prox)
        .scaleEffect(0.65 + prox * 0.35, anchor: scaleAnchor)
        .contentShape(buttonShape)
        .onHover { isButtonHovered = $0 }
        .onTapGesture { action() }
        .allowsHitTesting(prox > 0.5)
    }

    /// Fallback click region. Between panes it's the whole line; on an edge it's a
    /// narrow strip hugging the pane-side margin, so it doesn't steal clicks from
    /// the browser content behind it.
    @ViewBuilder
    private var clickTarget: some View {
        switch mode {
        case .collapse:
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { action() }
        case .expand:
            HStack(spacing: 0) {
                if paneSide == .trailing { Spacer(minLength: 0) }
                Color.clear
                    .frame(width: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { action() }
                if paneSide == .leading { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - Proximity tracker

/// Watches the cursor near the divider via a local mouse-moved monitor (so it
/// never steals clicks from the panes). Publishes only horizontal closeness
/// (`proximity`, 0–1) and the cursor's normalized height (`cursorNorm`); the view
/// derives the particle/handle motion declaratively from those.
@MainActor
@Observable
private final class DividerProximity {
    var proximity: CGFloat = 0
    var cursorNorm: CGFloat = 0.5

    @ObservationIgnored var dividerFrame: CGRect = .zero
    @ObservationIgnored weak var hostWindow: NSWindow?
    @ObservationIgnored private var monitors: [Any] = []

    /// Pending activation dwell + whether it has elapsed for the current entry.
    @ObservationIgnored private var armTimer: Timer?
    @ObservationIgnored private var armed = false

    /// Horizontal reach (pt) at which the handle starts tracking the cursor.
    private let range: CGFloat = 64
    /// Dwell the cursor must hold inside the zone before the handle activates, so
    /// quick fly-bys past the divider never light it.
    private let activationDelay: TimeInterval = 0.12

    func start() {
        stop()
        // Local + global so proximity keeps updating whether or not Nodee is
        // frontmost — a local-only monitor goes silent once the panel stops being
        // key (e.g. the cursor leaves for another app), leaving the handle stuck
        // until a click reactivates it. Position is derived from the global mouse
        // location (not `event.window`), which global monitors don't carry.
        let track: (NSEvent) -> Void = { [weak self] _ in self?.handle() }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { track($0) },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { track($0); return $0 }
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        disarm()
    }

    private func handle() {
        guard let host = hostWindow, let content = host.contentView,
              dividerFrame != .zero else { return }

        // Screen coords (bottom-left) → window coords → flip to SwiftUI's top-left
        // `.global` frame. Going through the screen location works for both the
        // local and global monitor, regardless of which window has the event.
        let windowPoint = host.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: windowPoint.x, y: content.bounds.height - windowPoint.y)

        let dx = abs(point.x - dividerFrame.midX)
        let withinHeight = point.y >= dividerFrame.minY - 4 && point.y <= dividerFrame.maxY + 4

        // Outside the zone: relax at once and require a fresh dwell on re-entry.
        guard dx <= range && withinHeight else { disarm(); return }

        // Inside the zone but the dwell hasn't elapsed yet — stay dark so a quick
        // pass-through never triggers. The timer re-runs handle() on fire, so a
        // cursor that enters and stops still activates without needing more motion.
        guard armed else { scheduleArm(); return }

        // Guard against redundant @Observable invalidations on every mouse move.
        let newProx: CGFloat = 1 - dx / range
        if abs(newProx - proximity) > 0.001 { proximity = newProx }
        let norm = (point.y - dividerFrame.minY) / max(1, dividerFrame.height)
        let clamped = min(max(norm, 0), 1)
        if abs(clamped - cursorNorm) > 0.001 { cursorNorm = clamped }
    }

    /// Start (once) the activation dwell for the current zone entry; on fire it
    /// arms and re-applies from the live cursor location.
    private func scheduleArm() {
        guard armTimer == nil else { return }
        armTimer = Timer.scheduledTimer(withTimeInterval: activationDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.armTimer = nil
                self.armed = true
                self.handle()
            }
        }
    }

    /// Leaving the zone (or tearing down): cancel a pending dwell, disarm, and
    /// collapse proximity so nothing stays lit.
    private func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        armed = false
        if proximity != 0 { proximity = 0 }
    }
}

// MARK: - Window accessor

/// Resolves the `NSWindow` hosting this view so the proximity monitor can flip
/// AppKit's bottom-left coordinates and ignore events from other windows. Only
/// reports when the resolved window actually changes.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.report(from: view, onResolve)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.report(from: nsView, onResolve)
    }

    final class Coordinator {
        private weak var last: NSWindow?
        private var delivered = false

        func report(from view: NSView, _ onResolve: @escaping (NSWindow?) -> Void) {
            DispatchQueue.main.async { [weak view] in
                let window = view?.window
                guard !self.delivered || window !== self.last else { return }
                self.last = window
                self.delivered = true
                onResolve(window)
            }
        }
    }
}

// MARK: - Preview

