//
//  NotchGestures.swift
//  Nodee
//
//  Trackpad gestures that drive the Notch panel, kept apart from the AppKit
//  panel plumbing so the contract is easy to read:
//
//    • Two-finger swipe DOWN while hovering the Notch     → expand the canvas.
//    • Two/three-finger swipe UP over the bottom grabber  → condense to the Notch.
//
//  The open gesture is a global scroll monitor (the window isn't key while
//  condensed, so it can't rely on the responder chain). The condense gesture
//  reads raw multitouch from the panel's content view, which is first responder
//  while expanded — but only acts while the pointer is over the bottom grabber
//  (a state the SwiftUI `GrabberHandle` publishes). Gating there keeps it clear
//  of the system's own multi-finger gestures and the two-finger canvas pan.
//  Both gestures are intentional, gradual, and report live progress so the
//  surface can stretch under the finger before it commits.
//

import AppKit

// MARK: - Open gesture (two-finger swipe down + hover)

/// Watches two-finger scroll globally and reports hover + downward intent over
/// the Notch hit area. All callbacks fire on the main actor.
@MainActor
final class NotchOpenGestureMonitor {
    /// Whether the open gesture should be tracked right now (i.e. condensed).
    var shouldTrack: () -> Bool = { true }
    /// Whether the Notch is concealed (external display / fullscreen). When true
    /// the hover/dwell hit area tightens to the bare Notch so merely skimming the
    /// top-centre never auto-opens — the gesture only engages directly over it.
    var isConcealed: () -> Bool = { false }
    var onHoverChange: (Bool) -> Void = { _ in }
    var onProgress: (CGFloat) -> Void = { _ in }
    var onCommit: () -> Void = {}

    private var scrollMonitors: [Any] = []
    private var hoverMonitors: [Any] = []
    private var accumulated: CGFloat = 0
    private var committed = false
    private var lastTimestamp: TimeInterval = -1
    private var isHovering = false

    // Dwell-to-open: resting the cursor over the Notch fills `onProgress` over
    // `Theme.holdToOpenDuration` and commits, a swipe-free second way in.
    private var holdTimer: Timer?
    private var holdStart: TimeInterval = 0

    func start() {
        stop()
        // Local + global so the gesture works whether or not Nodee is frontmost.
        let scroll: (NSEvent) -> Void = { [weak self] event in self?.handleScroll(event) }
        scrollMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { scroll($0) },
            NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { scroll($0); return $0 }
        ].compactMap { $0 }

        let hover: (NSEvent) -> Void = { [weak self] _ in self?.refreshHover() }
        hoverMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { hover($0) },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { hover($0); return $0 }
        ].compactMap { $0 }
    }

    func stop() {
        (scrollMonitors + hoverMonitors).forEach { NSEvent.removeMonitor($0) }
        scrollMonitors.removeAll()
        hoverMonitors.removeAll()
        cancelHold(resettingProgress: false)
        reset()
        setHover(false)
    }

    private func reset() {
        accumulated = 0
        committed = false
        lastTimestamp = -1
        onProgress(0)
    }

    // MARK: - Dwell-to-open

    private func startHold() {
        guard holdTimer == nil, !committed, shouldTrack() else { return }
        holdStart = Date().timeIntervalSinceReferenceDate
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickHold() }
        }
    }

    private func tickHold() {
        guard !committed, shouldTrack() else { cancelHold(); return }
        let elapsed = Date().timeIntervalSinceReferenceDate - holdStart
        let t = min(CGFloat(elapsed / Theme.holdToOpenDuration), 1)
        // easeOut cubic: snappy initial response that decelerates into the commit,
        // so the notch reacts within the first ~200 ms instead of growing linearly.
        let progress = 1 - pow(1 - t, 3)
        onProgress(progress)
        if t >= 1 {
            committed = true
            cancelHold(resettingProgress: false)
            onCommit()
        }
    }

    /// Stop the dwell timer. By default this springs the notch back to rest; pass
    /// `false` when the caller is committing or tearing down and owns the reset.
    private func cancelHold(resettingProgress: Bool = true) {
        guard holdTimer != nil else { return }
        holdTimer?.invalidate()
        holdTimer = nil
        if resettingProgress && !committed { onProgress(0) }
    }

    private func currentGeometry() -> NotchGeometry? {
        guard let screen = NotchGeometry.activeScreen() else { return nil }
        return NotchGeometry(screen: screen)
    }

    private func cursorIsOverNotch() -> Bool {
        guard let geometry = currentGeometry() else { return false }
        let hitArea = isConcealed() ? geometry.notchActivateRect : geometry.hoverTargetRect
        return hitArea.contains(NSEvent.mouseLocation)
    }

    private func setHover(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
        onHoverChange(value)
        // Dwell starts the moment the cursor enters; leaving the area aborts it
        // and clears any committed/accumulated state so the next entry is fresh.
        if value {
            startHold()
        } else {
            cancelHold()
            accumulated = 0
            committed = false
        }
    }

    private func refreshHover() {
        guard shouldTrack() else { setHover(false); return }
        setHover(cursorIsOverNotch())
    }

    private func handleScroll(_ event: NSEvent) {
        // The same physical event can reach both monitors; de-dupe by timestamp.
        guard lastTimestamp != event.timestamp else { return }
        lastTimestamp = event.timestamp

        guard shouldTrack() else { reset(); return }

        let overNotch = cursorIsOverNotch()
        setHover(overNotch)

        if event.phase.contains(.ended) || event.momentumPhase.contains(.ended) {
            if !committed { onProgress(0) }
            reset()
            return
        }

        guard overNotch else { return }

        // Natural scrolling: a downward two-finger swipe yields positive Y.
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.2 else { return }
        // A deliberate swipe takes over from the dwell so they don't fight over
        // `onProgress`; the scroll accumulator drives the fill from here.
        cancelHold(resettingProgress: false)
        accumulated = delta > 0 ? accumulated + delta : max(0, accumulated + delta)

        let progress = min(accumulated / Theme.openGestureDistance, 1)
        onProgress(progress)

        if !committed && progress >= 1 {
            committed = true
            onCommit()
        }
    }
}

