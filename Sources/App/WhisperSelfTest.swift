import Foundation
import WhisperKit

/// Headless check of the Whisper engine: installs the model if needed (about 0.65 GB), loads it,
/// and transcribes speech synthesized with `say`, with timings. Also checks that silence yields
/// nothing and that offloading turns Whisper off. Run with `Typeless-Rev --selftest-whisper`.
///
/// `--transcribe-file PATH` instead prints what Whisper makes of a recording (any format
/// AVFoundation reads), for comparing it with Apple's recognizer on real speech.
enum WhisperSelfTest {
    private struct Case {
        let name: String
        let voice: String
        let phrase: String
        let language: String?
        let prompt: String?
        /// Every one of these must appear in the transcript, ignoring case.
        let expected: [String]
    }

    private static let cases = [
        Case(name: "en", voice: "Samantha", phrase: "Let me check the current pipeline before I push the branch.",
            language: nil, prompt: nil, expected: ["current pipeline", "branch"]),
        Case(name: "zh", voice: "Tingting", phrase: "你好，这是一个语音输入的测试。", language: nil, prompt: nil,
            expected: ["语音", "测试"]),
        Case(name: "mixed", voice: "Tingting", phrase: "我今天要去 Costco 买一些 milk，然后回家写代码。",
            language: nil, prompt: nil, expected: ["Costco", "代码"]),
        Case(name: "en with prompt", voice: "Samantha", phrase: "Open the Typeless Rime settings and redeploy.",
            language: "en", prompt: "Typeless, Rime, redeploy.", expected: ["typeless", "rime"]),
    ]

    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failures += 1 }
        }
        func wait<T>(timeout: TimeInterval = 1800, _ work: @escaping () async -> T) -> (T?, TimeInterval) {
            var result: T?
            let started = Date()
            Task { result = await work() }
            while result == nil, Date().timeIntervalSince(started) < timeout {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            return (result, Date().timeIntervalSince(started))
        }
        func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func secs(_ t: TimeInterval) -> String { String(format: "%.1fs", t) }

        // Install.
        if !WhisperEngine.isInstalled {
            print("downloading \(WhisperEngine.variant)…")
            _ = wait { await WhisperEngine.shared.startInstall() }
            var last = -1
            let started = Date()
            while !WhisperEngine.isInstalled, Date().timeIntervalSince(started) < 1800 {
                if case .failed(let message) = WhisperEngine.install { print("install failed: \(message)"); break }
                if case .downloading(let fraction) = WhisperEngine.install, Int(fraction * 10) != last {
                    last = Int(fraction * 10)
                    print("  \(last * 10)%")
                }
                spin(0.5)
            }
            check("model installs", WhisperEngine.isInstalled, secs(Date().timeIntervalSince(started)))
        } else {
            check("model is installed", true, WhisperEngine.modelFolder?.path ?? "")
        }
        guard WhisperEngine.isInstalled else { return 1 }

        // Load (the first ever load compiles the model for this Mac).
        _ = wait { await WhisperEngine.shared.load() }
        let loadStarted = Date()
        while WhisperEngine.residency != .loaded, Date().timeIntervalSince(loadStarted) < 1800 {
            spin(0.2)
            if WhisperEngine.residency == .offloaded, Date().timeIntervalSince(loadStarted) > 2 { break }
        }
        check("model loads", WhisperEngine.residency == .loaded, secs(Date().timeIntervalSince(loadStarted)))
        guard WhisperEngine.residency == .loaded else { return 1 }

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("typeless-whisper-selftest")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        for testCase in cases {
            let audio = scratch.appendingPathComponent("\(testCase.voice)-\(testCase.name).aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", testCase.voice, "-o", audio.path, testCase.phrase]
            try? say.run()
            say.waitUntilExit()
            guard let samples = try? AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path) else {
                check("\(testCase.name): synthesized audio loads", false)
                continue
            }
            let seconds = Double(samples.count) / 16_000
            let (text, time) = wait {
                await WhisperEngine.shared.transcribe(
                    samples, prompt: testCase.prompt, language: testCase.language, timeout: .seconds(30))
            }
            let output = (text ?? nil) ?? ""
            print("      -> \(output)")
            let found = testCase.expected.allSatisfy { output.lowercased().contains($0.lowercased()) }
            check("\(testCase.name): transcribed", found, "\(secs(time)) for \(secs(seconds)) of audio")
        }

        // Silence must not turn into text.
        let silence = [Float](repeating: 0, count: 16_000 * 2)
        let (quiet, _) = wait {
            await WhisperEngine.shared.transcribe(silence, prompt: nil, language: nil, timeout: .seconds(30))
        }
        check("silence gives no text", (quiet ?? nil) == nil, (quiet ?? nil) ?? "")

        // Offloaded, it answers nothing, so the caller keeps Apple's text.
        _ = wait { await WhisperEngine.shared.offload() }
        spin(0.3)
        let (off, _) = wait {
            await WhisperEngine.shared.transcribe(silence, prompt: nil, language: nil, timeout: .seconds(5))
        }
        check("offloaded, Whisper steps aside", (off ?? nil) == nil && !WhisperEngine.isAvailable)
        VoiceSettings.setWhisperOffloaded(false)

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }

    /// `--transcribe-file PATH`: Whisper's text for a recording, with the time it took.
    static func transcribeFile(_ path: String, language: String?) -> Int32 {
        guard WhisperEngine.isInstalled else {
            print("the Whisper model is not installed (run --selftest-whisper or use the menu)")
            return 1
        }
        guard let samples = try? AudioProcessor.loadAudioAsFloatArray(fromPath: path) else {
            print("could not read \(path)")
            return 1
        }
        var text: String??
        Task {
            await WhisperEngine.shared.load()
            while await MainActor.run(body: { WhisperEngine.residency }) != .loaded {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let started = Date()
            let result = await WhisperEngine.shared.transcribe(samples, prompt: nil, language: language, timeout: .seconds(120))
            print(String(format: "%.1fs of audio in %.2fs", Double(samples.count) / 16_000, Date().timeIntervalSince(started)))
            text = .some(result)
        }
        while text == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        print((text ?? nil) ?? "(no text)")
        return 0
    }
}
