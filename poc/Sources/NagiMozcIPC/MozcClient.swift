// MozcClient — thin Swift wrapper over Mozc's IPC.
//
// This file is a *skeleton*. The real work in M0 is to fill in the four
// TODOs below. Each TODO points at what needs to be figured out and where
// in the Mozc source to look.

import Foundation
// import NagiMozcProto  // enable once protos have been generated

/// One converter session with a running mozc_server.
public actor MozcClient {

    public struct ConversionResult: Sendable {
        public let preedit: String
        public let candidates: [String]
    }

    public enum MozcError: Error {
        case socketNotFound(path: String)
        case handshakeFailed(reason: String)
        case protocolError(String)
        case notImplemented(String)
    }

    // MARK: - Init

    public init() throws {
        // TODO(M0-1): locate the mozc_server IPC socket.
        //   Mozc's convention on macOS is a path under
        //   ~/Library/Application Support/Google/JapaneseInput/
        //   (for the official build) or a nagi-owned directory once we
        //   bundle our own server. See src/ipc/ in google/mozc.
    }

    // MARK: - Session lifecycle

    public func createSession() async throws -> UInt64 {
        // TODO(M0-2): send a CREATE_SESSION command, return the session id.
        //   The request/response shape lives in commands.proto ->
        //   Input/Output with input_type = CREATE_SESSION.
        throw MozcError.notImplemented("createSession")
    }

    public func deleteSession(_ id: UInt64) async throws {
        // TODO(M0-3): send DELETE_SESSION for the given id.
        throw MozcError.notImplemented("deleteSession")
    }

    // MARK: - Conversion

    public func sendRomaji(_ romaji: String, session: UInt64) async throws -> ConversionResult {
        // TODO(M0-4): translate the romaji string into a sequence of
        //   SEND_KEY commands, collect the resulting Output messages, and
        //   extract the current preedit + candidate list from the last
        //   Output. See how Mozc's own renderer clients do this in
        //   src/renderer/.
        throw MozcError.notImplemented("sendRomaji")
    }
}
