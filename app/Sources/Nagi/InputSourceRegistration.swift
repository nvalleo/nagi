// InputSourceRegistration.swift — makes Nagi's Text Input Source
// (bundle `com.nvleo.inputmethod.nagi` and its `Hiragana` mode) show up
// in System Settings > キーボード > 入力ソース after the next login,
// without the user having to Edit... > "+" > find Nagi > Add it by
// hand. See the "Net effect" paragraph below for what this does and
// doesn't get Nagi as of the *current* login session.
//
// Same self-registration pattern as ConverterServiceRegistration.swift
// (#30) applied to the other half of "no external installer needed":
// that file registers the NagiConverter LaunchAgent via SMAppService;
// this one registers the input source itself.
//
// REVERSED ON REAL HARDWARE (#33 follow-up) — this file used to also
// `killall -HUP imklaunchagent TextInputMenuAgent` after writing the
// preference below, believing that made the menu bar Input menu and
// conversion pick Nagi up with **no logout needed at all**. Extensive
// live reverse-engineering (disassembling the relevant HIToolbox
// private functions, testing against Kotoeri/AinuIM/plain keyboard
// layouts, and testing `TISEnableInputSource`/`TISDisableInputSource`
// both with and without the user consent dialogue they turn out to
// trigger) disproved that:
//
//   * The menu bar Input menu is not built from
//     `AppleEnabledInputSources` freshly per process. It's built from
//     `_TSMCopySelectableInputSourcesInUIOrder()`, which reads a
//     **login-session-scoped pasteboard** that HIToolbox materializes
//     via `UpdatePBInputSourcesInUIOrder` ("PB" = PasteBoard) — a
//     rebuild that only happens at login. Writing the preference below
//     changes what the *next* rebuild will produce; it does not trigger
//     one. `killall -HUP` on either agent does restart it (confirmed via
//     `launchctl print`), but neither agent is what's stale, so nothing
//     changes — it was pure cost (a brief hiccup in text input
//     switching) for zero benefit. Removed.
//   * `TISEnableInputSource()`/`TISDisableInputSource()` looked like a
//     more legitimate way to force that rebuild, and do trigger a
//     genuine one-time user consent dialogue ("'Nagi' を有効にします
//     か？") the first time they're called for a given source — but
//     calling them on Nagi's own bundle or its Hiragana mode is a
//     silent no-op both before *and* after granting that consent
//     (`OSStatus noErr`, `AppleEnabledInputSources` unchanged, menu
//     unchanged — verified repeatedly). The only way found to actually
//     force the rebuild is enabling/disabling some *unrelated*,
//     already-installed input source (e.g. a keyboard layout) — which
//     also has the side effect of pruning Nagi's own preference entry
//     as "orphaned" if it has no matching `Input Mode` entry yet. Not
//     something to run against a user's real, unrelated input sources
//     from inside Nagi's own install path.
//   * The NagiConverter LaunchAgent (`ConverterServiceRegistration.swift`)
//     has the same shape of limitation: `SMAppService.register()`
//     reports `.enabled` (approved) immediately, but the job is not
//     actually loaded into launchd for the *current* login session
//     until the next login — nothing in this process can force that
//     either.
//
// Net effect, and not a Nagi-specific bug: Google 日本語入力, macSKK and
// other third-party macOS IMEs all document the same thing — install,
// launch once, then log out and back in once before it shows up
// anywhere (System Settings included) or converts. See app/README.md's
// install steps, and issue #34 for tracking whether logout can be
// eliminated too (not just the full reboot this file already killed).
// What this file still buys over doing nothing:
// `TISRegisterInputSource` below gets Nagi into the installed catalogue
// (required either way), and writing `AppleEnabledInputSources`
// directly means that once the next login's rebuild happens, Nagi comes
// up already configured — System Settings, the menu bar and conversion
// together, no manual "+" needed at any point.

import Carbon
import Foundation
import os

enum InputSourceRegistration {
    private static let logger = Logger(
        subsystem: "com.nvleo.inputmethod.nagi", category: "InputSourceRegistration")

    // Must match Info.plist's CFBundleIdentifier exactly. The Hiragana
    // mode deliberately isn't named here — HIToolbox expands the parent
    // bundle entry into its visible modes on its own at the next login;
    // adding a second, explicit "Input Mode" entry for it (the shape
    // Kotoeri stores) is actively wrong: HIToolbox then registers the
    // mode a second time instead of matching it to the one it already
    // has, and Nagi shows up twice in the input source list.
    private static let bundleID = "com.nvleo.inputmethod.nagi"

    // The `com.apple.HIToolbox` preference that System Settings, the
    // menu bar Input menu and TextInputMenuAgent all render from.
    private static let hiToolboxDomain = "com.apple.HIToolbox" as CFString
    private static let enabledSourcesKey = "AppleEnabledInputSources" as CFString

    // Entry field names and values, spelled exactly as macOS writes
    // them — including the spaces.
    private static let entryBundleID = "Bundle ID"
    private static let entryKind = "InputSourceKind"
    private static let kindKeyboardInputMethod = "Keyboard Input Method"

    /// Best-effort — never blocks startup on failure. Safe to call on
    /// every launch: once Nagi is present in `AppleEnabledInputSources`
    /// this is a single preference read and nothing else happens.
    static func registerIfNeeded() {
        let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        if status != noErr {
            logger.error("TISRegisterInputSource failed with OSStatus \(status)")
        }

        _ = addToEnabledInputSources()
    }

    /// Appends Nagi's parent-bundle entry to `AppleEnabledInputSources`
    /// if it isn't already there, so the next login's rebuild has
    /// correct data to work from (see file header — nothing reads this
    /// preference directly in the *current* session). Returns whether the
    /// preference was actually modified; the caller doesn't currently
    /// need that (no follow-up action left to gate on it) but it's kept
    /// for tests/future use rather than made a bare `Void` return.
    private static func addToEnabledInputSources() -> Bool {
        let existing =
            CFPreferencesCopyValue(
                enabledSourcesKey, hiToolboxDomain, kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost) as? [[String: Any]]

        guard var sources = existing else {
            // Never expected: every account has this key from first
            // login. Bailing out is safer than writing a fresh array
            // that would drop the user's real input sources.
            logger.error(
                "Could not read AppleEnabledInputSources — leaving it untouched rather than risk clobbering the user's input sources"
            )
            return false
        }

        let alreadyPresent = sources.contains { ($0[entryBundleID] as? String) == bundleID }
        if alreadyPresent {
            return false
        }

        sources.append([
            entryBundleID: bundleID,
            entryKind: kindKeyboardInputMethod,
        ])

        CFPreferencesSetValue(
            enabledSourcesKey, sources as CFArray, hiToolboxDomain, kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost)

        guard
            CFPreferencesSynchronize(
                hiToolboxDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        else {
            logger.error("CFPreferencesSynchronize failed for \(hiToolboxDomain as String, privacy: .public)")
            return false
        }

        logger.info("Added Nagi to AppleEnabledInputSources")
        return true
    }
}
