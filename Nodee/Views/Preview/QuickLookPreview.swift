//
//  QuickLookPreview.swift
//  Nodee
//
//  Bridges QLPreviewView so the side panel can render markdown, images, PDFs
//  and code (with syntax highlighting) natively, without opening another app.
//  Preview is read-only — editing opens the right app.
//

import SwiftUI
import Quartz

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? URL) != url {
            nsView.previewItem = url as NSURL
        }
    }
}
