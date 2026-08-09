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

    /// `MozcClient.init` is declared `throws` for API-shape reasons but
    /// never actually fails today (see its doc comment) — `try!`
    /// documents that rather than threading an unreachable error path
    /// through every call site.
    static let client: MozcClient = try! MozcClient()

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
