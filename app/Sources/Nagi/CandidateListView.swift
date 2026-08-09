// CandidateListView — minimal SwiftUI candidate list.
//
// M2 scope only: a plain vertical list, focused candidate highlighted.
// No grid mode, no preview pane, no scroll/animation — that's M3 (see
// docs/roadmap.md). Visual design here is deliberately basic (system
// font, a material background, a highlight color) rather than invested
// in, since M3 revisits this file's contents wholesale.

import SwiftUI

struct CandidateListView: View {
    @ObservedObject var state: CandidateListState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(state.candidates) { candidate in
                HStack(spacing: 6) {
                    Text("\(candidate.id + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .trailing)
                    Text(candidate.text)
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    candidate.id == state.focusedID
                        ? Color.accentColor.opacity(0.25)
                        : Color.clear
                )
            }
        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }
}
