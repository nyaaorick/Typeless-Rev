# Typeless-Rev

A macOS input method built on InputMethodKit that types through an embedded
[librime](https://github.com/rime/librime), plus push-to-talk dictation through Apple's
on-device speech APIs and a local LLM (MLX) that polishes what you said. See
[roadmap.md](roadmap.md) for the plan; this tree currently implements Phase 1 (IME skeleton +
librime typing), Phase 2 (voice MVP), Phase 3 (local LLM polish), Phase 4 (menu bar and HUD) and
Phase 5 (English first, pinyin as a mode, speech language auto-detect) and Phase 6 (stable signing,
permission onboarding, password-field safety, profiling).

## Using it

It starts in **English** and types exactly like the native keyboard: every key goes straight to the
app. Press the **中/英 key** (the Caps Lock key; on a Mac sold in China, a tap of it) to switch to
**Chinese pinyin**, and again to switch back. Each switch shows a short note ("Switch to Chinese
mode" / "Switch to English mode"). Pinyin gives Chinese characters only; all punctuation is ASCII
(`,` `.` `?` `!` are never `，` `。` `？` `！`). Every new focus starts in English again.

The key has three states: Chinese, English, and English with Caps Lock.

- A **tap** steps back one state. In Chinese it switches to English, even while the blue
  composition box is showing (the pinyin typed so far stays as plain letters). In English it
  switches to Chinese. With Caps Lock on it turns Caps Lock off and stays in English.
- A **long press** (half a second) turns Caps Lock on, from either language, and leaves the
  language on English. A long press while it is on turns it off.
- **Holding Shift** types capitals as on the native keyboard. In Chinese mode a Shift-letter keeps
  the pinyin typed so far as letters, and pinyin resumes when Shift is released. With Caps Lock on,
  Shift gives lower case, as on macOS.

Telling a tap from a long press needs the **Input Monitoring** permission (System Settings >
Privacy & Security; the input method asks once, and the menu shows its state). Without it every
press is a tap: the key only switches language, there is no Caps Lock, and English letters are
always lower case (Shift still gives capitals).

This Caps Lock belongs to the input method: the keyboard light does not come on. The menu bar icon
shows a Caps Lock symbol while it is on, and each change shows a short tip. It stays on across
fields and apps until you turn it off. It does not apply in password fields, which macOS keeps away
from input methods.

If your Mac is set to use Caps Lock to switch input sources (Keyboard > Input Sources), macOS
handles the key before this input method sees it; turn that option off to use it for the mode.

## Requirements

macOS 26+, Xcode 26, `xcodegen`, `gh` (authenticated) and `brew`. Homebrew is only used to
download the OpenCC dictionaries; nothing is installed system-wide.

MLX compiles its Metal shaders with Xcode's Metal Toolchain. If the build stops with
"missing Metal Toolchain", run `xcodebuild -downloadComponent MetalToolchain` once (about 700 MB).

## Build, test, install

```sh
scripts/build.sh          # fetches vendor/ on first run, prints the .app path
scripts/selftest.sh       # unit tests + the librime and menu bar/HUD self-tests
SPEECH=1 scripts/selftest.sh   # ...and the speech pipeline (downloads speech models on first run)
POLISH=1 scripts/selftest.sh   # ...and the polish model (run scripts/prepare-model.sh first)
scripts/prepare-model.sh       # the menu's "Download" without the menu: install the polish model (2.4 GB)
scripts/install.sh        # build, copy to ~/Library/Input Methods, register + enable
scripts/setup-signing.sh  # once: a stable signing identity, so the microphone grant survives rebuilds
```

`install.sh` never switches your input source. It enables **Typeless-Rev**, which is listed under
System Settings > Keyboard > Input Sources > English (it is an English-first input method; log out
and in once if it is not listed). Builds before Phase 5 registered a "Chinese, Simplified" source;
`install.sh` turns that old entry off, so after upgrading pick the new **Typeless-Rev** once. Rebuilding replaces the installed bundle and stops the running copy; macOS
starts the new one when the input source is next used.

## Signing

macOS ties the microphone permission to the app's code signature. An ad-hoc signature (what a plain
build gets) is different every time, so each rebuild would ask again. `scripts/build.sh` therefore
signs with a stable identity, chosen by `scripts/sign-identity.sh` in this order: `$SIGN_IDENTITY` if
set (`-` forces ad-hoc), a self-signed certificate named `TypelessDev`, the first valid Apple
Development certificate (a free Apple ID's Personal Team), then ad-hoc with a warning.

Run `scripts/setup-signing.sh` once in a terminal to create and trust `TypelessDev`. It needs you
there: macOS asks for your login password to trust the certificate, and the script asks for it once
more so `codesign` can use the key without a dialog (read silently, never stored). If a new key makes
macOS show a Keychain "codesign wants to sign" dialog, choose Always Allow. The identity is only used
if `codesign` can use it without a prompt, so a build never hangs behind a dialog.

The app is not notarized (that needs a paid Apple Developer account), which only matters for a copy
downloaded to another Mac. `scripts/install.sh` installs from this repo, so it is not affected.
Check what a build is signed with: `codesign -dr - ~/Library/Input\ Methods/Typeless-Rev.app`.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/Core` | Pure logic with no framework dependencies, all unit tested: key translation, push-to-talk detection, transcript assembly, the polish prompt and reply checks, the mic level meter, the safetensors filter. |
| `Sources/Rime` | `RimeEngine`, the Swift wrapper over the librime C API. |
| `Sources/IME` | `TypelessInputController` (IMK), the candidate panel, and the voice HUD. |
| `Sources/Voice` | `VoiceSession` (one utterance: audio feed to `SpeechAnalyzer`), audio feeds, speech model install, settings. |
| `Sources/Polish` | `PolishEngine` (the local Qwen model through `mlx-swift-lm`), `ModelInstaller` (download, verify, strip), the tokenizer adapter. |
| `Sources/App` | Entry point, `StatusMenu` (the menu bar icon), paths, logging, the `--selftest*`, `--install-model` and `--register` commands. |
| `Data/` | `rime/` (our pinyin schema), `user-seed/` (copied to the user data dir) and our OpenCC config. |
| `scripts/` | Vendor fetch, build, bundle (embeds librime and data), install, selftest, prepare-model. |
| `vendor/` | Pinned downloads: librime 1.17.0, Rime data repos, OpenCC dictionaries. Gitignored. |

## Self-tests

The input method has no UI to drive from a script, so the binary tests itself headlessly. Each flag
runs one check, prints PASS/FAIL lines, and exits non-zero on failure:

| Command | What it checks |
| --- | --- |
| `Typeless-Rev --selftest` | Embedded librime: deploy, typing, candidates, ASCII punctuation and Chinese-characters-only candidates, focus-loss flush, simplified output, upgrade from the first-release config, Caps Lock reset, secure-input detection, redeploy. |
| `Typeless-Rev --selftest-ui` | The menu bar menu (items, permission lines, settings, checkmarks, icon state), the polish crash-loop breaker, and the HUD (size, placement, show/hide). Restores your settings. |
| `Typeless-Rev --selftest-speech` | Synthesized en-US and zh-CN speech through `VoiceSession`: transcript, live updates, cancel; then the auto-detecting path on English, Chinese and mixed phrases (with a deliberately wrong mode hint), printing each recognizer's confidence. Downloads the speech models on first run. |
| `Typeless-Rev --selftest-polish` | The polish model: cold and warm latency, filler removal (zh, en), an injection attempt, the timeout, memory handed back after an unload, reload. Needs the model installed. |
| `Typeless-Rev --disable-legacy` | Not a test: turns off input sources an older build registered (`install.sh` runs it). |
| `Typeless-Rev --install-model` | Not a test: the menu's model download, headless. |

Run them from the built app, for example
`build/DerivedData/Build/Products/Release/Typeless-Rev.app/Contents/MacOS/Typeless-Rev --selftest-ui`.
What they cannot cover is anything that needs a real text field or microphone; see the status
list in [roadmap.md](roadmap.md) and the checklist in [SMOKE_TEST.md](SMOKE_TEST.md).

## How it fits together

- **Bundle.** `scripts/bundle-rime.sh` runs as the target's post-build phase. It copies
  `librime.1.dylib` and the plugins into `Contents/Frameworks`, the schemas and OpenCC data
  into `Contents/SharedSupport/rime`, prebuilds the dictionaries with `rime_deployer`, signs
  everything, and fails the build if any dylib links outside the bundle or system.
- **User data.** Rime state lives in `~/Library/Application Support/Typeless-Rev/Rime`
  (override with `TYPELESS_REV_USER_DIR`). `default.custom.yaml` is seeded there. Its first line,
  `# managed-by: typeless-rev`, lets the app refresh it when a new build changes it; delete that
  line to keep your own copy.
- **Schema.** One schema of our own, `typeless_pinyin` (`Data/rime/`), on the Luna Pinyin
  dictionary: simplified characters through OpenCC (our own `t2s.json`, because the Homebrew one
  targets a newer OpenCC than the one compiled into librime 1.17), every ASCII punctuation key
  mapped to itself (a punctuation key typed mid-composition commits the highlighted candidate,
  then the character), and no symbol, emoji, stroke or full-width candidates. The Traditional
  schema is not shipped.
- **Modes.** English is a pass-through: the controller returns every key to the host and Rime
  sees nothing. Rime's own ASCII switch, Shift toggle and Caps Lock handling are not used. A tap
  and a long press of the 中/英 key are told apart by reading the key's down and up from the
  keyboard itself (`ModeKeyMonitor`, IOHIDManager, Input Monitoring): on Apple keyboards the
  system's "is it held" state follows the lock, not the finger. The real lock is never turned on: on this
  keyboard the system reports the key as held while the lock is on, so a lock written by the input
  method hides what the finger is doing. Caps Lock is the input method's own (`SoftCapsLock`). The
  keyboard layout is forced to US ABC only in Chinese mode; English keeps your own layout.
- **Keys.** Command shortcuts go to the host app. Modifier events are never swallowed.
- **Focus loss.** Mid-composition focus loss inserts the typed letters, not a converted guess.

## Menu bar

The icon in the menu bar is the whole interface; there is no Dock icon and no settings window. It
shows the state (a red microphone while listening, sparkles while polishing, a warning if Rime
failed to start) and its menu holds everything:

- **Microphone** and **Speech Data**: first-run setup. The microphone line shows the grant and
  asks for it ("Allow…") or opens the Privacy pane when it is off; speech data downloads the models
  for the current language setting (Auto-Detect needs two).
- **Polish with Local LLM**: turn polishing on or off. If the polish model crashes the input method
  twice in a row, polishing turns itself off and the menu says so; switching it back on clears that.
- **Speech Language** and **Push-to-Talk Key**: take effect on the next dictation.
- **Polish Model**: download (3 GB, once), cancel, or move to the Trash. Shows the state and size.
- **Open Rime Folder** and **Redeploy Rime** (recompiles dictionaries, reloads `*.custom.yaml`).
- **About** and **Quit** (macOS restarts the input method the next time it is used).

While you dictate, a small pill near the caret shows a red dot and a live level meter, then a
spinner while the model polishes. It never takes focus and disappears when you are done.

## Password fields

While macOS reports secure input (a password field has focus, or Terminal's Secure Keyboard Entry
is on), voice does not start ("Voice is off in password fields.") and Chinese mode does not switch
on or compose: keys go straight to the app.

## Voice

Hold **Right Option**, speak, release. The words appear as marked text while you speak and are
committed when you let go. Releasing is what finalizes the text; pressing any other key during
the hold cancels the dictation (the modifier was part of a shortcut), and so does losing focus.

- **Needs macOS 26.** Speech runs on the device through `SpeechAnalyzer` / `SpeechTranscriber`;
  nothing is sent anywhere.
- **First use.** macOS asks for microphone access. The first dictation in a locale downloads
  Apple's speech model (a status tip says so); hold the key again once it is ready.
- **Settings.** The menu bar sets these; they are also plain `defaults` keys:

  ```sh
  defaults write com.nyaaorick.inputmethod.TypelessRev speechLocale en-US       # default auto
  defaults write com.nyaaorick.inputmethod.TypelessRev pushToTalkKey rightControl  # rightOption, rightControl, rightCommand
  ```

  The menu applies changes on the next dictation; with `defaults`, restart the input method
  (`pkill Typeless-Rev`; macOS relaunches it).
- **Keyboard first.** Voice does not start while a Rime composition is open.
- **Language.** **Auto-Detect** (the default) listens in English (en-US) and Mandarin (zh-CN) at
  once and commits the one that fits what you said, whichever mode you are in; the mode only
  breaks a tie. The menu's other entries pin a single language. Both speech models download on
  first use. Mixed speech goes to one language as a whole: Chinese with English words comes out
  as Chinese with the English words as the Mandarin model hears them (usually right for common
  words, sometimes dropped or garbled), and English with a Chinese name may come out in either.
  Running two recognizers costs some extra CPU while you hold the key.

### Polish

After you release the key, the transcript is cleaned up by a local LLM (punctuation, filler words,
obvious misrecognitions) and committed. The raw transcript stays on screen as marked text until the
polished text replaces it. If the model is missing, still loading, or slower than 3 seconds, the raw
transcript is committed instead; typing a key while it waits commits the raw text at once. Hold
**Shift** when you release the key to skip polishing for that utterance.

- **Model.** `CaseD0rsett/Qwen3.8-4B-Distill-Heretic-Abliterated-MLX-4bit` (Apache 2.0, pinned
  revision), run in-process with `mlx-swift-lm`. No server and no network at inference time.
  The menu's **Download** (or `scripts/prepare-model.sh`) fetches the file from Hugging Face at
  that revision, checks its SHA-256, and writes a text-only copy to
  `~/Library/Application Support/Typeless-Rev/Models/polish` (override with
  `TYPELESS_REV_MODEL_DIR`). It drops the 297 vision-tower tensors (0.67 GB), so 3.03 GB becomes
  2.37 GB; the language tensors are copied byte for byte. It needs about 6 GB free while it works,
  and the model only appears once it is complete.
- **Memory.** The model loads when you press the key, so it is ready at release, and is released
  after 5 idle minutes. Expect roughly 1.1 to 1.7 GB while loaded.
- **Off switch.** `defaults write com.nyaaorick.inputmethod.TypelessRev polishEnabled -bool false`.

## Logs

```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.nyaaorick.inputmethod.TypelessRev"'
```

Rime's own logs are in `~/Library/Application Support/Typeless-Rev/Rime/log`; set
`TYPELESS_REV_LOG_LEVEL=0` for verbose output.
