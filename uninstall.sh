#!/bin/sh
# On upgrade KPM reinstalls right after, so keep everything.
[ "$1" = "upgrade" ] && exit 0
APP_ID=com.kylep33.ktailscale
DEST=/mnt/us/extensions/tailscale
sh ./ctl.sh off >/dev/null 2>&1
pkill tailscaled
rm -f /var/run/tailscale/tailscaled.sock
if [ -e /etc/upstart/ktailscale.conf ]; then
    mntroot rw && rm -f /etc/upstart/ktailscale.conf
    mntroot ro
fi
sqlite3 /var/local/appreg.db <<SQL
DELETE FROM properties WHERE handlerId='$APP_ID';
DELETE FROM handlerIds WHERE handlerId='$APP_ID';
SQL
rm -f /mnt/us/documents/ktailscale.sh
if [ -e "$DEST/.made-by-ktailscale" ]; then
    rm -rf "$DEST"
else
    # The KUAL extension was there before us: keep its binaries, key and tailscaled.state, drop only our settings.
    rm -f "$DEST/bin/mode" "$DEST/bin/awake" "$DEST/bin/no-autostart"
fi
exit 0
