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
- `Resources/icons/nagi.tiff` — the menu bar / Input Sources list mode
  icon (real artwork, generated from `scripts/icons/generate.py` — see
  `scripts/build-icons.sh`). An alpha-cutout badge matching Apple's own
  IME icons (e.g. AinuIM.app's Ainu.tiff), required for
  `TISIconIsTemplate` (see Info.plist) to tint it correctly instead of
  rendering a solid blob (issue #35).

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

## Prebuilt install (curl one-liner)

For trying Nagi out without a full dev environment (Xcode, Bazel, ... —
see "Build" above):

```sh
curl -fsSL https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh | bash
```

`scripts/install-nagi.sh` downloads the latest release's `Nagi.zip`,
unzips it, installs to `/Library/Input Methods/` (asking for your admin
password once — a system folder), and launches Nagi. Prefer not to pipe
a script straight into a shell without reading it first? Reasonable —
download it, read it, then run it:

```sh
curl -fsSLO https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh
less install-nagi.sh
bash install-nagi.sh
```

`scripts/build-release-zip.sh` produces the `Nagi.zip` this fetches
(via `ditto`, which — unlike a plain `zip` — preserves what a
code-signed `.app` bundle needs intact through a zip round-trip:
extended attributes, resource forks, and the code signature itself).

### Why not a `.dmg`

An earlier version of this section shipped a drag-and-drop `.dmg`
(discussed on #30, credit to [this r/opensource
thread](https://www.reddit.com/r/opensource/comments/1ku0zv0/) for
correcting an even earlier `.pkg`-based plan) — first with `Nagi.app`
dragged onto a symlink to `/Library/Input Methods/`, then, after
real-machine testing found Finder's drag-and-drop only escalates to an
admin password prompt for a fixed allowlist of destinations and
silently no-ops on anything else (see [this Apple Developer Forums
thread](https://developer.apple.com/forums/thread/712148)), with a
double-clickable `Install Nagi.app` installer instead. Both were
abandoned after further real-machine testing (this time via an actual
browser download, not just a locally-built `.dmg`) hit a dead end
neither could work around:

**There is no Apple Developer Program membership (Developer ID) behind
this repo, so everything Nagi ships is ad-hoc signed
(`codesign --sign -`), not Developer ID-signed, and not notarized. On
macOS 15 (Sequoia) and later — 26 (Tahoe) included — Gatekeeper has no
GUI bypass at all for a quarantined *ad-hoc signed* app**, unlike a
Developer ID-signed-but-unnotarized one (which does get the familiar,
bypassable "unidentified developer" prompt). Instead, macOS reports
`"<app>" is damaged and can't be opened` and offers only "Move to
Trash" — Control-click → Open does nothing, and no "Open Anyway" button
appears in System Settings → Privacy & Security, because Gatekeeper
never records a blocked assessment it could offer to override. (The
quarantine flag on a downloaded `.dmg` is what makes macOS mount its
volume with the `quarantine` mount option, which in turn is what makes
every ad-hoc signed app inside it unlaunchable — clearing the flag by
hand with `xattr -d com.apple.quarantine` before opening the `.dmg`
does work around it, but that's a Terminal step either way, which
defeats a drag-and-drop/double-click installer's entire point.)

curl doesn't set `com.apple.quarantine` on what it downloads the way a
browser does, so `install-nagi.sh` sidesteps the problem at the
distribution-channel level instead: nothing it fetches ever gets
quarantined, so the ad-hoc/notarization Gatekeeper wall above never
triggers, and no `xattr` workaround is needed at all — not even the one
line the `.dmg` approach couldn't avoid. This is the same signing
tradeoff another solo-dev macOS IME,
[SwiftyGyaim](https://github.com/tanabe1478/SwiftyGyaim), makes for the
same reason. A Developer ID-signed and notarized release (matching
macSKK/AquaSKK/azooKey-Desktop, all surveyed on #30) is still on the
roadmap (M4) — it just needs a paid Developer ID first.

What makes a one-line installer (as opposed to a from-source build)
possible at all: Nagi.app registers its own `NagiConverter` LaunchAgent
via `SMAppService` the first time it runs (see
`app/Sources/Nagi/ConverterServiceRegistration.swift`), and — as of the
M4 #30 follow-up — also registers itself as a Text Input Source
(`app/Sources/Nagi/InputSourceRegistration.swift`, see "Getting
registered" below) and deploys its own `Uninstall Nagi.app` to
`/Applications/` (#33 follow-up,
`app/Sources/Nagi/UninstallerDeployment.swift`) — no installer script
needs to do any of that on its behalf. None of the three takes effect
until the next login, though (same "Getting registered" section) — not
a full reboot, but not instant either.

**If `install-nagi.sh` itself fails partway through** (e.g. the network
drops mid-download), Nagi never gets installed and there's nothing to
clean up — rerun the one-liner. If it fails *after* copying Nagi.app
into place but before Nagi ever launches, `Uninstall Nagi.app` never
gets deployed to `/Applications/` either; remove
`/Library/Input Methods/Nagi.app` by hand in Finder, or use
`scripts/uninstall-ime.sh` from a clone of the repo, in that case.

## Install (from source)

```sh
./scripts/install-ime.sh                  # ~/Library/Input Methods/
./scripts/install-ime.sh release --system # /Library/Input Methods/ (sudo)
```

**Then, manually:**

1. **Launch `Nagi.app` once** — double-click it in Finder, or `open
   "/Library/Input Methods/Nagi.app"`. This triggers self-registration
   (`app/Sources/Nagi/InputSourceRegistration.swift`, #30 follow-up), and
   an alert dialog should pop up on top of whatever you're doing,
   offering to log you out right there
   (`app/Sources/Nagi/FirstRunPrompt.swift`) — click through that (or
   its "あとで"/"later" button, then do step 2 yourself) rather than
   waiting on a notification: a background notification was tried first
   but is unreliable for a Dock-icon-less, window-less `LSUIElement` app
   like Nagi (confirmed failing with "Notifications are not allowed for
   this application" — see `app/Sources/Nagi/ConverterServiceRegistration.swift`),
   which is exactly why this alert exists instead.
2. **Log out and back in once**, if step 1's alert didn't already do it
   for you. Nothing shows up yet — not System
   Settings' Input Sources list, not the menu bar Input menu, not
   conversion — even though registration already succeeded; see
   "Getting registered" below for why it all waits for the next login.
   No full reboot needed, just a log out — the same one-time step
   Google 日本語入力 and other third-party macOS IMEs also require.
3. System Settings → Keyboard → Input Sources → "Nagi" should now be
   listed under Japanese, no "+" needed. If other Japanese IMEs are
   installed (Google Japanese Input, macSKK, ...), there may be
   multiple entries named "ひらがな" — check the mode icon to tell
   Nagi's apart. If it's still missing, fall back to Edit... → "+" →
   find "Nagi" under Japanese → Add.
4. Switch to it from the menu bar Input menu.
5. In TextEdit, type `nagi` then Enter.

## Uninstall

```sh
./scripts/uninstall-ime.sh                  # ~/Library/Input Methods/
./scripts/uninstall-ime.sh --system         # /Library/Input Methods/ (sudo)
./scripts/uninstall-ime.sh --all            # both
```

Installed via the curl one-liner above? That's `/Library/Input Methods/`,
so use `--system` — or just double-click `Uninstall Nagi.app` in your
Applications folder, no Terminal needed (see "Prebuilt install" above).

Removes `Nagi.app`, stops the `NagiConverter` LaunchAgent, and clears
Nagi's entry from System Settings' Input Sources — no manual step, no
reboot needed (#33: this compiles and runs
`scripts/dmg/nagi-tis-disable.swift` on the fly, the same helper the GUI
`Uninstall Nagi.app` uses). Requires `swiftc` (Xcode Command Line
Tools); if that's unavailable the Input Sources entry falls back to the
old behavior — lingers, non-switchable-to, until cleared by hand via
System Settings > Keyboard > Input Sources > Edit... > select "ひらがな
(Nagi)" > "−" (no reboot needed for that either) or a reboot.
`uninstall-ime.sh` didn't exist until #30's install/uninstall
follow-up — `install-ime.sh` had no counterpart before that.

**Tested (#30 follow-up): `NagiConverter` does not leave a visible
ghost entry in System Settings > General > Login Items.** Since it's
registered via `SMAppService` from inside the app rather than a plist
this script writes, there's no file left to delete for that cleanup —
this script can only `launchctl bootout` the running job, not call the
equivalent of `SMAppService.unregister()` (an instance method callable
only from inside the registering app's own running process — no public
API exists for an external script to unregister someone else's
`SMAppService` entry). Confirmed on the dev machine: right after
uninstalling, both `Nagi` and `NagiConverter` briefly persisted at the
`sfltool dumpbtm` level (`Nagi` flipped to `disabled`,
`NagiConverter` stayed `enabled`), but neither ever appeared in System
Settings' actual Login Items UI, and both were gone from that same
`dumpbtm` dump within a few minutes with no manual step taken. No
user-facing residue.

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

   **Partially resolved, M4 (#30 follow-up) — a full *reboot* is no
   longer needed, but a *log out and back in* still is.** Full write-up
   in [issue #33](https://github.com/nv-leo/nagi/issues/33) — short
   version: Nagi.app appends its own entry to the
   `AppleEnabledInputSources` array in the `com.apple.HIToolbox`
   preference domain directly via `CFPreferencesSetValue` (see
   `app/Sources/Nagi/InputSourceRegistration.swift`) — that's the array
   System Settings' Input Sources list, the menu bar Input menu, and
   conversion all ultimately depend on being correct. It does **not**,
   however, make any of the three pick Nagi up in the *current* login
   session — confirmed against a genuinely fresh install (never
   previously registered in that session): System Settings' Input
   Sources list still doesn't show Nagi even freshly reopened, quit and
   relaunched.

   Extensive live reverse-engineering (disassembling the relevant
   HIToolbox private functions, differential testing against
   Kotoeri/AinuIM/plain keyboard layouts) found that neither System
   Settings nor the menu bar Input menu (the latter built from
   `_TSMCopySelectableInputSourcesInUIOrder()`) reads
   `AppleEnabledInputSources` directly — both read a
   **login-session-scoped pasteboard** HIToolbox materializes via
   `UpdatePBInputSourcesInUIOrder`, which expands a bare "Keyboard Input
   Method" parent entry (the shape Nagi writes) into its visible
   "Input Mode" child (the shape Kotoeri's own entries already include)
   — and that expansion only happens at login, not on demand.
   `killall -HUP`-restarting `imklaunchagent`/`TextInputMenuAgent` (an
   earlier version of this file did that) restarts the agents fine but
   doesn't touch the stale pasteboard, so it was removed — pure cost (a
   brief hiccup in text input switching), zero benefit.
   `TISEnableInputSource`/`TISDisableInputSource` looked more promising
   — they do trigger a genuine one-time user consent dialogue the first
   time they're called for a given source — but calling them on Nagi's
   own bundle or its Hiragana mode is a silent no-op (`OSStatus noErr`,
   nothing changes) both before *and* after granting that consent. The
   only way found to force the rebuild is enabling/disabling some
   unrelated, already-installed input source, which is not something to
   do to a user's real configuration from inside an install path.
   Likewise, `NagiConverter`'s `SMAppService` registration
   (`app/Sources/Nagi/ConverterServiceRegistration.swift`) reports
   `.enabled` immediately, but the LaunchAgent isn't actually loaded
   into launchd for the *current* login session until the next login —
   nothing in-process can force that either.

   Net result: install → launch once → log out and back in once →
   System Settings, the menu bar, and conversion all pick Nagi up
   together, no manual "+" needed. **Not a Nagi-specific bug** — Google
   日本語入力 and macSKK's own install guides document the exact same
   one-time requirement.

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
