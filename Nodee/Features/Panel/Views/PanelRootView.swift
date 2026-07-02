//
//  PanelRootView.swift
//  Nodee
//
//  Root of the Notch panel: sidebar + canvas + contextual preview, wrapped in
//  the surface that scales/fades from the top to read as "emerging from the
//  Notch".
//

import SwiftUI
import SwiftData

struct PanelRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(PanelPresentation.self) private var presentation
    @Query(sort: \PinnedProject.sortIndex) private var projects: [PinnedProject]
    
    //FinderViewModel
    //MediaPlayerViewModel
    //TimerViewModel
    //NotesViewModel
    @State private var featureSelection: Features = .fileManager
    
    @State private var panelVM: PanelViewModel
//    @State private var sidebarVM: SidebarViewModel
    /// Independent visibility state for the content and shadow, driven by the
    /// onChange orchestrator below. Keeping them separate from `isExpanded`
    /// gives each layer its own animation timeline so the panel reads as a
    /// single solid block: shape expands first, content and shadow reveal after.
    @State private var contentVisible = false
    @State private var shadowVisible  = false
    let container: ModelContainer
    
    /// Notch geometry for the screen the controller anchored the panel to. Derived
    /// (not stored) so it always tracks `presentation.activeScreen` — the same
    /// display the host window was placed on — keeping size, scale and the
    /// Notch-vs-pill shape consistent across built-in / external monitors.
    private var geometry: NotchGeometry {
        NotchGeometry(screen: presentation.activeScreen ?? NSScreen.main!)
    }
    
    private var locations: [SidebarLocation] { SidebarLocation.defaults(home: appState.homeURL) }
    private var browser: BrowserViewModel { panelVM.browser }
    
    /// Vertical shift that tucks the compact Notch above the top edge on displays
    /// that conceal it (external monitors / fullscreen), bringing it back down as
    /// the pointer nears the top-centre. Zero while expanded or on the always-on
    /// built-in notch, so nothing changes there.
    private var concealOffset: CGFloat {
        guard presentation.concealsNotch, !presentation.isExpanded else { return 0 }
        let hiddenDistance = geometry.closedHeight + 10
        return -hiddenDistance * (1 - presentation.notchReveal)
    }
    
    /// How much the whole panel widens to fund a near handle's gutter: the sum of
    /// the active edge reveals × the gutter. The Notch expands horizontally instead
    /// of any pane ceding space, so directory strings never truncate. At most one
    /// handle is near at a time, so this is ≈ one gutter — discreet and smooth.
    private var gutterWidthBoost: CGFloat {
        (presentation.sidebarTrailingReveal
         + presentation.previewLeadingReveal) * Theme.paneHandleGutter
    }
    
    /// Sidebar collapse lives in the shared presentation so the controller's
    /// three-finger swipe can toggle it — same effect as the toolbar toggle.
    private var isSidebarCollapsed: Bool { presentation.isSidebarCollapsed }
    private func setSidebarCollapsed(_ collapsed: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            presentation.isSidebarCollapsed = collapsed
        }
    }
    
    init(container: ModelContainer, appState: AppState) {
        self.container = container
        let browser = BrowserViewModel(container: container)
        _panelVM = State(initialValue: PanelViewModel(appState: appState, browser: browser))
    }
    
    var body: some View {
        let metrics = currentMetrics
        
        ZStack(alignment: .top) {
            // The solid shape that mimics the hardware notch / island expanding.
            panelShape(metrics)
                .fill(Theme.panelBackground)
                .frame(width: metrics.width, height: metrics.height)
                .shadow(
                    color: .black.opacity(shadowVisible ? 0.45 : 0),
                    radius: 28,
                    y: 0
                )
            
            //Contents of the open notch
            VStack {
                if geometry.hasFullscreenWindow {
                    Rectangle()
                        .frame(width: geometry.panelSize.width + gutterWidthBoost, height: geometry.topInset)
                        .scaleEffect(1, anchor: .top)
                        .opacity(contentVisible ? 1 : 0)
                        .mask {
                            panelShape(metrics)
                                .frame(width: metrics.width, height: metrics.height)
                        }
                        .foregroundStyle(Color.black)
                }
//                ToolbarView(selection: $featureSelection)
                surface
                Spacer()
            }
            
            //Grabber
            .overlay(alignment: .bottom) {
                if presentation.isExpanded {
                    GrabberHandle()
                        .transition(.opacity)
                }
            }
            //Makes so that the content, doesn't spill over.
            .frame(width: geometry.panelSize.width + gutterWidthBoost, height: geometry.panelSize.height)
            .scaleEffect(1, anchor: .top)
            .background(.black)
            .opacity(contentVisible ? 1 : 0)
            .mask {
                panelShape(metrics)
                    .frame(width: metrics.width, height: metrics.height)
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The host window's top edge sits on the physical screen top; without
        // this SwiftUI insets the content below the menu bar, dropping the notch
        // shape a menu-bar's height too low. Ignore it so the shape is flush
        // with the hardware notch / top edge.
        .ignoresSafeArea()
        .offset(y: -6 + concealOffset)
        .onAppear {
            panelVM.onAppear()
        }
        .animation(presentation.isExpanded ? Theme.panelOpen : Theme.panelClose, value: presentation.isExpanded)
        .animation(Theme.notchStretch, value: presentation.isHoveringNotch)
        // Slide the concealed Notch up out of view and back as the pointer nears.
        .animation(Theme.notchStretch, value: concealOffset)
        // Discreet, smooth horizontal growth as a pane handle is approached.
        .animation(.smooth(duration: 0.35), value: gutterWidthBoost)
        // Phase orchestrator: content and shadow have independent timelines so the
        // panel reads as one solid block. On open the shape leads; content and
        // shadow reveal after it has visibly grown. On close both vanish first so
        // only the clean black shape retracts to the Notch.
        .onChange(of: presentation.isExpanded) { _, expanded in
            if expanded {
                withAnimation(Theme.panelOpen.delay(Theme.panelContentRevealDelay)) {
                    contentVisible = true
                }
                withAnimation(Theme.panelOpen.delay(Theme.panelShadowRevealDelay)) {
                    shadowVisible = true
                }
            } else {
                withAnimation(Theme.panelOverlayDismiss) {
                    contentVisible = false
                    shadowVisible  = false
                }
            }
        }
    }
    
    // MARK: - Shape morphing
    
    /// Resolved size + corner radii for the current state. Condensed, the notch
    /// grows slightly on hover and peeks down under an in-flight open gesture
    /// (the minimal "stretch"); expanded, it becomes the full panel.
    private struct ShapeMetrics {
        var width: CGFloat
        var height: CGFloat
        var topCorner: CGFloat
        var bottomCorner: CGFloat
    }
    
    private var currentMetrics: ShapeMetrics {
        if presentation.isExpanded {
            let corner = Theme.panelCornerRadius * geometry.panelScale
            return ShapeMetrics(
                width: geometry.panelSize.width + gutterWidthBoost,
                height: geometry.panelSize.height,
                // Flat-ish top when anchored to the top edge — a hardware notch, or
                // a concealed/external display where the canvas is pinned to the top
                // (so it reads as a rectangle emerging from the top edge instead of a
                // rounded panel floating below it over a fullscreen app).
                topCorner: presentation.concealsNotch ? 0 : corner,
                bottomCorner: corner
            )
        }
        
        let hoverGrowth = presentation.isHoveringNotch ? Theme.notchHoverGrowth : 0
        let peekGrowth = presentation.openProgress * Theme.notchPeekGrowth
        let width = geometry.closedWidth + presentation.openProgress * 8
        let height = geometry.closedHeight + hoverGrowth + peekGrowth
        // While concealed (external display / fullscreen) the compact shape reads
        // as a notch flush to the top edge — flat top, rounded bottom — so the
        // reveal peeks down like the hardware notch instead of a floating pill.
        let notchShaped = geometry.hasNotch || presentation.concealsNotch
        return ShapeMetrics(
            width: width,
            height: height,
            topCorner: notchShaped ? 0 : height / 2,
            bottomCorner: notchShaped ? min(14, height / 2) : height / 2
        )
    }
    
    /// Whether the panel draws as a notch (independent top/bottom corners) rather
    /// than a fully-rounded pill: physical notch screens always, plus concealed
    /// displays (so the compact peek stays flush to the edge). Kept true through
    /// the expand so the shape type never swaps mid-morph — expanded just rounds
    /// the top corners back via the metrics.
    private var usesNotchShape: Bool {
        geometry.hasNotch || presentation.concealsNotch
    }
    
    private func panelShape(_ metrics: ShapeMetrics) -> AnyShape {
        if usesNotchShape {
            AnyShape(NotchShape(topCornerRadius: metrics.topCorner, bottomCornerRadius: metrics.bottomCorner))
        } else {
            AnyShape(DynamicIslandPillShape(cornerRadius: metrics.bottomCorner))
        }
    }
    @ViewBuilder
    private var surface: some View {
        let panelWidth = geometry.panelSize.width
        
        switch featureSelection {
        case .fileManager:
            FinderView(panelVM: panelVM, sidebarVM: SidebarViewModel(container: container, appState: appState), panelWidth: panelWidth, geometry: geometry)
        case .timer:
            EmptyView()
        case .notes:
            EmptyView()
        case .mediaPlayer:
            EmptyView()
        }
    }
    
    /// First-run gate: with no Home grant the browser has nothing to show, so we
    /// invite the user to concede access. Granting lands them in their Home.
    var homeAccessCTA: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("Conceda acesso aos seus arquivos")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("O Nodee navega tudo dentro da sua pasta pessoal.\nSelecione-a uma vez para começar.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button {
                Task { await panelVM.grantHomeAccess() }} label: {
                    Text("Conceder acesso à pasta pessoal")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panelBackground)
    }
    
}
