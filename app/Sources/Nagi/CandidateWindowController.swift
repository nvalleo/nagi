// CandidateWindowController — owns the candidate window itself.
//
// Not IMKCandidates (Apple's built-in candidate window): its styling is
// fixed and doesn't give the layout freedom the product wants — see
// docs/architecture.md, "The candidate window". Instead this is a plain
// borderless NSPanel hosting a SwiftUI tree, matching the "M2" section of
// docs/roadmap.md.

import Cocoa
import NagiMozcProto
import SwiftUI

// Not @MainActor: IMKit calls NagiInputController's overrides
// synchronously on the main thread (docs/architecture.md, "Threading
// model"), but that contract comes from IMKit/ObjC, not something the
// Swift compiler can see through NagiInputController's nonisolated
// overrides. Isolating this type would just force NagiInputController's
// call sites into artificial `Task { @MainActor in ... }` hops for calls
// that are already synchronous in practice.
final class CandidateWindowController {

    private let panel: NSPanel
    private let state = CandidateListState()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        // Floats above normal windows, never takes key focus (typing
        // must keep going to the target app, not this panel), and isn't
        // dismissed just because Nagi itself isn't the active app.
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let hostingView = NSHostingView(rootView: CandidateListView(state: state))
        panel.contentView = hostingView
    }

    /// Shows (or repositions/updates) the panel with `output`'s candidate
    /// data (see `CandidateListState.update(from:)` for why this takes the
    /// whole `Output`, not just `Output.candidateWindow`). `caretRect` is
    /// screen coordinates, as returned by
    /// `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`
    /// — see docs/architecture.md, "OS integration: InputMethodKit".
    func show(_ output: Mozc_Commands_Output, belowCaret caretRect: NSRect) {
        state.update(from: output)

        guard let hostingView = panel.contentView as? NSHostingView<CandidateListView> else { return }
        // fittingSize resolves SwiftUI's *ideal* size, which for the
        // scrollable candidate list is its full unclipped content height
        // (see CandidateListView.maxPanelHeight) — clamp it here so the
        // panel (and therefore the hosting view's actual layout bounds)
        // is what makes the list's internal ScrollView clip/scroll at
        // all, not just visually cap it.
        let idealSize = hostingView.fittingSize
        let size = NSSize(width: idealSize.width, height: min(idealSize.height, CandidateListView.maxPanelHeight))
        let origin = NSPoint(x: caretRect.minX, y: caretRect.minY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        // orderFrontRegardless, not orderFront/makeKeyAndOrderFront:
        // this must not steal key focus from the target app's text
        // field, or every subsequent keystroke would go to the panel
        // instead of back through IMKit.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
