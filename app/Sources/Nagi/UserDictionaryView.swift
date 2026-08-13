// UserDictionaryView — #40: 設定ウィンドウ内のユーザー辞書タブ。
//
// 追加専用の入力行 + 一覧（削除のみ、行内編集はしない——理由は
// UserDictionaryStore.add/remove のドキュメント参照）というごく単純な
// 構成。エントリが変わるたび `UserDictionaryStore.push()` で mozc へ
// 全件送り直す。
//
// 追加行と一覧行は同じ `Grid` の中の GridRow として並べてある——
// 別コンテナ（GroupBox のカードと List）に分けていた前バージョンは、
// それぞれが独立に列幅を決めるせいで「よみ・単語・品詞」の列が追加行
// と一覧行とで揃わなかった。Grid は列幅を全 GridRow 横断で揃えて
// くれるので、この問題はコンテナを 1 つにまとめるだけで解決する
// （macOS 13+ の Grid API — Package.swift の platforms 指定を満たす）。

import SwiftUI

struct UserDictionaryView: View {
    @ObservedObject private var store = UserDictionaryStore.shared

    @State private var newReading = ""
    @State private var newWord = ""
    @State private var newPartOfSpeech: UserDictionaryPartOfSpeech = .noun
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("よみ")
                        Text("単語")
                        Text("品詞")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // よみ・単語は `.frame(maxWidth: .infinity)` を持つ
                    // セルが列にあるとその列が可変幅になる、という Grid
                    // の挙動を使ってウィンドウ幅に追従させている。品詞・
                    // ボタン列は内容量が決まっているので最小幅のみ。
                    GridRow {
                        TextField("ひらがな", text: $newReading)
                            .frame(minWidth: 110, maxWidth: .infinity)
                        TextField("単語", text: $newWord)
                            .frame(minWidth: 110, maxWidth: .infinity)
                        Picker("", selection: $newPartOfSpeech) {
                            ForEach(UserDictionaryPartOfSpeech.allCases) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .labelsHidden()
                        // 列揃えのため視覚ラベルは上のヘッダー行「品詞」
                        // に譲って `.labelsHidden()` にしているが、
                        // VoiceOver 用の名前まで消えてしまっていたので
                        // 明示的に補う。
                        .accessibilityLabel("品詞")
                        .frame(minWidth: 130)
                        Button("追加", action: addEntry)
                            .disabled(newReading.isEmpty || newWord.isEmpty)
                            .gridColumnAlignment(.trailing)
                    }

                    // #40 の調査コメントの制約: ASCII だけのよみは
                    // ローマ字→ひらがな変換の preedit と一致しないため
                    // 事実上ヒットしない。登録自体は止めず、ここで
                    // 気づけるようにするだけ。
                    if !newReading.isEmpty && newReading.allSatisfy(\.isASCII) {
                        GridRow {
                            Text("よみが半角英数字のみだと、日本語入力中には一致しません。")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .gridCellColumns(4)
                        }
                    }

                    Divider()
                        .gridCellColumns(4)
                        .padding(.vertical, 2)

                    if store.entries.isEmpty {
                        GridRow {
                            Text("登録された単語はありません。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .gridCellColumns(4)
                        }
                    }

                    ForEach(store.entries) { entry in
                        GridRow {
                            HStack(spacing: 4) {
                                Text(entry.reading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if entry.readingLooksUnconvertible {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                        // `.help` はマウスホバー時のツール
                                        // チップで、VoiceOver には読まれ
                                        // ない——読み上げ用のラベルは
                                        // 別に必要。
                                        .help("よみが半角英数字のみのため、日本語入力中には一致しません。")
                                        .accessibilityLabel("よみが半角英数字のみのため、日本語入力中には一致しません")
                                }
                            }
                            Text(entry.word)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(entry.partOfSpeech.displayName)
                                .foregroundStyle(.secondary)
                            // macOS の List は iOS と違いスワイプ削除が
                            // なく、`.onDelete` だけでは削除する手段が
                            // 事実上見えない状態になっていた——行ごとに
                            // 明示的な削除ボタンを置く。アイコンのみの
                            // ボタンは VoiceOver では「ゴミ箱、ボタン」
                            // としか読まれずどの行の削除か伝わらない
                            // ため、対象の単語を含むラベルを明示する。
                            Button {
                                removeEntry(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("「\(entry.word)」を削除")
                            .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .padding(8)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func addEntry() {
        let entry = UserDictionaryEntry(reading: newReading, word: newWord, partOfSpeech: newPartOfSpeech)
        store.add(entry)
        newReading = ""
        newWord = ""
        newPartOfSpeech = .noun
        pushToMozc()
    }

    private func removeEntry(_ entry: UserDictionaryEntry) {
        guard let index = store.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        store.remove(at: IndexSet(integer: index))
        pushToMozc()
    }

    private func pushToMozc() {
        Task {
            do {
                try await store.push()
                statusMessage = "ユーザー辞書を更新しました。"
            } catch {
                statusMessage = "ユーザー辞書の更新に失敗しました: \(error)"
            }
        }
    }
}
