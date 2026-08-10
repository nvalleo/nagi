// EmojiShortcodeDictionary — M4 (#19): ":"-triggered emoji shortcode
// search, Slack/GitHub-style.
//
// Entirely client-side, independent of mozc — mozc's OSS build has no
// shortcode search of its own (confirmed while scoping #19: sending ":"
// to it just returns the fullwidth colon "：" as an ordinary conversion
// candidate). The keyword data comes from Unicode CLDR annotations
// (English + Japanese), built at fetch/build time by
// scripts/fetch-emoji-annotations.sh into app/Resources/emoji-
// shortcodes.json — see that script and generate-emoji-shortcode-
// dictionary.py for how the JSON itself is produced. Not vendored into
// git, same policy as NagiMozcProto's generated Swift.

import Foundation

final class EmojiShortcodeDictionary {

    /// One dictionary instance is plenty — the underlying data never
    /// changes at runtime, and NagiInputController creates one
    /// controller per IMKit client connection (see
    /// NagiInputController.sessionID's doc comment), so a shared
    /// instance avoids re-parsing the ~2 MB JSON per connection.
    static let shared = EmojiShortcodeDictionary()

    /// Caps how many emoji a single search can return. CandidateListView
    /// only ever renders a bounded window around the focused candidate
    /// (see its `visibleRows`), so this isn't about the UI — it's a
    /// backstop against a short, common query (e.g. a single letter)
    /// matching hundreds of entries and building a large Candidate array
    /// on every keystroke, for results the user would never actually
    /// scroll to in practice.
    private static let maxResults = 200

    private struct Entry {
        let emoji: String
        /// Pre-lowercased once at load time rather than per search —
        /// search() runs on every keystroke of the shortcode buffer.
        let lowercasedKeywords: [String]
    }

    private let entries: [Entry]

    private init() {
        entries = Self.loadEntries()
    }

    /// Emoji whose keywords include a prefix match for `query` (case-
    /// insensitive ASCII — see MozcKeyEventMapping, which is all
    /// shortcode-mode key input can be, per NagiInputController), in the
    /// dictionary's own order (Unicode's CLDR grouping — smileys,
    /// people, animals, ... — see generate-emoji-shortcode-
    /// dictionary.py). Empty query returns no results: NagiInputController
    /// only enters shortcode mode on ":" itself and doesn't search until
    /// at least one character follows it.
    func search(_ query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        var results: [String] = []
        for entry in entries {
            guard entry.lowercasedKeywords.contains(where: { $0.hasPrefix(lowered) }) else { continue }
            results.append(entry.emoji)
            if results.count >= Self.maxResults { break }
        }
        return results
    }

    /// All emoji in dictionary order (same Unicode CLDR grouping as
    /// `search`) — deliberately *not* capped by `maxResults`, unlike
    /// `search`. That cap exists to bound how much a single narrow
    /// *query* can match (e.g. one common letter matching hundreds of
    /// keyword entries); it doesn't apply here since this is a fixed-
    /// size, uncapped browse of the whole dictionary, and capping it
    /// would silently hide every emoji past the cutoff (confirmed: with
    /// the cap, browsing never reached "person bowing" — People & Body
    /// sorts well past Smileys & Emotion in CLDR order). Used by
    /// NagiInputController's Tab-to-browse entry point (#19 follow-up):
    /// pressing Tab on an empty query browses the full list instead of
    /// committing, making shortcode search discoverable as a browsable
    /// picker and not just a search box that only reacts once you start
    /// typing. `CandidateListView.visibleRows` windows this down to what
    /// actually renders, so passing the full list costs nothing there.
    var allEmoji: [String] {
        entries.map(\.emoji)
    }

    private static func loadEntries() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "emoji-shortcodes", withExtension: "json") else {
            NSLog("Nagi: emoji-shortcodes.json not found in bundle — shortcode search (#19) disabled")
            return []
        }
        struct RawEntry: Decodable {
            let emoji: String
            let keywords: [String]
        }
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode([RawEntry].self, from: data)
            return raw.map { Entry(emoji: $0.emoji, lowercasedKeywords: $0.keywords.map { $0.lowercased() }) }
        } catch {
            NSLog("Nagi: failed to load emoji-shortcodes.json: \(error) — shortcode search (#19) disabled")
            return []
        }
    }
}
