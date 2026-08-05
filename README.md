# nagi

> A modern, lightweight Japanese IME for macOS — the conversion quality you
> already know, in a candidate window that finally looks like it was made this
> decade.

**Status:** pre-alpha. Everything below is a plan.

## What it is

`nagi` is a macOS input method that reuses the Mozc conversion engine (the
open-source core of Google 日本語入力) and puts a native SwiftUI candidate
window on top of it. The engine ships inside the app bundle — no separate
Google 日本語入力 install required.

The name is 凪 — the calm, wind-free state of the sea. That is the input
experience we are aiming for: light, quiet, predictable.

## Why another Japanese IME

There are three neighbouring products worth naming, because `nagi` is
deliberately none of them:

| | Google 日本語入力 (official) | azooKey / Zenzai | **nagi** |
|---|---|---|---|
| Conversion | Mozc | Neural (Zenzai) | Mozc (bundled) |
| Candidate UI | Legacy (~2010) | Modern, SwiftUI | Modern, SwiftUI |
| Extra install | — | — | none |
| Predictability | High | Neural / variable | High |
| Memory | Low | Higher (model resident) | Low |
| Target user | Anyone | Users who want AI-flavoured input | Anyone who wants the classic Mozc feel with a modern UI |

`nagi` sits in the empty quadrant: **Mozc quality, modern UI, self-contained,
predictable.** It is not trying to be smarter than the engine — the engine is
already good. It is trying to be the frontend the engine has been missing on
macOS.

## Non-goals

- **Not** a neural / LLM-first IME. If you want Magic Conversions, use azooKey.
- **Not** an engineer-specialised IME. It should feel right for writers, office
  users, students — anyone typing Japanese.
- **Not** a Mozc fork. We track upstream `google/mozc` and only replace the
  renderer.
- **Not** cross-platform in v1. Linux and Windows are on the long-term
  roadmap, once the macOS core has stabilised.

## Architecture at a glance

```
┌────────────────────────────────────┐
│ macOS app (Swift, IMKit)           │
│   ┌────────────────────────────┐   │
│   │ IMKInputController         │   │
│   │  → routes keys, commits    │   │
│   └────────────┬───────────────┘   │
│                │                   │
│   ┌────────────▼───────────────┐   │
│   │ Candidate window (SwiftUI) │   │
│   │  NSPanel, non-activating   │   │
│   └────────────┬───────────────┘   │
│                │                   │
│   ┌────────────▼───────────────┐   │
│   │ Mozc IPC client (Swift +   │   │
│   │ SwiftProtobuf)             │   │
│   └────────────┬───────────────┘   │
└────────────────┼───────────────────┘
                 │ Unix domain socket
┌────────────────▼───────────────────┐
│ mozc_server (bundled, C++)         │
│   converter, dictionary, learning  │
└────────────────────────────────────┘
```

See [docs/architecture.md](docs/architecture.md) for the full write-up and
[docs/roadmap.md](docs/roadmap.md) for the milestone plan.

## Performance targets

- Key → candidate window paint: **≤ 16 ms** (1 frame) as the goal, **≤ 50 ms**
  as the hard cap.
- Resident memory (app + bundled `mozc_server`): **≤ 150 MB** typical.
- Cold start (first key after login): **≤ 300 ms** to first paint.

These are targets, not promises. They exist so we notice when a design choice
puts them at risk.

## Development

Nothing to build yet — the repository currently contains the plan and a
`poc/` scaffold. See [`poc/README.md`](poc/README.md) for the first thing to
try: getting Swift to speak Mozc's IPC protocol.

## License

Apache License 2.0 — see [LICENSE](LICENSE). Chosen for compatibility with
Mozc's BSD 3-Clause license and for its explicit patent grant.

Mozc itself remains under its original BSD 3-Clause license; the bundled
`mozc_server` binary and any Mozc-derived code will carry that notice.
