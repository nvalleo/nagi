-- Install Nagi.applescript — double-clickable installer, compiled to
-- "Install Nagi.app" by scripts/build-installer.sh and bundled at the
-- top level of the .dmg (#30 follow-up).
--
-- Replaces "drag Nagi.app onto the bundled 'Input Methods' symlink" as
-- the documented install step: that drag silently no-ops on a real
-- machine. Finder's drag-and-drop only escalates to an admin password
-- prompt for a fixed allowlist of destinations (Applications,
-- Applications/Utilities, Desktop, a handful of Library subfolders) —
-- dropping onto an alias/symlink pointing anywhere else, including
-- /Library/Input Methods, is silently blocked by system policy instead
-- (confirmed on the dev machine; see
-- https://developer.apple.com/forums/thread/712148). This sidesteps
-- the problem rather than working around it: `do shell script ... with
-- administrator privileges` is a different privilege-escalation path,
-- not subject to that Finder drag policy.
--
-- Also strips the quarantine attribute macOS attaches to anything
-- downloaded via a browser, then opens Nagi.app once — the same
-- `xattr -cr` workaround app/README.md's "Prebuilt download" section
-- documents as a manual Terminal fallback for Gatekeeper's "can't
-- verify the developer"/"is damaged" block, just automatic now. This
-- is the app's own installer, run by the user who chose to run it —
-- not a third party stripping someone else's quarantine — so skipping
-- that prompt here is the same trust decision the manual xattr
-- fallback already asked users to make, just without needing a
-- Terminal.
--
-- Installs to /Library/Input Methods/ only, matching the .dmg's
-- previous symlink target — scripts/install-ime.sh's per-user default
-- remains available for anyone building from source instead.
--
-- Doesn't delete itself when done (unlike Uninstall Nagi.app): it runs
-- directly off the mounted .dmg volume, which is read-only (UDZO
-- format), not somewhere it got dragged/deployed to. Ejecting the .dmg
-- is what makes it go away.

set installerPath to POSIX path of (path to me)
set sourceApp to (do shell script "dirname " & quoted form of installerPath) & "/Nagi.app"
set targetApp to "/Library/Input Methods/Nagi.app"

set sourceAppExists to (do shell script "test -d " & quoted form of sourceApp & " && echo yes || echo no") is "yes"
if not sourceAppExists then
	display dialog "Nagi.app が見つかりませんでした。「Install Nagi.app」は .dmg のトップレベルからそのまま実行してください（他の場所にコピーすると動作しません）。" buttons {"OK"} default button "OK" with icon stop
	return
end if

set alreadyInstalled to (do shell script "test -d " & quoted form of targetApp & " && echo yes || echo no") is "yes"

if alreadyInstalled then
	set promptText to "Nagi は既にインストールされています。上書きしてインストールし直しますか？"
else
	set promptText to "Nagi をインストールします。/Library/Input Methods はシステムフォルダのため、管理者パスワードの入力を求められます。"
end if

set userChoice to button returned of (display dialog promptText buttons {"キャンセル", "インストール"} default button "インストール" cancel button "キャンセル" with icon note)

if userChoice is "インストール" then
	if alreadyInstalled then
		-- Best-effort: stop any already-running instance before
		-- overwriting it. Same reasoning as uninstall-ime.sh — an
		-- orphaned process holding an IMKit/XPC connection can make
		-- the copy below fail with "resource busy".
		do shell script "pkill -f '/Nagi.app/Contents/MacOS/Nagi' >/dev/null 2>&1; exit 0"
	end if

	do shell script "rm -rf " & quoted form of targetApp & " && cp -R " & quoted form of sourceApp & " " & quoted form of targetApp with administrator privileges

	-- Strip quarantine (see header) and open once, so registration
	-- (SMAppService + Text Input Source — see
	-- app/Sources/Nagi/ConverterServiceRegistration.swift and
	-- InputSourceRegistration.swift) runs immediately instead of
	-- waiting for the user to fight through Gatekeeper by hand.
	--
	-- No "install complete" dialog of our own here: Nagi.app's first
	-- launch already shows one (FirstRunPrompt.swift's "セットアップが
	-- 完了しました" alert, with a working "log out now" button this
	-- script can't offer) a moment after `open` returns — a second,
	-- OK-only dialog saying the same thing would just be a redundant
	-- extra click in front of the more useful one.
	do shell script "xattr -cr " & quoted form of targetApp & "; open " & quoted form of targetApp
end if
