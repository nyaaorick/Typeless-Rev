import Cocoa
import InputMethodKit

/// One instance per client text field. Rime sessions are per controller; the
/// engine and the candidate panel are shared.
@objc(TypelessInputController)
final class TypelessInputController: IMKInputController {
    private static let notFound = NSRange(location: NSNotFound, length: NSNotFound)

    private let engine = RimeEngine.shared
    private var session: UInt = 0
    private var hasMarkedText = false
    /// English is a pass-through: Rime sees no key until the user switches to Chinese.
    private var mode = InputMode.english
    /// Tells a tap of the 中/英 key from a long press; `longPressTimer` fires while the key is down.
    private var modeKey = ModeKeyClassifier()
    private var longPressTimer: Timer?
    private var modeKeyDownAt: TimeInterval = 0
    /// Caps Lock events up to this time are echoes of our own lock clear.
    private static var modeKeyQuietUntil: TimeInterval = 0
    /// Shift was held for a capital letter in Chinese mode: English until Shift comes up.
    private var shiftEnglish = false

    private var pushToTalk = PushToTalkDetector(key: VoiceSettings.pushToTalkKey)
    /// The utterance in progress, from key press until its final text is committed.
    private var voice: VoiceSession?
    /// True once the key is up and the final result is pending.
    private var voiceReleased = false
    /// Shift held when the key was released: commit the raw transcript, skip polishing.
    private var skipPolish = false
    /// A finished transcript waiting for the polish model; it stays on screen as marked text.
    private var pendingPolish: PendingPolish?

    private struct PendingPolish {
        let id = UUID()
        let raw: String
    }

    deinit {
        engine.destroySession(session)
        if let voice {
            DispatchQueue.main.async { voice.cancel() }
        }
    }

    // MARK: - IMKInputController

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    /// Every focus change starts in English, with the user's own keyboard layout.
    override func activateServer(_ sender: Any!) {
        mode = .english
        resetModeKeys()
        // The keyboard reports the key to whichever field has focus now.
        ModeKeyMonitor.shared.start()
        ModeKeyMonitor.shared.onKey = { [weak self] down in self?.modeKeyChanged(down: down) }
        clearRealCapsLock()
        applyKeyboard(client: sender as? IMKTextInput)
        pushToTalk = PushToTalkDetector(key: VoiceSettings.pushToTalkKey)
    }

    override func deactivateServer(_ sender: Any!) {
        pushToTalk.reset()
        resetModeKeys()
        commitComposition(sender)
        CandidatePanel.shared.hide()
    }

    /// Called by the system when focus moves away mid-composition.
    override func commitComposition(_ sender: Any!) {
        // A finished transcript is still on screen: commit it as spoken, into the field it was in.
        if let pending = pendingPolish {
            pendingPolish = nil
            setVoiceIdle()
            (sender as? IMKTextInput)?.insertText(pending.raw, replacementRange: Self.notFound)
            hasMarkedText = false
            return
        }
        // An unfinished utterance is dropped, never written: the field that had focus
        // when the user spoke may not be the one that has it now.
        if voice != nil {
            cancelVoice(client: sender as? IMKTextInput)
            return
        }
        guard engine.hasSession(session), let client = sender as? IMKTextInput else { return }
        if let raw = engine.flushRawInput(session) {
            client.insertText(raw, replacementRange: Self.notFound)
            hasMarkedText = false
        }
        syncUI(client: client)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else { return false }
        if let handled = handleVoice(event, client: client) { return handled }
        if event.type == .flagsChanged {
            if event.keyCode == InputMode.switchKeyCode {
                modeKeyEvent(lockOn: event.modifierFlags.contains(.capsLock))
            } else if shiftEnglish, !event.modifierFlags.contains(.shift) {
                shiftEnglish = false
            }
            // Modifier events are never swallowed: the host app still sees them.
            return false
        }
        // The input method's own Caps Lock types capitals itself; nothing else changes in English.
        // Without Input Monitoring there is no Caps Lock at all: the real lock can be left on for a
        // moment by the key press, so letters are typed in lower case (capitals with Shift) here.
        if event.type == .keyDown, mode == .english {
            let capitals: Bool? =
                SoftCapsLock.isOn ? true
                : (!ModeKeyMonitor.shared.isRunning && event.modifierFlags.contains(.capsLock)) ? false : nil
            if let capitals, let text = Self.letterText(event, capitals: capitals) {
                client.insertText(text, replacementRange: Self.notFound)
                return true
            }
        }
        // English mode leaves every key to the host app, so typing is exactly the native keyboard.
        // So does a password field: no composition, no candidate window, nothing recorded.
        guard mode == .chinese, event.type == .keyDown, !SecureInput.isActive else { return false }
        guard engine.isReady, ensureSession() else {
            if engine.state == .deploying {
                CandidatePanel.shared.presentTip("Deploying Rime…", anchor: caretRect(client))
            }
            return false
        }
        // Command shortcuts belong to the host app.
        if event.modifierFlags.contains(.command) { return false }
        // Holding Shift types capitals, as on the native keyboard, and English with them: the
        // typed letters stay as letters, and Chinese comes back when Shift is released.
        if shiftEnglish { return false }
        if Self.isShiftedLetter(event) {
            commitComposition(client)
            shiftEnglish = true
            Log.ime.info("shift held in Chinese mode: English until Shift is released")
            return false
        }
        // Pinyin is always typed in lower case, whatever the lock says.
        guard
            let key = KeyTranslator.keyDown(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                flags: event.modifierFlags.subtracting(.capsLock))
        else { return false }
        let consumed = engine.process(session, key: key)
        syncUI(client: client)
        return consumed
    }

