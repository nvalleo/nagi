// NagiSettings — nagi 独自の設定値。
//
// #39: UserDefaults に直接読み書きするプロセス内シングルトンとして、
// RecentEmojiStore/EmojiShortcodeDictionary と同じパターン（.shared）
// を踏襲する。設定ウィンドウと候補ウィンドウは同一プロセス内で動くの
// で、@Published の変更は両方に即座に伝わり、プロセス間同期の仕組み
// は要らない — mozc 由来の設定（NagiSettings.mozc の管轄外、
// MozcClient 経由で config1.db に持つ）とは保存先が分かれる。

import Combine
import Foundation

final class NagiSettings: ObservableObject {

    static let shared = NagiSettings()

    private enum Keys {
        static let candidateFontSize = "NagiCandidateFontSize"
    }

    static let defaultCandidateFontSize: Double = 15
    /// 下限はグリフが判読できる最小値、上限は候補ウィンドウが横に暴れ
    /// ない範囲——どちらも実測ではなく常識的な値。
    static let candidateFontSizeRange: ClosedRange<Double> = 11...24

    private let defaults: UserDefaults

    /// CandidateListView の候補テキストのフォントサイズ。デフォルト値
    /// は変更前の元々のハードコード値（15pt）と一致させてあるので、
    /// 未設定時の見た目は変わらない。
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
