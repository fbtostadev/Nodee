//
//  GlobalHotKey.swift
//  Nodee
//
//  System-wide hotkey via Carbon's RegisterEventHotKey — works without
//  Accessibility permission and is App Store–safe. The Notch gesture is the
//  primary way to open the panel; this is the reliable, configurable fallback.
//

import AppKit
import Carbon.HIToolbox

/// Not actor-isolated: the Carbon handler is a C callback that hops to main.
nonisolated final class GlobalHotKey {
    /// ⌥⌘ — the modifier mask for the default shortcut.
    static let optionCommand = UInt32(optionKey | cmdKey)
    /// ⌥ alone — modifier for the `⌥\` shortcut.
    static let optionOnly = UInt32(optionKey)
    /// Virtual key code for "N".
    static let keyN = UInt32(kVK_ANSI_N)
    /// Virtual key code for "\" (backslash).
    static let keyBackslash = UInt32(kVK_ANSI_Backslash)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onTrigger: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { hotKey.onTrigger() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F4445), id: 1) // 'NODE'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
