import Foundation

/// Counts how many runs in a row died while the polish model was loading or generating.
///
/// The input method is its own process, so a crash inside MLX cannot take a host app down, but
/// it does drop the user's typing until macOS relaunches it. A model that crashes the same way on
/// every dictation would do that over and over, so after `limit` dead runs in a row polishing
/// is switched off and the user turns it back on from the menu.
struct CrashCounter: Equatable {
    static let limit = 2

    private(set) var consecutive: Int

    init(consecutive: Int = 0) {
        self.consecutive = max(0, consecutive)
    }

    /// The previous run ended with polishing in progress. Returns true once polishing
    /// should be switched off.
    mutating func previousRunDied() -> Bool {
        consecutive += 1
        return consecutive >= Self.limit
    }

    /// A polish ran to the end without the process dying.
    mutating func runSucceeded() {
        consecutive = 0
    }
}
