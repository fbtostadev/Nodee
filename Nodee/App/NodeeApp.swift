//
//  NodeeApp.swift
//  Nodee
//
//  Entry point. The app lives in the menu bar (MenuBarExtra) and presents its
//  UI in a Notch-anchored panel managed by the AppDelegate — there is no main
//  window. See CLAUDE.md → "Presença no sistema".
//

import SwiftUI

@main
struct NodeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nodee", systemImage: "square.on.square.dashed") {
            MenuBarMenu(appState: appDelegate.appState)
        }
        // Drop SwiftUI's default Edit ▸ Undo/Redo items. Their ⌘Z / ⌘⇧Z key
        // equivalents target the panel window's undoManager (always non-nil, so
        // the items stay enabled) and would swallow the keystrokes before our
        // browser key monitor — unlike ⌘C/⌘V, whose menu items validate to
        // disabled and fall through. The browser owns undo/redo itself.
        .commands {
            CommandGroup(replacing: .undoRedo) { }
        }

        Settings {
            PreferencesView()
        }
    }
}
