# Roadmap

Four milestones. Each one has to end with something we can point at that
either works or definitively doesn't, before the next one starts.

## M0 — Prove Swift can talk to Mozc (1–2 weeks)

The single riskiest assumption in the whole plan. Do this before writing any
IME code.

- Fetch `commands.proto` and its dependencies from a pinned `google/mozc`
  tag.
- Generate Swift types with SwiftProtobuf.
- Write a small CLI that:
  - Launches an already-installed `mozc_server` (or an out-of-tree build).
  - Opens the IPC socket.
  - Sends an `Input` for the romaji sequence `konnnichiha`.
  - Prints the returned candidates.

**Exit criterion:** running `swift run nagi-poc konnnichiha` prints
`こんにちは` and a plausible candidate list on stdout. No IME involved yet.

Living in [`poc/`](../poc).

## M1 — Empty IME with committing text (2 weeks) — done

Get the IMKit skeleton into System Settings and let it write text into
TextEdit. No conversion yet — just prove we can hold the input mode.

- SwiftPM app target (no Xcode project — see [`app/README.md`](../app/README.md)),
  `LSUIElement = YES`.
- `IMKInputController` subclass.
- Romaji → hiragana table, commit-on-Enter.
- Install script that registers the IME with `~/Library/Input Methods/` or
  `/Library/Input Methods/`.

**Exit criterion:** typing `nagi<Enter>` in TextEdit inserts `なぎ`. **Confirmed
on the dev machine.**