    // MARK: - English / Chinese

    /// The letter a key types with Caps Lock on (`capitals`) or forced off: Shift flips the case,
    /// as on macOS. Nil for anything that is not a plain letter, which goes to the host app unchanged.
    private static func letterText(_ event: NSEvent, capitals: Bool) -> String? {
        let flags = event.modifierFlags
        guard flags.isDisjoint(with: [.command, .control, .option]), let characters = event.characters,
            characters.count == 1, characters.first?.isLetter == true
        else { return nil }
        return capitals != flags.contains(.shift) ? characters.uppercased() : characters.lowercased()
    }

    private static func isShiftedLetter(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.contains(.shift), flags.isDisjoint(with: [.control, .option]),
            let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first
        else { return false }
        return (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    // MARK: - 中/英 key

    /// The keyboard's own down and up for the key (`ModeKeyMonitor`).
    private func modeKeyChanged(down: Bool) {
        guard let client = self.client() else { return resetModeKeys() }
        let now = ProcessInfo.processInfo.systemUptime
        if down {
            modeKeyDownAt = now
            modeKey.press(at: now)
            longPressTimer?.invalidate()
            let timer = Timer(timeInterval: ModeKeyClassifier.holdThreshold, repeats: false) { [weak self] _ in
                guard let self, let client = self.client() else { return }
                if self.modeKey.held(at: ProcessInfo.processInfo.systemUptime) == .longPress {
                    self.toggleCapsLock(client: client)
                }
            }
            // Common modes: the timer must fire while the system is tracking events too.
            RunLoop.main.add(timer, forMode: .common)
            longPressTimer = timer
            return
        }
        longPressTimer?.invalidate()
        longPressTimer = nil
        let action = modeKey.release(at: now)
        let held = String(format: "%.3f", now - modeKeyDownAt)
        let outcome = action.map { String(describing: $0) } ?? "long press, already handled"
        Log.ime.info("mode key released after \(held, privacy: .public)s: \(outcome, privacy: .public)")
        switch action {
        case .tap: tapModeKey(client: client)
        case .longPress: toggleCapsLock(client: client)
        case nil: break
        }
        clearRealCapsLock()
    }

    /// The Caps Lock events macOS sends for the key. With the keyboard monitor running they carry
    /// nothing new. Without Input Monitoring they are all there is, and they cannot time a press:
    /// the lock turning on counts as a tap that only switches language. There is no long press and
    /// no Caps Lock; English stays lower case.
    private func modeKeyEvent(lockOn: Bool) {
        guard !ModeKeyMonitor.shared.isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard lockOn, now >= Self.modeKeyQuietUntil, let client = self.client() else { return }
        Log.ime.info("mode key tap (no Input Monitoring, so no long press)")
        Self.modeKeyQuietUntil = now + 0.3
        tapModeKey(client: client)
        clearRealCapsLockSoon()
    }

    /// Without the keyboard monitor there is no key-up to wait for, and turning the lock off while
    /// the key is still down does not stick (it comes straight back on). So wait, and retry until
    /// it stays off, ignoring the echo of each try.
    private func clearRealCapsLockSoon(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, CapsLock.isOn == true else { return }
            Self.modeKeyQuietUntil = ProcessInfo.processInfo.systemUptime + 0.3
            CapsLock.clear()
            if attempt < 8 { self.clearRealCapsLockSoon(attempt: attempt + 1) }
        }
    }

    /// The real lock is never wanted on: Caps Lock is `SoftCapsLock`. The key press can leave it
    /// on, so turn it off once the key is up, and ignore the echo that produces.
    private func clearRealCapsLock() {
        guard !ModeKeyMonitor.shared.isDown, CapsLock.isOn == true else { return }
        Self.modeKeyQuietUntil = ProcessInfo.processInfo.systemUptime + 0.2
        CapsLock.clear()
    }

    private func resetModeKeys() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        modeKey.reset()
        shiftEnglish = false
    }

