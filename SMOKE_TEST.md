# Smoke test

What the self-tests cannot cover: a real text field, the keyboard, and the microphone. Run this
after `scripts/install.sh` and tick it off per app. Everything here is also listed as "not yet
verified" in [roadmap.md](roadmap.md); when a row passes, record it there.

## Before you start

1. `scripts/setup-signing.sh` once, so the microphone grant survives rebuilds.
2. `scripts/install.sh`, then pick **Typeless-Rev** under Input Sources > English.
3. System Settings > Keyboard > Input Sources: turn **off** "Use the Caps Lock key to switch to and
   from ABC", or macOS takes the 中/英 key first.
4. From the menu bar icon: **Microphone** (allow it), **Speech Data** (download), and, if you want
   polishing, **Polish Model** (3 GB).
5. Watch the log while you test:
   `log stream --info --predicate 'subsystem == "com.nyaaorick.inputmethod.TypelessRev"'`

## Per app

Apps: Notes, Safari, Chrome, VS Code, Slack, Terminal. For each one:

| # | Check | Expect |
| --- | --- | --- |
| 1 | Click into a text field and type English, hold a key to repeat it, try Option-letter and a Command shortcut | Exactly the native keyboard; no marked text, no popup |
| 2 | Tap Caps Lock (中/英) | "Switch to Chinese mode" for about a second; the Caps Lock light does not come on |
| 3 | Type `nihao`, then Space | Marked `ni hao` and a candidate panel; Space commits `你好` |
| 4 | Type `nihao,` | `你好,` with an ASCII comma, never `，` |
| 5 | Type `nihao` (blue box showing) and tap Caps Lock | "Switch to English mode"; `nihao` is left as letters |
| 6 | Switch to Chinese, click into another field or app, come back | Back in English; no stray marked text in either field |
| 7 | Hold Right Option, say a sentence, release | Words appear as marked text while you speak; the final text is committed on release |
| 8 | Same, but say it in Chinese, then in English, in either mode | The right language each time (Speech Language on Auto-Detect) |
| 9 | Hold Right Option, then press a letter before releasing | The dictation is cancelled, nothing is written |
| 10 | Dictate, then switch app before releasing | Nothing is written into the wrong field |
| 11 | With the polish model installed: dictate "um so basically I think we should uh ship it" | The raw text stays on screen, then is replaced by a cleaned version within about 3 s; typing a key meanwhile keeps the raw text; Shift on release skips polishing |
| 14 | In English, hold Caps Lock for about a second, release, type letters | "Caps Lock on", capitals come out, the menu bar icon shows the Caps Lock symbol, the key light stays off |
| 15 | With Caps Lock on, hold Shift and type | Lower case |
| 16 | With Caps Lock on, tap | "Caps Lock off", lower case English; tap again: Chinese |
| 17 | In Chinese with `nihao` in the blue box, hold Caps Lock | The letters stay, English with Caps Lock on |
| 18 | In Chinese, type `ni`, hold Shift and type `H`, then release Shift and type `nihao` | `niH` is left as letters, then pinyin works again |
| 19 | Tap and hold the key 10 times in a row, in any mix | Only the matching change each time; no tip or switch appears by itself |
| 12 | With a non-US keyboard layout (Dvorak, AZERTY) selected: type English, switch to Chinese and back | English keeps your layout after the round trip |
| 13 | Marked-text updates while dictating a long sentence | No flicker or lag at about 10 updates per second |

## Password fields (must be off)

In Safari or Chrome, focus a password field (and, if you use it, Terminal with Secure Keyboard
Entry on). Then:

| # | Check | Expect |
| --- | --- | --- |
| P1 | Hold Right Option | "Voice is off in password fields."; nothing is recorded (no red icon, no HUD) |
| P2 | Tap Caps Lock, then type | No mode switch, no marked text, no candidate panel; keys type as-is |
| P3 | Leave the field and hold Right Option | Voice works again |

## Menu bar

| # | Check | Expect |
| --- | --- | --- |
| M1 | Open the menu | Shows Ready, the permission lines, the model state; icon turns into a red microphone while you speak and sparkles while polishing |
| M2 | **Microphone** line | "Not Asked Yet — Allow…" opens the macOS prompt; after "Off", "Open Privacy Settings…" opens the right pane; "Allowed" afterwards |
| M3 | Rebuild and reinstall, then dictate | No new microphone prompt (this is what the stable signature is for) |
| M4 | Idle | Activity Monitor shows the process near 0% CPU; about 13 MB after a fresh start, about 400 MB after the polish model has been used and unloaded (5 minutes idle) |
