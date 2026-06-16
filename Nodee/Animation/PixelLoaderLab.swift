//
//  PixelLoaderLab.swift
//  Nodee
//
//  A standalone test window for the glowing pixel loader. Opened from the menu
//  bar (Animation Lab…), it puts the loader on a black stage beside live controls
//  so the bloom, speed, density and per-action colour can be dialled in before the
//  loader is wired into the app. This scene is for experimentation and can be
//  removed once the animation lands in its real home.
//

import SwiftUI

struct PixelLoaderLab: View {
    /// Scene id used by the menu-bar command to open this window.
    static let windowID = "pixel-loader-lab"

    @State private var mode: Mode = .tuning
    @State private var preset: Preset = .orbit
    @State private var dimension = 3
    @State private var colorChoice: ColorChoice = .white
    @State private var brightness = 2
    @State private var density = 6
    @State private var speed = 0.09
    @State private var cellSize = 64.0
    @State private var cornerRadius = 0.0
    @State private var isPaused = false

    // Layered-glow recipe (see `GlowStyle`) — defaults are the notch preset.
    @State private var glowLayers = 5
    @State private var glowBaseRadius = 24.0
    @State private var glowSpread = 1.31
    @State private var glowBaseOpacity = 0.45
    @State private var glowPerSubPixel = false

    // MARK: Options

    /// The bare loader stage (for dialling the bloom) vs. the in-context mock that
    /// drops the loader into a notch toolbar + toasts so it can be judged at the
    /// real, tiny scale alongside the other chrome.
    enum Mode: String, CaseIterable, Identifiable {
        case tuning = "Loader", context = "In context"
        var id: String { rawValue }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case orbit = "Orbit", snake = "Snake", cross = "Cross", lDraw = "L-draw"
        var id: String { rawValue }
        /// Cross and L-draw are fixed 3×3 shapes; orbit and snake scale with the grid.
        var honoursDimension: Bool { self == .orbit || self == .snake }
    }

    /// White by default, plus the semantic accents the loader will eventually use
    /// per-action (delete = red, etc.) so they can be previewed now.
    enum ColorChoice: String, CaseIterable, Identifiable {
        case white = "White", delete = "Delete (red)", info = "Info (blue)"
        case copy = "Copy (amber)", success = "Success (green)"
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .white:   return .white
            case .delete:  return Color(red: 1.00, green: 0.23, blue: 0.36)
            case .info:    return Color(red: 0.55, green: 0.80, blue: 1.00)
            case .copy:    return Color(red: 1.00, green: 0.78, blue: 0.38)
            case .success: return Color(red: 0.45, green: 0.92, blue: 0.56)
            }
        }
    }

    private var sequence: PixelLoaderSequence {
        switch preset {
        case .orbit: return .orbit(dimension: dimension, interval: speed)
        case .snake: return .snake(dimension: dimension, interval: speed)
        case .cross: return .cross(interval: speed)
        case .lDraw: return .lDraw(interval: speed)
        }
    }

    private var glow: GlowStyle {
        GlowStyle(layers: glowLayers,
                  baseRadius: glowBaseRadius,
                  spread: glowSpread,
                  baseOpacity: glowBaseOpacity)
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
                .background(.black)
                stage
            }
            Divider()
            controls
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            Color.black
            switch mode {
            case .tuning:
                PixelLoaderView(sequence: sequence,
                                color: colorChoice.color,
                                cellSize: cellSize,
                                brightness: brightness,
                                cornerRadius: cornerRadius,
                                glow: glow,
                                density: density,
                                glowPerSubPixel: glowPerSubPixel,
                                isPaused: isPaused)
            case .context:
                NotchChromeLab(glow: glow,
                               referenceCellSize: cellSize,
                               brightness: brightness,
                               interval: speed,
                               density: density,
                               glowPerSubPixel: glowPerSubPixel,
                               isPaused: isPaused)
            }
        }
        .frame(minWidth: 380, minHeight: 380)
    }

    private var controls: some View {
        Form {
            Section("Pattern") {
                Picker("Preset", selection: $preset) {
                    ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Grid: \(dimension)×\(dimension)", value: $dimension, in: 3...7)
                    .disabled(!preset.honoursDimension)
                    .opacity(preset.honoursDimension ? 1 : 0.4)
                Stepper("Pixel density: ×\(density)", value: $density, in: 1...8)
                Text("\(dimension)×\(dimension) → \(dimension * density)×\(dimension * density) pixels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Colour") {
                Picker("Colour", selection: $colorChoice) {
                    ForEach(ColorChoice.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Bloom") {
                Stepper("Brightness (fills): \(brightness)", value: $brightness, in: 1...5)
                Stepper("Glow layers: \(glowLayers)", value: $glowLayers, in: 0...8)
                sliderRow("Base radius", $glowBaseRadius, in: 2...24, fraction: 0)
                sliderRow("Spread (×)", $glowSpread, in: 1.1...2.2, fraction: 2)
                sliderRow("Base opacity", $glowBaseOpacity, in: 0.1...1.0, fraction: 2)
                Text(String(format: "outer radius ≈ %.0f pt · %.0f%% α",
                            glowBaseRadius * pow(glowSpread, Double(max(0, glowLayers - 1))),
                            glowBaseOpacity / pow(glowSpread, Double(max(0, glowLayers - 1))) * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Glow por sub-pixel", isOn: $glowPerSubPixel)
                    .disabled(density <= 1)
                    .opacity(density <= 1 ? 0.4 : 1)
            }

            Section("Geometry & speed") {
                LabeledContent("Cell size") {
                    Slider(value: $cellSize, in: 24...120)
                }
                LabeledContent("Corner radius") {
                    Slider(value: $cornerRadius, in: 0...cellSize / 2)
                }
                LabeledContent("Frame interval") {
                    Slider(value: $speed, in: 0.03...0.5)
                }
                Text(String(format: "%.0f ms / frame", speed * 1000))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Pause animation", isOn: $isPaused)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
    }

    /// A slider paired with a numeric field that edits the same value. Typed
    /// input is clamped to `range` so it stays in sync with the slider.
    private func sliderRow(_ title: String,
                           _ value: Binding<Double>,
                           in range: ClosedRange<Double>,
                           fraction: Int) -> some View {
        let clamped = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
        return LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: clamped, in: range)
                TextField("", value: clamped,
                          format: .number.precision(.fractionLength(fraction)))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
            }
        }
    }
}

#Preview {
    PixelLoaderLab()
}
