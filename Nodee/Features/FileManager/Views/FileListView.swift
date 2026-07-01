//
//  FileListView.swift
//  Nodee
//
//  The List surface: the current directory's contents as a flat, indented list
//  with in-place disclosure triangles (Finder list view). Single-click selects,
//  double-click enters a folder / opens a file, the triangle expands in place.
//  Drag a row onto a folder to move it on disk.
//

import SwiftUI

struct FileListView: View {
    @Bindable var vm: BrowserViewModel
    @Environment(PanelPresentation.self) private var presentation
    /// Top/bottom content insets so the list scrolls edge-to-edge under the
    /// header (toolbar + column header) and footer progressive-blur bands.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    /// Room for the reveal-sidebar chevron on the left margin — present only while
    /// the sidebar is collapsed (when that expand-handle exists).
    private var leadingHandleInset: CGFloat {
        presentation.isSidebarCollapsed ? Theme.paneHandleGutter : 0
    }
    /// Room for the reveal-preview chevron on the right margin — present only while
    /// the preview is hidden but a file is selected (when that expand-handle exists).
    private var trailingHandleInset: CGFloat {
        (!vm.isPreviewVisible && vm.selectedFile != nil) ? Theme.paneHandleGutter : 0
    }

    var body: some View {
        ZStack {
            list
                .contentMargins(.top, topInset, for: .scrollContent)
                .contentMargins(.bottom, bottomInset, for: .scrollContent)
                // A fresh identity per directory makes SwiftUI treat each folder's
                // contents as a distinct "page" — the old one slides out and the new
                // one slides in (and scroll resets to the top, like turning a page).
                .id(vm.currentDirectory)
                .transition(pageTransition)
        }
        .clipped()
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: vm.currentDirectory)
    }

    /// Going back slides the page in from the leading edge (the old page exits
    /// right) — a visible "return to the previous folder". Advancing into a folder
    /// is instant: entering is the common case and shouldn't carry motion cost.
    private var pageTransition: AnyTransition {
        guard vm.navDirection == .backward else { return .identity }
        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(vm.rows) { row in
                        FileRowView(
                            file: row.file,
                            isSelected: vm.selection.contains(row.file.url),
                            depth: row.depth,
                            reservesDisclosure: true,
                            isExpanded: vm.isExpanded(row.file.url),
                            showsMetadata: true,
                            isRenaming: vm.renamingURL == row.file.url,
                            isFailed: vm.renameFailureURL == row.file.url,
                            isInClipboard: vm.clipboard.contains(row.file.url),
                            onToggleDisclosure: { vm.toggleExpanded(row.file) },
                            onCommitRename: { vm.commitRename(row.file.url, to: $0) },
                            onCancelRename: { vm.cancelRename() }
                        )
                        .contextMenu { fileContextMenu(vm: vm, file: row.file) }
                        // AppKit drag layer; it intercepts the left click, so
                        // selection/open is handled here instead of .onTapGesture.
                        .fileDrag(
                            isRenaming: vm.renamingURL == row.file.url,
                            dragItems: {
                                // Drag the whole selection when this row is in it,
                                // preserving display order; else just this row.
                                if vm.selection.count > 1, vm.selection.contains(row.file.url) {
                                    return vm.rows.map(\.file.url).filter(vm.selection.contains)
                                }
                                return [row.file.url]
                            }
                        ) { click in
                            if click.count >= 2 { Task.detached{ await vm.open(row.file) }}
                            else if click.shift { vm.selectRange(to: row.file.url) }
                            else if click.command { vm.select(row.file.url, extending: true) }
                            else { vm.select(row.file.url) }
                        }
                        .modifier(FolderDropTarget(vm: vm, file: row.file))
                        .id(row.file.url)
                    }
                }
                // Static gutters keyed to collapse state (not hover): reserve room
                // for an edge expand-handle only while its pane is hidden, so rows
                // never reflow as the cursor merely approaches a divider.
                .padding(.leading, 6 + leadingHandleInset)
                .padding(.trailing, 6 + trailingHandleInset)
                .padding(.vertical, 4)
                .animation(.smooth(duration: 0.3), value: presentation.isSidebarCollapsed)
                .animation(.smooth(duration: 0.3), value: trailingHandleInset)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let dir = vm.currentDirectory else { return false }
                vm.move(urls, into: dir)
                return true
            }
            // Bring keyboard-driven moves into view, then clear the request.
            .onChange(of: vm.scrollTarget) { _, target in
                if let target {
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    vm.scrollTarget = nil
                }
            }
        }
    }
}

/// The fixed Name/Size/Modified header for the List surface. Lives in the panel
/// header overlay (above the progressive blur), so the list itself scrolls clean
/// underneath it.
struct FileColumnsHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Nome")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tamanho").frame(width: 64, alignment: .trailing)
            Text("Modificado").frame(width: 92, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 14)
        .padding(.leading, 26)
        .frame(height: 24)
    }
}

/// Makes a folder row accept dropped URLs (move into it). No-op for files.
private struct FolderDropTarget: ViewModifier {
    let vm: BrowserViewModel
    let file: FileNode
    @State private var targeted = false

    func body(content: Content) -> some View {
        if file.isDirectory {
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: targeted ? 2 : 0)
                )
                .dropDestination(for: URL.self) { urls, _ in
                    vm.move(urls, into: file.url)
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}
