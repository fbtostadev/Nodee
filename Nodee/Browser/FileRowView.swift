//
//  FileRowView.swift
//  Nodee
//
//  A single file/folder row shared by the List and Columns surfaces. Carries the
//  visual identity from FileKind (icon + color), an inline rename field, optional
//  disclosure triangle (list), size/modified columns (list) and a drill chevron
//  (columns). Purely presentational — selection and navigation live in the parent.
//

import SwiftUI

struct FileRowView: View {
    let file: FileNode
    let isSelected: Bool

    var depth: Int = 0
    var reservesDisclosure = false      // list: align leaves under folders
    var isExpanded = false
    var showsMetadata = false           // list: size + modified
    var showsChevron = false            // columns: folder drill affordance
    var isRenaming = false
    /// Triggers a horizontal shake animation when a rename fails.
    var isFailed = false
    /// Shows a dashed border when the file is in the in-app clipboard.
    var isInClipboard = false

    var onToggleDisclosure: () -> Void = {}
    var onCommitRename: (String) -> Void = { _ in }
    var onCancelRename: () -> Void = {}

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 14)
            }
            disclosure
            Image(systemName: file.kind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : file.kind.accentColor)
                .frame(width: 18)

            if isRenaming {
                RenameField(initial: file.name, isFailed: isFailed,
                            onCommit: onCommitRename, onCancel: onCancelRename)
            } else {
                Text(file.name)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if showsMetadata {
                Text(file.displaySize)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .white.opacity(0.4))
                    .frame(width: 64, alignment: .trailing)
                Text(file.displayModified)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .white.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 92, alignment: .trailing)
            }

            if showsChevron && file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .white.opacity(0.35))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .offset(x: shakeOffset)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    Color.accentColor.opacity(isInClipboard ? 0.5 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .contentShape(Rectangle())
        .onChange(of: isFailed) { _, failed in
            guard failed else { return }
            shakeOffset = 0
            withAnimation(.linear(duration: 0.05).repeatCount(6, autoreverses: true)) {
                shakeOffset = 5
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(620))
                shakeOffset = 0
            }
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if reservesDisclosure {
            if file.isDirectory {
                Button(action: onToggleDisclosure) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }
        }
    }
}

/// Inline rename text field: grabs focus on appear, commits on Return, cancels
/// on Escape. Used the moment a folder is created or a row enters rename.
private struct RenameField: View {
    let isFailed: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(initial: String, isFailed: Bool = false,
         onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initial)
        self.isFailed = isFailed
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { onCommit(text) }
            .onKeyPress(.escape) { onCancel(); return .handled }
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isFailed ? Color.red.opacity(0.18) : .clear)
                    .animation(.easeOut(duration: 0.2), value: isFailed)
            )
    }
}
