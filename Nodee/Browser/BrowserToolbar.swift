//
//  BrowserToolbar.swift
//  Nodee
//
//  The browser's top bar: back/forward, a clickable breadcrumb (List surface),
//  the List/Columns mode selector, and the New Folder action. Kept thin so the
//  content area dominates the small Notch panel.
//

import SwiftUI

struct BrowserToolbar: View {
    @Bindable var vm: BrowserViewModel
    @Environment(PanelPresentation.self) private var presentation
    var topInset: CGFloat = 0

    /// Which breadcrumb crumb the cursor is currently over (tracked by URL so it
    /// survives re-renders as the path mutates). Drives the per-crumb hover state.
    @State private var hoveredCrumb: URL?

    /// Briefly flips the copy-path icon to a checkmark right after a copy, the
    /// same momentary confirmation a browser's address-bar copy button gives.
    @State private var didCopyPath = false

    var body: some View {
        VStack(spacing: 0) {
            // Spacer that fills the notch zone — the area is still "in" the toolbar
            // background, but no controls land under the physical hardware notch.
            if topInset > 0 {
                Color.clear.frame(height: topInset)
            }
            HStack(spacing: 8) {
                historyControls
                if vm.displayMode == .list {
                    breadcrumb
                } else {
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                copyPathButton
                newFolderButton
                modePicker
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
        }
        .background(.black.opacity(0.18))
    }

    private var historyControls: some View {
        HStack(spacing: 2) {
            toolbarButton("chevron.left", help: "Voltar", enabled: vm.canGoBack) { vm.goBack() }
            toolbarButton("chevron.right", help: "Avançar", enabled: vm.canGoForward) { vm.goForward() }
        }
    }

    private var breadcrumb: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    ForEach(Array(vm.breadcrumb.enumerated()), id: \.element.id) { index, crumb in
                        crumbCell(crumb, isLast: index == vm.breadcrumb.count - 1, showSeparator: index > 0)
                            .id(crumb.id)
                    }
                }
                .padding(.vertical, 2)
                // Animate crumbs blooming in / imploding out as the hierarchy
                // changes — keeps gestural depth navigation feeling continuous.
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: vm.breadcrumb.map(\.id))
            }
            .scrollIndicators(.never)
            // Keep the active (deepest) crumb in view as the path grows.
            .onChange(of: vm.breadcrumb.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last, anchor: .trailing)
                }
            }
        }
    }

    /// A single breadcrumb segment: optional leading chevron + a clickable,
    /// hover-reactive label. Built as one cell so the chevron and label
    /// transition together when the crumb is inserted or removed.
    private func crumbCell(_ crumb: FileNode, isLast: Bool, showSeparator: Bool) -> some View {
        let isHovered = hoveredCrumb == crumb.url
        return HStack(spacing: 1) {
            if showSeparator {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 2)
            }
            Button { vm.navigate(to: crumb.url); presentation.reclaimGestureFocus() } label: {
                Text(crumb.name)
                    .font(.system(size: 11, weight: isLast ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isLast ? 0.95 : (isHovered ? 0.85 : 0.5)))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(isHovered ? 0.12 : 0))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    if hovering {
                        hoveredCrumb = crumb.url
                    } else if hoveredCrumb == crumb.url {
                        hoveredCrumb = nil
                    }
                }
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.82, anchor: .leading)),
            removal: .opacity.combined(with: .scale(scale: 0.82, anchor: .trailing))
        ))
    }

    /// Copies the current directory's path, flashing a checkmark to confirm —
    /// like the "copy URL" button at the end of a browser's address bar.
    private var copyPathButton: some View {
        let enabled = vm.activeDirectory != nil
        return Button {
            vm.copyDirectoryPath()
            presentation.reclaimGestureFocus()
            withAnimation(.easeOut(duration: 0.15)) { didCopyPath = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.2)) { didCopyPath = false }
            }
        } label: {
            Image(systemName: didCopyPath ? "checkmark" : "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(didCopyPath ? Color.green.opacity(0.9)
                                             : .white.opacity(enabled ? 0.7 : 0.22))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Copiar caminho")
    }

    private var newFolderButton: some View {
        toolbarButton("folder.badge.plus", help: "Nova pasta", enabled: vm.activeDirectory != nil) {
            vm.newFolder()
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases) { mode in
                Button { vm.displayMode = mode; presentation.reclaimGestureFocus() } label: {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(vm.displayMode == mode ? .white : .white.opacity(0.45))
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(vm.displayMode == mode ? Color.white.opacity(0.14) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
    }

    private func toolbarButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); presentation.reclaimGestureFocus() } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? .white.opacity(0.7) : .white.opacity(0.22))
                .frame(width: 34, height: 30)
                // Without an explicit content shape a .plain button only hits
                // the glyph's opaque pixels — make the whole frame tappable.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
