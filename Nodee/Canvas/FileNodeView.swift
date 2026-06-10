//
//  FileNodeView.swift
//  Nodee
//
//  Pure visual representation of a node at one of three scales:
//
//  - .full    — preview body + header (148×116), the richest form.
//  - .compact — icon + truncated name (88×34), context nodes.
//  - .dot     — coloured circle by FileKind (28×28), maximum compression.
//
//  Expanded folders (orbital centres) gain a soft radial glow to communicate
//  "gravity" — the visual cue that children orbit around them.
//

import SwiftUI

struct FileNodeView: View {
    let node: CanvasNode
    let isSelected: Bool
    var isDropTarget: Bool = false

    @State private var thumbnail: NSImage?
    @State private var snippet: String?

    private var kind: FileKind { node.file.kind }
    private var scale: NodeScale { node.scale }

    var body: some View {
        Group {
            switch scale {
            case .full:    fullBody
            case .compact: compactBody
            case .dot:     dotBody
            }
        }
        .scaleEffect(isDropTarget ? Theme.dropTargetScale : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTarget)
        .task(id: node.file.url) { await loadBody() }
    }

    // MARK: - Full scale (148×116)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewBody(for: kind.previewStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            header
        }
        .frame(width: NodeScale.full.size.width, height: NodeScale.full.size.height)
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: NodeScale.full.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: NodeScale.full.cornerRadius)
                .strokeBorder(fullStrokeColor, lineWidth: fullStrokeWidth)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .orbitalGlow(isExpanded: node.isExpanded, color: kind.accentColor)
    }

    private var fullStrokeColor: Color {
        if isDropTarget { return kind.accentColor }
        return isSelected ? Color.white : kind.accentColor.opacity(0.85)
    }

    private var fullStrokeWidth: CGFloat {
        if isDropTarget { return Theme.dropTargetStrokeWidth }
        return isSelected ? 2.5 : 1.5
    }

    // Header (always visible on full nodes: symbol + name)
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: node.file.isDirectory && node.isExpanded ? "folder.fill.badge.minus" : kind.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kind.accentColor)
            Text(node.file.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.black.opacity(0.25))
    }

    // Preview body per kind
    @ViewBuilder
    private func previewBody(for style: FileKind.PreviewStyle) -> some View {
        switch style {
        case .thumbnail:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                centeredSymbol
            }
        case .text:
            if let snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            } else {
                centeredSymbol
            }
        case .none:
            ZStack {
                centeredSymbol
                if kind == .other {
                    Text(node.file.displayExtension)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(y: 24)
                }
            }
        }
    }

    private var centeredSymbol: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(kind.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(kind.accentColor.opacity(0.10))
    }

    // MARK: - Compact scale (88×34)

    private var compactBody: some View {
        HStack(spacing: 4) {
            Image(systemName: node.file.isDirectory && node.isExpanded ? "folder.fill.badge.minus" : kind.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(kind.accentColor)
            Text(node.file.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 8)
        .frame(width: NodeScale.compact.size.width, height: NodeScale.compact.size.height)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: NodeScale.compact.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: NodeScale.compact.cornerRadius)
                .strokeBorder(compactStrokeColor, lineWidth: compactStrokeWidth)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .orbitalGlow(isExpanded: node.isExpanded, color: kind.accentColor)
    }

    private var compactStrokeColor: Color {
        if isDropTarget { return kind.accentColor }
        return isSelected ? Color.white : kind.accentColor.opacity(0.5)
    }

    private var compactStrokeWidth: CGFloat {
        if isDropTarget { return 2.5 }
        return isSelected ? 2 : 1
    }

    // MARK: - Dot scale (28×28)

    private var dotBody: some View {
        Circle()
            .fill(kind.accentColor.opacity(0.7))
            .frame(width: NodeScale.dot.size.width, height: NodeScale.dot.size.height)
            .overlay {
                Circle()
                    .strokeBorder(dotStrokeColor, lineWidth: dotStrokeWidth)
            }
            .shadow(color: kind.accentColor.opacity(0.3), radius: 3, y: 1)
            .help(node.file.name) // tooltip on hover
    }

    private var dotStrokeColor: Color {
        if isDropTarget { return .white }
        return isSelected ? .white : kind.accentColor.opacity(0.2)
    }

    private var dotStrokeWidth: CGFloat {
        isSelected || isDropTarget ? 2 : 0.5
    }

    // MARK: - Loading

    private func loadBody() async {
        guard scale.showsPreview else { return }
        switch kind.previewStyle {
        case .thumbnail:
            thumbnail = await PreviewStore.shared.thumbnail(
                for: node.file.url,
                size: CGSize(width: NodeScale.full.size.width, height: NodeScale.full.size.height)
            )
        case .text:
            snippet = await PreviewStore.shared.snippet(for: node.file.url)
        case .none:
            break
        }
    }
}

// MARK: - Orbital Glow modifier

private struct OrbitalGlowModifier: ViewModifier {
    let isExpanded: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isExpanded ? color.opacity(0.3) : .clear,
                radius: isExpanded ? 18 : 0
            )
    }
}

extension View {
    func orbitalGlow(isExpanded: Bool, color: Color) -> some View {
        modifier(OrbitalGlowModifier(isExpanded: isExpanded, color: color))
    }
}
