//
//  NotchChromeLab.swift
//  Nodee
//
//  An in-context test harness for the pixel loader. It rebuilds the notch panel's
//  chrome — the toolbar (history chevrons, breadcrumb, "copy path" link button,
//  new-folder, mode picker) and the bottom toast — but drops the new `PixelLoader`
//  into the two spots that today use `DotMatrixIndicator`: the copy-path feedback
//  and the toast status indicator. This lets the bloom be judged at the real, tiny
//  scale, beside the other UI, before it ever replaces the dot matrix in the app.
//
//  Everything here is a self-contained mock (static breadcrumb, faked toasts) so it
//  drags in none of the real view models — it exists purely to look right.
//

import SwiftUI

// MARK: - Fixed-footprint status indicator

/// The in-context stand-in for `DotMatrixIndicator`: a `PixelLoader` sized to a
/// fixed `extent` (so a 3×3 grid lands in ~16–18 pt like the real indicators) with
/// its `glow` scaled down from the tuning-stage cell size, keeping the bloom
/// proportional to the tiny pixels — "1×1" with the rest of the chrome.
struct PixelStatusIndicator: View {
    var sequence: PixelLoaderSequence
    var color: Color
    var extent: CGFloat = 18
    var brightness: Int = 2
    /// The same proportions (gap & corner ratios) the tuning stage uses, so the
    /// tiny grid is a faithful down-scale of the big one — not a separate guess.
    var style: PixelGridStyle = .init()
    /// Glow recipe authored for a cell of `referenceCellSize`; scaled to this grid.
    var glow: GlowStyle = .init()
    var referenceCellSize: CGFloat = 64
    var density: Int = 1
    var glowPerSubPixel: Bool = false
    var isPaused: Bool = false

    var body: some View {
        let n = CGFloat(sequence.dimension)
        let cell = extent / (n + style.gapRatio * (n - 1))   // footprint == extent
        let factor = referenceCellSize > 0 ? cell / referenceCellSize : 1
        PixelLoaderView(sequence: sequence,
                        color: color,
                        cellSize: cell,
                        style: style,
                        glow: glow.scaled(by: factor),
                        brightness: brightness,
                        density: density,
                        glowPerSubPixel: glowPerSubPixel,
                        isPaused: isPaused)
            .frame(width: extent, height: extent)
    }
}

// MARK: - Feedback catalogue

/// The toast feedback variants the dot matrix speaks today, reproduced so each can
/// be fired in the lab and seen with the pixel loader. Accents and copy mirror the
/// real app (trash/error → red, copy → amber, move/loading → ice-blue, success →
/// green).
enum NotchFeedback: String, CaseIterable, Identifiable {
    case loading, copy, move, trash, success, error
    var id: String { rawValue }

    var title: String {
        switch self {
        case .loading: return "Loading"
        case .copy:    return "Copy"
        case .move:    return "Move"
        case .trash:   return "Trash"
        case .success: return "Success"
        case .error:   return "Error"
        }
    }

    var message: String {
        switch self {
        case .loading: return "Carregando…"
        case .copy:    return "Caminho copiado"
        case .move:    return "Movido para Documentos"
        case .trash:   return "Movido para o Lixo"
        case .success: return "Concluído"
        case .error:   return "Falha na operação"
        }
    }

    var actionLabel: String? { self == .trash ? "Desfazer" : nil }

    var accent: Color {
        switch self {
        case .copy:           return Color(red: 1.00, green: 0.78, blue: 0.38)   // amber
        case .trash, .error:  return Color(red: 1.00, green: 0.38, blue: 0.38)   // red
        case .success:        return Color(red: 0.45, green: 0.92, blue: 0.56)   // green
        case .loading, .move: return Color(red: 0.55, green: 0.80, blue: 1.00)   // ice-blue
        }
    }

    /// Motion states orbit; terminal states (success/error) pulse on the midpoints.
    func sequence(interval: TimeInterval) -> PixelLoaderSequence {
        switch self {
        case .success, .error: return .cross(interval: max(0.18, interval * 3))
        default:               return .orbit(dimension: 3, interval: interval)
        }
    }
}

// MARK: - In-context mock

