// CandidateListView — minimal SwiftUI candidate list.
//
// M2 scope only: a plain vertical list, focused candidate highlighted.
// No grid mode, no preview pane — that's M3c/M3d (see docs/roadmap.md,
// issues #15/#16). Visual design here is deliberately basic (system
// font, a material background, a highlight color) rather than invested
// in, since M3 revisits this file's contents wholesale.

import SwiftUI

struct CandidateListView: View {
    @ObservedObject var state: CandidateListState

    /// M3a (#13): was a step-change (`background(condition ? color :
    /// .clear)` with no animation) — the highlight jumped instantly
    /// between candidates instead of visibly tracking arrow-key
    /// movement. Originally a sliding highlight via `matchedGeometryEffect`,
    /// but that turned out to conflict with M3b's (#14) `ScrollViewReader.
    /// scrollTo` once scrolling was involved — animating a matched-geometry
    /// move and a scroll offset change in the same transaction made the
    /// highlight visibly freeze once it had to cross a scroll. A plain
    /// cross-fade doesn't have that per-row geometry coupling, so it
    /// keeps working once the list scrolls.
    private static let highlightAnimation = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// M3b (#14): `state.candidates` now backs onto `Output.
    /// allCandidateWords` (see `CandidateListState.update(from:)`),
    /// which for a homophone-heavy reading can easily run into the
    /// dozens (76, for example, for "こうしょう") — rendered
    /// unconstrained, the panel would run off the bottom of the screen.
    /// Capping to roughly this many rows (a rough estimate from the row
    /// font/padding below, not pixel-measured — precision doesn't
    /// matter here since a partial row at the boundary is itself a
    /// useful "more below" affordance) keeps the panel a sane height;
    /// anything beyond it scrolls, and the scroll position tracks
    /// `focusedID` below. Deliberately not sized off the screen's own
    /// height (roadmap's "画面サイズに応じて") — out of scope for now,
    /// see the file header.
    private static let maxVisibleRows: CGFloat = 10
    private static let approximateRowHeight: CGFloat = 25
    private static let maxListHeight = maxVisibleRows * approximateRowHeight

    /// `.frame(maxHeight:)` below caps the *content* height, but adding
    /// it (or `body`'s own ideal height) doesn't cap what
    /// `NSHostingView.fittingSize` reports — that API resolves SwiftUI's
    /// *ideal* size, which for a `ScrollView` is its full unclipped
    /// content height, not the constrained one. `CandidateWindowController`
    /// has to clamp the panel to this explicitly and let the *actual*,
    /// smaller frame it then assigns force `ScrollView` to lay out (and
    /// therefore clip/scroll) within real bounds. `outerPadding` accounts
    /// for the `.padding(4)` around the list itself (4pt top + 4pt bottom).
    static let outerPadding: CGFloat = 8
    static let maxPanelHeight = maxListHeight + outerPadding

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(state.candidates) { candidate in
                        row(for: candidate)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: Self.maxListHeight)
            // Single-parameter onChange, not the two-parameter form: the
            // target here is macOS 13 (app/Package.swift), and the
            // two-parameter overload needs macOS 14.
            .onChange(of: state.focusedID) { focusedID in
                guard let focusedID else { return }
                withAnimation(Self.highlightAnimation) {
                    proxy.scrollTo(focusedID, anchor: .center)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
        .animation(Self.highlightAnimation, value: state.focusedID)
    }

    @ViewBuilder
    private func row(for candidate: CandidateListState.Candidate) -> some View {
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
        .background(candidate.id == state.focusedID ? Color.accentColor.opacity(0.25) : Color.clear)
        .id(candidate.id)
    }
}
