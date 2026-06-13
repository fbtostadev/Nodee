//
//  DotMatrixIndicator.swift
//  Nodee
//
//  A data-driven dot grid for system status feedback. The standard geometry is a
//  radial *iris* (concentric rings of dots, `DotMatrixLayout.standardIris`); a
//  legacy square lattice survives behind `layout: nil`. Behaviour is entirely
//  dictated by injected *intensity* frames (0…1 brightness, one per dot). Swap the
//  frames and the same component becomes a spinner, a checkmark, a falling shred —
//  no view code changes required.
//
//  Why intensity, not boolean on/off:
//    A binary grid can only blink — pixels snap between lit and dark. By giving
//    each pixel a brightness, light can *flow*: a comet carries a decaying tail,
//    a "move" rises with a wake, a "trash" sinks and fades. The per-pixel spring
//    tweens those intensities so a handful of frames reads as continuous motion.
//
//  The vocabulary is a set of "verbs of light", each mapped to an app operation
//  and the semantic accent of DSGNConcept §2:
//    orbit    → loading / scanning           (ice-blue)
//    converge → success / done               (accent, white apex)
//    lift     → move file                    (ice-blue)
//    cascade  → copy / duplicate             (amber, source stays lit)
//    dissolve → trash                        (red, sinks away)
//    breathe  → live / FSEvents sync / wait  (ice-blue, dim, continuous)
//    shudder  → error                        (red, X flares & jitters)
//    bloom    → pin project / created        (ice-blue, centre bursts outward)
//
//  Architecture:
//    DotMatrixState    → high-level intent (loading / move / trash / …)
//    DotMatrixSequence → the intensity frames that realise that intent
//    DotMatrixEngine   → timer-driven playback of a sequence
//    DotMatrixIndicator → the SwiftUI view (grid + breathing glow)
//

import SwiftUI

// MARK: - Semantic palette (DSGNConcept §2)

private enum DotMatrixPalette {
    static let iceBlue = Color(red: 0.55, green: 0.80, blue: 1.00) // #8CCCFF
    static let amber   = Color(red: 1.00, green: 0.78, blue: 0.38) // #FFC761
    static let red     = Color(red: 1.00, green: 0.38, blue: 0.38) // #FF6161
    /// Transient "done" accent — a one-shot recolour that confirms completion
    /// (e.g. a loading indicator that finishes). Not a fifth semantic accent for
    /// resting states; reserved for the completion beat of an animation.
    static let green   = Color(red: 0.45, green: 0.92, blue: 0.56) // #73EB8F
}

// MARK: - DotMatrixLayout (radial / iris geometry — prototype)

/// One dot in a non-grid layout: a normalized position plus the polar metadata
/// (`ring`, `angle`) the verb generators need. Positions live in the unit square
/// with the centre at (0.5, 0.5), so the same layout scales to any `extent`.
struct DotMatrixDot: Equatable {
    let point: CGPoint   // normalized 0…1, centre at (0.5, 0.5)
    let ring: Int        // 0 = centre, growing outward
    let angle: Double    // radians (0 for the centre)
}

/// A radial alternative to the square lattice: concentric rings of dots (an
/// "iris"). The data-driven contract is untouched — a frame is still a `[Double]`
/// of intensities, one per dot, in `dots` order (this order replaces the square's
/// row-major indexing). Verb generators read each dot's `ring`/`angle` instead of
/// `r*n + c`, so the engine and the per-pixel spring never know the shape changed.
///
/// Prototype scope: only the natively-radial verbs (orbit / converge / bloom /
/// breathe) are provided. The linear verbs and `shudder` stay on the square path.
struct DotMatrixLayout: Equatable {
    let dots: [DotMatrixDot]

    /// Outer radius of the iris in normalized units. Kept below 0.5 so dots near
    /// the rim don't clip the footprint; also drives the inter-ring spacing used
    /// to size the dots at render time.
    static let outerRadius: CGFloat = 0.46

    var count: Int { dots.count }
    var maxRing: Int { dots.map(\.ring).max() ?? 0 }

    /// Chebyshev-equivalent ring of a dot (0 = centre) — the radial analogue of
    /// the square `ring(_:_:)`. Drives converge / bloom / breathe.
    func ring(of index: Int) -> Int { dots[index].ring }

    /// Indices of the outermost ring's dots, already in angular order — the radial
    /// analogue of `perimeter(n)`. Drives the orbit comet path.
    var outerRingIndices: [Int] {
        let m = maxRing
        return dots.indices.filter { dots[$0].ring == m }
    }

    /// Normalized centre-to-centre distance between adjacent rings. Used to size a
    /// dot so it fits its ring slot regardless of `extent` (footprint stays fixed).
    var normalizedRingSpacing: CGFloat {
        DotMatrixLayout.outerRadius / CGFloat(max(1, maxRing))
    }

