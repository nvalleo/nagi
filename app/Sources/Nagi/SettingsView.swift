// SettingsView — #39 の設定ウィンドウ「一般」タブの中身
// （SettingsRootView 参照。ユーザー辞書タブは #40 の UserDictionaryView）。
//
// NagiSettings.shared / RecentEmojiStore.shared を直接 @ObservedObject
// で観測する（既存の *.shared パターンを踏襲 — NagiSettings.swift 参照）。
// 依存を注入せず shared を直接見るのは、この View がプロセス内に一つ
// しかない SettingsWindowController からしか使われないため。
//
// mozc 由来の設定（`変換` セクション）は nagi 独自設定と保存先が違い
// （UserDefaults ではなく mozc の config1.db — MozcClient.getConfig/
// setConfig 参照）、`@State private var mozcConfig` にウィンドウを開く
// たびフェッチしたスナップショットを持つ。SET_CONFIG は Config を丸ごと
// 置き換えるプロトコルなので、常にこのスナップショットを起点に一部だけ
// 書き換えて送り返す read-modify-write になっている
// （`updateConfig(_:)` 参照）。

import NagiMozcProto
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = NagiSettings.shared

    /// リセット系ボタンの結果を伝えるだけの簡易な一過性メッセージ。
    /// 込み入った状態管理をするほどの価値がないため、Alert 等は使わず
    /// 1 行の Text で十分——数秒後に消すような仕掛けもあえて作らない
    /// (次の操作やウィンドウを閉じるまで残っていても実害がない)。
    @State private var statusMessage: String?

    /// `nil` はまだ取得できていない状態（起動直後、または取得失敗）。
    /// `変換` セクションはこれが埋まるまで操作不能にする——空の
    /// Config を仮に見せて操作させると、実際の現在値と食い違ったまま
    /// SET_CONFIG で上書きしてしまう事故につながる。
    @State private var mozcConfig: Mozc_Config_Config?

    /// `CandidateWindow.pageSize`（9、NagiInputController 冒頭のコメント
    /// 群で言及されている mozc プロトコル側の値）と同じ上限。1 未満は
    /// 候補が出せず意味をなさない。
    private static let suggestionsSizeRange: ClosedRange<Int> = 1...9

    var body: some View {
        Form {
            Section("候補ウィンドウ") {
                Slider(
                    value: $settings.candidateFontSize,
                    in: NagiSettings.candidateFontSizeRange,
                    step: 1
                ) {
                    Text("候補フォントサイズ")
                } minimumValueLabel: {
                    Text("小")
                } maximumValueLabel: {
                    Text("大")
                }
                Text("\(Int(settings.candidateFontSize)) pt")
                    .foregroundStyle(.secondary)
            }

            Section("変換") {
                if let mozcConfig {
                    // トグルの説明は 1 行のラベルに () で埋め込まず、
                    // 短い名詞句＋グレーの補足キャプションという System
                    // Settings 側のトグルと同じ 2 段構成にしてある——
                    // ラベル本文の途中に括弧が挟まると、それが名詞句と
                    // 「を使う」のどちらへの注釈か一瞬迷う。
                    Toggle(isOn: incognitoModeBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("学習を無効化する")
                            Text("シークレットモード——変換履歴・入力予測の学習を保存しない")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("変換履歴の学習", selection: historyLearningLevelBinding) {
                        Text("学習する").tag(Mozc_Config_Config.HistoryLearningLevel.defaultHistory)
                        Text("固定（追加学習しない）").tag(Mozc_Config_Config.HistoryLearningLevel.readOnly)
                        Text("学習しない").tag(Mozc_Config_Config.HistoryLearningLevel.noHistory)
                    }
                    Toggle(isOn: useTypingCorrectionBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("入力補正を使う")
                            Text("タイプミスを自動修正する")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: suggestionsSizeBinding, in: Self.suggestionsSizeRange) {
                        Text("候補の最大表示数: \(mozcConfig.suggestionsSize)")
                    }
                } else {
                    Text("mozc の設定を取得しています…")
                        .foregroundStyle(.secondary)
                }
            }

            Section("履歴") {
                Button("最近使った絵文字をリセット") {
                    RecentEmojiStore.shared.clear()
                    statusMessage = "最近使った絵文字をリセットしました。"
                }
                Button("変換履歴と入力予測の学習をリセット") {
                    resetMozcHistory()
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await loadConfig()
        }
    }

    private func loadConfig() async {
        do {
            mozcConfig = try await MozcBridge.getConfig()
        } catch {
            statusMessage = "mozc の設定取得に失敗しました: \(error)"
        }
    }

    /// `mozcConfig` を書き換えて即座に画面に反映しつつ、mozc 側にも
    /// `SET_CONFIG` で push する——ここで読み書きするのは常に
    /// `mozcConfig`（直近の `getConfig()` スナップショット）で、
    /// mutate は差分 1 つだけを当てる形にすることで、他のフィールドを
    /// 意図せずデフォルト値に戻してしまう事故を避ける
    /// (`MozcClient.setConfig`のドキュメント参照)。
    private func updateConfig(_ mutate: (inout Mozc_Config_Config) -> Void) {
        guard var config = mozcConfig else { return }
        mutate(&config)
        mozcConfig = config
        Task {
            do {
                try await MozcBridge.setConfig(config)
            } catch {
                statusMessage = "設定の反映に失敗しました: \(error)"
            }
        }
    }

    private var incognitoModeBinding: Binding<Bool> {
        Binding(
            get: { mozcConfig?.incognitoMode ?? false },
            set: { newValue in updateConfig { $0.incognitoMode = newValue } }
        )
    }

    private var historyLearningLevelBinding: Binding<Mozc_Config_Config.HistoryLearningLevel> {
        Binding(
            get: { mozcConfig?.historyLearningLevel ?? .defaultHistory },
            set: { newValue in updateConfig { $0.historyLearningLevel = newValue } }
        )
    }

    private var useTypingCorrectionBinding: Binding<Bool> {
        Binding(
            get: { mozcConfig?.useTypingCorrection ?? false },
            set: { newValue in updateConfig { $0.useTypingCorrection = newValue } }
        )
    }

    private var suggestionsSizeBinding: Binding<Int> {
        Binding(
            get: { Int(mozcConfig?.suggestionsSize ?? 3) },
            set: { newValue in updateConfig { $0.suggestionsSize = UInt32(newValue) } }
        )
    }

    /// `CLEAR_USER_HISTORY` / `CLEAR_USER_PREDICTION` はどちらも
    /// NagiConverter 上の全セッション共通のストアに効くので、セッション
    /// ID を一切要らない（MozcClient/MozcClient+MachIPC 参照）。SwiftUI
    /// のボタンアクションは同期関数である必要はないので、
    /// `NagiInputController` のように `MozcBridge.runSync` を経由せず、
    /// ここから直接 `Task` で async 呼び出しする。
    private func resetMozcHistory() {
        Task {
            do {
                try await MozcBridge.clearUserHistory()
                try await MozcBridge.clearUserPrediction()
                statusMessage = "変換履歴と入力予測の学習をリセットしました。"
            } catch {
                statusMessage = "リセットに失敗しました: \(error)"
            }
        }
    }
}
