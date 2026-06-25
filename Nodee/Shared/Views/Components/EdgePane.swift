import SwiftUI
import AppKit

struct EdgePane<Content: View>: View {
    enum Edge { case leading, trailing }

    let edge: Edge
    let fullWidth: CGFloat
    let collapsed: Bool
    let toggle: () -> Void
    var restingCenterFromTop: CGFloat = 30
    var dockedRestingCenterFromTop: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    @State private var progress: CGFloat
    @State private var tracker = EdgeProximity()
    @State private var isHovered = false
    @State private var tabCenterY: CGFloat
    @State private var returnWork: DispatchWorkItem?

    var headerHeight: CGFloat = 0

    init(edge: Edge, fullWidth: CGFloat, collapsed: Bool,
         restingCenterFromTop: CGFloat = 30,
         dockedRestingCenterFromTop: CGFloat? = nil,
         headerHeight: CGFloat = 0,
         toggle: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.edge = edge
        self.fullWidth = fullWidth
        self.collapsed = collapsed
        self.restingCenterFromTop = restingCenterFromTop
        self.dockedRestingCenterFromTop = dockedRestingCenterFromTop
        self.headerHeight = headerHeight
        self.toggle = toggle
        self.content = content
        _progress = State(initialValue: collapsed ? 1 : 0)
        _tabCenterY = State(initialValue: collapsed ? (dockedRestingCenterFromTop ?? restingCenterFromTop)
                                                    : restingCenterFromTop)
    }

    private var outerWidth: CGFloat {
        let open = fullWidth + Theme.paneHandleGutter
        return open + (Theme.edgePaneTabWidth - open) * progress
    }

    private var marginAlignment: Alignment { edge == .leading ? .leading : .trailing }
    private var marginInwardSign: CGFloat { edge == .leading ? 1 : -1 }

    private var dockedResting: CGFloat { dockedRestingCenterFromTop ?? restingCenterFromTop }
    private var restingTarget: CGFloat { collapsed ? dockedResting : restingCenterFromTop }

    private var collapseChevron: String {
        edge == .leading ? "chevron.compact.left" : "chevron.compact.right"
    }
    private var revealChevron: String {
        edge == .leading ? "chevron.compact.right" : "chevron.compact.left"
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = min(max(x, 0), 1); return t * t * (3 - 2 * t)
    }
    private var bell: CGFloat { sin(progress * .pi) }
    private var tabPresence: CGFloat { smoothstep((progress - 0.30) / 0.70) }
    private var contentOpacity: CGFloat { 1 - smoothstep(progress / 0.55) }
    private var chevronShown: CGFloat { smoothstep((progress - 0.25) / 0.50) }
    private var approach: CGFloat { max(tracker.proximity, isHovered ? 1 : 0) }

    private var paneBloom: Double { min(0.28, Theme.edgePaneGlowPeak * 0.5 * Double(bell)) }

    private var headerSymbol: String {
        edge == .leading ? "rectangle.portrait.lefthalf.filled" : "rectangle.portrait.righthalf.filled"
    }

    private func morphShape() -> UnevenRoundedRectangle {
        let inner = Theme.edgePaneCardCorner * bell + Theme.edgePaneTabCorner * progress
        switch edge {
        case .trailing:
            return UnevenRoundedRectangle(topLeadingRadius: inner, bottomLeadingRadius: inner,
                                          bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        case .leading:
            return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: inner, topTrailingRadius: inner, style: .continuous)
        }
    }

    private func handleShape() -> UnevenRoundedRectangle {
        let c = Theme.edgePaneTabCorner
        let outward = c * (1 - progress)
        let inward = c * progress
        switch edge {
        case .trailing:
            return UnevenRoundedRectangle(topLeadingRadius: inward, bottomLeadingRadius: inward,
                                          bottomTrailingRadius: outward, topTrailingRadius: outward, style: .continuous)
        case .leading:
            return UnevenRoundedRectangle(topLeadingRadius: outward, bottomLeadingRadius: outward,
                                          bottomTrailingRadius: inward, topTrailingRadius: inward, style: .continuous)
        }
    }

    private var haloSign: CGFloat { marginInwardSign * (2 * progress - 1) }

    private var cardAlignment: Alignment { edge == .trailing ? .topTrailing : .topLeading }
    private var innerAlignment: Alignment { edge == .trailing ? .topLeading : .topTrailing }