    /// Build an iris from per-ring dot counts (index 0 = centre). Ring radii are
    /// spread evenly to `outerRadius`; each ring starts at the top (−90°) and steps
    /// clockwise. With counts that nest (6 ⊂ 12) the dots align into spokes, which
    /// is what makes bloom / converge read as clean radial fronts.
    private static func iris(ringCounts: [Int]) -> DotMatrixLayout {
        let maxRing = ringCounts.count - 1
        var dots: [DotMatrixDot] = []
        for (ring, count) in ringCounts.enumerated() {
            guard ring > 0 else {
                dots.append(DotMatrixDot(point: CGPoint(x: 0.5, y: 0.5), ring: 0, angle: 0))
                continue
            }
            let radius = outerRadius * CGFloat(ring) / CGFloat(maxRing)
            for k in 0..<count {
                let angle = -Double.pi / 2 + 2 * Double.pi * Double(k) / Double(count)
                let x = 0.5 + radius * CGFloat(cos(angle))
                let y = 0.5 + radius * CGFloat(sin(angle))
                dots.append(DotMatrixDot(point: CGPoint(x: x, y: y), ring: ring, angle: angle))
            }
        }
        return DotMatrixLayout(dots: dots)
    }

    /// The standard iris: centre + 6 + 12 = 19 dots. Density mirror of the square
    /// `standardDimension` (5×5 = 25) at the same fixed footprint.
    static let standardIris = iris(ringCounts: [1, 6, 12])
}

// MARK: - DotMatrixSequence

/// A filmstrip of intensity frames that drive the pixel grid. Each frame is an
/// array of 9 floats (3×3, row-major: index 0 = top-left … 8 = bottom-right),
/// each a brightness in `0…1`. `0` = dark, `1` = full accent.
struct DotMatrixSequence: Equatable {
    let frames: [[Double]]
    let interval: TimeInterval
    let loops: Bool
    /// Frame indices that flash to white at their apex (a positive "pop"). The
    /// engine swaps the accent to white on these frames only.
    let flashFrames: Set<Int>
    /// Optional accent override — when nil the indicator uses the state's
    /// semantic accent, falling back to the view's base accent.
    let accentOverride: Color?

    init(frames: [[Double]],
         interval: TimeInterval = Theme.dotMatrixFrameInterval,
         loops: Bool = true,
         flashFrames: Set<Int> = [],
         accentOverride: Color? = nil) {
        self.frames = frames
        self.interval = interval
        self.loops = loops
        self.flashFrames = flashFrames
        self.accentOverride = accentOverride
    }

    /// Convenience for boolean patterns (true → 1.0, false → 0.0). Useful for
    /// hand-built one-off masks; prefer intensity frames for fluid motion.
    init(boolFrames: [[Bool]],
         interval: TimeInterval = Theme.dotMatrixFrameInterval,
         loops: Bool = true,
         flashFrames: Set<Int> = [],
         accentOverride: Color? = nil) {
        self.init(frames: boolFrames.map { $0.map { $0 ? 1.0 : 0.0 } },
                  interval: interval,
                  loops: loops,
                  flashFrames: flashFrames,
                  accentOverride: accentOverride)
    }

    // MARK: Grid reference (row-major)
    //   0=TL  1=TC  2=TR
    //   3=ML  4=MC  5=MR
    //   6=BL  7=BC  8=BR
    //
    // Perimeter order (clockwise): 0→1→2→5→8→7→6→3

    /// Build one comet frame over a `cellCount`-cell grid: head at `path[head]`
    /// at full brightness, trailing cells fading by `decay`. The decaying tail is
    /// what reads as motion blur.
    private static func comet(on path: [Int],
                              cellCount: Int,
                              head: Int,
                              length: Int = 4,
                              decay: Double = Theme.dotMatrixTrailDecay) -> [Double] {
        var f = Array(repeating: 0.0, count: cellCount)
        var level = 1.0
        for i in 0..<length {
            let p = path[((head - i) % path.count + path.count) % path.count]
            f[p] = max(f[p], level)
            level *= decay
        }
        return f
    }

    /// Clockwise perimeter-ring indices of an n×n grid (top L→R, right T→B,
    /// bottom R→L, left B→T). The ring has 4·(n−1) cells.
    private static func perimeter(_ n: Int) -> [Int] {
        guard n >= 2 else { return [0] }
        func idx(_ r: Int, _ c: Int) -> Int { r * n + c }
        var path: [Int] = []
        for c in 0..<n            { path.append(idx(0, c)) }       // top L→R
        for r in 1..<n            { path.append(idx(r, n - 1)) }   // right T→B
        for c in stride(from: n - 2, through: 0, by: -1) { path.append(idx(n - 1, c)) } // bottom R→L
        for r in stride(from: n - 2, through: 1, by: -1) { path.append(idx(r, 0)) }     // left B→T
        return path
    }

    /// Chebyshev ring index of a cell (0 = centre, growing outward) on an n×n grid.
    private static func ring(_ idx: Int, _ n: Int) -> Int {
        let c = Double(n - 1) / 2
        let r = Double(idx / n), col = Double(idx % n)
        return Int(max(abs(r - c), abs(col - c)).rounded())
    }

    /// The single grid-density standard for the whole vocabulary. Every verb
    /// defaults to this; pass another dimension only for a deliberate fallback
    /// (e.g. the coarser 3×3). Keeping one standard avoids cross-density hand-offs,
    /// which reflow the grid and read badly.
    static let standardDimension = 5

    /// Build one frame from a per-cell intensity closure (row, col → 0…1).
    private static func frame(_ n: Int,
                              _ value: (_ row: Int, _ col: Int) -> Double) -> [Double] {
        (0..<n * n).map { value($0 / n, $0 % n) }
    }

    // MARK: Verbs of light
    //
    // Every verb is generated for an n×n grid (default `standardDimension`), so
    // the whole vocabulary shares one density. The motions are built from four
    // primitives — perimeter ring (orbit), concentric rings (converge/bloom/
    // breathe), rows (lift/cascade/dissolve), and the diagonal X (shudder) — each
    // of which scales to any n.

