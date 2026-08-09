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
            ? output.candidateWindow.candidate.map { Candidate(id: Int($0.index), text: $0.value) }
            : output.allCandidateWords.candidates.map { Candidate(id: Int($0.index), text: $0.value) }
        focusedID = output.candidateWindow.hasFocusedIndex ? Int(output.candidateWindow.focusedIndex) : nil
    }
}
