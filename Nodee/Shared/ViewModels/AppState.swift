//
//  AppState.swift
//  Nodee
//
//  App-wide state shared between the menu bar scene and the Notch panel. Holds
//  the SwiftData container, drives the panel controller, and owns the global
//  hotkey. It also owns the sandbox access layer: a broad grant on the user's
//  Home folder (the effective navigation root) plus any favorites opened this
//  session.
//

import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppState {
    let container: ModelContainer
    var isPanelOpen = false

    /// The user's real Home folder, once granted. Nil until the user concedes
    /// access (or after a stale bookmark is dropped). When set, the whole subtree
    /// (Desktop/Documents/Downloads/projects) is reachable through one bookmark.
    private(set) var homeURL: URL?
    var hasHomeAccess: Bool { homeURL != nil }

    @ObservationIgnored private weak var controller: NotchPanelController?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    /// Security-scoped roots we've started accessing, so we can stop on remove.
    /// Includes the Home grant and any favorites opened this session.
    @ObservationIgnored private var accessedRoots: Set<URL> = []

    private static let homeBookmarkKey = "nodee.homeBookmark"

    init(container: ModelContainer) {
        self.container = container
    }

    func attach(controller: NotchPanelController) {
        self.controller = controller
        registerDefaultHotKey()
    }

    // MARK: - Panel

    func togglePanel() { controller?.toggle() }
    func openPanel() { controller?.open() }
    func closePanel() { controller?.close() }

    /// Run `work` (a sandbox open/save panel `runModal`) with the always-on-top
    /// Notch panel lowered, so the system picker isn't hidden behind it. Powerbox
    /// renders the picker out-of-process and ignores the level set on it locally.
    func runWithPanelLowered<T>(_ work: () -> T) -> T {
        controller?.runWithPanelLowered(work) ?? work()
    }

    private func registerDefaultHotKey() {
        hotKey = GlobalHotKey(
            keyCode: GlobalHotKey.keyBackslash,
            modifiers: GlobalHotKey.optionOnly
        ) { [weak self] in
            self?.togglePanel()
        }
    }
}
