//
//  PaneDivider.swift
//  Nodee
//
//  An interactive separator between the browser and a side panel. A proximity
//  tracker watches the cursor within ~110 pt of the line: as it approaches, the
//  divider brightens, particles drift toward the cursor, a shimmer band follows
//  it, and a chevron handle glides vertically to meet the cursor's height inside
//  the shelf. The handle is an explicit affordance — clicking the line collapses
//  the adjacent pane, and the chevron points in the direction it will hide.
//

import SwiftUI
import AppKit

struct PaneDivider: View {
    /// Which side of the divider the collapsible pane sits on. Drives the chevron
    /// direction (the way the pane will hide).
    enum PaneSide { case leading, trailing }

    let paneSide: PaneSide
    /// Hide the adjacent pane. Invoked on a click anywhere along the divider line.
    let onCollapse: () -> Void

    // Accent shared with ToastView's default/move semantic.
    private let iceBlue = Color(red: 0.55, green: 0.80, blue: 1.00)

    @State private var tracker = DividerProximity()

    private var chevron: String { paneSide == .leading ? "chevron.left" : "chevron.right" }

    var body: some View {
        GeometryReader { geo in
            let prox = tracker.proximity
            let h = geo.size.height
            // Keep the chevron handle fully on screen as it tracks the cursor.
            let halfTravel = max(0, h / 2 - 18)
            let handleY = min(max((tracker.cursorNorm - 0.5) * h, -halfTravel), halfTravel)

            ZStack {
                // [1] Click target — the whole line collapses the adjacent pane.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onCollapse() }

                // [2] Outer horizontal glow, scaled by proximity.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(prox * 0.07), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)

                // [3] Cursor shimmer band — a soft ice-blue spot following the cursor.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, tracker.cursorNorm - 0.28)),
                        .init(color: iceBlue.opacity(prox * 0.22), location: tracker.cursorNorm),
                        .init(color: .clear, location: min(1, tracker.cursorNorm + 0.28))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 1)
                .blur(radius: 4)
                .allowsHitTesting(false)

                // [4] Base separator line — brightens with proximity.
                Rectangle()
                    .fill(Color.white.opacity(0.08 + prox * 0.30))
                    .frame(width: 1)
                    .allowsHitTesting(false)

                // [5] Magnetic particles — drift toward the cursor.
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(iceBlue)
                        .frame(width: 2.5, height: 2.5)
                        .blur(radius: 1.5)
                        .opacity(prox * 0.40)
                        .offset(y: (tracker.particleYs[i] - 0.5) * h)
                        .allowsHitTesting(false)
                }

                // [6] Chevron handle — capsule + directional glyph gliding to the cursor.
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.10 * prox))
                        .frame(width: 3 + prox * 13, height: 28)
                    Image(systemName: chevron)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75 * prox))
                        .opacity(prox)
                }
                .offset(y: handleY)
                .allowsHitTesting(false)
            }
            .background(WindowAccessor { tracker.hostWindow = $0 })
            .onAppear {
                tracker.dividerFrame = geo.frame(in: .global)
                tracker.start()
            }
            .onChange(of: geo.frame(in: .global)) { _, frame in
                tracker.dividerFrame = frame
            }
            .onDisappear { tracker.stop() }
            // Soft, dynamic follow — nothing snappy.
            .animation(.smooth(duration: 0.40), value: tracker.cursorNorm)
            .animation(.smooth(duration: 0.35), value: tracker.proximity)
        }
        .frame(width: 20)
    }
}

// MARK: - Proximity tracker

/// Watches the cursor near the divider via a local mouse-moved monitor (so it
/// never steals clicks from the panes). Publishes horizontal closeness
/// (`proximity`, 0–1), the cursor's normalized height (`cursorNorm`), and the
/// spring-attracted particle positions.
@MainActor
@Observable
private final class DividerProximity {
    var proximity: CGFloat = 0
    var cursorNorm: CGFloat = 0.5
    var particleYs: [CGFloat] = [0.20, 0.40, 0.60, 0.80]

    @ObservationIgnored var dividerFrame: CGRect = .zero
    @ObservationIgnored weak var hostWindow: NSWindow?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private let rest: [CGFloat] = [0.20, 0.40, 0.60, 0.80]

    /// Horizontal reach (pt) at which the handle starts tracking the cursor.
    private let range: CGFloat = 110

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        proximity = 0
    }

    private func handle(_ event: NSEvent) {
        guard let host = hostWindow, event.window === host,
              let content = host.contentView, dividerFrame != .zero else { return }

        // Window coords are bottom-left; SwiftUI's .global frame is top-left.
        let loc = event.locationInWindow
        let point = CGPoint(x: loc.x, y: content.bounds.height - loc.y)

        let dx = abs(point.x - dividerFrame.midX)
        let withinHeight = point.y >= dividerFrame.minY - 4 && point.y <= dividerFrame.maxY + 4

        if dx <= range, withinHeight {
            proximity = 1 - dx / range
            cursorNorm = min(max((point.y - dividerFrame.minY) / max(1, dividerFrame.height), 0), 1)
            attract(to: cursorNorm)
        } else if proximity != 0 {
            proximity = 0
            release()
        }
    }

    /// Pull each particle toward `target`, weighted by proximity — closer ones
    /// move more, giving a magnetic cluster. Springs are staggered per particle so
    /// the motion reads organic rather than locked.
    private func attract(to target: CGFloat) {
        for i in 0..<4 {
            let strength = max(0, 1 - abs(rest[i] - target) * 2.5) * 0.55
            let dest = rest[i] + (target - rest[i]) * strength
            withAnimation(.spring(response: 0.45 + Double(i) * 0.04, dampingFraction: 0.62)) {
                particleYs[i] = dest
            }
        }
    }

    /// Ease all particles back to their idle rest positions.
    private func release() {
        for i in 0..<4 {
            withAnimation(.spring(response: 0.80, dampingFraction: 0.72)) {
                particleYs[i] = rest[i]
            }
        }
    }
}

// MARK: - Window accessor

/// Resolves the `NSWindow` hosting this view so the proximity monitor can flip
/// AppKit's bottom-left coordinates and ignore events from other windows.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
