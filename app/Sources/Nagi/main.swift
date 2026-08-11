// Nagi — IMKit host process entry point.
//
// Mirrors the bootstrap in google/mozc's mac/main.mm: read the connection
// name IMKit expects from Info.plist, stand up an IMKServer under it, and
// run as a background (LSUIElement) app. No dock icon, no windows — the
// only UI is whatever the target application's text field shows via
// NagiInputController.

import Cocoa
import InputMethodKit

let bundle = Bundle.main
let connectionName = (bundle.infoDictionary?["InputMethodConnectionName"] as? String) ?? "Nagi_1_Connection"

// Must be retained for the process lifetime — IMKServer doesn't hold a
// strong reference to itself, and IMKit dispatches to
// NagiInputController through it.
let server = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// #30: self-register the bundled NagiConverter as a LaunchAgent instead
// of relying on an external install script/installer to do it — see
// ConverterServiceRegistration.swift. Deferred via `DispatchQueue.main.async`
// (runs once `app.run()`'s run loop is actually spinning) rather than
// called inline above — calling it before NSApplication had a running
// run loop was an early theory for why ConverterServiceRegistration's
// UNUserNotificationCenter authorization request was unreliable.
// SMAppService's own `.register()` doesn't need this, and moving the
// notification call here didn't end up fixing it either — it still
// fails end-to-end with "Notifications are not allowed for this
// application" (see that file's doc comment) — but there's no harm
// running everything below this late, and FirstRunPrompt below doesn't
// depend on notification permission at all.
DispatchQueue.main.async {
    ConverterServiceRegistration.registerIfNeeded()
    // Companion self-registration for the Text Input Source itself (as
    // opposed to the NagiConverter LaunchAgent above) — see
    // InputSourceRegistration.swift for why and its open questions.
    InputSourceRegistration.registerIfNeeded()
    // #33: deploy the bundled uninstaller to /Applications/ so it has a
    // permanent home without a second manual drag in the .dmg — see
    // UninstallerDeployment.swift.
    UninstallerDeployment.deployIfNeeded()
    // The reliable (no permission needed) "log out and back in" prompt
    // — see FirstRunPrompt.swift for why this exists alongside
    // ConverterServiceRegistration's notification instead of replacing
    // it.
    FirstRunPrompt.showIfNeeded()
}

app.run()
