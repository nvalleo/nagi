// UserDictionaryStore — #40: the array of user-dictionary entries that
// nagi treats as the source of truth, plus pushing it to mozc.
//
// As weighed in #40's investigation comment, this deliberately does not
// auto-import macOS's own text replacements — there's no way to detect
// changes to them, iCloud sync can grow/shrink the list without the
// user's intent, and an ASCII reading never matches mid-conversion
// anyway. nagi treats this array alone as the source of truth and, on
// every change, pushes the full set to mozc under a fixed dictionary
// name — not diffing keeps the implementation and maintenance cost low
// (IMPORT_USER_DICTIONARY replaces the named dictionary wholesale, which
// is exactly what makes this simplification work).

import Combine
import Foundation

final class UserDictionaryStore: ObservableObject {

    static let shared = UserDictionaryStore()

    /// Fixed name for the dictionary created on the mozc side — nagi
    /// isn't designed to let the user manage multiple dictionaries, so
    /// there's always exactly this one, replaced wholesale each time.
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

    /// Add and remove only — updating an existing entry isn't supported;
    /// editing means deleting and re-adding. This screen's requirement is
    /// low implementation/maintenance cost, so it deliberately doesn't
    /// carry the state management an inline-editable row would need.
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

    /// Builds mozc's TSV import format (reading\tword\tPOS). Tabs/
    /// newlines are stripped from the reading/word first since they'd
    /// otherwise shift the columns — chosen over rejecting the entry as
    /// an error, so registration at least goes through (this field is a
    /// single-line TextField, so this shouldn't come up in practice).
    func buildTSV() -> String {
        entries.map { entry in
            let reading = entry.reading.replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
            let word = entry.word.replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
            return "\(reading)\t\(word)\t\(entry.partOfSpeech.mozcLabel)"
        }.joined(separator: "\n")
    }

    /// #40: pushes the full set to mozc on every change — no diffing, by
    /// design (see this file's header comment). This is an async command
    /// with no result reported back, so success can only be confirmed by
    /// actually converting afterward (see MozcClient.importUserDictionary's
    /// doc comment).
    func push() async throws {
        try await MozcBridge.importUserDictionary(name: Self.mozcDictionaryName, tsv: buildTSV())
    }
}
