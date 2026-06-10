//
//  ToastCenter.swift
//  Nodee
//
//  Drives the single transient toast shown at the foot of the panel — the
//  confirmation + Undo affordance for out-of-view operations (Trash, move into a
//  pinned project). One toast at a time; a new one replaces the old and resets
//  the auto-dismiss timer.
//

import SwiftUI

// MARK: - ToastContext

/// Optional spatial/directory context shown when the user hovers the toast pill.
struct ToastContext {
    enum Kind { case moved, copied, trashed }

    let kind: Kind
    let fileNames: [String]
    let sourceFolder: String
    let destinationFolder: String?   // nil → Trash
    /// Full URL of the destination folder — drives the "navigate here" tap on the chip.
    let destinationURL: URL?
}

// MARK: - Toast

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?
    var context: ToastContext?
    /// Invoked when the user taps the destination chip in the expanded card.
    var navigationAction: (() -> Void)?
    /// When true, the toast renders with a red accent regardless of context kind.
    var isError: Bool = false
}

// MARK: - ToastCenter

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var remainingDuration: TimeInterval = 0
    @ObservationIgnored private var pauseStart: Date?

    /// Show `message`, optionally with a trailing action button. Auto-dismisses
    /// after `duration`; a fresh call cancels the pending dismissal.
    func show(_ message: String,
              actionLabel: String? = nil,
              duration: TimeInterval = 4,
              isError: Bool = false,
              context: ToastContext? = nil,
              action: (() -> Void)? = nil,
              navigationAction: (() -> Void)? = nil) {
        dismissTask?.cancel()
        pauseStart = nil
        current = Toast(message: message, actionLabel: actionLabel, action: action,
                        context: context, navigationAction: navigationAction, isError: isError)
        scheduleDismiss(after: duration)
    }

    /// Pause the auto-dismiss countdown (call on hover enter).
    func pauseDismiss() {
        guard pauseStart == nil else { return }
        pauseStart = Date()
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Resume the countdown with whatever time was left (call on hover exit).
    func resumeDismiss() {
        guard let start = pauseStart else { return }
        pauseStart = nil
        let elapsed = Date().timeIntervalSince(start)
        let left = max(remainingDuration - elapsed, 0.5)
        scheduleDismiss(after: left)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        pauseStart = nil
        current = nil
    }

    private func scheduleDismiss(after duration: TimeInterval) {
        remainingDuration = duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
