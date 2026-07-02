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

    /// Run `work` (a synchronous sandbox open/save panel `runModal`) with the
    /// floating Notch panel lowered, so the system picker isn't hidden behind it.
    /// Powerbox renders the picker out-of-process and ignores the level set on it
    /// locally.
    func runWithPanelLowered<T>(_ work: () -> T) -> T {
        controller?.runWithPanelLowered(work) ?? work()
    }

    /// Lower / restore the Notch panel level around an *async* picker (which uses
    /// `NSOpenPanel.begin` instead of a nested modal run loop).
    func lowerPanelLevel() { controller?.lowerPanelLevel() }
    func restorePanelLevel() { controller?.restorePanelLevel() }

    private func registerDefaultHotKey() {
        hotKey = GlobalHotKey(
            keyCode: GlobalHotKey.keyBackslash,
            modifiers: GlobalHotKey.optionOnly
        ) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Home access (the navigation root)

    /// Resolve the persisted Home bookmark and begin accessing it. Called once at
    /// launch. A stale bookmark is dropped so the grant CTA reappears.
    func resolveHomeAccess() {
        guard homeURL == nil,
              let data = UserDefaults.standard.data(forKey: Self.homeBookmarkKey),
              let resolved = SecurityScopedBookmark.resolve(data) else { return }
        if resolved.isStale {
            UserDefaults.standard.removeObject(forKey: Self.homeBookmarkKey)
            return
        }
        if resolved.url.startAccessingSecurityScopedResource() {
            accessedRoots.insert(resolved.url)
            homeURL = resolved.url
        }
    }

    /// Prompt the user to grant access to their Home folder. Returns the granted
    /// URL on success. The open panel is pre-pointed at the *real* Home, not the
    /// sandbox container, and lifted above the floating Notch panel.
    @discardableResult
    func grantHomeAccess() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.realHomeDirectory
        panel.prompt = "Conceder"
        panel.message = "Conceda acesso à sua pasta pessoal para o Nodee navegar seus arquivos"
        NSApp.activate()
        // Use the async, non-modal `begin` (never `runModal()`: a nested AppKit modal
        // run loop inside a Swift-concurrency `Task` on the MainActor is a known
        // crash vector). `begin` presents the picker as its own free-floating window
        // — no parent, so no sheet backdrop dimming the transparent Notch window (the
        // gray rectangle). Lower the Notch to `.normal` first so the picker isn't
        // hidden behind the always-on-top panel, and restore the level afterwards.
        //lowerPanelLevel()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        //restorePanelLevel()
        guard response == .OK, let url = panel.url,
              let bookmark = SecurityScopedBookmark.make(for: url) else { return nil }

        UserDefaults.standard.set(bookmark, forKey: Self.homeBookmarkKey)
        if url.startAccessingSecurityScopedResource() {
            accessedRoots.insert(url)
        }
        homeURL = url
        return url
    }

    /// Drop the persisted Home grant and stop accessing every scoped root, so the
    /// first-run onboarding can be tested again from scratch. The browser falls
    /// back to its access CTA until a new grant lands.
    func revokeHomeAccess() {
        UserDefaults.standard.removeObject(forKey: Self.homeBookmarkKey)
        for url in accessedRoots { url.stopAccessingSecurityScopedResource() }
        accessedRoots.removeAll()
        homeURL = nil
    }

    /// The user's real Home directory. Inside the sandbox
    /// `FileManager.homeDirectoryForCurrentUser` resolves to the app container
    /// (~/Library/Containers/...); `getpwuid` gives the true Home for the picker.
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Security-scoped access

    /// Resolve a favorite's bookmark and begin accessing it. The access is held
    /// for the app session and released when the favorite is removed.
    func beginAccess(_ project: PinnedProject) -> URL? {
        guard let resolved = SecurityScopedBookmark.resolve(project.bookmark) else { return nil }
        if accessedRoots.contains(resolved.url) { return resolved.url }
        // Only hand back a URL we actually hold a live scope on. A failed start
        // would otherwise let navigation proceed against an inaccessible root.
        guard resolved.url.startAccessingSecurityScopedResource() else { return nil }
        accessedRoots.insert(resolved.url)
        return resolved.url
    }

    func endAccess(_ url: URL) {
        guard accessedRoots.contains(url) else { return }
        // Never relinquish the Home grant — it backs all default-location navigation.
        if url == homeURL { return }
        url.stopAccessingSecurityScopedResource()
        accessedRoots.remove(url)
    }

    /// The granted root (Home or an open favorite) that contains `url` — the
    /// ceiling navigation may walk up to. Picks the broadest (shortest-prefix)
    /// grant, so a favorite nested under Home still lets you climb up to Home.
    func accessRoot(containing url: URL) -> URL? {
        let target = url.standardizedFileURL.path
        return accessedRoots
            .filter { root in
                let r = root.standardizedFileURL.path
                return target == r || target.hasPrefix(r + "/")
            }
            .min { $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count }
    }
}
