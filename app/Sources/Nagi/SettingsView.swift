// SettingsView — #39: contents of the settings window's "General" tab
// (see SettingsRootView; the user dictionary tab is #40's
// UserDictionaryView).
//
// Observes NagiSettings.shared / RecentEmojiStore.shared directly via
// @ObservedObject, following the existing *.shared pattern (see
// NagiSettings.swift). Injecting nothing and reading .shared directly is
// fine because this View is only ever used by the single
// SettingsWindowController instance in the process.
//
// mozc-originated settings (the "変換" section) live in a different
// store than nagi's own settings — not UserDefaults, but mozc's own
// config1.db (see MozcClient.getConfig/setConfig). `@State private var
// mozcConfig` holds a snapshot fetched when the window opens. SET_CONFIG
// replaces the whole Config proto, so every mutation here is a
// read-modify-write starting from that snapshot (see updateConfig(_:)).

import NagiMozcProto
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = NagiSettings.shared

    /// A lightweight, ephemeral message reporting the result of a reset
    /// button — not worth the complexity of an Alert; a single line of
    /// Text is enough, and there's no need to auto-dismiss it after a
    /// few seconds either (leaving it up until the next action or window
    /// close is harmless).
    @State private var statusMessage: String?

    /// `nil` means not fetched yet (just opened, or the fetch failed).
    /// The "変換" section stays disabled until this is populated —
    /// showing controls against a placeholder Config and letting the
    /// user act on it would risk overwriting the real current value with
    /// SET_CONFIG.
    @State private var mozcConfig: Mozc_Config_Config?

    /// Same upper bound as `CandidateWindow.pageSize` (9, already
    /// referenced in NagiInputController's header comments) — the mozc
    /// protocol's own limit. Below 1 there'd be no candidates to show.
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
                    // Toggle descriptions use a short noun-phrase label
                    // plus a gray caption underneath, matching how System
                    // Settings' own toggles are laid out — not a
                    // parenthetical stuffed mid-label. A parenthetical in
                    // the middle of a label makes it briefly ambiguous
                    // whether it's annotating the noun phrase or the verb
                    // that follows it.
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

    /// Mutates `mozcConfig` and reflects the change on screen right away,
    /// while also pushing it to mozc via SET_CONFIG. Always reads and
    /// writes `mozcConfig` (the most recent getConfig() snapshot), and
    /// `mutate` is meant to touch exactly one field at a time — that's
    /// what keeps this from accidentally resetting every other field to
    /// its proto default (see MozcClient.setConfig's doc comment).
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

    /// CLEAR_USER_HISTORY / CLEAR_USER_PREDICTION both act on state
    /// shared across every session on NagiConverter, so neither needs a
    /// session ID (see MozcClient/MozcClient+MachIPC). A SwiftUI button
    /// action doesn't need to be synchronous, so unlike
    /// NagiInputController this calls straight into `Task` rather than
    /// going through MozcBridge.runSync.
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
