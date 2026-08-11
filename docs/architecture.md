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
Mach bootstrap service, declared under `MachServices` in a per-user
LaunchAgent (`com.nvleo.inputmethod.nagi.Converter`), and **launchd** —
not Nagi — starts the `NagiConverter` process on demand the first time
any client calls `bootstrap_look_up` for it, exactly like it does for
Google 日本語入力's own Converter service (which `poc/`'s M0 CLI still
piggybacks on — a deliberate, useful difference for a "does Mach IPC even
work at all" PoC, not an oversight).

**Who registers that LaunchAgent changed in M4 (#30).** Originally
`install-ime.sh` wrote the plist to `~/Library/LaunchAgents/` and called
`launchctl bootstrap` itself; a since-abandoned `.pkg` installer's
`postinstall` script briefly did the same thing from outside the app.
Both worked, but both meant Nagi.app wasn't self-sufficient — something
external always had to run first. `Nagi.app` now registers its own
LaunchAgent at runtime via `ServiceManagement.SMAppService`
(`app/Sources/Nagi/ConverterServiceRegistration.swift`), using a plist
embedded in the bundle at `Contents/Library/LaunchAgents/` (the fixed
location `SMAppService.agent(plistName:)` requires) with a
`BundleProgram` key instead of an absolute `Program` path, so it resolves
correctly whether Nagi.app ends up at `~/Library/Input Methods/` or
`/Library/Input Methods/`. Confirmed working end-to-end on the dev
machine: `launchctl print` on the registered service shows `managed_by =
com.apple.xpc.ServiceManagement` (absent under the old manual-bootstrap
approach) and the correct bundle-relative `program identifier`. This is
what made dropping the custom installer for `scripts/build-dmg.sh`
possible — see app/README.md's "Prebuilt download (.dmg)".

**One caveat, found during the #33 follow-up below:** `register()`
reporting `.enabled` does not mean the job is loaded into launchd for
the *current* login session — `launchctl print` on a just-registered
service can come back "Could not find service" even though
`sfltool dumpbtm` already shows it `enabled, allowed`. Nothing in
Nagi.app can force the load; it happens automatically starting the
*next* login. See "Getting registered as a Text Input Source" below —
the Text Input Source registration has the identical limitation, for
different underlying reasons, and both are why conversion needs one
log out/in after the very first install just like the menu bar entry
does.

Nagi is LSUIElement (no Dock icon, no window), so registering silently
leaves no feedback that anything happened — `ConverterServiceRegistration`
also posts a one-shot local notification the first time registration
succeeds, as the only feedback available without adding real UI to a
headless host process. Getting that notification to actually appear
took its own debugging round: `registerIfNeeded()` was originally called
from `main.swift` *before* `NSApplication.shared`/`setActivationPolicy`
and `app.run()`, and calling `UNUserNotificationCenter`'s
`requestAuthorization` at that point was unreliable — its completion
handler either never fired at all, or came back with the error
"Notifications are not allowed for this application" *even with the
toggle already on in System Settings*. Moving the call to
`DispatchQueue.main.async` scheduled just before `app.run()` (so it
actually runs once the run loop is spinning, not before) fixed it —
confirmed by manually forcing the notification path on the dev machine.
SMAppService's own `.register()` call didn't have this problem, only
`UNUserNotificationCenter` did.

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

**Partially resolved, M4 (#30 follow-up) — item 3's full *reboot* is no
longer needed, but a *log out and back in* still is.** Full write-up,
including two wrong attempts that briefly shipped along the way, in
[issue #33](https://github.com/nv-leo/nagi/issues/33) — summary:

- `Nagi.app` appends its own entry to the `AppleEnabledInputSources`
  array in the `com.apple.HIToolbox` preference domain directly via
  `CFPreferencesSetValue`, alongside the required (but not by itself
  sufficient) `TISRegisterInputSource` call that gets the bundle into
  the installed catalogue
  (`app/Sources/Nagi/InputSourceRegistration.swift`). This array is
  what System Settings' Input Sources list, the menu bar Input menu,
  and conversion all ultimately depend on being correct.
- Writing it does **not**, however, make any of the three pick Nagi up
  in the *current* login session — confirmed against a genuinely fresh
  install (never previously registered in that session): System
  Settings' Input Sources list still didn't show Nagi even freshly
  reopened, quit and relaunched. This took two more rounds of live
  reverse-engineering (disassembling the relevant HIToolbox private
  functions, differential testing against Kotoeri/AinuIM/plain keyboard
  layouts) to pin down:
  - Neither System Settings nor the menu bar Input menu (the latter
    built from `_TSMCopySelectableInputSourcesInUIOrder()`) reads
    `AppleEnabledInputSources` directly. Both read a
    **login-session-scoped pasteboard** that HIToolbox materializes via
    `UpdatePBInputSourcesInUIOrder` ("PB" = PasteBoard) — which is also
    what expands a bare "Keyboard Input Method" parent entry (the shape
    Nagi writes) into the visible "Input Mode" child entry (the shape
    Kotoeri's own entries already include) — and that rebuild only
    happens at login, not on demand. An earlier version of this file
    (and of `InputSourceRegistration.swift`) believed
    `killall -HUP imklaunchagent TextInputMenuAgent` after the
    preference write stood in for a reboot, the same way it does for
    the on-boot registry rescan in item 3 above. It doesn't:
    `launchctl print` confirms the signal does restart both agents, but
    neither agent is what's stale, so nothing changes — pure cost (a
    brief hiccup in text input switching) for zero benefit. Removed
    from `InputSourceRegistration.swift`.
  - `TISEnableInputSource`/`TISDisableInputSource` looked like a more
    legitimate way to force that rebuild, and do trigger a genuine
    one-time user consent dialogue the first time they're called for a
    given source — but calling them on Nagi's own bundle or its
    Hiragana mode is a silent no-op (`OSStatus noErr`, nothing changes)
    both before *and* after granting that consent, verified repeatedly.
    (`kTISPropertyInputSourceIsEnabled` also reads back a phantom
    `true` for Nagi regardless, synthesised from
    `tsInputModeDefaultStateKey` in Info.plist rather than the actual
    preference — an earlier theory pinned the no-op on that phantom
    value gating the call, but the same no-op persisted even against a
    *different*, honestly-`false` system input mode, so that theory
    doesn't hold either.) The only way found to actually force the
    rebuild is enabling/disabling some unrelated, already-installed
    input source (e.g. a keyboard layout) — not something to do to a
    user's real configuration from inside an install path, and it has
    its own side effect of pruning Nagi's own preference entry as
    "orphaned" if it has no matching `Input Mode` entry yet.
  - The `NagiConverter` `SMAppService` LaunchAgent (see "Runtime layout
    on macOS" above) has the same shape of limitation: `register()`
    reports `.enabled` (approved) immediately, but the job is not
    actually loaded into launchd for the *current* login session until
    the next login — nothing in-process can force that either, which is
    why conversion itself (not just the menu bar entry) needs the same
    one-time log out/in.

Net effect, and not a Nagi-specific bug: Google 日本語入力, macSKK and
other third-party macOS IMEs all document the same one-time requirement
— install → launch once → log out and back in once → System Settings,
the menu bar, and conversion all pick it up together, no manual "+"
needed. None of the preference-writing above is documented Apple
behavior —
it's simply what System Settings' own UI does when you tick the
checkbox — so if a future macOS version changes the schema, this
degrades back to the old fully-manual behavior (every step in
`InputSourceRegistration.swift` is unconditionally best-effort), not a
crash.

**Removal, tested and confirmed end-to-end, M4 (#30 install/uninstall
follow-up), superseding the hypothesis below.** Full cycle tested on the
dev machine: install → reboot → add "ひらがな (Nagi)" in System
Settings → confirmed switchable → run `scripts/uninstall-ime.sh` (a
plain `rm -rf` of `Nagi.app` plus tearing down the `NagiConverter`
LaunchAgent) → observe. Two distinct findings came out of that last step:

1. **Passive removal doesn't happen on its own — reboot required, same
   as additions.** After uninstalling, "ひらがな (Nagi)" stayed listed
   in System Settings' Input Sources with no logout/reboot; it just
   stopped being switchable to, since its backing bundle was gone. So
   the on-boot registry rescan additions need applies to plain
   file-level removal too — it isn't add-only, contradicting the
   original hypothesis below.
2. **Active removal (the "−" button in System Settings' Input Sources
   editor) works immediately, no reboot needed.** Manually selecting the
   now-broken "ひらがな (Nagi)" entry and clicking "−" cleared it right
   away. Makes sense in hindsight: that's a direct, explicit
   deregistration call the picker makes on your behalf, not the passive
   background rescan that only happens at boot.

Net effect for `uninstall-ime.sh`: a reboot is *not* actually required to
get back to a clean state — removing the stale entry by hand with "−"
is enough, and is the faster path. Reboot is only a fallback if that's
not an option for some reason.

This also reframes the earlier Google 日本語入力 observation below —
the likely explanation is that Google's uninstaller doesn't just delete
files, it also actively deregisters the source (the same effect as
clicking "−" by hand) before removing the bundle, which a blunt
`rm -rf` can't replicate without doing the equivalent call itself.
Recorded as the plausible explanation, not confirmed against Google's
actual uninstaller code.

Original hypothesis (kept for context, refined by the above): this
reboot requirement might only apply to *additions* (a new/changed
`TISInputSourceID` becoming selectable), because uninstalling Google
日本語入力 made it disappear from System Settings' Input Sources list
immediately, no logout/reboot, on the same machine where addition-side
reboot was confirmed required (item 3 above).

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
