Nagi — install

1. Drag Nagi.app onto the "Input Methods" icon in this window.
   macOS will ask for your admin password — that's normal and expected,
   Input Methods is a system folder.

2. Open Nagi.app once (double-click it in /Library/Input Methods/).
   macOS will very likely warn that it can't verify the developer —
   that's expected too, this app isn't notarized (no paid Apple
   Developer ID behind this project). To open it anyway:
     - Control-click (or right-click) Nagi.app, choose "Open", then
       click "Open" again in the dialog that appears.
   Opening it this one time is all it takes — Nagi finishes setting
   itself up automatically, including copying "Uninstall Nagi.app" into
   your Applications folder for later. No restart needed.

   If step 2 above doesn't offer an "Open" option (some versions of
   macOS instead say the app "is damaged"), it's not actually damaged —
   this is Gatekeeper being extra cautious about unnotarized apps. Open
   Terminal (Applications > Utilities > Terminal) and paste this one
   line, then try opening Nagi.app again:
     xattr -cr "/Library/Input Methods/Nagi.app"

3. Open System Settings > Keyboard > Input Sources. "Nagi" should
   already be listed under Japanese — no need to click "+". If you also
   have Google 日本語入力, macSKK, or another Mozc-based IME installed,
   you may see more than one entry named "ひらがな" — check the little
   icon next to each one to tell them apart.
   (Not showing up? Click Edit... > "+" > find "Nagi" under Japanese >
   Add, and it'll work from there.)

4. Switch to it from the input menu in your menu bar. Try it in
   TextEdit: type "nagi" and press Enter — it should turn into "なぎ".

That's it — no restart required anywhere in this process, and no second
app to drag anywhere: dragging Nagi.app in step 1 is the only drag.

---

Uninstall

Double-click "Uninstall Nagi.app" in your Applications folder
(Launchpad or Finder both work) — it ended up there on its own after
step 2 above. It asks you to confirm, then for your admin password, and
then removes everything: the app, its background process, and its
entry in Input Sources.

(Never got past step 2 above — Nagi.app wouldn't open at all? Use the
"Uninstall Nagi.app" in this window instead; it does the same thing.)

One small thing it can't clean up: an empty, unlabeled row can be left
behind under the 日本語 (Japanese) group in Input Sources. It's harmless
and you can't accidentally switch to it — but if it bothers you, a
restart clears it completely. The uninstaller will offer to restart for
you; feel free to say no and do it later, whenever's convenient.

Once it's done, it removes itself too — there's nothing left over to
throw away by hand.