    var body: some View {
        let shape = morphShape()
        GeometryReader { geo in
            let fullH = geo.size.height
            let minCenter = restingCenterFromTop
            let maxCenter = max(minCenter, fullH - Theme.edgePaneTabHeight / 2 - 10)
            let center = min(max(tabCenterY, minCenter), maxCenter)
            let cardH = fullH + (Theme.edgePaneTabHeight - fullH) * progress
            let cardTop = max(0, center - Theme.edgePaneTabHeight / 2) * progress
            let handleTop = center - Theme.edgePaneTabHeight / 2
            let atHeader = 1 - smoothstep(abs(center - restingTarget) / 34)

            ZStack(alignment: marginAlignment) {
                shape.fill(Color.black)

                content()
                    .opacity(contentOpacity)
                    .allowsHitTesting(progress < 0.5)
            }
            .frame(width: outerWidth, height: cardH, alignment: cardAlignment)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.10 * tabPresence), lineWidth: 1))
            .shadow(color: Theme.edgePaneGlow.opacity(paneBloom), radius: 18)
            .offset(y: cardTop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cardAlignment)
            .overlay(alignment: innerAlignment) { handle(topOffset: handleTop, atHeader: atHeader) }
            .onAppear { tracker.edgeFrame = innerEdgeRect(geo) }
            .onChange(of: geo.frame(in: .global)) { _, _ in tracker.edgeFrame = innerEdgeRect(geo) }
            .onChange(of: outerWidth) { _, _ in tracker.edgeFrame = innerEdgeRect(geo) }
        }
        .frame(width: outerWidth)
        .background(WindowAccessor { tracker.hostWindow = $0 })
        .onAppear {
            tracker.activationDelay = 0.10
            tracker.headerHeight = headerHeight
            tracker.start()
        }
        .onChange(of: headerHeight) { _, h in tracker.headerHeight = h }
        .onDisappear {
            tracker.stop()
        }
        .onChange(of: tracker.cursorLocalY) { _, y in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { tabCenterY = y }
        }
        .onChange(of: tracker.proximity) { _, v in
            if v == 0 {
                scheduleReturnToHeader()
            } else {
                returnWork?.cancel(); returnWork = nil
            }
        }
        .onChange(of: collapsed) { _, c in
            withAnimation(Theme.edgePaneMorph) { progress = c ? 1 : 0 }
            if tracker.proximity == 0 {
                returnWork?.cancel(); returnWork = nil
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                    tabCenterY = c ? dockedResting : restingCenterFromTop
                }
            }
        }
        .onDisappear { returnWork?.cancel(); returnWork = nil }
        .animation(.smooth(duration: 0.30), value: tracker.proximity)
        .animation(.easeInOut(duration: 0.22), value: isHovered)
    }

    private func scheduleReturnToHeader() {
        let returnDelay: TimeInterval = 1
        returnWork?.cancel()
        let work = DispatchWorkItem {
            guard tracker.proximity == 0 else { return }
            withAnimation(.easeInOut(duration: 0.42)) { tabCenterY = restingTarget }
        }
        returnWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + returnDelay, execute: work)
    }

    private func innerEdgeRect(_ geo: GeometryProxy) -> CGRect {
        let f = geo.frame(in: .global)
        let innerX = edge == .trailing ? f.minX : f.maxX
        return CGRect(x: innerX - 0.5, y: f.minY, width: 1, height: f.height)
    }

    private func handle(topOffset: CGFloat, atHeader: CGFloat) -> some View {
        let shape = handleShape()
        let tabness = 1 - atHeader
        let halo = min(0.4, Theme.edgePaneGlowRest * 0.5 + 0.16 * Double(approach)) * Double(tabness)
        let chevronGlow = (0.10 + 0.16 * Double(approach)) * Double(tabness)
        let reach: CGFloat = 26

        return ZStack {
            shape.fill(Color.black)
                .overlay(shape.strokeBorder(.white.opacity(0.12 * tabness), lineWidth: 1))
                .opacity(Double(tabness))
            ZStack {
                Image(systemName: collapseChevron).opacity(1 - chevronShown)
                Image(systemName: revealChevron).opacity(chevronShown)
            }
            .font(.system(size: 13, weight: .semibold))
            .opacity(Double(tabness))
            .shadow(color: .white.opacity(chevronGlow), radius: 4)

            Image(systemName: headerSymbol)
                .font(.system(size: 15, weight: .medium))
                .opacity(Double(atHeader) * (isHovered ? 1.0 : 0.7))
        }
        .foregroundStyle(.white)
        .frame(width: Theme.edgePaneTabWidth, height: Theme.edgePaneTabHeight)
        .shadow(color: Theme.edgePaneGlow.opacity(halo), radius: 10)
        .shadow(color: Theme.edgePaneGlow.opacity(halo * 0.45), radius: 20)
        .mask {
            Rectangle()
                .frame(width: Theme.edgePaneTabWidth + reach,
                       height: Theme.edgePaneTabHeight + 2 * reach)
                .offset(x: haloSign * reach / 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { toggle() }
        .offset(y: topOffset)
        .animation(.easeInOut(duration: 0.18), value: approach)
    }
}

@MainActor
@Observable
final class EdgeProximity {
    var proximity: CGFloat = 0
    var cursorLocalY: CGFloat = 0

    @ObservationIgnored var edgeFrame: CGRect = .zero
    @ObservationIgnored weak var hostWindow: NSWindow?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var armTimer: Timer?
    @ObservationIgnored private var armed = false

    private let range: CGFloat = 20
    @ObservationIgnored var activationDelay: TimeInterval = 0.40
    @ObservationIgnored var headerHeight: CGFloat = 0

    func start() {
        stop()
        let track: (NSEvent) -> Void = { [weak self] _ in self?.handle() }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { track($0) },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { track($0); return $0 }
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        disarm()
    }

    private func handle() {
        guard let host = hostWindow, let content = host.contentView,
              edgeFrame != .zero else { return }
        let windowPoint = host.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: windowPoint.x, y: content.bounds.height - windowPoint.y)

        let dx = abs(point.x - edgeFrame.midX)
        let withinHeight = point.y >= edgeFrame.minY - 4 && point.y <= edgeFrame.maxY + 4
        guard dx <= range && withinHeight else { disarm(); return }

        let relY = point.y - edgeFrame.minY
        guard relY >= headerHeight else { disarm(); return }
        if abs(relY - cursorLocalY) > 0.5 { cursorLocalY = relY }

        guard armed else { scheduleArm(); return }

        if proximity != 1 { proximity = 1 }
    }

    private func scheduleArm() {
        guard armTimer == nil else { return }
        armTimer = Timer.scheduledTimer(withTimeInterval: activationDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.armTimer = nil
                self.armed = true
                self.handle()
            }
        }
    }

    private func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        armed = false
        if proximity != 0 { proximity = 0 }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.report(from: view, onResolve)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.report(from: nsView, onResolve)
    }

    final class Coordinator {
        private weak var last: NSWindow?
        private var delivered = false
        func report(from view: NSView, _ onResolve: @escaping (NSWindow?) -> Void) {
            DispatchQueue.main.async { [weak view] in
                let window = view?.window
                guard !self.delivered || window !== self.last else { return }
                self.last = window
                self.delivered = true
                onResolve(window)
            }
        }
    }
}

