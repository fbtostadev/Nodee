//
//  FileNode.swift
//  Nodee
//
//  Runtime representation of a single item on disk. Identity is the file URL —
//  the canvas is always a faithful mirror of the file system, never a cache
//  that can drift out of sync.
//

import Foundation

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    /// Standardized file URL. Doubles as the stable identity of the node.
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileExtension: String
    let kind: FileKind
    /// Byte size of the file; nil for directories (and on read error).
    let size: Int?
    /// Last content modification date; nil on read error.
    let modifiedAt: Date?

    var id: URL { url }

    init(url: URL) {
        let standardized = url.standardizedFileURL
        self.url = standardized
        self.name = standardized.lastPathComponent

        // One disk read for everything the list/columns views show — kept lean so
        // listing a large folder stays cheap.
        let values = try? standardized.resourceValues(forKeys: [
            .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey
        ])
        // Bundles (.app, .pages, .numbers, .key, .rtfd, .framework, …) are
        // directories on disk but the OS — and the user — treat them as a single
        // file. We surface them as files so they open in their app instead of
        // letting the user navigate inside the package.
        let isPackage = values?.isPackage ?? false
        let isNavigableDir = (values?.isDirectory ?? false) && !isPackage
        self.isDirectory = isNavigableDir
        self.size = isNavigableDir ? nil : values?.fileSize
        self.modifiedAt = values?.contentModificationDate

        let ext = standardized.pathExtension.lowercased()
        self.fileExtension = ext
        self.kind = isNavigableDir ? .folder : FileKind.forExtension(ext)
    }

    /// Label shown when the file has no extension (rare) or for the "other" kind.
    var displayExtension: String {
        fileExtension.isEmpty ? "—" : fileExtension.uppercased()
    }

    /// Human-readable size ("1.2 MB"); "--" for directories or unknown size.
    var displaySize: String {
        guard let size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Relative modification date ("ontem", "há 3 dias"); "--" when unknown.
    var displayModified: String {
        guard let modifiedAt else { return "--" }
        return modifiedAt.formatted(.relative(presentation: .named))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(url) }
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
}
