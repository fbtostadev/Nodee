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

    @State private var browser: BrowserViewModel
    @State private var toast = ToastCenter()
    /// The favorite explicitly opened (sidebar highlight). Locations highlight
    /// themselves live off the current directory.
    @State private var selectedFavoriteID: UUID?
    /// Independent visibility state for the content and shadow, driven by the
    /// onChange orchestrator below. Keeping them separate from `isExpanded`
    /// gives each layer its own animation timeline so the panel reads as a
    /// single solid block: shape expands first, content and shadow reveal after.
    @State private var contentVisible = false
    @State private var shadowVisible  = false

    /// Notch geometry for the screen the controller anchored the panel to. Derived
    /// (not stored) so it always tracks `presentation.activeScreen` — the same
    /// display the host window was placed on — keeping size, scale and the
    /// Notch-vs-pill shape consistent across built-in / external monitors.
    private var geometry: NotchGeometry {
        NotchGeometry(screen: presentation.activeScreen ?? NSScreen.main!)
    }

    private var locations: [SidebarLocation] { SidebarLocation.defaults(home: appState.homeURL) }

    /// Sidebar collapse lives in the shared presentation so the controller's
    /// three-finger swipe can toggle it — same effect as the toolbar toggle.
    private var isSidebarCollapsed: Bool { presentation.isSidebarCollapsed }
    private func setSidebarCollapsed(_ collapsed: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            presentation.isSidebarCollapsed = collapsed
        }
    }

    init(container: ModelContainer) {
        _browser = State(initialValue: BrowserViewModel(container: container))
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

            // The inner content, revealed only once expanded; masked to the
            // shape so it never spills out during the morph.
            surface
                .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
                .scaleEffect(1, anchor: .top)
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
        .offset(y: -6)
        .onAppear {
            browser.toast = toast
            appState.resolveHomeAccess()
            restoreSession()
        }
        .animation(presentation.isExpanded ? Theme.panelOpen : Theme.panelClose, value: presentation.isExpanded)
        .animation(Theme.notchStretch, value: presentation.isHoveringNotch)
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
                width: geometry.panelSize.width,
                height: geometry.panelSize.height,
                topCorner: geometry.hasNotch ? 12 : corner,
                bottomCorner: corner
            )
        }

        let hoverGrowth = presentation.isHoveringNotch ? Theme.notchHoverGrowth : 0
        let peekGrowth = presentation.openProgress * Theme.notchPeekGrowth
        let width = geometry.closedWidth + presentation.openProgress * 8
        let height = geometry.closedHeight + hoverGrowth + peekGrowth
        return ShapeMetrics(
            width: width,
            height: height,
            topCorner: geometry.hasNotch ? 0 : height / 2,
            bottomCorner: geometry.hasNotch ? min(14, height / 2) : height / 2
        )
    }

    private func panelShape(_ metrics: ShapeMetrics) -> AnyShape {
        if geometry.hasNotch {
            AnyShape(NotchShape(topCornerRadius: metrics.topCorner, bottomCornerRadius: metrics.bottomCorner))
        } else {
            AnyShape(DynamicIslandPillShape(cornerRadius: metrics.bottomCorner))
        }
    }

    private var surface: some View {
        let panelWidth = geometry.panelSize.width
        return HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView(
                    locations: locations,
                    projects: projects,
                    currentDirectory: browser.currentDirectory,
                    selectedFavoriteID: selectedFavoriteID,
                    width: Theme.sidebarWidth(panelWidth: panelWidth),
                    onSelectLocation: openLocation,
                    onSelectFavorite: openFavorite,
                    onCollapse: { setSidebarCollapsed(true) },
                    onDropFiles: dropFiles,
                    onDropIntoLocation: dropFilesIntoLocation
                )
                .transition(.move(edge: .leading).combined(with: .opacity))

                PaneDivider(paneSide: .leading, onCollapse: { setSidebarCollapsed(true) })
                    .transition(.opacity)
            }

            BrowserRootView(vm: browser, panelWidth: panelWidth, notchInset: geometry.topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if !appState.hasHomeAccess {
                        homeAccessCTA
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isSidebarCollapsed {
                        Button {
                            setSidebarCollapsed(false)
                        } label: {
                            Image(systemName: "square.lefthalf.filled")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 24, height: 32)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .padding(.top, 6)
                        .help("Expandir sidebar")
                        .transition(.opacity)
                    }
                }
                // Left invitation strip — visible when the sidebar is collapsed,
                // signals that a rightward swipe reveals it.
                .overlay(alignment: .leading) {
                    if isSidebarCollapsed {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.10), location: 0),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 12)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius * geometry.panelScale)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            // The handle that condenses the panel — only while expanded.
            if presentation.isExpanded {
                GrabberHandle()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            // Transient confirmation / Undo, floated just above the grabber.
            if let current = toast.current {
                ToastView(toast: current, center: toast)
                    .padding(.bottom, Theme.grabberHitHeight + 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: toast.current?.id)
    }

    /// First-run gate: with no Home grant the browser has nothing to show, so we
    /// invite the user to concede access. Granting lands them in their Home.
    private var homeAccessCTA: some View {
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
            Button(action: grantHomeAccess) {
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
        .background(Theme.canvasBackground)
    }

    // MARK: - Actions

    /// Open a standard Location (under the granted Home). Its access root is the
    /// broadest grant containing it — Home — so the user can climb back up to it.
    private func openLocation(_ location: SidebarLocation) {
        guard let root = appState.accessRoot(containing: location.url) else { return }
        selectedFavoriteID = nil
        browser.go(to: location.url, accessRoot: root)
    }

    /// Open a Favorite. Resolving its bookmark starts security-scoped access; the
    /// access root is its own folder (favorites may live outside Home).
    private func openFavorite(_ project: PinnedProject) {
        guard let url = appState.beginAccess(project) else { return }
        let root = appState.accessRoot(containing: url) ?? url
        selectedFavoriteID = project.id
        browser.go(to: url, accessRoot: root)
    }

    /// Files dropped onto a favorite's row: move (or ⌥-copy) them into that folder
    /// on disk. Resolving the bookmark starts security-scoped access; the browser
    /// records the operation for undo and toasts the confirmation.
    private func dropFiles(_ urls: [URL], into project: PinnedProject, copy: Bool) {
        guard let folder = appState.beginAccess(project) else { return }
        browser.move(urls, into: folder, copy: copy)
    }

    /// Files dropped onto a Location row: move (or ⌥-copy) into that standard
    /// folder. Locations live under the Home grant, already security-scoped, so
    /// the URL is moved into directly — no per-location bookmark to resolve.
    private func dropFilesIntoLocation(_ urls: [URL], into folder: URL, copy: Bool) {
        browser.move(urls, into: folder, copy: copy)
    }

    private func grantHomeAccess() {
        guard appState.grantHomeAccess() != nil else { return }
        restoreSession()
    }

    /// On launch / after granting: restore the last visited directory (if still
    /// reachable under a granted root), else land in Home. No-op without a grant —
    /// the CTA shows instead.
    private func restoreSession() {
        guard let home = appState.homeURL else { return }
        let last = browser.lastVisitedDirectory()
        if let last, FileSystemService.exists(last),
           let root = appState.accessRoot(containing: last) {
            selectedFavoriteID = nil
            browser.go(to: last, accessRoot: root)
        } else {
            browser.go(to: home, accessRoot: home)
        }
    }
}
