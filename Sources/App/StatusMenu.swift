import Cocoa

/// The menu bar icon: the app's only entry point. It shows what the voice path is doing and
/// holds every setting. The menu is rebuilt each time it opens, so it never shows stale state.
final class StatusMenu: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    private let engine = RimeEngine.shared
    private let installer = ModelInstaller.shared
    /// The model submenu's title, kept so download progress updates it while the menu is open.
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
        modelItem.title = modelTitle()
        modelItem.submenu = modelSubmenu()
    }

    /// Keeps the Whisper entry current while the menu is open.
    @objc private func whisperChanged() {
        guard let whisperItem else { return }
        whisperItem.title = whisperTitle()
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        refreshSpeechData()

        add(statusText(), enabled: false)
        menu.addItem(.separator())

        let polish = add("Polish with Local LLM", #selector(togglePolish))
        polish.state = VoiceSettings.polishEnabled ? .on : .off
        if VoiceSettings.polishDisabledByCrash {
            add("Polish was turned off after repeated crashes", enabled: false)
        }
        if VoiceSettings.speechEngine == .whisper, let reason = whisperFallbackReason() {
            add("Using Apple Speech: Whisper \(reason)", enabled: false)
        }

        let language = NSMenuItem(title: "Speech Language", action: nil, keyEquivalent: "")
        language.submenu = NSMenu()
        language.submenu?.autoenablesItems = false
        let choices = [(id: VoiceSettings.autoDetect, name: "Auto-Detect")] + VoiceSettings.localeChoices
        for (index, choice) in choices.enumerated() {
            if index == 1 { language.submenu?.addItem(.separator()) }
            let item = NSMenuItem(title: choice.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.id
            item.state = choice.id == VoiceSettings.localeIdentifier ? .on : .off
            item.isEnabled = true
            language.submenu?.addItem(item)
        }
        menu.addItem(language)

        let engineMenu = NSMenuItem(title: "Speech Engine", action: nil, keyEquivalent: "")
        engineMenu.submenu = NSMenu()
        engineMenu.submenu?.autoenablesItems = false
        for engine in VoiceSettings.SpeechEngine.allCases {
            let item = NSMenuItem(title: engine.title, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = engine == VoiceSettings.speechEngine ? .on : .off
            item.isEnabled = true
            engineMenu.submenu?.addItem(item)
        }
        menu.addItem(engineMenu)

        let key = NSMenuItem(title: "Push-to-Talk Key", action: nil, keyEquivalent: "")
        key.submenu = NSMenu()
        key.submenu?.autoenablesItems = false
        for option in PushToTalkKey.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(selectKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == VoiceSettings.pushToTalkKey ? .on : .off
            item.isEnabled = true
            key.submenu?.addItem(item)
        }
        menu.addItem(key)

        // The layout English mode types with; Chinese mode always uses ABC for pinyin.
        let layout = NSMenuItem(title: "English Keyboard Layout", action: nil, keyEquivalent: "")
        layout.submenu = NSMenu()
        layout.submenu?.autoenablesItems = false
        let current = KeyboardLayout.english
        for choice in KeyboardLayout.choices {
            let item = NSMenuItem(title: choice.name, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.id
            item.state = choice.id == current ? .on : .off
            item.isEnabled = true
            layout.submenu?.addItem(item)
        }
        menu.addItem(layout)

        menu.addItem(.separator())
        addPermissionItems()

        menu.addItem(.separator())
        let model = NSMenuItem(title: modelTitle(), action: nil, keyEquivalent: "")
        model.submenu = modelSubmenu()
        menu.addItem(model)
        modelItem = model
        let whisper = NSMenuItem(title: whisperTitle(), action: nil, keyEquivalent: "")
        whisper.submenu = whisperSubmenu()
        menu.addItem(whisper)
        whisperItem = whisper

        menu.addItem(.separator())
        add("Open Rime Folder", #selector(openRimeFolder))
        let redeploy = add("Redeploy Rime", #selector(redeployRime))
        redeploy.isEnabled = engine.state == .ready || engine.state == .failed

        menu.addItem(.separator())
        add("About Typeless-Rev", #selector(showAbout))
        add("Quit Typeless-Rev", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector? = nil, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled && action != nil
        menu.addItem(item)
        return item
    }

    private func statusText() -> String {
        switch VoiceStatus.phase {
        case .listening: return "Listening…"
        case .polishing: return "Polishing…"
        case .idle:
            switch engine.state {
            case .deploying: return "Deploying Rime…"
            case .failed: return "Rime failed to start"
            default: return "Ready"
            }
        }
    }

    // MARK: - Permissions and speech data

    /// First-run setup in one place: the microphone grant and the speech models.
    private func addPermissionItems() {
        let microphone = MicrophonePermission.status
        if let action = microphone.actionTitle {
            let item = add(microphone.menuTitle("Microphone") + " — " + action, #selector(fixMicrophone))
            item.representedObject = microphone == .notDetermined
        } else {
            add(microphone.menuTitle("Microphone"), enabled: false)
        }

        if VoiceAssets.isInstalling {
            add("Speech Data: Downloading…", enabled: false)
        } else if speechDataFailed {
            add("Speech Data: Download Failed — Try Again", #selector(downloadSpeechData))
        } else {
            switch speechDataReady {
            case .some(true): add("Speech Data: Ready", enabled: false)
            case .some(false): add("Speech Data: Not Installed — Download…", #selector(downloadSpeechData))
            case .none: add("Speech Data: Checking…", enabled: false)
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

    private func modelTitle() -> String {
        let name = PolishModel.current == .qwen9b ? "9B" : "4B"
        switch installer.state {
        case .notInstalled: return "Polish Model \(name): Not Installed"
        case .downloading(let fraction): return "Polish Model \(name): Downloading \(Int(fraction * 100))%"
        case .preparing: return "Polish Model \(name): Preparing…"
        case .installed(let bytes):
            switch PolishEngine.residency {
            case .loaded: return "Polish Model \(name): Loaded (\(Self.size(bytes)))"
            case .loading: return "Polish Model \(name): Loading…"
            case .offloaded: return "Polish Model \(name): Offloaded (\(Self.size(bytes)) on disk)"
            }
        case .failed: return "Polish Model \(name): Download Failed"
        }
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

    private func whisperTitle() -> String {
        switch WhisperEngine.install {
        case .notInstalled: return "Whisper Model: Not Installed"
        case .downloading(let fraction): return "Whisper Model: Downloading \(Int(fraction * 100))%"
        case .failed: return "Whisper Model: Download Failed"
        case .installed(let bytes):
            switch WhisperEngine.residency {
            case .loaded: return "Whisper Model: Loaded (\(Self.size(bytes)))"
            case .loading: return "Whisper Model: Loading…"
            case .offloaded: return "Whisper Model: Offloaded (\(Self.size(bytes)) on disk)"
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
