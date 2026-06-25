//
//  FileKind.swift
//  Nodee
//
//  Classifies a file by extension and gives it a visual identity.
//  Principle: "Reconhecimento antes de leitura" — the user should know what
//  a file is before reading its name. Color, symbol and preview style per kind.
//

import SwiftUI

/// Visual category of a node, derived from its file extension.
nonisolated enum FileKind: String, Sendable {
    case markdown
    case image
    case pdf
    case data
    case code
    case folder
    case other

    // MARK: - Classification

    static func forExtension(_ ext: String) -> FileKind {
        let e = ext.lowercased()
        if markdownExtensions.contains(e) { return .markdown }
        if imageExtensions.contains(e) { return .image }
        if e == "pdf" { return .pdf }
        if dataExtensions.contains(e) { return .data }
        if codeExtensions.contains(e) { return .code }
        return .other
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdx", "txt", "text", "rtf"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "heic", "heif", "webp", "tiff", "tif", "bmp", "icns"]
    private static let dataExtensions: Set<String> = ["json", "yaml", "yml", "toml", "plist", "xml", "csv"]
    private static let codeExtensions: Set<String> = [
        "swift", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java", "kt",
        "c", "h", "cpp", "cc", "hpp", "m", "mm", "cs", "php", "sh", "zsh", "bash",
        "sql", "html", "css", "scss", "lua", "dart", "ex", "exs", "vue", "swiftpm"
    ]

    // MARK: - Visual identity

    /// Accent color used for the node's edge, symbol and highlights.
    var accentColor: Color {
        switch self {
        case .markdown: return Color(red: 0.62, green: 0.64, blue: 0.70) // neutral
        case .image:    return Color(red: 0.62, green: 0.64, blue: 0.70) // neutral (content is the thumbnail)
        case .pdf:      return Color(red: 0.86, green: 0.27, blue: 0.24) // red
        case .data:     return Color(red: 0.95, green: 0.66, blue: 0.13) // amber
        case .code:     return Color(red: 0.27, green: 0.73, blue: 0.44) // green
        case .folder:   return Color(red: 0.29, green: 0.55, blue: 0.96) // blue, distinct from files
        case .other:    return Color(red: 0.55, green: 0.57, blue: 0.62) // neutral
        }
    }

    var symbolName: String {
        switch self {
        case .markdown: return "doc.text"
        case .image:    return "photo"
        case .pdf:      return "doc.richtext"
        case .data:     return "curlybraces"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .folder:   return "folder.fill"
        case .other:    return "doc"
        }
    }

    /// How the node's body should be rendered on the canvas.
    enum PreviewStyle { case thumbnail, text, none }

    var previewStyle: PreviewStyle {
        switch self {
        case .image, .pdf:            return .thumbnail
        case .markdown, .data, .code: return .text
        case .folder, .other:         return .none
        }
    }
}
