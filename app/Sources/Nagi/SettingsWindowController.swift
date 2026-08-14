// SettingsWindowController — #39: process-wide singleton owning the
// settings window itself.
//
// Unlike CandidateWindowController's NSPanel, this is a plain NSWindow —
// a normal document-style window with a title bar and close button is
// fine here, since none of the candidate window's "must not steal
// focus" constraints apply.
//
// Nagi is LSUIElement (no Dock icon) and never comes to the foreground
// on its own until called from the IMKit menu item
// (NagiInputController.menu()) — same as FirstRunPrompt.swift, this
// needs NSApp.activate(ignoringOtherApps:) right before showing.

import Cocoa
import SwiftUI

final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nagi の設定"
        // Pairs with SettingsRootView's own `.frame(minWidth:minHeight:
        // ...)` — keeps SwiftUI's layout from breaking if the window
        // itself gets dragged smaller first.
        window.minSize = NSSize(width: 480, height: 420)
        window.contentView = NSHostingView(rootView: SettingsRootView())
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    /// Just brings the same window to front on every call —
    /// NagiInputController can be instantiated multiple times, one per
    /// IMKit client connection (docs/architecture.md), but the settings
    /// window only needs to exist once per process.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
