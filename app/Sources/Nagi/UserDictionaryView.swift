// UserDictionaryView — #40: the "user dictionary" tab in the settings
// window.
//
// A very simple shape: an add-only input row plus a list (delete only,
// no inline editing — see UserDictionaryStore.add/remove's doc comment
// for why). `UserDictionaryStore.push()` re-sends the full set to mozc
// on every change.
//
// The add row and the list rows live as GridRows in the same `Grid` —
// an earlier version split them into separate containers (a GroupBox
// card and a List), each computing its own column widths independently,
// which meant the よみ/単語/品詞 columns didn't line up between the add
// row and the list below it. Grid keeps column widths consistent across
// every GridRow, so merging both into one container solves that
// (macOS 13+ Grid API — within Package.swift's platform requirement).

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

                    // Reading/word cells carry `.frame(maxWidth:
                    // .infinity)`, which is what makes Grid treat their
                    // column as flexible and grow with the window —
                    // POS/button columns have fixed, known content sizes
                    // so they only need a minimum width.
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
                        // The visible label is deferred to the "品詞"
                        // header row above for column alignment, via
                        // `.labelsHidden()` — but that also drops the
                        // VoiceOver name, so it's restored explicitly
                        // here.
                        .accessibilityLabel("品詞")
                        .frame(minWidth: 130)
                        Button("追加", action: addEntry)
                            .disabled(newReading.isEmpty || newWord.isEmpty)
                            .gridColumnAlignment(.trailing)
                    }

                    // Constraint noted in #40's investigation comment: a
                    // reading made of nothing but ASCII can never match
                    // during romaji→hiragana conversion. Registration
                    // itself isn't blocked — this is just a heads-up.
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
                                        // `.help` is a mouse-hover
                                        // tooltip only — VoiceOver never
                                        // reads it, so an explicit
                                        // accessibility label is needed
                                        // too.
                                        .help("よみが半角英数字のみのため、日本語入力中には一致しません。")
                                        .accessibilityLabel("よみが半角英数字のみのため、日本語入力中には一致しません")
                                }
                            }
                            Text(entry.word)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(entry.partOfSpeech.displayName)
                                .foregroundStyle(.secondary)
                            // Unlike iOS, macOS's List has no swipe
                            // gesture, so `.onDelete` alone left no
                            // actually visible way to delete a row — an
                            // explicit delete button per row instead. An
                            // icon-only button reads to VoiceOver as
                            // just "trash, button" with no way to tell
                            // which row it belongs to, hence the
                            // explicit label naming the entry.
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
