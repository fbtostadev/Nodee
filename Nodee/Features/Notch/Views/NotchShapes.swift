//
//  NotchShapes.swift
//  Nodee
//
//  Custom shapes for the Notch panel to simulate the "Dynamic Island" feel.
//

import SwiftUI

/// Custom shape for physical notch screens, supporting independent top/bottom corner radii.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Top left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topCornerRadius))
        if topCornerRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
                radius: topCornerRadius,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
        }
        
        // Top right
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY))
        if topCornerRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius),
                radius: topCornerRadius,
                startAngle: Angle(degrees: -90),
                endAngle: Angle(degrees: 0),
                clockwise: false
            )
        }
        
        // Bottom right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomCornerRadius))
        if bottomCornerRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomCornerRadius, y: rect.maxY - bottomCornerRadius),
                radius: bottomCornerRadius,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
        }
        
        // Bottom left
        path.addLine(to: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY))
        if bottomCornerRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY - bottomCornerRadius),
                radius: bottomCornerRadius,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
        }
        
        path.closeSubpath()
        return path
    }
}

/// A standard capsule shape for non-notch screens.
struct DynamicIslandPillShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}
