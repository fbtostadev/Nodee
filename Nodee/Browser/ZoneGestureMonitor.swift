//
//  ZoneGestureMonitor.swift
//  Nodee
//
//  Watches two-finger horizontal scrolling within a specific defined zone to
//  trigger actions like opening/closing side panels (Sidebar or Preview).
//  Uses a local NSEvent monitor to capture `.scrollWheel` events.
//

import AppKit

@MainActor
final class ZoneGestureMonitor {
    var onProgress: (CGFloat) -> Void = { _ in }
    var onCommit: (_ swipeRight: Bool) -> Void = { _ in }
    var onCancel: () -> Void = {}

    /// Closure that determines if the mouse location is within the valid zone for this monitor.
    /// Passes the location in window coordinates, and the window size.
    var validZone: ((CGPoint, CGSize) -> Bool)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var accumulatedX: CGFloat = 0
    private var committed = false
    private var lastTimestamp: TimeInterval = -1

    /// Distance in points the user must swipe to commit the action
    private let triggerDistance: CGFloat = 60.0

    func start() {
        stop()
        let scroll: (NSEvent) -> Void = { [weak self] event in self?.handleScroll(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            scroll(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { event in
            scroll(event)
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        reset()
    }

    private func reset() {
        accumulatedX = 0
        committed = false
        lastTimestamp = -1
    }

    private func handleScroll(_ event: NSEvent) {
        // Prevent duplicate events
        guard lastTimestamp != event.timestamp else { return }
        lastTimestamp = event.timestamp
        
        // Ignore pure momentum events to prevent "momentum ghosting"
        if event.momentumPhase.contains(.changed) { return }

        // End of swipe gesture
        if event.phase.contains(.ended) || event.momentumPhase.contains(.ended) {
            if !committed && abs(accumulatedX) > 0 {
                onCancel()
            }
            reset()
            return
        }

        // Spatial Gating
        if let window = event.window, let validZone = validZone {
            let location = event.locationInWindow
            let size = window.frame.size
            if !validZone(location, size) {
                return
            }
        }

        // Only track if the gesture is predominantly horizontal
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy), abs(dx) > 0.1 else { return }

        accumulatedX += dx
        
        guard !committed else { return }
        
        // Report progress for interactive pan
        onProgress(accumulatedX)

        if accumulatedX > triggerDistance {
            committed = true
            onCommit(true) // Swiped right
        } 
        else if accumulatedX < -triggerDistance {
            committed = true
            onCommit(false) // Swiped left
        }
    }
}
