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
    /// movement. A `matchedGeometryEffect` slide was tried first but
    /// conflicted with M3b's (#14) scrolling; a plain cross-fade doesn't
    /// have that per-row geometry coupling.
    private static let highlightAnimation = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// M3b/M3d follow-up (#14, #16, #21): earlier revisions rendered
    /// the *full* candidate list inside a `ScrollView` and called
    /// `ScrollViewReader.scrollTo(focusedID)` on every focus change to
    /// keep the highlight in view. That `scrollTo` turned out to be
    /// unreliable specifically in this app's setup — a `ScrollView`
    /// inside `NSHostingView`-hosted SwiftUI content floating in a
    /// plain `NSPanel`, not a normal SwiftUI window scene. Confirmed via
    /// file-based logging (Unified Logging/`NSLog` itself wasn't
    /// reaching `log stream` for this IMKit process, for reasons never
    /// pinned down) that `state.focusedID` advanced correctly and
    /// `scrollTo` was *called* on every single keystroke, all the way
    /// through a candidate list — yet the on-screen highlight still
    /// visibly froze partway through. Four different fixes aimed at
    /// *how* scrollTo was invoked (animated vs. not, `Grid` vs.
    /// `LazyVGrid`, deferring a runloop turn, skipping redundant
    /// `panel.setFrame` calls) all failed to change that.
    //
    // The fix here sidesteps the whole API rather than continuing to
    // chase it: instead of rendering everything and asking SwiftUI to
    // scroll to the focused one, `visibleRows` computes a bounded
    // *window* of rows around `focusedID` itself and only that window
    // is ever rendered. There's no scroll position for anything to fail
    // to update — "keeping the focused candidate in view" is just
    // "compute a slice that contains it", recomputed fresh on every
    // `focusedID` change like any other SwiftUI state.
    private static let maxVisibleRows: CGFloat = 10
    private static let approximateRowHeight: CGFloat = 25
    private static let maxListHeight = maxVisibleRows * approximateRowHeight

    /// `.frame(maxHeight:)` below caps the *content* height, but adding
    /// it (or `body`'s own ideal height) doesn't cap what
    /// `NSHostingView.fittingSize` reports — that API resolves SwiftUI's
    /// *ideal* size. `CandidateWindowController` has to clamp the panel
    /// to this explicitly. `outerPadding` accounts for the `.padding(4)`
    /// around the list itself (4pt top + 4pt bottom).
    static let outerPadding: CGFloat = 8
    static let maxPanelHeight = maxListHeight + outerPadding

    /// M3d (#16): emoji/kaomoji candidates (`Candidate.isPictograph`,
    /// see `CandidateListState`) render as fixed-size grid cells instead
    /// of full-width rows — a `9`-wide grid of 26pt glyphs reads far
    /// better than a scroll of one-per-line rows.
    private static let gridColumnCount = 9
    private static let gridCellSize: CGFloat = 26
    private static let gridRowHeight: CGFloat = gridCellSize + 4 // cell + vertical padding

    /// One visual row of the list: either a single plain-text candidate,
    /// or a full row of up to `gridColumnCount` pictograph candidates.
    /// `groupedCandidates`/`allRows` build these from `state.candidates`
    /// (see their docs); `visibleRows` windows them for `body`.
    private enum Row: Identifiable {
        case text(CandidateListState.Candidate)
        case grid([CandidateListState.Candidate])

        var id: Int {
            switch self {
            case .text(let candidate): return candidate.id
            case .grid(let candidates): return candidates.first?.id ?? -1
            }
        }

        var height: CGFloat {
            switch self {
            case .text: return CandidateListView.approximateRowHeight
            case .grid: return CandidateListView.gridRowHeight
            }
        }

        func contains(candidateID: Int) -> Bool {
            switch self {
            case .text(let candidate): return candidate.id == candidateID
            case .grid(let candidates): return candidates.contains { $0.id == candidateID }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleRows) { row in
                switch row {
                case .text(let candidate):
                    self.row(for: candidate)
                case .grid(let candidates):
                    pictographRow(candidates)
                }
            }
        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
        .animation(Self.highlightAnimation, value: state.focusedID)
    }

    /// Splits `state.candidates` into consecutive runs sharing the same
    /// `isPictograph` value, preserving order — e.g. for "かお":
    /// [顔, かお, カオ, 買お] (text) then [☠️, ☹️, ☺️, …] (pictograph).
    /// Candidates aren't pre-grouped by mozc itself (see
    /// `CandidateListState.Candidate.isPictograph`).
    private var groupedCandidates: [[CandidateListState.Candidate]] {
        state.candidates.reduce(into: [[CandidateListState.Candidate]]()) { groups, candidate in
            if groups.last?.first?.isPictograph == candidate.isPictograph {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
    }

    /// Flattens `groupedCandidates` into `Row`s: one `Row.text` per
    /// plain candidate, one `Row.grid` per `gridColumnCount`-sized chunk
    /// of a pictograph run.
    private var allRows: [Row] {
        groupedCandidates.flatMap { group -> [Row] in
            guard group.first?.isPictograph == true else {
                return group.map { .text($0) }
            }
            return stride(from: 0, to: group.count, by: Self.gridColumnCount).map { start in
                .grid(Array(group[start..<min(start + Self.gridColumnCount, group.count)]))
            }
        }
    }

    /// The window of `allRows` actually rendered: starts centered on
    /// whichever row contains `state.focusedID` and grows outward
    /// (alternating forward/backward) until it would exceed
    /// `maxListHeight`. Always includes the focused row when there is
    /// one. Falls back to the first `maxListHeight`'s worth of rows if
    /// nothing is focused yet (e.g. a suggestion list before the
    /// candidate window has been opened with Down/Tab/Space).
    private var visibleRows: [Row] {
        let rows = allRows
        guard let focusedID = state.focusedID,
            let focusedRowIndex = rows.firstIndex(where: { $0.contains(candidateID: focusedID) })
        else {
            var height: CGFloat = 0
            var end = 0
            while end < rows.count, height + rows[end].height <= Self.maxListHeight {
                height += rows[end].height
                end += 1
            }
            return Array(rows[0..<max(end, min(1, rows.count))])
        }

        var lowIndex = focusedRowIndex
        var highIndex = focusedRowIndex
        var height = rows[focusedRowIndex].height
        var growForward = true
        while height < Self.maxListHeight {
            if growForward, highIndex + 1 < rows.count {
                highIndex += 1
                height += rows[highIndex].height
            } else if !growForward, lowIndex > 0 {
                lowIndex -= 1
                height += rows[lowIndex].height
            } else if highIndex + 1 < rows.count {
                highIndex += 1
                height += rows[highIndex].height
            } else if lowIndex > 0 {
                lowIndex -= 1
                height += rows[lowIndex].height
            } else {
                break
            }
            growForward.toggle()
        }
        return Array(rows[lowIndex...highIndex])
    }

    @ViewBuilder
    private func pictographRow(_ candidates: [CandidateListState.Candidate]) -> some View {
        HStack(spacing: 4) {
            ForEach(candidates) { candidate in
                Text(candidate.text)
                    .font(.system(size: 20))
                    .frame(width: Self.gridCellSize, height: Self.gridCellSize)
                    .background(candidate.id == state.focusedID ? Color.accentColor.opacity(0.25) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(candidate.text)
                    .accessibilityAddTraits(candidate.id == state.focusedID ? [.isSelected] : [])
            }
            if candidates.count < Self.gridColumnCount {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
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
            if candidate.hasSubCandidates {
                // Visual cue that further variants (half/full-width
                // etc., under "そのほかの文字種" and similar) are one
                // more press away — only ever true for the focused row
                // (see CandidateListState.Candidate.hasSubCandidates),
                // so there's nothing to show on rows the user hasn't
                // reached yet.
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(candidate.id == state.focusedID ? Color.accentColor.opacity(0.25) : Color.clear)
        // VoiceOver doesn't pick this list up via normal focus-follows —
        // see CandidateWindowController.announceFocusChange for the
        // actual announcement. These traits/labels are still worth
        // setting for Rotor-based exploration and consistency with how
        // any other selectable list should describe itself.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(candidate.id + 1). \(candidate.text)" + (candidate.hasSubCandidates ? "、さらに選択肢あり" : ""))
        .accessibilityAddTraits(candidate.id == state.focusedID ? [.isSelected] : [])
    }
}
