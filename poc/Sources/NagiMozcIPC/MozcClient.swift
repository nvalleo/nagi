// MozcClient — thin Swift wrapper over Mozc's IPC.
//
// M0 finding: on macOS this is Mach IPC, not a Unix domain socket — see
// MozcClient+MachIPC.swift for the transport and poc/README.md for the
// write-up. This file owns the session/conversion protocol on top of it.

import Foundation
import NagiMozcProto

/// One converter session with a running mozc_server.
public actor MozcClient {

    public struct ConversionResult: Sendable {
        public let preedit: String
        public let candidates: [String]
    }

    public enum MozcError: Error, CustomStringConvertible, Sendable {
        case socketNotFound(path: String)
        case handshakeFailed(reason: String)
        case protocolError(String)
        case notImplemented(String)

        public var description: String {
            switch self {
            case .socketNotFound(let path):
                return "could not reach mozc_server: \(path)"
            case .handshakeFailed(let reason):
                return "session handshake failed: \(reason)"
            case .protocolError(let message):
                return "protocol error: \(message)"
            case .notImplemented(let what):
                return "not implemented: \(what)"
            }
        }
    }

    /// Mach bootstrap service name for mozc_server's session port.
    ///
    /// Hard-coded to the officially-installed Google 日本語入力 build for
    /// M0, per the issue's "piggyback" instruction — this is the label
    /// `GetMachPortName("session")` resolves to in mach_ipc.cc for that
    /// build (confirmed locally with `launchctl list | grep inputmethod`).
    /// Once nagi bundles its own mozc_server (M2), this becomes our own
    /// launchd label instead, and this constant goes away.
    public static let defaultServiceName = "com.google.inputmethod.Japanese.Converter.session"

    private let serviceName: String
    private let callTimeout: TimeInterval

    public init(
        serviceName: String = MozcClient.defaultServiceName,
        callTimeout: TimeInterval = 3.0
    ) throws {
        self.serviceName = serviceName
        self.callTimeout = callTimeout
    }

    // MARK: - Session lifecycle

    public func createSession() async throws -> UInt64 {
        var input = Mozc_Commands_Input()
        input.type = .createSession

        let output = try await call(input)
        guard output.hasID, output.id != 0 else {
            throw MozcError.handshakeFailed(reason: "CREATE_SESSION returned no session id")
        }
        return output.id
    }

    public func deleteSession(_ id: UInt64) async throws {
        var input = Mozc_Commands_Input()
        input.type = .deleteSession
        input.id = id
        _ = try await call(input)
    }

    // MARK: - Conversion

    public func sendRomaji(_ romaji: String, session: UInt64) async throws -> ConversionResult {
        var output = Mozc_Commands_Output()

        // One SEND_KEY per character, exactly like a physical keystroke.
        // The server's romaji-to-kana composer builds the hiragana preedit
        // incrementally; we only need the very last Output.
        for scalar in romaji.unicodeScalars {
            guard scalar.isASCII else {
                throw MozcError.protocolError(
                    "non-ASCII romaji input isn't supported in M0: \(scalar)"
                )
            }

            var input = Mozc_Commands_Input()
            input.type = .sendKey
            input.id = session
            var key = Mozc_Commands_KeyEvent()
            key.keyCode = scalar.value
            input.key = key

            output = try await call(input)
        }

        // SEND_KEY alone only ever produces a hiragana preedit — it does
        // not populate candidates. Converting (what pressing Space does)
        // is what turns that preedit into segments with a real candidate
        // list, which is what the exit criterion in issue #2 expects.
        var convert = Mozc_Commands_Input()
        convert.type = .sendKey
        convert.id = session
        var spaceKey = Mozc_Commands_KeyEvent()
        spaceKey.specialKey = .space
        convert.key = spaceKey

        output = try await call(convert)

        // The rendered candidate_window only carries whatever page of
        // candidates the (nonexistent, here) UI last scrolled to.
        // all_candidate_words is the flat, complete list the server
        // computed for this conversion — that's what CLI output should
        // show.
        let preedit = output.preedit.segment.map(\.value).joined()
        let candidates = output.allCandidateWords.candidates.map(\.value)
        return ConversionResult(preedit: preedit, candidates: candidates)
    }

    // MARK: - Direct key events (M2: IMKit / candidate window)

    /// Sends one raw key event through the session and returns the
    /// server's `Output` unmodified.
    ///
    /// Deliberately no bespoke keymap logic on our side: mozc_server's own
    /// session state machine (PRECOMPOSITION / COMPOSITION / CONVERSION)
    /// already implements what Space / arrow keys / Enter / Escape do —
    /// exactly like every other Mozc client (mac/mozc_imk_input_controller.mm
    /// included). The caller only has to render whatever `Output` says.
    public func sendKey(_ keyEvent: Mozc_Commands_KeyEvent, session: UInt64) async throws -> Mozc_Commands_Output {
        var input = Mozc_Commands_Input()
        input.type = .sendKey
        input.id = session
        input.key = keyEvent
        return try await call(input)
    }

    /// Forces the current composition to commit (`SessionCommand.SUBMIT`),
    /// equivalent to the user pressing Enter. Used when IMKit tears the
    /// composition down from outside (focus loss, IME switch) rather than
    /// from a key event we can just forward.
    public func submit(session: UInt64) async throws -> Mozc_Commands_Output {
        var input = Mozc_Commands_Input()
        input.type = .sendCommand
        input.id = session
        var command = Mozc_Commands_SessionCommand()
        command.type = .submit
        input.command = command
        return try await call(input)
    }

    // MARK: - Transport

    private func call(_ input: Mozc_Commands_Input) async throws -> Mozc_Commands_Output {
        let requestData: Data
        do {
            requestData = try input.serializedData()
        } catch {
            throw MozcError.protocolError("failed to serialize Input: \(error)")
        }

        let serverPort = try Self.lookUpConverterPort(serviceName: serviceName)
        let responseData = try machCall(requestData, serverPort: serverPort, timeout: callTimeout)

        do {
            return try Mozc_Commands_Output(serializedBytes: responseData)
        } catch {
            throw MozcError.protocolError("failed to parse Output: \(error)")
        }
    }
}
