// UserDictionaryEntry — #40: the model for a single user-dictionary
// entry, nagi's own.
//
// mozc's user_dictionary.PosType has 44 cases (down to individual verb
// conjugation classes by row/group), but only a handful of them see real
// use in everyday word registration — even Google 日本語入力's own word
// registration dialog doesn't expose the full set. Only 14 common cases
// are surfaced in the UI here, a deliberately curated subset (see #40's
// investigation comment; verb conjugation classes are out of scope,
// rarely useful for a personal dictionary).

import Foundation

enum UserDictionaryPartOfSpeech: String, Codable, CaseIterable, Identifiable {
    case noun
    case abbreviation
    case suggestionOnly
    case properNoun
    case personalName
    case familyName
    case firstName
    case organizationName
    case placeName
    case adjective
    case adverb
    case interjection
    case symbol
    case emoticon

    var id: String { rawValue }

    /// The literal string that goes in column 3 of mozc's TSV import
    /// format. `dictionary/user_dictionary_importer.cc` (ConvertEntry)
    /// matches this string against `PosType` — get even one character
    /// wrong and the whole line is silently dropped, so change these
    /// values with care.
    var mozcLabel: String {
        switch self {
        case .noun: "名詞"
        case .abbreviation: "短縮よみ"
        case .suggestionOnly: "サジェストのみ"
        case .properNoun: "固有名詞"
        case .personalName: "人名"
        case .familyName: "姓"
        case .firstName: "名"
        case .organizationName: "組織"
        case .placeName: "地名"
        case .adjective: "形容詞"
        case .adverb: "副詞"
        case .interjection: "感動詞"
        case .symbol: "記号"
        case .emoticon: "顔文字"
        }
    }

    /// The Picker's display name — same as `mozcLabel` today, kept as a
    /// separate property so a future non-Japanese-label display doesn't
    /// require touching call sites.
    var displayName: String { mozcLabel }
}

struct UserDictionaryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var reading: String = ""
    var word: String = ""
    var partOfSpeech: UserDictionaryPartOfSpeech = .noun

    /// A constraint noted in #40's investigation comment: input during
    /// conversion always goes through the romaji→hiragana preedit
    /// (MozcKeyEventMapping), so an entry whose reading is pure ASCII can
    /// never actually match what gets typed, no matter how it's typed.
    /// Registration itself isn't blocked on this — it's only used by
    /// UserDictionaryView to decide when to show a warning.
    var readingLooksUnconvertible: Bool {
        !reading.isEmpty && reading.allSatisfy(\.isASCII)
    }
}
