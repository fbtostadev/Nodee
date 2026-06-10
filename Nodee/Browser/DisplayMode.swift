//
//  DisplayMode.swift
//  Nodee
//
//  The two well-established file-browsing paradigms Nodee adopts to "steal" the
//  Finder's primary job inside the Notch: a hierarchical List (disclosure
//  triangles) and Miller Columns (horizontal drill-down). The spatial canvas is
//  archived for now; these are the MVP's default surfaces.
//

import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case list
    case columns

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list:    return "Lista"
        case .columns: return "Colunas"
        }
    }

    var symbolName: String {
        switch self {
        case .list:    return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }
}
