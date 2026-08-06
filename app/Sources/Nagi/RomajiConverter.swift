// RomajiConverter — a small, self-contained romaji → hiragana table.
//
// M1 is explicitly scoped to *not* touch Mozc IPC (see docs/roadmap.md);
// real conversion quality comes from `MozcClient` in M2
// (poc/Sources/NagiMozcIPC/, proven out in M0). This is just enough to
// prove the IMKit skeleton can hold an input mode and commit text — a
// plain greedy table, no dictionary, no candidates.

enum RomajiConverter {

    /// Converts a buffer of typed romaji into hiragana on a best-effort,
    /// greedy basis. Trailing romaji that doesn't yet form a complete mora
    /// (e.g. a lone consonant waiting for its vowel) is left as-is, so the
    /// preedit shows the user what they've typed so far.
    static func convert(_ romaji: String) -> String {
        let chars = Array(romaji.lowercased())
        var result = ""
        var i = 0

        while i < chars.count {
            // Longest match first: 3-character youon combos (kya, sha, ...)
            // before 2-character morae before 1-character ones.
            if let match = longestTableMatch(chars, at: i) {
                result += match.kana
                i += match.length
                continue
            }

            // "nn" (or "n" followed by anything that isn't a vowel/y/n)
            // is the syllabic ん. This has to come after the table check
            // so "na", "ni", ... win first.
            if chars[i] == "n" {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if next == nil || !"aiueyn".contains(next!) {
                    result.append("ん")
                    i += 1
                    continue
                }
                if next == "n" {
                    result.append("ん")
                    i += 2
                    continue
                }
            }

            // Doubled consonant (kk, tt, ss, pp, ...) is the sokuon っ;
            // consume just the first consonant and keep going so the
            // second one still forms its own mora.
            if i + 1 < chars.count, chars[i] == chars[i + 1], !"aeiou".contains(chars[i]) {
                result.append("っ")
                i += 1
                continue
            }

            // Unrecognized / incomplete — surface the raw character so
            // the preedit isn't silently swallowed.
            result.append(chars[i])
            i += 1
        }

        return result
    }

    private static func longestTableMatch(_ chars: [Character], at index: Int) -> (kana: String, length: Int)? {
        for length in [3, 2, 1] where index + length <= chars.count {
            let key = String(chars[index..<(index + length)])
            if let kana = table[key] {
                return (kana, length)
            }
        }
        return nil
    }

    // Not exhaustive (no obsolete kana, limited youon coverage) — enough
    // for M1's "prove we can hold an input mode" bar.
    private static let table: [String: String] = [
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "sa": "さ", "si": "し", "shi": "し", "su": "す", "se": "せ", "so": "そ",
        "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "ta": "た", "ti": "ち", "chi": "ち", "tu": "つ", "tsu": "つ", "te": "て", "to": "と",
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "ha": "は", "hi": "ひ", "hu": "ふ", "fu": "ふ", "he": "へ", "ho": "ほ",
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "ya": "や", "yu": "ゆ", "yo": "よ",
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "wa": "わ", "wo": "を",
        "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ",
        "sha": "しゃ", "shu": "しゅ", "sho": "しょ",
        "ja": "じゃ", "ju": "じゅ", "jo": "じょ",
        "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",
        "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ",
        "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ",
        "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
        "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ",
        "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
        "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ",
        "-": "ー",
    ]
}
