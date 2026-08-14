// NagiSettings — nagi's own (non-mozc) settings.
//
// #39: a process-wide singleton reading/writing UserDefaults directly,
// same pattern (.shared) as RecentEmojiStore/EmojiShortcodeDictionary.
// The settings window and the candidate window run in the same process,
// so @Published changes reach both immediately — no cross-process sync
// needed. This is a separate store from mozc-originated settings
// (outside NagiSettings' scope, kept in config1.db via MozcClient).

import Combine
import Foundation

final class NagiSettings: ObservableObject {

    static let shared = NagiSettings()

    private enum Keys {
        static let candidateFontSize = "NagiCandidateFontSize"
    }

    static let defaultCandidateFontSize: Double = 15
    /// Lower bound is roughly the smallest still-legible glyph size;
    /// upper bound keeps the candidate window from growing unreasonably
    /// wide. Neither is measured — both are common-sense values.
    static let candidateFontSizeRange: ClosedRange<Double> = 11...24

    private let defaults: UserDefaults

    /// Font size for CandidateListView's candidate text. Defaults to the
    /// value that was previously hardcoded (15pt), so the look is
    /// unchanged until the user actually opens the settings window.
    @Published var candidateFontSize: Double {
        didSet {
            defaults.set(candidateFontSize, forKey: Keys.candidateFontSize)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Keys.candidateFontSize) as? Double
        let raw = stored ?? Self.defaultCandidateFontSize
        self.candidateFontSize = Swift.min(
            Swift.max(raw, Self.candidateFontSizeRange.lowerBound),
            Self.candidateFontSizeRange.upperBound
        )
    }
}
