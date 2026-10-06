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
    /// Keeps the mode when focus only bounced away (system UI taking input for a moment).
    private var focus = FocusBounce()
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
    /// The field around the cursor, read when the push-to-talk key went down.
    private var dictation: DictationContext?
    /// What voice last wrote here, so consecutive dictation need not read the field again.
    private var recent = RecentCommit()

    private struct PendingPolish {
        let id = UUID()
        let raw: String
        let context: DictationContext?
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

    /// Short id for the log: one controller per text field, each with its own mode.
    private var tag: String { String(UInt(bitPattern: ObjectIdentifier(self).hashValue) & 0xFFFF, radix: 16) }

    /// Every focus starts in English, with the user's own keyboard layout, unless focus only
    /// bounced away for a moment (`FocusBounce`).
    override func activateServer(_ sender: Any!) {
        Log.ime.info(
            "activate \(self.tag, privacy: .public) in \((sender as? IMKTextInput)?.bundleIdentifier() ?? "?", privacy: .public), mode was \(String(describing: self.mode), privacy: .public)")
        let kept = focus.modeOnActivation(current: mode, at: ProcessInfo.processInfo.systemUptime)
        mode = kept == .chinese && engine.isReady && ensureSession() ? .chinese : .english
        if mode == .chinese { Log.ime.info("focus bounced back to \(self.tag, privacy: .public): keeping Chinese") }
        shiftEnglish = false
        applyKeyboard(client: sender as? IMKTextInput)
        pushToTalk = PushToTalkDetector(key: VoiceSettings.pushToTalkKey)
    }

    override func deactivateServer(_ sender: Any!) {
        Log.ime.info("deactivate \(self.tag, privacy: .public), mode \(String(describing: self.mode), privacy: .public)")
        focus.deactivated(at: ProcessInfo.processInfo.systemUptime)
        pushToTalk.reset()
        shiftEnglish = false
        commitComposition(sender)
        recent.invalidate()
        CandidatePanel.shared.hide()
    }

    /// Called by the system when focus moves away mid-composition.
    override func commitComposition(_ sender: Any!) {
        // A finished transcript is still on screen: commit it as spoken, into the field it was in.
        if let pending = pendingPolish {
            pendingPolish = nil
            setVoiceIdle()
            if let client = sender as? IMKTextInput {
                insertVoiceText(pending.raw, context: pending.context, client: client)
            }
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
        // Typing, deleting, or moving the cursor: the field is no longer what voice left it.
        if event.type == .keyDown { recent.invalidate() }
        if event.type == .flagsChanged {
            if event.keyCode == InputMode.switchKeyCode {
                modeKeyPressed(flags: event.modifierFlags)
            } else if shiftEnglish, !event.modifierFlags.contains(.shift) {
                shiftEnglish = false
            }
            // Modifier events are never swallowed: the host app still sees them.
            return false
        }
        // Which mode each key lands in, and in which controller; never which key it was.
        if event.type == .keyDown {
            Log.ime.debug("key in \(String(describing: self.mode), privacy: .public) by \(self.tag, privacy: .public)")
        }
        // The real lock follows the 中/英 key, so English letters take their case from the guard
        // whenever a lock is on. Not in a password field: nothing is typed for the user there.
        if event.type == .keyDown, mode == .english, !SecureInput.isActive,
            let text = CapsLockGuard.shared.englishText(event.characters, flags: event.modifierFlags)
        {
            client.insertText(text, replacementRange: Self.notFound)
            return true
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
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                flags: event.modifierFlags.subtracting(.capsLock))
        else { return false }
        let consumed = engine.process(session, key: key)
        syncUI(client: client)
        return consumed
    }

    // MARK: - English / Chinese

    private static func isShiftedLetter(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.contains(.shift), flags.isDisjoint(with: [.control, .option]),
            let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first
        else { return false }
        return (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    // MARK: - 中/英 key

    /// One press of the key, as `CapsLockGuard` reads it. The real lock is never touched.
    private func modeKeyPressed(flags: NSEvent.ModifierFlags) {
        let shift = CapsLockGuard.shiftHeld(flags)
        let action = CapsLockGuard.shared.press(shift: shift, at: ProcessInfo.processInfo.systemUptime)
        Log.ime.info(
            "mode key: shift \(shift ? "held" : "up", privacy: .public), real lock \(flags.contains(.capsLock) ? "on" : "off", privacy: .public), \(action.map { String(describing: $0) } ?? "duplicate, ignored", privacy: .public)")
        guard let action, let client = self.client() else { return }
        switch action {
        case .switchLanguage: switchMode(client: client)
        case .capsLockOn: capsLockTurnedOn(client: client)
        case .capsLockOff: CandidatePanel.shared.presentTip("Caps Lock off", anchor: caretRect(client), duration: 0.9)
        }
    }

    /// Shift + 中/英 turned Caps Lock on: English, in capitals, until it is turned off.
    private func capsLockTurnedOn(client: IMKTextInput) {
        shiftEnglish = false
        if mode == .chinese {
            // What was typed so far stays, as letters.
            commitComposition(client)
            mode = .english
            applyKeyboard(client: client)
        }
        CandidatePanel.shared.presentTip("Caps Lock on", anchor: caretRect(client), duration: 0.9)
    }

    /// Returns true when the mode changed.
    @discardableResult
    private func switchMode(client: IMKTextInput) -> Bool {
        if mode == .english {
            // No pinyin in a password field.
            guard !SecureInput.isActive else {
                Log.ime.info("switch refused: secure input")
                return false
            }
            // Rime is still compiling its dictionaries: stay in English rather than eat keys.
            guard engine.isReady, ensureSession() else {
                Log.ime.info("switch refused: Rime \(String(describing: self.engine.state), privacy: .public)")
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
        Log.ime.info(
            "mode now \(String(describing: self.mode), privacy: .public) in \(self.tag, privacy: .public), marked text \(self.hasMarkedText)")
        applyKeyboard(client: client)
        CandidatePanel.shared.presentTip(mode.announcement, anchor: caretRect(client), duration: 0.9)
        return true
    }

    /// Pinyin needs raw US keys; English keeps whatever layout the user types on.
    private func applyKeyboard(client: IMKTextInput?) {
        client?.overrideKeyboard(
            withKeyboardNamed: mode == .chinese ? KeyboardLayout.pinyinBase : KeyboardLayout.english)
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
            if event.keyCode == pushToTalk.key.keyCode {
                Log.ime.info(
                    "push-to-talk key event: flags 0x\(String(event.modifierFlags.rawValue, radix: 16), privacy: .public), was \(self.pushToTalk.isDown ? "down" : "up", privacy: .public)")
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
        // Read the field first: its words prime the recognizer as well as the polish model.
        let context = captureContext(client)
        dictation = context
        let hints = VocabularyHints.terms(before: context.before, style: context.style)
        let session = VoiceSession(recognition: recognition, hints: hints, whisper: whisperRequest(context, hints: hints))
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
        Log.ime.info(
            "voice start in \(client.bundleIdentifier() ?? "?", privacy: .public), \(hints.count) hint terms")
        VoiceStatus.phase = .listening
        VoiceHUD.shared.show(.listening, anchor: caretRect(client))
        session.start()
        // Load the polish model while the user talks, so it is ready at release.
        if VoiceSettings.polishEnabled { Task { await PolishEngine.shared.warmUp() } }
    }

    /// What to ask Whisper, when it is the chosen engine and loaded. Otherwise Apple's text is final;
    /// a Whisper that is chosen but not loaded starts loading for the next utterance.
    private func whisperRequest(_ context: DictationContext, hints: [String]) -> WhisperRequest? {
        guard VoiceSettings.speechEngine == .whisper else { return nil }
        guard WhisperEngine.isReady else {
            let reason =
                !WhisperEngine.isInstalled ? "not installed"
                : VoiceSettings.whisperOffloaded ? "offloaded"
                : MemoryGovernor.tier > 0 ? "paused by memory pressure" : "not loaded yet"
            Log.ime.info("voice engine: apple, whisper \(reason, privacy: .public)")
            Task { await WhisperEngine.shared.warmUp() }
            return nil
        }
        return WhisperRequest(
            prompt: WhisperText.prompt(before: context.before, hints: hints),
            language: WhisperText.language(for: VoiceSettings.localeIdentifier, autoDetect: VoiceSettings.autoDetect))
    }

    /// The text around the cursor, for the spacing and the polish model: this field's record of
    /// what voice just wrote while the cursor has not moved, otherwise the field itself. Read
    /// now, while the key is held and nothing can be typed, not after release while the user waits.
    private func captureContext(_ client: IMKTextInput) -> DictationContext {
        let style = AppStyle.forApp(client.bundleIdentifier())
        let selection = client.selectedRange()
        let caret = selection.location == NSNotFound ? nil : selection.location
        let context = recent.context(style: style, currentCaret: caret) ?? readField(client, selection: selection, style: style)
        Log.ime.info(
            "voice context: \(context.source.rawValue, privacy: .public), \(context.before?.count ?? 0) before, \(context.after?.count ?? 0) after, style \(style.rawValue, privacy: .public)")
        return context
    }

    /// What the app shares of the text on either side of the selection, which dictation replaces.
    private func readField(_ client: IMKTextInput, selection: NSRange, style: AppStyle) -> DictationContext {
        guard selection.location != NSNotFound else {
            return DictationContext(style: style, before: nil, after: nil, source: .none)
        }
        let start = max(0, selection.location - DictationContext.beforeLimit)
        let before = selection.location > start
            ? client.attributedSubstring(from: NSRange(location: start, length: selection.location - start))?.string
            : nil
        let end = NSMaxRange(selection)
        let total = client.length()
        // Some apps report no length; then ask for the most and take what comes back.
        let available = total == NSNotFound || total < end ? DictationContext.afterLimit : total - end
        let after = available > 0
            ? client.attributedSubstring(from: NSRange(location: end, length: min(available, DictationContext.afterLimit)))?.string
            : nil
        let source: DictationContext.Source = before == nil && after == nil ? .none : .field
        return DictationContext(style: style, before: before, after: after, source: source)
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
        dictation = nil
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
        let context = dictation
        voice = nil
        dictation = nil
        voiceReleased = false
        setVoiceIdle()
        guard let client = self.client() else {
            Log.ime.error("voice finished with no client to write into")
            return
        }
        Log.ime.info("voice final: \(text.count) characters, into \(client.bundleIdentifier() ?? "?", privacy: .public)")
        if text.isEmpty {
            clearMarkedText(client)
        } else if VoiceSettings.polishEnabled, !skipPolish, PolishEngine.isAvailable {
            beginPolish(raw: text, context: context, client: client)
        } else {
            insertVoiceText(text, context: context, client: client)
        }
    }

    /// Keeps the raw transcript as marked text and asks the model for a cleaned version.
    /// Whatever happens, the raw text is what gets committed if the model has nothing better.
    private func beginPolish(raw: String, context: DictationContext?, client: IMKTextInput) {
        let pending = PendingPolish(raw: raw, context: context)
        pendingPolish = pending
        VoiceStatus.phase = .polishing
        VoiceHUD.shared.show(.polishing, anchor: caretRect(client))
        Task {
            let polished = await PolishEngine.shared.polish(raw, context: context, timeout: PolishPrompt.timeout(for: raw, scale: PolishModel.current.timeoutScale))
            await MainActor.run { self.finishPolish(id: pending.id, polished: polished) }
        }
    }

    /// Commits the polished text, or the raw one when `polished` is nil. Ignores a stale answer.
    private func finishPolish(id: UUID, polished: String?) {
        guard let pending = pendingPolish, pending.id == id else { return }
        pendingPolish = nil
        setVoiceIdle()
        guard let client = self.client() else { return }
        insertVoiceText(polished ?? pending.raw, context: pending.context, client: client)
    }

    /// Inserting replaces the marked preview. Text inside a sentence is fitted to it, spaces keep
    /// it off its neighbours, and the field's record now ends with what was written.
    private func insertVoiceText(_ text: String, context: DictationContext?, client: IMKTextInput) {
        let fitted = SentenceJoin.fitted(text, before: context?.before, after: context?.after)
        let padded = VoiceSpacing.padded(fitted, before: context?.before?.last, after: context?.after?.first)
        Log.ime.info("voice insert: \(text.count) characters, \(padded.count - text.count) spaces added")
        client.insertText(padded, replacementRange: Self.notFound)
        hasMarkedText = false
        let caret = client.selectedRange().location
        recent.record(padded, context: context, caretAfter: caret == NSNotFound ? nil : caret)
    }

    private func failVoice(_ error: VoiceError, recognition: Recognition) {
        voice = nil
        dictation = nil
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
