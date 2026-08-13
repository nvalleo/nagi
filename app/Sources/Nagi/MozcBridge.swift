// MozcBridge — synchronous facade over MozcClient's actor-isolated async
// API, for use from IMKit's synchronous callbacks.
//
// IMKInputController.handle(_:client:) must return a Bool synchronously
// on the calling thread — there's no async hook into IMKit's event
// dispatch. That's not actually a mismatch with what's underneath: a
// Mach IPC round trip (MozcClient+MachIPC.swift) is inherently
// synchronous blocking I/O with its own timeout; `MozcClient` only reads
// as `async` because it's an actor. This type bridges the two by running
// the actor call on a `Task` and blocking the caller on a semaphore,
// which is safe here because MozcClient never calls back into IMKit or
// anything else that could deadlock against the thread we're blocking.
//
// One MozcBridge (and one MozcClient) is shared process-wide; session
// IDs are owned per NagiInputController instance instead, matching one
// controller per IMKit client connection.

import Foundation
import NagiMozcIPC
import NagiMozcProto

enum MozcBridge {

    /// M2b: Nagi bundles its own mozc_server (rebranded "NagiConverter",
    /// see scripts/build-mozc-server.sh and issue #9) rather than
    /// piggybacking on another installed Mozc-based IME the way the M0
    /// PoC and M2a did. Its launchd Mach service name is rebranded to
    /// match — see scripts/mozc-patches/nagi-branding.patch's comment on
    /// why this has to be kept in sync with `kProjectPrefix` in mozc's
    /// own base/mac/mac_util.mm, not just its Info.plist bundle ID.
    static let converterServiceName = "com.nvleo.inputmethod.nagi.Converter.session"

    /// `MozcClient.init` is declared `throws` for API-shape reasons but
    /// never actually fails today (see its doc comment) — `try!`
    /// documents that rather than threading an unreachable error path
    /// through every call site.
    static let client: MozcClient = try! MozcClient(serviceName: converterServiceName)

    static func createSession() throws -> UInt64 {
        try runSync { try await client.createSession() }
    }

    static func deleteSession(_ id: UInt64) throws {
        try runSync { try await client.deleteSession(id) }
    }

    static func sendKey(_ keyEvent: Mozc_Commands_KeyEvent, session: UInt64) throws -> Mozc_Commands_Output {
        try runSync { try await client.sendKey(keyEvent, session: session) }
    }

    static func submit(session: UInt64) throws -> Mozc_Commands_Output {
        try runSync { try await client.submit(session: session) }
    }

    static func sendCommand(_ command: Mozc_Commands_SessionCommand, session: UInt64) throws -> Mozc_Commands_Output {
        try runSync { try await client.sendCommand(command, session: session) }
    }

    /// #39: settings window calls — unlike everything above, these run
    /// from a plain SwiftUI button action, not an IMKit synchronous
    /// callback, so there's no need to go through `runSync`'s
    /// semaphore-blocking bridge. Still funneled through `MozcBridge`
    /// (not `MozcClient` directly) so every Mozc IPC call in the app
    /// goes through one place.
    static func clearUserHistory() async throws {
        try await client.clearUserHistory()
    }

    static func clearUserPrediction() async throws {
        try await client.clearUserPrediction()
    }

    static func getConfig() async throws -> Mozc_Config_Config {
        try await client.getConfig()
    }

    static func setConfig(_ config: Mozc_Config_Config) async throws {
        try await client.setConfig(config)
    }

    /// #40: settings window's user dictionary editor pushes the whole
    /// dictionary on every change — see `UserDictionaryStore.push()` and
    /// `MozcClient.importUserDictionary`'s doc comment for why that's the
    /// intended usage, not wasted work.
    static func importUserDictionary(name: String, tsv: String) async throws {
        try await client.importUserDictionary(name: name, tsv: tsv)
    }

    private static func runSync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }
}

/// Plain mutable box to carry the `Task`'s result back across the
/// semaphore hand-off. `@unchecked Sendable` is safe here specifically
/// because `semaphore.wait()` below only returns after the `Task` body
/// has finished writing `result` and signaled — there's no concurrent
/// access, just a hand-off.
private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}
