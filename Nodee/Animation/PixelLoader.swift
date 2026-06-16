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

/// Renders a `PixelLoaderSequence` as a square grid of `PixelCell`s and plays it.
/// All the bloom/look knobs are forwarded to each cell so the lab can tune them
/// live. Light fades in/out via a short per-cell animation on the lit set.
struct PixelLoaderView: View {
    let sequence: PixelLoaderSequence
    var color: Color = .white
    var cellSize: CGFloat = 56
    var spacing: CGFloat = 12
    var brightness: Int = 1
    var cornerRadius: CGFloat = 0
    var glow: GlowStyle = .init()
    /// Sub-pixels per side that each *logical* cell is subdivided into. 1 = the
    /// classic one-square-per-cell grid; 6 renders a 3×3 pattern as an 18×18 panel
    /// while the orbit/snake/… choreography still plays on the logical grid.
    var density: Int = 1
    /// Glow each individual sub-pixel (every dot blooms) vs. one bloom per lit
    /// logical block. Only visible when `density > 1`.
    var glowPerSubPixel: Bool = false
    /// Freeze playback on the current frame while keeping the lit cells glowing.
    var isPaused: Bool = false

    @State private var engine = PixelLoaderEngine()

    private struct SubMetrics { let cell: CGFloat; let gap: CGFloat; let corner: CGFloat }

    /// Sub-pixel metrics derived so the whole thing stays a *uniform* N×N lattice
    /// at the same footprint as the density-1 grid — density is orthogonal to size.
    /// The gap ratio is taken from `spacing / cellSize`, so density 1 reproduces the
    /// current cell/spacing exactly.
    private var metrics: SubMetrics {
        let n = CGFloat(sequence.dimension)
        let total = n * CGFloat(max(1, density))                 // physical pixels per side
        let footprint = n * cellSize + (n - 1) * spacing         // unchanged by density
        let r = cellSize > 0 ? spacing / cellSize : 0
        let cell = footprint / (total + r * (total - 1))
        let corner = cellSize > 0 ? min(cell / 2, cornerRadius * cell / cellSize) : 0
        return SubMetrics(cell: cell, gap: cell * r, corner: corner)
    }

    var body: some View {
        let n = sequence.dimension
        let m = metrics
        VStack(spacing: m.gap) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: m.gap) {
                    ForEach(0..<n, id: \.self) { col in
                        block(row: row, col: col, m: m)
                    }
                }
            }
        }
        .onAppear {
            engine.play(sequence)
            if isPaused { engine.pause() }
        }
        .onChange(of: sequence) { _, new in
            engine.play(new)
            if isPaused { engine.pause() }
        }
        .onChange(of: isPaused) { _, paused in
            paused ? engine.pause() : engine.resume()
        }
        .onDisappear { engine.stop() }
    }

    /// One logical cell, drawn as a `density × density` block of fill-only sub-pixels
    /// (same gap as the rest of the matrix, so the lattice reads as one uniform panel)
    /// with the bloom cast **once over the whole cluster** — never per dot.
    ///
    /// Because a `.shadow` is just a (local) blur of the alpha mask, one cluster-wide
    /// `ShadowStack` reproduces both looks by radius alone: the full logical radius
    /// melts the 6×6 dots into a single block halo (per-block mode), while a radius
    /// scaled down to the dot leaves each dot its own halo (per-sub-pixel mode). This
    /// keeps the cost at `layers` blur passes per block instead of `layers` *per dot*,
    /// which is what made per-sub-pixel heavy at high density.
    @ViewBuilder
    private func block(row: Int, col: Int, m: SubMetrics) -> some View {
        let lit = engine.litCells.contains(row * sequence.dimension + col + 1)
        let big = max(1, density)
        let blockGlow = glowPerSubPixel
            ? glow.scaled(by: cellSize > 0 ? m.cell / cellSize : 1)
            : glow
        VStack(spacing: m.gap) {
            ForEach(0..<big, id: \.self) { _ in
                HStack(spacing: m.gap) {
                    ForEach(0..<big, id: \.self) { _ in
                        PixelCell(isOn: lit,
                                  size: m.cell,
                                  color: color,
                                  brightness: brightness,
                                  cornerRadius: m.corner,
                                  glow: GlowStyle(layers: 0))
                    }
                }
            }
        }
        // The bloom stays mounted (driven by the dots' own alpha: a dark block is
        // clear, so its shadow is invisible) — it fades in *and out* with the block
        // instead of popping off the instant the cell goes dark.
        .modifier(ShadowStack(enabled: true, color: color, style: blockGlow))
        .animation(.easeOut(duration: 0.18), value: engine.litCells)
    }
}

#Preview("PixelLoader — orbit (dense 18×18)") {
    ZStack {
        Color.black
        PixelLoaderView(sequence: .orbit(dimension: 3),
                        color: .white,
                        cellSize: 64,
                        brightness: 2,
                        glow: GlowStyle(layers: 5, baseRadius: 24, spread: 1.31, baseOpacity: 0.45),
                        density: 6)
    }
    .frame(width: 360, height: 360)
}
