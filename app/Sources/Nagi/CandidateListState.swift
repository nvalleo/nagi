// CandidateListState — the observable model CandidateListView renders.
//
// Kept as a plain ObservableObject rather than folding this into
// CandidateWindowController so SwiftUI's diffing has a stable object
// identity to observe across updates (NSHostingView's rootView is only
// set up once — see CandidateWindowController).

import Combine
import NagiMozcProto

final class CandidateListState: ObservableObject {

    struct Candidate: Identifiable {
        let id: Int
        let text: String
        /// M3d (#16): emoji/kaomoji candidates share the same category
        /// (`CandidateWindow.category == .conversion`) and direction
        /// (`.vertical`) as ordinary text candidates — mozc doesn't flag
        /// them separately at that level, and they're interleaved in the
        /// same candidate list, not returned as their own group. The one
        /// reliable signal, confirmed on-device, is
        /// `Candidate.annotation.description_p` starting with "絵文字"
        /// (emoji) or "顔文字" (kaomoji) — e.g. "絵文字 三日月", "顔文字
        /// にこにこ わーい". `CandidateListView` uses this to switch
        /// consecutive runs of these into a grid instead of the plain
        /// list.
        let isPictograph: Bool
        /// True only for the currently-*focused* candidate, and only
        /// when `CandidateWindow.hasSubCandidateWindow` — mozc only
        /// populates `subCandidateWindow` for whichever candidate is
        /// focused right now, so this can't be known ahead of time for
        /// candidates the user hasn't reached yet (see `update(from:)`).
        /// Drives a small "▶" hint in `CandidateListView`.
        let hasSubCandidates: Bool
    }

    @Published private(set) var candidates: [Candidate] = []
    /// Not a bug if this appears to "stick" on the same value for
    /// several keystrokes in a row near the end of a short candidate
    /// list: verified against the raw protocol (bypassing this app's
    /// UI entirely) that mozc_server itself holds `focusedIndex` on the
    /// last real candidate for exactly `CandidateWindow.pageSize` (9 by
    /// default) more Space/Down presses before wrapping back to the
    /// first candidate — this class and `CandidateListView` just
    /// reflect whatever mozc reports here faithfully. Cost real time to
    /// track down (see #21) after this repeatedly looked like a
    /// SwiftUI rendering freeze.
    @Published private(set) var focusedID: Int?

    /// Reads from `Output.candidateWindow.candidate` — whichever page
    /// mozc's own session state machine is actually cycling through
    /// right now (bounded to `CandidateWindow.pageSize`, 9 by default).
    ///
    /// M3b (#14) switched this to `Output.allCandidateWords` instead, on
    /// the theory that its indices line up with `candidateWindow.
    /// focusedIndex` across page boundaries, avoiding a re-implementation
    /// of mozc's page-flip UI. That held for Down-key navigation
    /// (verified against "こうしょう") but turned out **not** to hold in
    /// general (#21): Space (conversion) and Down (prediction) cycle
    /// through *different* candidate sets in mozc, of different sizes —
    /// for one short reading, allCandidateWords reported 11 entries
    /// while Space's own focusedIndex only ever reached 6 of them
    /// before wrapping. The list rendered candidates the user could
    /// never actually select. `candidateWindow.candidate` doesn't have
    /// that risk: it's definitionally whatever the *current* navigation
    /// mode is cycling through, since it's the same field `focusedIndex`
    /// itself is reported against. The tradeoff is back to M3b's
    /// original problem (no continuous scroll across page boundaries —
    /// crossing one just swaps in the next page's candidates), which is
    /// the lesser bug of the two.
    func update(from output: Mozc_Commands_Output) {
        let focusedIndex = output.candidateWindow.hasFocusedIndex ? Int(output.candidateWindow.focusedIndex) : nil
        let subCandidateIndicatorIndex = output.candidateWindow.hasSubCandidateWindow ? focusedIndex : nil
        update(rawCandidates: output.candidateWindow.candidate, focusedIndex: focusedIndex, subCandidateIndicatorIndex: subCandidateIndicatorIndex)
    }

    /// Renders a cascading sub-candidate window (`CandidateWindow.
    /// subCandidateWindow` — half/full-width variants under "そのほかの
    /// 文字種" and similar) in place of the parent list. mozc has no
    /// keyboard-navigable protocol support for these (see
    /// `NagiInputController`'s sub-candidate handling), so `focusedIndex`
    /// here is `NagiInputController`'s own locally-tracked position, not
    /// anything mozc reported.
    func updateSubCandidates(_ subCandidates: [Mozc_Commands_CandidateWindow.Candidate], focusedIndex: Int) {
        // Sub-candidate windows don't themselves nest further sub-
        // candidate windows, so there's never a "▶" hint to show here.
        update(rawCandidates: subCandidates, focusedIndex: focusedIndex, subCandidateIndicatorIndex: nil)
    }

    /// M4 (#19): renders `:`-triggered shortcode search results — see
    /// EmojiShortcodeDictionary and NagiInputController's shortcode-mode
    /// handling. Not backed by any mozc `Output`, so there's no
    /// `Candidate.index`/`.id` to reuse; the array position itself is a
    /// fine stand-in since this list is always rebuilt from scratch on
    /// every buffer change. Always `isPictograph: true` so
    /// `CandidateListView` renders it with the same grid layout M3d
    /// (#16) built for mozc's own emoji/kaomoji candidates, and never
    /// `hasSubCandidates` — a shortcode match is a plain emoji, nothing
    /// cascades from it.
    func updateShortcodeCandidates(_ emoji: [String], focusedIndex: Int?) {
        candidates = emoji.enumerated().map { index, text in
            Candidate(id: index, text: text, isPictograph: true, hasSubCandidates: false)
        }
        focusedID = focusedIndex
    }

    private func update(rawCandidates: [Mozc_Commands_CandidateWindow.Candidate], focusedIndex: Int?, subCandidateIndicatorIndex: Int?) {
        candidates = rawCandidates.map {
            Candidate(
                id: Int($0.index),
                text: $0.value,
                isPictograph: Self.isPictograph($0.annotation.description_p),
                hasSubCandidates: Int($0.index) == subCandidateIndicatorIndex
            )
        }
        focusedID = focusedIndex
    }

    private static func isPictograph(_ description: String) -> Bool {
        description.hasPrefix("絵文字") || description.hasPrefix("顔文字")
    }
}
