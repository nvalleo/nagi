// MozcKeyEventMapping — translates an AppKit NSEvent into the
// Mozc_Commands_KeyEvent the server expects.
//
// M2 forwards (almost) every key straight to mozc_server rather than
// re-implementing romaji tables / candidate-navigation keymaps locally —
// see MozcBridge.swift and NagiInputController.swift for why. This file
// is the one place that knows how a Carbon virtual keycode maps to
// Mozc's SpecialKey enum.

import Cocoa
import NagiMozcProto

enum MozcKeyEventMapping {

    /// Standard virtual keycodes (Carbon's HIToolbox constants) for the
    /// keys mozc_server's session state machine gives meaning to.
    /// Hardcoded rather than importing Carbon for just these.
    private enum VirtualKey {
        static let returnKey: UInt16 = 0x24
        static let tab: UInt16 = 0x30
        static let space: UInt16 = 0x31
        static let backspace: UInt16 = 0x33
        static let escape: UInt16 = 0x35
        static let leftArrow: UInt16 = 0x7B
        static let rightArrow: UInt16 = 0x7C
        static let downArrow: UInt16 = 0x7D
        static let upArrow: UInt16 = 0x7E
    }

    /// Returns `nil` for events that shouldn't reach Mozc at all — held
    /// Command/Control/Option (application shortcuts, not IME input) or
    /// anything that isn't a single special key or a printable ASCII
    /// character. `NagiInputController` treats `nil` the same way M1 did:
    /// let the app handle the event normally.
    static func keyEvent(for event: NSEvent) -> Mozc_Commands_KeyEvent? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }

        var keyEvent = Mozc_Commands_KeyEvent()

        if let special = specialKey(for: event.keyCode) {
            keyEvent.specialKey = special
            return keyEvent
        }

        guard let characters = event.characters,
            let scalar = characters.unicodeScalars.first,
            characters.unicodeScalars.count == 1,
            scalar.isASCII
        else {
            return nil
        }

        keyEvent.keyCode = scalar.value
        return keyEvent
    }

    private static func specialKey(for virtualKeyCode: UInt16) -> Mozc_Commands_KeyEvent.SpecialKey? {
        switch virtualKeyCode {
        case VirtualKey.returnKey: return .enter
        case VirtualKey.tab: return .tab
        case VirtualKey.space: return .space
        case VirtualKey.backspace: return .backspace
        case VirtualKey.escape: return .escape
        case VirtualKey.leftArrow: return .left
        case VirtualKey.rightArrow: return .right
        case VirtualKey.downArrow: return .down
        case VirtualKey.upArrow: return .up
        default: return nil
        }
    }
}
