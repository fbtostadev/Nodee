//
//  QuickLookCoordinator.swift
//  Nodee
//
//  Drives the system Quick Look panel for the space-bar preview, mirroring the
//  Finder. Holds the URLs being previewed and feeds them to the shared
//  QLPreviewPanel. If the panel can't take focus over the Notch NSPanel, the
//  side PreviewPane still covers previewing — this is the richer, optional path.
//

import AppKit
import Quartz

@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()

    private var urls: [URL] = []

    /// Toggle Quick Look for `urls`: open if hidden, close if already showing.
    func toggle(_ urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            present(urls)
        }
    }

    private func present(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
