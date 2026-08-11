// nagi-tis-disable.swift — removes Nagi's entries from
// AppleEnabledInputSources (the com.apple.HIToolbox preference System
// Settings' 入力ソース list, the menu bar Input menu and
// TextInputMenuAgent all actually render from), then restarts
// imklaunchagent/TextInputMenuAgent so they pick up the change
// immediately. See app/Sources/Nagi/InputSourceRegistration.swift for
// the full story of how this was found and why the agent restart is
// necessary (both agents cache the registry once, at their own process
// startup, and never rescan).
//
// Bundled into Uninstall Nagi.app's Contents/Resources/ by
// scripts/build-uninstaller.sh and invoked from
// scripts/dmg/Uninstall Nagi.applescript, since AppleScript can't call
// CoreFoundation preference APIs directly.
//
// Mirrors InputSourceRegistration.swift's addToEnabledInputSources(),
// in reverse: TISDisableInputSource (the previous approach here) is
// confirmed inert for third-party input methods — it returns noErr and
// writes nothing, same as TISEnableInputSource on the enable side. The
// working mechanism is a direct CFPreferences write to
// AppleEnabledInputSources.
//
// Called AFTER Nagi.app has already been deleted — that's fine, this
// only needs the bundle ID string, not the bundle itself.

import Carbon
import Foundation

let bundleID = "com.nvleo.inputmethod.nagi"
let hiToolboxDomain = "com.apple.HIToolbox" as CFString
let enabledSourcesKey = "AppleEnabledInputSources" as CFString
let entryBundleID = "Bundle ID"

func removeFromEnabledInputSources() -> Bool {
    guard
        let sources = CFPreferencesCopyValue(
            enabledSourcesKey, hiToolboxDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [[String: Any]]
    else {
        return false
    }

    let filtered = sources.filter { ($0[entryBundleID] as? String) != bundleID }
    guard filtered.count != sources.count else {
        return false  // nothing to remove
    }

    CFPreferencesSetValue(
        enabledSourcesKey, filtered as CFArray, hiToolboxDomain, kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost)
    return CFPreferencesSynchronize(hiToolboxDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
}

if removeFromEnabledInputSources() {
    for name in ["imklaunchagent", "TextInputMenuAgent"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-HUP", name]
        // waitUntilExit() on a Process that never launched is undefined
        // behavior — only call it once run() has actually succeeded.
        if (try? process.run()) != nil {
            process.waitUntilExit()
        }
    }
}
