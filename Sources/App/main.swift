import Cocoa

// Developer entry points; the system launches the input method with no arguments.
//   --selftest          exercise the embedded librime end to end, then exit
//   --selftest-speech   transcribe synthesized speech through the voice pipeline, then exit
//   --selftest-polish   run the local polish model on sample transcripts, then exit
//   --selftest-ui       build the menu bar menu and HUD, check them, then exit
//   --install-model     download and install the polish model, then exit
//   --register          register and enable this bundle as an input source, then exit
//   --disable-legacy    turn off input sources an older build registered, then exit
if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }
if CommandLine.arguments.contains("--selftest-speech") { exit(SpeechSelfTest.run()) }
if CommandLine.arguments.contains("--selftest-polish") { exit(PolishSelfTest.run()) }
if CommandLine.arguments.contains("--selftest-ui") { exit(UISelfTest.run()) }
if CommandLine.arguments.contains("--install-model") { exit(InstallModelCommand.run()) }
if CommandLine.arguments.contains("--register") { exit(InputSourceRegistration.register()) }
if CommandLine.arguments.contains("--disable-legacy") { exit(InputSourceRegistration.disableLegacy()) }

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
