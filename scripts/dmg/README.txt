Nagi — install

1. Drag Nagi.app onto the "Input Methods" icon in this window. macOS
   will ask for your admin password — that's normal, /Library/Input
   Methods/ is a system folder.

2. First time only: macOS will likely block opening Nagi.app itself,
   because it isn't notarized (this project has no paid Apple Developer
   ID — see the main README for why). Either:
     - Control-click Nagi.app in /Library/Input Methods/ > Open > Open
       (again, in the dialog that appears), or
     - if that doesn't offer an "Open" option, run this in Terminal:
         xattr -cr "/Library/Input Methods/Nagi.app"
       and try opening it again.
   Opening it once is what registers the bundled NagiConverter — you
   don't need to do anything else for that part.

3. Reboot the machine. Not log out/in — a full reboot. macOS only
   re-scans its Input Source registry on a full boot.

4. System Settings > Keyboard > Input Sources > Edit... > "+" > find
   "Nagi" under Japanese > Add. If Google 日本語入力, macSKK, or another
   Mozc-based IME is also installed, there may be multiple entries named
   "ひらがな" — check the icon to tell Nagi's apart.

5. Switch to it from the menu bar Input menu. In TextEdit, type "nagi"
   then Enter — expect "なぎ".

To uninstall: delete /Library/Input Methods/Nagi.app, or, if you have
this project's source checked out, run
  ./scripts/uninstall-ime.sh --system
which also stops the running NagiConverter service.
