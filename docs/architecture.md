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
│   │   ├── mozc_server             # bundled, launched on demand
│   │   ├── mozc_tool               # (optional) config / dictionary UI
│   │   └── dictionary/             # Mozc's system dictionary blobs
│   └── Info.plist                  # declares InputMethodKit connection
```

`mozc_server` is launched as a child process on first key event and kept alive
for the session. The IPC endpoint is a Unix domain socket under
`~/Library/Application Support/Nagi/ipc/`, following Mozc's convention.

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

We implement this in Swift using
[apple/swift-protobuf](https://github.com/apple/swift-protobuf) to generate
message types from the upstream `.proto` files, and a small hand-rolled
transport layer that speaks Mozc's socket framing (4-byte length prefix +
serialized protobuf, following `src/ipc/`).

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
2. **`mozc_server` bundling.** Building `mozc_server` for arm64 + x86_64 with
   the Mozc build system (Bazel-based, historically GYP) inside our release
   pipeline. Feasible, not trivial.
3. **SwiftUI paint latency.** Whether we hit 16 ms consistently for the
   candidate window, especially the first-paint case after focus change.
4. **`IMKInputController` edge cases.** Focus loss, IME switch mid-composition,
   Space menu integration — the parts of IMKit that are famously
   underdocumented.

Each of these has a concrete first experiment in
[docs/roadmap.md](roadmap.md).
