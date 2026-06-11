//
//  BrowserRootView.swift
//  Nodee
//
//  Composes the file browser shown inside the Notch panel: the toolbar on top,
//  the active surface (List or Columns) below, and — in List mode — the
//  contextual side preview. Owns the keyboard shortcuts that make it feel native
//  (space = Quick Look, ⌘⌫ = trash, ⌘D/⌘C/⌘V, ⌘⇧N = new folder).
//

import SwiftUI
import AppKit

struct BrowserRootView: View {
    @Bindable var vm: BrowserViewModel
    @Environment(PanelPresentation.self) private var presentation
    let panelWidth: CGFloat
    var notchInset: CGFloat = 0

    // The Notch panel keeps `NotchGestureView` as first responder (it needs it to
    // hear the three-finger condense), so SwiftUI's `.onKeyPress` never receives
    // keys. We read the keyboard through a local event monitor instead.
    @State private var keyMonitor: Any?

    // Two-finger horizontal swipe zones:
    //   • Sidebar strip (left)  → show/hide the Projects sidebar.
    //   • Preview strip (right) → show/hide the Preview pane (List mode only).
    //   • Middle (browser)      → folder-depth navigation (List mode only).
    // Zones are non-overlapping, so the three actions never conflict.
    @State private var sidebarGestureMonitor = ZoneGestureMonitor()
    @State private var previewGestureMonitor = ZoneGestureMonitor()
    @State private var navGestureMonitor = ZoneGestureMonitor()

