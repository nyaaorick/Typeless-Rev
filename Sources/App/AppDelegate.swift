import Cocoa
import InputMethodKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?
    private let statusMenu = StatusMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
        else {
            Log.app.fault("InputMethodConnectionName is missing from Info.plist")
            NSApp.terminate(nil)
            return
        }
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        // A run that died inside the polish model leaves a marker; two in a row switch polishing off.
        PolishCrashGuard.shared.recoverFromPreviousRun()
        statusMenu.install()
        // Timing the 中/英 key (tap or long press) needs Input Monitoring; ask once, up front.
        if !ModeKeyMonitor.shared.start(), ModeKeyMonitor.permission == .notDetermined {
            ModeKeyMonitor.requestAccess()
        }
        RimeEngine.shared.start(.app)
        Log.app.info("input method server \(connectionName, privacy: .public) is up")
    }

    func applicationWillTerminate(_ notification: Notification) {
        RimeEngine.shared.finalize()
    }
}
