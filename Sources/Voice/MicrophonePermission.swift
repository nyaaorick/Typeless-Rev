import AVFoundation
import AppKit

/// The microphone grant, which is the only permission voice needs: `SpeechAnalyzer` has no
/// speech-recognition authorization (only the older `SFSpeechRecognizer` does), and push-to-talk
/// uses the input method's own key events, so there is no Accessibility prompt either.
enum MicrophonePermission {
    static var status: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied
        }
    }

    /// Shows macOS's prompt (only the first time). `completion` runs on the main thread.
    static func request(completion: @escaping (PermissionStatus) -> Void) {
        // This app has no windows, so bring it forward or the prompt can open behind others.
        NSApp.activate(ignoringOtherApps: true)
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { completion(status) }
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
