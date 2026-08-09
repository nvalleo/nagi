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
        candidates = output.candidateWindow.candidate.map {
            Candidate(id: Int($0.index), text: $0.value, isPictograph: Self.isPictograph($0.annotation.description_p))
        }
        focusedID = output.candidateWindow.hasFocusedIndex ? Int(output.candidateWindow.focusedIndex) : nil
    }

    private static func isPictograph(_ description: String) -> Bool {
        description.hasPrefix("絵文字") || description.hasPrefix("顔文字")
    }
}