    /// ORBIT — a single comet with a decaying tail circling the perimeter.
    /// Continuous, ice-blue. `cycle` = seconds for one full turn.
    static func orbit(dimension n: Int = standardDimension,
                      cycle: TimeInterval = 0.62) -> DotMatrixSequence {
        let path = perimeter(n)
        let len = max(3, n + 1)
        let frames = (0..<path.count).map {
            comet(on: path, cellCount: n * n, head: $0, length: len, decay: 0.55)
        }
        return DotMatrixSequence(frames: frames,
                                 interval: cycle / Double(path.count),
                                 loops: true)
    }

    /// DUAL ORBIT — two comets 180° apart circling the perimeter. A +half-ring
    /// offset lands on the diametrically opposite cell, so the pair stays
    /// point-symmetric through the centre: a balanced, cyclic loading. Continuous,
    /// ice-blue. `cycle` = seconds for one full turn.
    static func dualOrbit(dimension n: Int = standardDimension,
                          cycle: TimeInterval = 0.45) -> DotMatrixSequence {
        let path = perimeter(n)
        let half = path.count / 2
        let cells = n * n
        let len = max(3, n - 1)            // tail proportional to the grid
        let frames = (0..<path.count).map { i -> [Double] in
            let a = comet(on: path, cellCount: cells, head: i,        length: len, decay: 0.50)
            let b = comet(on: path, cellCount: cells, head: i + half, length: len, decay: 0.50)
            return zip(a, b).map { max($0, $1) }
        }
        return DotMatrixSequence(frames: frames,
                                 interval: cycle / Double(path.count),
                                 loops: true)
    }

    /// CONVERGE — concentric rings collapse from the rim inward to the centre,
    /// then the grid flashes white and settles. One-shot "done".
    static func converge(dimension n: Int = standardDimension) -> DotMatrixSequence {
        let cells = n * n
        let maxR = ring(0, n)
        var frames: [[Double]] = []
        for k in stride(from: maxR, through: 0, by: -1) {
            frames.append((0..<cells).map { idx in
                let rg = ring(idx, n)
                if rg == k     { return 1.0 }
                if rg == k + 1 { return 0.35 }    // wake of the ring just passed
                return 0.0
            })
        }
        frames.append(Array(repeating: 1.0, count: cells))                  // white flash
        frames.append((0..<cells).map { ring($0, n) == 0 ? 0.6 : 0.0 })     // afterglow
        frames.append(Array(repeating: 0.0, count: cells))                  // settle
        return DotMatrixSequence(frames: frames, interval: 0.10, loops: false,
                                 flashFrames: [frames.count - 3])
    }

    /// DUAL ORBIT — completion. Same concentric collapse as `converge`, but
    /// recoloured green to confirm "done". One-shot. Pair with `dualOrbit` at the
    /// *same* density so the loading→done hand-off never crosses dimensions.
    static func dualOrbitDone(dimension n: Int = standardDimension) -> DotMatrixSequence {
        let cells = n * n
        let maxR = ring(0, n)
        var frames: [[Double]] = []
        for k in stride(from: maxR, through: 0, by: -1) {
            frames.append((0..<cells).map { idx in
                let rg = ring(idx, n)
                if rg == k     { return 1.0 }
                if rg == k + 1 { return 0.35 }
                return 0.0
            })
        }
        frames.append(Array(repeating: 1.0, count: cells))                  // green bloom
        frames.append((0..<cells).map { ring($0, n) == 0 ? 0.55 : 0.0 })    // afterglow
        frames.append(Array(repeating: 0.0, count: cells))                  // settle
        return DotMatrixSequence(frames: frames, interval: 0.075, loops: false,
                                 accentOverride: DotMatrixPalette.green)
    }

    /// LIFT — a bright row rises from the bottom to the top with a wake below,
    /// pops on arrival, and fades. Reads as relocation upward → *moving* a file.
    /// One-shot, ice-blue.
    static func lift(dimension n: Int = standardDimension) -> DotMatrixSequence {
        var frames: [[Double]] = []
        for target in stride(from: n - 1, through: 0, by: -1) {
            frames.append(frame(n) { r, _ in
                if r == target     { return 0.95 }
                if r == target + 1 { return 0.4 }    // wake below
                return 0.0
            })
        }
        frames.append(frame(n) { r, _ in r == 0 ? 1.0 : 0.0 })   // pop at top
        frames.append(frame(n) { r, _ in r == 0 ? 0.4 : 0.0 })   // top fades
        frames.append(Array(repeating: 0.0, count: n * n))       // settle
        return DotMatrixSequence(frames: frames, interval: 0.085, loops: false,
                                 flashFrames: [frames.count - 3])
    }

    /// CASCADE — a copy descends row by row while the source row stays lit, ending
    /// with two instances. The persistent source is the *copy* metaphor. One-shot,
    /// amber.
    static func cascade(dimension n: Int = standardDimension) -> DotMatrixSequence {
        var frames: [[Double]] = []
        frames.append(frame(n) { r, _ in r == 0 ? 0.9 : 0.0 })   // source row
        for target in 1..<n {
            frames.append(frame(n) { r, _ in
                if r == 0          { return 0.9 }    // source persists
                if r == target     { return 0.85 }   // descending copy
                if r == target - 1 { return 0.3 }    // wake
                return 0.0
            })
        }
        frames.append(frame(n) { r, _ in (r == 0 || r == n - 1) ? 0.95 : 0.0 })  // flash both
        frames.append(frame(n) { r, _ in (r == 0 || r == n - 1) ? 0.55 : 0.0 })  // two present
        frames.append(Array(repeating: 0.0, count: n * n))                       // clear
        return DotMatrixSequence(frames: frames, interval: 0.10, loops: false,
                                 flashFrames: [frames.count - 3],
                                 accentOverride: DotMatrixPalette.amber)
    }

