//
//  NodeScale.swift
//  Nodee
//
//  Three tiers of visual density for canvas nodes. The orbital layout assigns a
//  scale to each node based on its depth relative to the focal expansion — this
//  is what lets the 20% Notch panel show a deep tree without drowning in detail.
//
//  - .full:    preview body + header, the richest representation.
//  - .compact: icon + truncated name, no preview. Good for context nodes.
//  - .dot:     colored circle by FileKind. Maximum compression; tooltip on hover.
//

import Foundation
import CoreGraphics

enum NodeScale: Sendable {
    case full
    case compact
    case dot

    var size: CGSize {
        switch self {
        case .full:    return CGSize(width: 148, height: 116)
        case .compact: return CGSize(width: 88, height: 34)
        case .dot:     return CGSize(width: 28, height: 28)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .full:    return 12
        case .compact: return 8
        case .dot:     return 14
        }
    }

    var showsName: Bool { self != .dot }
    var showsPreview: Bool { self == .full }
}
