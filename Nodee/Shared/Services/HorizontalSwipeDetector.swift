//
//  HorizontalSwipeDetector.swift
//  Nodee
//
//  NSViewRepresentable that captures a directional swipe via
//  NSPanGestureRecognizer (velocity-based). On macOS there is no
//  NSSwipeGestureRecognizer, so a pan recognizer reading its end velocity is the
//  correct primitive. NOTE: NSGestureRecognizer only supports *direct* touches —
//  setting `.indirect` raises "Gesture recognizers do not support indirect
//  touches" and crashes, so we leave allowedTouchTypes at its default.
//

import SwiftUI
import AppKit

struct HorizontalSwipeDetector: NSViewRepresentable {
    var onSwipeLeft: (() -> Void)? = nil
    var onSwipeRight: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        view.addGestureRecognizer(pan)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipeLeft  = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
    }

    class Coordinator: NSObject {
        var onSwipeLeft: (() -> Void)?
        var onSwipeRight: (() -> Void)?

        init(onSwipeLeft: (() -> Void)?, onSwipeRight: (() -> Void)?) {
            self.onSwipeLeft  = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        @objc func panned(_ recognizer: NSPanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let velocity = recognizer.velocity(in: recognizer.view)
            guard abs(velocity.x) > abs(velocity.y) else { return }
            if velocity.x < -250 { onSwipeLeft?() }
            else if velocity.x > 250 { onSwipeRight?() }
        }
    }
}