    /// DISSOLVE — the grid extinguishes from the top down, the dissolving front
    /// leaving a faint trail as the body sinks and fades. Reads as matter falling
    /// away → *trashing*. One-shot, red.
    static func dissolve(dimension n: Int = standardDimension) -> DotMatrixSequence {
        let cells = n * n
        var frames: [[Double]] = []
        frames.append(Array(repeating: 0.7, count: cells))       // all present
        for front in 0..<n {
            frames.append(frame(n) { r, c in
                if r < front  { return 0.0 }
                if r == front { return 0.18 }                    // dissolving front
                let scatter = (c % 2 == 0) ? 0.0 : -0.08         // slight column scatter
                return max(0.0, 0.6 - 0.08 * Double(r - front) + scatter)
            })
        }
        frames.append(Array(repeating: 0.0, count: cells))       // gone
        return DotMatrixSequence(frames: frames, interval: 0.085, loops: false,
                                 accentOverride: DotMatrixPalette.red)
    }

    /// BREATHE — a centre-weighted swell (bright centre, dim rim) that rises and
    /// recedes, calm and low. "This object is alive and waiting." Continuous →
    /// live FSEvents / syncing.
    static func breathe(dimension n: Int = standardDimension) -> DotMatrixSequence {
        let cells = n * n
        let maxR = Double(ring(0, n))
        let phases = [0.35, 0.6, 1.0, 0.6]   // inhale → peak → exhale
        let frames = phases.map { p in
            (0..<cells).map { idx -> Double in
                let falloff = 1.0 - Double(ring(idx, n)) / (maxR + 0.6)
                return max(0.0, p * falloff * 0.9)
            }
        }
        return DotMatrixSequence(frames: frames, interval: 0.42, loops: true)
    }

    /// SHUDDER — the diagonal X flares, the grid flashes red in alarm, the X
    /// jitters and holds, then collapses. One-shot "something went wrong", red.
    static func shudder(dimension n: Int = standardDimension) -> DotMatrixSequence {
        let cells = n * n
        func isX(_ idx: Int) -> Bool {
            let r = idx / n, c = idx % n
            return r == c || r == n - 1 - c
        }
        let x        = (0..<cells).map { isX($0) ? 0.9 : 0.0 }
        let alarm    = Array(repeating: 0.85, count: cells)
        let jitter   = (0..<cells).map { isX($0) ? 0.95 : (ring($0, n) == 1 ? 0.25 : 0.0) }
        let xHot     = (0..<cells).map { isX($0) ? 1.0 : 0.0 }
        let collapse = (0..<cells).map { ring($0, n) == 0 ? 0.6 : 0.0 }
        let off      = Array(repeating: 0.0, count: cells)
        return DotMatrixSequence(frames: [x, alarm, jitter, xHot, collapse, off],
                                 interval: 0.10, loops: false,
                                 accentOverride: DotMatrixPalette.red)
    }

    /// BLOOM — a wavefront bursts from the centre outward to the rim, then flashes
    /// and fades. Reads as something taking hold → *pinned / created*. One-shot.
    static func bloom(dimension n: Int = standardDimension) -> DotMatrixSequence {
        let cells = n * n
        let maxR = ring(0, n)
        var frames: [[Double]] = []
        for k in 0...maxR {
            frames.append((0..<cells).map { idx in
                let rg = ring(idx, n)
                if rg == k     { return 0.9 }
                if rg == k - 1 { return 0.4 }    // trailing glow behind the front
                return 0.0
            })
        }
        frames.append(Array(repeating: 1.0, count: cells))                   // full bloom
        frames.append((0..<cells).map { ring($0, n) == maxR ? 0.35 : 0.0 })  // ring fades
        frames.append(Array(repeating: 0.0, count: cells))                   // settle
        return DotMatrixSequence(frames: frames, interval: 0.095, loops: false,
                                 flashFrames: [frames.count - 3])
    }

    /// Fully dark — the component disappears at rest. Sized to the standard grid
    /// so a resting indicator never reflows when a verb begins.
    static func idle(dimension n: Int = standardDimension) -> DotMatrixSequence {
        DotMatrixSequence(frames: [Array(repeating: 0.0, count: n * n)],
                          interval: 1.0, loops: false)
    }

    // MARK: Radial verbs (iris layout — prototype)
    //
    // The natively-radial half of the vocabulary, re-expressed over a
    // `DotMatrixLayout` instead of an n×n grid. Frames come back in `layout.dots`
    // order (one intensity per dot), so they feed the same engine unchanged. Each
    // reuses the existing motion structure — the orbit comet, the concentric-ring
    // collapse/burst, the centre-weighted swell — swapping `ring(idx,n)`/
    // `perimeter(n)` for the layout's `ring(of:)`/`outerRingIndices`.

