//
//  ColumnsView.swift
//  Nodee
//
//  The Columns surface: Miller-column drill-down (Finder column view). Column 0
//  lists the project root; selecting a folder opens the next column to its right;
//  selecting a file shows its preview in the final column. The view auto-scrolls
//  to keep the active column visible.
//

import SwiftUI

struct ColumnsView: View {
    @Bindable var vm: BrowserViewModel
    /// Top/bottom content insets so each column scrolls edge-to-edge under the
    /// header and footer progressive-blur bands.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    private let columnWidth: CGFloat = 210

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(vm.columns.enumerated()), id: \.offset) { index, items in
                        column(items, at: index)
                            .frame(width: columnWidth)
                            .id(columnID(index))
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                    previewColumn
                }
            }
            .onChange(of: vm.columns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(columnID(vm.columns.count - 1), anchor: .trailing)
                }
            }
        }
    }

    private func columnID(_ index: Int) -> String { "column-\(index)" }

    private func column(_ items: [FileNode], at index: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(items) { file in
                        FileRowView(
                            file: file,
                            isSelected: vm.selection.contains(file.url) || vm.columnPath.contains(file.url),
                            showsChevron: true,
                            isRenaming: vm.renamingURL == file.url,
                            onCommitRename: { vm.commitRename(file.url, to: $0) },
                            onCancelRename: { vm.cancelRename() }
                        )
                        .contextMenu { fileContextMenu(vm: vm, file: file) }
                        // AppKit drag layer; it intercepts the left click, so the
                        // Miller drill / selection is handled here, not .onTapGesture.
                        .fileDrag(
                            isRenaming: vm.renamingURL == file.url,
                            dragItems: {
                                // Drag the whole selection when this row is in it,
                                // preserving column order; else just this row.
                                if vm.selection.count > 1, vm.selection.contains(file.url) {
                                    return items.map(\.url).filter(vm.selection.contains)
                                }
                                return [file.url]
                            }
                        ) { click in
                            if click.count >= 2 {
                                if file.isDirectory { vm.selectInColumn(file.url, column: index) }
                                else { vm.open(file) }
                            } else if click.shift { vm.selectRange(to: file.url) }
                            else if click.command { vm.select(file.url, extending: true) }
                            else { vm.selectInColumn(file.url, column: index) }
                        }
                        .modifier(ColumnDropTarget(vm: vm, file: file))
                        .id(file.url)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .contentMargins(.top, topInset, for: .scrollContent)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            // Vertically scroll the column that owns the keyboard target into view.
            .onChange(of: vm.scrollTarget) { _, target in
                if let target, items.contains(where: { $0.url == target }) {
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    vm.scrollTarget = nil
                }
            }
        }
    }

    /// Trailing preview column when the current selection is a file (Finder-style).
    @ViewBuilder
    private var previewColumn: some View {
        if let file = vm.selectedFile, !file.isDirectory, vm.isPreviewVisible {
            PreviewPane(file: file, width: 240)
                .offset(x: max(0, vm.previewPanOffset))
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Folder rows in a column accept dropped URLs (move into the folder).
private struct ColumnDropTarget: ViewModifier {
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
                    for url in urls { vm.move(url, into: file.url) }
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}
