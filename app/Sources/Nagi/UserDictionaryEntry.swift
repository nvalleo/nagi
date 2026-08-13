// UserDictionaryEntry — #40: nagi 独自に保持するユーザー辞書エントリ
// 1 件分のモデル。
//
// mozc の user_dictionary.PosType は 44 種（動詞の行/段別活用まで
// 個別のケースを持つ）あるが、実際の単語登録でよく使われるものはごく
// 一部——Google 日本語入力の単語登録ダイアログ自体もフル網羅は
// していない。ここでは代表的な 14 種だけを UI に出す、意図的に絞った
// サブセットにしている（#40 の調査コメント参照。動詞活用クラスは
// 個人辞書用途での必要性が薄いため対象外）。

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

    /// mozc の TSV インポート形式の 3 列目に入る、そのままのリテラル。
    /// `dictionary/user_dictionary_importer.cc`（ConvertEntry）はこの
    /// 文字列を `PosType` にマッチさせるので、1 文字でも違うとその行は
    /// 黙って読み捨てられる——値を変えるときは要注意。
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

    /// Picker の表示名——現状は `mozcLabel` と同じでよいが、日本語
    /// ラベル以外の表示にしたくなった場合に呼び出し側を変えずに済む
    /// よう別プロパティとして分けてある。
    var displayName: String { mozcLabel }
}

struct UserDictionaryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var reading: String = ""
    var word: String = ""
    var partOfSpeech: UserDictionaryPartOfSpeech = .noun

    /// #40 の調査コメントの制約: 変換中の入力は常にローマ字→ひらがなの
    /// preedit を経由する（MozcKeyEventMapping）ため、よみが ASCII
    /// だけで構成されるエントリはどう打っても preedit と一致せず、
    /// 事実上ヒットしない。ここでは登録自体は止めず、
    /// UserDictionaryView 側で警告を出す判断材料としてだけ使う。
    var readingLooksUnconvertible: Bool {
        !reading.isEmpty && reading.allSatisfy(\.isASCII)
    }
}
