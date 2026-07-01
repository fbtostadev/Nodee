//
//  NotchPanelController.swift
//  Nodee
//
//  Owns the NotchPanel and coordinates the emerge/retract animation with the
//  SwiftUI surface. The window stays on screen the whole session: condensed it
//  reads as the compact Notch, expanded it becomes the canvas. Open/close is
//  always intentional (gesture, shortcut, menu, or Escape) — never a
//  click-outside, so an in-flight drag is never lost.
//

import SwiftUI
import SwiftData

@MainActor
final class NotchPanelController {
    private let panel = NotchPanel()
    private let gestureView = NotchGestureView(frame: CGRect(origin: .zero, size: NotchGeometry.panelSize(for: NSScreen.main)))
    private let presentation = PanelPresentation()
    private let openMonitor = NotchOpenGestureMonitor()
    private let dragRevealMonitor = DragRevealMonitor()
    private let appState: AppState
    private let finderState: FinderState

    private var escMonitor: Any?

    /// Global + local `mouseMoved` monitors that drive the conceal/reveal peek
    /// while the Notch is hidden (external display / fullscreen).
    private var revealMonitors: [Any] = []

    var isOpen: Bool { presentation.isExpanded }

    init(appState: AppState, container: ModelContainer) {
        self.appState = appState
        self.finderState = FinderState(container: container)

        let root = PanelRootView(container: container, appState: appState, finderState: finderState)
            .environment(appState)
            .environment(presentation)
            .environment(finderState)
            .modelContainer(container)

        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        // Don't reserve the menu-bar safe area — the surface must reach the very
        // top so the notch shape aligns with the hardware notch / screen edge.
        hosting.safeAreaRegions = []

        // The gesture view is the content view (first responder while expanded,
        // so it receives raw multitouch); the SwiftUI surface rides on top.
        gestureView.frame = CGRect(origin: .zero, size: NotchGeometry.panelSize(for: NSScreen.main))
        hosting.frame = gestureView.bounds
        gestureView.addSubview(hosting)
        panel.contentView = gestureView

        gestureView.onCondense = { [weak self] in self?.close() }
        // Only honor the upward finger-swipe while the pointer is over the grabber.
        gestureView.shouldAllowCondense = { [weak self] in self?.presentation.isHoveringGrabber ?? false }
        // The SwiftUI grabber's tap / drag-up commit routes here.
        presentation.requestCondense = { [weak self] in self?.close() }
        // SwiftUI controls steal first responder on click, muting the indirect-touch
        // gestures; let the surface hand focus back to the gesture view.
        presentation.reclaimGestureFocus = { [weak self] in
            guard let self, self.isOpen else { return }
            self.panel.makeFirstResponder(self.gestureView)
        }

        configureDragRevealMonitor()

        configureOpenMonitor()
    }

    /// Reveal the persistent compact Notch and start listening for the open
    /// gesture. Called once at launch — the panel never fully hides afterwards.
    func activate() {
        positionWindow()
        panel.orderFrontRegardless()
        openMonitor.start()
        dragRevealMonitor.start()
        startRevealTracking()
        observeScreenChanges()
        observeSpaceChanges()
        updateConcealState()
    }

    // MARK: - Commands

    /// Run `work` with the Notch panel temporarily dropped below normal windows.
    /// A sandbox open/save panel is rendered out-of-process by Powerbox, which
    /// ignores the level we set on our local `NSOpenPanel` — so the only reliable
    /// way to keep it from hiding behind our always-on-top Notch is to lower the
    /// Notch itself for the duration. Restored afterward.
    func runWithPanelLowered<T>(_ work: () -> T) -> T {
        let saved = panel.level
        panel.level = .normal
        defer { panel.level = saved }
        return work()
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        positionWindow()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gestureView) // so the finger gestures are heard
        installEscapeMonitor()
        panel.level = .floating
        positionWindow()

