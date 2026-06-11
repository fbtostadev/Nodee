//
//  DragRevealMonitor.swift
//  Nodee
//
//  Watches for system-wide file drags and auto-reveals the Notch panel when the
//  cursor enters the Notch hover zone while dragging. This makes Nodee a natural
//  drop target: start dragging a file anywhere (Finder, Desktop, Xcode) and move
//  toward the top of the screen — the panel slides out to receive it, no shortcut
//  or gesture needed.
//
//  The reveal is gated behind a short dwell (`Theme.dragRevealDelay`) so fast
//  drags across the top edge (e.g. repositioning a window) don't accidentally
//  open the panel. Leaving the zone cancels the timer. Once revealed during a
//  drag, a second entry into the zone won't re-trigger — the flag resets only
//  when the drag ends (mouse-up).
//

import AppKit

@MainActor
final class DragRevealMonitor {
    /// Called when the dwell commits — the controller wires this to `open()`.
    var onReveal: () -> Void = {}

    /// Gate: only track while the panel is closed. The controller sets this to
    /// `{ self?.isOpen == false }`.
    var shouldTrack: () -> Bool = { true }

    private var monitors: [Any] = []
    private var revealTimer: Timer?
    private var isDragging = false
    private var hasRevealed = false

    // MARK: - Lifecycle

    func start() {
        stop()
        // Global monitors catch drags that start in other apps (Finder, Desktop).
        // Local monitors catch drags that start inside Nodee itself (unlikely for
        // the reveal use-case, but defensive).
        let drag: (NSEvent) -> Void = { [weak self] event in self?.handleDrag(event) }
        let up:   (NSEvent) -> Void = { [weak self] event in self?.handleDragEnd(event) }

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { drag($0) },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp)      { up($0) },
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged)  { drag($0); return $0 },
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp)       { up($0); return $0 }
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        cancelTimer()
        isDragging = false
        hasRevealed = false
    }

    // MARK: - Drag tracking

    private func handleDrag(_ event: NSEvent) {
        isDragging = true
        guard shouldTrack(), !hasRevealed else {
            cancelTimer()
            return
        }

        if cursorIsInNotchZone() {
            startTimerIfNeeded()
        } else {
            cancelTimer()
        }
    }

    private func handleDragEnd(_ event: NSEvent) {
        cancelTimer()
        isDragging = false
        hasRevealed = false
    }

    // MARK: - Dwell timer

    private func startTimerIfNeeded() {
        guard revealTimer == nil else { return }
        revealTimer = Timer.scheduledTimer(
            withTimeInterval: Theme.dragRevealDelay,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitReveal() }
        }
    }

    private func commitReveal() {
        revealTimer = nil
        guard shouldTrack(), isDragging, !hasRevealed else { return }
        hasRevealed = true
        onReveal()
    }

    private func cancelTimer() {
        revealTimer?.invalidate()
        revealTimer = nil
    }

    // MARK: - Geometry

    private func cursorIsInNotchZone() -> Bool {
        guard let screen = NotchGeometry.activeScreen() else { return false }
        return NotchGeometry(screen: screen).hoverTargetRect.contains(NSEvent.mouseLocation)
    }
}