    var body: some View {
        HStack(spacing: 0) {
            browserColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if vm.displayMode == .list, let file = vm.selectedFile, vm.isPreviewVisible {
                PaneDivider(paneSide: .trailing, onCollapse: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        vm.previewPanOffset = 0
                        vm.isPreviewVisible = false
                    }
                })
                PreviewPane(file: file, width: Theme.previewWidth(panelWidth: panelWidth))
                    .offset(x: max(0, vm.previewPanOffset))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // Right invitation strip — visible in List mode when the preview is hidden,
        // signals that a leftward swipe reveals it.
        .overlay(alignment: .trailing) {
            if vm.displayMode == .list, !vm.isPreviewVisible {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.10), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 12)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPreviewVisible)
            }
        }
        .background(Theme.canvasBackground)
        .onAppear {
            installKeyMonitor()

            // The three-finger panel swipe (read by the panel controller) toggles
            // the Preview through this hook — the controller can't reach the VM.
            presentation.setPreviewVisible = { visible in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    vm.previewPanOffset = 0
                    vm.isPreviewVisible = visible
                }
            }

            // Sidebar strip: swipe right reveals, swipe left hides.
            sidebarGestureMonitor.validZone = { location, windowSize in
                let screenWidth = windowSize.width
                let containerMinX = (screenWidth - panelWidth) / 2
                let relativeX = location.x - containerMinX
                return relativeX >= 0 && relativeX < Theme.sidebarWidth(panelWidth: panelWidth)
            }
            sidebarGestureMonitor.onCommit = { swipeRight in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    presentation.isSidebarCollapsed = !swipeRight
                }
            }
            sidebarGestureMonitor.start()

            // Preview strip: swipe left reveals, swipe right hides (List mode only).
            previewGestureMonitor.validZone = { location, windowSize in
                guard vm.displayMode == .list else { return false }
                let screenWidth = windowSize.width
                let containerMinX = (screenWidth - panelWidth) / 2
                let relativeX = location.x - containerMinX
                let previewEdge = panelWidth - Theme.previewWidth(panelWidth: panelWidth)
                return relativeX >= previewEdge && relativeX <= panelWidth
            }
            previewGestureMonitor.onCommit = { swipeRight in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    vm.previewPanOffset = 0
                    vm.isPreviewVisible = !swipeRight
                }
            }
            previewGestureMonitor.start()

            // Middle browser strip: folder-depth navigation (List mode only).
            navGestureMonitor.validZone = { location, windowSize in
                guard vm.displayMode == .list else { return false }
                let screenWidth = windowSize.width
                let containerMinX = (screenWidth - panelWidth) / 2
                let relativeX = location.x - containerMinX
                let sidebarEdge = Theme.sidebarWidth(panelWidth: panelWidth)
                let previewEdge = panelWidth - Theme.previewWidth(panelWidth: panelWidth)
                return relativeX >= sidebarEdge && relativeX <= previewEdge
            }
            navGestureMonitor.onCommit = { swipeRight in
                // Left drills into the selected folder; right climbs to the parent.
                swipeRight ? vm.navigateShallower() : vm.navigateDeeper()
            }
            navGestureMonitor.start()
        }
        .onDisappear {
            removeKeyMonitor()
            sidebarGestureMonitor.stop()
            previewGestureMonitor.stop()
            navGestureMonitor.stop()
            presentation.setPreviewVisible = nil
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.selectedFile?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.displayMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPreviewVisible)
    }

    /// Fixed heights that make up the header band above the scrolling content.
    private let toolbarHeight: CGFloat = 38
    private let columnsHeaderHeight: CGFloat = 25 // FileColumnsHeader (24) + divider (1)

    /// The main browser column: content scrolling edge-to-edge behind a header
    /// (toolbar — plus the column header in List mode) and a footer, both fading
    /// the content out with a progressive blur so they stay legible.
    private var browserColumn: some View {
        let listMode = vm.displayMode == .list
        let headerHeight = notchInset + toolbarHeight + (listMode ? columnsHeaderHeight : 0)
        let footerHeight = Theme.footerBlurHeight

        return ZStack(alignment: .top) {
            surface(topInset: headerHeight, bottomInset: footerHeight)

            // Header: a solid absolute-black bar (toolbar + column header). Content
            // scrolls up and vanishes behind it — pure #000000, no grey material.
            VStack(spacing: 0) {
                BrowserToolbar(vm: vm, topInset: notchInset)
                if listMode {
                    FileColumnsHeader()
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
            .background(Theme.panelBackground)

            // Footer overlay: blurs the rows behind it and dissolves them into black
            // above the grabber (the grabber is drawn on top, by PanelRootView).
            ProgressiveBlur(height: footerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func surface(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        switch vm.displayMode {
        case .list:    FileListView(vm: vm, topInset: topInset, bottomInset: bottomInset)
        case .columns: ColumnsView(vm: vm, topInset: topInset, bottomInset: bottomInset)
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event // nil = consumed (no system beep)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
    }

    /// Returns true when the key was handled (and should be swallowed).
    private func handleKey(_ event: NSEvent) -> Bool {
        // Let any active text editor (inline rename) own the keyboard.
        if vm.renamingURL != nil { return false }
        if event.window?.firstResponder is NSText { return false }

        let mods = event.modifierFlags
        let command = mods.contains(.command)
        let shift = mods.contains(.shift)
        let option = mods.contains(.option)

        // Arrows and bare keys (only when no ⌘, so shortcuts below don't clash).
        if !command {
            switch event.keyCode {
            case 126: shift ? vm.extendSelection(by: -1) : vm.moveSelection(by: -1); return true // up
            case 125: shift ? vm.extendSelection(by: 1)  : vm.moveSelection(by: 1);  return true // down
            case 124: vm.drillSelection();      return true  // right
            case 123: vm.undrillSelection();    return true  // left
            case 49:  QuickLookCoordinator.shared.toggle(Array(vm.selection)); return true // space
            case 36, 76: if let file = vm.selectedFile { vm.open(file) }; return true       // return / enter
            default: return false
            }
        }

        // ⌘ shortcuts.
        if event.keyCode == 51 { vm.trashSelection(); return true } // ⌘⌫ (delete)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p" where shift: vm.isPreviewVisible.toggle(); return true
        case "d": vm.duplicateSelection(); return true
        case "c" where option: vm.copyPath(); return true
        case "c": vm.copySelection(); return true
        case "v": vm.paste(); return true
        case "r": vm.revealInFinder(); return true
        // Check ⇧ first so ⌘Z (undo) doesn't swallow ⌘⇧Z (redo).
        case "z" where shift: vm.redo(); return true
        case "z": vm.undo(); return true
        // Check ⇧ first so ⌘N (new file) doesn't swallow ⌘⇧N (new folder).
        case "n" where shift: vm.newFolder(); return true
        case "n": vm.newFile(); return true
        default: return false
        }
    }
}