        withAnimation(Theme.panelOpen) {
            presentation.openProgress = 0
            presentation.isExpanded = true
        }
        appState.isPanelOpen = true
    }

    func close() {
        guard isOpen else { return }
        removeEscapeMonitor()
        withAnimation(Theme.panelClose) {
            presentation.isExpanded = false
            presentation.openProgress = 0
        }
        presentation.isHoveringGrabber = false
        presentation.grabberDragProgress = 0
        appState.isPanelOpen = false
        panel.level = .statusBar
        positionWindow()
        // The window stays on screen as the compact Notch — never ordered out,
        // so the open gesture always has a target to grab. On a concealing
        // display, re-tuck it above the edge unless the pointer is still near.
        refreshReveal()
    }

    // MARK: - Open gesture wiring

    private func configureOpenMonitor() {
        openMonitor.shouldTrack = { [weak self] in self?.isOpen == false }
        openMonitor.isConcealed = { [weak self] in self?.presentation.concealsNotch ?? false }

        openMonitor.onHoverChange = { [weak self] hovering in
            guard let self, !self.isOpen else { return }
            withAnimation(Theme.notchStretch) {
                self.presentation.isHoveringNotch = hovering
            }
        }

        openMonitor.onProgress = { [weak self] progress in
            guard let self, !self.isOpen else { return }
            // Track the finger directly while dragging; spring back on release.
            if progress == 0 {
                withAnimation(Theme.notchStretch) { self.presentation.openProgress = 0 }
            } else {
                self.presentation.openProgress = progress
            }
        }

        openMonitor.onCommit = { [weak self] in self?.open() }
    }

    private func configureDragRevealMonitor() {
        dragRevealMonitor.shouldTrack = { [weak self] in self?.isOpen == false }
        dragRevealMonitor.onReveal = { [weak self] in self?.open() }
    }

    // MARK: - Geometry

    private func positionWindow() {
        guard let screen = NotchGeometry.activeScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        var frame = geometry.hostWindowFrame
        // When floating (below the menu bar), drop the window by the menu bar / notch height
        // so the top of the content doesn't sit underneath the menu bar.
        if panel.level == .floating {
            frame.origin.y -= geometry.topInset
        }
        panel.setFrame(frame, display: true)
        // Publish the resolved screen so the SwiftUI surface sizes its geometry
        // against the *same* display the host window was just placed on. This is
        // the single source of truth for "which screen" — keeping window and
        // content in sync as the panel moves between built-in and external.
        presentation.activeScreen = screen
        updateConcealState()
    }

    // MARK: - Conceal / reveal (external display + fullscreen)

    /// Decide whether the active display should hide the compact Notch until the
    /// pointer approaches: external monitors (no hardware notch) and any display
    /// whose menu bar is hidden (a fullscreen app, or auto-hide). The built-in
    /// notched display in windowed mode keeps the Notch always visible.
    private func updateConcealState() {
        guard let screen = presentation.activeScreen else { return }
        let geometry = NotchGeometry(screen: screen)
        let conceal = !geometry.hasNotch || geometry.menuBarHidden
        if presentation.concealsNotch != conceal {
            withAnimation(Theme.notchStretch) {
                presentation.concealsNotch = conceal
                // Leaving conceal mode pins it fully visible again.
                presentation.notchReveal = conceal ? 0 : 1
            }
        }
        // Whether newly concealing or already concealed, settle the peek against
        // where the pointer is right now.
        refreshReveal()
    }

    /// Match the reveal peek to the current pointer position: peeked while the
    /// cursor is in the top-centre band, tucked away otherwise. No-op while the
    /// panel isn't concealing or is expanded.
    private func refreshReveal() {
        guard presentation.concealsNotch, !isOpen else { return }
        guard let screen = NotchGeometry.activeScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        // Peek the compact Notch only while the pointer is squarely over its
        // footprint; tuck it away otherwise. No wider proximity band, so an app's
        // top chrome stays reachable in fullscreen.
        let over = geometry.notchActivateRect.contains(NSEvent.mouseLocation)
        setReveal(over ? Theme.notchNearPeek : 0)
    }

    private func setReveal(_ value: CGFloat) {
        guard presentation.notchReveal != value else { return }
        withAnimation(Theme.notchStretch) { presentation.notchReveal = value }
    }

    private func startRevealTracking() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.followCursorScreenIfNeeded()
            self?.refreshReveal()
        }
        revealMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { handler($0) },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { handler($0); return $0 }
        ].compactMap { $0 }
    }

    /// Move the compact Notch to whatever display the cursor is now on. The host
    /// window otherwise stays put on the display it was last placed on, so a peek
    /// triggered while the cursor is on another monitor would surface on the wrong
    /// screen. Only follows while condensed — never yank an open panel between
    /// displays mid-use. Repositioning also refreshes conceal state + geometry for
    /// the new screen, so the fullscreen behaviour is unchanged per display.
    private func followCursorScreenIfNeeded() {
        guard !isOpen, let cursorScreen = NotchGeometry.activeScreen() else { return }
        guard cursorScreen != presentation.activeScreen else { return }
        positionWindow()
    }

    private func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateConcealState() }
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionWindow() }
        }
    }

    // MARK: - Escape to close

    private func installEscapeMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // While editing text (e.g. inline rename), let the field editor own the
            // keyboard so Escape cancels the rename and Space types a space.
            if self.panel.firstResponder is NSTextView { return event }
            if event.keyCode == 53 { // Escape
                self.close()
                return nil
            }
            // Space, ⌘-shortcuts and the rest fall through to the SwiftUI browser
            // (Quick Look, trash, duplicate, copy/paste, new folder).
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }

}
