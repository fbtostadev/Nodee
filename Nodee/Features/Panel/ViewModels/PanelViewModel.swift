//
//  PanelViewModel.swift
//  Nodee
//
//  Coordinates app-level navigation: opening Locations and Favorites from
//  the sidebar, dropping files into them, granting Home access, and
//  restoring the last session. Also owns the ToastCenter so the browser
//  can queue feedback without reaching into UI layer.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class PanelViewModel {
    private let appState: AppState
    //    let browser: BrowserViewModel
    let toast = ToastCenter()
    
    //    private(set) var selectedFavoriteID: UUID?
    
    init(appState: AppState, browser: BrowserViewModel) {
        self.appState = appState
        //        self.browser = browser
        // Wire the toast immediately so the browser can queue notifications
        // as soon as file operations run, without any view-lifecycle dependency.
        browser.toast = toast
    }
}
