//
//  SidebarViewModel.swift
//  Nodee
//
//  Manages the sidebar's business logic: pinning folders as favorites,
//  removing them, and opening the system picker to add new ones. Views
//  call these methods and read only the state they need to render.
//

import AppKit
import SwiftData

@MainActor
@Observable
final class SidebarViewModel {
    private let container: ModelContainer
//    private let appState: AppState
    private let appState: FinderState

    init(container: ModelContainer, appState: FinderState) {
        self.container = container
        self.appState = appState
    }

    // MARK: - Favorites management

    func pin(_ urls: [URL], existingProjects: [PinnedProject]) {
        let context = container.mainContext
        let directories = urls.filter {
            let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }
        var nextIndex = (existingProjects.map(\.sortIndex).max() ?? -1) + 1
        for directory in directories {
            guard let bookmark = SecurityScopedBookmark.make(for: directory) else { continue }
            context.insert(PinnedProject(name: directory.lastPathComponent,
                                        bookmark: bookmark,
                                        sortIndex: nextIndex))
            nextIndex += 1
        }
        try? context.save()
    }

    func addViaPanel(existingProjects: [PinnedProject]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Adicionar"
        panel.message = "Escolha uma ou mais pastas para adicionar aos favoritos"
        NSApp.activate()
        let response = appState.runWithPanelLowered { panel.runModal() }
        if response == .OK { pin(panel.urls, existingProjects: existingProjects) }
    }

    func remove(_ project: PinnedProject) {
        if let resolved = SecurityScopedBookmark.resolve(project.bookmark) {
            appState.endAccess(resolved.url)
        }
        let context = container.mainContext
        context.delete(project)
        try? context.save()
    }
}
