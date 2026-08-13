// UserDictionaryStore — #40: nagi 側が真実の情報源として持つユーザー
// 辞書エントリの配列と、mozc への push。
//
// #40 の調査コメントで比較検討したとおり、OS のテキスト置換の自動
// 取り込みはしない（変更検知の口がない・ iCloud 同期で意図せず増減する
// ・ ASCII よみがひらがな変換中に一致しない、という 3 つの構造的な問題
// があるため）。nagi はこの配列だけを真実として持ち、変更のたびに
// 辞書名固定で全件を mozc へ push する——差分同期のロジックを持たない
// ことで実装・保守コストを最小化する設計判断（IMPORT_USER_DICTIONARY
// が同名辞書を丸ごと置換してくれるので、この単純化に対応できる）。

import Combine
import Foundation

final class UserDictionaryStore: ObservableObject {

    static let shared = UserDictionaryStore()

    /// mozc 側に作る辞書の名前は固定——nagi はユーザーに複数辞書を
    /// 選ばせる複雑さを持たない設計なので、常にこの 1 つだけを丸ごと
    /// 置き換える。
    static let mozcDictionaryName = "Nagi"

    private static let userDefaultsKey = "NagiUserDictionaryEntries"

    private let defaults: UserDefaults

    @Published private(set) var entries: [UserDictionaryEntry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.userDefaultsKey),
            let decoded = try? JSONDecoder().decode([UserDictionaryEntry].self, from: data)
        {
            entries = decoded
        }
    }

    /// 追加・削除のみで、既存エントリの更新はサポートしない——
    /// 編集したければ削除して登録し直す。この画面に求められている
    /// のは実装・保守コストの低さなので、行内編集の状態管理までは
    /// 持たせないという意図的なスコープ限定。
    func add(_ entry: UserDictionaryEntry) {
        entries.append(entry)
        persist()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    /// mozc の TSV インポート形式（よみ\t 単語\t 品詞）を組み立てる。
    /// タブ/改行がよみ・単語に混ざると列がずれるので取り除く——弾いて
    /// エラーにするより、少なくとも登録自体は通す方を選んだ（この
    /// フィールドは 1 行 TextField 入力なので通常は混入しない）。
    func buildTSV() -> String {
        entries.map { entry in
            let reading = entry.reading.replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
            let word = entry.word.replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
            return "\(reading)\t\(word)\t\(entry.partOfSpeech.mozcLabel)"
        }.joined(separator: "\n")
    }

    /// #40: 変更のたびに全件を mozc へ push する——差分計算をしない
    /// 設計（このファイル冒頭コメント参照）。戻り値のない非同期
    /// コマンドなので、成否は呼び出し元で実際に変換して確かめるしか
    /// ない（MozcClient.importUserDictionary のドキュメント参照）。
    func push() async throws {
        try await MozcBridge.importUserDictionary(name: Self.mozcDictionaryName, tsv: buildTSV())
    }
}
