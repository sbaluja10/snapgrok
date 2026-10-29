import Carbon
import Foundation

/// Global Option-Shift-G. Carbon hotkeys are the supported way to listen while another app is frontmost.
final class HotkeyCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var hotKey: EventHotKeyRef?
    private var installed = false

    func setHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x5347_524B), id: 1)
        let modifiers = UInt32(optionKey | shiftKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            NSLog("Snapgrok: RegisterEventHotKey failed with \(status)")
        }
    }

    fileprivate func invoke() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}

private func hotkeyCallback(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        center.invoke()
    }
    return noErr
}
