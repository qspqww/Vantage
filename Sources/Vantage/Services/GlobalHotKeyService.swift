import Carbon.HIToolbox
import Foundation
import os.log

private let hotKeyLog = Logger(subsystem: "dev.vantage.preview", category: "hotkeys")

/// Registers system-wide hotkeys via Carbon RegisterEventHotKey.
///
/// Chosen over NSEvent.addGlobalMonitorForEvents / CGEventTap because it needs
/// no Accessibility or Input Monitoring permission, can consume the key event
/// (so a full-screen game never sees it), and is the same mechanism used by
/// classic window switchers.
///
/// Registered combos mirror the in-app menu shortcuts:
///   ⌘1…⌘9          switch to client N
///   ⌘⇧] / ⌘⇧[      next / previous client
@MainActor
final class GlobalHotKeyService {
    enum Action {
        case selectIndex(Int)
        case nextClient
        case previousClient
    }

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actionsByID: [UInt32: Action] = [:]
    private var eventHandler: EventHandlerRef?
    private var selectHandler: ((Action) -> Void)?

    /// Installs the Carbon event handler and registers all combos.
    /// Returns false when any registration failed (logged, non-fatal).
    @discardableResult
    func start(selectHandler: @escaping (Action) -> Void) -> Bool {
        guard eventHandler == nil else { return true }
        self.selectHandler = selectHandler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                return service.handle(event: event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            hotKeyLog.error("InstallEventHandler failed osstatus=\(status, privacy: .public)")
            return false
        }
        eventHandler = handler

        let digitKeyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
        ]
        let cmd = UInt32(cmdKey)
        let cmdShift = cmd | UInt32(shiftKey)

        var allSucceeded = true
        for (index, keyCode) in digitKeyCodes.enumerated() {
            allSucceeded = allSucceeded && register(keyCode: keyCode, modifiers: cmd, action: .selectIndex(index))
        }
        allSucceeded = allSucceeded && register(keyCode: UInt32(kVK_ANSI_RightBracket), modifiers: cmdShift, action: .nextClient)
        allSucceeded = allSucceeded && register(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: cmdShift, action: .previousClient)

        hotKeyLog.info("global hotkeys registered ok=\(allSucceeded, privacy: .public) count=\(self.actionsByID.count, privacy: .public)")
        return allSucceeded
    }

    func stop() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        actionsByID.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        selectHandler = nil
        hotKeyLog.info("global hotkeys unregistered")
    }

    private func register(keyCode: UInt32, modifiers: UInt32, action: Action) -> Bool {
        let id = UInt32(actionsByID.count + 1)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: OSType(0x5661_7468) /* 'Vath' */, id: id),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            hotKeyLog.error("register keyCode=\(keyCode, privacy: .public) failed osstatus=\(status, privacy: .public)")
            return false
        }
        hotKeyRefs.append(hotKeyRef)
        actionsByID[id] = action
        return true
    }

    private nonisolated func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        // Carbon delivers to the main thread (GetApplicationEventTarget), so the
        // MainActor hop is synchronous and safe here.
        MainActor.assumeIsolated {
            guard let action = self.actionsByID[hotKeyID.id] else { return }
            self.selectHandler?(action)
        }
        return noErr
    }
}