    /// A tap steps back one state: Caps Lock off if it is on, otherwise the other language.
    private func tapModeKey(client: IMKTextInput) {
        if SoftCapsLock.isOn {
            SoftCapsLock.isOn = false
            CandidatePanel.shared.presentTip("Caps Lock off", anchor: caretRect(client), duration: 0.9)
        } else {
            switchMode(client: client)
        }
    }

    /// A long press turns Caps Lock on, from either language, and leaves the language English.
    /// Pressed again while it is on, it turns it off.
    private func toggleCapsLock(client: IMKTextInput) {
        SoftCapsLock.isOn.toggle()
        Log.ime.info("mode key long press: caps lock \(SoftCapsLock.isOn ? "on" : "off", privacy: .public)")
        shiftEnglish = false
        if mode == .chinese {
            // What was typed so far stays, as letters.
            commitComposition(client)
            mode = .english
            applyKeyboard(client: client)
        }
        CandidatePanel.shared.presentTip(
            SoftCapsLock.isOn ? "Caps Lock on" : "Caps Lock off", anchor: caretRect(client), duration: 0.9)
    }

    /// Returns true when the mode changed.
    @discardableResult
    private func switchMode(client: IMKTextInput) -> Bool {
        if mode == .english {
            // No pinyin in a password field.
            guard !SecureInput.isActive else { return false }
            // Rime is still compiling its dictionaries: stay in English rather than eat keys.
            guard engine.isReady, ensureSession() else {
                if engine.state == .deploying {
                    CandidatePanel.shared.presentTip("Deploying Rime…", anchor: caretRect(client))
                }
                return false
            }
        } else {
            // What was typed so far stays, as letters, the way losing focus would leave it.
            commitComposition(client)
        }
        mode.toggle()
        applyKeyboard(client: client)
        CandidatePanel.shared.presentTip(mode.announcement, anchor: caretRect(client), duration: 0.9)
        return true
    }

    /// Pinyin needs raw US keys; English keeps whatever layout the user types on.
    private func applyKeyboard(client: IMKTextInput?) {
        client?.overrideKeyboard(
            withKeyboardNamed: mode == .chinese ? KeyboardLayout.pinyinBase : KeyboardLayout.userASCIICapable)
    }

    // MARK: - Voice

