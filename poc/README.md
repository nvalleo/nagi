# poc — M0: prove Swift can talk to Mozc

**Status: M0 done.** `swift run nagi-poc konnnichiha` reliably prints a real
preedit and candidate list from the installed Google 日本語入力 converter.
See "Surprises" below before starting M1/M2 — the plan's IPC assumption in
[`docs/architecture.md`](../docs/architecture.md) was wrong for macOS in a
way that matters.

This directory contains the very first thing we have to prove, before writing
any IME code: **can a Swift program open Mozc's IPC channel, send an `Input`
message, and get back a candidate list.**

## What's here

- `Package.swift` — Swift Package with SwiftProtobuf dependency, plus a
  `CMozcMach` system-library target (see "Surprises").
- `Sources/NagiPoC/main.swift` — CLI entry point. Takes a romaji string,
  prints the returned candidates.
- `Sources/NagiMozcIPC/` — the IPC transport (`MozcClient+MachIPC.swift`)
  and session/conversion protocol (`MozcClient.swift`).
- `Sources/CMozcMach/` — system-library shim exposing `bootstrap_look_up`
  and the Mach message structs, which Swift's `Darwin` module doesn't
  import by default.
- `Sources/NagiMozcProto/` — vendored Mozc protobufs. **Not checked in** —
  regenerated locally via `scripts/fetch-mozc-proto.sh`.

## Setup (macOS, one-time)

1. Install Xcode 15+ or the Swift toolchain (Swift 5.9+). Verified against
   Swift 6.3.3 (Xcode 26 / macOS 26 "Tahoe" Command Line Tools).
2. Install `protoc` + `protoc-gen-swift`:

   ```sh
   brew install protobuf swift-protobuf
   ```

3. Fetch the Mozc protobufs. We pin to a specific tag so the wire format is
   stable:

   ```sh
   ./scripts/fetch-mozc-proto.sh
   ```

4. Make sure Google 日本語入力 (or a locally built `mozc_server`) is
   installed on this machine. `MozcClient` looks up the Converter's Mach
   service by name (see "Surprises") and doesn't launch it itself — launchd
   does that on first message, the same way it does for the real IME.

## Running

```sh
cd poc
swift run nagi-poc konnnichiha
```

Actual output (verified locally, ordering/candidate set will drift slightly
with dictionary updates):

```
preedit: こんにちは
candidates:
  0. こんにちは
  1. 今日は
  2. コンニチハ
  3. :-)
  4. こんにちは
  5. コンニチハ
  6. konnnichiha
  ...
```

## Answers to the open questions from planning

1. **Which Mozc tag do we pin to?** `3.34.6239` — latest tag on `google/mozc`
   `master` as of the start of M0. Recorded in
   `scripts/fetch-mozc-proto.sh`. The locally-installed Google 日本語入力
   build reports version `3.34.6260.1` — close enough that the protocol
   hasn't drifted; re-check on the next tag bump.
2. **Socket path.** There isn't one — see "Surprises" #1.
3. **Message framing.** Not a length-prefixed protobuf frame — see
   "Surprises" #1. It's a Mach message with an out-of-line (OOL) descriptor
   carrying the raw serialized protobuf bytes; the kernel handles framing.