struct NotchChromeLab: View {
    var glow: GlowStyle = .init()
    var style: PixelGridStyle = .init()
    var referenceCellSize: CGFloat = 64
    var brightness: Int = 2
    var interval: TimeInterval = 0.09
    var density: Int = 1
    var glowPerSubPixel: Bool = false
    var isPaused: Bool = false
    /// When set (from the lab's "loop toast" toggle) the toast stays pinned open so
    /// its animation loops and updates live with the controls, instead of
    /// auto-dismissing. Transient fires from the trigger row still play over it and
    /// then fall back to the pinned one.
    var pinnedToast: NotchFeedback? = nil

    @State private var activeToast: NotchFeedback?
    @State private var dismissTask: Task<Void, Never>?

    /// The toast actually shown: a transient fire wins, otherwise the pinned one.
    private var displayedToast: NotchFeedback? { activeToast ?? pinnedToast }

    var body: some View {
        VStack(spacing: 22) {
            panel
            triggers
        }
        .padding(24)
    }

    // The notch panel: toolbar on top, a little faux content, toast overlaid at the
    // foot exactly like `PanelRootView` does.
    private var panel: some View {
        VStack(spacing: 0) {
            MockToolbar(glow: glow,
                        style: style,
                        referenceCellSize: referenceCellSize,
                        brightness: brightness,
                        interval: interval,
                        density: density,
                        glowPerSubPixel: glowPerSubPixel,
                        isPaused: isPaused)
            fauxContent
        }
        .frame(width: 460, height: 280)
        .background(Color(white: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if let fb = displayedToast {
                MockToastPill(feedback: fb,
                              glow: glow,
                              style: style,
                              referenceCellSize: referenceCellSize,
                              brightness: brightness,
                              interval: interval,
                              density: density,
                              glowPerSubPixel: glowPerSubPixel,
                              isPaused: isPaused,
                              onDismiss: dismiss)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(fb)
            }
        }
        // Pin/unpin (and feedback swaps) from the lab animate in/out; transient
        // fires keep their own `withAnimation` in `fire`/`dismiss`.
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: pinnedToast)
    }

