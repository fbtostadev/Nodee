//
//  ToastView.swift
//  Nodee
//
//  The toast bubble itself: a compact dark pill with a message and an optional
//  action button (e.g. "Desfazer"). Hovering for 700ms expands the pill into a
//  contextual card with spatial/directory detail. Rendered by PanelRootView as a
//  bottom overlay, above the grabber.
//

import AppKit
import SwiftUI

// MARK: - ToastView

struct ToastView: View {
    let toast: Toast
    let center: ToastCenter

    @State private var shimmerAngle: Double = 0
    @State private var isExpanded = false
    @State private var hoverTask: Task<Void, Never>?

    // Two-phase dot-matrix: a verb announces the operation once, then the
    // indicator settles into a continuous breathe so it stays alive for the
    // toast's whole life — in lockstep with the perpetually-breathing border
    // shimmer (DSGNConcept §4.2). Without this the one-shot verb dies into an
    // empty slot while the toast keeps breathing — the conformance gap.
    @State private var dotState: DotMatrixState = .idle
    @State private var dotTask: Task<Void, Never>?
    /// Drives the indicator's own gentle bloom-in, staged a beat after the pill
    /// starts arriving so the light wakes *with* the toast instead of riding in
    /// already-formed (DSGNConcept §6 — shape first, content after).
    @State private var dotAppeared = false

    /// The verb that announces the operation, or nil for a plain message (which
    /// goes straight to breathing). Error shudders; move/copy/trash lift/cascade/
    /// dissolve in their semantic accents.
    private var announceVerb: DotMatrixState? {
        if toast.isError { return .error }
        guard let ctx = toast.context else { return nil }
        switch ctx.kind {
        case .trashed: return .trash
        case .copied:  return .copy
        case .moved:   return .move
        }
    }

    // Semantic accent derived from the operation kind. Trash → red, copy → amber,
    // move / nil → ice-blue. Used for the rotating shimmer and the outer glow shadow.
    private var accent: Color {
        if toast.isError { return Color(red: 1.00, green: 0.38, blue: 0.38) }
        switch toast.context?.kind {
        case .trashed: return Color(red: 1.00, green: 0.38, blue: 0.38)
        case .copied:  return Color(red: 1.00, green: 0.78, blue: 0.38)
        default:       return Color(red: 0.55, green: 0.80, blue: 1.00)
        }
    }

    private var glowColors: [Color] {
        [
            .clear,
            accent.opacity(0.0),
            accent.opacity(0.32),
            Color(white: 1.0).opacity(0.18),
            accent.opacity(0.20),
            accent.opacity(0.08),
            .clear,
            .clear,
        ]
    }

