//
//  PixelCell.swift
//  Nodee
//
//  A single lit square of the loader grid — just the crisp core. The bloom around
//  it is no longer a per-cell stack of `.shadow()`s (that quantised five
//  translucent layers over black and came out grainy, and re-blurred every cell
//  every frame, which stuttered); it is now one analytic Metal pass shared by the
//  whole grid (see `PixelBloom.metal`, driven from `PixelLoaderView`). So the cell
//  itself is only the sharp emissive square; the grid fades it via `.opacity`.
//
//  `color` is intentionally a plain parameter: for now every cell is white, but
//  the caller drives it per-action (e.g. red for a delete, green for success).
//

import SwiftUI

/// One sharp square of the loader grid. Lit/dark is expressed by the caller via
/// `.opacity`, so the square can fade smoothly in and out with the animation.
struct PixelCell: View {
    /// Side length of the square, in points.
    var size: CGFloat
    /// The pixel's colour — driven per-action by the caller (white by default).
    var color: Color = .white
    /// How many fill rectangles are stacked in the body. Kept for parity with the
    /// lab's "brightness" knob (opaque fills, so it reads as a denser core).
    var brightness: Int = 1
    /// Corner radius of the square (0 = hard pixel).
    var cornerRadius: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<max(1, brightness), id: \.self) { _ in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }
}

// MARK: - Bloom recipe

/// The recipe for the loader's bloom. Authored as the talk's layered-shadow knobs
/// (`layers`, `baseRadius`, `spread`, `baseOpacity`) so the lab UI and the tuned
/// presets stay meaningful, but now *interpreted* as a two-lobe gaussian field
/// (a tight hot core easing into a wide soft halo) rendered analytically by
/// `PixelBloom.metal`. The same numbers therefore reproduce the known look while
/// dropping the grain and the per-frame blur cost.
///
///     coreRadius  = baseRadius                          // tight, bright centre
///     haloRadius  = baseRadius · spread^(layers - 1)    // wide, faint surround
///     peak        = baseOpacity                         // alpha at a lit centre
struct GlowStyle: Equatable {
    /// Number of conceptual layers. 0 disables the glow entirely.
    var layers: Int = 5
    /// Blur radius of the innermost (tightest, brightest) lobe, in points.
    var baseRadius: CGFloat = 8
    /// Per-layer growth factor: spreads the outer halo out from the core.
    var spread: CGFloat = 1.6
    /// Alpha of the bloom at a fully-lit pixel's centre.
    var baseOpacity: CGFloat = 0.5

    /// Whether the bloom contributes anything at all.
    var isVisible: Bool { layers > 0 && baseRadius > 0 && baseOpacity > 0 }
    /// Point radius of the tight hot core.
    var coreRadius: CGFloat { baseRadius }
    /// Point radius where the diffuse halo has effectively faded out.
    var haloRadius: CGFloat { baseRadius * pow(spread, CGFloat(max(0, layers - 1))) }
    /// Peak alpha at a lit pixel's centre.
    var peak: CGFloat { baseOpacity }

    /// The same recipe with every radius multiplied by `factor`, keeping spread,
    /// opacity and layer count — used to keep the bloom proportional when the grid
    /// renders at a different cell size than the one it was tuned at (the tiny
    /// status pixels in the toolbar/toast vs. the big tuning stage).
    func scaled(by factor: CGFloat) -> GlowStyle {
        GlowStyle(layers: layers,
                  baseRadius: baseRadius * factor,
                  spread: spread,
                  baseOpacity: baseOpacity)
    }
}

// MARK: - Grid proportions

/// The proportions that must stay constant whatever size the grid renders at, so
/// the tiny in-context version is a faithful scale of the tuned stage instead of a
/// separately-guessed geometry. One source of truth shared by `PixelLoaderView`
/// and `PixelStatusIndicator`, derived against the current cell size.
struct PixelGridStyle: Equatable {
    /// Gap between pixels as a fraction of a pixel's side. The tuned look is a
    /// 12 pt gap on a 64 pt cell → 0.1875.
    var gapRatio: CGFloat = 0.1875
    /// Corner radius as a fraction of a pixel's side. 0 = hard square pixels.
    var cornerRatio: CGFloat = 0
}

#Preview("PixelCell") {
    HStack(spacing: 28) {
        PixelCell(size: 72, color: .white, brightness: 2)
        PixelCell(size: 72, color: Color(red: 1, green: 0.23, blue: 0.36), brightness: 2)
        PixelCell(size: 72, color: .white, cornerRadius: 16)
    }
    .padding(60)
    .background(.black)
}
