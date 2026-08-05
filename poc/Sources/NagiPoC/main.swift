// nagi PoC — M0
//
// Purpose: prove that Swift can drive Mozc's converter through its IPC
// protocol. Takes one romaji argument, prints preedit + candidates.
//
// Usage: swift run nagi-poc konnnichiha
//
// This file is intentionally small; the interesting work lives in
// NagiMozcIPC.

import Foundation
import NagiMozcIPC

@main
struct NagiPoC {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: nagi-poc <romaji>\n".utf8))
            exit(64) // EX_USAGE
        }

        let romaji = args[1]

        do {
            let client = try MozcClient()
            let sessionID = try await client.createSession()
            defer { Task { try? await client.deleteSession(sessionID) } }

            let result = try await client.sendRomaji(romaji, session: sessionID)

            print("preedit: \(result.preedit)")
            print("candidates:")
            for (i, candidate) in result.candidates.enumerated() {
                print("  \(i). \(candidate)")
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}
