#!/bin/sh
# KPM runs this from the package folder after unpacking.
DEST=/mnt/us/extensions/tailscale
mkdir -p "$DEST/bin"
cp tailscale/config.xml tailscale/menu.json "$DEST/"
cp tailscale/bin/*.sh "$DEST/bin/" && chmod +x "$DEST"/bin/*.sh
# Keep the user's settings across upgrades. Binaries and tailscaled.state are not in the package, so they are untouched.
for f in auth.key up.args proxy.address; do
    [ -e "$DEST/bin/$f" ] || cp "tailscale/bin/$f" "$DEST/bin/"
done
echo "tailscale installed. In KUAL: Tailscale > Install / Update Binaries, then fill in $DEST/bin/auth.key."