    /// Watches for the push-to-talk key. Returns nil when the event is not voice's
    /// business and should go to Rime, otherwise the value `handle` should return.
    private func handleVoice(_ event: NSEvent, client: IMKTextInput) -> Bool? {
        switch event.type {
        case .flagsChanged:
            // The menu may have changed the key since this field gained focus.
            if !pushToTalk.isDown, pushToTalk.key != VoiceSettings.pushToTalkKey {
                pushToTalk = PushToTalkDetector(key: VoiceSettings.pushToTalkKey)
            }
            switch pushToTalk.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags) {
            case .press: beginVoice(client: client)
            case .release: endVoice(skipPolish: event.modifierFlags.contains(.shift))
            case nil: break
            }
            // Modifier events are never swallowed; while dictating, Rime does not need them
            // (and syncing its empty composition would wipe the marked text).
            return voice == nil && pendingPolish == nil ? nil : false
        case .keyDown:
            if pendingPolish != nil {
                // Typing on means the user does not want to wait: keep what was said.
                finishPolish(id: pendingPolish!.id, polished: nil)
                return nil
            }
            guard voice != nil else { return nil }
            if voiceReleased {
                // The final text is about to replace the marked text; a keystroke now
                // would land in the middle of it.
                return true
            }
            // A key during the hold means the modifier belongs to a shortcut, not dictation.
            cancelVoice(client: client)
            return nil
        default:
            return nil
        }
    }

    private func beginVoice(client: IMKTextInput) {
        // Dictating over a Rime composition would mix the two; the user can commit first.
        guard voice == nil, !hasMarkedText else { return }
        // Never listen while a password field has focus.
        guard !SecureInput.isActive else {
            CandidatePanel.shared.presentTip("Voice is off in password fields.", anchor: caretRect(client), duration: 2)
            return
        }
        // The mode is only a tie-breaker: speech in either language works in either mode.
        let recognition = VoiceSettings.recognition(hint: mode == .chinese ? .chinese : .english)
        let session = VoiceSession(recognition: recognition)
        session.onText = { [weak self, weak session] text in
            guard let self, let session, self.voice === session else { return }
            self.showVoiceText(text)
        }
        session.onFinish = { [weak self, weak session] text in
            guard let self, let session, self.voice === session else { return }
            self.commitVoice(text)
        }
        session.onLevel = { level in VoiceHUD.shared.setLevel(level) }
        session.onFailure = { [weak self, weak session] error in
            guard let self, let session, self.voice === session else { return }
            self.failVoice(error, recognition: recognition)
        }
        voice = session
        voiceReleased = false
        skipPolish = false
        Log.ime.info("voice start in \(client.bundleIdentifier() ?? "?", privacy: .public)")
        VoiceStatus.phase = .listening
        VoiceHUD.shared.show(.listening, anchor: caretRect(client))
        session.start()
        // Load the polish model while the user talks, so it is ready at release.
        if VoiceSettings.polishEnabled { Task { await PolishEngine.shared.warmUp() } }
    }

    private func endVoice(skipPolish: Bool) {
        guard let voice, !voiceReleased else { return }
        Log.ime.info("voice key released")
        voiceReleased = true
        self.skipPolish = skipPolish
        voice.finish()
    }

    private func cancelVoice(client: IMKTextInput?) {
        if voice != nil { Log.ime.info("voice cancelled (another key, or focus moved)") }
        voice?.cancel()
        voice = nil
        voiceReleased = false
        if let client { clearMarkedText(client) }
        setVoiceIdle()
    }

    private func showVoiceText(_ text: String) {
        guard !text.isEmpty, let client = self.client() else {
            if !text.isEmpty { Log.ime.error("voice text with no client to show it in") }
            return
        }
        Log.ime.debug("voice marked text: \(text.count) characters")
        let marked = NSMutableAttributedString(string: text)
        marked.addAttribute(
            .underlineStyle, value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: marked.length))
        client.setMarkedText(
            marked, selectionRange: NSRange(location: marked.length, length: 0), replacementRange: Self.notFound)
        hasMarkedText = true
    }

    private func commitVoice(_ text: String) {
        voice = nil
        voiceReleased = false
        setVoiceIdle()
        guard let client = self.client() else {
            Log.ime.error("voice finished with no client to write into")
            return
        }
        Log.ime.info("voice final: \(text.count) characters, into \(client.bundleIdentifier() ?? "?", privacy: .public)")
        if text.isEmpty {
            clearMarkedText(client)
        } else if VoiceSettings.polishEnabled, !skipPolish, PolishEngine.isInstalled {
            beginPolish(raw: text, client: client)
        } else {
            insertVoiceText(text, client: client)
        }
    }

    /// Keeps the raw transcript as marked text and asks the model for a cleaned version.
    /// Whatever happens, the raw text is what gets committed if the model has nothing better.
    private func beginPolish(raw: String, client: IMKTextInput) {
        let pending = PendingPolish(raw: raw)
        pendingPolish = pending
        VoiceStatus.phase = .polishing
        VoiceHUD.shared.show(.polishing, anchor: caretRect(client))
        Task {
            let polished = await PolishEngine.shared.polish(raw, timeout: VoiceSettings.polishTimeout)
            await MainActor.run { self.finishPolish(id: pending.id, polished: polished) }
        }
    }

    /// Commits the polished text, or the raw one when `polished` is nil. Ignores a stale answer.
    private func finishPolish(id: UUID, polished: String?) {
        guard let pending = pendingPolish, pending.id == id else { return }
        pendingPolish = nil
        setVoiceIdle()
        guard let client = self.client() else { return }
        insertVoiceText(polished ?? pending.raw, client: client)
    }

    /// Inserting replaces the marked preview.
    private func insertVoiceText(_ text: String, client: IMKTextInput) {
        Log.ime.info("voice insert: \(text.count) characters")
        client.insertText(text, replacementRange: Self.notFound)
        hasMarkedText = false
    }

    private func failVoice(_ error: VoiceError, recognition: Recognition) {
        voice = nil
        voiceReleased = false
        setVoiceIdle()
        guard let client = self.client() else { return }
        clearMarkedText(client)
        let anchor = caretRect(client)
        if case .assetsMissing = error {
            installSpeechAssets(locales: recognition.locales, anchor: anchor)
        } else {
            Log.ime.error("voice failed: \(error.message, privacy: .public)")
            CandidatePanel.shared.presentTip(error.message, anchor: anchor, duration: 4)
        }
    }

    /// First use of a language: fetch Apple's on-device models, then tell the user to try again.
    private func installSpeechAssets(locales: [Locale], anchor: NSRect) {
        CandidatePanel.shared.presentTip("Downloading speech data…", anchor: anchor, duration: 600)
        VoiceAssets.install(locales: locales) { [weak self] result in
            guard let self, self.voice == nil else { return }
            switch result {
            case .success:
                CandidatePanel.shared.presentTip("Speech data is ready. Hold the key and speak.", anchor: anchor, duration: 3)
            case .failure(let error):
                Log.ime.error("speech data install failed: \(error.message, privacy: .public)")
                CandidatePanel.shared.presentTip(error.message, anchor: anchor, duration: 4)
            }
        }
    }

    /// The voice path is done with the screen: hide the HUD and tell the menu bar.
    private func setVoiceIdle() {
        VoiceHUD.shared.hide()
        VoiceStatus.phase = .idle
    }

    private func clearMarkedText(_ client: IMKTextInput) {
        guard hasMarkedText else { return }
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
        hasMarkedText = false
    }

    // MARK: - Session

    private func ensureSession() -> Bool {
        guard engine.isReady else { return false }
        if engine.hasSession(session) { return true }
        session = engine.createSession()
        if session == 0 { Log.ime.error("could not create a Rime session") }
        return session != 0
    }

    // MARK: - UI sync

    /// Pushes librime's state to the client: committed text, marked text, candidates.
    private func syncUI(client: IMKTextInput) {
        if let text = engine.takeCommit(session), !text.isEmpty {
            // Inserting replaces any marked text, so Rime's next composition starts clean.
            client.insertText(text, replacementRange: Self.notFound)
            hasMarkedText = false
        }

        guard let composition = engine.composition(session) else {
            if hasMarkedText {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
                hasMarkedText = false
            }
            CandidatePanel.shared.hide()
            return
        }

        showMarkedText(composition, client: client)
        showCandidates(composition, client: client)
    }

    private func showMarkedText(_ composition: RimeComposition, client: IMKTextInput) {
        let text = NSMutableAttributedString(string: composition.preedit)
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
        let selection = composition.selection
        if selection.length > 0, NSMaxRange(selection) <= text.length {
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: selection)
        }
        client.setMarkedText(
            text,
            selectionRange: NSRange(location: min(composition.caret, text.length), length: 0),
            replacementRange: Self.notFound)
        hasMarkedText = true
    }

    private func showCandidates(_ composition: RimeComposition, client: IMKTextInput) {
        guard !composition.candidates.isEmpty else {
            CandidatePanel.shared.hide()
            return
        }
        let rows = composition.candidates.map {
            CandidateRow(label: $0.label, text: $0.text, comment: $0.comment)
        }
        CandidatePanel.shared.present(
            rows: rows,
            highlighted: composition.highlighted,
            anchor: caretRect(client)
        ) { [weak self] index in
            self?.pickCandidate(at: index)
        }
    }

    private func pickCandidate(at index: Int) {
        guard engine.hasSession(session), let client = self.client() else { return }
        if engine.selectCandidateOnCurrentPage(session, index: index) {
            syncUI(client: client)
        }
    }

    /// The caret's line rectangle in screen coordinates, or `.zero` when unknown.
    private func caretRect(_ client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }
}
