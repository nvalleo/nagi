-- Uninstall Nagi.applescript — double-clickable uninstaller, compiled
-- to "Uninstall Nagi.app" by scripts/build-uninstaller.sh and bundled
-- into the .dmg (#30 follow-up). GUI counterpart to
-- scripts/uninstall-ime.sh, for people who installed via the .dmg and
-- don't have/want a Terminal — admin authentication (when removing from
-- the system-wide /Library/Input Methods/) is a native macOS password
-- dialog via `do shell script ... with administrator privileges`, not a
-- `sudo` prompt.
--
-- Mirrors uninstall-ime.sh's behavior: removes the Nagi.app bundle(s)
-- and stops the running NagiConverter LaunchAgent job. Also kills any
-- running Nagi host process first — harmless if there is none, and
-- means a leftover menu bar icon doesn't linger after this app tells
-- you the uninstall is done.
--
-- Goes one step further than uninstall-ime.sh: after removing the
-- files, it also runs the bundled nagi-tis-disable helper (see
-- scripts/build-uninstaller.sh) to clear the named "ひらがな (Nagi)"
-- Input Sources entry immediately, instead of leaving that as a manual
-- "select it, click −" step. Confirmed working (#30 follow-up) — the
-- entry itself is gone as soon as System Settings' Keyboard pane is
-- closed and reopened.
--
-- One residual artifact even after that: an empty/blank row can be left
-- behind under the 日本語 (Japanese) language group in the Input
-- Sources list — cosmetic, not switchable to, but only a real reboot
-- clears it (same as Google 日本語入力's own uninstaller, which
-- suggests — doesn't force — a restart afterwards for the same reason).
-- This dialog mirrors that: offers a restart, doesn't require one.
--
-- Deletes itself as the very last step, once everything above has
-- succeeded (#33 follow-up). It's meant to be found in /Applications
-- (the .dmg gives it that as a drop target, see build-dmg.sh) for as
-- long as Nagi is actually installed, not to linger forever once
-- there's nothing left for it to uninstall — same convention as most
-- uninstaller utilities, self included.

set systemApp to "/Library/Input Methods/Nagi.app"
set userApp to (POSIX path of (path to home folder)) & "Library/Input Methods/Nagi.app"

set systemAppExists to (do shell script "test -d " & quoted form of systemApp & " && echo yes || echo no") is "yes"
set userAppExists to (do shell script "test -d " & quoted form of userApp & " && echo yes || echo no") is "yes"

if not systemAppExists and not userAppExists then
	display dialog "Nagi.app が見つかりませんでした。既にアンインストール済みかもしれません。" buttons {"OK"} default button "OK" with icon note
	return
end if

set userChoice to button returned of (display dialog "Nagi をアンインストールします。よろしいですか？" buttons {"キャンセル", "アンインストール"} default button "アンインストール" cancel button "キャンセル" with icon caution)

if userChoice is "アンインストール" then
	-- Best-effort: stop the running Nagi host process and the
	-- NagiConverter LaunchAgent job before removing files. Failures
	-- here just mean neither was running — not an error.
	do shell script "pkill -f '/Nagi.app/Contents/MacOS/Nagi' >/dev/null 2>&1; launchctl bootout gui/$(id -u)/com.nvleo.inputmethod.nagi.Converter >/dev/null 2>&1; exit 0"

	if systemAppExists then
		do shell script "rm -rf " & quoted form of systemApp with administrator privileges
	end if

	if userAppExists then
		do shell script "rm -rf " & quoted form of userApp
	end if

	-- Best-effort: try to clear the stale Input Sources entry
	-- immediately, now that the backing bundle is gone. Ignore
	-- failures — the manual "select it, click −" fallback mentioned
	-- below still works either way.
	set helperPath to (POSIX path of (path to me)) & "Contents/Resources/nagi-tis-disable"
	do shell script quoted form of helperPath & " >/dev/null 2>&1; exit 0"

	-- Reset the one-shot "log out and back in" prompt (FirstRunPrompt.swift,
	-- app/Sources/Nagi/) so a later reinstall shows it again instead of
	-- staying permanently silent — its UserDefaults flag lives in
	-- ~/Library/Preferences/, which removing the app bundle above doesn't
	-- touch (#32 follow-up).
	do shell script "defaults delete com.nvleo.inputmethod.nagi FirstRunLogoutPromptShown >/dev/null 2>&1; exit 0"

	set restartChoice to button returned of (display dialog "Nagi をアンインストールしました。" & return & return & "「日本語」の入力ソース一覧に空欄の行が残ることがあります。実害はありませんが、完全に消すには再起動が必要です（今すぐでなくても構いません）。" buttons {"後で", "今すぐ再起動"} default button "後で" with icon note)

	-- Finally, remove the uninstaller itself — otherwise it lives
	-- forever wherever it was dragged (typically /Applications, #33
	-- follow-up: the .dmg gives it that as a drop target specifically
	-- so it survives the .dmg being ejected/deleted, which also means
	-- nothing else ever cleans it up). Removing a running app's own
	-- bundle is fine on macOS — unlike Finder's GUI trash (which
	-- refuses while a process is "open"), a plain rm/unlink works
	-- immediately, and this process keeps running to completion on its
	-- already-loaded pages regardless.
	do shell script "rm -rf " & quoted form of (POSIX path of (path to me))

	if restartChoice is "今すぐ再起動" then
		tell application "System Events" to restart
	end if
end if
