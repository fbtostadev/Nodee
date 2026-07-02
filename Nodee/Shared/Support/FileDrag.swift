//
//  FileDrag.swift
//  Nodee
//
//  Native, outward file dragging — done through AppKit, not SwiftUI's `.onDrag`.
//
//  Why not `.onDrag`: whatever we register as `public.file-url` (file
//  representation, registerItem, even raw data), SwiftUI pre-materializes a temp
//  copy under `…/Containers/<app>/…/Caches/com.apple.SwiftUI.Drag-<UUID>/` and
//  hands the target *that* path. Path-pasting targets (Terminal, shells, editors)
//  then get the throwaway copy instead of the real file.
//
//  So we run the drag ourselves: `beginDraggingSession` with an `NSPasteboardItem`
//  whose `public.file-url` is the URL's *string*. That's a plain pasteboard value,
//  not a file promise — nothing is materialized, and the target receives the real
//  on-disk path. The in-app `dropDestination(for: URL.self)` (move between folders)
//  still reads it as a URL.
//
//  Sandbox note: vending a path isn't a filesystem op by Nodee, so it doesn't go
//  through the sandbox. The receiving process opens the file with the user's own
//  rights. No extra entitlement or per-file security scope is needed.
//
//  Coexisting with SwiftUI: the drag view sits as an overlay but its `hitTest`
//  only claims *left-button* events. Right-click (context menu), scroll, and hover
//  fall through to the SwiftUI row underneath. Because the overlay swallows the
//  left click, selection/open — previously `.onTapGesture` — are forwarded back
//  through `onClick`. During an inline rename the overlay goes inert so the text
//  field gets its clicks.
//

import SwiftUI
import AppKit

/// A resolved left-click forwarded from the AppKit drag layer.
struct DragClick {
    /// `NSEvent.clickCount` — 1 for a single click, 2 for a double click.
    let count: Int
    let shift: Bool
    let command: Bool
}

extension View {
    /// Makes the view draggable as real files out of the app, and forwards the
    /// left clicks the drag layer intercepts back to `onClick`.
    /// - Parameters:
    ///   - isRenaming: when true the layer is inert so an inline editor works.
    ///   - dragItems: the files to drag, resolved when the drag begins. Return the
    ///     whole selection when this row is part of it, else just this row.
    ///   - onClick: selection/open handler (replaces `.onTapGesture`).
    func fileDrag(
        isRenaming: Bool = false,
        dragItems: @escaping () -> [URL],
        onClick: @escaping (DragClick) -> Void
    ) -> some View {
        overlay(FileDragLayer(isRenaming: isRenaming, dragItems: dragItems, onClick: onClick))
    }
}

private struct FileDragLayer: NSViewRepresentable {
    let isRenaming: Bool
    let dragItems: () -> [URL]
    let onClick: (DragClick) -> Void

    func makeNSView(context: Context) -> FileDragView {
        let view = FileDragView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: FileDragView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: FileDragView) {
        view.isRenaming = isRenaming
        view.dragItems = dragItems
        view.onClick = onClick
    }
}

/// Left-button-only interaction layer: starts a real-file drag, otherwise reports
/// the click. Transparent to everything else so SwiftUI keeps its behaviour.
private final class FileDragView: NSView, NSDraggingSource {
    var isRenaming = false
    var dragItems: (() -> [URL])?
    var onClick: ((DragClick) -> Void)?

    private var mouseDownAt: NSPoint?
    private var didStartDrag = false
    // The Notch panel keeps its gesture view as first responder (for the
    // three-finger condense). Our click steals it; capture it on mouse-down and
    // hand it back after a click so that gesture keeps being heard.
    private weak var priorResponder: NSResponder?

    // The Notch floats above other apps without activating Nodee, so when it opens
    // over a windowed (non-fullscreen) app that app stays the active one. Without
    // this, the first click into a row would be treated as a mere window-activation
    // click and swallowed — the folder wouldn't open and the panel felt frozen.
    // Acting on the first mouse makes clicks work immediately, exactly as they
    // already did over a fullscreen app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Claim only left-button events; let right-click, scroll, and hover fall
    // through to the SwiftUI row underneath. Inert while renaming.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isRenaming { return nil }
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        priorResponder = window?.firstResponder
        mouseDownAt = event.locationInWindow
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let origin = mouseDownAt else { return }
        let dx = event.locationInWindow.x - origin.x
        let dy = event.locationInWindow.y - origin.y
        guard (dx * dx + dy * dy) > 16 else { return } // ~4pt slop before dragging
        didStartDrag = true
        beginFileDrag(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownAt = nil }
        guard !didStartDrag else { return } // a drag consumed the gesture
        let flags = event.modifierFlags
        onClick?(DragClick(
            count: event.clickCount,
            shift: flags.contains(.shift),
            command: flags.contains(.command)
        ))
        restoreFocusAfterClick()
    }

    /// Return first responder to whoever held it before the click (the Notch
    /// gesture view), so the three-finger condense keeps being heard. Deferred so
    /// SwiftUI finishes its own selection pass first.
    private func restoreFocusAfterClick() {
        guard let prior = priorResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.firstResponder !== prior else { return }
            window.makeFirstResponder(prior)
        }
    }

    private func beginFileDrag(event: NSEvent) {
        let urls = dragItems?() ?? []
        guard !urls.isEmpty else { return }

        // One dragging item per file. Each carries the file URL as a plain
        // pasteboard string — no file promise, so nothing is copied; targets read
        // the real on-disk paths. AppKit badges the stack with the count.
        let draggingItems: [NSDraggingItem] = urls.enumerated().map { index, fileURL in
            let item = NSPasteboardItem()
            item.setString(fileURL.absoluteString, forType: .fileURL)

            let dragItem = NSDraggingItem(pasteboardWriter: item)
            let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
            icon.size = NSSize(width: 32, height: 32)
            // Fan the icons into a slight stack so a multi-drag reads as a pile.
            let offset = CGFloat(min(index, 4)) * 4
            dragItem.setDraggingFrame(
                NSRect(x: bounds.midX - 16 + offset, y: bounds.midY - 16 - offset,
                       width: 32, height: 32),
                contents: icon
            )
            return dragItem
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Inside the app, allow the move-between-folders drop; outside, copy.
        context == .outsideApplication ? .copy : [.move, .copy, .generic]
    }
}
