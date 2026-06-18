//
//  PixelLoader.swift
//  Nodee
//
//  The frame machinery and grid view that drive `PixelCell`s as a loading
//  animation, recreating the talk's approach:
//    • A loader is a list of *frames*; each frame lists the cell numbers lit on
//      that frame (1-based, row-major — top-left = 1 — to match the talk's
//      literals like `[[2],[4],[6],[8]]`).
//    • A high-level `pattern` of keyframes is expanded into played frames by
//      `expand(pattern:)`, the faithful port of the talk's `frames` computed
//      property (single keyframe → draw one cell at a time; all-singles → blink
//      together then clear; otherwise play the keyframes as-is).
//    • `PixelLoaderEngine` ticks through the frames on a timer; the grid view
//      lights each `PixelCell` whose number is in the current frame.
//
//  This is a deliberately separate path from `DotMatrixIndicator`: that one is an
//  intensity-driven iris with a single `.shadow`; this one is the boolean,
//  stacked-shadow "pixel bloom" look from the talk.
//

import SwiftUI

// MARK: - Sequence

/// A loader over an `dimension × dimension` grid. Each frame is the set of 1-based
/// cell numbers lit on that frame.
struct PixelLoaderSequence: Equatable {
    let dimension: Int
    let frames: [[Int]]
    var interval: TimeInterval = 0.12
    var loops: Bool = true
}

extension PixelLoaderSequence {
    /// Clockwise perimeter cell numbers (1-based) of an n×n grid:
    /// top L→R, right T→B, bottom R→L, left B→T.
    static func perimeter(_ n: Int) -> [Int] {
        guard n >= 2 else { return [1] }
        func num(_ r: Int, _ c: Int) -> Int { r * n + c + 1 }
        var path: [Int] = []
        for c in 0..<n { path.append(num(0, c)) }                                 // top L→R
        for r in 1..<n { path.append(num(r, n - 1)) }                             // right T→B
        for c in stride(from: n - 2, through: 0, by: -1) { path.append(num(n - 1, c)) } // bottom R→L
        for r in stride(from: n - 2, through: 1, by: -1) { path.append(num(r, 0)) }     // left B→T
        return path
    }

    /// Faithful port of the talk's `frames` computed property: turn a high-level
    /// `pattern` of keyframes into the list of frames actually played.
    ///   • empty pattern            → no frames
    ///   • one keyframe             → light each of its cells one at a time
    ///   • every keyframe a single  → merge all the singles, blink, then clear
    ///   • otherwise                → play the keyframes verbatim
    static func expand(pattern: [[Int]]) -> [[Int]] {
        guard let first = pattern.first else { return [] }
        if pattern.count == 1 { return first.map { [$0] } }
        let allSingles = pattern.allSatisfy { $0.count == 1 }
        if allSingles {
            let merged = pattern.compactMap { $0.first }
            return [merged, []]
        }
        return pattern
    }

    // MARK: Presets

    /// ORBIT — one lit cell travels around the perimeter; the stacked-shadow bloom
    /// reads as a glowing dot sweeping the grid. The default generic loader.
    static func orbit(dimension n: Int = 3, interval: TimeInterval = 0.10) -> PixelLoaderSequence {
        PixelLoaderSequence(dimension: n,
                            frames: expand(pattern: [perimeter(n)]),
                            interval: interval, loops: true)
    }

    /// SNAKE — the perimeter fills one cell at a time into a full ring, then clears
    /// and repeats. A drawing-style sweep.
    static func snake(dimension n: Int = 3, interval: TimeInterval = 0.09) -> PixelLoaderSequence {
        let path = perimeter(n)
        var frames: [[Int]] = (1...path.count).map { Array(path.prefix($0)) }
        frames.append([])                                                         // clear before looping
        return PixelLoaderSequence(dimension: n, frames: frames, interval: interval, loops: true)
    }

    /// CROSS — the four edge midpoints blink on together, then off. Straight from
    /// the talk's `[[2],[4],[6],[8]]` (the all-singles → merge-then-clear path).
    static func cross(interval: TimeInterval = 0.4) -> PixelLoaderSequence {
        PixelLoaderSequence(dimension: 3,
                            frames: expand(pattern: [[2], [4], [6], [8]]),
                            interval: interval, loops: true)
    }

