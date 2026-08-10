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
import UserNotifications
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
                // Nagi is LSUIElement — no Dock icon, no window, so a
                // manual "double-click Nagi.app to register" (the
                // install docs' recommended smoke test) otherwise looks
                // like nothing happened at all. A one-shot notification,
                // only on this notRegistered -> registered transition
                // (never fires again once .enabled), is the only
                // feedback available without adding real UI to what's
                // supposed to be a headless host process.
                notifyFirstRegistration()
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

    /// Best-effort, silent on any failure (denied permission, no
    /// notification center available, ...) — this is a courtesy, not
    /// something registration correctness depends on.
    private static func notifyFirstRegistration() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                logger.error(
                    "Notification authorization request failed: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            guard granted else {
                logger.notice("Notification authorization denied — registration still succeeded")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Nagi"
            content.body =
                "セットアップが完了しました。再起動後、システム設定 > キーボード > 入力ソース から Nagi を追加してください。"
            let request = UNNotificationRequest(
                identifier: "com.nvleo.inputmethod.nagi.converter-registered",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    logger.error(
                        "Failed to post registration notification: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}
