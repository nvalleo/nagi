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
    private var lastFrame: NSRect?

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
        announceFocusChange(
            hasSubmenu: output.candidateWindow.hasFocusedIndex && output.candidateWindow.hasSubCandidateWindow,
            isSubCandidateContext: false
        )
        reposition(belowCaret: caretRect)
    }

    /// Shows a cascading sub-candidate window in place of the parent
    /// list — see `CandidateListState.updateSubCandidates(_:focusedIndex:)`
    /// and `NagiInputController`'s sub-candidate handling for why this
    /// needs its own entry point instead of going through `show(_:
    /// belowCaret:)`: there's no real `Output` for this state, since
    /// mozc itself isn't tracking it.
    func showSubCandidates(_ subCandidates: [Mozc_Commands_CandidateWindow.Candidate], focusedIndex: Int, belowCaret caretRect: NSRect) {
        state.updateSubCandidates(subCandidates, focusedIndex: focusedIndex)
        announceFocusChange(hasSubmenu: false, isSubCandidateContext: true)
        reposition(belowCaret: caretRect)
    }

    private var lastAnnouncedCandidateID: Int?
    private var lastAnnouncedWasSubCandidateContext = false

    /// VoiceOver support. The panel deliberately never becomes key (see
    /// `becomesKeyOnlyIfNeeded` above — typing must keep going to the
    /// target app), which means VoiceOver's normal focus-follows model
    /// never picks it up: nothing here is "focused" in the AX sense, so
    /// a plain `.accessibilityAddTraits(.isSelected)` in
    /// `CandidateListView` alone is silent. macOS's own system Japanese
    /// input candidate window has the same constraint and solves it the
    /// same way — an explicit `.announcementRequested` notification,
    /// which VoiceOver speaks regardless of AX focus.
    ///
    /// Only fires when the focused candidate's identity (or list/
    /// sub-list context) actually changed — critically, *not* on every
    /// `show()` call, since mozc's own end-of-list stall (see
    /// `CandidateListState.focusedID`'s doc comment) means several
    /// consecutive keystrokes can report the same focused candidate; if
    /// each one still announced, that stall would sound like VoiceOver
    /// itself is stuck repeating, instead of accurately going silent
    /// (correctly) while nothing changes.
    private func announceFocusChange(hasSubmenu: Bool, isSubCandidateContext: Bool) {
        guard let focusedID = state.focusedID,
            let candidate = state.candidates.first(where: { $0.id == focusedID })
        else {
            lastAnnouncedCandidateID = nil
            lastAnnouncedWasSubCandidateContext = false
            return
        }
        let contextChanged = isSubCandidateContext != lastAnnouncedWasSubCandidateContext
        guard contextChanged || candidate.id != lastAnnouncedCandidateID else { return }
        lastAnnouncedCandidateID = candidate.id
        lastAnnouncedWasSubCandidateContext = isSubCandidateContext

        var announcement = candidate.text
        if isSubCandidateContext {
            announcement = "サブ候補: " + announcement
        } else if hasSubmenu {
            announcement += "、右矢印キーでさらに選択肢"
        }
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func reposition(belowCaret caretRect: NSRect) {
        guard let hostingView = panel.contentView as? NSHostingView<CandidateListView> else { return }
        // fittingSize resolves SwiftUI's ideal size for whatever
        // CandidateListView.visibleRows currently windows into view —
        // clamp it here as a backstop against CandidateListView's own
        // (estimated, not pixel-measured) height budget slightly
        // overshooting maxPanelHeight.
        let idealSize = hostingView.fittingSize
        let size = NSSize(width: idealSize.width, height: min(idealSize.height, CandidateListView.maxPanelHeight))
        let origin = NSPoint(x: caretRect.minX, y: caretRect.minY - size.height)
        let frame = NSRect(origin: origin, size: size)

        // Only actually resize the panel when the frame changed — e.g. a
        // new conversion, or crossing into/out of the M3d (#16)
        // pictograph grid, changes the content's natural size. Cycling
        // through candidates within one conversion (Space/Down/Tab) is
        // the common case and produces the *same* frame most calls;
        // skipping the redundant `setFrame` avoids forcing AppKit to
        // redo the hosting view's layout on every keystroke for no
        // visible benefit (tried while chasing #21 — didn't turn out to
        // be the cause, but kept as a harmless optimization).
        if frame != lastFrame {
            panel.setFrame(frame, display: true)
            lastFrame = frame
        }

        // orderFrontRegardless, not orderFront/makeKeyAndOrderFront:
        // this must not steal key focus from the target app's text
        // field, or every subsequent keystroke would go to the panel
        // instead of back through IMKit.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        // Without this, a coincidental id match (e.g. both this closing
        // list and the next conversion's list happen to have a
        // candidate id=0 first) could suppress that next announcement.
        lastAnnouncedCandidateID = nil
        lastAnnouncedWasSubCandidateContext = false
    }
}
