//
//  PreviewViewModel.swift
//  Nodee
//
//  Backs the preview pane: loads a folder's children off the main thread
//  and opens files in their default app. Views call these methods instead
//  of reaching into FileSystemService directly.
//

import Foundation

@MainActor
@Observable
final class PreviewViewModel {
    private(set) var folderChildren: [FileNode] = []

    func load(for file: FileNode) async {
        guard file.isDirectory else { folderChildren = []; return }
        let url = file.url
        folderChildren = await Task.detached(priority: .utility) {
            FileSystemService.children(of: url)
        }.value
    }

    func open(_ file: FileNode) {
        FileSystemService.open(file.url)
    }
}