    private var fauxContent: some View {
        VStack(spacing: 2) {
            ForEach(["Documents", "Downloads", "Projetos", "Screenshot.png"], id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: name.contains(".") ? "doc" : "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.55, green: 0.80, blue: 1.00).opacity(0.7))
                        .frame(width: 16)
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // Buttons to fire each feedback variant into the toast slot.
    private var triggers: some View {
        HStack(spacing: 8) {
            ForEach(NotchFeedback.allCases) { fb in
                Button { fire(fb) } label: {
                    HStack(spacing: 6) {
                        Circle().fill(fb.accent).frame(width: 7, height: 7)
                        Text(fb.title).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(.white.opacity(activeToast == fb ? 0.16 : 0.06))
                    )
                    .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fire(_ fb: NotchFeedback) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { activeToast = fb }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { activeToast = nil }
    }
}

// MARK: - Toolbar mock

private struct MockToolbar: View {
    var glow: GlowStyle
    var style: PixelGridStyle
    var referenceCellSize: CGFloat
    var brightness: Int
    var interval: TimeInterval
    var density: Int
    var glowPerSubPixel: Bool
    var isPaused: Bool

    private let crumbs = ["Macintosh HD", "Users", "jotape", "Documents"]
    private let iceBlue = Color(red: 0.55, green: 0.80, blue: 1.00)
    private let green = Color(red: 0.45, green: 0.92, blue: 0.56)

    @State private var copyPhase: CopyPhase = .idle
    @State private var copyTask: Task<Void, Never>?
    @State private var shimmerAngle: Double = 0
    @State private var shimmerOpacity: Double = 0
    @State private var shimmerTask: Task<Void, Never>?

    private enum CopyPhase { case idle, loading, done }

    var body: some View {
        HStack(spacing: 8) {
            chevron("chevron.left")
            chevron("chevron.right")
            breadcrumb
            Spacer(minLength: 0)
            copyButton
            toolbarIcon("folder.badge.plus")
            modePicker
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(.black.opacity(0.18))
    }

    private func chevron(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 28, height: 30)
    }

    private var breadcrumb: some View {
        HStack(spacing: 1) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { i, crumb in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 2)
                }
                Text(crumb)
                    .font(.system(size: 11, weight: i == crumbs.count - 1 ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(i == crumbs.count - 1 ? 0.95 : 0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: shimmerColors, center: .center,
                                    angle: .degrees(shimmerAngle)),
                    lineWidth: 1.5
                )
                .opacity(shimmerOpacity)
                .allowsHitTesting(false)
        }
    }

    /// The copy-path button: link glyph at rest, replaced in place by the pixel
    /// loader — an ice-blue orbit that finishes by blooming green — on tap, while
    /// the breadcrumb border sweeps once.
    private var copyButton: some View {
        Button(action: fireCopy) {
            ZStack {
                if copyPhase == .idle {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    PixelStatusIndicator(
                        sequence: copyPhase == .done
                            ? .cross(interval: max(0.18, interval * 3))
                            : .orbit(dimension: 3, interval: interval),
                        color: copyPhase == .done ? green : iceBlue,
                        extent: 18,
                        brightness: brightness,
                        style: style,
                        glow: glow,
                        referenceCellSize: referenceCellSize,
                        density: density,
                        glowPerSubPixel: glowPerSubPixel,
                        isPaused: isPaused
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .frame(width: 34, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copiar caminho (⌘⌥C)")
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: copyPhase)
    }

    private func toolbarIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 34, height: 30)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(["list.bullet", "square.grid.2x2"], id: \.self) { symbol in
                let isActive = symbol == "list.bullet"
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.45))
                    .frame(width: 28, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive ? Color.white.opacity(0.14) : .clear)
                    )
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
    }

    private var shimmerColors: [Color] {
        let a = iceBlue
        return [a.opacity(0.00), a.opacity(0.03), a.opacity(0.08), a.opacity(0.14),
                a.opacity(0.20), a.opacity(0.26), a.opacity(0.28), Color.white.opacity(0.09),
                a.opacity(0.24), a.opacity(0.16), a.opacity(0.08), a.opacity(0.02), a.opacity(0.00)]
    }

    private func fireCopy() {
        copyTask?.cancel()
        shimmerTask?.cancel()

        shimmerAngle = 225
        withAnimation(.easeIn(duration: 0.50)) { shimmerOpacity = 1 }
        withAnimation(.easeInOut(duration: 3.2)) { shimmerAngle = 225 + 360 }
        copyPhase = .loading

        copyTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            copyPhase = .done
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.0)) { shimmerOpacity = 0 }
            copyPhase = .idle
        }
    }
}

// MARK: - Toast mock

private struct MockToastPill: View {
    let feedback: NotchFeedback
    var glow: GlowStyle
    var style: PixelGridStyle
    var referenceCellSize: CGFloat
    var brightness: Int
    var interval: TimeInterval
    var density: Int
    var glowPerSubPixel: Bool
    var isPaused: Bool
    var onDismiss: () -> Void

    @State private var shimmerAngle: Double = 0

    private var glowColors: [Color] {
        let a = feedback.accent
        return [.clear, a.opacity(0.0), a.opacity(0.32), Color(white: 1).opacity(0.18),
                a.opacity(0.20), a.opacity(0.08), .clear, .clear]
    }

    var body: some View {
        HStack(spacing: 10) {
            PixelStatusIndicator(sequence: feedback.sequence(interval: interval),
                                 color: feedback.accent,
                                 extent: 16,
                                 brightness: brightness,
                                 style: style,
                                 glow: glow,
                                 referenceCellSize: referenceCellSize,
                                 density: density,
                                 glowPerSubPixel: glowPerSubPixel,
                                 isPaused: isPaused)

            Text(feedback.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            if let label = feedback.actionLabel {
                Divider().frame(height: 14).overlay(Color.white.opacity(0.28))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.80, blue: 1.00))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(white: 1, opacity: 0.19), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AngularGradient(colors: glowColors, center: .center,
                                                  angle: .degrees(shimmerAngle)), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: feedback.accent.opacity(0.18), radius: 16)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .onTapGesture(perform: onDismiss)
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                shimmerAngle = 360
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        NotchChromeLab(glow: GlowStyle(layers: 5, baseRadius: 24, spread: 1.31, baseOpacity: 0.45),
                       referenceCellSize: 64,
                       density: 6,
                       pinnedToast: .loading)
    }
    .frame(width: 560, height: 460)
}
