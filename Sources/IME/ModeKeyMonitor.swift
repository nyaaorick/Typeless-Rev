import AppKit
import IOKit.hid

/// Reads the 中/英 (Caps Lock) key straight from the keyboard, as key down and key up.
///
/// The input method's own key events cannot time a press: macOS reports this key only as Caps
/// Lock changes, and on Apple keyboards the "is it held" state follows the lock rather than the
/// finger, so a tap can look like a three-second hold. The HID value is the finger. It needs the
/// Input Monitoring permission; without it the controller falls back to taps only.
final class ModeKeyMonitor {
    static let shared = ModeKeyMonitor()

    /// Called on the main thread: true when the key goes down, false when it comes up.
    var onKey: ((Bool) -> Void)?
    private(set) var isDown = false
    private var manager: IOHIDManager?

    var isRunning: Bool { manager != nil }

    static var permission: PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .allowed
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }

    /// Starts listening when Input Monitoring is allowed. Cheap to call again once running.
    @discardableResult
    func start() -> Bool {
        if manager != nil { return true }
        guard Self.permission == .allowed else { return false }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager,
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
                as CFDictionary)
        IOHIDManagerSetInputValueMatching(
            manager,
            [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad, kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock]
                as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, _, value in
                guard let context else { return }
                let monitor = Unmanaged<ModeKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.keyChanged(down: IOHIDValueGetIntegerValue(value) != 0)
            }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            Log.ime.error("could not open the keyboard for the 中/英 key")
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.manager = manager
        Log.ime.info("reading the 中/英 key from the keyboard")
        return true
    }

    /// Two keyboards can both report the key; only a real change counts.
    private func keyChanged(down: Bool) {
        guard down != isDown else { return }
        isDown = down
        onKey?(down)
    }

    /// Shows macOS's prompt the first time; afterwards the user has to use System Settings.
    static func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { shared.start() }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
