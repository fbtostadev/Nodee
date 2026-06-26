//
//  SurfaceView.swift
//  Nodee
//
//  Created by Wise on 25/06/26.
//

import SwiftUI
import Foundation
import SwiftData


struct FinderView: View {
    @Environment(AppState.self) private var appState
    @Environment(PanelPresentation.self) private var presentation
    @Query(sort: \PinnedProject.sortIndex) private var projects: [PinnedProject]

    let panelVM: PanelViewModel
    let sidebarVM: SidebarViewModel
    /// Independent visibility state for the content and shadow, driven by the
    /// onChange orchestrator below. Keeping them separate from `isExpanded`
    /// gives each layer its own animation timeline so the panel reads as a
    /// single solid block: shape expands first, content and shadow reveal after.
    @State private var contentVisible = false
    @State private var shadowVisible  = false
    
    let panelWidth: CGFloat
    let geometry: NotchGeometry

    private var locations: [SidebarLocation] { SidebarLocation.defaults(home: appState.homeURL) }
    private var browser: BrowserViewModel { panelVM.browser }

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

    
    var body: some View {
        return HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView(
                    vm: sidebarVM,
                    locations: locations,
                    projects: projects,
                    currentDirectory: browser.currentDirectory,
                    selectedFavoriteID: panelVM.selectedFavoriteID,
                    width: Theme.sidebarWidth(panelWidth: panelWidth),
                    onSelectLocation: { panelVM.openLocation($0) },
                    onSelectFavorite: { panelVM.openFavorite($0) },
                    onCollapse: { setSidebarCollapsed(true) },
                    onDropFiles: { panelVM.dropFiles($0, into: $1, copy: $2) },
                    onDropIntoLocation: { panelVM.dropFilesIntoLocation($0, into: $1, copy: $2) }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                
                PaneDivider(paneSide: .leading, gutter: .sidebarTrailing, action: { setSidebarCollapsed(true) })
                    .zIndex(1) // keep the handle aura above the browser pane
                    .transition(.opacity)
            }
            
            BrowserRootView(vm: browser, panelWidth: panelWidth, notchInset: geometry.topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if !appState.hasHomeAccess {
                        homeAccessCTA(panelVM: panelVM)
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
            // Edge handle to reveal the sidebar — chevron CTA on the left margin.
                .overlay(alignment: .leading) {
                    if isSidebarCollapsed {
                        PaneDivider(paneSide: .leading, mode: .expand, action: { setSidebarCollapsed(false) })
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
            if let current = panelVM.toast.current {
                ToastView(toast: current, center: panelVM.toast)
                    .padding(.bottom, Theme.grabberHitHeight + 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: panelVM.toast.current?.id)
    }
}
