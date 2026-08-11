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
Attached to the [latest GitHub
Release](https://github.com/nv-leo/nagi/releases/latest); to build one
locally instead:

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
`/Library/Input Methods/`, not `/Applications/`, so `Nagi.app`'s drop
target in the DMG is a symlink to that folder instead of the usual
Applications alias. That's still only one drag, though — the DMG isn't
asking for a second one to place `Uninstall Nagi.app` too (#33
follow-up): Nagi.app embeds a copy of it and deploys it to
`/Applications/` itself on first launch
(`app/Sources/Nagi/UninstallerDeployment.swift`), the same way it
already self-registers `NagiConverter` and the Text Input Source below.
Writing to `/Applications/` doesn't need admin privileges the way
`/Library/Input Methods/` does (it's `root:admin`, group-writable, same
reason Finder never prompts when *you* drag a normal app there), so
this needs no extra permission dialog beyond the one already required
for step 1. The DMG still carries its own top-level copy of `Uninstall
Nagi.app` too, purely as a fallback for the case Nagi.app never got to
run at all (e.g. Gatekeeper blocked it and the user gave up before
getting past that). What made dropping the custom installer possible at
all in the first place: Nagi.app
now registers its own `NagiConverter` LaunchAgent via `SMAppService` the
first time it runs (see
`app/Sources/Nagi/ConverterServiceRegistration.swift`), and — as of the
M4 #30 follow-up — also registers itself as a Text Input Source
(`app/Sources/Nagi/InputSourceRegistration.swift`, see "Getting
registered" below) — no installer script needs to do either on its
behalf anymore. Neither one takes effect until the next login, though
(same "Getting registered" section) — not a full reboot, but not
instant either.

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

Installed via the `.dmg` above? That's `/Library/Input Methods/`, so use
`--system`.

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
