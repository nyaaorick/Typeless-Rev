import Foundation

enum AppPaths {
    static let bundleID = "com.nyaaorick.inputmethod.TypelessRev"

    /// Schemas, dictionaries and prebuilt binaries shipped inside the bundle.
    static var sharedDataDir: URL {
        Bundle.main.sharedSupportURL!.appendingPathComponent("rime")
    }

    /// Files copied into the user data directory on first run.
    static var seedDir: URL {
        Bundle.main.sharedSupportURL!.appendingPathComponent("user-seed")
    }

    /// Rime's user data: custom patches, learned phrases, compiled `build/`.
    /// `TYPELESS_REV_USER_DIR` redirects it, which the self-test and dev runs use.
    static var userDataDir: URL {
        if let override = ProcessInfo.processInfo.environment["TYPELESS_REV_USER_DIR"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typeless-Rev/Rime")
    }

    /// The selected polish model's text-only weights, installed from the menu or by
    /// `scripts/prepare-model.sh`. `TYPELESS_REV_MODEL_DIR` redirects it.
    static var modelDir: URL { modelDir(for: PolishModel.current) }

    static func modelDir(for model: PolishModel) -> URL {
        if let override = ProcessInfo.processInfo.environment["TYPELESS_REV_MODEL_DIR"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typeless-Rev/Models/\(model.folderName)")
    }

    /// The Whisper speech model and its tokenizer, downloaded from the menu.
    /// `TYPELESS_REV_WHISPER_DIR` redirects it.
    static var whisperDir: URL {
        if let override = ProcessInfo.processInfo.environment["TYPELESS_REV_WHISPER_DIR"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typeless-Rev/Models/whisper")
    }

    static var logDir: URL {
        userDataDir.appendingPathComponent("log")
    }
}

extension RimeEngine.Configuration {
    static var app: RimeEngine.Configuration {
        let level = ProcessInfo.processInfo.environment["TYPELESS_REV_LOG_LEVEL"].flatMap { Int32($0) } ?? 1
        return RimeEngine.Configuration(
            sharedDataDir: AppPaths.sharedDataDir,
            seedDir: AppPaths.seedDir,
            userDataDir: AppPaths.userDataDir,
            logDir: AppPaths.logDir,
            minLogLevel: level)
    }
}
