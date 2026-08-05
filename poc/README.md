# poc — M0: prove Swift can talk to Mozc

This directory contains the very first thing we have to prove, before writing
any IME code: **can a Swift program open Mozc's IPC socket, send an `Input`
message, and get back a candidate list.**

If the answer is yes, the rest of the roadmap is engineering. If the answer
is no, we go back to the drawing board.

## What's here

- `Package.swift` — Swift Package with SwiftProtobuf dependency.
- `Sources/NagiPoC/main.swift` — CLI entry point. Takes a romaji string,
  prints the returned candidates.
- `Sources/NagiMozcIPC/` — placeholder for the IPC transport layer.
- `Sources/NagiMozcProto/` — vendored Mozc protobufs. **Not checked in** —
  regenerated locally via the setup script below.

## Setup (macOS, one-time)

1. Install Xcode 15+ or the Swift toolchain (Swift 5.9+).
2. Install `protoc`:

   ```sh
   brew install protobuf
   ```

3. Fetch the Mozc protobufs. We pin to a specific tag so the wire format is
   stable:

   ```sh
   ./scripts/fetch-mozc-proto.sh
   ```

   (Script to be written in M0 — see the "Open questions" section below.)

4. Make sure Google 日本語入力 or a locally built `mozc_server` is running on
   this machine. The PoC does **not** launch its own server yet — that comes
   in M2. For now we piggyback on an existing one.

## Running

```sh
swift run nagi-poc konnnichiha
```

Expected output (rough shape):

```
preedit: こんにちは
candidates:
  0. こんにちは
  1. 今日は
  2. コンニチハ
  ...
```

## Open questions we expect to answer in M0

1. **Which Mozc tag do we pin to?** Latest tag on `master` at start of work,
   documented here once chosen.
2. **Socket path.** Google 日本語入力's `mozc_server` picks a socket path
   under `~/Library/Application Support/Google/JapaneseInput/` — needs to be
   confirmed by inspection.
3. **Message framing.** Mozc uses a length-prefixed protobuf frame; the exact
   header format lives in `src/ipc/ipc.h` and needs to be transcribed to
   Swift.
4. **`Input` shape for a bare romaji query.** The `commands.proto` `Input`
   message has many fields; we need to determine the minimal set for a
   conversion request.
5. **Session handshake.** Mozc requires a session id obtained via
   `CREATE_SESSION` before any `SEND_KEY` — the PoC needs to do that
   handshake.

Each of these is small on its own; the risk is that one of them turns out
to require reading a lot of Mozc source. That's precisely why we're doing
the PoC before the IME.

## Non-goals for M0

- No candidate window.
- No IMKit.
- No `mozc_server` bundling.
- No performance work.

The PoC is a CLI on purpose. Everything visual comes later.
