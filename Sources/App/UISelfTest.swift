import Cocoa

/// Headless check of the menu bar menu and the HUD, in a real (but invisible-to-the-user)
/// NSApplication. Settings are restored afterwards. Run with `Typeless-Rev --selftest-ui`.
enum UISelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failures += 1 }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // The menu edits the user's real preferences; put them back when done.
        let defaults = UserDefaults.standard
        let keys = [
            VoiceSettings.localeKey, VoiceSettings.pushToTalkKeyKey, VoiceSettings.polishEnabledKey,
            VoiceSettings.polishCrashesKey, VoiceSettings.polishDisabledByCrashKey, KeyboardLayout.englishKey,
        ]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { zip(keys, saved).forEach { defaults.set($1, forKey: $0) } }
        defaults.removeObject(forKey: VoiceSettings.polishEnabledKey)
        defaults.removeObject(forKey: VoiceSettings.localeKey)

        // MARK: menu
        let status = StatusMenu()
        status.install()
        check("the status item has an icon", status.statusItem.button?.image != nil)
        status.menuNeedsUpdate(status.menu)
        let titles = status.menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        print("      menu: \(titles.joined(separator: " | "))")
        for expected in ["Ready", "Polish with Local LLM", "Speech Language", "Push-to-Talk Key", "English Keyboard Layout",
            "Auto-Downgrade Under Memory Pressure", "Open Rime Folder", "Redeploy Rime", "About Typeless-Rev",
            "Quit Typeless-Rev"] {
            check("menu has \"\(expected)\"", titles.contains(expected))
        }
        check("menu has a microphone entry", titles.contains { $0.hasPrefix("Microphone:") })
        check("menu has a speech data entry", titles.contains { $0.hasPrefix("Speech Data:") })
        check("menu has a polish model entry", titles.contains { $0.hasPrefix("Polish Model ") })
        check("menu has a Whisper model entry", titles.contains { $0.hasPrefix("Whisper Model:") })
        let engines = status.menu.items.first { $0.title == "Speech Engine" }?.submenu?.items.map(\.title) ?? []
        check("speech engine offers Apple and Whisper", engines == VoiceSettings.SpeechEngine.allCases.map(\.title))
        check("actions are enabled", status.menu.items.filter { $0.action != nil && $0.title != "Redeploy Rime" }
            .allSatisfy(\.isEnabled))
        check("Redeploy is off until Rime is running", status.menu.items.first { $0.title == "Redeploy Rime" }?.isEnabled == false)

        func item(_ title: String) -> NSMenuItem? { status.menu.items.first { $0.title == title } }
        func click(_ item: NSMenuItem?) {
            guard let item, let action = item.action else { return }
            NSApp.sendAction(action, to: item.target, from: item)
        }

        check("polish starts on", item("Polish with Local LLM")?.state == .on)
        click(item("Polish with Local LLM"))
        check("clicking it turns polish off", !VoiceSettings.polishEnabled)
        status.menuNeedsUpdate(status.menu)
        check("the checkmark follows", item("Polish with Local LLM")?.state == .off)

        check("language starts on Auto-Detect", VoiceSettings.localeIdentifier == VoiceSettings.autoDetect)
        check("Auto-Detect is the first language item",
            item("Speech Language")?.submenu?.items.first?.title == "Auto-Detect"
                && item("Speech Language")?.submenu?.items.first?.state == .on)
        click(item("Speech Language")?.submenu?.items.first { $0.title == "English (US)" })
        check("choosing a language saves it", VoiceSettings.localeIdentifier == "en-US")
        status.menuNeedsUpdate(status.menu)
        check("the language checkmark follows",
            item("Speech Language")?.submenu?.items.first { $0.state == .on }?.title == "English (US)")

        click(item("Push-to-Talk Key")?.submenu?.items.first { $0.title == "Right Control" })
        check("choosing a key saves it", VoiceSettings.pushToTalkKey == .rightControl)

        // English types with ABC unless another enabled layout is picked; a stale pick falls back.
        defaults.removeObject(forKey: KeyboardLayout.englishKey)
        check("English defaults to ABC", KeyboardLayout.english == KeyboardLayout.pinyinBase, KeyboardLayout.english)
        if let other = KeyboardLayout.choices.first(where: { $0.id != KeyboardLayout.pinyinBase }) {
            click(item("English Keyboard Layout")?.submenu?.items.first { $0.representedObject as? String == other.id })
            check("choosing a layout saves it", KeyboardLayout.english == other.id, other.id)
        }
        KeyboardLayout.setEnglish("com.example.not-enabled")
        check("a layout that is no longer enabled falls back to ABC", KeyboardLayout.english == KeyboardLayout.pinyinBase)

        // MARK: a run that dies inside the polish model
        let crashGuard = PolishCrashGuard.shared
        defaults.removeObject(forKey: VoiceSettings.polishCrashesKey)
        defaults.removeObject(forKey: VoiceSettings.polishDisabledByCrashKey)
        VoiceSettings.setPolishEnabled(true)
        crashGuard.begin()  // "dies": the marker is left behind and never cleared
        check("one dead run is forgiven", !crashGuard.recoverFromPreviousRun() && VoiceSettings.polishEnabled)
        crashGuard.end()
        crashGuard.begin()
        check("two dead runs in a row turn polish off", crashGuard.recoverFromPreviousRun() && !VoiceSettings.polishEnabled)
        crashGuard.end()
        check("the crash is remembered", VoiceSettings.polishDisabledByCrash)
        status.menuNeedsUpdate(status.menu)
        check("the menu says why polish is off",
            status.menu.items.contains { $0.title == "Polish was turned off after repeated crashes" })
        VoiceSettings.setPolishEnabled(true)
        check("turning it back on clears the note", !VoiceSettings.polishDisabledByCrash)
        crashGuard.begin()
        crashGuard.end(succeeded: true)
        check("a finished polish resets the count", VoiceSettings.polishCrashes == 0)
        check("no stale marker is left", !crashGuard.recoverFromPreviousRun())

        // MARK: icon follows the voice phase
        VoiceStatus.phase = .listening
        check("listening tints the icon red", status.statusItem.button?.contentTintColor == .systemRed)
        status.menuNeedsUpdate(status.menu)
        check("the menu says Listening…", status.menu.items.first?.title == "Listening…")
        VoiceStatus.phase = .idle
        check("idle clears the tint", status.statusItem.button?.contentTintColor == nil)

        // MARK: HUD
        let caret = NSRect(x: 300, y: 400, width: 2, height: 18)
        VoiceHUD.shared.show(.listening, anchor: caret)
        let listening = VoiceHUD.shared.frame
        check("the HUD shows while listening", VoiceHUD.shared.isVisible, "\(Int(listening.width))x\(Int(listening.height))")
        check("the HUD is a compact pill", listening.height == 30 && (80...200).contains(listening.width))
        check("the HUD sits below the caret", listening.maxY <= caret.minY)
        VoiceHUD.shared.setLevel(0.8)
        VoiceHUD.shared.show(.polishing, anchor: caret)
        check("the HUD stays up while polishing", VoiceHUD.shared.isVisible)
        VoiceHUD.shared.hide()
        check("the HUD hides when idle", !VoiceHUD.shared.isVisible)
        VoiceHUD.shared.show(.idle, anchor: caret)
        check("showing the idle phase hides it", !VoiceHUD.shared.isVisible)

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }
}
