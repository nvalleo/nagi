// NagiInputController — M1's whole IME: hold an input mode, buffer
// romaji, commit hiragana on Enter. No conversion (that's M2, via
// MozcClient — see poc/Sources/NagiMozcIPC/).
//
// Modeled on how google/mozc's own mac/mozc_imk_input_controller.mm
// drives IMKit: override `handleEvent:client:` for full control over raw
// key events (rather than `inputText:client:`, which loses key identity
// for special keys), and talk back to the client via the `IMKTextInput`
// methods `setMarkedText(_:selectionRange:replacementRange:)` (preedit)
// and `insertText(_:replacementRange:)` (commit).

import Cocoa
import InputMethodKit

// Standard virtual keycodes (Carbon's HIToolbox constants) for the two
// special keys M1 cares about. Hardcoded rather than importing Carbon for
// just these two.
private enum VirtualKey {
    static let returnKey: UInt16 = 0x24
    static let delete: UInt16 = 0x33
}

@objc(NagiInputController)
final class NagiInputController: IMKInputController {

    /// Romaji typed so far, not yet committed.
    private var buffer: String = ""

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

        if event.keyCode == VirtualKey.returnKey {
            guard !buffer.isEmpty else { return false }
            commit(client: client)
            return true
        }

        if event.keyCode == VirtualKey.delete {
            guard !buffer.isEmpty else { return false }
            buffer.removeLast()
            updateMarkedText(client: client)
            return true
        }

        // Only plain lowercase ASCII letters feed the romaji buffer —
        // anything else (space, punctuation, modified keys, ...) commits
        // whatever's pending and falls through so the app handles it
        // normally, matching how a real IME doesn't eat unrelated input.
        if let character = printableASCIILetter(from: event) {
            buffer.append(character)
            updateMarkedText(client: client)
            return true
        }

        if !buffer.isEmpty {
            commit(client: client)
        }
        return false
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput, !buffer.isEmpty else { return }
        commit(client: client)
    }

    private func printableASCIILetter(from event: NSEvent) -> Character? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }
        guard let characters = event.characters, characters.count == 1,
            let character = characters.lowercased().first, character.isASCII, character.isLetter
        else {
            return nil
        }
        return character
    }

    private func updateMarkedText(client: IMKTextInput) {
        let composed = RomajiConverter.convert(buffer)
        let selection = NSRange(location: composed.utf16.count, length: 0)
        client.setMarkedText(
            composed,
            selectionRange: selection,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func commit(client: IMKTextInput) {
        let composed = RomajiConverter.convert(buffer)
        client.insertText(composed, replacementRange: NSRange(location: NSNotFound, length: 0))
        buffer = ""
    }
}
