//
//  PreviewPane.swift
//  Nodee
//
//  Contextual preview of the selected file, shown beside the browser. Folder →
//  list of immediate children with their visual identity; "other" → metadata +
//  open button; everything else → QuickLook. Takes a FileNode directly so it is
//  independent of any particular browsing surface (list, columns, canvas).
//

import SwiftUI
import AppKit

struct PreviewPane: View {
    let file: FileNode
    let width: CGFloat

    /// Cached folder listing, loaded once per file instead of re-reading disk on
    /// every body render. Only populated for folders (see .task below).
    @State private var folderChildren: [FileNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            content
        }
        .frame(width: width)
        .background(.black.opacity(0.18))
        .task(id: file.url) {
            // Read the disk once when the previewed file changes; skip the I/O for
            // non-folders, which never use the cached listing.
            folderChildren = file.isDirectory ? FileSystemService.children(of: file.url) : []
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: file.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(file.kind.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1).truncationMode(.middle)
                Text(file.isDirectory ? "Pasta" : file.displayExtension)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch file.kind {
        case .folder:
            folderListing
        case .other:
            metadata
        default:
            QuickLookPreview(url: file.url)
                .background(Color(white: 0.13))
        }
    }

    /// Read-only glimpse of a folder's contents. Deliberately styled *unlike* the
    /// interactive rows (FileRowView): a section caption + dimmed, desaturated,
    /// shorter lines with no full-width hit area, so it reads as inert information
    /// — at most scrollable — not as a navigable list inviting clicks.
    @ViewBuilder
    private var folderListing: some View {
        if folderChildren.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Pasta vazia")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Conteúdo · \(folderChildren.count) \(folderChildren.count == 1 ? "item" : "itens")")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    ForEach(folderChildren) { child in
                        HStack(spacing: 7) {
                            Image(systemName: child.kind.symbolName)
                                .font(.system(size: 10))
                                .foregroundStyle(child.kind.accentColor.opacity(0.55))
                                .frame(width: 16)
                            Text(child.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 21)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var metadata: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metaRow("Nome", file.name)
                metaRow("Extensão", file.displayExtension)
                if file.size != nil {
                    metaRow("Tamanho", file.displaySize)
                }
                if file.modifiedAt != nil {
                    metaRow("Modificado", file.displayModified)
                }
                Button {
                    FileSystemService.open(file.url)
                } label: {
                    Label("Abrir no app padrão", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(16)
            // Keep the CTA above the grabber hit area
            .padding(.bottom, Theme.grabberHitHeight)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
        }
    }
}
