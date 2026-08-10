// InputSourceRegistration.swift — enables Nagi's own Text Input Source
// (bundle `com.nvleo.inputmethod.nagi` and its `Hiragana` mode) at
// startup, via Carbon.HIToolbox's TextInputSources.h. The goal: a
// freshly dropped-in Nagi.app becomes selectable in System Settings >
// Keyboard > Input Sources without the full reboot macOS otherwise
// requires (see app/README.md's "Getting registered: three silent
// requirements", #3).
//
// Same self-registration pattern as ConverterServiceRegistration.swift
// (#30) applied to the other half of "no external installer needed":
// that file registers the NagiConverter LaunchAgent via SMAppService;
// this one registers the input source itself.
//
// CONFIRMED ON REAL HARDWARE (#30 follow-up) — what the "reboot
// required" folklore actually is: `imklaunchagent` and
// `TextInputMenuAgent` (the two per-user agents backing System
// Settings' Input Sources list and the menu bar Input menu) load their
// view of the Text Input Source registry once, at their own process
// startup, and never rescan it afterwards. TISRegisterInputSource /
// TISEnableInputSource genuinely do write through to the underlying
// registry (verified: a second call from a *fresh* process reads the
// change back correctly) — the two agents just don't know about it
// until *they* restart, which normally only happens at login (hence
// "reboot fixes it"). `launchctl kickstart -k` on either is blocked by
// SIP ("Operation not permitted while System Integrity Protection is
// engaged"), which is almost certainly why this repo's earlier
// restart attempt (docs/architecture.md, "not by restarting
// imklaunchagent/TextInputMenuAgent by hand") concluded restarting
// doesn't help — that attempt never actually restarted anything. A
// plain `kill -HUP` (no `launchctl` involved) *does* terminate them,
// and launchd immediately respawns both as on-demand agents — at which
// point they pick up the change. Full working sequence, in order:
//   1. TISRegisterInputSource(bundleURL) — its header doc literally
//      describes this exact "installer notifies the system about a
//      new bundle" scenario.
//   2. TISEnableInputSource, parent bundle first, then the Hiragana
//      mode — TextInputSources.h's kTISPropertyInputSourceIsEnableCapable
//      discussion states a mode can only flip disabled -> enabled while
//      its parent is already enabled.
//   3. `killall -HUP imklaunchagent TextInputMenuAgent` to force both
//      agents to reload. Only reached if step 2 actually changed
//      something — never on steady-state launches where Nagi is
//      already enabled, since that would restart both agents (a
//      user-visible, if brief, hiccup in text input switching) on
//      every single launch for no reason.
//
// None of this is documented Apple behavior — `kill -HUP` forcing a
// respawn is an artifact of these agents being ordinary on-demand
// LaunchAgents, not a designed reload mechanism. If a future macOS
// version changes that, this degrades back to "works after reboot"
// (unchanged prior behavior), not a crash — enable() below is already
// unconditionally best-effort.

import Carbon
import Foundation
import os

enum InputSourceRegistration {
    private static let logger = Logger(
        subsystem: "com.nvleo.inputmethod.nagi", category: "InputSourceRegistration")

    // Must match Info.plist's CFBundleIdentifier and its
    // ComponentInputModeDict > tsInputModeListKey > TISInputSourceID
    // exactly.
    private static let bundleID = "com.nvleo.inputmethod.nagi"
    private static let hiraganaModeID = "com.nvleo.inputmethod.nagi.Hiragana"

    // The two per-user agents that cache the Text Input Source registry
    // at their own startup only — see the file header for why
    // restarting them is what stands in for "the user rebooted".
    private static let agentsToRestart = ["imklaunchagent", "TextInputMenuAgent"]

    /// Best-effort — never blocks startup on failure. Safe to call on
    /// every launch: if Nagi is already fully enabled, this is a single
    /// property read per source and nothing else happens.
    static func registerIfNeeded() {
        let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        if status != noErr {
            logger.error("TISRegisterInputSource failed with OSStatus \(status)")
        }

        let parentChanged = enable(
            propertyKey: kTISPropertyBundleID, value: bundleID, label: "Nagi (parent input method)")
        let modeChanged = enable(
            propertyKey: kTISPropertyInputSourceID, value: hiraganaModeID,
            label: "Nagi Hiragana (input mode)")

        // Only restart imklaunchagent/TextInputMenuAgent when something
        // actually just transitioned disabled -> enabled — this is the
        // one-time "just installed/updated" path, not every launch.
        if parentChanged || modeChanged {
            restartTextInputAgents()
        }
    }

    /// Returns whether this call actually flipped the source from
    /// disabled to enabled (false for "already enabled", "not found",
    /// or "TISEnableInputSource failed").
    @discardableResult
    private static func enable(propertyKey: CFString, value: String, label: String) -> Bool {
        let filter = [propertyKey: value as CFString] as CFDictionary
        guard
            let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
            let source = list.first
        else {
            logger.notice(
                "\(label, privacy: .public) not found via TISCreateInputSourceList — not yet known to the Text Input Source registry"
            )
            return false
        }

        if isEnabled(source) {
            return false
        }

        let status = TISEnableInputSource(source)
        if status == noErr {
            logger.info("Enabled Text Input Source: \(label, privacy: .public)")
            return true
        } else {
            logger.error("TISEnableInputSource failed for \(label, privacy: .public) with OSStatus \(status)")
            return false
        }
    }

    private static func isEnabled(_ source: TISInputSource) -> Bool {
        guard let rawPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(rawPtr).takeUnretainedValue())
    }

    /// `launchctl kickstart -k` on either agent is blocked by SIP; a
    /// plain signal isn't a launchctl service-management call, so it
    /// goes through, and launchd respawns both as on-demand agents.
    private static func restartTextInputAgents() {
        for name in agentsToRestart {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["-HUP", name]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    logger.info("Restarted \(name, privacy: .public) to pick up the new Text Input Source")
                } else {
                    // Likely just "no matching process" (killall exits
                    // 1) — not fatal, the agent will pick up the change
                    // whenever it next starts regardless.
                    logger.notice(
                        "killall -HUP \(name, privacy: .public) exited \(process.terminationStatus)")
                }
            } catch {
                logger.error(
                    "Failed to restart \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