    /// L-DRAW — cells 1,2,3,4,6 light one at a time. From the talk's `[[1,2,3,4,6]]`.
    static func lDraw(interval: TimeInterval = 0.18) -> PixelLoaderSequence {
        PixelLoaderSequence(dimension: 3,
                            frames: expand(pattern: [[1, 2, 3, 4, 6]]),
                            interval: interval, loops: true)
    }
}

// MARK: - Engine

/// Timer-driven playback of a `PixelLoaderSequence`. Advances `litCells` at the
/// sequence's interval, looping or holding the final frame for one-shots. Mirrors
/// `DotMatrixEngine`'s Task-based playback.
@MainActor
@Observable
final class PixelLoaderEngine {
    private(set) var litCells: Set<Int> = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sequence: PixelLoaderSequence?
    @ObservationIgnored private var frameIndex = 0

    func play(_ sequence: PixelLoaderSequence) {
        task?.cancel()
        self.sequence = sequence
        frameIndex = 0
        guard !sequence.frames.isEmpty else { litCells = []; return }

        litCells = Set(sequence.frames[0])
        guard sequence.frames.count > 1 || sequence.loops else { return }
        startTicking()
    }

    /// Freeze on the current frame, leaving `litCells` lit so the loader holds
    /// its pose. `resume()` picks up from the same frame.
    func pause() {
        task?.cancel()
        task = nil
    }

    /// Continue ticking from the frame `pause()` froze on. No-op if already
    /// running or if the sequence is a single, non-looping frame.
    func resume() {
        guard task == nil, let sequence, !sequence.frames.isEmpty,
              sequence.frames.count > 1 || sequence.loops else { return }
        startTicking()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Advances `frameIndex`/`litCells` on a timer until cancelled, resuming from
    /// wherever `frameIndex` currently points.
    private func startTicking() {
        guard let sequence else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(sequence.interval))
                guard !Task.isCancelled else { break }

                var i = self.frameIndex + 1
                if i >= sequence.frames.count {
                    if sequence.loops { i = 0 } else { break }   // hold the last frame
                }
                self.frameIndex = i
                self.litCells = Set(sequence.frames[i])
            }
        }
    }

    deinit { task?.cancel() }
}

// MARK: - Grid view

/// Renders a `PixelLoaderSequence` as a square grid and plays it. Two stacked
/// layers, both fed by the same lit set:
///   • the **bloom** — one analytic Metal pass (`PixelBloom.metal`) over the whole
///     grid, accumulated in float and dithered once, so it stays smooth on black
///     and costs one draw instead of a stack of per-cell blurs; and
///   • the **cores** — the crisp `PixelCell` squares on top, faded by `.opacity`.
/// Geometry comes entirely from `style` + `cellSize`, so the tiny in-context grid
/// is a faithful scale of the tuned stage. The bloom's per-cell intensity is eased
/// over real time by a `TimelineView`, since shader uniforms can't ride SwiftUI's
/// implicit animation; the cores ride a plain `.opacity` animation tuned to match.
struct PixelLoaderView: View {
    let sequence: PixelLoaderSequence
    var color: Color = .white
    var cellSize: CGFloat = 56
    /// Shared grid proportions (gap & corner as fractions of the cell). One source
    /// of truth for both the lab stage and the in-context status pixels.
    var style: PixelGridStyle = .init()
    /// The bloom recipe, already authored in points for this `cellSize` (the caller
    /// scales it when rendering at a different size — see `PixelStatusIndicator`).
    var glow: GlowStyle = .init()
    var brightness: Int = 1
    /// Sub-pixels per side that each *logical* cell is subdivided into. 1 = the
    /// classic one-square-per-cell grid; 6 renders a 3×3 pattern as an 18×18 panel
    /// while the orbit/snake/… choreography still plays on the logical grid.
    var density: Int = 1
    /// Glow each individual sub-pixel (every dot blooms) vs. one bloom per lit
    /// logical cell. Only visible when `density > 1`.
    var glowPerSubPixel: Bool = false
    /// Freeze playback on the current frame while keeping the lit cells glowing.
    var isPaused: Bool = false

    @State private var engine = PixelLoaderEngine()
    @State private var fades: [CellFade] = []

