//
//  PreviewStore.swift
//  Nodee
//
//  Memoizes per-file visual content so panning/zooming the canvas never
//  regenerates thumbnails. Thumbnails come from QuickLook (rich, free for
//  images and PDF first pages); text snippets are read off-main.
//

import SwiftUI
import QuickLookThumbnailing

@MainActor
@Observable
final class PreviewStore {
    static let shared = PreviewStore()

    private var thumbnails: [URL: NSImage] = [:]
    private var snippets: [URL: String] = [:]

    /// QuickLook thumbnail for image / PDF nodes.
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        if let cached = thumbnails[url] { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2,
            representationTypes: .thumbnail
        )
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        let image = representation?.nsImage
        if let image { thumbnails[url] = image }
        return image
    }

    /// First lines of a text-based file, read off the main thread.
    func snippet(for url: URL, maxBytes: Int = 4096, maxLines: Int = 8) async -> String? {
        if let cached = snippets[url] { return cached }

        let text = await Task.detached(priority: .utility) { () -> String? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
            guard let string = String(data: data, encoding: .utf8) else { return nil }
            let lines = string
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(maxLines)
            return lines.joined(separator: "\n")
        }.value

        if let text { snippets[url] = text }
        return text
    }

    /// Drop cached content for a URL that vanished from disk.
    func invalidate(_ url: URL) {
        thumbnails[url] = nil
        snippets[url] = nil
    }
}
