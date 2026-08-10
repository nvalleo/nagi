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
  google/mozc's own `mac/Info.plist`, macSKK, and Apple's own bundled
  `/System/Library/Input Methods/AinuIM.app` to get the easy-to-get-wrong
  keys right (see "Getting registered" below — this took a lot more than
  "get the keys right").
- `Resources/InfoPlist.strings` — display names for the Input Source
  picker. Without this, macOS shows the raw `TISInputSourceID` string
  instead of "Nagi"/"ひらがな".
- `Resources/icons/nagi.tiff` — placeholder mode icon (a generic system
  icon, not real artwork — revisit before any real release).

## Why no `.xcodeproj`

Same reasoning as [`poc/`](../poc): this environment has Xcode's Command
Line Tools but not the Xcode GUI, and the project has been SwiftPM-based
since M0. An IMKit `.app` doesn't require Xcode — it just needs a valid
Mach-O binary in a bundle with the right `Info.plist` keys, which
`scripts/build-app.sh` assembles by hand from a plain `swift build`
output. (Xcode did end up getting installed on the dev machine partway
through M1, to get a free Apple ID development certificate while
chasing a dead-end signing theory — see below — but the build itself
still doesn't use it.) Revisit this if/when someone picks the project up
in an Xcode-GUI environment and wants richer Interface Builder / asset
catalog tooling for M3.

## Build

```sh
./scripts/build-app.sh          # release (default)
./scripts/build-app.sh debug    # compiles, but will NEVER register — see below
```

Produces `.build-app/Nagi.app` (ad-hoc signed by default; set
`CODESIGN_IDENTITY` to a `security find-identity` hash to sign with a
real identity instead — not required, ad-hoc works fine).

## Install

```sh
./scripts/install-ime.sh                  # ~/Library/Input Methods/
./scripts/install-ime.sh release --system # /Library/Input Methods/ (sudo)
```

**Then, manually:**

1. **Reboot the machine.** Not log out/in — a full reboot. This is the
   single most surprising thing learned building M1 (see below).
2. System Settings → Keyboard → Input Sources → Edit... → "+" → find
   "Nagi" under Japanese → Add. If other Japanese IMEs are installed
   (Google Japanese Input, macSKK, ...), there may be multiple entries
   named "ひらがな" — check the mode icon to tell Nagi's apart.
3. Switch to it from the menu bar Input menu.
4. In TextEdit, type `nagi` then Enter.

## Uninstall

```sh
./scripts/uninstall-ime.sh                  # ~/Library/Input Methods/
./scripts/uninstall-ime.sh --system         # /Library/Input Methods/ (sudo)
./scripts/uninstall-ime.sh --all            # both
```

Removes `Nagi.app` and stops/deregisters the `NagiConverter` LaunchAgent.
Didn't exist until #25's install/uninstall follow-up — `install-ime.sh`
had no counterpart before that.

**Confirmed (#25): removal needs a reboot too, same as installing does.**
"ひらがな (Nagi)" stays listed in System Settings' Input Sources after
running this — just no longer switchable to, since its backing bundle is
gone. Try removing the stale entry by hand with the "−" button first; if
that doesn't work, reboot. See docs/architecture.md's "Mozc IPC" section
for why this differs from Google 日本語入力's own uninstaller, which
clears its entry immediately.

## Exit criterion

Typing `nagi<Enter>` in TextEdit inserts `なぎ`. **Confirmed working on
the dev machine.**

## Getting registered: three silent requirements

Getting `Nagi.app` to actually show up as an Input Source (as opposed to
just building and launching without crashing) took a multi-day
bisection against known-working IMKit bundles, because every failure
mode here is completely silent — no crash, no log line anywhere, no
error from any tool. If this breaks again, check these in order:

1. **Must be a `release` build.** `debug` builds carry an
   auto-generated `com.apple.security.get-task-allow` entitlement. A
   bundle whose binary has that entitlement is never added to the Text
   Input Source registry — `imklaunchagent` still accepts its XPC
   connection fine at runtime, so the process looks perfectly healthy;
   it just never becomes selectable.
2. **`CFBundleIdentifier` (and every `TISInputSourceID` under it) must
   contain the literal substring `.inputmethod.`.** Confirmed by
   bisecting against every known-working IMKit bundle found on the
   dev machine — Apple's own `AinuIM.app`, Google Japanese Input,
   macSKK — all of them use this token, and the literal string
   `.inputmethod.` is embedded in `imklaunchagent`/HIToolbox's string
   table right next to `ComponentInputModeDict`/`TISInputSourceID`
   in their `__cstring` sections. Bundle IDs without it are silently
   dropped, no matter how correct everything else is. This is why the
   bundle ID ended up as `com.nvleo.inputmethod.nagi` rather than the
   simpler `com.nvleo.nagi` floated in issue #1.
3. **A change to the bundle ID (or anything else the registry keys
   off) only takes effect after a full reboot.** Logging out and back
   in — the commonly-cited fix, and what earlier versions of this repo's
   docs claimed was sufficient — does *not* force a re-scan. Only a full
   boot does. Restarting `imklaunchagent`/`TextInputMenuAgent` by hand
   doesn't help either.

None of the following turned out to matter, despite each looking
plausible mid-investigation — noted here so nobody re-derives them:
ad-hoc vs. real code-signing identity (a real Apple Development
certificate was eventually obtained and confirmed to make no
difference), hardened runtime, binary vs. XML `Info.plist` format, thin
vs. universal binary, `LSBackgroundOnly`, `TISInputSourceID` matching
vs. differing from its `ComponentInputModeDict` dictionary key, presence
of an icon file, presence of `InputMethodServerDataSourceClass`/
`DelegateClass`.

## Non-goals for M1 (unchanged from the issue)

- No Mozc IPC / real conversion — `RomajiConverter` is a placeholder.
- No candidate window.
- No performance work.
- Bundle ID (`com.nvleo.inputmethod.nagi`) and the app icon are still
  effectively draft — functional now that `.inputmethod.` is known to
  be required, but not treated as final/branded.
