import Foundation

/// How dictated text should read in the app it lands in, told to the polish model in one line.
enum AppStyle: String, Equatable, Sendable {
    case chat, document, code, plain

    private static let chatApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.tencent.xinWeChat", "com.tencent.qq", "com.apple.MobileSMS",
        "ru.keepcoder.Telegram", "com.hnc.Discord", "net.whatsapp.WhatsApp", "com.microsoft.teams2",
    ]
    private static let documentApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.apple.iWork.Pages", "com.microsoft.Word",
        "com.apple.Notes", "com.apple.TextEdit", "notion.id", "md.obsidian",
    ]
    private static let codeApps: Set<String> = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2",
        "dev.warp.Warp-Stable", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.mitchellh.ghostty",
    ]

    static func forApp(_ bundleID: String?) -> AppStyle {
        guard let bundleID else { return .plain }
        if chatApps.contains(bundleID) { return .chat }
        if documentApps.contains(bundleID) { return .document }
        if codeApps.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.") { return .code }
        return .plain
    }

    /// One line for the polish model's instructions, or nil when nothing needs saying.
    var hint: String? {
        switch self {
        case .chat:
            "The text goes into a chat message: keep it casual, and leave off the period at the end of a lone sentence."
        case .document:
            "The text goes into a document or email: write complete sentences with full punctuation."
        case .code:
            "The text goes into a code editor or terminal: keep identifiers, file names, and commands exactly as spoken, in their case."
        case .plain:
            nil
        }
    }
}
