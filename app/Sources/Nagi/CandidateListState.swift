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
    @Published private(set) var focusedID: Int?

    /// M3b (#14): reads from `Output.allCandidateWords`, not just
    /// `Output.candidateWindow.candidate` — the latter is whichever page
    /// mozc's own paginated UI last rendered (bounded to
    /// `CandidateWindow.pageSize`, 9 by default; the array itself is
    /// swapped out wholesale on page-forward/back, e.g. indices 0–8 become
    /// 9–17). `allCandidateWords` carries every candidate for the current
    /// conversion as one flat list with stable absolute indices — verified
    /// against `candidateWindow.focusedIndex`, which tracks that same
    /// absolute index across page boundaries — which is what lets
    /// `CandidateListView` scroll one continuous list instead of
    /// re-implementing mozc's page-flip UI. Falls back to
    /// `candidateWindow.candidate` for the rare category that doesn't
    /// populate `allCandidateWords`.
    func update(from output: Mozc_Commands_Output) {
        candidates = output.allCandidateWords.candidates.isEmpty
            ? output.candidateWindow.candidate.map {
                Candidate(id: Int($0.index), text: $0.value, isPictograph: Self.isPictograph($0.annotation.description_p))
            }
            : output.allCandidateWords.candidates.map {
                Candidate(id: Int($0.index), text: $0.value, isPictograph: Self.isPictograph($0.annotation.description_p))
            }
        focusedID = output.candidateWindow.hasFocusedIndex ? Int(output.candidateWindow.focusedIndex) : nil
    }

    private static func isPictograph(_ description: String) -> Bool {
        description.hasPrefix("絵文字") || description.hasPrefix("顔文字")
    }
}