    /// ORBIT (radial) — a comet with a decaying tail circling the outer ring.
    /// Continuous, ice-blue. `cycle` = seconds for one full turn.
    static func orbitRadial(layout: DotMatrixLayout = .standardIris,
                            cycle: TimeInterval = 0.7) -> DotMatrixSequence {
        let path = layout.outerRingIndices
        guard !path.isEmpty else { return idle() }
        let len = max(3, path.count / 3)
        let frames = (0..<path.count).map {
            comet(on: path, cellCount: layout.count, head: $0, length: len, decay: 0.55)
        }
        return DotMatrixSequence(frames: frames,
                                 interval: cycle / Double(path.count),
                                 loops: true)
    }

    /// CONVERGE (radial) — rings collapse from the rim inward to the centre, then
    /// the iris flashes white and settles. One-shot "done".
    static func convergeRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let cells = layout.count
        let maxR = layout.maxRing
        var frames: [[Double]] = []
        for k in stride(from: maxR, through: 0, by: -1) {
            frames.append((0..<cells).map { idx in
                let rg = layout.ring(of: idx)
                if rg == k     { return 1.0 }
                if rg == k + 1 { return 0.35 }    // wake of the ring just passed
                return 0.0
            })
        }
        frames.append(Array(repeating: 1.0, count: cells))                       // white flash
        frames.append((0..<cells).map { layout.ring(of: $0) == 0 ? 0.6 : 0.0 })  // afterglow
        frames.append(Array(repeating: 0.0, count: cells))                       // settle
        return DotMatrixSequence(frames: frames, interval: 0.11, loops: false,
                                 flashFrames: [frames.count - 3])
    }

    /// BLOOM (radial) — a wavefront bursts from the centre outward to the rim, then
    /// flashes and fades. Reads as something taking hold. One-shot.
    static func bloomRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let cells = layout.count
        let maxR = layout.maxRing
        var frames: [[Double]] = []
        for k in 0...maxR {
            frames.append((0..<cells).map { idx in
                let rg = layout.ring(of: idx)
                if rg == k     { return 0.9 }
                if rg == k - 1 { return 0.4 }    // trailing glow behind the front
                return 0.0
            })
        }
        frames.append(Array(repeating: 1.0, count: cells))                          // full bloom
        frames.append((0..<cells).map { layout.ring(of: $0) == maxR ? 0.35 : 0.0 }) // ring fades
        frames.append(Array(repeating: 0.0, count: cells))                          // settle
        return DotMatrixSequence(frames: frames, interval: 0.11, loops: false,
                                 flashFrames: [frames.count - 3])
    }

    /// BREATHE (radial) — a centre-weighted swell that rises and recedes, calm and
    /// low. "This object is alive and waiting." Continuous.
    static func breatheRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let cells = layout.count
        let maxR = Double(layout.maxRing)
        let phases = [0.35, 0.6, 1.0, 0.6]   // inhale → peak → exhale
        let frames = phases.map { p in
            (0..<cells).map { idx -> Double in
                let falloff = 1.0 - Double(layout.ring(of: idx)) / (maxR + 0.6)
                return max(0.0, p * falloff * 0.9)
            }
        }
        return DotMatrixSequence(frames: frames, interval: 0.42, loops: true)
    }

    /// DUAL ORBIT (radial) — two comets 180° apart circling the outer ring, kept
    /// point-symmetric through the centre. Continuous, ice-blue. Used by copy-path.
    static func dualOrbitRadial(layout: DotMatrixLayout = .standardIris,
                                cycle: TimeInterval = 0.5) -> DotMatrixSequence {
        let path = layout.outerRingIndices
        guard !path.isEmpty else { return idleRadial(layout: layout) }
        let half = path.count / 2
        let cells = layout.count
        let len = max(3, path.count / 3)
        let frames = (0..<path.count).map { i -> [Double] in
            let a = comet(on: path, cellCount: cells, head: i,        length: len, decay: 0.50)
            let b = comet(on: path, cellCount: cells, head: i + half, length: len, decay: 0.50)
            return zip(a, b).map { max($0, $1) }
        }
        return DotMatrixSequence(frames: frames,
                                 interval: cycle / Double(path.count),
                                 loops: true)
    }

    /// DUAL ORBIT DONE (radial) — concentric collapse recoloured green to confirm
    /// completion. One-shot. Pair with `dualOrbitRadial`.
    static func dualOrbitDoneRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let cells = layout.count
        let maxR = layout.maxRing
        var frames: [[Double]] = []
        for k in stride(from: maxR, through: 0, by: -1) {
            frames.append((0..<cells).map { idx in
                let rg = layout.ring(of: idx)
                if rg == k     { return 1.0 }
                if rg == k + 1 { return 0.35 }
                return 0.0
            })
        }
        frames.append(Array(repeating: 1.0, count: cells))                       // green bloom
        frames.append((0..<cells).map { layout.ring(of: $0) == 0 ? 0.55 : 0.0 }) // afterglow
        frames.append(Array(repeating: 0.0, count: cells))                       // settle
        return DotMatrixSequence(frames: frames, interval: 0.075, loops: false,
                                 accentOverride: DotMatrixPalette.green)
    }

    // MARK: Linear verbs over a radial layout
    //
    // The cartesian verbs (lift / cascade / dissolve) survive the move to an iris
    // because every dot carries a real `point.y`. "Up" / "down" become a moving
    // brightness *band* over the normalized y of each dot — not a row index — so
    // the relocation/copy/sink metaphors read intact with no grid.

    /// A horizontal brightness band centred at normalized `y == center`, falling
    /// off linearly over `halfWidth`. The primitive the linear verbs sweep.
    private static func band(_ layout: DotMatrixLayout,
                             center: Double, halfWidth: Double, peak: Double = 1.0) -> [Double] {
        layout.dots.map { dot in
            max(0.0, peak * (1.0 - abs(Double(dot.point.y) - center) / halfWidth))
        }
    }

    /// LIFT (radial) — a band rises from the bottom to the top with a wake below,
    /// pops on arrival, and fades. Reads as relocation upward → *move*. One-shot.
    static func liftRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let hw = 0.26, steps = 6
        var frames: [[Double]] = []
        for s in 0..<steps {
            let c = 1.0 - Double(s) / Double(steps - 1)              // bottom → top
            let main = band(layout, center: c,      halfWidth: hw, peak: 0.95)
            let wake = band(layout, center: c + hw, halfWidth: hw, peak: 0.4)  // below
            frames.append(zip(main, wake).map(Swift.max))
        }
        frames.append(band(layout, center: 0.0, halfWidth: hw, peak: 1.0))     // pop at top
        frames.append(band(layout, center: 0.0, halfWidth: hw, peak: 0.4))     // fade
        frames.append(Array(repeating: 0.0, count: layout.count))              // settle
        return DotMatrixSequence(frames: frames, interval: 0.085, loops: false,
                                 flashFrames: [frames.count - 3])
    }

    /// CASCADE (radial) — a copy descends from the top while the source band stays
    /// lit, ending with two instances. The persistent source is the copy metaphor.
    /// One-shot, amber.
    static func cascadeRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let hw = 0.26, steps = 6
        let source = band(layout, center: 0.0, halfWidth: hw, peak: 0.9)        // top source
        var frames: [[Double]] = [source]
        for s in 1..<steps {
            let c = Double(s) / Double(steps - 1)                   // top → bottom
            let copyBand = band(layout, center: c,      halfWidth: hw, peak: 0.85)
            let wake     = band(layout, center: c - hw, halfWidth: hw, peak: 0.3)
            frames.append(zip(zip(source, copyBand).map(Swift.max), wake).map(Swift.max))
        }
        let bottom = band(layout, center: 1.0, halfWidth: hw, peak: 0.95)
        frames.append(zip(source, bottom).map(Swift.max))                       // flash both
        frames.append(zip(band(layout, center: 0.0, halfWidth: hw, peak: 0.55),
                          band(layout, center: 1.0, halfWidth: hw, peak: 0.55)).map(Swift.max))
        frames.append(Array(repeating: 0.0, count: layout.count))              // clear
        return DotMatrixSequence(frames: frames, interval: 0.10, loops: false,
                                 flashFrames: [frames.count - 3],
                                 accentOverride: DotMatrixPalette.amber)
    }

    /// DISSOLVE (radial) — a front sweeps top→bottom; dots above it are gone, the
    /// body below sinks and fades. Reads as matter falling away → *trash*. One-shot,
    /// red.
    static func dissolveRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let cells = layout.count
        var frames: [[Double]] = [Array(repeating: 0.7, count: cells)]          // all present
        let steps = 6
        for s in 0..<steps {
            let front = Double(s) / Double(steps - 1)               // 0 → 1, sweeping down
            frames.append(layout.dots.map { dot in
                let y = Double(dot.point.y)
                if y < front - 0.12 { return 0.0 }                  // already gone
                if y < front + 0.06 { return 0.18 }                 // dissolving front
                return max(0.0, 0.6 - 0.4 * (y - front))            // body sinking
            })
        }
        frames.append(Array(repeating: 0.0, count: cells))                      // gone
        return DotMatrixSequence(frames: frames, interval: 0.085, loops: false,
                                 accentOverride: DotMatrixPalette.red)
    }

    /// SHUDDER → JOLT (radial) — the rings flare outward in alarm, the grid flashes
    /// red, the rim jitters, then everything collapses to the centre. Reads as a
    /// seismic shock → *error*. One-shot, red. (Replaces the square diagonal-X,
    /// which has no analogue on an iris.)
    static func shudderRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        let cells = layout.count
        let maxR = layout.maxRing
        let flareOut = (0..<cells).map { idx -> Double in
            let rg = layout.ring(of: idx)
            return rg == maxR ? 0.95 : (rg == maxR - 1 ? 0.4 : 0.0) // outer rings flare out
        }
        let alarm  = Array(repeating: 0.9, count: cells)                        // full red flash
        let jitter = (0..<cells).map { idx -> Double in
            let rg = layout.ring(of: idx)
            return rg == maxR ? 1.0 : (rg == 0 ? 0.3 : 0.15)        // rim hot, body trembles
        }
        let collapse = (0..<cells).map { layout.ring(of: $0) == 0 ? 0.6 : 0.0 } // sink to centre
        let off      = Array(repeating: 0.0, count: cells)
        return DotMatrixSequence(frames: [flareOut, alarm, jitter, flareOut, collapse, off],
                                 interval: 0.10, loops: false,
                                 accentOverride: DotMatrixPalette.red)
    }

    /// Fully dark, sized to the iris — a resting radial indicator never reflows
    /// when a verb begins.
    static func idleRadial(layout: DotMatrixLayout = .standardIris) -> DotMatrixSequence {
        DotMatrixSequence(frames: [Array(repeating: 0.0, count: layout.count)],
                          interval: 1.0, loops: false)
    }
}

