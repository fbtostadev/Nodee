//
//  NotchGeometry.swift
//  Nodee
//
//  Resolves where the Notch is on a given screen so the panel can be anchored
//  to it and appear to emerge from it. Falls back gracefully on screens without
//  a Notch (top-center, below the menu bar) so the app is usable while we build
//  — full no-Notch support is out of v0 scope.
//

import AppKit

struct NotchGeometry {
    let screen: NSScreen

    /// Height of the menu bar / notch region at the top of the screen.
    var topInset: CGFloat {
        let safeArea = screen.safeAreaInsets.top
        return safeArea > 0 ? safeArea : (screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// Width of the physical notch, 0 on screens without one.
    var notchWidth: CGFloat {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, screen.frame.width - left.width - right.width)
    }

    var hasNotch: Bool { notchWidth > 0 && topInset > 0 }

    /// Expanded panel size for this screen. Sized so its area is a fixed slice of
    /// the display (`Theme.panelScreenAreaFraction`) while keeping the canonical
    /// aspect ratio. Bigger displays get a proportionally bigger panel, but it
    /// never balloons to dominate the screen the way the old fixed size did.
    /// Horizontal centring over the physical notch is handled by the full-width
    /// host window + top-centre content alignment, so this is just the footprint.
    var panelSize: CGSize {
        let ratio = Theme.panelAspectRatio                       // width / height
        let targetArea = screen.frame.width * screen.frame.height * Theme.panelScreenAreaFraction
        let height = (targetArea / ratio).squareRoot()
        let width = height * ratio
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// Convenience for code paths that only have a screen (or none) at hand —
    /// e.g. window/content placeholders created before the active screen is known.
    static func panelSize(for screen: NSScreen?) -> CGSize {
        guard let screen else { return Theme.panelReferenceSize }
        return NotchGeometry(screen: screen).panelSize
    }

    /// Uniform scale of this screen's panel relative to the reference size. Used
    /// to keep chrome that's authored at reference scale (corner radii, strokes)
    /// visually proportional on the resized panel.
    var panelScale: CGFloat { panelSize.width / Theme.panelReferenceSize.width }

    /// Base width when closed (the physical notch width or pill width)
    var closedWidth: CGFloat {
        hasNotch ? notchWidth : 160
    }
    
    /// Base height when closed (the physical notch height or pill height)
    var closedHeight: CGFloat {
        hasNotch ? topInset : 32
    }

    /// Rect of the notch (or the anchor region on non-notch screens), in screen
    /// coordinates (origin bottom-left).
    var anchorRect: CGRect {
        let width = closedWidth
        let height = max(closedHeight, 32)
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Hover/scroll hit area for the open gesture, in screen coordinates. A bit
    /// wider and taller than the bare notch so a two-finger swipe that "kisses"
    /// the top edge near the Notch reliably triggers, without false opens from
    /// far out on the menu bar.
    ///
    /// The rect overshoots the top of the screen by `topOvershoot`: `CGRect`
    /// contains is half-open at `maxY`, so without it a cursor parked on the very
    /// top row (`mouseLocation.y == screen.frame.maxY`) would fall in a deadzone
    /// and miss the gesture. Pushing `maxY` above the physical edge keeps that
    /// top row strictly inside.
    var hoverTargetRect: CGRect {
        let topOvershoot: CGFloat = 8
        let width = closedWidth + 96
        let height = max(closedHeight, 24) + 18 + topOvershoot
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height + topOvershoot,
            width: width,
            height: height
        )
    }

    /// Frame for the large transparent host window. The window is pinned to the
    /// very top of the screen (its top edge sits on `screen.frame.maxY`) and
    /// spans the full screen width, so the SwiftUI content — anchored top-center
    /// — lands its compact notch exactly over the hardware notch and has room to
    /// expand without ever being clipped. Height covers the expanded panel plus
    /// headroom for the drop shadow and the open "stretch" overshoot.
    var hostWindowFrame: CGRect {
        let height = panelSize.height + Theme.panelHostVerticalHeadroom
        return CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
    }

    /// The *only* region that peeks the concealed Notch out: a thin strip pinned
    /// to the very top edge, the Notch's own width. The Notch reacts only when the
    /// pointer is pressed all the way up against the top limit of the screen — so
    /// an app's top chrome (tabs, toolbars) stays fully reachable in fullscreen.
    ///
    /// The strip overshoots the top edge by `topOvershoot`: `CGRect.contains` is
    /// half-open at `maxY`, so without it a cursor parked on the very top row
    /// (`mouseLocation.y == screen.frame.maxY`) would miss the strip.
    var notchActivateRect: CGRect {
        let topOvershoot: CGFloat = 8
        let band: CGFloat = 4
        let width = closedWidth
        let height = band + topOvershoot
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - band,
            width: width,
            height: height
        )
    }

    /// Whether the menu bar is currently hidden on this screen — true while a
    /// fullscreen app owns the space (or the system menu bar is set to
    /// auto-hide). In windowed mode the menu bar reserves a strip at the top so
    /// `visibleFrame.maxY` sits below `frame.maxY`; fullscreen collapses it,
    /// bringing the two flush.
    var menuBarHidden: Bool {
        screen.frame.maxY - screen.visibleFrame.maxY < 1
    }

    /// Screen the pointer is currently on, falling back to the main screen.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
