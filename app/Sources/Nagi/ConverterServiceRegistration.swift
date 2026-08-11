// ConverterServiceRegistration.swift — registers the bundled
// NagiConverter as a per-user LaunchAgent via ServiceManagement's
// SMAppService, so Nagi.app is fully self-contained: no install script
// or installer package has to hand-write a LaunchAgent plist into
// ~/Library/LaunchAgents/ or shell out to `launchctl bootstrap` on our
// behalf.
//
// Replaces two earlier mechanisms that both did this externally instead
// (#30): scripts/install-ime.sh used to write the plist + bootstrap it
// directly, and a since-abandoned .pkg postinstall script (scripts/pkg/)
// did the same thing from an installer. Both worked, but having the app
// register its own background helper is the pattern
// Contents/Library/LaunchAgents/ + SMAppService exists for, and it's
// what makes a plain drag-and-drop DMG (no custom installer — see
// app/README.md's "Prebuilt download" section for why that's the goal)
// sufficient on its own.
//
// The actual plist lives inside the app bundle at
// Resources/LaunchAgents/com.nvleo.inputmethod.nagi.Converter.plist
// (copied to Contents/Library/LaunchAgents/ by scripts/build-app.sh —
// the fixed location SMAppService requires). Its BundleProgram key is
// resolved relative to wherever this bundle currently lives, so
// registration works identically whether Nagi.app ends up at
// ~/Library/Input Methods/ or /Library/Input Methods/.

import Foundation
import ServiceManagement
import os

enum ConverterServiceRegistration {
    private static let logger = Logger(
        subsystem: "com.nvleo.inputmethod.nagi", category: "ConverterServiceRegistration")

    private static let service = SMAppService.agent(
        plistName: "com.nvleo.inputmethod.nagi.Converter.plist")

    /// Best-effort — never blocks startup on failure. Safe to call on
    /// every launch, not just a detected "first run": re-registering an
    /// already-`.enabled` service is a documented no-op.
    static func registerIfNeeded() {
        switch service.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            do {
                try service.register()
                logger.info("Registered NagiConverter LaunchAgent")
                // #32: this used to also fire a one-shot
                // UNUserNotificationCenter notification here as
                // "registration succeeded" feedback (Nagi is
                // LSUIElement — no Dock icon, no window — so a manual
                // "double-click Nagi.app to register" otherwise looks
                // like nothing happened). Removed: confirmed failing
                // end-to-end with "Notifications are not allowed for
                // this application" regardless (see FirstRunPrompt.swift,
                // the reliable NSAlert-based replacement that fully
                // subsumed this), and merely *requesting* that
                // authorization was enough to leave a permanent
                // Nagi/NagiConverter entry in System Settings >
                // Notifications even after uninstalling — with no
                // public API to remove it again from outside System
                // Settings itself.
            } catch {
                // Not fatal — Nagi still works for anything that doesn't
                // need conversion (e.g. this run is just to trigger
                // registration, per app/README.md's install steps), and
                // scripts/install-ime.sh's manual fallback still exists
                // for whoever hits this.
                logger.error(
                    "Failed to register NagiConverter LaunchAgent: \(error.localizedDescription, privacy: .public)"
                )
            }
        case .requiresApproval:
            // The person previously disabled it via System Settings >
            // General > Login Items — respect that instead of
            // re-prompting every launch.
            logger.notice(
                "NagiConverter LaunchAgent requires approval in System Settings > General > Login Items"
            )
        @unknown default:
            logger.notice("NagiConverter LaunchAgent: unknown SMAppService status")
        }
    }
}
