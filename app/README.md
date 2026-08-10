🇺🇸 English ・ [🇯🇵 日本語](README-JP.md)

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

## Prebuilt download (.dmg)

For trying Nagi out without a full dev environment (Xcode, Bazel, ... —
see "Build" above): `scripts/build-dmg.sh` packages a built `Nagi.app`
into a plain drag-and-drop `.dmg` — just the app, no installer package.
Not yet attached to a GitHub Release (no release has been cut), so for
now this still means building it locally first:

```sh
./scripts/build-dmg.sh   # -> .build-dmg/Nagi-<version>.dmg
```

Deliberately just the app, not a `.pkg`/custom installer — a signed and
notarized DMG containing nothing but the app, that the user drags
wherever they want, is what solo/small-team macOS developers converge on
as the actual standard once you look past the big corporate installers
(discussed on #30, credit to
[this r/opensource thread](https://www.reddit.com/r/opensource/comments/1ku0zv0/)
for the correction — an earlier version of this section pointed at a
`.pkg` instead). The one accommodation still needed: Nagi has to land in
`/Library/Input Methods/`, not `/Applications/`, so the DMG's drop
target is a symlink to that folder instead of the usual Applications
alias. What made dropping the custom installer possible at all: Nagi.app
now registers its own `NagiConverter` LaunchAgent via `SMAppService` the
first time it runs (see
`app/Sources/Nagi/ConverterServiceRegistration.swift`), and — as of the
M4 #30 follow-up — also registers itself as a Text Input Source without
needing a reboot (`app/Sources/Nagi/InputSourceRegistration.swift`, see
"Getting registered" below) — no installer script needs to do either on
its behalf anymore.

**Unsigned — there is no Apple Developer Program membership (Developer
ID) behind this repo, so macOS's Gatekeeper will block the first open of
Nagi.app.** Control-click Nagi.app → Open → Open (again, in the dialog),
or System Settings → Privacy & Security → "Open Anyway" after the first
blocked attempt. If neither offers an "Open" option (recent macOS
sometimes shows "is damaged" instead, with no GUI bypass — also raised
in the thread linked above), strip the quarantine attribute by hand:
`xattr -cr "/Library/Input Methods/Nagi.app"`. Full steps, including
this fallback, are in `scripts/dmg/README.txt`, bundled inside the DMG
itself. This is the same tradeoff another solo-dev macOS IME,
[SwiftyGyaim](https://github.com/tanabe1478/SwiftyGyaim), makes for the
same reason. A signed and notarized DMG (matching macSKK/AquaSKK/
azooKey-Desktop, all surveyed on #30) is still on the roadmap (M4) — it
just needs a paid Developer ID first.

## Install (from source)

```sh
./scripts/install-ime.sh                  # ~/Library/Input Methods/
./scripts/install-ime.sh release --system # /Library/Input Methods/ (sudo)
```

**Then, manually:**

1. **Launch `Nagi.app` once** — double-click it in Finder, or `open
   "/Library/Input Methods/Nagi.app"`. This triggers self-registration
   (`app/Sources/Nagi/InputSourceRegistration.swift`, #30 follow-up) —
   **no reboot needed anymore.** Earlier versions of this doc said a full
   reboot was required here; see "Getting registered" below for why that
   turned out not to be a hard requirement after all.
2. System Settings → Keyboard → Input Sources → "Nagi" should already be
   listed under Japanese, no "+" needed (self-registration enables it
   directly). If other Japanese IMEs are installed (Google Japanese
   Input, macSKK, ...), there may be multiple entries named "ひらがな" —
   check the mode icon to tell Nagi's apart. If it's missing, fall back
   to Edit... → "+" → find "Nagi" under Japanese → Add.
3. Switch to it from the menu bar Input menu.
4. In TextEdit, type `nagi` then Enter.

## Uninstall

```sh
./scripts/uninstall-ime.sh                  # ~/Library/Input Methods/
./scripts/uninstall-ime.sh --system         # /Library/Input Methods/ (sudo)
./scripts/uninstall-ime.sh --all            # both
```

Installed via the `.dmg` above? That's `/Library/Input Methods/`, so use
`--system`.

Removes `Nagi.app` and stops the `NagiConverter` LaunchAgent. Didn't
exist until #30's install/uninstall follow-up — `install-ime.sh` had no
counterpart before that.

**Confirmed (#30): no reboot needed, but a manual step is.** "ひらがな
(Nagi)" stays listed in System Settings' Input Sources after running
this — it won't disappear on its own without a reboot — but it also
stops being switchable to, since its backing bundle is gone. Clear it
immediately (no reboot) via System Settings > Keyboard > Input Sources >
Edit... > select "ひらがな (Nagi)" > "−". See docs/architecture.md's
"Mozc IPC" section for the full test and why this differs from Google
日本語入力's own uninstaller, which clears its entry without that manual
step.

**Untested (#30): `NagiConverter` may similarly linger in System
Settings > General > Login Items.** Since it's registered via
`SMAppService` from inside the app rather than a plist this script
writes, there's no file left to delete that cleanup — this script can
only `launchctl bootout` the running job, not call the equivalent of
`SMAppService.unregister()`. If a stale "Nagi" entry shows up there
after uninstalling, removing it by hand (same "−"/right-click gesture as
Input Sources above) is the expected fix; not yet verified against a
real reinstall/uninstall cycle.

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

   **Resolved, M4 (#30 follow-up) — item 3 turned out not to be a hard
   requirement.** `imklaunchagent`/`TextInputMenuAgent` cache the Text
   Input Source registry once, at their own process startup, and never
   rescan it afterwards — that's the actual mechanism behind "only a
   full reboot works", since a reboot is what restarts them along with
   everything else. `TISRegisterInputSource`/`TISEnableInputSource` do
   correctly write through to the underlying registry even without a
   reboot (confirmed: a *fresh* process reads the change back
   correctly) — the two agents just don't know about it until *they*
   restart. `launchctl kickstart -k` on either is blocked by SIP
   ("Operation not permitted while System Integrity Protection is
   engaged"), which is almost certainly why the "restarting by hand
   doesn't help" claim above was wrong — that earlier attempt never
   actually restarted anything. A plain `kill -HUP` (not going through
   `launchctl`) does terminate them, and launchd immediately respawns
   both as on-demand agents, which do pick up the change. Nagi.app now
   does exactly this itself on first launch after install — see
   `app/Sources/Nagi/InputSourceRegistration.swift`. None of this is
   documented Apple behavior; if a future macOS version changes it, this
   degrades back to the old reboot-required behavior, not a crash.

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
