// CandidateListView — minimal SwiftUI candidate list.
//
// M2 scope only: a plain vertical list, focused candidate highlighted.
// No preview pane — that's M3c, and out of scope entirely (#15: mozc's
// OSS build has no usage-dictionary data to show). Visual design here
// is deliberately basic (system font, a material background, a
// highlight color) rather than invested in, since M3 revisits this
// file's contents wholesale.

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

    /// M3d (#16): emoji/kaomoji candidates (`Candidate.isPictograph`,
    /// see `CandidateListState`) render as fixed-size grid cells instead
    /// of full-width rows — a `9`-wide grid of 26pt glyphs reads far
    /// better than a scroll of one-per-line rows. Fixed-size `GridItem`s,
    /// not `.flexible()`: a flexible column wants to fill "available"
    /// width, which under `NSHostingView.fittingSize`'s ideal-size
    /// resolution (unconstrained proposal — the same quirk documented on
    /// `maxPanelHeight` above) resolves to something absurdly wide
    /// instead of the panel's actual, content-driven width.
    private static let gridColumnCount = 9
    private static let gridCellSize: CGFloat = 26
    private static let gridColumns = Array(
        repeating: GridItem(.fixed(gridCellSize), spacing: 4),
        count: gridColumnCount
    )

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groupedCandidates.enumerated()), id: \.offset) { _, group in
                        if group.first?.isPictograph == true {
                            pictographGrid(for: group)
                        } else {
                            ForEach(group) { candidate in
                                row(for: candidate)
                            }
                        }
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

    /// Splits `state.candidates` into consecutive runs sharing the same
    /// `isPictograph` value, preserving order — e.g. for "かお":
    /// [顔, かお, カオ, 買お] (text) then [☠️, ☹️, ☺️, …] (pictograph).
    /// Candidates aren't pre-grouped by mozc itself (see
    /// `CandidateListState.Candidate.isPictograph`), so this has to be
    /// recomputed whenever the candidate list changes; it's cheap enough
    /// (at most a few dozen candidates per conversion) not to bother
    /// caching.
    private var groupedCandidates: [[CandidateListState.Candidate]] {
        state.candidates.reduce(into: [[CandidateListState.Candidate]]()) { groups, candidate in
            if groups.last?.first?.isPictograph == candidate.isPictograph {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
    }

    @ViewBuilder
    private func pictographGrid(for candidates: [CandidateListState.Candidate]) -> some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 4) {
            ForEach(candidates) { candidate in
                Text(candidate.text)
                    .font(.system(size: 20))
                    .frame(width: Self.gridCellSize, height: Self.gridCellSize)
                    .background(candidate.id == state.focusedID ? Color.accentColor.opacity(0.25) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .id(candidate.id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
