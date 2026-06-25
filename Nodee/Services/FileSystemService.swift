//
//  FileSystemService.swift
//  Nodee
//
//  Reads the disk. Pure functions — no caching, no state. The canvas asks for
//  the children of a folder whenever it needs the truth.
//

import Foundation
import AppKit

nonisolated enum FileSystemService {
    /// Direct children of a folder, hidden files skipped, folders first then
    /// case-insensitive name order. Returns [] on any access error rather than
    /// surfacing a broken state ("não há nós zumbis, não há estados de erro").
    static func children(of url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .map(FileNode.init(url:))
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Move `source` into `folder`, resolving name collisions ("name 2.ext",
    /// "name 3.ext"…). Returns the new URL, or nil on any error — the canvas
    /// re-reads disk via FSEvents, so failures just leave the node where it was
    /// (no error state, no zombie nodes).
    static func move(_ source: URL, into folder: URL) -> URL? {
        let destination = nonCollidingURL(for: source.lastPathComponent, in: folder)
        // No-op move (e.g. dropped into its current parent): nothing to do.
        guard destination.standardizedFileURL != source.standardizedFileURL else { return source }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    // MARK: - File operations
    //
    // Mutations that "steal" the Finder's primary job. Same contract as move():
    // best-effort, no thrown errors surfaced to the UI — failures just leave disk
    // untouched and FSEvents keeps the browser a faithful mirror either way.

    /// Open in the user's default app (Finder double-click equivalent).
    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// Rename in place, resolving collisions ("name 2.ext"). Returns the new URL,
    /// or nil on error / empty name / no-op rename.
    static func rename(_ url: URL, to newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != url.lastPathComponent else { return nil }
        let folder = url.deletingLastPathComponent()
        let destination = nonCollidingURL(for: trimmed, in: folder)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Create a new folder inside `parent`, resolving name collisions. Returns the
    /// created folder's URL, or nil on error.
    static func createFolder(in parent: URL, name: String = "Nova pasta") -> URL? {
        let destination = nonCollidingURL(for: name, in: parent)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            return destination
        } catch {
            return nil
        }
    }

    /// Create an empty file inside `parent`, resolving name collisions. Returns the
    /// created file's URL, or nil on error.
    static func createFile(in parent: URL, name: String = "Novo arquivo.txt") -> URL? {
        let destination = nonCollidingURL(for: name, in: parent)
        return FileManager.default.createFile(atPath: destination.path, contents: nil) ? destination : nil
    }

    /// Reveal items in the Finder (select them in a Finder window). The one place
    /// Nodee hands off to the Finder on purpose, for the operations it doesn't own.
    static func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Move items to the Trash (recoverable delete). Returns, for each item that
    /// was successfully trashed, the original location and where it landed in the
    /// Trash — the pair undo needs to put it back.
    @discardableResult
    static func moveToTrash(_ urls: [URL]) -> [(original: URL, trashed: URL)] {
        urls.compactMap { url in
            var landed: NSURL?
            guard (try? FileManager.default.trashItem(at: url, resultingItemURL: &landed)) != nil,
                  let trashed = landed as URL? else { return nil }
            return (original: url, trashed: trashed)
        }
    }

    /// Move `source` to an exact destination, restoring it (undo of move/trash).
    /// Recreates missing intermediate parents so a restore survives the original
    /// folder being gone; falls back to a non-colliding name if the exact spot is
    /// taken. Returns the resulting URL, or nil on error.
    static func move(_ source: URL, to destination: URL) -> URL? {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return source }
        let parent = destination.deletingLastPathComponent()
        if !exists(parent) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let target = exists(destination)
            ? nonCollidingURL(for: destination.lastPathComponent, in: parent)
            : destination
        do {
            try FileManager.default.moveItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }

    /// Duplicate an item beside itself ("name 2.ext"). Returns the copy's URL.
    static func duplicate(_ url: URL) -> URL? {
        let folder = url.deletingLastPathComponent()
        let destination = nonCollidingURL(for: url.lastPathComponent, in: folder)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Copy items into `folder`, resolving collisions. Returns the new URLs.
    @discardableResult
    static func copy(_ urls: [URL], into folder: URL) -> [URL] {
        urls.compactMap { source in
            let destination = nonCollidingURL(for: source.lastPathComponent, in: folder)
            guard destination.standardizedFileURL != source.standardizedFileURL else { return nil }
            return (try? FileManager.default.copyItem(at: source, to: destination)) != nil ? destination : nil
        }
    }

    /// A free URL inside `folder` for `name`, appending " 2", " 3"… before the
    /// extension when needed.
    private static func nonCollidingURL(for name: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard exists(candidate) else { return candidate }

        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let suffixed = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let url = folder.appendingPathComponent(suffixed)
            if !exists(url) { return url }
            index += 1
        }
    }

    /// Path of `url` relative to `root` (used as the stable layout key).
    static func relativePath(of url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents
        else { return url.lastPathComponent }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
