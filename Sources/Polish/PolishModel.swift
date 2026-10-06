import Foundation

/// The polish models on offer. One is selected (`VoiceSettings.polishModel`); the installer, the
/// engine and the menu all act on that one, and only it is ever in memory.
enum PolishModel: String, CaseIterable {
    case qwen4b = "4b"
    case qwen9b = "9b"

    static var current: PolishModel { override ?? VoiceSettings.polishModel }

    /// Set by `--polish-model` for one developer run, without touching the saved choice.
    nonisolated(unsafe) static var override: PolishModel?

    var title: String {
        switch self {
        case .qwen4b: "Qwen 4B (2.4 GB)"
        case .qwen9b: "Qwen 9B (5.0 GB)"
        }
    }

    /// The community conversion, pinned so the files never change under us.
    var repo: String {
        switch self {
        case .qwen4b: "CaseD0rsett/Qwen3.8-4B-Distill-Heretic-Abliterated-MLX-4bit"
        case .qwen9b: "keXjos/Qwen3.8-9B-mlx-4Bit"
        }
    }

    var revision: String {
        switch self {
        case .qwen4b: "012db115605dab31b813f8c01a00ea09bf27846f"
        case .qwen9b: "3833d0220ac862d6de38448c0cd414bd2ca29d00"
        }
    }

    /// The small files, each with its SHA-256 where it matters.
    var files: [(name: String, sha256: String?)] {
        let tokenizer: String =
            switch self {
            case .qwen4b: "6f32ce20dc35f57a7f9ad1eac03525bd7d30f9df8cea6507e958279cc3657706"
            case .qwen9b: "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"
            }
        return [
            ("config.json", nil),
            ("generation_config.json", nil),
            ("tokenizer_config.json", nil),
            ("chat_template.jinja", nil),
            ("tokenizer.json", tokenizer),
        ]
    }

    var weights: (name: String, sha256: String) {
        switch self {
        case .qwen4b: ("model.safetensors", "ce5a70fa86c09f709a662c656e5a171bacc2aac2c5e4717d96336ff10cf7c000")
        case .qwen9b: ("model.safetensors", "b2c47ca5681b0e641852e5ca2ea5a5fb87d82d6329de7469d3cd42c3ad03ea15")
        }
    }

    /// Whether the download carries a vision encoder to strip. The 9B upload already has none, so
    /// its weights are used as downloaded, without a second 5 GB copy.
    var hasVision: Bool { self == .qwen4b }

    /// Disk needed while installing: the 4B's download (3.03 GB) and its text-only copy (2.37 GB)
    /// exist side by side for a moment; the 9B's weights (5.04 GB) are moved, not copied.
    var requiredFreeBytes: Int64 {
        switch self {
        case .qwen4b: 6_000_000_000
        case .qwen9b: 6_500_000_000
        }
    }

    var downloadTitle: String {
        switch self {
        case .qwen4b: "Download (3 GB)"
        case .qwen9b: "Download (5 GB)"
        }
    }

    /// How much longer than the 4B it takes to answer.
    var timeoutScale: Double {
        switch self {
        case .qwen4b: 1
        case .qwen9b: 2
        }
    }

    /// Folder name under `Models`. The 4B keeps the folder it always had.
    var folderName: String {
        switch self {
        case .qwen4b: "polish"
        case .qwen9b: "polish-9b"
        }
    }
}
