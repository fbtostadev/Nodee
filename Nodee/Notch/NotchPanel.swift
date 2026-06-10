//
//  NotchPanel.swift
//  Nodee
//
//  Borderless, non-activating floating panel that hosts the SwiftUI UI. It
//  joins all Spaces and floats above other apps without taking over the screen
//  — "sempre presente, nunca no caminho". The menu bar stays visible.
//

import AppKit

final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: NotchGeometry.panelSize(for: NSScreen.main)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above the menu bar so the panel reaches the very top of the screen and
        // sits over / inside the hardware notch. `.floating` renders *below* the
        // menu bar, which pushed the notch shape a menu-bar height too low. The
        // content view's hit-test lets clicks fall through transparent areas, so
        // the menu bar stays interactive on either side of the notch.
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the SwiftUI surface draws its own shadow
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    // Must be able to take key focus to receive Escape / typing, but never
    // becomes the main window of the (agent) app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