Getting a bundle to actually register as a Text Input Source (as opposed to
just building and running) turned out to be the real risk in this milestone,
not the IMKit code itself — see
[docs/architecture.md](architecture.md#getting-registered-as-a-text-input-source-learned-the-hard-way-in-m1)
for the three silent requirements that took most of the milestone to find.

## M2 — Candidate window with Mozc backend (2–3 weeks) — done

The first real product moment. All keystrokes go through `mozc_server`, and
the candidate window is our own `NSPanel`.

Split in two once implementation made the remaining scope clearer:

- **M2a — done.** Real conversion end-to-end: `NagiInputController` forwards
  every key event to `mozc_server` over Mach IPC (not a Unix socket — the
  original bullet here was wrong, carried over from before M0; see
  docs/architecture.md, "Mozc IPC") and renders whatever `Output` comes
  back. `NSPanel` (`.nonactivatingPanel`, borderless, floating) hosts a
  SwiftUI candidate list, positioned under the caret via
  `attributesForCharacterIndex(_:lineHeightRectangle:)`. Space to open the
  candidate window, arrow keys to navigate, Enter to commit, Escape to
  cancel — all handled by `mozc_server`'s own session state machine, not
  reimplemented locally. Still piggybacks on an installed Google 日本語入力
  for the Converter service, same as the M0 PoC.
- **M2b — done, [#9](https://github.com/nv-leo/nagi/issues/9).** Nagi now
  bundles its own `mozc_server` (rebranded "NagiConverter") built from a
  pinned google/mozc tag via `scripts/build-mozc-server.sh` — Bazel
  cross-build (arm64 + x86_64, `lipo`'d together, same pattern as
  `build-app.sh` uses for Nagi itself) of just `//server:mozc_server_macos`,
  skipping the Qt/GUI-dependent parts of the upstream build entirely.
  Registered as its own launchd Mach service
  (`com.nvleo.inputmethod.nagi.Converter`) by `install-ime.sh`, replacing
  the Google 日本語入力 piggyback from M2a/M0. See
  `scripts/mozc-patches/nagi-branding.patch` for the two-line-looking but
  easy-to-half-do rebrand this needed — `config.bzl`'s
  `MACOS_BUNDLE_ID_PREFIX` only reaches `Info.plist`; the actual runtime
  Mach service name comes from a separate hardcoded constant in mozc's own
  `base/mac/mac_util.mm`.

**Exit criterion:** using nagi as the active IME, `konnnichiha` shows a
candidate window with `こんにちは` selectable, Enter commits it, **with no
other Mozc-based IME installed or running. Confirmed on the dev machine**
after actually uninstalling Google 日本語入力 — `NagiConverter` keeps
working with no logout/reboot needed, since it's an independent LaunchAgent
registration, not a Text Input Source registry change (that reboot
requirement, from M1, is a separate mechanism and still applies to Nagi's
own registration — see docs/architecture.md). Instruments Time Profiler
median key-to-paint within 16 ms — not yet measured.

Two issues found while dogfooding M2a, neither blocking: multi-segment
conversions don't visually distinguish the currently-active segment
([#7](https://github.com/nv-leo/nagi/issues/7)); a non-fatal kernel
`EXC_GUARD` (Mach port guard violation) was observed once under heavy IPC
load ([#8](https://github.com/nv-leo/nagi/issues/8)) — see
docs/architecture.md's "Mozc IPC" section for the manual port lifecycle
code involved.

If we miss 16 ms and can't recover it by profiling, we branch off M2.5 to
port the candidate view from SwiftUI to AppKit + `CAMetalLayer`. Decision
point at the end of M2, not before.

## M3 — Modern interaction (3–4 weeks) — done, one item descoped

The "why does this exist" milestone. This is where nagi has to stop looking
like Mozc-with-nicer-colours and start feeling like it was designed after
2015.

- **M3a — done, [#13](https://github.com/nv-leo/nagi/issues/13).** Selection
  highlight animates via spring, not step-change.
- **M3b — done, [#14](https://github.com/nv-leo/nagi/issues/14).** Vertical
  scroll for long candidate lists, `ScrollViewReader` keeps the selection in
  view.
- **M3c — descoped, [#15](https://github.com/nv-leo/nagi/issues/15).**
  Preview pane showing reading and meaning for the selected candidate.
  Investigated and closed without implementation: the OSS `google/mozc`
  build's usage dictionary (`usages`/`informationID`) is always empty —
  that data lives in a Google-internal dataset not shipped in the public
  source — so there is no "meaning/example" content to show. Revisit only
  if nagi ever bundles its own usage data (would be an M4+-scale effort).
- **M3d — done, [#16](https://github.com/nv-leo/nagi/issues/16).** Grid
  layout mode for emoji / kaomoji. Three dogfooding follow-ups found and
  fixed after merging: highlight getting stuck on a fixed candidate index
  for up to a page's worth of keystrokes
  ([#21](https://github.com/nv-leo/nagi/issues/21), a `mozc_server`
  `focusedIndex` hold-then-wrap behavior, not a nagi bug, but needed
  client-side detection to skip past), cascading "そのほかの文字種"
  sub-candidate windows being unselectable from the keyboard
  ([#22](https://github.com/nv-leo/nagi/issues/22), `SELECT_CANDIDATE` +
  `SUBMIT` is the only entry point mozc's protocol exposes for those), and
  the candidate window never being announced to VoiceOver since it
  intentionally never becomes key window
  ([#23](https://github.com/nv-leo/nagi/issues/23), fixed via
  `.announcementRequested`).

**Exit criterion:** internal dogfooding for a full workday without falling
back to Kotoeri. **Not formally tracked/confirmed** — dogfooding has been
ongoing throughout M3 (that's how #21/#22/#23 above were found) but no
single full-workday session has been explicitly logged as a pass.

## M4 — Extras & polish (open-ended)

The scope beyond M3 depends on how M0–M3 landed. Candidates:

- Local history UI (recent commits, per-app).
- Emoji panel with search — **first slice done,
  [#19](https://github.com/nv-leo/nagi/issues/19).** `:`-triggered emoji
  shortcode search (Slack/GitHub style): typing `:` starts narrowing emoji
  by name as you keep typing.
- App icon design — **done, [#25](https://github.com/nv-leo/nagi/issues/25).**
  Dock/Finder icon (`Nagi.icns`) and menu bar / Input Sources badge
  (`nagi.tiff`) both real artwork. The badge went through a follow-up,
  [#35](https://github.com/nv-leo/nagi/issues/35): it rendered as a blank
  square everywhere (menu bar and the Input Sources list row) until
  redrawn as an alpha-cutout — `TISIconIsTemplate` discards color and
  repaints from alpha alone. The list row re-reads its icon live; the
  menu bar badge doesn't — a changed icon there only takes effect after a
  real logout/login, not a relaunch.
- Optional LLM-backed suggestions via a local endpoint (keeping the
  no-network-by-default promise).
- Preferences pane (`mozc_tool`-style, but native).
- Signed and notarised `.pkg` distribution, Homebrew cask. (Not required
  just to *register* as a Text Input Source — M1 confirmed ad-hoc signing
  works fine for that — but still needed for Gatekeeper-friendly
  distribution to other people's machines.)

## Cross-platform (post-1.0)

Once macOS is stable and we know what the shared surface actually looks like,
factor the candidate window and Mozc IPC client into a Rust core and add
platform shims:

- Linux via a Fcitx5 addon.
- Windows via TSF.

Not before macOS 1.0. Building for three OSes on day one is how projects die.
