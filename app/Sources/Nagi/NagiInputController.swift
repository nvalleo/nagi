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

        let output: Mozc_Commands_Output
        do {
            output = try MozcBridge.sendKey(keyEvent, session: sessionID)
        } catch {
            NSLog("Nagi: sendKey failed: \(error)")
            return false
        }

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
            candidateWindow.show(output.candidateWindow, belowCaret: caretRect(client: client))
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
