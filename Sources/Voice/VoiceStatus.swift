import Foundation

enum VoicePhase: Equatable {
    case idle
    case listening
    case polishing
}

extension Notification.Name {
    static let voicePhaseChanged = Notification.Name("TypelessRevVoicePhaseChanged")
}

/// What the voice path is doing right now, for the menu bar icon. Main thread only.
/// Only one text field has focus at a time, so a single shared phase is enough.
enum VoiceStatus {
    static var phase = VoicePhase.idle {
        didSet {
            if phase != oldValue { NotificationCenter.default.post(name: .voicePhaseChanged, object: nil) }
        }
    }
}
