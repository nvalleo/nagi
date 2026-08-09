// NagiInputController — M2: real conversion via mozc_server.
//
// M1 held its own romaji buffer and a local RomajiConverter table with no
// real conversion. M2 drops both: every key event is forwarded to
// mozc_server as-is (via MozcBridge/MozcClient, see docs/architecture.md
// "Mozc IPC") and this class only renders whatever `Output` comes back —
// committed text via `insertText`, preedit via `setMarkedText`, and
// candidates via CandidateWindowController. mozc_server's own session
// state machine already implements what Space / arrow keys / Enter /
// Escape do; there is no local keymap to get right or wrong here.
//
// IPC connection target is still MozcClient.defaultServiceName — the
// installed Google 日本語入力's Converter service, exactly like the M0
// PoC. Bundling our own mozc_server (so Nagi doesn't depend on another
// IME being installed) is scoped out to a follow-up, tracked separately
// from this milestone's exit criterion.

import Cocoa
import InputMethodKit
import NagiMozcProto

@objc(NagiInputController)
final class NagiInputController: IMKInputController {

    /// One Mozc converter session per IMKit client connection, created on
    /// activation and torn down on deactivation — mirrors how IMKit
    /// itself scopes one controller instance per client.
    private var sessionID: UInt64?

    private let candidateWindow = CandidateWindowController()

    /// The `CandidateWindow.focusedIndex` from the most recently applied
    /// `Output`, used by `handle(_:client:)`'s auto-advance loop to spot
    /// mozc's end-of-list stall — see there. `nil` whenever no candidate
    /// is focused (matches `CandidateListState.focusedID`'s own
    /// `hasFocusedIndex` gating), so a fresh composition after a commit
    /// can never be mistaken for a stall still in progress.
    private var lastFocusedIndex: UInt32?

    /// How many *real* (not auto-advanced) keystrokes in a row have
    /// reported the same `focusedIndex` as the one before. The first
    /// keystroke that lands on the last real candidate is never a
    /// repeat (`lastFocusedIndex` was different), so it's always shown
    /// as-is — the user can see and select it normally. Auto-advance
    /// used to fire on the very next keystroke, the first *repeat*,
    /// which meant one further press silently jumped clear past the
    /// last candidate to the first with no chance to notice or act on
    /// it in between. Requiring `repeatGraceThreshold` repeats first
    /// gives that one candidate a real keystroke's worth of standing
    /// still before anything starts skipping.
    private var repeatedFocusStreak = 0
    private static let repeatGraceThreshold = 2

    /// Safety net for the auto-advance loop below, not an expected trip
    /// count — the stall itself was verified (against the raw protocol)
    /// to last exactly `CandidateWindow.pageSize` (9 by default) more
    /// presses of the same key. Generous margin in case that assumption
    /// doesn't hold for some case not yet seen; without a cap, a case
    /// where it never resolves would hang key handling in a loop.
    private static let maxAutoAdvance = 20

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        guard sessionID == nil else { return }
        do {
            sessionID = try MozcBridge.createSession()
        } catch {
            NSLog("Nagi: failed to create Mozc session: \(error)")
        }
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput {
            flush(client: client)
        }
        candidateWindow.hide()
        if let sessionID {
            do {
                try MozcBridge.deleteSession(sessionID)
            } catch {
                NSLog("Nagi: failed to delete Mozc session: \(error)")
            }
        }
        sessionID = nil
        super.deactivateServer(sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }
        guard let sessionID else { return false }
        guard let keyEvent = MozcKeyEventMapping.keyEvent(for: event) else { return false }

        var output: Mozc_Commands_Output
        do {
            output = try MozcBridge.sendKey(keyEvent, session: sessionID)
        } catch {
            NSLog("Nagi: sendKey failed: \(error)")
            return false
        }

