import Carbon
import Foundation

/// Registers the bundle with Text Input Sources and enables its input modes, so a
/// freshly copied build shows up in System Settings > Keyboard > Input Sources.
/// It never selects the source: switching input methods stays the user's call.
enum InputSourceRegistration {
    static func register() -> Int32 {
        let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        guard status == noErr else {
            print("TISRegisterInputSource failed: OSStatus \(status)")
            return 1
        }

        let filter = [kTISPropertyBundleID as String: AppPaths.bundleID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
            !sources.isEmpty
        else {
            print("registered, but no input sources were found for \(AppPaths.bundleID)")
            return 1
        }

        var failed = false
        for source in sources {
            let enableStatus = TISEnableInputSource(source)
            let id = string(source, kTISPropertyInputSourceID) ?? "?"
            let type = string(source, kTISPropertyInputSourceType) ?? "?"
            print("\(enableStatus == noErr ? "enabled" : "FAILED (\(enableStatus))")  \(id)  [\(type)]")
            failed = failed || enableStatus != noErr
        }
        return failed ? 1 : 0
    }

    /// Input source ids this bundle used before. The first release declared itself Chinese
    /// (Simplified) and was enabled under this id.
    static let legacySourceIDs = ["com.nyaaorick.inputmethod.TypelessRev.Hans"]

    /// Disables the enabled sources an older build left behind. A renamed mode leaves a dead
    /// entry in the user's Input Sources, and only the bundle that still declares it can be
    /// asked to turn it off, so `install.sh` runs this before replacing the installed copy.
    static func disableLegacy() -> Int32 {
        let filter = [kTISPropertyBundleID as String: AppPaths.bundleID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        for source in sources {
            guard let id = string(source, kTISPropertyInputSourceID), legacySourceIDs.contains(id) else { continue }
            let status = TISDisableInputSource(source)
            print("\(status == noErr ? "disabled" : "FAILED (\(status))")  \(id)")
            if status != noErr { return 1 }
        }
        return 0
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
