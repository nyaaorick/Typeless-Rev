import Foundation

/// Headless check of the speech pipeline. Synthesizes a phrase with `say`, streams it
/// through a `VoiceSession` exactly as the microphone would, and checks the transcript.
/// Also runs the auto-detecting path, which listens in English and Mandarin at once.
/// Downloads each locale's speech model on first run. Run with `Typeless-Rev --selftest-speech`.
enum SpeechSelfTest {
    private struct Case {
        let locale: String
        let voice: String
        let phrase: String
        /// Every one of these must appear in the transcript.
        let expected: [String]
        /// What the auto-detecting session must conclude.
        var language: SpeechLanguage { locale.hasPrefix("zh") ? .chinese : .english }
    }

    /// Chinese speech with English words in it; auto-detect must call it Chinese.
    private static let mixed = Case(
        locale: "zh-CN", voice: "Tingting", phrase: "我今天要去 Costco 买一些 milk 和 eggs，然后回家写代码。",
        expected: ["今天", "代码"])

    private static let cases = [
        Case(locale: "en-US", voice: "Samantha", phrase: "Hello world. This is a speech test.",
            expected: ["hello", "speech test"]),
        Case(locale: "zh-CN", voice: "Tingting", phrase: "你好，世界。这是一个语音测试。",
            expected: ["你好", "语音"]),
    ]

    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failures += 1 }
        }
        func spin(timeout: TimeInterval, until done: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !done(), Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            return done()
        }

        for testCase in cases {
            let locale = Locale(identifier: testCase.locale)
            let tag = testCase.locale

            // 1. The on-device model must be installed.
            var installResult: Result<Void, VoiceError>?
            var started = Date()
            VoiceAssets.install(locale: locale) { installResult = $0 }
            _ = spin(timeout: 900) { installResult != nil }
            guard case .success = installResult else {
                check("\(tag): speech data is installed", false, installResult.map { "\($0)" } ?? "timed out")
                continue
            }
            check("\(tag): speech data is installed", true, String(format: "%.1fs", Date().timeIntervalSince(started)))

            // 2. Synthesize speech to a file.
            let audio = FileManager.default.temporaryDirectory
                .appendingPathComponent("typeless-rev-speech-\(UUID().uuidString).aiff")
            defer { try? FileManager.default.removeItem(at: audio) }
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", testCase.voice, "-o", audio.path, testCase.phrase]
            try? say.run()
            say.waitUntilExit()
            let synthesized = say.terminationStatus == 0 && FileManager.default.fileExists(atPath: audio.path)
            check("\(tag): say produced an audio file", synthesized)
            guard synthesized else { continue }

            // 3. Transcribe it through the session. finish() right after start() exercises
            //    the release-before-setup-completes path.
            var finalText: String?
            var failure: VoiceError?
            var partials = 0
            let session = VoiceSession(locale: locale, feed: FileFeed(url: audio))
            session.onText = { _ in partials += 1 }
            session.onFinish = { finalText = $0 }
            session.onFailure = { failure = $0 }
            started = Date()
            session.start()
            session.finish()
            _ = spin(timeout: 90) { finalText != nil || failure != nil }
            let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))
            check("\(tag): session finishes without error", failure == nil && finalText != nil, failure?.message ?? elapsed)
            let lowered = finalText?.lowercased() ?? ""
            check("\(tag): transcript contains the spoken words", testCase.expected.allSatisfy(lowered.contains),
                finalText ?? "none")
            check("\(tag): text updates arrived while transcribing", partials > 0, "\(partials) updates")

            // 4. A cancelled session must stay silent.
            var spoke = false
            let cancelled = VoiceSession(locale: locale, feed: FileFeed(url: audio))
            cancelled.onText = { _ in spoke = true }
            cancelled.onFinish = { _ in spoke = true }
            cancelled.onFailure = { _ in spoke = true }
            cancelled.start()
            cancelled.cancel()
            _ = spin(timeout: 3) { spoke }
            check("\(tag): a cancelled session delivers nothing", !spoke)
        }

        // Auto-detect: both models listen to the same audio. The hint is deliberately wrong, to show
        // that it only breaks ties and cannot override what was said.
        for testCase in cases + [mixed] {
            let audio = FileManager.default.temporaryDirectory
                .appendingPathComponent("typeless-rev-speech-\(UUID().uuidString).aiff")
            defer { try? FileManager.default.removeItem(at: audio) }
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", testCase.voice, "-o", audio.path, testCase.phrase]
            try? say.run()
            say.waitUntilExit()

            let wrongHint: SpeechLanguage = testCase.language == .english ? .chinese : .english
            let name = testCase.phrase == mixed.phrase ? "mixed" : testCase.locale
            var finalText: String?
            var failure: VoiceError?
            let session = VoiceSession(recognition: .auto(hint: wrongHint), feed: FileFeed(url: audio))
            session.onFinish = { finalText = $0 }
            session.onFailure = { failure = $0 }
            let started = Date()
            session.start()
            session.finish()
            _ = spin(timeout: 90) { finalText != nil || failure != nil }
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(started))
            let confidences = session.confidences.map { $0.map { String(format: "%.2f", $0) } ?? "-" }
            check("auto \(name): finishes without error", failure == nil && finalText != nil, failure?.message ?? elapsed)
            check("auto \(name): detects \(testCase.language)", session.detectedLanguage == testCase.language,
                "en \(confidences[0]) / zh \(confidences[1]), \(session.detectedLanguage.map { "\($0)" } ?? "none")")
            let lowered = finalText?.lowercased() ?? ""
            check("auto \(name): transcript contains the spoken words", testCase.expected.allSatisfy(lowered.contains),
                finalText ?? "none")
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }
}
