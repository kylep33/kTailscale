#!/bin/sh
# "kpm launch ktailscale" runs this from the package folder.
# utild lets the app run ctl.sh. It forks into the background, and exits if another app already started it.
B=utild/UtildSF
[ -e /lib/ld-linux-armhf.so.3 ] && B=utild/UtildHF
chmod +x "$B" ctl.sh stub/eips 2>/dev/null
"./$B" >/dev/null 2>&1
lipc-set-prop com.lab126.appmgrd start app://com.kylep33.ktailscale
