#!/bin/sh
# Starts tailscaled. Mode (first argument): std (default, userspace networking),
# proxy (userspace plus a SOCKS5/HTTP proxy, address in proxy.address), tun (kernel TUN, not on all firmware).

BIN=/mnt/us/extensions/tailscale/bin
LOG=$BIN/tailscaled_start_log.txt

eips_log() {
    echo "$1" >> "$LOG"
    eips 0 22 "$(printf '%-50s' "$1")" 2>/dev/null
}

case $1 in
    proxy)
        PROXY_ADDR=localhost:1055
        [ -s "$BIN/proxy.address" ] && PROXY_ADDR=$(cat "$BIN/proxy.address")
        NAME="proxy: $PROXY_ADDR"
        set -- -tun userspace-networking --socks5-server="$PROXY_ADDR" --outbound-http-proxy-listen="$PROXY_ADDR" ;;
    tun) NAME="kernel TUN"; set -- ;;
    *) NAME=; set -- -tun userspace-networking ;;
esac

echo "[$(date)] Starting tailscaled${NAME:+ ($NAME)}..." > "$LOG"

# Kill any existing instance and remove stale socket before starting.
# This makes it safe to switch modes without explicitly stopping first.
pkill tailscaled 2>/dev/null || true
sleep 2
rm -f /var/run/tailscale/tailscaled.sock

eips_log "Starting tailscaled${NAME:+ ($NAME)}..."

nohup "$BIN/tailscaled" --statedir="$BIN/" "$@" >> "$LOG" 2>&1 &
DAEMON_PID=$!

sleep 3
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    eips_log "tailscaled started OK${NAME:+ ($NAME)}"
elif [ "$NAME" = "kernel TUN" ]; then
    eips_log "tailscaled failed - kernel TUN may not be supported"
else
    eips_log "tailscaled failed to start - check log"
fi