// MARK: - DotMatrixState

/// High-level intent that selects the appropriate sequence and semantic accent.
enum DotMatrixState: Equatable {
    case idle
    case loading           // orbit
    case success           // converge
    case error             // shudder
    case move              // lift
    case copy              // cascade
    case trash             // dissolve
    case syncing           // breathe
    case pinned            // bloom
    case custom(DotMatrixSequence)

    var sequence: DotMatrixSequence {
        switch self {
        case .idle:            return .idleRadial()
        case .loading:         return .orbitRadial()
        case .success:         return .convergeRadial()
        case .error:           return .shudderRadial()
        case .move:            return .liftRadial()
        case .copy:            return .cascadeRadial()
        case .trash:           return .dissolveRadial()
        case .syncing:         return .breatheRadial()
        case .pinned:          return .bloomRadial()
        case .custom(let seq): return seq
        }
    }

    /// Semantic accent for the state, or nil for "neutral" states that should
    /// adopt the view's base accent (ice-blue by default). Overridden by
    /// `sequence.accentOverride` when present.
    var semanticAccent: Color? {
        switch self {
        case .error, .trash: return DotMatrixPalette.red
        case .copy:          return DotMatrixPalette.amber
        default:             return nil   // neutral → base accent
        }
    }
}

// MARK: - DotMatrixEngine

