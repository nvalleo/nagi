// RecentEmojiStore — M4 (#19 follow-up): remembers emoji committed via
// shortcode search, most-recent-first, so Tab-to-browse (see
// NagiInputController.browseAllShortcodeCandidates) surfaces them ahead
// of the full dictionary instead of always starting from "Smileys &
// Emotion" in CLDR order.
//
// Backed by UserDefaults — small (bounded to maxRecents entries), so a
// property list round-trip on each commit is cheap, and it means the
// list survives the IME process restarting (switching input sources,
// logging out) rather than resetting every session.

import Foundation

final class RecentEmojiStore {

    static let shared = RecentEmojiStore()

    /// Bounded to roughly two grid rows (see CandidateListView.
    /// gridColumnCount = 9) worth of recents — enough to matter without
    /// the "recent" section itself growing long enough to bury the
    /// dictionary browse it's meant to save time over.
    private static let maxRecents = 18
    private static let userDefaultsKey = "NagiRecentShortcodeEmoji"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Most-recently-committed emoji first.
    var recentEmoji: [String] {
        defaults.stringArray(forKey: Self.userDefaultsKey) ?? []
    }

    /// Moves `emoji` to the front, deduplicating any earlier occurrence,
    /// and trims to `maxRecents`. Called from
    /// NagiInputController.commitShortcodeCandidate on every successful
    /// shortcode commit — not from commitShortcodeQueryAsLiteralText,
    /// since that path never actually selected an emoji.
    func record(_ emoji: String) {
        var list = recentEmoji
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        if list.count > Self.maxRecents {
            list.removeLast(list.count - Self.maxRecents)
        }
        defaults.set(list, forKey: Self.userDefaultsKey)
    }

    /// #39: 設定ウィンドウの「最近使った絵文字をリセット」から呼ばれる。
    /// mozc 側の履歴（CLEAR_USER_HISTORY 等）とは無関係な、この
    /// UserDefaults キーだけを消す。
    func clear() {
        defaults.removeObject(forKey: Self.userDefaultsKey)
    }
}
