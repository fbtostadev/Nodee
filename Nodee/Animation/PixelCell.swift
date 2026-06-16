//
//  PixelCell.swift
//  Nodee
//
//  A single pixel of the glowing loader grid. The look (a hot, emissive square
//  blooming on black) does not come from one rectangle and one shadow — it comes
//  from *stacking*:
//    • `brightness`   fill rectangles layered in a ZStack → a denser core.
//    • the glow       several independent shadows of *different* radii and
//                     intensities, composited under the crisp square by
//                     `ShadowStack` → a soft, graduated bloom.
//  This mirrors how Figma's "Beautiful Shadows" works: rather than one halo (or
//  many identical ones, which only get brighter, never softer), a tight bright
//  halo near the edge fades through progressively wider, fainter ones, so the
//  dispersion eases smoothly out from the centre.
//
//  `color` is intentionally a plain parameter: for now every cell is white, but
//  the caller is meant to drive it per-action later (e.g. red for a delete).
//

import SwiftUI

/// One lit-or-dark square in the loader grid.
struct PixelCell: View {
    /// Whether the pixel is lit. When `false` it renders fully clear and casts no
    /// shadow, so dark cells are genuinely invisible against the black stage.
    let isOn: Bool
    /// Side length of the square, in points.
    let size: CGFloat
    /// The light's colour — driven per-action by the caller (white by default).
    let color: Color
    /// How many fill rectangles are stacked in the body. Higher → brighter core.
    var brightness: Int = 1
    /// Corner radius of the square (0 = hard pixel).
    var cornerRadius: CGFloat = 0
    /// The glow's layered-shadow recipe (radii, intensities, falloff).
    var glow: GlowStyle = .init()

    var body: some View {
        ZStack {
            ForEach(Array(0..<max(1, brightness)), id: \.self) { _ in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            }
        }
        .foregroundStyle(isOn ? color : .clear)
        .frame(width: size, height: size)
        .modifier(ShadowStack(enabled: isOn, color: color, style: glow))
    }
}

/// The recipe for a `PixelCell`'s bloom: `layers` independent shadows whose blur
/// grows by `× spread` and whose alpha shrinks by `÷ spread` per step, all cast
/// from the centre. Inner layers are tight and bright, outer ones wide and faint.
///
///     layer i → radius = baseRadius · spread^i
///               alpha  = baseOpacity / spread^i
///
/// With the defaults (5 layers, r₀ = 8, spread 1.6, α₀ = 0.5) the layers land at
/// roughly r = 8, 13, 20, 33, 52 and α = 0.50, 0.31, 0.20, 0.12, 0.08 — a hot
/// core easing into a soft ambient halo.
struct GlowStyle: Equatable {
    /// Number of stacked shadow layers. 0 disables the glow entirely.
    var layers: Int = 5
    /// Blur radius of the innermost (tightest, brightest) layer, in points.
    var baseRadius: CGFloat = 8
    /// Per-layer growth factor: each layer's radius ×= spread, its alpha ÷= spread.
    var spread: CGFloat = 1.6
    /// Alpha of the innermost layer; outer layers fall off from here.
    var baseOpacity: CGFloat = 0.5

    /// The same recipe with every radius multiplied by `factor`, keeping spread,
    /// opacity and layer count. Used to keep the bloom proportional when the cell
    /// is rendered at a different size than the one the recipe was tuned at — e.g.
    /// the tiny status pixels in the toolbar/toast vs. the big tuning stage.
    func scaled(by factor: CGFloat) -> GlowStyle {
        GlowStyle(layers: layers,
                  baseRadius: baseRadius * factor,
                  spread: spread,
                  baseOpacity: baseOpacity)
    }
}

/// Composites a `GlowStyle`'s shadow layers *under* its content so the square
/// itself stays crisp on top. Widest/faintest layers are drawn first (furthest
/// back) and the tightest, brightest one last, just beneath the core, so the hot
/// inner glow is never washed out by the diffuse outer layers. When `enabled` is
/// false no shadows are cast, so a dark pixel emits nothing.
struct ShadowStack: ViewModifier {
    let enabled: Bool
    let color: Color
    let style: GlowStyle

    func body(content: Content) -> some View {
        ZStack {
            if enabled {
                ForEach((0..<max(0, style.layers)).reversed(), id: \.self) { i in
                    let step = pow(style.spread, CGFloat(i))
                    content.shadow(color: color.opacity(min(1, style.baseOpacity / step)),
                                   radius: style.baseRadius * step, x: 0, y: 0)
                }
            }
            content
        }
    }
}

#Preview("PixelCell — glow") {
    HStack(spacing: 28) {
        PixelCell(isOn: true, size: 72, color: .white, brightness: 2)
        PixelCell(isOn: true, size: 72, color: Color(red: 1, green: 0.23, blue: 0.36),
                  brightness: 2)
        PixelCell(isOn: false, size: 72, color: .white)
    }
    .padding(60)
    .background(.black)
}
