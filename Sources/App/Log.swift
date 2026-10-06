import os

enum Log {
    static let app = Logger(subsystem: AppPaths.bundleID, category: "app")
    static let ime = Logger(subsystem: AppPaths.bundleID, category: "ime")
    static let rime = Logger(subsystem: AppPaths.bundleID, category: "rime")
    static let polish = Logger(subsystem: AppPaths.bundleID, category: "polish")
    static let whisper = Logger(subsystem: AppPaths.bundleID, category: "whisper")
}
