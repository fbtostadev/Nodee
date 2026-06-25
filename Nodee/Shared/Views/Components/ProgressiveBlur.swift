//
//  ProgressiveBlur.swift
//  Nodee
//
//  A bottom progressive blur for the browser surface. It blurs the *live* list
//  behind it with a within-window NSVisualEffectView, layered as an overlay — so
//  it never has to flatten the content. (A SwiftUI layerEffect / .blur can't be
//  used here: the rows host an AppKit FileDragLayer NSViewRepresentable, which
//  cannot be rendered into a flattened layer.)
//
//  A dark material plus a black tint gradient keeps the band close to #000000
//  rather than the light-grey cast of .ultraThinMaterial, and a mask ramps the
//  blur in toward the bottom so the rows dissolve into the panel above the grabber.
//

import SwiftUI
import AppKit

struct ProgressiveBlur: View {
    var height: CGFloat
    var tint: Color = Theme.panelBackground

    var body: some View {
        ZStack {
            // Real backdrop blur of the rows behind, ramped in from the top of the
            // band so the blur grows toward the bottom edge.
            VisualEffectBackdrop()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.6), location: 0.4),
                            .init(color: .black, location: 0.8)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Fade to the panel's black so the bottom strip reads as #000000, not
            // the material's residual grey.
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(0), location: 0),
                    .init(color: tint.opacity(0.85), location: 0.7),
                    .init(color: tint, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

/// A within-window dark visual-effect view: blurs whatever is behind it inside the
/// panel window (the scrolling rows) without flattening them.
private struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .underPageBackground // the darkest standard material
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
