//
//  PanelViewModel.swift
//  Nodee
//
//  Coordinates app-level navigation: opening Locations and Favorites from
//  the sidebar, dropping files into them, granting Home access, and
//  restoring the last session. Also owns the ToastCenter so the browser
//  can queue feedback without reaching into UI layer.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class PanelViewModel {
    private let appState: AppState
    let browser: BrowserViewModel
    let toast = ToastCenter()

    private(set) var selectedFavoriteID: UUID?

    init(appState: AppState, browser: BrowserViewModel) {
        self.appState = appState
        self.browser = browser
        // Wire the toast immediately so the browser can queue notifications
        // as soon as file operations run, without any view-lifecycle dependency.
        browser.toast = toast
    }

    // MARK: - Lifecycle

    func onAppear() {
        appState.resolveHomeAccess()
        restoreSession()
    }

    // MARK: - Sidebar navigation

    func openLocation(_ location: SidebarLocation) {
        guard let root = appState.accessRoot(containing: location.url) else { return }
        selectedFavoriteID = nil
        browser.go(to: location.url, accessRoot: root)
    }

    func openFavorite(_ project: PinnedProject) {
        guard let url = appState.beginAccess(project) else { return }
        let root = appState.accessRoot(containing: url) ?? url
        selectedFavoriteID = project.id
        browser.go(to: url, accessRoot: root)
    }

    // MARK: - Drop into sidebar items

    func dropFiles(_ urls: [URL], into project: PinnedProject, copy: Bool) {
        guard let folder = appState.beginAccess(project) else { return }
        browser.move(urls, into: folder, copy: copy)
    }

    func dropFilesIntoLocation(_ urls: [URL], into folder: URL, copy: Bool) {
        browser.move(urls, into: folder, copy: copy)
    }

    // MARK: - Home access

    @discardableResult
    func grantHomeAccess() -> Bool {
        guard appState.grantHomeAccess() != nil else { return false }
        restoreSession()
        return true
    }

    // MARK: - Session restore

    func restoreSession() {
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