        // mozc_server holds focusedIndex on the last real candidate for
        // CandidateWindow.pageSize (9 by default) more presses of the
        // same navigation key before wrapping to the first candidate —
        // verified against the raw protocol, independent of anything in
        // this app's rendering (see the CandidateListState.focusedID
        // doc comment). Left alone, that reads as up to 9 keystrokes of
        // dead input, which is exactly the kind of legacy-IME wart nagi
        // is meant to not have (README's positioning vs Google
        // 日本語入力). Silently replaying the same keyEvent while
        // focusedIndex doesn't move collapses that dead zone into one
        // immediate transition. This is a deliberate, narrow exception
        // to this file's "no local keymap" rule above — it doesn't
        // change *what* any key does, only how many times mozc's own
        // state machine has to be asked before its answer changes.
        //
        // repeatedFocusStreak gates *when* that kicks in — see its own
        // doc comment for why the very first repeat must not trigger it.
        let initialFocusedIndex = output.candidateWindow.hasFocusedIndex ? output.candidateWindow.focusedIndex : nil
        if output.hasCandidateWindow, initialFocusedIndex != nil, initialFocusedIndex == lastFocusedIndex {
            repeatedFocusStreak += 1
        } else {
            repeatedFocusStreak = 0
        }

        var autoAdvanceCount = 0
        while repeatedFocusStreak >= Self.repeatGraceThreshold,
            output.hasCandidateWindow,
            output.candidateWindow.hasFocusedIndex,
            output.candidateWindow.focusedIndex == lastFocusedIndex,
            autoAdvanceCount < Self.maxAutoAdvance
        {
            do {
                output = try MozcBridge.sendKey(keyEvent, session: sessionID)
            } catch {
                NSLog("Nagi: sendKey (auto-advance) failed: \(error)")
                break
            }
            autoAdvanceCount += 1
        }
        lastFocusedIndex = output.candidateWindow.hasFocusedIndex ? output.candidateWindow.focusedIndex : nil

        apply(output, client: client)
        return output.consumed
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        flush(client: client)
    }

    /// Forces mozc_server to submit whatever composition is pending
    /// (SessionCommand.SUBMIT — see MozcClient.submit) and renders the
    /// result. Shared by commitComposition(_:), which IMKit calls when
    /// the app forces an end to the input session, and deactivateServer,
    /// which doesn't get a separate commit callback of its own.
    private func flush(client: IMKTextInput) {
        guard let sessionID else { return }
        do {
            let output = try MozcBridge.submit(session: sessionID)
            apply(output, client: client)
        } catch {
            NSLog("Nagi: submit failed: \(error)")
        }
        // Commit always ends candidate selection; without this, a stale
        // focusedIndex from before the commit could coincidentally match
        // the next composition's first focusedIndex and be mistaken by
        // handle(_:client:)'s auto-advance loop for a stall already in
        // progress.
        lastFocusedIndex = nil
        repeatedFocusStreak = 0
    }

    private func apply(_ output: Mozc_Commands_Output, client: IMKTextInput) {
        if !output.result.value.isEmpty {
            client.insertText(output.result.value, replacementRange: NSRange(location: NSNotFound, length: 0))
        }

        if output.preedit.segment.isEmpty {
            client.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        } else {
            let selection = NSRange(location: Int(output.preedit.cursor), length: 0)
            client.setMarkedText(
                markedText(for: output.preedit),
                selectionRange: selection,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }

        if output.hasCandidateWindow, !output.candidateWindow.candidate.isEmpty {
            candidateWindow.show(output, belowCaret: caretRect(client: client))
        } else {
            candidateWindow.hide()
        }
    }

    /// Renders `preedit.segment` as an attributed string so the segment
    /// currently under operation (`Segment.Annotation.highlight`) reads as
    /// visually distinct from the rest — plain `joined()` gave every
    /// segment the same underline, making it unclear which one arrow-key
    /// reconversion was about to affect (#7). Mirrors how Mozc's own
    /// renderer treats these two annotations: a thick underline plus a
    /// selection-colored background for the active segment, a thin
    /// underline for everything else.
    private func markedText(for preedit: Mozc_Commands_Preedit) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for segment in preedit.segment {
            let attributes: [NSAttributedString.Key: Any]
            switch segment.annotation {
            case .highlight:
                attributes = [
                    .underlineStyle: NSUnderlineStyle.thick.rawValue,
                    .backgroundColor: NSColor.selectedTextBackgroundColor,
                ]
            case .underline, .none:
                attributes = [.underlineStyle: NSUnderlineStyle.single.rawValue]
            }
            text.append(NSAttributedString(string: segment.value, attributes: attributes))
        }
        return text
    }

    /// Caret geometry in screen coordinates, per
    /// `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`
    /// — the only documented way to place a candidate window under the
    /// caret across arbitrary target apps (docs/architecture.md).
    private func caretRect(client: IMKTextInput) -> NSRect {
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        return lineRect
    }
}
