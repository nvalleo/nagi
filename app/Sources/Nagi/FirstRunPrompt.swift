// FirstRunPrompt.swift — a guaranteed-to-render alternative to
// ConverterServiceRegistration's notification for telling the user
// "log out and back in once" after the very first launch.
//
// Why this exists alongside that notification rather than replacing it:
// `UNUserNotificationCenter` needs the user to grant notification
// permission, and that authorization request is unreliable for an
// `LSUIElement` app that never becomes frontmost — confirmed failing
// end-to-end with "Notifications are not allowed for this application"
// (see ConverterServiceRegistration.swift's doc comment). An `NSAlert`
// needs no permission at all; the only trick is getting it to actually
// appear in front of the user despite Nagi having no Dock icon and
// never normally activating — `NSApp.activate(ignoringOtherApps:)`
// below handles that.
//
// One-shot via a plain `UserDefaults` flag rather than the
// `SMAppService`/`AppleEnabledInputSources` state
// ConverterServiceRegistration's notification keys off — deliberately
// independent of those, since this Mac's dev/test history already
// demonstrated the failure mode of tying a "have I ever shown this"
// check to state that can already be `.enabled`/present from an
// earlier install (the notification silently never fires again in that
// case). A dedicated preference key doesn't have that problem: it only
// tracks "has *this* alert been shown," nothing else.
//
// The "log out now" button runs a real, cancellable log out (the same
// AppleEvent the menu bar's Apple menu "Log Out" item itself sends)
// rather than forcing one — matching the existing "offers but doesn't
// force a restart" pattern in the GUI uninstaller
// (scripts/dmg/Uninstall Nagi.applescript) and app/README.md's
// uninstall section.

import AppKit
import Foundation
import os

enum FirstRunPrompt {
    private static let logger = Logger(
        subsystem: "com.nvleo.inputmethod.nagi", category: "FirstRunPrompt")

    private static let shownKey = "FirstRunLogoutPromptShown"

    /// Best-effort, main-thread only (call from the same
    /// `DispatchQueue.main.async` block `main.swift` already uses for
    /// the other self-registration calls). Safe to call on every
    /// launch — shows nothing after the first time.
    static func showIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)

        // Nagi is LSUIElement (no Dock icon, no app menu bar) and never
        // otherwise activates — without this, the alert can render
        // behind whatever the user is currently working in, or not be
        // brought forward at all.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Nagi のセットアップが完了しました"
        alert.informativeText =
            "入力ソースとして使えるようになるには、一度ログアウトしてログインし直す必要があります。"
        alert.addButton(withTitle: "今すぐログアウト")
        alert.addButton(withTitle: "あとで")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            logOutNow()
        }
    }

    /// Sends the same AppleEvent the Apple menu's own "Log Out" item sends —
    /// macOS shows its normal confirmation (with the usual grace period
    /// to cancel or let open documents save), it isn't an instant,
    /// unconfirmable logout. Best-effort: if this fails, the user still
    /// has the docs' manual instructions.
    private static func logOutNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to log out"]
        do {
            try process.run()
        } catch {
            logger.error("Failed to trigger log out: \(error.localizedDescription, privacy: .public)")
        }
    }
}