    /// Fade duration for a cell going lit↔dark — shared by the bloom easing and the
    /// cores' `.opacity` animation so they stay in lockstep.
    private let fadeDuration: TimeInterval = 0.18
    /// A `.shadow` radius reads as roughly the gaussian σ of its blur; this maps the
    /// authored lobe radii to σ. Tune here (or via the lab's Base radius) to match.
    private let sigmaPerRadius: CGFloat = 0.6
    /// How many σ of the outer lobe to keep before the bloom layer is cropped.
    private let padScale: CGFloat = 3.0
    /// Fine value-noise amplitude (~±0.8 LSB) to dissolve banding on near-black.
    private let ditherAmp: CGFloat = 1.6 / 255.0

    // MARK: Geometry (single source of truth: style × cellSize)

    private var n: Int { sequence.dimension }
    private var d: Int { max(1, density) }
    private var gap: CGFloat { cellSize * style.gapRatio }
    private var pitch: CGFloat { cellSize + gap }
    private var footprint: CGFloat { CGFloat(n) * cellSize + CGFloat(n - 1) * gap }

    /// Sub-pixel side so the whole thing stays one *uniform* (n·d)×(n·d) lattice at
    /// the same footprint — density is orthogonal to size. For density 1, `subCell`
    /// collapses back to `cellSize` and `subGap` to `gap`.
    private var subCell: CGFloat {
        let total = CGFloat(n * d)
        let r = style.gapRatio
        return footprint / (total + r * (total - 1))
    }
    private var subGap: CGFloat { subCell * style.gapRatio }
    private var subPitch: CGFloat { subCell + subGap }
    private var subCorner: CGFloat { subCell * style.cornerRatio }

    // MARK: Bloom field parameters

    /// Bloom one halo per *sub-pixel* (only when explicitly asked and dense).
    private var perSub: Bool { glowPerSubPixel && d > 1 }
    /// The bloom recipe at the right scale: shrunk to the dot in per-sub-pixel mode.
    private var bloomGlow: GlowStyle {
        perSub ? glow.scaled(by: cellSize > 0 ? subCell / cellSize : 1) : glow
    }
    private var bloomDim: Int { perSub ? n * d : n }
    private var bloomPitch: CGFloat { perSub ? subPitch : pitch }
    private var bloomCellSize: CGFloat { perSub ? subCell : cellSize }
    /// σ of the innermost lobe; the shader grows it by `spread` per layer (matching
    /// the old stacked-shadow recipe), so the same lab knobs reproduce the bloom.
    private var bloomSigma0: CGFloat { bloomGlow.baseRadius * sigmaPerRadius }
    private var bloomOuterSigma: CGFloat {
        bloomSigma0 * pow(bloomGlow.spread, CGFloat(max(0, bloomGlow.layers - 1)))
    }
    /// Halo room kept on every side so the soft tail isn't hard-cropped.
    private var bloomPad: CGFloat { bloomOuterSigma * padScale }
    private var bloomFrame: CGFloat { footprint + 2 * bloomPad }
    /// Centre of cell (0,0) within the (padded) bloom layer.
    private var bloomFirstCentre: CGFloat { bloomPad + bloomCellSize / 2 }

    var body: some View {
        // Read the lit set here, at the top of `body`, so SwiftUI registers a render
        // dependency on it. The cores otherwise read it only inside `ForEach` child
        // closures over a *dynamic* range, which isn't reliably tracked — without
        // this the body never re-evaluated as the engine ticked, so the loader sat
        // frozen on frame 0.
        let lit = engine.litCells
        return ZStack {
            bloomLayer
            coresLayer(lit: lit)
        }
        // Layout size is the grid footprint; the bloom overflows it (uncropped),
        // exactly as the old shadows did, so callers still reserve `footprint`.
        .frame(width: footprint, height: footprint)
        .onAppear {
            resetFades()
            engine.play(sequence)
            updateFades(engine.litCells)
            if isPaused { engine.pause() }
        }
        .onChange(of: sequence) { _, new in
            resetFades()
            engine.play(new)
            updateFades(engine.litCells)
            if isPaused { engine.pause() }
        }
        .onChange(of: isPaused) { _, paused in
            paused ? engine.pause() : engine.resume()
        }
        .onChange(of: lit) { _, new in
            updateFades(new)
        }
        .onDisappear { engine.stop() }
    }

    // MARK: Bloom layer (analytic Metal pass, time-eased)

