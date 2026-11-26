#!/bin/sh
# KPM runs this from the package folder after unpacking.
PKG=$(pwd)
APP_ID=com.kylep33.ktailscale
DEST=/mnt/us/extensions/tailscale

# The KUAL extension (mitanshu7's scripts), which the app drives.
mkdir -p "$DEST/bin"
cp tailscale/config.xml tailscale/menu.json "$DEST/"
cp tailscale/bin/*.sh "$DEST/bin/" && chmod +x "$DEST"/bin/*.sh
# Keep the user's settings across upgrades. Binaries and tailscaled.state are not in the package, so they are untouched.
for f in auth.key up.args proxy.address; do
    [ -e "$DEST/bin/$f" ] || cp "tailscale/bin/$f" "$DEST/bin/"
done
chmod +x ctl.sh launch.sh stub/eips utild/* 2>/dev/null

# Register the Mesquite app (appreg.db lives in /var/local, not the read-only rootfs).
sqlite3 /var/local/appreg.db <<SQL
INSERT OR IGNORE INTO handlerIds VALUES('$APP_ID');
INSERT OR REPLACE INTO properties VALUES('$APP_ID','lipcId','$APP_ID');
INSERT OR REPLACE INTO properties VALUES('$APP_ID','command','/usr/bin/mesquite -l $APP_ID -c file://$PKG/app/');
INSERT OR REPLACE INTO properties VALUES('$APP_ID','supportedOrientation','U');
SQL

# Library tile that opens the app.
cp ktailscale.sh /mnt/us/documents/ktailscale.sh

# Boot job for "Turn on Tailscale by default". /etc is read-only, so only remount when it changed.
sed "s#@PKG@#$PKG#" ktailscale.conf > /tmp/ktailscale.conf
if ! cmp -s /tmp/ktailscale.conf /etc/upstart/ktailscale.conf; then
    if mntroot rw && cp /tmp/ktailscale.conf /etc/upstart/ktailscale.conf; then
        echo "Boot job installed"
    else
        echo "Could not install the boot job: Tailscale won't turn on by itself at boot"
    fi
    mntroot ro
fi
rm -f /tmp/ktailscale.conf
echo "kTailscale installed. Open it from your library."
