// nagi-tis-disable.swift — best-effort TISDisableInputSource on both
// com.nvleo.inputmethod.nagi and its Hiragana mode, followed by
// restarting imklaunchagent/TextInputMenuAgent so they pick up the
// change immediately. See app/Sources/Nagi/InputSourceRegistration.swift
// for why that restart is necessary (both agents cache the Text Input
// Source registry once, at their own process startup, and TIS API calls
// don't take visible effect until they restart).
//
// Bundled into Uninstall Nagi.app's Contents/Resources/ by
// scripts/build-uninstaller.sh and invoked from
// scripts/dmg/Uninstall Nagi.applescript, since AppleScript can't call
// Carbon APIs directly.
//
// Called AFTER Nagi.app has already been deleted — unlike
// InputSourceRegistration.swift's enable() path (proven working, #30
// follow-up), this disable-on-uninstall path is UNVERIFIED on real
// hardware as of writing: whether TISDisableInputSource's write
// survives the subsequent agent restart once the backing bundle is
// already gone is untested. Strictly best-effort either way — if it
// doesn't help, System Settings still shows the stale "ひらがな (Nagi)"
// entry exactly as before this helper existed, and the documented
// "select it, click −" fallback (scripts/uninstall-ime.sh, both
// READMEs) is unchanged.

import Carbon
import Foundation

func disable(propertyKey: CFString, value: String) {
    let filter = [propertyKey: value as CFString] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    else { return }
    for source in list {
        _ = TISDisableInputSource(source)
    }
}

disable(propertyKey: kTISPropertyBundleID, value: "com.nvleo.inputmethod.nagi")
disable(propertyKey: kTISPropertyInputSourceID, value: "com.nvleo.inputmethod.nagi.Hiragana")

for name in ["imklaunchagent", "TextInputMenuAgent"] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["-HUP", name]
    try? process.run()
    process.waitUntilExit()
}