    @ViewBuilder
    private var bloomLayer: some View {
        if glow.isVisible {
            let frame = bloomFrame
            let centre = CGPoint(x: bloomFirstCentre, y: bloomFirstCentre)
            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: isPaused)) { ctx in
                let intensity = bloomIntensities(at: ctx.date)
                Rectangle()
                    .fill(.white)   // full coverage; the shader synthesises the output
                    .colorEffect(ShaderLibrary.pixelBloom(
                        .float2(centre),
                        .float(Float(bloomPitch)),
                        .float(Float(bloomDim)),
                        .float(Float(bloomSigma0)),
                        .float(Float(bloomGlow.spread)),
                        .float(Float(bloomGlow.layers)),
                        .float(Float(bloomGlow.peak)),
                        .color(color),
                        .float(Float(ditherAmp)),
                        .floatArray(intensity)
                    ))
                    .frame(width: frame, height: frame)
            }
            .frame(width: frame, height: frame)
            .allowsHitTesting(false)
        }
    }

    // MARK: Cores layer (crisp squares, opacity-faded)

    private func coresLayer(lit: Set<Int>) -> some View {
        VStack(spacing: subGap) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: subGap) {
                    ForEach(0..<n, id: \.self) { col in
                        coreCell(on: lit.contains(row * n + col + 1))
                    }
                }
            }
        }
    }

    /// One logical cell as a `density × density` block of crisp sub-pixels, faded
    /// in/out together by `.opacity`. The bloom behind it is drawn separately.
    private func coreCell(on: Bool) -> some View {
        VStack(spacing: subGap) {
            ForEach(0..<d, id: \.self) { _ in
                HStack(spacing: subGap) {
                    ForEach(0..<d, id: \.self) { _ in
                        PixelCell(size: subCell, color: color,
                                  brightness: brightness, cornerRadius: subCorner)
                    }
                }
            }
        }
        .opacity(on ? 1 : 0)
        .animation(.easeOut(duration: fadeDuration), value: on)
    }

    // MARK: Per-cell intensity easing (for the bloom uniforms)

    /// A cell's in-flight fade: interpolate `from → to` over `fadeDuration` from
    /// `start`. Only rewritten when a cell flips lit/dark (≤ a few times a second),
    /// so the per-frame `TimelineView` body only *reads* it — never mutates state.
    private struct CellFade: Equatable {
        var from: Double = 0
        var to: Double = 0
        var start: Date = .distantPast
    }

    private func resetFades() {
        fades = Array(repeating: CellFade(), count: max(0, n * n))
    }

    private func updateFades(_ lit: Set<Int>, at now: Date = .now) {
        guard fades.count == n * n else { resetFades(); return updateFades(lit, at: now) }
        for i in 0..<(n * n) {
            let target: Double = lit.contains(i + 1) ? 1 : 0
            if fades[i].to != target {
                fades[i] = CellFade(from: eased(fades[i], at: now), to: target, start: now)
            }
        }
    }

    private func eased(_ f: CellFade, at now: Date) -> Double {
        let t = now.timeIntervalSince(f.start) / fadeDuration
        if t <= 0 { return f.from }
        if t >= 1 { return f.to }
        let p = 1 - pow(1 - t, 3)                    // easeOut cubic, matches the cores
        return f.from + (f.to - f.from) * p
    }

    /// Per-cell eased intensity for the bloom, expanded to the bloom's grid: one
    /// value per logical cell (per-block mode) or replicated to every sub-pixel
    /// (per-sub-pixel mode).
    private func bloomIntensities(at date: Date) -> [Float] {
        guard fades.count == n * n else { return Array(repeating: 0, count: bloomDim * bloomDim) }
        let logical = (0..<(n * n)).map { eased(fades[$0], at: date) }
        if !perSub { return logical.map(Float.init) }
        let side = n * d
        var out = [Float](repeating: 0, count: side * side)
        for r in 0..<side {
            for c in 0..<side {
                out[r * side + c] = Float(logical[(r / d) * n + (c / d)])
            }
        }
        return out
    }
}

#Preview("PixelLoader — orbit (dense 18×18)") {
    ZStack {
        Color.black
        PixelLoaderView(sequence: .orbit(dimension: 3),
                        color: .white,
                        cellSize: 64,
                        glow: GlowStyle(layers: 5, baseRadius: 24, spread: 1.31, baseOpacity: 0.45),
                        brightness: 2,
                        density: 6)
    }
    .frame(width: 360, height: 360)
}
