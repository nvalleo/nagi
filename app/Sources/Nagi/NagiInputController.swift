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

    /// The most recently applied `Output`, used to check
    /// `candidateWindow.hasSubCandidateWindow` before forwarding a Right
    /// arrow press — see `handle(_:client:)`'s sub-candidate entry point.
    private var lastOutput: Mozc_Commands_Output?

    /// mozc `Candidate.id` values (not `.index` — see
    /// `CandidateListState.Candidate`) of the cascading sub-candidate
    /// window currently being browsed (e.g. "そのほかの文字種"'s
    /// half/full-width variants), and which one is locally focused.
    /// `nil` outside of that mode.
    ///
    /// mozc's protocol has no keyboard-navigable notion of this state —
    /// verified against the raw protocol that sending the Right arrow
    /// key itself, from a candidate with `hasSubCandidateWindow`, just
    /// closes the whole candidate window. `SessionCommand.
    /// SELECT_CANDIDATE` with an explicit id — the mouse-click path per
    /// its own doc comment in commands.proto — is the only way in. So
    /// once entered (see `enterSubCandidateMode`), this state is tracked
    /// and driven entirely client-side; mozc's own session is left
    /// completely alone until `commitSubCandidate` issues that command.
    private var subCandidateIDs: [Int32] = []
    private var subCandidateFocusedIndex: Int?
    /// The parent `Output` whose focused candidate had the sub-window —
    /// restored to redisplay the parent list on exiting (Left/Escape),
    /// and its `subCandidateWindow.candidate` re-read on every
    /// `moveSubCandidateFocus` to render the sub-list itself.
    private var subCandidateParentOutput: Mozc_Commands_Output?

    /// M4 (#19): the current ":"-triggered emoji shortcode search query
    /// (see `EmojiShortcodeDictionary`), *not* including the leading
    /// ":" itself — `""` right after entering the mode, appended to on
    /// every printable keystroke. `nil` outside of shortcode search
    /// entirely; that's the mode's own on/off switch, checked first
    /// thing in `handle(_:client:)`. Same "entirely client-side, mozc's
    /// session never touched" approach as `subCandidateIDs` above — this
    /// is a client-only feature mozc's OSS build has no notion of at
    /// all, not something being shadowed from its own session state.
    private var shortcodeQuery: String?
    /// `EmojiShortcodeDictionary.shared.search(shortcodeQuery)`'s result,
    /// recomputed on every buffer change (append/backspace) — this is
    /// what `CandidateListState.updateShortcodeCandidates` renders and
    /// what `shortcodeFocusedIndex` indexes into.
    private var shortcodeMatches: [String] = []
    /// Position within `shortcodeMatches` the grid is focused on. `nil`
    /// only when `shortcodeMatches` is empty (no match, or query still
    /// empty) — mirrors `CandidateListState.focusedID`'s own
    /// `hasFocusedIndex` gating.
    private var shortcodeFocusedIndex: Int?
    /// The ":" keystroke that enters shortcode search — `keyEvent.keyCode`
    /// is the Unicode scalar value for any non-special key (see
    /// MozcKeyEventMapping), so this is what a literal ":" arrives as.
    private static let shortcodeSearchTriggerKeyCode = UnicodeScalar(":").value

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

        if shortcodeQuery != nil {
            return handleShortcodeSearchKey(keyEvent, client: client)
        }

        if subCandidateFocusedIndex != nil {
            switch keyEvent.specialKey {
            case .down, .space:
                // Space advances the *parent* candidate list too (it's
                // conversion-cycling's own next-candidate key, distinct
                // from Down's prediction-cycling — see
                // CandidateListState.update's doc comment) — the sub-
                // candidate list only has one navigation model, so both
                // keys drive it the same way here.
                moveSubCandidateFocus(by: 1, keyEvent: keyEvent, session: sessionID, client: client)
                return true
            case .up:
                moveSubCandidateFocus(by: -1, keyEvent: keyEvent, session: sessionID, client: client)
                return true
            case .enter:
                commitSubCandidate(session: sessionID, client: client)
                return true
            case .left, .escape:
                exitSubCandidateMode(client: client)
                return true
            default:
                // Not a sub-cascade key — drop the local state and let
                // it fall through to mozc normally below. Safe: mozc's
                // own session was never touched while browsing the
                // sub-list, only queried for its (already-cached)
                // subCandidateWindow contents.
                subCandidateIDs = []
                subCandidateFocusedIndex = nil
                subCandidateParentOutput = nil
            }
        } else if keyEvent.specialKey == .right,
            let lastOutput,
            lastOutput.candidateWindow.hasFocusedIndex,
            lastOutput.candidateWindow.hasSubCandidateWindow
        {
            enterSubCandidateMode(from: lastOutput, client: client)
            return true
        } else if isShortcodeSearchTrigger(keyEvent) {
            enterShortcodeSearchMode(client: client)
            return true
        }

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
            // The stalled candidate itself has further variants ("その
            // ほかの文字種" and similar, e.g. half/full-width) — the
            // repeat press isn't dead input to wait out, there's
            // somewhere for it to go. Descend into the sub-candidates
            // immediately, the same place Right arrow leads to
            // explicitly (see enterSubCandidateMode), so continuing to
            // press the same navigation key reads as the list simply
            // continuing rather than requiring a different key. No
            // repeatGraceThreshold delay here, unlike the plain-stall
            // case below: this isn't a silent skip past something the
            // user might have wanted to select, it's revealing more of
            // what's conceptually the same list.
            if output.candidateWindow.hasFocusedIndex, output.candidateWindow.hasSubCandidateWindow {
                lastFocusedIndex = output.candidateWindow.focusedIndex
                lastOutput = output
                enterSubCandidateMode(from: output, client: client)
                return true
            }
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
        lastOutput = output

        apply(output, client: client)
        return output.consumed
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        flush(client: client)
    }

    /// #39: the item shown in the menu bar's Input Source menu. Passing
    /// only `action` with no explicit target has IMKit route it to
    /// whichever object implements the selector — the controller itself
    /// (self) — the same wiring macSKK uses (InputController.swift's
    /// `menu()`). The settings window is a single process-wide
    /// singleton, so it doesn't matter which NagiInputController
    /// instance this gets called on; it always shows the same window.
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "環境設定…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        return menu
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
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
            lastOutput = output
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
        subCandidateIDs = []
        subCandidateFocusedIndex = nil
        subCandidateParentOutput = nil
        shortcodeQuery = nil
        shortcodeMatches = []
        shortcodeFocusedIndex = nil
    }

    /// Enters cascading sub-candidate browsing (`output.candidateWindow.
    /// subCandidateWindow`) — see `subCandidateIDs`'s doc comment for why
    /// this is entirely client-side from here on.
    private func enterSubCandidateMode(from output: Mozc_Commands_Output, client: IMKTextInput) {
        let subCandidates = output.candidateWindow.subCandidateWindow.candidate
        guard !subCandidates.isEmpty else { return }
        subCandidateIDs = subCandidates.map(\.id)
        subCandidateFocusedIndex = 0
        subCandidateParentOutput = output
        renderSubCandidates(client: client)
    }

    /// Neither direction wraps *within* the sub-candidate list itself —
    /// both ends hand off to the parent list instead, so the whole
    /// thing (main candidates → sub-candidates → back to the first main
    /// candidate) reads as one continuous loop, matching how entering
    /// is now just "keep pressing the same key" (see
    /// `handle(_:client:)`'s stall-with-subCandidateWindow branch).
    /// Moving up past the first sub-candidate returns to right where
    /// the parent list was left, at no cost — mozc's own session was
    /// never touched while browsing. Moving down past the last one is
    /// the harder direction: mozc's session is still sitting on the
    /// same stalled focusedIndex it was at on entry, so getting back to
    /// the first main candidate means resuming its own stall countdown
    /// — see `exitSubCandidateModeAndWrapToStart`.
    private func moveSubCandidateFocus(by delta: Int, keyEvent: Mozc_Commands_KeyEvent, session: UInt64, client: IMKTextInput) {
        guard let index = subCandidateFocusedIndex, !subCandidateIDs.isEmpty else { return }
        let newIndex = index + delta
        if newIndex < 0 {
            exitSubCandidateMode(client: client)
            return
        }
        if newIndex >= subCandidateIDs.count {
            exitSubCandidateModeAndWrapToStart(keyEvent: keyEvent, session: session, client: client)
            return
        }
        subCandidateFocusedIndex = newIndex
        renderSubCandidates(client: client)
    }

    /// Continuing forward past the last sub-candidate completes the
    /// "one continuous list" loop back to the first main candidate,
    /// instead of looping within the sub-candidates alone — see
    /// `moveSubCandidateFocus`'s doc comment. mozc's own session was
    /// left completely untouched while sub-candidates were being
    /// browsed, so it's still sitting on the exact same stalled
    /// focusedIndex it reported on entry; replaying the same key here
    /// drives it the rest of the way through its own
    /// `CandidateWindow.pageSize`-bounded stall, the same mechanism
    /// `handle(_:client:)`'s own end-of-list auto-advance loop uses.
    private func exitSubCandidateModeAndWrapToStart(keyEvent: Mozc_Commands_KeyEvent, session: UInt64, client: IMKTextInput) {
        guard let stalledOutput = subCandidateParentOutput, stalledOutput.candidateWindow.hasFocusedIndex else {
            exitSubCandidateMode(client: client)
            return
        }
        let stalledIndex = stalledOutput.candidateWindow.focusedIndex
        subCandidateIDs = []
        subCandidateFocusedIndex = nil
        subCandidateParentOutput = nil

        var output = stalledOutput
        var advanceCount = 0
        while output.candidateWindow.hasFocusedIndex,
            output.candidateWindow.focusedIndex == stalledIndex,
            advanceCount < Self.maxAutoAdvance
        {
            do {
                output = try MozcBridge.sendKey(keyEvent, session: session)
            } catch {
                NSLog("Nagi: sendKey (sub-candidate wrap) failed: \(error)")
                break
            }
            advanceCount += 1
        }
        lastFocusedIndex = output.candidateWindow.hasFocusedIndex ? output.candidateWindow.focusedIndex : nil
        lastOutput = output
        repeatedFocusStreak = 0
        apply(output, client: client)
    }

    private func renderSubCandidates(client: IMKTextInput) {
        guard let subCandidateParentOutput, let subCandidateFocusedIndex else { return }
        let subCandidates = subCandidateParentOutput.candidateWindow.subCandidateWindow.candidate
        candidateWindow.showSubCandidates(
            subCandidates,
            focusedIndex: subCandidateFocusedIndex,
            belowCaret: caretRect(client: client)
        )
        if subCandidates.indices.contains(subCandidateFocusedIndex) {
            previewSubCandidate(subCandidates[subCandidateFocusedIndex], in: subCandidateParentOutput, client: client)
        }
    }

    /// Shows the locally-focused sub-candidate in the text field itself
    /// (the underlined preview text), not just in the sub-candidate
    /// window's own list — without this, moving through "そのほかの
    /// 文字種" and its like changed what was highlighted in the popup
    /// but never what the user actually saw being composed, since
    /// mozc's own session (and therefore its `preedit`) is never
    /// touched while browsing (see `subCandidateIDs`'s doc comment).
    /// Substitutes the candidate's text into a *copy* of the parent
    /// output's preedit — specifically the segment currently under
    /// conversion (`Segment.Annotation.highlight`, the same one
    /// `markedText(for:)` gives the "active segment" styling to) — and
    /// renders that, exactly like `apply(_:client:)` would for a real
    /// `Output`. `exitSubCandidateMode` undoes this by re-applying the
    /// real, unmodified `parentOutput` when backing out without
    /// selecting.
    private func previewSubCandidate(_ candidate: Mozc_Commands_CandidateWindow.Candidate, in parentOutput: Mozc_Commands_Output, client: IMKTextInput) {
        guard let highlightIndex = parentOutput.preedit.segment.firstIndex(where: { $0.annotation == .highlight })
        else { return }
        var preedit = parentOutput.preedit
        preedit.segment[highlightIndex].value = candidate.value
        let text = markedText(for: preedit)
        client.setMarkedText(
            text,
            selectionRange: NSRange(location: text.length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    /// Commits the locally-focused sub-candidate: `SELECT_CANDIDATE`
    /// (the mouse-click equivalent — see `subCandidateIDs`'s doc
    /// comment) moves it into the preedit and closes the sub-window,
    /// verified against the raw protocol to *not* itself commit, so a
    /// normal `SUBMIT` follows, exactly like Enter would on the parent
    /// list.
    private func commitSubCandidate(session: UInt64, client: IMKTextInput) {
        guard let index = subCandidateFocusedIndex, subCandidateIDs.indices.contains(index) else {
            exitSubCandidateMode(client: client)
            return
        }
        let id = subCandidateIDs[index]
        subCandidateIDs = []
        subCandidateFocusedIndex = nil
        subCandidateParentOutput = nil
        do {
            var select = Mozc_Commands_SessionCommand()
            select.type = .selectCandidate
            select.id = id
            _ = try MozcBridge.sendCommand(select, session: session)
            let output = try MozcBridge.submit(session: session)
            lastOutput = output
            lastFocusedIndex = nil
            repeatedFocusStreak = 0
            apply(output, client: client)
        } catch {
            NSLog("Nagi: sub-candidate select/submit failed: \(error)")
        }
    }

    /// Backs out of sub-candidate browsing (Left/Escape) without
    /// committing anything, restoring the parent candidate list — mozc's
    /// own session was never touched while browsing, so there's nothing
    /// to undo there. Goes through `apply(_:client:)`, not just
    /// `candidateWindow.show`, so the text-field preview
    /// `previewSubCandidate` overwrote gets put back to the real,
    /// unmodified parent preedit too.
    private func exitSubCandidateMode(client: IMKTextInput) {
        let parentOutput = subCandidateParentOutput
        subCandidateIDs = []
        subCandidateFocusedIndex = nil
        subCandidateParentOutput = nil
        if let parentOutput {
            apply(parentOutput, client: client)
        } else {
            candidateWindow.hide()
        }
    }

    /// True for a bare ":" keystroke while nothing is currently being
    /// composed — the Slack/GitHub-style entry point into shortcode
    /// search (#19). Gated on preedit being empty so ordinary Japanese
    /// input keeps working exactly as before: a ":" typed *during*
    /// composition still reaches mozc below and converts to the
    /// fullwidth "：" candidate, same as always. `lastOutput` is the
    /// only place preedit state lives client-side; no `Output` yet
    /// (fresh session) reads the same as an empty one.
    private func isShortcodeSearchTrigger(_ keyEvent: Mozc_Commands_KeyEvent) -> Bool {
        guard keyEvent.hasKeyCode, keyEvent.keyCode == Self.shortcodeSearchTriggerKeyCode else { return false }
        return lastOutput?.preedit.segment.isEmpty ?? true
    }

    /// Enters shortcode search with an empty query — nothing to match
    /// yet, so the candidate window stays hidden until the first
    /// character of the query itself arrives (`appendToShortcodeQuery`).
    /// Still shows the triggering ":" itself as marked text, same as any
    /// other keystroke in this mode — see `updateShortcodeMarkedText`.
    private func enterShortcodeSearchMode(client: IMKTextInput) {
        shortcodeQuery = ""
        shortcodeMatches = []
        shortcodeFocusedIndex = nil
        candidateWindow.hide()
        updateShortcodeMarkedText(client: client)
    }

    /// Routes every keystroke while shortcode search is active (i.e.
    /// `shortcodeQuery != nil`) — mozc's session is never sent anything
    /// here, mirroring `subCandidateIDs`'s doc comment: this is a
    /// client-only feature, not shadowing mozc's own state.
    private func handleShortcodeSearchKey(_ keyEvent: Mozc_Commands_KeyEvent, client: IMKTextInput) -> Bool {
        switch keyEvent.specialKey {
        case .enter:
            commitShortcodeCandidate(client: client)
            return true
        case .tab:
            // On an empty query, Tab browses the full emoji list instead
            // of committing — the discoverable-picker entry point (#19
            // follow-up). A non-empty query already has real matches to
            // commit, so Tab there behaves exactly like Enter, matching
            // Tab's usual "accept the suggestion" role.
            if (shortcodeQuery ?? "").isEmpty {
                browseAllShortcodeCandidates(client: client)
            } else {
                commitShortcodeCandidate(client: client)
            }
            return true
        case .escape:
            commitShortcodeQueryAsLiteralText(client: client)
            return true
        case .backspace:
            deleteLastShortcodeQueryCharacter(client: client)
            return true
        case .left:
            moveShortcodeFocus(by: -1, client: client)
            return true
        case .right:
            moveShortcodeFocus(by: 1, client: client)
            return true
        case .up:
            moveShortcodeFocus(by: -CandidateListView.gridColumnCount, client: client)
            return true
        case .down:
            moveShortcodeFocus(by: CandidateListView.gridColumnCount, client: client)
            return true
        default:
            break
        }

        // Printable ASCII appended to the query. `keyEvent.keyCode` is
        // already the Unicode scalar value for anything that isn't a
        // special key — see MozcKeyEventMapping — so this covers exactly
        // what would otherwise have been forwarded to mozc as ordinary
        // text input.
        guard keyEvent.hasKeyCode, let scalar = Unicode.Scalar(keyEvent.keyCode) else {
            // Not something shortcode search understands (a modifier-only
            // event or similar that still made it past
            // MozcKeyEventMapping). Swallow rather than falling through
            // to mozc — its session was never touched while this mode is
            // active, so there's nothing coherent to hand it mid-buffer.
            return true
        }
        appendToShortcodeQuery(Character(scalar), client: client)
        return true
    }

    private func appendToShortcodeQuery(_ character: Character, client: IMKTextInput) {
        guard var query = shortcodeQuery else { return }
        query.append(character)
        shortcodeQuery = query
        refreshShortcodeMatches(client: client)
    }

    /// Backspace on an already-empty query (i.e. right after the
    /// triggering ":") exits the mode entirely — mirrors how deleting
    /// past the start of an ordinary composition would end it.
    private func deleteLastShortcodeQueryCharacter(client: IMKTextInput) {
        guard var query = shortcodeQuery else { return }
        guard !query.isEmpty else {
            exitShortcodeSearchMode(client: client)
            return
        }
        query.removeLast()
        shortcodeQuery = query
        refreshShortcodeMatches(client: client)
    }

    private func refreshShortcodeMatches(client: IMKTextInput) {
        guard let query = shortcodeQuery else { return }
        shortcodeMatches = EmojiShortcodeDictionary.shared.search(query)
        shortcodeFocusedIndex = shortcodeMatches.isEmpty ? nil : 0
        updateShortcodeMarkedText(client: client)
        renderShortcodeCandidates(client: client)
    }

    /// Tab-on-empty-query entry point (#19 follow-up) — shows
    /// `RecentEmojiStore`'s most-recently-committed emoji first, then
    /// the rest of `EmojiShortcodeDictionary.allEmoji` (recents removed
    /// from their dictionary-order position, so nothing appears twice)
    /// for browsing instead of a filtered search result. Doesn't touch
    /// `shortcodeQuery` itself (still `""`), so typing right after this
    /// still filters normally via `appendToShortcodeQuery`/
    /// `refreshShortcodeMatches`, and Enter/Escape on the still-empty
    /// query keep committing the fullwidth "：" (see
    /// `commitShortcodeQueryAsLiteralText`) exactly as before — this
    /// only changes what Tab itself does.
    private func browseAllShortcodeCandidates(client: IMKTextInput) {
        let recents = RecentEmojiStore.shared.recentEmoji
        let recentsSet = Set(recents)
        let rest = EmojiShortcodeDictionary.shared.allEmoji.filter { !recentsSet.contains($0) }
        shortcodeMatches = recents + rest
        shortcodeFocusedIndex = shortcodeMatches.isEmpty ? nil : 0
        renderShortcodeCandidates(client: client)
    }

    /// Shows the shortcode buffer itself — ":" plus the query typed so
    /// far — as marked text (underlined, like ordinary preedit). Without
    /// this the user would have no visible feedback for what they've
    /// typed: shortcode search never touches mozc's own preedit, so
    /// nothing about it would otherwise reach the text field at all
    /// until a candidate is actually committed. Deliberately a plain
    /// single-style underline, not `markedText(for:)`'s highlighted-
    /// segment styling — there's no multi-segment concept here to
    /// distinguish.
    private func updateShortcodeMarkedText(client: IMKTextInput) {
        guard let shortcodeQuery else { return }
        let text = ":" + shortcodeQuery
        let attributed = NSAttributedString(string: text, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func renderShortcodeCandidates(client: IMKTextInput) {
        guard !shortcodeMatches.isEmpty else {
            candidateWindow.hide()
            return
        }
        candidateWindow.showShortcodeCandidates(shortcodeMatches, focusedIndex: shortcodeFocusedIndex, belowCaret: caretRect(client: client))
    }

    /// `delta` is in flattened `shortcodeMatches` index space — ±1 for
    /// Left/Right, ±`CandidateListView.gridColumnCount` for Up/Down, to
    /// match how that view actually lays the grid out. Out-of-range
    /// moves (top/bottom/either edge of the grid) are no-ops rather than
    /// wrapping — unlike the mozc-backed sub-candidate list above, there
    /// is no "continuous loop back to a parent list" concept here for an
    /// edge to hand off to.
    private func moveShortcodeFocus(by delta: Int, client: IMKTextInput) {
        guard let index = shortcodeFocusedIndex, shortcodeMatches.indices.contains(index + delta) else { return }
        shortcodeFocusedIndex = index + delta
        renderShortcodeCandidates(client: client)
    }

    /// Commits the focused match as plain text via `insertText` — no
    /// `SessionCommand` of any kind, since mozc's session was never
    /// involved in shortcode search to begin with (see `shortcodeQuery`'s
    /// doc comment). No separate call to clear the ":"+query marked text
    /// first: `insertText` replaces whatever marked text is currently
    /// showing, per `IMKTextInput`'s own contract. Records the commit in
    /// `RecentEmojiStore` so `browseAllShortcodeCandidates` surfaces it
    /// next time — not done in `commitShortcodeQueryAsLiteralText`,
    /// since that path never actually selected an emoji.
    private func commitShortcodeCandidate(client: IMKTextInput) {
        guard let index = shortcodeFocusedIndex, shortcodeMatches.indices.contains(index) else {
            // Enter/Tab with no match — same "keep what was typed" call
            // as Escape (see commitShortcodeQueryAsLiteralText) rather
            // than silently discarding it: there's nothing more useful
            // Enter could do here, and dropping the text the user just
            // typed would be surprising.
            commitShortcodeQueryAsLiteralText(client: client)
            return
        }
        let emoji = shortcodeMatches[index]
        RecentEmojiStore.shared.record(emoji)
        shortcodeQuery = nil
        shortcodeMatches = []
        shortcodeFocusedIndex = nil
        candidateWindow.hide()
        client.insertText(emoji, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Escape dismisses the candidate picker but keeps whatever was
    /// typed, committing ":"+query as plain text — the only way to type
    /// a literal ":" at all, since every ":" keystroke enters this mode
    /// (see `isShortcodeSearchTrigger`). Mirrors Slack/GitHub's own
    /// Escape behavior: it closes the suggestion popup, not the text
    /// already typed. No separate call to clear the marked text first:
    /// `insertText` replaces whatever marked text is currently showing,
    /// per `IMKTextInput`'s own contract (same as `commitShortcodeCandidate`).
    ///
    /// A bare ":" (query still empty) becomes the fullwidth "：" —
    /// matches what ordinary Japanese input would have produced for a
    /// lone ":" keystroke (mozc's own conversion candidate), since a
    /// half-width symbol reads as an odd leftover mid-Japanese-input. A
    /// non-empty query almost always mixes in ASCII letters/digits
    /// (that's the whole point of shortcode search), where fullwidth-
    /// converting only the ":" would look inconsistent, so those are
    /// left exactly as typed.
    private func commitShortcodeQueryAsLiteralText(client: IMKTextInput) {
        let query = shortcodeQuery ?? ""
        let text = query.isEmpty ? "：" : ":" + query
        shortcodeQuery = nil
        shortcodeMatches = []
        shortcodeFocusedIndex = nil
        candidateWindow.hide()
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Backs out of shortcode search when Backspace deletes past an
    /// already-empty query — unlike Escape above, this drops the ":"
    /// entirely rather than committing it: it's a continuation of
    /// "delete one more character", not a dismissal of typed text.
    /// Clears the ":"+query marked text `updateShortcodeMarkedText` put
    /// up, since nothing is being committed to replace it.
    private func exitShortcodeSearchMode(client: IMKTextInput) {
        shortcodeQuery = nil
        shortcodeMatches = []
        shortcodeFocusedIndex = nil
        candidateWindow.hide()
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
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
