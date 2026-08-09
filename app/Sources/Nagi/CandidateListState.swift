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

    func update(from window: Mozc_Commands_CandidateWindow) {
        candidates = window.candidate.map { Candidate(id: Int($0.index), text: $0.value) }
        focusedID = window.hasFocusedIndex ? Int(window.focusedIndex) : nil
    }
}
