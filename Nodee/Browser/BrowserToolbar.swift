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

    /// Which mode-picker button is currently hovered — drives the hover pill.
    @State private var hoveredMode: DisplayMode?

    // MARK: - Breadcrumb copy shimmer
    // Fires when the user copies the directory path. A soft arc of ice-blue light
    // sweeps the full URL border once — like a loading ring completing a cycle —
    // then dissolves. One rotation (360°) in 2.0 s reads as deliberate/loading,
    // not a flash. The gradient is a wide, bell-shaped arc (~120° of coverage)
    // with 12 stops so there are no visible angular jumps between colours.
    @State private var crumbShimmerAngle: Double  = 0
    @State private var crumbShimmerOpacity: Double = 0
    @State private var crumbShimmerTask: Task<Void, Never>?

    /// Dot-matrix state for the copy-path feedback: plays in place of the link
    /// icon — a dual-comet orbit that finishes by blooming green.
    @State private var copyDotState: DotMatrixState = .idle
    @State private var copyFeedbackTask: Task<Void, Never>?

    private var crumbGlowColors: [Color] {
        let a = Color(red: 0.55, green: 0.80, blue: 1.00)
        // Bell-shaped arc: long gradual rise → soft peak → symmetric fall.
        // Low peak opacity (0.28) and no hard .clear boundaries keep the sweep
        // smooth — no angular hotspot flicker as the gradient rotates.
        return [
            a.opacity(0.00),  //  0° – leading tail
            a.opacity(0.03),
            a.opacity(0.08),
            a.opacity(0.14),
            a.opacity(0.20),
            a.opacity(0.26),
            a.opacity(0.28),  // apex
            Color.white.opacity(0.09), // delicate white at the apex
            a.opacity(0.24),
            a.opacity(0.16),
            a.opacity(0.08),
            a.opacity(0.02),
            a.opacity(0.00),  // 360° – matches 0° so the seam is invisible
        ]
    }

    private func fireCrumbShimmer() {
        crumbShimmerTask?.cancel()
        // Start at 225° (bottom-left diagonal) — the arc enters from the corner,
        // which reads as directional rather than arbitrary.
        crumbShimmerAngle = 225
        // Slow ease-in: the border materialises gently over 0.5 s.
        withAnimation(.easeIn(duration: 0.50))         { crumbShimmerOpacity = 1 }
        // easeInOut over 3.2 s: starts slow (loading), builds momentum,
        // decelerates to rest (complete) — one unidirectional clockwise pass.
        withAnimation(.easeInOut(duration: 3.2))        { crumbShimmerAngle   = 225 + 360 }

        // Dot matrix: start loading, then land on success after 0.6 s.
        copyDotState = .loading

        // Begin dissolving at 2.2 s — the fade overlaps the deceleration phase
        // so the border softly "lands" as it completes rather than cutting off.
        crumbShimmerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            copyDotState = .success

            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.0)) { crumbShimmerOpacity = 0 }

            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            copyDotState = .idle
        }
    }

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
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: vm.breadcrumb.map(\.id))
                // Shimmer wraps the full URL path as one unit — fires on copy-path.
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: crumbGlowColors,
                                center: .center,
                                angle: .degrees(crumbShimmerAngle)
                            ),
                            lineWidth: 1.5
                        )
                        .opacity(crumbShimmerOpacity)
                        .allowsHitTesting(false)
                }
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

    /// Copies the current directory's path — like the "copy URL" button at the end
    /// of a browser's address bar. The feedback plays *in place of the icon*: the
    /// link glyph gives way to a dual-comet loading that finishes by blooming green
    /// to confirm, then settles back to the link.
    private var copyPathButton: some View {
        let enabled = vm.activeDirectory != nil
        return Button {
            vm.copyDirectoryPath()
            presentation.reclaimGestureFocus()
            fireCrumbShimmer()
            runCopyFeedback()
        } label: {
            ZStack {
                if copyDotState == .idle {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.22))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    DotMatrixIndicator(
                        state: copyDotState,
                        showGlow: false,
                        extent: 18
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .frame(width: 34, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Copiar caminho (⌘⌥C)")
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: copyDotState)
    }

    /// Drives the in-place copy feedback: a dual-comet orbit on the iris rim (one
    /// quick cycle), then a green completion bloom, then back to the resting link
    /// icon. Both halves share the `.standardIris`, so the hand-off never reflows.
    private func runCopyFeedback() {
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            copyDotState = .custom(.dualOrbitRadial(cycle: 0.42))
            try? await Task.sleep(for: .seconds(0.46))    // ~one quick cycle
            guard !Task.isCancelled else { return }
            copyDotState = .custom(.dualOrbitDoneRadial())
            try? await Task.sleep(for: .seconds(0.62))    // hold the bloom
            guard !Task.isCancelled else { return }
            copyDotState = .idle                          // back to the link
        }
    }

    private var newFolderButton: some View {
        toolbarButton("folder.badge.plus", help: "Nova pasta", enabled: vm.activeDirectory != nil) {
            vm.newFolder()
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases) { mode in
                let isActive = vm.displayMode == mode
                let isHovered = hoveredMode == mode
                Button { vm.displayMode = mode; presentation.reclaimGestureFocus() } label: {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? .white : .white.opacity(isHovered ? 0.65 : 0.45))
                        // Bounce the icon the moment this mode becomes active.
                        .symbolEffect(.bounce.up.byLayer, value: isActive)
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isActive  ? Color.white.opacity(0.14)
                                      : isHovered ? Color.white.opacity(0.07) : .clear)
                        )
                        .animation(.easeOut(duration: 0.12), value: isHovered)
                }
                .buttonStyle(.plain)
                .help(mode.label)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredMode = hovering ? mode : (hoveredMode == mode ? nil : hoveredMode)
                    }
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
    }

    private func toolbarButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        ToolbarButtonView(symbol: symbol, help: help, enabled: enabled) {
            action(); presentation.reclaimGestureFocus()
        }
    }
}

// MARK: - ToolbarButtonView

/// A single toolbar icon button with a native macOS hover pill.
/// Extracted to its own struct so @State isHovered is scoped per-button
/// without adding properties to the parent view.
private struct ToolbarButtonView: View {
    let symbol: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? .white.opacity(isHovered ? 0.9 : 0.7) : .white.opacity(0.22))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(enabled && isHovered ? 0.09 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = enabled && hovering }
        }
    }
}