// MARK: - Condense gesture (two/three-finger swipe up over the grabber)

/// Hosts the SwiftUI surface and reads raw multitouch to detect a deliberate
/// upward swipe with two or three fingers. Indirect (trackpad) touches arrive
/// via the responder chain, so this view is made first responder while
/// expanded. The swipe only condenses while `shouldAllowCondense` is true — set
/// to "the pointer is over the bottom grabber" — so it never collides with the
/// system's multi-finger gestures or the two-finger canvas pan.
final class NotchGestureView: NSView {
    /// Fires once when a qualifying upward swipe crosses the commit threshold.
    var onCondense: (() -> Void)?

    /// Gate: only honor the upward swipe while this returns true (pointer over
    /// the grabber). Defaults closed so the gesture is inert until wired.
    var shouldAllowCondense: () -> Bool = { false }

    /// Finger counts that may drive a condense over the grabber.
    private static let condenseTouchCounts: Set<Int> = [2, 3]

    // Condense — upward 2/3-finger swipe over the grabber.
    private var condenseTracking = false
    private var condenseFired = false
    private var condenseStartY: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    /// Let clicks fall through everywhere the SwiftUI surface is transparent, so
    /// the full-width host window never blocks the screen — "nunca no caminho".
    /// Only the rendered Notch / canvas (the hosting subview) captures the mouse.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    private func averageY(_ touches: Set<NSTouch>) -> CGFloat {
        guard !touches.isEmpty else { return 0 }
        return touches.reduce(0) { $0 + $1.normalizedPosition.y } / CGFloat(touches.count)
    }

    private func averageX(_ touches: Set<NSTouch>) -> CGFloat {
        guard !touches.isEmpty else { return 0 }
        return touches.reduce(0) { $0 + $1.normalizedPosition.x } / CGFloat(touches.count)
    }

    private func update(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        updateCondense(touches)
    }

    /// Upward 2/3-finger swipe over the grabber ⇒ condense to the Notch.
    private func updateCondense(_ touches: Set<NSTouch>) {
        guard shouldAllowCondense(), Self.condenseTouchCounts.contains(touches.count) else {
            condenseTracking = false
            condenseFired = false
            return
        }
        let y = averageY(touches)
        if !condenseTracking {
            condenseTracking = true
            condenseFired = false
            condenseStartY = y
            return
        }
        // normalizedPosition is bottom-left origin, so upward swipe ⇒ y grows.
        guard !condenseFired, y - condenseStartY > Theme.condenseGestureTravel else { return }
        condenseFired = true
        onCondense?()
    }

    override func touchesBegan(with event: NSEvent) { update(with: event) }
    override func touchesMoved(with event: NSEvent) { update(with: event) }

    override func touchesEnded(with event: NSEvent) {
        condenseTracking = false; condenseFired = false
    }

    override func touchesCancelled(with event: NSEvent) {
        condenseTracking = false; condenseFired = false
    }
}
