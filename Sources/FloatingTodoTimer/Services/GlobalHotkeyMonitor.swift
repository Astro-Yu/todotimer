import Carbon
import Foundation

public final class GlobalHotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onTrigger: () -> Void

    private static weak var activeInstance: GlobalHotkeyMonitor?

    /// Registers a global hotkey (Default: Option + Space) using Carbon `RegisterEventHotKey`.
    public init(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey),
        onTrigger: @escaping () -> Void
    ) {
        self.onTrigger = onTrigger
        Self.activeInstance = self
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        unregister()
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr && hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        GlobalHotkeyMonitor.activeInstance?.onTrigger()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x544F_444F), id: 1) // 'TODO'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