/// Timer-driven playback of a `DotMatrixSequence`. Advances `currentFrame` at the
/// sequence's interval and handles looping / one-shot completion. The view's
/// per-pixel spring tweens the intensity changes into continuous motion.
@MainActor
@Observable
final class DotMatrixEngine {
    private(set) var currentFrame: [Double] = Array(
        repeating: 0.0,
        count: DotMatrixSequence.standardDimension * DotMatrixSequence.standardDimension
    )
    private(set) var resolvedAccent: Color = DotMatrixPalette.iceBlue
    /// True while the current frame is a white-flash apex.
    private(set) var isFlashing: Bool = false

    @ObservationIgnored private var sequence: DotMatrixSequence = .idle()
    @ObservationIgnored private var frameIndex: Int = 0
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    func play(state: DotMatrixState, base: Color) {
        let seq = state.sequence
        // Resolve accent: sequence override > state semantic > view base.
        resolvedAccent = seq.accentOverride ?? state.semanticAccent ?? base

        playbackTask?.cancel()
        sequence = seq
        frameIndex = 0

        guard !seq.frames.isEmpty else { return }
        currentFrame = seq.frames[0]
        isFlashing = seq.flashFrames.contains(0)

        guard seq.frames.count > 1 || seq.loops else { return }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seq.interval))
                guard !Task.isCancelled else { break }

                self.frameIndex += 1

                if self.frameIndex >= seq.frames.count {
                    if seq.loops {
                        self.frameIndex = 0
                    } else {
                        // One-shot complete — hold the last frame.
                        break
                    }
                }

                self.isFlashing = seq.flashFrames.contains(self.frameIndex)
                self.currentFrame = seq.frames[self.frameIndex]
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isFlashing = false
    }

    deinit {
        playbackTask?.cancel()
    }
}

// MARK: - DotMatrixIndicator

/// A data-driven pixel grid for communicating system status. The view is a square
/// lattice of rounded squares whose density is set by the playing sequence (3×3,
/// 5×5, 7×7…). The footprint is fixed by `extent`, so a denser grid just yields
/// smaller pixels — never a bigger component. Which squares are lit, how brightly,
/// and in what colour is entirely determined by the injected `state`.
///
/// Usage:
/// ```swift
/// DotMatrixIndicator(state: .loading)
/// DotMatrixIndicator(state: .move)                       // ice-blue lift
/// DotMatrixIndicator(state: .copy, extent: 18)           // amber cascade, larger
/// DotMatrixIndicator(state: .custom(.dualOrbit(dimension: 5)))  // dense loading
/// ```
struct DotMatrixIndicator: View {
    let state: DotMatrixState
    /// Base accent for neutral states — overridden by state/sequence semantics.
    var accent: Color = DotMatrixPalette.iceBlue
    /// Whether the semantic glow halo renders behind the grid.
    var showGlow: Bool = true
    /// Total side of the component — constant across grid densities.
    var extent: CGFloat = Theme.dotMatrixExtent
    /// Which cell positions (row-major) are visible. `nil` = the whole grid.
    /// Square path only — ignored by the radial layout.
    var gridMask: Set<Int>? = nil
    /// The dot layout. `.standardIris` (default) renders the radial iris — the app
    /// standard. Pass `nil` for the legacy square `LazyVGrid` fallback.
    var layout: DotMatrixLayout? = .standardIris

    @State private var engine = DotMatrixEngine()

    /// Grid dimension derived from the playing frame (√ of the cell count), so the
    /// view auto-adapts to whatever density the sequence carries.
    private var dimension: Int {
        max(1, Int(Double(engine.currentFrame.count).squareRoot().rounded()))
    }

    /// Pixel side and gap derived from `extent` so the footprint stays fixed.
    private var metrics: (cell: CGFloat, gap: CGFloat, corner: CGFloat) {
        let n = CGFloat(dimension)
        let g = Theme.dotMatrixGapRatio
        let cell = extent / (n + g * (n - 1))
        let gap = cell * g
        return (cell, gap, cell * Theme.dotMatrixCornerRatio)
    }