    var body: some View {
        // Detail is above the pill so the pill stays anchored at the bottom when the
        // card expands. (The toast overlay uses .bottom alignment; if the detail were
        // below the pill the pill would shift upward on expansion, causing misclicks.)
        VStack(alignment: .leading, spacing: 0) {
            // ── Expanded detail card ──────────────────────────────────────
            if isExpanded, let ctx = toast.context {
                ToastDetailView(context: ctx, onNavigate: toast.navigationAction.map { nav in
                    {
                        nav()
                        center.dismiss()
                    }
                })
                .transition(
                    .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                )

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
            }

            // ── Primary pill row ──────────────────────────────────────────
            HStack(spacing: 10) {
                // Leading status indicator — the dot matrix maps toast intent to
                // a living pixel pattern (error pulse, success convergence, idle).
                DotMatrixIndicator(
                    state: dotState,
                    accent: accent,
                    showGlow: false,
                    extent: 16
                )
                // Blooms in a beat after the pill lands, accompanying the arrival.
                .scaleEffect(dotAppeared ? 1 : 0.5, anchor: .center)
                .opacity(dotAppeared ? 1 : 0)

                Text(toast.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if let label = toast.actionLabel, let action = toast.action {
                    Divider()
                        .frame(height: 14)
                        .overlay(Color.white.opacity(0.28))
                    Button {
                        center.dismiss()   // dismiss first — action() may show a new toast
                        action()
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.80, blue: 1.00))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 16 : 20, style: .continuous)
                        .fill(.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 16 : 20, style: .continuous)
                        .strokeBorder(Color(white: 1.0, opacity: 0.19), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 16 : 20, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: glowColors,
                                center: .center,
                                angle: .degrees(shimmerAngle)
                            ),
                            lineWidth: 1
                        )
                )
        )
        // Mask content to the rounded shape so the detail can't bleed past the
        // bounds while the container resizes — applied before the shadows so they
        // still render outside the clip.
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 20, style: .continuous))
        .shadow(color: accent.opacity(0.18), radius: 16, y: 0)
        .shadow(color: Color(white: 1.0).opacity(0.06), radius: 28, y: 2)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 20, style: .continuous))
        .onTapGesture { center.dismiss() }
        .onHover { inside in
            if inside {
                center.pauseDismiss()
                guard toast.context != nil else { return }
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    // Smooth ease-out bezier (no spring overshoot): resize and the
                    // content fade share this curve, so the detail surfaces in sync
                    // with the container instead of popping.
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)) {
                        isExpanded = true
                    }
                }
            } else {
                hoverTask?.cancel()
                hoverTask = nil
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)) {
                    isExpanded = false
                }
                center.resumeDismiss()
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                shimmerAngle = 360
            }
            // Staged reveal: let the pill start landing, then bloom the indicator
            // in, then announce the operation's verb, then settle into a continuous
            // breathe in the toast's accent — alive alongside the border shimmer.
            dotTask = Task {
                try? await Task.sleep(for: .seconds(0.12))   // let the pill arrive
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                    dotAppeared = true                       // light wakes with the settle
                }
                if let verb = announceVerb {
                    try? await Task.sleep(for: .seconds(0.18))
                    guard !Task.isCancelled else { return }
                    dotState = verb
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled else { return }
                }
                dotState = .syncing
            }
        }
        .onDisappear { dotTask?.cancel() }
    }
}

// MARK: - ToastDetailView

private struct ToastDetailView: View {
    let context: ToastContext
    /// Called when the user taps the destination chip. Nil for Trash (no navigation target).
    var onNavigate: (() -> Void)?

    private var destinationLabel: String {
        context.destinationFolder ?? "Lixeira"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // File list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(context.fileNames.prefix(3), id: \.self) { name in
                    HStack(spacing: 6) {
                        Image(systemName: fileIcon(for: name))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(red: 0.55, green: 0.80, blue: 1.00).opacity(0.80))
                            .frame(width: 12)
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                }
                if context.fileNames.count > 3 {
                    Text("+ \(context.fileNames.count - 3) mais")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.40))
                        .padding(.leading, 18)
                }
            }

            // Spatial path — origin (muted, the past) → destination (accented,
            // where the file lives now). The two chips read as distinct places.
            HStack(spacing: 8) {
                folderChip(context.sourceFolder, icon: "folder", role: .origin)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))

                let destRole: ChipRole = context.kind == .trashed ? .trash : .destination
                let destIcon = context.kind == .trashed ? "trash" : "folder"

                if let navigate = onNavigate, context.kind != .trashed {
                    Button(action: navigate) {
                        folderChip(destinationLabel, icon: destIcon, role: destRole)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                } else {
                    folderChip(destinationLabel, icon: destIcon, role: destRole)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: Folder chip

    private enum ChipRole { case origin, destination, trash }

    @ViewBuilder
    private func folderChip(_ name: String, icon: String, role: ChipRole) -> some View {
        let accent = Color(red: 0.55, green: 0.80, blue: 1.00)
        let red = Color(red: 1.00, green: 0.42, blue: 0.42)

        let (fg, bg, stroke): (Color, Color, Color) = {
            switch role {
            case .origin:      return (.white.opacity(0.55), .white.opacity(0.06),  .white.opacity(0.10))
            case .destination: return (accent,               accent.opacity(0.14),  accent.opacity(0.30))
            case .trash:       return (red,                  red.opacity(0.12),     red.opacity(0.28))
            }
        }()

        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(name)
                .font(.system(size: 10.5, weight: role == .origin ? .medium : .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 110, alignment: .leading)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(bg)
                .overlay(Capsule(style: .continuous).strokeBorder(stroke, lineWidth: 0.75))
        )
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "js", "ts", "py", "rb", "go", "rs", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "md", "txt", "rtf":
            return "doc.text"
        case "json", "yaml", "yml", "toml":
            return "curlybraces"
        case "":
            return "folder"
        default:
            return "doc"
        }
    }
}
