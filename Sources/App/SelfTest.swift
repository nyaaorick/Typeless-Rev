import Carbon
import Foundation

/// Headless end-to-end check of the embedded librime and the key translation:
/// deploys into a throwaway user directory, types pinyin, selects candidates,
/// and checks the Chinese-mode punctuation rules. Run with `Typeless-Rev --selftest`.
enum SelfTest {
    static func run() -> Int32 {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("typeless-rev-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failures += 1 }
        }

        let engine = RimeEngine.shared
        let started = Date()
        var config = RimeEngine.Configuration.app
        config.userDataDir = root.appendingPathComponent("Rime")
        config.logDir = root.appendingPathComponent("log")
        // A first-release install: the old, unedited default.custom.yaml names schemas that are
        // no longer shipped. The seed step must replace it, or Rime would have nothing to load.
        try? fm.createDirectory(at: config.userDataDir, withIntermediateDirectories: true)
        let legacy = config.userDataDir.appendingPathComponent("default.custom.yaml")
        try? SeedPolicy.legacyDefaultCustom.write(to: legacy, atomically: true, encoding: .utf8)
        engine.start(config)
        let deadline = Date().addingTimeInterval(300)
        while engine.state == .deploying, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let deployTime = String(format: "%.1fs", Date().timeIntervalSince(started))
        check("engine deploys and becomes ready", engine.isReady, deployTime)
        guard engine.isReady else { return 1 }

        let migrated = (try? String(contentsOf: legacy, encoding: .utf8)).map(SeedPolicy.isManaged) ?? false
        check("a first-release default.custom.yaml is migrated", migrated)

        let session = engine.createSession()
        check("session is created", session != 0)
        guard session != 0 else { return 1 }

        func type(_ text: String) {
            for character in text {
                guard
                    let key = KeyTranslator.keyDown(
                        keyCode: 0, charactersIgnoringModifiers: String(character), flags: [])
                else { continue }
                _ = engine.process(session, key: key)
            }
        }
        func press(keyCode: UInt16, _ characters: String) -> Bool {
            let key = KeyTranslator.keyDown(keyCode: keyCode, charactersIgnoringModifiers: characters, flags: [])!
            return engine.process(session, key: key)
        }
        /// Types `text`, then commits whatever is left (space), and returns all committed text.
        func typeAndCommit(_ text: String) -> String {
            var committed = ""
            func collect() { if let out = engine.takeCommit(session) { committed += out } }
            for character in text {
                guard
                    let key = KeyTranslator.keyDown(
                        keyCode: 0, charactersIgnoringModifiers: String(character).lowercased(),
                        flags: character.isUppercase ? .shift : [])
                else { continue }
                _ = engine.process(session, key: key)
                collect()
            }
            if engine.composition(session) != nil {
                _ = press(keyCode: 36, "\r")  // Return commits the raw input, not a guess
                collect()
            }
            return committed
        }

        // Typing builds a composition with candidates.
        type("nihao")
        let composition = engine.composition(session)
        check("typing 'nihao' starts a composition", composition != nil, composition?.preedit ?? "none")
        let candidates = composition?.candidates.map(\.text) ?? []
        check("candidates include 你好", candidates.contains("你好"), candidates.prefix(5).joined(separator: " "))
        check("candidates carry labels", composition?.candidates.first?.label == "1", composition?.candidates.first?.label ?? "none")

        // Selecting a candidate commits it (this is the path a mouse click takes).
        if let index = candidates.firstIndex(of: "你好") {
            check("selecting a candidate succeeds", engine.selectCandidateOnCurrentPage(session, index: index))
            check("selection commits 你好", engine.takeCommit(session) == "你好")
            check("composition ends after commit", engine.composition(session) == nil)
        }

        // Space commits the highlighted candidate.
        type("nihao")
        _ = press(keyCode: 49, " ")
        check("space commits the top candidate", engine.takeCommit(session) == "你好")

        // Escape cancels without committing.
        type("ni")
        _ = press(keyCode: 53, "\u{1b}")
        check("escape cancels the composition", engine.composition(session) == nil)
        check("escape commits nothing", engine.takeCommit(session) == nil)

        // Backspace edits the composition.
        type("nii")
        _ = press(keyCode: 51, "\u{7f}")
        check("backspace edits the input", engine.composition(session)?.preedit.contains("ni") == true)
        _ = press(keyCode: 53, "\u{1b}")

        // Return commits the raw input.
        type("ni")
        _ = press(keyCode: 36, "\r")
        let raw = engine.takeCommit(session)
        check("return commits the raw input", raw == "ni", raw ?? "none")

        // Chinese characters with ASCII punctuation. A punctuation key typed while composing
        // commits the highlighted candidate first.
        let punctuation: [(typed: String, expected: String)] = [
            ("nihao,", "你好,"), ("nihao.", "你好."), ("nihao?", "你好?"), ("nihao!", "你好!"),
            ("nihao;", "你好;"), ("nihao:", "你好:"), ("nihao(", "你好("), ("nihao)", "你好)"),
            ("nihao\"", "你好\""), ("nihao-", "你好-"), ("nihao=", "你好="), ("nihao/", "你好/"),
            ("nihao[", "你好["), ("nihao]", "你好]"), ("nihao<", "你好<"), ("nihao>", "你好>"),
        ]
        for (typed, expected) in punctuation {
            let out = typeAndCommit(typed)
            check("typing \(typed) commits \(expected)", out == expected, out)
        }
        check("a lone punctuation key commits its ASCII form", typeAndCommit(",.?!;:()\"'") == ",.?!;:()\"'")
        let fullWidth = Set("，。？！；：（）、“”‘’《》〈〉「」『』【】〔〕—…～·")
        var leaked: [String] = []
        for input in ["nihao", "zhongguo", "ma", "shi", "de", "wo", "women", "xiexie", "a", "ni"] {
            type(input)
            for candidate in engine.composition(session)?.candidates ?? [] {
                // Chinese characters only: no punctuation, symbols, emoji or full-width forms.
                let isHan = candidate.text.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
                if !isHan || candidate.text.contains(where: { fullWidth.contains($0) }) {
                    leaked.append("\(input): \(candidate.text)")
                }
            }
            _ = press(keyCode: 53, "\u{1b}")
        }
        check("candidates are Chinese characters only", leaked.isEmpty, leaked.prefix(5).joined(separator: ", "))
        let words = typeAndCommit("Hello")
        check("a capital letter starts a literal run", words == "Hello", words)

        // Focus loss mid-composition inserts the typed letters, not a converted guess.
        type("nihao")
        let flushed = engine.flushRawInput(session)
        check("focus loss flushes the raw input", flushed == "nihao", flushed ?? "none")
        check("composition is cleared after the flush", engine.composition(session) == nil)
        check("flushing with nothing typed does nothing", engine.flushRawInput(session) == nil)

        // Simplified output: the default schema must convert through OpenCC.
        type("zhongguo")
        let simplified = engine.composition(session)?.candidates.map(\.text) ?? []
        check("default schema outputs simplified characters", simplified.contains("中国"),
            simplified.prefix(5).joined(separator: " "))
        _ = press(keyCode: 53, "\u{1b}")

        // Redeploy recompiles, invalidates old sessions, and typing works again afterwards.
        let redeployStarted = Date()
        engine.redeploy()
        check("redeploy starts a deployment", engine.state == .deploying)
        let redeployDeadline = Date().addingTimeInterval(300)
        while engine.state == .deploying, Date() < redeployDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        check("redeploy finishes and the engine is ready", engine.isReady,
            String(format: "%.1fs", Date().timeIntervalSince(redeployStarted)))
        check("sessions from before the redeploy are stale", !engine.hasSession(session))
        let fresh = engine.createSession()
        for character in "nihao" {
            if let key = KeyTranslator.keyDown(keyCode: 0, charactersIgnoringModifiers: String(character), flags: []) {
                _ = engine.process(fresh, key: key)
            }
        }
        check("typing works after a redeploy",
            engine.composition(fresh)?.candidates.map(\.text).contains("你好") == true)
        engine.destroySession(fresh)

        // Shifted punctuation as AppKit really delivers it under the ABC override: the shift is
        // missing from charactersIgnoringModifiers ("/"), present in characters ("?").
        do {
            let shifted = engine.createSession()
            defer { engine.destroySession(shifted) }
            var committed = ""
            for character in "nihao" {
                if let key = KeyTranslator.keyDown(keyCode: 0, charactersIgnoringModifiers: String(character), flags: []) {
                    _ = engine.process(shifted, key: key)
                }
            }
            for (code, base, typed) in [(UInt16(44), "/", "?"), (41, ";", ":"), (18, "1", "!")] {
                let key = KeyTranslator.keyDown(
                    keyCode: code, characters: typed, charactersIgnoringModifiers: base, flags: .shift)!
                _ = engine.process(shifted, key: key)
                if let out = engine.takeCommit(shifted) { committed += out }
            }
            check("Shift+/ ; 1 after nihao commit 你好?:!", committed == "你好?:!", committed)
        }

        // Voice and pinyin are switched off while secure event input (a password field) is on.
        check("secure input is off to begin with", !SecureInput.isActive)
        EnableSecureEventInput()
        check("secure input is detected", SecureInput.isActive)
        DisableSecureEventInput()
        check("secure input ends when released", !SecureInput.isActive)

        engine.destroySession(session)
        engine.finalize()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }
}