    /// The live accent: flash white on a flash apex, else the engine's resolved
    /// semantic colour.
    private var liveAccent: Color {
        engine.isFlashing ? .white : engine.resolvedAccent
    }

    /// Brightest pixel currently lit — drives the breathing glow.
    private var peakIntensity: Double {
        engine.currentFrame.max() ?? 0
    }

    var body: some View {
        content
            // Semantic glow — halo in the accent colour, breathing with peak intensity.
            .shadow(
                color: showGlow ? liveAccent.opacity(0.28 * peakIntensity) : .clear,
                radius: Theme.dotMatrixGlowRadius
            )
            .animation(Theme.dotMatrixPixelSpring, value: peakIntensity)
            .onChange(of: state) { _, newState in
                engine.play(state: newState, base: accent)
            }
            .onAppear {
                engine.play(state: state, base: accent)
            }
            .onDisappear {
                engine.stop()
            }
    }

    /// The grid itself — radial iris when a `layout` is supplied, else the square
    /// `LazyVGrid`. The shared glow + lifecycle modifiers wrap whichever renders.
    @ViewBuilder
    private var content: some View {
        if let layout {
            radialContent(layout)
        } else {
            squareContent
        }
    }

    private var squareContent: some View {
        let n = dimension
        let m = metrics
        let columns = Array(repeating: GridItem(.fixed(m.cell), spacing: m.gap),
                            count: n)

        return LazyVGrid(columns: columns, spacing: m.gap) {
            ForEach(0..<(n * n), id: \.self) { index in
                if gridMask?.contains(index) ?? true {
                    pixel(intensity: engine.currentFrame[safe: index] ?? 0,
                          cell: m.cell, corner: m.corner)
                } else {
                    Color.clear
                        .frame(width: m.cell, height: m.cell)
                }
            }
        }
        .frame(width: extent, height: extent)
    }

    /// Radial render: each dot is a circle positioned by its normalized point.
    /// Diameter is derived from the inter-ring spacing so the footprint stays fixed
    /// (denser iris → smaller dots), matching the square path's "extent is law".
    private func radialContent(_ layout: DotMatrixLayout) -> some View {
        let diameter = layout.normalizedRingSpacing * extent * 0.8
        return ZStack {
            ForEach(layout.dots.indices, id: \.self) { i in
                let intensity = engine.currentFrame[safe: i] ?? 0
                Circle()
                    .fill(liveAccent.opacity(intensity * Theme.dotMatrixActiveOpacity))
                    .frame(width: diameter, height: diameter)
                    .position(x: layout.dots[i].point.x * extent,
                              y: layout.dots[i].point.y * extent)
                    .animation(Theme.dotMatrixPixelSpring, value: intensity)
                    .animation(Theme.dotMatrixPixelSpring, value: engine.isFlashing)
            }
        }
        .frame(width: extent, height: extent)
    }

    // MARK: Single pixel

    @ViewBuilder
    private func pixel(intensity: Double, cell: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(liveAccent.opacity(intensity * Theme.dotMatrixActiveOpacity))
            .frame(width: cell, height: cell)
            .animation(Theme.dotMatrixPixelSpring, value: intensity)
            .animation(Theme.dotMatrixPixelSpring, value: engine.isFlashing)
    }
}

private extension Array {
    /// Bounds-safe subscript — guards the brief window where the grid dimension
    /// and the playing frame's cell count are mid-transition.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("DotMatrix — Verbs of Light") {
    let states: [(String, DotMatrixState)] = [
        ("idle", .idle), ("loading", .loading), ("success", .success),
        ("error", .error), ("move", .move), ("copy", .copy),
        ("trash", .trash), ("syncing", .syncing), ("pinned", .pinned),
    ]
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                     spacing: 28) {
        ForEach(states, id: \.0) { label, state in
            VStack(spacing: 10) {
                DotMatrixIndicator(state: state, extent: 30)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
    .padding(40)
    .background(.black)
}

/// The app standard (radial iris) beside the legacy square fallback, at the same
/// footprint. The iris is the default everywhere; the square path survives only
/// for `layout: nil` callers.
#Preview("DotMatrix — Iris vs. Square") {
    HStack(spacing: 40) {
        VStack(spacing: 10) {
            DotMatrixIndicator(state: .loading, extent: 30)   // default = iris
            Text("íris · padrão")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        VStack(spacing: 10) {
            DotMatrixIndicator(state: .custom(.orbit()), extent: 30, layout: nil)
            Text("5×5 · fallback")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
    .padding(50)
    .background(.black)
}

#Preview("DotMatrix — Transition") {
    DotMatrixTransitionDemo()
}

/// Demo view that cycles through states to preview transitions.
private struct DotMatrixTransitionDemo: View {
    @State private var currentState: DotMatrixState = .idle

    private let options: [(String, DotMatrixState)] = [
        ("Idle", .idle), ("Loading", .loading), ("Success", .success),
        ("Error", .error), ("Move", .move), ("Copy", .copy),
        ("Trash", .trash), ("Sync", .syncing), ("Pin", .pinned),
    ]

    var body: some View {
        VStack(spacing: 24) {
            DotMatrixIndicator(state: currentState, extent: 44)
                .frame(height: 60)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                      spacing: 8) {
                ForEach(options, id: \.0) { label, state in
                    Button(label) {
                        // Bounce through idle so one-shots replay on re-tap.
                        currentState = .idle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            currentState = state
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
        .frame(width: 280)
        .padding(40)
        .background(.black)
    }
}
