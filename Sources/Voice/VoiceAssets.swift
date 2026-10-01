import Speech

/// Downloads the on-device speech model for a locale. Apple stores it system-wide,
/// so this is a one-time cost per locale.
enum VoiceAssets {
    /// Main thread only.
    private(set) static var isInstalling = false

    /// Installs the models for `locales` (those already installed cost nothing).
    /// `completion` runs on the main thread.
    static func install(locales: [Locale], completion: @escaping (Result<Void, VoiceError>) -> Void) {
        guard !isInstalling else { return }
        isInstalling = true
        Task {
            let result: Result<Void, VoiceError>
            do {
                for locale in locales { try await download(locale: locale) }
                result = .success(())
            } catch let error as VoiceError {
                result = .failure(error)
            } catch {
                result = .failure(.engine(error.localizedDescription))
            }
            await MainActor.run {
                isInstalling = false
                completion(result)
            }
        }
    }

    static func install(locale: Locale, completion: @escaping (Result<Void, VoiceError>) -> Void) {
        install(locales: [locale], completion: completion)
    }

    /// Whether the on-device models for all of `locales` are already on this Mac.
    static func areInstalled(locales: [Locale]) async -> Bool {
        for locale in locales {
            guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return false }
            let transcriber = VoiceSession.makeTranscriber(locale: resolved)
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else { return false }
        }
        return true
    }

    static func download(locale: Locale) async throws {
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw VoiceError.unsupportedLocale(locale.identifier)
        }
        let transcriber = VoiceSession.makeTranscriber(locale: resolved)
        _ = try await AssetInventory.reserve(locale: resolved)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
