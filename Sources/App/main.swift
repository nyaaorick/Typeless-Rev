import Cocoa

// Developer entry points; the system launches the input method with no arguments.
//   --selftest          exercise the embedded librime end to end, then exit
//   --selftest-speech   transcribe synthesized speech through the voice pipeline, then exit
//   --selftest-polish   run the local polish model on sample transcripts, then exit
//   --selftest-ui       build the menu bar menu and HUD, check them, then exit
//   --selftest-whisper  install (if needed) and load the Whisper model, transcribe synthesized speech, then exit
//   --transcribe-file PATH [--language CODE]  print Whisper's text for a recording, then exit
//   --polish-text TEXT  polish TEXT with the local model, print the reply and timing, then exit
//                       (after --polish-before CONTEXT: as if CONTEXT were already before the cursor;
//                       after --polish-app BUNDLE-ID: in that app's style)
//   --install-model     download and install the polish model, then exit
//   --polish-model 4b|9b  with the polish commands above: use that model for this run only
//   --register          register and enable this bundle as an input source, then exit
//   --disable-legacy    turn off input sources an older build registered, then exit
if let i = CommandLine.arguments.firstIndex(of: "--polish-model") {
    PolishModel.override = PolishModel(rawValue: CommandLine.arguments[i + 1])
}
if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }
if CommandLine.arguments.contains("--selftest-speech") { exit(SpeechSelfTest.run()) }
if CommandLine.arguments.contains("--selftest-polish") { exit(PolishSelfTest.run()) }
if CommandLine.arguments.contains("--selftest-ui") { exit(UISelfTest.run()) }
if CommandLine.arguments.contains("--selftest-whisper") { exit(WhisperSelfTest.run()) }
if let i = CommandLine.arguments.firstIndex(of: "--transcribe-file") {
    let language = CommandLine.arguments.firstIndex(of: "--language").map { CommandLine.arguments[$0 + 1] }
    exit(WhisperSelfTest.transcribeFile(CommandLine.arguments[i + 1], language: language))
}
if let i = CommandLine.arguments.firstIndex(of: "--polish-text") {
    let before = CommandLine.arguments.firstIndex(of: "--polish-before").map { CommandLine.arguments[$0 + 1] }
    let app = CommandLine.arguments.firstIndex(of: "--polish-app").map { CommandLine.arguments[$0 + 1] }
    exit(PolishSelfTest.polishText(
        CommandLine.arguments.dropFirst(i + 1).joined(separator: " "), before: before, style: AppStyle.forApp(app)))
}
if CommandLine.arguments.contains("--install-model") { exit(InstallModelCommand.run()) }
if CommandLine.arguments.contains("--register") { exit(InputSourceRegistration.register()) }
if CommandLine.arguments.contains("--disable-legacy") { exit(InputSourceRegistration.disableLegacy()) }

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
