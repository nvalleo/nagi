# app — M1: empty IME with committing text

Get the IMKit skeleton into System Settings and let it write text into
TextEdit. No conversion yet (that's M2, via `MozcClient` — see
[`poc/`](../poc)) — this just proves nagi can hold an input mode.

## What's here

- `Package.swift` — plain SwiftPM executable target, no external deps.
  `Cocoa` / `InputMethodKit` are system frameworks and link implicitly.
- `Sources/Nagi/main.swift` — process entry point: stands up an
  `IMKServer` under the connection name declared in `Info.plist`, runs as
  an accessory (no dock icon) app.
- `Sources/Nagi/NagiInputController.swift` — the `IMKInputController`
  subclass. Buffers typed romaji, shows it as marked (underlined) text via
  `setMarkedText`, commits the converted hiragana via `insertText` on
  Enter.
- `Sources/Nagi/RomajiConverter.swift` — a small greedy romaji → hiragana
  table. Deliberately not Mozc — see the file header for why.
- `Resources/Info.plist` — the IMKit registration metadata (connection
  name, controller class, declared input mode). Cross-checked against
  google/mozc's own `mac/Info.plist` (`src/mac/Info.plist` upstream) to
  get the easy-to-get-wrong keys right.

## Why no `.xcodeproj`

Same reasoning as [`poc/`](../poc): this environment has Xcode's Command
Line Tools but not the Xcode GUI, and the project has been SwiftPM-based
since M0. An IMKit `.app` doesn't require Xcode — it just needs a valid
Mach-O binary in a bundle with the right `Info.plist` keys, which
`scripts/build-app.sh` assembles by hand from a plain `swift build`
output. Revisit this if/when someone picks the project up in an
Xcode-GUI environment and wants richer Interface Builder / asset catalog
tooling for M3.

## Build

```sh
./scripts/build-app.sh          # debug
./scripts/build-app.sh release  # release
```

Produces `.build-app/Nagi.app` (ad-hoc signed — required, otherwise
InputMethodKit refuses the bundle).

## Install

```sh
./scripts/install-ime.sh
```

Copies the built app to `~/Library/Input Methods/Nagi.app`.

**Then, manually** (this part genuinely needs a human at the keyboard —
see "Verification" below for why it can't be scripted headlessly):

1. Log out and back in (or reboot). macOS only rebuilds its Text Input
   Sources registry once per login session — restarting `imklaunchagent`
   or `TextInputMenuAgent` does *not* pick up a newly-installed IME; this
   was verified experimentally while building M1, not assumed.
2. System Settings → Keyboard → Input Sources → Edit... → "+" → find
   "Nagi" under Japanese → Add.
3. Switch to it from the menu bar Input menu.
4. In TextEdit, type `nagi` then Enter.

## Exit criterion

Typing `nagi<Enter>` in TextEdit inserts `なぎ`.

## Verification

Confirmed so far, all headlessly from this environment:

- `swift build` succeeds; `Nagi.app` assembles and ad-hoc codesigns
  cleanly (`codesign -dv` shows a valid adhoc signature).
- The built binary launches (`open .build-app/Nagi.app`) and stays
  resident without crashing — `IMKServer` initialization and
  `NSApplication.run()` don't throw.
- Installing to `~/Library/Input Methods/` and forcing `imklaunchagent`
  / `TextInputMenuAgent` to restart (`kill -HUP`, `kill -9`) does **not**
  make the new source appear in `TISCreateInputSourceList` — confirmed by
  querying it directly via a throwaway Carbon/TIS script, source count
  unchanged (324) before and after. This is consistent with widely
  reported macOS IME development experience: the Text Input Sources
  registry is a per-login-session cache, not something rescanned live.

**Not yet confirmed**: the actual `nagi<Enter>` → `なぎ` keystroke test in
TextEdit with Nagi selected as the active input source. That requires the
login-session refresh above, which this environment can't trigger without
ending the current session — needs a human to do the "log out, add the
input source, type the test string" steps and report back.

## Non-goals for M1 (unchanged from the issue)

- No Mozc IPC / real conversion — `RomajiConverter` is a placeholder.
- No candidate window.
- No performance work.
