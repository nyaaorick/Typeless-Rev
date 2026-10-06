import Cocoa

/// The menu bar icon: the app's only entry point. It shows what the voice path is doing and
/// holds every setting. The menu is rebuilt each time it opens, so it never shows stale state.
final class StatusMenu: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    private let engine = RimeEngine.shared
    private let installer = ModelInstaller.shared
    /// The polish model entry, kept so download progress updates its subtitle while the menu is open.
    private var modelItem: NSMenuItem?
    /// The same for the Whisper model.
    private var whisperItem: NSMenuItem?
    /// Whether the speech models for the current language setting are on this Mac; nil while checking.
    private var speechDataReady: Bool?
    private var speechDataFailed = false

    func install() {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("Typeless-Rev")
        refreshIcon()

        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged), name: .voicePhaseChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(modelChanged), name: .polishResidencyChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(whisperChanged), name: .whisperChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(modelChanged), name: .memoryTierChanged, object: nil)
        engine.onStateChange = { [weak self] _ in self?.stateChanged() }
        installer.onChange = { [weak self] in
            self?.stateChanged()
            self?.modelChanged()
        }
    }

    // MARK: - Icon

    @objc private func stateChanged() {
        refreshIcon()
    }

    /// Keeps the model entry current while the menu is open (download progress, load finishing).
    @objc private func modelChanged() {
        guard let modelItem else { return }
        modelItem.subtitle = modelStatus()
        modelItem.submenu = modelSubmenu()
    }

    /// Keeps the Whisper entry current while the menu is open.
    @objc private func whisperChanged() {
        guard let whisperItem else { return }
        whisperItem.subtitle = whisperStatus()
        whisperItem.submenu = whisperSubmenu()
    }

    private func refreshIcon() {
        let (symbol, tint): (String, NSColor?) =
            switch VoiceStatus.phase {
            case .listening: ("mic.fill", .systemRed)
            case .polishing: ("sparkles", nil)
            case .idle where engine.state == .failed: ("exclamationmark.triangle", nil)
            case .idle: ("mic", nil)
            }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Typeless-Rev")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = tint
    }

    // MARK: - Menu

    /// Health first (what is happening, what needs attention, first-run setup), then the settings
    /// grouped by what they act on: dictation, the models behind it, and typing.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        refreshSpeechData()

        let (statusTitle, statusSymbol) = statusText()
        add(statusTitle, enabled: false, symbol: statusSymbol)
        if VoiceSettings.polishDisabledByCrash {
            add("Polish was turned off after repeated crashes", enabled: false, symbol: "exclamationmark.triangle")
        }
        if let note = memoryNote() {
            add(note, enabled: false, symbol: "memorychip")
        } else if VoiceSettings.speechEngine == .whisper, let reason = whisperFallbackReason() {
            add("Using Apple Speech: Whisper \(reason)", enabled: false, symbol: "info.circle")
        }

        section("Setup")
        addPermissionItems()

        section("Dictation")
        addChoices(
            "Push-to-Talk Key", symbol: "keyboard", #selector(selectKey(_:)),
            PushToTalkKey.allCases.map { ($0.rawValue, $0.title) }, selected: VoiceSettings.pushToTalkKey.rawValue)
        let languages = [(id: VoiceSettings.autoDetect, name: "Auto-Detect")] + VoiceSettings.localeChoices
        addChoices(
            "Speech Language", symbol: "globe", #selector(selectLanguage(_:)),
            languages.map { ($0.id, $0.name) }, selected: VoiceSettings.localeIdentifier, separatorAfterFirst: true)
        addChoices(
            "Speech Engine", symbol: "waveform", #selector(selectEngine(_:)),
            VoiceSettings.SpeechEngine.allCases.map { ($0.rawValue, $0.title) },
            selected: VoiceSettings.speechEngine.rawValue)
        let polish = add("Polish with Local LLM", #selector(togglePolish), symbol: "sparkles")
        polish.state = VoiceSettings.polishEnabled ? .on : .off

        section("Models")
        let whisper = add("Whisper Model", symbol: "waveform.badge.mic")
        whisper.isEnabled = true
        whisper.submenu = whisperSubmenu()
        whisper.subtitle = whisperStatus()
        whisperItem = whisper
        let model = add("Polish Model", symbol: "cpu")
        model.isEnabled = true
        model.submenu = modelSubmenu()
        model.subtitle = modelStatus()
        modelItem = model
        let downgrade = add("Auto-Downgrade Under Memory Pressure", #selector(toggleAutoDowngrade), symbol: "gauge.with.dots.needle.33percent")
        downgrade.state = VoiceSettings.autoDowngrade ? .on : .off

        // The layout English mode types with; Chinese mode always uses ABC for pinyin.
        section("Typing")
        addChoices(
            "English Keyboard Layout", symbol: "character.cursor.ibeam", #selector(selectLayout(_:)),
            KeyboardLayout.choices.map { ($0.id, $0.name) }, selected: KeyboardLayout.english)
        add("Open Rime Folder", #selector(openRimeFolder), symbol: "folder")
        let redeploy = add("Redeploy Rime", #selector(redeployRime), symbol: "arrow.clockwise")
        redeploy.isEnabled = engine.state == .ready || engine.state == .failed

        menu.addItem(.separator())
        add("About Typeless-Rev", #selector(showAbout), symbol: "info.circle")
        add("Quit Typeless-Rev", #selector(quit), key: "q", symbol: "power")
    }

    @discardableResult
    private func add(
        _ title: String, _ action: Selector? = nil, key: String = "", enabled: Bool = true, symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        // An item with a submenu needs no action to stay enabled.
        item.isEnabled = enabled && action != nil
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    private func section(_ title: String) {
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: title))
    }

    /// A submenu of mutually exclusive choices, with the current one shown under the title.
    private func addChoices(
        _ title: String, symbol: String, _ action: Selector, _ choices: [(id: String, name: String)],
        selected: String, separatorAfterFirst: Bool = false
    ) {
        let parent = add(title, symbol: symbol)
        parent.isEnabled = true
        parent.subtitle = choices.first { $0.id == selected }?.name
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (index, choice) in choices.enumerated() {
            if separatorAfterFirst && index == 1 { submenu.addItem(.separator()) }
            let item = NSMenuItem(title: choice.name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = choice.id
            item.state = choice.id == selected ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
    }

    private func statusText() -> (String, String) {
        switch VoiceStatus.phase {
        case .listening: return ("Listening…", "mic.fill")
        case .polishing: return ("Polishing…", "sparkles")
        case .idle:
            switch engine.state {
            case .deploying: return ("Deploying Rime…", "arrow.triangle.2.circlepath")
            case .failed: return ("Rime failed to start", "exclamationmark.triangle")
            default: return ("Ready", "checkmark.circle")
            }
        }
    }

    // MARK: - Permissions and speech data

    /// First-run setup in one place: the microphone grant and the speech models.
    private func addPermissionItems() {
        let microphone = MicrophonePermission.status
        if let action = microphone.actionTitle {
            let item = add(microphone.menuTitle("Microphone"), #selector(fixMicrophone), symbol: "mic.slash")
            item.subtitle = action
            item.representedObject = microphone == .notDetermined
        } else {
            add(microphone.menuTitle("Microphone"), enabled: false, symbol: "mic")
        }

        let speechData = "arrow.down.circle"
        if VoiceAssets.isInstalling {
            add("Speech Data: Downloading…", enabled: false, symbol: speechData)
        } else if speechDataFailed {
            add("Speech Data: Download Failed", #selector(downloadSpeechData), symbol: "exclamationmark.triangle")
                .subtitle = "Try Again"
        } else {
            switch speechDataReady {
            case .some(true): add("Speech Data: Ready", enabled: false, symbol: "checkmark.circle")
            case .some(false):
                add("Speech Data: Not Installed", #selector(downloadSpeechData), symbol: speechData).subtitle = "Download…"
            case .none: add("Speech Data: Checking…", enabled: false, symbol: speechData)
            }
        }
    }

    private func speechLocales() -> [Locale] {
        VoiceSettings.recognition(hint: nil).locales
    }

    /// Looks up whether the models are installed. The answer shows the next time the menu opens.
    private func refreshSpeechData() {
        let locales = speechLocales()
        Task {
            let ready = await VoiceAssets.areInstalled(locales: locales)
            await MainActor.run { self.speechDataReady = ready }
        }
    }

    // MARK: - Polish model

    /// The selected polish model and where it is, shown under the menu entry.
    private func modelStatus() -> String {
        let name = PolishModel.current == .qwen9b ? "Qwen 9B" : "Qwen 4B"
        let state: String =
            switch installer.state {
            case .notInstalled: "Not Installed"
            case .downloading(let fraction): "Downloading \(Int(fraction * 100))%"
            case .preparing: "Preparing…"
            case .installed(let bytes):
                switch PolishEngine.residency {
                case .loaded: "Loaded · \(Self.size(bytes))"
                case .loading: "Loading…"
                case .offloaded: "Offloaded · \(Self.size(bytes)) on disk"
                }
            case .failed: "Download Failed"
            }
        return "\(name) · \(state)"
    }

    private func modelSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        func item(_ title: String, _ action: Selector?) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = action != nil
            submenu.addItem(entry)
        }
        // Which model: one at a time, so picking the other unloads this one. Not while downloading.
        let busy = installer.isRunning
        for model in PolishModel.allCases {
            let entry = NSMenuItem(title: model.title, action: #selector(selectPolishModel(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = model.rawValue
            entry.state = model == PolishModel.current ? .on : .off
            entry.isEnabled = !busy
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        switch installer.state {
        case .notInstalled:
            item(PolishModel.current.downloadTitle, #selector(downloadModel))
        case .downloading:
            item("Cancel Download", #selector(cancelModel))
        case .preparing:
            item(PolishModel.current.hasVision ? "Removing the vision encoder…" : "Verifying the download…", nil)
        case .installed:
            // Loaded, it can be offloaded; offloaded, it can be loaded again or uninstalled.
            switch PolishEngine.residency {
            case .loaded:
                item("Offload from Memory", #selector(offloadModel))
            case .loading:
                item("Loading into memory…", nil)
                item("Cancel and Offload", #selector(offloadModel))
            case .offloaded:
                item("Load into Memory", #selector(loadModel))
                item("Uninstall (Move to Trash)", #selector(removeModel))
            }
        case .failed(let message):
            item(message, nil)
            item("Try Again", #selector(downloadModel))
        }
        return submenu
    }

    // MARK: - Memory pressure

    /// What memory pressure has switched off right now, or nil when nothing.
    private func memoryNote() -> String? {
        let tier = MemoryGovernor.tier
        guard tier > 0 else { return nil }
        var paused: [String] = []
        if VoiceSettings.speechEngine == .whisper { paused.append("Whisper paused") }
        if tier == 3 || (tier == 2 && PolishEngine.effectiveModel == nil) {
            if VoiceSettings.polishEnabled { paused.append("polish paused") }
        } else if tier == 2, PolishModel.current == .qwen9b {
            paused.append("polishing with 4B")
        }
        return "Memory pressure: " + (paused.isEmpty ? "models stepped down" : paused.joined(separator: ", "))
    }

    @objc private func toggleAutoDowngrade() {
        VoiceSettings.setAutoDowngrade(!VoiceSettings.autoDowngrade)
        MemoryGovernor.shared.settingChanged()
    }

    // MARK: - Whisper model

    /// Why the next utterance will not use Whisper, or nil when it will.
    private func whisperFallbackReason() -> String? {
        switch WhisperEngine.install {
        case .notInstalled: return "is not installed"
        case .downloading: return "is downloading"
        case .failed: return "failed to download"
        case .installed:
            if VoiceSettings.whisperOffloaded { return "is offloaded" }
            switch WhisperEngine.residency {
            case .loaded: return nil
            case .loading: return "is loading"
            case .offloaded: return "loads on the next key press"
            }
        }
    }

    /// Where the Whisper model is, shown under the menu entry.
    private func whisperStatus() -> String {
        switch WhisperEngine.install {
        case .notInstalled: return "Not Installed"
        case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
        case .failed: return "Download Failed"
        case .installed(let bytes):
            switch WhisperEngine.residency {
            case .loaded: return "Loaded · \(Self.size(bytes))"
            case .loading: return "Loading…"
            case .offloaded: return "Offloaded · \(Self.size(bytes)) on disk"
            }
        }
    }

    private func whisperSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        func item(_ title: String, _ action: Selector?) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = action != nil
            submenu.addItem(entry)
        }
        switch WhisperEngine.install {
        case .notInstalled:
            item("Download (632 MB)", #selector(downloadWhisper))
        case .downloading:
            item("Cancel Download", #selector(cancelWhisper))
        case .failed(let message):
            item(message, nil)
            item("Try Again", #selector(downloadWhisper))
        case .installed:
            switch WhisperEngine.residency {
            case .loaded:
                item("Offload from Memory", #selector(offloadWhisper))
            case .loading:
                item("Loading (the first load can take a few minutes)…", nil)
                item("Cancel and Offload", #selector(offloadWhisper))
            case .offloaded:
                item("Load into Memory", #selector(loadWhisper))
            }
            item("Uninstall (Move to Trash)", #selector(removeWhisper))
        }
        return submenu
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Actions

    @objc private func togglePolish() {
        VoiceSettings.setPolishEnabled(!VoiceSettings.polishEnabled)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { VoiceSettings.setLocale(id) }
    }

    @objc private func fixMicrophone(_ sender: NSMenuItem) {
        if sender.representedObject as? Bool == true {
            MicrophonePermission.request { _ in }
        } else {
            MicrophonePermission.openSettings()
        }
    }

    @objc private func downloadSpeechData() {
        speechDataFailed = false
        VoiceAssets.install(locales: speechLocales()) { [weak self] result in
            if case .failure(let error) = result {
                Log.app.error("speech data install failed: \(error.message, privacy: .public)")
                self?.speechDataFailed = true
            }
            self?.speechDataReady = nil
            self?.refreshSpeechData()
        }
    }

    @objc private func selectKey(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let key = PushToTalkKey(rawValue: raw) {
            VoiceSettings.setPushToTalkKey(key)
        }
    }

    /// Applies at the next focus or language switch.
    @objc private func selectLayout(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { KeyboardLayout.setEnglish(id) }
    }

    /// Picking Whisper before it is installed starts the download; until it is loaded, Apple's text is used.
    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let engine = VoiceSettings.SpeechEngine(rawValue: raw)
        else { return }
        VoiceSettings.setSpeechEngine(engine)
        guard engine == .whisper else { return }
        if WhisperEngine.isInstalled { Task { await WhisperEngine.shared.load() } } else { downloadWhisper() }
    }

    @objc private func downloadWhisper() { Task { await WhisperEngine.shared.startInstall() } }
    @objc private func cancelWhisper() { Task { await WhisperEngine.shared.cancelInstall() } }
    @objc private func loadWhisper() { Task { await WhisperEngine.shared.load() } }
    @objc private func offloadWhisper() { Task { await WhisperEngine.shared.offload() } }
    @objc private func removeWhisper() { Task { await WhisperEngine.shared.uninstall() } }

    /// Switches the polish model: the current one leaves memory first; the new one loads at the next
    /// key press, or right away if it was loaded. Not installed, its download is offered.
    @objc private func selectPolishModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let model = PolishModel(rawValue: raw),
            model != PolishModel.current, !installer.isRunning
        else { return }
        let wasLoaded = PolishEngine.residency != .offloaded
        Task {
            await PolishEngine.shared.switchModel(to: model)
            await MainActor.run {
                self.installer.refresh()
                self.modelChanged()
            }
            if wasLoaded { await PolishEngine.shared.warmUp() }
        }
    }

    @objc private func downloadModel() { installer.install() }
    @objc private func cancelModel() { installer.cancel() }
    @objc private func removeModel() { installer.remove() }
    @objc private func loadModel() { Task { await PolishEngine.shared.load() } }
    @objc private func offloadModel() { Task { await PolishEngine.shared.offload() } }

    @objc private func openRimeFolder() {
        NSWorkspace.shared.open(AppPaths.userDataDir)
    }

    @objc private func redeployRime() {
        engine.redeploy()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
