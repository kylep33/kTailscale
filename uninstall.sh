#!/bin/sh
# On upgrade KPM reinstalls right after, so keep the binaries, auth key and login state.
[ "$1" = "upgrade" ] && exit 0
DEST=/mnt/us/extensions/tailscale
[ -x "$DEST/bin/tailscale" ] && "$DEST/bin/tailscale" down
pkill tailscaled
sleep 2
[ -x "$DEST/bin/tailscaled" ] && "$DEST/bin/tailscaled" -cleanup
rm -f /var/run/tailscale/tailscaled.sock
rm -rf "$DEST"
exit 0
