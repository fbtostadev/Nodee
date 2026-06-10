//
//  SidebarLocation.swift
//  Nodee
//
//  The Finder-style "Locais" section of the sidebar: standard folders derived
//  from the granted Home. They aren't persisted — they're computed each time the
//  Home grant resolves, and all live under the single broad bookmark, so no
//  per-location access is needed.
//

import Foundation

struct SidebarLocation: Identifiable, Hashable {
    let name: String
    let systemImage: String
    let url: URL

    var id: URL { url }

    /// Default locations under `home`, keeping only those that exist on disk.
    static func defaults(home: URL?) -> [SidebarLocation] {
        guard let home else { return [] }
        let candidates: [(String, String, String?)] = [
            ("Início", "house", nil),
            ("Desktop", "menubar.dock.rectangle", "Desktop"),
            ("Documentos", "doc", "Documents"),
            ("Downloads", "arrow.down.circle", "Downloads"),
        ]
        return candidates.compactMap { name, image, sub in
            let url = sub.map { home.appendingPathComponent($0) } ?? home
            guard FileSystemService.exists(url) else { return nil }
            return SidebarLocation(name: name, systemImage: image, url: url)
        }
    }
}
