# Architecture

This document captures the design decisions we already know we want to make,
and flags the ones we still have to prove out.

## The two-process split (inherited from Mozc)

Mozc, and Google 日本語入力 by extension, is architected as two processes that
talk over an IPC channel:

- **Converter / server** (`mozc_server`) — dictionary, statistical model,
  learning, session state. Written in C++. Deterministic, self-contained,
  and — importantly for us — completely decoupled from any UI.
- **Renderer** — the candidate window. In upstream Mozc this is where the
  legacy per-platform code lives (Win32, Cocoa, X11).

`nagi` keeps the split, replaces only the renderer, and ships an unmodified
`mozc_server` binary inside the app bundle. This means:

- We inherit the exact conversion quality of Mozc/Google 日本語入力.
- We can pull upstream Mozc fixes by rebuilding the bundled binary.
- The surface area we own is small: the IMKit shim, the IPC client, and the
  candidate window itself.

## Runtime layout on macOS

```
Nagi.app/
├── Contents/
│   ├── MacOS/
│   │   └── Nagi                    # IMKit host, Swift, foreground
│   ├── Resources/
│   │   └── NagiConverter.app       # our own mozc_server, rebranded (M2b)
│   └── Info.plist                  # declares InputMethodKit connection
```

No separate `mozc_tool`/`dictionary/` — the OSS build embeds the dictionary
data directly into the server binary (via Bazel genrules under
`data_manager/`), and we don't build or bundle the Qt-based `mozc_tool` GUI
at all (see `scripts/build-mozc-server.sh` — only
`//server:mozc_server_macos` is built, deliberately skipping everything
Qt-dependent).

The IPC endpoint is **not** a Unix domain socket on macOS, and Nagi does
**not** launch `NagiConverter` itself as a child process — see "Mozc IPC"
below, confirmed against upstream source and verified end-to-end in
[`poc/`](../poc) (M0) and now against our own bundled server (M2b). It's a
Mach bootstrap service: `install-ime.sh` registers a per-user LaunchAgent
(`com.nvleo.inputmethod.nagi.Converter`) declaring the service under
`MachServices`, and **launchd** — not Nagi — starts the `NagiConverter`
process on demand the first time any client calls `bootstrap_look_up` for
it, exactly like it does for Google 日本語入力's own Converter service
(which `poc/`'s M0 CLI still piggybacks on — a deliberate, useful
difference for a "does Mach IPC even work at all" PoC, not an oversight).

## OS integration: InputMethodKit

`IMKInputController` is the class every macOS IME derives from. It receives
key events, owns the client-side composition state, and is responsible for
committing text into the target application via `IMKTextInput`.

Two IMKit specifics matter for the design:

1. `IMKCandidates`, Apple's built-in candidate window, is **not** used. Its
   styling is fixed and does not give us the layout freedom the product is
   built around. We host our own `NSPanel` instead.
2. Caret geometry comes from
   `attributesForCharacterIndex(_:lineHeightRectangle:)`. This is the only
   documented way to place the candidate window under the caret across
   arbitrary apps.

### Getting registered as a Text Input Source (learned the hard way in M1)

A correctly-built, correctly-signed, non-crashing IMKit bundle can still be
completely invisible to System Settings — with zero errors anywhere. M1
spent most of its time on this, bisecting against every known-working IMKit
bundle available on the dev machine (Apple's own bundled
`/System/Library/Input Methods/AinuIM.app`, an installed Google 日本語入力,
a downloaded macSKK release). Three silent requirements came out of it:

1. **Must be a `release` build.** SwiftPM `debug` builds carry an
   auto-generated `com.apple.security.get-task-allow` entitlement, and a
   binary with that entitlement is never added to the Text Input Source
   registry — the process runs fine and even completes its XPC handshake
   with `imklaunchagent`, it just never becomes selectable.
2. **`CFBundleIdentifier` (and every `TISInputSourceID` under it) must
   contain the literal substring `.inputmethod.`.** Every working bundle we
   found used this token, and the literal string is embedded in
   `imklaunchagent`/HIToolbox's string table next to
   `ComponentInputModeDict`/`TISInputSourceID`. Bundle IDs without it are
   silently dropped regardless of anything else being correct — this is why
   nagi's bundle ID is `com.nvleo.inputmethod.nagi`, not the simpler
   `com.nvleo.nagi` floated in issue #1.
3. **Changes to the registry key (bundle ID, essentially) only take effect
   after a full reboot**, not a log out/in — the commonly-cited advice —
   and not by restarting `imklaunchagent`/`TextInputMenuAgent` by hand.

