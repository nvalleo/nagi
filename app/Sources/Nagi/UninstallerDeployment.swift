// UninstallerDeployment.swift — copies the bundled "Uninstall Nagi.app"
// helper out to /Applications/ on first launch (#33 follow-up).
//
// Without this, getting Uninstall Nagi.app somewhere permanent meant a
// second explicit drag in the .dmg (Nagi.app → Input Methods, Uninstall
// Nagi.app → Applications) — no ordinary Mac app asks for two drags to
// two different folders, and it's an easy way to end up with Uninstall
// Nagi.app dragged into Input Methods by mistake instead (it doesn't
// belong there; it's a plain AppleScript app, not an IMKit bundle).
// Nagi.app now embeds a prebuilt copy of it in its own
// Contents/Resources/ (see scripts/build-app.sh) and deploys it here —
// one drag, same as any other Mac app.
//
// Writing to /Applications/ doesn't need admin privileges the way
// /Library/Input Methods/ does: it's root:admin/0775, and the logged-in
// user is normally in the admin group, so a plain FileManager copy
// succeeds without a password prompt (confirmed — this is also why
// Finder never prompts when *you* drag an app into Applications).
//
// The .dmg still carries its own top-level copy of Uninstall Nagi.app
// too, as a fallback for the case Nagi.app never got to run at all
// (e.g. Gatekeeper blocked it and the user gave up before getting past
// that) — see scripts/build-dmg.sh.

import Foundation
import os

enum UninstallerDeployment {
    private static let logger = Logger(
        subsystem: "com.nvleo.inputmethod.nagi", category: "UninstallerDeployment")

    private static let destinationURL = URL(fileURLWithPath: "/Applications/Uninstall Nagi.app")

    /// Best-effort — never blocks startup on failure. Safe to call on
    /// every launch: a no-op once the destination already exists.
    static func deployIfNeeded() {
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }

        let sourceURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Resources/Uninstall Nagi.app")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            // Not fatal — the .dmg's own top-level copy (or
            // uninstall-ime.sh, for anyone who built from source) is
            // still there as a fallback.
            logger.error("Bundled Uninstall Nagi.app not found at \(sourceURL.path, privacy: .public)")
            return
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            logger.info("Deployed Uninstall Nagi.app to /Applications")
        } catch {
            logger.error(
                "Failed to deploy Uninstall Nagi.app to /Applications: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
