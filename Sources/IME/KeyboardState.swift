import Carbon
import IOKit
import IOKit.hidsystem

/// The real Caps Lock state. The input method keeps it off: on this keyboard the system reports
/// the key as held while the lock is on, so writing the lock would hide what the finger does.
/// Capitals come from `SoftCapsLock` instead.
enum CapsLock {
    /// Turns the lock off. Returns false when the HID system would not let us.
    @discardableResult
    static func clear() -> Bool { set(false) }

    static var isOn: Bool? {
        withConnection { connect in
            var state = false
            guard IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS else {
                return nil
            }
            return state
        }
    }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        withConnection { connect in
            IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on) == KERN_SUCCESS
        } ?? false
    }

    private static func withConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS
        else { return nil }
        defer { IOServiceClose(connect) }
        return body(connect)
    }
}

extension Notification.Name {
    static let softCapsLockChanged = Notification.Name("TypelessRevSoftCapsLockChanged")
}

/// The input method's own Caps Lock, turned on by a long press of the 中/英 key. While it is on the
/// language is English and the controller types letters in capitals itself. It is shared by every
/// text field, like the real lock, and survives focus changes. Main thread only.
enum SoftCapsLock {
    static var isOn = false {
        didSet {
            if isOn != oldValue { NotificationCenter.default.post(name: .softCapsLockChanged, object: nil) }
        }
    }
}

enum KeyboardLayout {
    /// Rime wants raw US-layout keys, whatever layout the user last typed on.
    static let pinyinBase = "com.apple.keylayout.ABC"

    /// The layout the system would give a plain English keyboard: the user's own (Dvorak,
    /// AZERTY, ...), or ABC when nothing else is set.
    static var userASCIICapable: String {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return pinyinBase }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// macOS turns on secure event input while a password field has focus (and while an app such as
/// Terminal holds "Secure Keyboard Entry"). Nothing here may listen or compose then.
enum SecureInput {
    static var isActive: Bool { IsSecureEventInputEnabled() }
}