private struct EdgePanePreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preview")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(14)
            Divider().overlay(Theme.hairline)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.18))
    }
}

#Preview("EdgePane — trailing (open + tab)") {
    HStack(spacing: 0) {
        HStack(spacing: 0) {
            Color.black.frame(maxWidth: .infinity)
            EdgePane(edge: .trailing, fullWidth: 180, collapsed: false,
                     restingCenterFromTop: 22, toggle: {}) { EdgePanePreviewContent() }
        }
        Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        HStack(spacing: 0) {
            Color.black.frame(maxWidth: .infinity)
            EdgePane(edge: .trailing, fullWidth: 180, collapsed: true,
                     restingCenterFromTop: 22, toggle: {}) { EdgePanePreviewContent() }
        }
    }
    .frame(width: 560, height: 300)
    .background(Color.black)
    .environment(PanelPresentation())
}

#Preview("EdgePane — leading (open + tab)") {
    HStack(spacing: 0) {
        HStack(spacing: 0) {
            EdgePane(edge: .leading, fullWidth: 150, collapsed: false,
                     restingCenterFromTop: 22, toggle: {}) { EdgePanePreviewContent() }
            Color.black.frame(maxWidth: .infinity)
        }
        Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        HStack(spacing: 0) {
            EdgePane(edge: .leading, fullWidth: 150, collapsed: true,
                     restingCenterFromTop: 22, toggle: {}) { EdgePanePreviewContent() }
            Color.black.frame(maxWidth: .infinity)
        }
    }
    .frame(width: 560, height: 300)
    .background(Color.black)
    .environment(PanelPresentation())
}
