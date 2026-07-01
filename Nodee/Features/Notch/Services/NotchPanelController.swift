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

    private var escMonitor: Any?

    /// Last menu-bar / notch height measured while not fullscreen. Used to drop the
    /// window by a reliable amount on a fullscreen display, where `safeAreaInsets`
    /// (and thus `topInset`) can collapse to 0.
    private var lastTopInset: CGFloat = 0

    /// Global + local `mouseMoved` monitors that drive the conceal/reveal peek
    /// while the Notch is hidden (external display / fullscreen).
    private var revealMonitors: [Any] = []

    var isOpen: Bool { presentation.isExpanded }

    init(appState: AppState, container: ModelContainer) {
        self.appState = appState

        let root = PanelRootView(container: container, appState: appState)
            .environment(appState)
            .environment(presentation)
            .modelContainer(container)

        // FirstMouse hosting so SwiftUI controls (sidebar Favoritos/Locais taps,
        // toolbar buttons) act on the very first click even though the Notch floats
        // above other apps without activating Nodee. Over a windowed app that app
        // stays active, so without this the first click would be eaten as a mere
        // window-activation click and the tap would be lost — the "freeze".
        let hosting = FirstMouseHostingView(rootView: root)
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

    /// A sandbox open/save panel is rendered out-of-process by Powerbox, which
    /// ignores the level we set on our local `NSOpenPanel` — so the only reliable
    /// way to keep it from hiding behind our floating Notch is to lower the Notch
    /// itself for the duration. Use `lowerPanelLevel()` before showing the picker
    /// and `restorePanelLevel()` when it dismisses; for synchronous callers the
    /// `runWithPanelLowered` wrapper does both around `work`.
    private var savedPanelLevel: NSWindow.Level?

    func lowerPanelLevel() {
        guard savedPanelLevel == nil else { return }
        savedPanelLevel = panel.level
        panel.level = .normal
    }

    func restorePanelLevel() {
        guard let saved = savedPanelLevel else { return }
        panel.level = saved
        savedPanelLevel = nil
    }

    func runWithPanelLowered<T>(_ work: () -> T) -> T {
        lowerPanelLevel()
        defer { restorePanelLevel() }
        return work()
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        // `isOpen` is still false here (it flips with the animation below), so tell
        // `positionWindow` we're opening — a fullscreen display must drop the window
        // below the menu bar for the expanded canvas.
        positionWindow(expanded: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gestureView) // so the finger gestures are heard
        installEscapeMonitor()
        positionWindow(expanded: true)

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

    /// Place the host window for the active screen. `expanded` says whether the
    /// panel is (about to be) open; it defaults to the live `isOpen` for the
    /// callers that just react to display/space changes. It matters only on a
    /// fullscreen display, where the window drops below the menu bar *only while
    /// expanded* (see below).
    private func positionWindow(expanded: Bool? = nil) {
        guard let screen = NotchGeometry.activeScreen() else { return }
        let willExpand = expanded ?? isOpen
        let geometry = NotchGeometry(screen: screen)
        // Detect a fullscreen app via the window list, NOT `menuBarHidden`: the
        // latter flips to false the instant the menu bar auto-reveals (cursor at
        // the top to open the Notch), which made the drop never apply.
        let fullscreen = geometry.hasFullscreenWindow
        // Over the menu bar (reaching the hardware notch) when no app is fullscreen —
        // both closed and expanded — so the canvas grows seamlessly out of the
        // physical notch. `.floating` on a fullscreen display so the system menu bar
        // renders above us and stays clickable. Don't clobber a temporarily lowered
        // level (file picker).
        //
        // The one thing that must never happen at `.statusBar` is presenting a system
        // open/save picker (Powerbox) behind us — that wedged the app. Folder access
        // is therefore granted up front in the dedicated onboarding window (a normal
        // window, not this panel), so no picker is ever shown over the Notch.
        let level: NSWindow.Level = fullscreen ? .floating : .statusBar
        if savedPanelLevel == nil {
            panel.level = level
        } else {
            savedPanelLevel = level
        }
        if geometry.topInset > 0 { lastTopInset = geometry.topInset }
        var frame = geometry.hostWindowFrame
        // On a fullscreen app's display, drop the whole window by the menu-bar
        // height so the *expanded* Notch starts below the menu bar — leaving the
        // black menu-bar strip uncovered and every menu reachable. Only while
        // expanded: closed, the window stays pinned to the top so the concealed
        // compact Notch tucks into the hardware island and peeks from there. On a
        // normal (non-fullscreen) display we do NOT drop: the `.floating` canvas
        // reaches the very top and grows seamlessly out of the hardware notch, with
        // the menu bar (above us in z-order) resting over its top strip. `topInset`
        // is 0 in fullscreen, so prefer the last inset measured while windowed and
        // fall back to a robust height that survives the menu bar collapsing.
        //
        // Only on a display with a *hardware* notch: there the drop keeps the menu
        // bar reachable beside the island. On a notch-less external display there's
        // no island to tuck under, so dropping just leaves the expanded canvas
        // floating below the top edge (a visible gap over a fullscreen app). Keep it
        // pinned to the top instead, so it reads as anchored to the top edge.
        if fullscreen, willExpand, geometry.hasNotch {
            let reserved = screen.frame.maxY - screen.visibleFrame.maxY
            let drop = reserved > 1 ? reserved : (lastTopInset > 0 ? lastTopInset : geometry.menuBarHeight)
            frame.origin.y -= drop
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
    /// pointer approaches: external monitors (no hardware notch), a display whose
    /// menu bar is hidden (auto-hide), and any display running a fullscreen app.
    /// The built-in notched display in windowed mode keeps the Notch always
    /// visible, over the menu bar — so the user sees it and can open it by resting
    /// on the notch.
    ///
    /// A fullscreen app conceals it too: the closed Notch then tucks into the
    /// hardware island and only peeks/opens when the cursor is squarely over the
    /// physical notch strip (`notchActivateRect`), so the fullscreen app's own top
    /// chrome and the menu bar stay reachable — same feel as a windowed notch.
    /// `menuBarHidden` alone can't catch this: with "hide menu bar in full screen"
    /// off it reads false, so we OR in `hasFullscreenWindow`.
    private func updateConcealState() {
        guard let screen = presentation.activeScreen else { return }
        let geometry = NotchGeometry(screen: screen)
        let conceal = !geometry.hasNotch || geometry.menuBarHidden || geometry.hasFullscreenWindow
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
        // footprint (the physical island on a notched display, else a thin top
        // strip); tuck it away otherwise. No wider proximity band, so an app's
        // top chrome stays reachable in fullscreen.
        let over = geometry.concealActivateRect.contains(NSEvent.mouseLocation)
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
            // Entering/leaving a fullscreen space flips the window level
            // (.statusBar ↔ .floating) and the conceal state, so reposition.
            MainActor.assumeIsolated { self?.positionWindow() }
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

/// Hosts the SwiftUI surface and lets its controls act on the first click even
/// while Nodee isn't the active app (the Notch floats over other apps without
/// activating). Returning `true` here routes that first click straight to the
/// SwiftUI hit target instead of consuming it as a window-activation click.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
