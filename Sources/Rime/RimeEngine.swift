import Foundation

struct RimeCandidateItem: Equatable {
    let label: String
    let text: String
    let comment: String
}

/// What the UI needs to render an in-progress composition.
struct RimeComposition {
    let preedit: String
    /// Caret position and highlighted segment, as UTF-16 offsets into `preedit`.
    let caret: Int
    let selection: NSRange
    let candidates: [RimeCandidateItem]
    let highlighted: Int
    let pageNo: Int
    let isLastPage: Bool
}

/// Swift wrapper over the librime C API. Main thread only, except that deployment
/// is joined on a background queue.
final class RimeEngine {
    static let shared = RimeEngine()

    struct Configuration {
        var sharedDataDir: URL
        /// Files copied into `userDataDir` on first run (never overwritten).
        var seedDir: URL?
        var userDataDir: URL
        var logDir: URL
        /// 0 = info, 1 = warning, 2 = error, 3 = fatal.
        var minLogLevel: Int32 = 1
    }

    enum State: Equatable {
        case idle
        /// Dictionaries are being compiled; keys must pass through untouched.
        case deploying
        case ready
        case failed
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var isReady: Bool { state == .ready }
    var onStateChange: ((State) -> Void)?

    private let rime: RimeApi
    /// strdup'd traits strings; librime may hold on to them for the process lifetime.
    private var retainedStrings: [UnsafeMutablePointer<CChar>] = []
    private var sawDeployFailure = false
    private var configuration: Configuration?
    /// Sessions this engine created since it was last initialized. librime reuses session ids
    /// after a restart, so a stale id must not pass for a live one.
    private var liveSessions: Set<UInt> = []

    private init() {
        rime = rime_get_api().pointee
    }

    // MARK: - Lifecycle

