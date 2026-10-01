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
            self, selector: #selector(stateChanged), name: .softCapsLockChanged, object: nil)
        engine.onStateChange = { [weak self] _ in self?.stateChanged() }
        installer.onChange = { [weak self] in
            self?.stateChanged()
            self?.modelItem?.title = self?.modelTitle() ?? ""
        }
    }

    // MARK: - Icon

    @objc private func stateChanged() {
        refreshIcon()
    }

    private func refreshIcon() {
        let (symbol, tint): (String, NSColor?) =
            switch VoiceStatus.phase {
            case .listening: ("mic.fill", .systemRed)
            case .polishing: ("sparkles", nil)
            case .idle where engine.state == .failed: ("exclamationmark.triangle", nil)
            case .idle: (SoftCapsLock.isOn ? "capslock.fill" : "mic", nil)
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

        menu.addItem(.separator())
        addPermissionItems()

        menu.addItem(.separator())
        let model = NSMenuItem(title: modelTitle(), action: nil, keyEquivalent: "")
        model.submenu = modelSubmenu()
        menu.addItem(model)
        modelItem = model

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

        // Long press of the 中/英 key (Caps Lock) needs it; without it the key only switches language.
        let monitoring = ModeKeyMonitor.permission
        if let action = monitoring.actionTitle {
            let item = add(monitoring.menuTitle("Input Monitoring") + " — " + action, #selector(fixInputMonitoring))
            item.representedObject = monitoring == .notDetermined
        } else {
            add(monitoring.menuTitle("Input Monitoring"), enabled: false)
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
        switch installer.state {
        case .notInstalled: return "Polish Model: Not Installed"
        case .downloading(let fraction): return "Polish Model: Downloading \(Int(fraction * 100))%"
        case .preparing: return "Polish Model: Preparing…"
        case .installed(let bytes): return "Polish Model: Ready (\(Self.size(bytes)))"
        case .failed: return "Polish Model: Download Failed"
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
        switch installer.state {
        case .notInstalled:
            item("Download (3 GB)", #selector(downloadModel))
        case .downloading:
            item("Cancel Download", #selector(cancelModel))
        case .preparing:
            item("Removing the vision encoder…", nil)
        case .installed:
            item("Move to Trash", #selector(removeModel))
        case .failed(let message):
            item(message, nil)
            item("Try Again", #selector(downloadModel))
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

    @objc private func fixInputMonitoring(_ sender: NSMenuItem) {
        if sender.representedObject as? Bool == true {
            ModeKeyMonitor.requestAccess()
        } else {
            ModeKeyMonitor.openSettings()
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

    @objc private func downloadModel() { installer.install() }
    @objc private func cancelModel() { installer.cancel() }
    @objc private func removeModel() { installer.remove() }

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
