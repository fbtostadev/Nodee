//
//  MenuBarMenu.swift
//  Nodee
//
//  The minimal menu-bar control point required for App Store compliance:
//  open the panel, preferences, quit. No Dock icon.
//

import SwiftUI

struct MenuBarMenu: View {
    let appState: AppState

    var body: some View {
        Button("Abrir Nodee") { appState.openPanel() }

        Divider()

        SettingsLink {
            Text("Preferências…")
        }

        Divider()

        Button("Encerrar Nodee") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