    func start(_ config: Configuration, fullCheck: Bool = false) {
        guard state == .idle else { return }
        configuration = config

        let fm = FileManager.default
        try? fm.createDirectory(at: config.userDataDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: config.logDir, withIntermediateDirectories: true)
        seedUserData(from: config.seedDir, to: config.userDataDir)

        var traits = RimeTraits()
        traits.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
        traits.shared_data_dir = retain(config.sharedDataDir.path)
        traits.user_data_dir = retain(config.userDataDir.path)
        traits.log_dir = retain(config.logDir.path)
        traits.min_log_level = config.minLogLevel
        traits.distribution_name = retain("Typeless-Rev")
        traits.distribution_code_name = retain("TypelessRev")
        traits.distribution_version = retain(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        traits.app_name = retain("rime.typeless-rev")

        rime.setup!(&traits)
        rime.set_notification_handler!(rimeNotificationHandler, nil)
        rime.initialize!(&traits)
        let version = rime.get_version!().map { String(cString: $0) } ?? "unknown"
        Log.rime.info("librime \(version, privacy: .public) initialized")

        // Compiles anything missing or stale. Usually a no-op thanks to the
        // dictionaries prebuilt into the bundle.
        state = .deploying
        _ = rime.start_maintenance!(fullCheck ? 1 : 0)
        sawDeployFailure = false
        DispatchQueue.global(qos: .userInitiated).async { [rime] in
            rime.join_maintenance_thread!()
            DispatchQueue.main.async { self.finishDeployment() }
        }
    }

    func finalize() {
        guard state != .idle else { return }
        rime.finalize!()
        liveSessions.removeAll()
        state = .idle
    }

    /// Recompiles the dictionaries and reloads the user's config, like Squirrel's "Deploy".
    /// Open compositions are dropped; each text field gets a fresh session on its next key.
    func redeploy() {
        guard let config = configuration, state == .ready || state == .failed else { return }
        finalize()
        start(config, fullCheck: true)
    }

    private func finishDeployment() {
        let probe = rime.create_session!()
        if probe != 0 { _ = rime.destroy_session!(probe) }
        if probe == 0 || sawDeployFailure {
            Log.rime.error("deployment finished with problems (session probe: \(probe != 0))")
        }
        state = probe != 0 ? .ready : .failed
    }

    fileprivate func handleNotification(type: String, value: String) {
        Log.rime.info("notification \(type, privacy: .public): \(value, privacy: .public)")
        if type == "deploy", value == "failure" { sawDeployFailure = true }
    }

    // MARK: - Sessions

    func createSession() -> UInt {
        let session = rime.create_session!()
        if session != 0 { liveSessions.insert(session) }
        return session
    }

    func hasSession(_ session: UInt) -> Bool {
        session != 0 && liveSessions.contains(session) && rime.find_session!(session) != 0
    }

    func destroySession(_ session: UInt) {
        guard session != 0, state != .idle, liveSessions.remove(session) != nil else { return }
        _ = rime.destroy_session!(session)
    }

    // MARK: - Input

    /// Returns true when librime consumed the key.
    func process(_ session: UInt, key: RimeKeyEvent) -> Bool {
        rime.process_key!(session, key.keycode, key.mask) != 0
    }

    /// Ends the composition and returns the letters the user typed ("nihao"), for
    /// when focus is lost mid-typing. Rime's own commit_composition would convert the
    /// highlighted candidate instead, which is a surprising thing to insert uninvited.
    func flushRawInput(_ session: UInt) -> String? {
        let raw = rime.get_input!(session).map { String(cString: $0) } ?? ""
        rime.clear_composition!(session)
        return raw.isEmpty ? nil : raw
    }

    func selectCandidateOnCurrentPage(_ session: UInt, index: Int) -> Bool {
        rime.select_candidate_on_current_page!(session, index) != 0
    }

    // MARK: - Output

    /// Text librime wants inserted into the client, if any.
    func takeCommit(_ session: UInt) -> String? {
        var commit = RimeCommit()
        commit.data_size = Int32(MemoryLayout<RimeCommit>.size - MemoryLayout<Int32>.size)
        guard rime.get_commit!(session, &commit) != 0 else { return nil }
        defer { _ = rime.free_commit!(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    /// The current composition, or nil when the user isn't composing.
    func composition(_ session: UInt) -> RimeComposition? {
        var ctx = RimeContext()
        ctx.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        guard rime.get_context!(session, &ctx) != 0 else { return nil }
        defer { _ = rime.free_context!(&ctx) }
        guard ctx.composition.length > 0, let rawPreedit = ctx.composition.preedit else { return nil }

        let preedit = String(cString: rawPreedit)
        let selStart = TextOffsets.utf16Offset(forUTF8Offset: Int(ctx.composition.sel_start), in: preedit)
        let selEnd = TextOffsets.utf16Offset(forUTF8Offset: Int(ctx.composition.sel_end), in: preedit)
        let caret = TextOffsets.utf16Offset(forUTF8Offset: Int(ctx.composition.cursor_pos), in: preedit)

        let menu = ctx.menu
        let selectKeys = menu.select_keys.map { String(cString: $0) } ?? "1234567890"
        let keyLabels = selectKeys.map { String($0) }
        var items: [RimeCandidateItem] = []
        for i in 0..<Int(max(0, menu.num_candidates)) {
            let candidate = menu.candidates![i]
            let label: String
            if let labels = ctx.select_labels, i < Int(menu.page_size), let raw = labels[i] {
                label = String(cString: raw)
            } else if i < keyLabels.count {
                label = keyLabels[i]
            } else {
                label = String((i + 1) % 10)
            }
            items.append(
                RimeCandidateItem(
                    label: label,
                    text: candidate.text.map { String(cString: $0) } ?? "",
                    comment: candidate.comment.map { String(cString: $0) } ?? ""))
        }

        return RimeComposition(
            preedit: preedit,
            caret: caret,
            selection: NSRange(location: selStart, length: max(0, selEnd - selStart)),
            candidates: items,
            highlighted: Int(menu.highlighted_candidate_index),
            pageNo: Int(menu.page_no),
            isLastPage: menu.is_last_page != 0)
    }

    // MARK: - Helpers

    private func retain(_ string: String) -> UnsafePointer<CChar> {
        let pointer = strdup(string)!
        retainedStrings.append(pointer)
        return UnsafePointer(pointer)
    }

    /// Copies the bundled seed files into the user data directory. A file the user already has
    /// stays, unless it still carries the managed marker and the bundled copy has changed.
    private func seedUserData(from seedDir: URL?, to userDir: URL) {
        guard let seedDir,
            let names = try? FileManager.default.contentsOfDirectory(atPath: seedDir.path)
        else { return }
        for name in names where !name.hasPrefix(".") {
            let source = seedDir.appendingPathComponent(name)
            let target = userDir.appendingPathComponent(name)
            let existing = try? String(contentsOf: target, encoding: .utf8)
            let bundled = try? String(contentsOf: source, encoding: .utf8)
            if FileManager.default.fileExists(atPath: target.path) {
                guard let existing, let bundled, SeedPolicy.shouldInstall(existing: existing, bundled: bundled)
                else { continue }
            }
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: source, to: target)
            } catch {
                Log.rime.error("could not seed \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// librime calls this from whatever thread is doing the work.
private let rimeNotificationHandler: RimeNotificationHandler = { _, _, type, value in
    let type = type.map { String(cString: $0) } ?? ""
    let value = value.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async { RimeEngine.shared.handleNotification(type: type, value: value) }
}