Full write-up, including the long list of things that turned out **not**
to matter (code-signing identity, hardened runtime, plist format, binary
architecture, icon presence, …) is in [`app/README.md`](../app/README.md).

## The candidate window

A borderless `NSPanel` (`.nonactivatingPanel`, floating level, non-key by
default) hosts a SwiftUI view. Rationale:

- `NSPanel` — because we need a floating, non-activating window that does not
  steal focus from the target app.
- SwiftUI for the tree — declarative layout, easy animation, cheap to iterate
  on visual design.
- If SwiftUI's paint latency turns out to exceed the 16 ms target, the
  fallback is AppKit + `CAMetalLayer` direct drawing. We defer that decision
  to measurement, not speculation.

The window content is not a single fixed layout. It swaps between:

- List view — default vertical candidate list.
- Grid view — for emoji / kaomoji categories.
- Preview pane — meaning / reading for the selected candidate.

## Mozc IPC

Mozc's client-side interface is defined in `protocol/commands.proto` (in
`google/mozc`). The message flow, simplified:

1. Client sends `Input` with the current preedit and key event.
2. Server responds with `Output` containing the updated preedit, candidate
   list, and any commit string.

**Transport is Mach IPC, not a Unix domain socket — updated after M0.** The
original plan here assumed a length-prefixed protobuf frame over a Unix
socket, following what `src/ipc/` looked like at a glance. That's true for
Linux (`unix_ipc.cc`, `#if defined(__linux__)`), but the mac build compiles
`mach_ipc.cc` instead (`#ifdef __APPLE__`), which is a completely different
transport:

1. `bootstrap_look_up(bootstrap_port, "<launchd label>.Converter.session",
   &port)` resolves the server's Mach bootstrap service, transparently
   starting it via launchd on first lookup if it isn't already running.
2. The client allocates a private receive port and sends a **complex Mach
   message** carrying one out-of-line (OOL) memory descriptor with the
   serialized `Input` bytes — the kernel handles framing/size, there is no
   length prefix to write. `msgh_id` is Mozc's `IPC_PROTOCOL_VERSION` (`3`),
   echoed back by the server.
3. The client blocks on its receive port for the `Output` reply, also
   delivered via an OOL descriptor.

We implement this in Swift using
[apple/swift-protobuf](https://github.com/apple/swift-protobuf) to generate
message types from the upstream `.proto` files, and a small system-library
shim (`CMozcMach`, see `poc/Sources/CMozcMach/`) exposing the Mach
bootstrap APIs Swift's `Darwin` module doesn't import by default. Verified
end-to-end against the installed Google 日本語入力 build in
[`poc/`](../poc); see `poc/README.md` "Surprises" for the full write-up,
including a Swift/Mach interop gotcha worth reading before touching this
code (stale struct-field reads after `mach_msg()` unless you take the
receive pointer over the whole message struct, not just its header field).

## Threading model

- IMKit callbacks run on the main thread; we keep them non-blocking.
- The IPC client owns a dedicated dispatch queue so socket reads never block
  the main thread.
- SwiftUI updates are marshalled back to the main actor.

## What we still have to prove

The following are the unresolved risks in this design, in rough order of
concern:

1. **IPC protocol stability.** `commands.proto` is treated as internal by
   Mozc. We pin to a specific upstream tag and re-verify on each bump.
   M0 confirmed Swift can drive the real (Mach-based, see "Mozc IPC" above)
   transport end-to-end against an installed Google 日本語入力 build — this
   risk is downgraded from "unproven" to "pin discipline going forward."
2. ~~**`mozc_server` bundling.**~~ **Resolved in M2b** ([#9](https://github.com/nv-leo/nagi/issues/9)).
   `scripts/build-mozc-server.sh` builds `//server:mozc_server_macos` for
   arm64 + x86_64 with Bazel (the Mozc project's own build system — GYP is
   deprecated upstream, never a live option) and `lipo`s them together.
   The one non-obvious part was rebranding the Mach service name — see
   `scripts/mozc-patches/nagi-branding.patch`.
3. **SwiftUI paint latency.** Whether we hit 16 ms consistently for the
   candidate window, especially the first-paint case after focus change.
4. **`IMKInputController` edge cases.** Focus loss, IME switch mid-composition,
   Space menu integration — the parts of IMKit that are famously
   underdocumented.

Each of these has a concrete first experiment in
[docs/roadmap.md](roadmap.md).
