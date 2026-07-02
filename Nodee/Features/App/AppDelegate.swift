//
//  AppDelegate.swift
//  Nodee
//
//  Builds the SwiftData container and wires up the Notch panel controller. The
//  app is an agent (LSUIElement): no Dock icon, only the menu-bar control point.
//

import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let appState: AppState
    private var panelController: NotchPanelController?

    override init() {
        let container = AppDelegate.makeContainer()
        self.container = container
        self.appState = AppState(container: container)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchPanelController(appState: appState, container: container)
        appState.attach(controller: controller)
        panelController = controller

        // Show the persistent compact Notch. The canvas stays condensed until
        // the user invokes it via gesture (two-finger swipe down on the Notch),
        // shortcut, or menu — it never launches expanded.
        controller.activate()

        // Resolve any previously granted folder access. On first run there's none,
        // so the Notch shows its access request the first time it's opened — the
        // grant happens right there, as a sheet of the panel (no external window).
        appState.resolveHomeAccess()
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([PinnedProject.self, BrowserState.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
