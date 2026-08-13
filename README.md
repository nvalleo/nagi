<p align="center">
  <img src="docs/images/icon.png" width="120" height="120" alt="Nagi icon — a sun over two calming waves">
</p>

<h1 align="center">nagi</h1>

<p align="center">
  A modern, lightweight Japanese IME for macOS — the conversion quality you<br>
  already know, in a new SwiftUI candidate window.
</p>

<p align="center">
  <a href="README-JP.md">🇯🇵 日本語</a> ・ 🇺🇸 English
</p>

<p align="center">
  <img alt="status: pre-alpha" src="https://img.shields.io/badge/status-pre--alpha-lightgrey">
  <img alt="platform: macOS" src="https://img.shields.io/badge/platform-macOS-black">
  <img alt="license: Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-blue">
</p>

---

## Contents

- [What it is](#what-it-is)
- [Features](#features)
- [Install](#install)
- [Uninstall](#uninstall)
- [Why another Japanese IME](#why-another-japanese-ime)
- [Architecture at a glance](#architecture-at-a-glance)
- [Performance targets](#performance-targets)
- [Development](#development)
- [License](#license)

## What it is

`nagi` is a macOS input method that reuses the Mozc conversion engine (the
open-source core of Google 日本語入力) and puts a native SwiftUI candidate
window on top of it. The engine ships inside the app bundle — no separate
Google 日本語入力 install required.

The name is 凪 — the calm, wind-free state of the sea, the moment when the
wind dies down and the water goes still. That is the input experience we
are aiming for: light, quiet, predictable.

## Features

- **A candidate window that never steals focus** — it's a non-activating
  panel, so the app you're typing into keeps input focus throughout
  conversion.

  ![Converting text in the candidate window](docs/images/candidate-window.gif)

- **`:`-triggered emoji shortcode search** — Slack/GitHub-style: type `:`
  followed by an English keyword to search emoji. Tab browses the full
  emoji list, and recently-used emoji surface first. Mozc's OSS build has
  no shortcode search of its own.

  ![Emoji shortcode search](docs/images/emoji-shortcode.gif)

## Install

```sh
curl -fsSL https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh | bash
```

- Asks for your admin password once (`/Library/Input Methods/` is a
  system folder)
- Launches Nagi automatically once it's done

> [!IMPORTANT]
> Then log out and back in once before typing with it. macOS only
> picks up a freshly-installed input method — in System Settings >
> Keyboard > Input Sources, the menu bar, and its conversion engine
> alike — at the next login, not immediately. No full restart needed,
> just a log out — the same one-time step Google 日本語入力 and other
> third-party macOS IMEs also require, not something `nagi` can skip.

<details>
<summary>Why a curl one-liner</summary>

This is a `curl | bash` one-liner — reasonable to want to read a script
before piping it into a shell, so `app/README.md`'s "Prebuilt download"
section has the download-then-read-then-run alternative.

It also replaced an earlier `.dmg`-based installer. Short version:
`nagi` is pre-alpha and unsigned/unnotarized — no paid Apple Developer
ID yet — and it turns out that combination makes a `.dmg` fundamentally
unable to open without a Terminal detour anyway, so the one-liner is
the more honest shape.

</details>

Prefer building it yourself instead? See [`app/README.md`](app/README.md)
for the full build-from-source steps.

## Uninstall

Double-click `Uninstall Nagi.app` in your Applications folder — Nagi
copies it there itself the first time it runs, so it's there whenever
you actually need it without the installer needing to do anything
extra. It asks for confirmation and your admin password, then removes
Nagi, stops its background process, and clears its entry from Input
Sources — no Terminal needed. It removes itself as the last step, once
everything else has succeeded — nothing left over to throw away by
hand.

> [!NOTE]
> An empty, unlabeled row can be left behind under the 日本語 (Japanese)
> group afterwards. It's harmless, and the uninstaller offers (but
> doesn't force) a restart to clear it.

(`install-nagi.sh` itself failed partway through, so Nagi never got to
run and never deployed that uninstaller? Remove
`/Library/Input Methods/Nagi.app` by hand in Finder instead, or use
`scripts/uninstall-ime.sh` from a clone of the repo.)

Built from source instead? `./scripts/uninstall-ime.sh --system` does
the file/process cleanup part — see [`app/README.md`](app/README.md)
for the rest.

## Why another Japanese IME

There is one product worth naming directly, because `nagi` exists
specifically to be a different frontend for it: **Google 日本語入力**, the
official Mozc-based IME on macOS. `nagi` runs the exact same conversion
engine — Mozc — so the difference is entirely in the surface:

| | Google 日本語入力 (official) | **nagi** |
|---|---|---|
| Conversion | Mozc | Mozc (bundled) |
| Candidate UI | 2010s design | Modern, SwiftUI |
| Extra install | — | none |
| Predictability | High | High |
| Memory | Low | Low |

`nagi` is not trying to be smarter than the engine — the engine is already
good. It is trying to be the frontend Mozc has been missing on macOS.

If neural / LLM-first conversion (Magic Conversions) is what you're after,
azooKey is the better fit. `nagi` is not a Mozc fork — we track upstream
`google/mozc` and only replace the renderer.

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
                 │ Mach IPC
┌────────────────▼───────────────────┐
│ mozc_server (bundled, C++,         │
│ rebranded "NagiConverter")         │
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

See [`poc/README.md`](poc/README.md) for the M0 proof-of-concept (Swift ↔
Mozc IPC) and [`app/README.md`](app/README.md) for the IMKit app itself —
build, install, and the `scripts/install-ime.sh` flow.

## License

Apache License 2.0 — see [LICENSE](LICENSE). Chosen for compatibility with
Mozc's BSD 3-Clause license and for its explicit patent grant.

Mozc itself remains under its original BSD 3-Clause license; the bundled
`mozc_server` binary and any Mozc-derived code carry that notice.
