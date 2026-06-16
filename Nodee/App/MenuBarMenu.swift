//
//  MenuBarMenu.swift
//  Nodee
//
//  The minimal menu-bar control point required for App Store compliance:
//  open the panel, preferences, quit. No Dock icon.
//

import SwiftUI
import AppKit

struct MenuBarMenu: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Abrir Nodee") { appState.openPanel() }

        Divider()

        // Standalone test window for the glowing pixel loader. The app is an
        // agent (LSUIElement), so activate it first to bring the window forward.
        Button("Animation Lab…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: PixelLoaderLab.windowID)
        }

        SettingsLink {
            Text("Preferências…")
        }

        Divider()

        Button("Encerrar Nodee") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
