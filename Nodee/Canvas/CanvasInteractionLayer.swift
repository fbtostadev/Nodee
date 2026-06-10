//
//  CanvasInteractionLayer.swift
//  Nodee
//
//  Camera PAN for the canvas, read straight from AppKit so it feels native to
//  the trackpad: two-finger scroll pans, with the trackpad's own momentum.
//  Living in AppKit (instead of SwiftUI's DragGesture) keeps it clear of the
//  per-node drag gestures — the camera and the nodes never fight over a touch.
//
//  Zoom is NOT handled here: .magnify gesture events don't get processed by the
//  NSEvent monitor reliably on this non-activating panel — the pinch is consumed
//  by the responder chain, so zoom lives in SwiftUI as a MagnifyGesture on
//  NodeCanvasView. We still list .magnify in the mask (so the system delivers
//  pinch gestures to the process at all) but pass it straight through.
//
//  We watch with BOTH a global and a local NSEvent monitor: the panel is a
//  non-activating agent window, so when the app isn't frontmost the events never
//  reach the local monitor. The global monitor catches those; the local one
//  swallows the event when our app is key so nothing behind reacts twice. The
//  same physical event can hit both, so we de-dupe by timestamp — keyed PER
//  EVENT TYPE so an interleaved .magnify never steals a .scrollWheel's slot (a
//  shared key dropped pans whenever a pinch's stray events arrived). We only act
//  while the cursor is over this view's bounds (the canvas, not the sidebar or
//  preview pane).
//

import SwiftUI
import AppKit

struct CanvasInteractionLayer: NSViewRepresentable {
    /// Two-finger scroll, in points. Natural-scroll deltas; pan adds them as-is.
    /// The `momentum` flag marks post-finger-lift inertia events so the camera can
    /// refuse to rubber-band past the limit during a flick's decay.
    var onPan: (CGFloat, CGFloat, Bool) -> Void
    /// Fires when the scroll gesture (including trackpad momentum) fully settles,
    /// so the camera can spring back to the file mass.
    var onScrollEnded: () -> Void
    /// True while a Notch gesture owns the current scroll — the cursor is over the
    /// notch (open swipe) or the grabber (condense swipe). When it is, the camera
    /// stands down so the same two-finger swipe doesn't also pan the canvas.
    var shouldYieldPan: () -> Bool = { false }

    func makeNSView(context: Context) -> CameraGestureView {
        let view = CameraGestureView()
        view.onPan = onPan
        view.onScrollEnded = onScrollEnded
        view.shouldYieldPan = shouldYieldPan
        view.startMonitoring()
        return view
    }

    func updateNSView(_ view: CameraGestureView, context: Context) {
        view.onPan = onPan
        view.onScrollEnded = onScrollEnded
        view.shouldYieldPan = shouldYieldPan
    }

    static func dismantleNSView(_ view: CameraGestureView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class CameraGestureView: NSView {
        var onPan: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }
        var onScrollEnded: () -> Void = {}
        var shouldYieldPan: () -> Bool = { false }

        private var monitors: [Any] = []
        /// Last handled timestamp per event type, so de-duping scroll vs magnify
        /// stays independent.
        private var lastTimestamp: [NSEvent.EventType: TimeInterval] = [:]

        /// Let clicks fall through to the SwiftUI nodes — this layer only watches
        /// scroll via the monitors, it should never capture the pointer.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func startMonitoring() {
            stopMonitoring()
            let mask: NSEvent.EventTypeMask = [.scrollWheel, .magnify]
            monitors = [
                NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                    _ = self?.handle(event)
                },
                NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    self?.handle(event) ?? event
                }
            ].compactMap { $0 }
        }

        func stopMonitoring() {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors.removeAll()
        }

        /// Returns nil to swallow the event (we handled it), or the event to let
        /// it pass (not over the canvas, a duplicate, or a magnify we don't own).
        @discardableResult
        private func handle(_ event: NSEvent) -> NSEvent? {
            // The same physical event can reach both monitors; de-dupe per type.
            guard lastTimestamp[event.type] != event.timestamp else { return nil }
            guard cursorIsOverCanvas() else { return event }

            // Hand a scroll back to the Notch gesture when it owns it (open over
            // the notch, condense over the grabber). Pinch (.magnify) is never a
            // Notch gesture, so it's exempt. Done before claiming the timestamp so
            // the event passes through untouched.
            if event.type == .scrollWheel, shouldYieldPan() { return event }

            lastTimestamp[event.type] = event.timestamp

            switch event.type {
            case .scrollWheel:
                // momentumPhase is empty while the finger is down and non-empty
                // for the trackpad's post-lift inertia. Flagging it lets the
                // camera hard-clamp at the limit during inertia instead of letting
                // the flick's decay (~2s) hold it overscrolled before springing back.
                let momentum = event.momentumPhase != []
                onPan(event.scrollingDeltaX, event.scrollingDeltaY, momentum)
                // Settle the moment the finger lifts (no waiting on inertia) and
                // again when inertia finally ends. settleCamera is idempotent.
                if event.momentumPhase == .ended || event.phase == .ended {
                    onScrollEnded()
                }
                return nil
            default:
                // .magnify: leave it for SwiftUI's MagnifyGesture to consume.
                return event
            }
        }

        /// Hit-test in screen space so it works for both the global monitor
        /// (event has no window) and the local one.
        private func cursorIsOverCanvas() -> Bool {
            guard let window else { return false }
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let viewPoint = convert(windowPoint, from: nil)
            return bounds.contains(viewPoint)
        }
    }
}
