import Foundation

/// `Typeless-Rev --install-model`: the menu's "Download Polish Model" without the menu.
/// Used by `scripts/prepare-model.sh` and for testing the installer headlessly.
enum InstallModelCommand {
    static func run() -> Int32 {
        if PolishEngine.isInstalled {
            print("already installed: \(AppPaths.modelDir.path)")
            return 0
        }
        let installer = ModelInstaller.shared
        var lastPercent = -1
        installer.onChange = {
            switch installer.state {
            case .downloading(let fraction):
                let percent = Int(fraction * 100)
                if percent / 5 != lastPercent / 5 { print("downloading \(percent)%") }
                lastPercent = percent
            case .preparing: print("verifying and removing the vision encoder…")
            default: break
            }
        }
        installer.install()
        while true {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            switch installer.state {
            case .installed(let bytes):
                print(String(format: "installed %.2f GB: %@", Double(bytes) / 1e9, AppPaths.modelDir.path))
                return 0
            case .failed(let message):
                print("error: \(message)")
                return 1
            case .notInstalled where !installer.isRunning:
                print("error: install did not complete")
                return 1
            default: continue
            }
        }
    }
}