4. **`Input` shape for a bare romaji query.** `type = SEND_KEY`, `id =
   <session>`, `key.key_code = <ASCII of each romaji character>` — one
   `Input` per keystroke, exactly like a physical key event. After typing
   the full string, one more `SEND_KEY` with `key.special_key = SPACE`
   triggers conversion (see "Surprises" #3 for why this step is required).
5. **Session handshake.** `CREATE_SESSION` with no other fields is enough.
   On macOS the session starts in `PRECOMPOSITION` state already (see
   `session/session.cc`, `Session::CreateContext` — the `#else // _WIN32`
   branch), so unlike Windows there's no need to send `key.activated = true`
   first.

## Surprises (read before starting M1/M2)

### 1. macOS Mozc does not use a Unix domain socket

This was the working assumption in `docs/architecture.md` and issue #1
("IPC is the standard Mozc `commands.proto` over a Unix domain socket").
**It's wrong for macOS.** Tracing `google/mozc`'s `src/ipc/BUILD.bazel`:
`unix_ipc.cc` is guarded by `#if defined(__linux__)`; `mach_ipc.cc` (guarded
by `#ifdef __APPLE__`) is what actually compiles in for the Mac build.

On macOS, Mozc registers a **Mach bootstrap service** via launchd — for the
installed Google 日本語入力 build, `com.google.inputmethod.Japanese.Converter.session`
(confirmed with `launchctl list | grep inputmethod`; the exact label is
built from `GetMachPortName("session")` in `mach_ipc.cc`, which is
`<product label>.Converter.session`). A client does:

1. `bootstrap_look_up(bootstrap_port, "<label>.Converter.session", &port)` —
   this also transparently starts the server via launchd if it isn't
   running yet, so there's no separate "launch the server" step.
2. Allocate a private receive port for the reply.
3. Send a **complex Mach message** with one out-of-line (OOL) memory
   descriptor holding the serialized `Input` bytes — no length prefix, the
   kernel carries the size. `msgh_id` is set to Mozc's
   `IPC_PROTOCOL_VERSION` (`3`, from `src/ipc/ipc.h`) and echoed back by the
   server so a reply can be told apart from noise on the same port.
4. Block-receive on that same port for the `Output` reply, also delivered
   as an OOL descriptor.

The `~/Library/Application Support/Google/JapaneseInput/.session.ipc` file
mentioned in issue #2 as a place to look for a socket path is a red
herring for macOS: it's a serialized `IPCPathInfo` (`src/ipc/ipc.proto`)
holding a session key/pid/version — used by other platforms' IPC, not
consulted by the Mach path at all. Don't spend time on it.

Implication for M2: when nagi bundles its own `mozc_server`, "start the
server and open the socket" becomes "register (as the server) or look up
(as the client) a Mach bootstrap service under our own launchd label,
declared in our own `.plist`." This is a materially different integration
than the Unix-socket design implied in `docs/architecture.md`; that doc's
"IPC" section needs a rewrite before M2, flagged here rather than done
inline in this PoC pass.

`Sources/CMozcMach/` is a small system-library shim exposing
`bootstrap_look_up` (declared in `<servers/bootstrap.h>`, not part of
Swift's default `Darwin` overlay) and the raw Mach message struct types.

### 2. A real Swift/Mach gotcha: stale struct-field reads after `mach_msg`

This one cost most of the debugging time and is worth flagging loudly for
whoever touches this code next.

`mach_msg()` takes a `UnsafeMutablePointer<mach_msg_header_t>` — from
Swift's point of view, a pointer to just the `header` field of our
`{header, body, data, count}` message struct. But the *kernel* writes the
received OOL descriptor straight into the memory following that pointer
(`.body`, `.data`, `.count` — fields Swift wasn't told the call could
touch). Getting a pointer via `withUnsafeMutablePointer(to: &msg.header)`
and then, after the call, reading `msg.data.address` / `msg.data.size`
compiles fine and returns **0 / nil every time** — not a crash, just
silently wrong data — because Swift's optimizer treats those sibling
fields as unmodified by a call it only granted `.header` access to.

This is *very* easy to miss: `mach_msg()` itself reports `KERN_SUCCESS`,
`msgh_id` round-trips correctly, and only the OOL payload fields read as
empty. Confirmed by dumping the raw bytes of the struct with
`withUnsafeBytes(of:)` right after the call — the real data (correct
address, `size: 10`, `descriptor_count: 1`) was sitting right there in
memory; only the typed field reads were lying.

Fix: take the pointer over the *whole* struct's bytes, not just `.header`:

```swift
let kr = withUnsafeMutableBytes(of: &receiveMessage) { raw -> kern_return_t in
    let headerPtr = raw.baseAddress!.assumingMemoryBound(to: mach_msg_header_t.self)
    return mach_msg(headerPtr, ...)
}
```

`withUnsafeMutableBytes(of:)` grants mutable access to the entire value, so
Swift correctly invalidates/re-reads `.body` / `.data` / `.count` afterward.
`MozcClient+MachIPC.swift` does this for both the send and receive calls.

Side note while debugging this: `mach_msg_ool_descriptor_t`'s LP64 layout
is `address, {deallocate,copy,pad1,type} bitfield, size` — `size` comes
*after* the bitfields, not right after `address` like the 32-bit variant
(`<mach/message.h>`, the `#if defined(__LP64__)` branch). Irrelevant if you
always go through the named Swift properties (the Clang importer gets the
real offsets right), but will mislead you if you ever hand-compute byte
offsets while debugging, like we did.

### 3. Candidates only show up after an explicit "convert" key

`SEND_KEY` events alone (typing `k`, `o`, `n`, ...) only ever build the
hiragana preedit via the romaji-to-kana composer — `Output.candidate_window`
and `Output.all_candidate_words` stay empty. A conversion has to be
explicitly triggered, exactly like a human pressing Space: send one more
`SEND_KEY` with `key.special_key = SPACE`. *That* response has both the
converted preedit segment and the full candidate list.

Also: the exit criterion's candidate list lives in
`Output.all_candidate_words` (a flat `CandidateList`), not
`Output.candidate_window` (which only reflects whatever page of candidates
a real candidate-window UI last scrolled to — empty here since there's no
UI in M0).

## Non-goals for M0 (unchanged)

- No candidate window.
- No IMKit.
- No `mozc_server` bundling — this PoC piggybacks on the installed Google
  日本語入力 build's Converter service.
- No performance work.

The PoC is a CLI on purpose. Everything visual comes later.
