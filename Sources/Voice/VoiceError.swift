import Foundation

enum VoiceError: Error, Equatable {
    case microphoneDenied
    case noInputDevice
    case unsupportedLocale(String)
    /// The on-device speech model for this locale has not been downloaded yet.
    case assetsMissing(String)
    case noAudioFormat
    case engine(String)

    /// A short sentence fit for the status tip.
    var message: String {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off. Enable it in System Settings > Privacy & Security."
        case .noInputDevice:
            return "No microphone found."
        case .unsupportedLocale(let id):
            return "Speech recognition does not support \(id)."
        case .assetsMissing:
            return "Speech data is not installed yet."
        case .noAudioFormat:
            return "Speech recognition has no usable audio format."
        case .engine(let detail):
            return "Speech recognition failed: \(detail)"
        }
    }
}
