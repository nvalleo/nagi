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
app.run()
