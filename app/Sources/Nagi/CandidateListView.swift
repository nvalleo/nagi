// CandidateListView — minimal SwiftUI candidate list.
//
// M2 scope only: a plain vertical list, focused candidate highlighted.
// No grid mode, no preview pane, no scroll — that's M3b/M3c/M3d (see
// docs/roadmap.md, issues #14/#15/#16). Visual design here is
// deliberately basic (system font, a material background, a highlight
// color) rather than invested in, since M3 revisits this file's
// contents wholesale.

import SwiftUI

struct CandidateListView: View {
    @ObservedObject var state: CandidateListState

    /// Shared identity for the highlight's `matchedGeometryEffect` — one
    /// namespace per list instance, not per row, so SwiftUI treats a
    /// focus change as the *same* highlight view moving between rows
    /// (a spring-animated slide) rather than one row's background
    /// fading out while another fades in.
    @Namespace private var highlightNamespace

    /// M3a (#13): was a step-change (`background(condition ? color :
    /// .clear)` with no animation) — the highlight jumped instantly
    /// between candidates instead of visibly tracking arrow-key
    /// movement.
    private static let highlightAnimation = Animation.spring(response: 0.28, dampingFraction: 0.82)

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
                .background {
                    if candidate.id == state.focusedID {
                        Color.accentColor.opacity(0.25)
                            .matchedGeometryEffect(id: "highlight", in: highlightNamespace)
                    }
                }
            }
        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize()
        .animation(Self.highlightAnimation, value: state.focusedID)
    }
}
