#!/bin/sh
# kTailscale backend. The app runs it through utild; the boot job runs "ctl.sh boot".
# Usage: ctl.sh status|on|off|boot|install|autostart 0|1|awake 0|1|mode std|proxy|tun|key KEY|rename NAME
# It drives mitanshu7's KUAL scripts in extensions/tailscale/bin and writes app/state/ui.txt for the app to read.
PKG=$(cd "$(dirname "$0")" && pwd)
BIN=/mnt/us/extensions/tailscale/bin
ST=$PKG/app/state
LOG=$ST/log.txt
BUSY=/tmp/ktailscale.busy
LOCK=/tmp/ktailscale.lock
# The KUAL scripts print to the screen with eips; our stub sends those lines to the log instead.
export PATH="$PKG/stub:$PATH" KT_LOG="$LOG"
mkdir -p "$ST"

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }
yes_if() { if "$@"; then echo true; else echo false; fi; }
running() { pidof tailscaled >/dev/null 2>&1; }
mode() { case $(cat "$BIN/mode" 2>/dev/null) in proxy) echo proxy ;; tun) echo tun ;; *) echo std ;; esac; }
proxy() { if [ -s "$BIN/proxy.address" ]; then tr -d '"\\\n' < "$BIN/proxy.address"; else echo localhost:1055; fi; }
awake() { [ -e "$BIN/awake" ] && lipc-set-prop com.lab126.powerd preventScreenSaver "$1" 2>/dev/null; }

status() {
    ts=null
    if running; then
        out=$(timeout 5 "$BIN/tailscale" status --json --peers=false 2>/dev/null) && [ -n "$out" ] && ts=$out
    fi
    printf '{"installed":%s,"autostart":%s,"awake":%s,"haskey":%s,"mode":"%s","proxy":"%s","busy":"%s","ts":%s}\n' \
        "$(yes_if [ -e "$BIN/tailscaled" ])" "$(yes_if [ ! -e "$BIN/no-autostart" ])" "$(yes_if [ -e "$BIN/awake" ])" \
        "$(yes_if [ -s "$BIN/auth.key" ])" "$(mode)" "$(proxy)" "$(cat "$BUSY" 2>/dev/null)" "$ts" > "$ST/ui.tmp" &&
        mv "$ST/ui.tmp" "$ST/ui.txt"
}

# Long actions: one at a time, shown in the app as busy until done.
run() {
    mkdir "$LOCK" 2>/dev/null || { log "Busy with something else, try again in a moment"; exit 1; }
    trap 'rm -f "$BUSY"; rmdir "$LOCK" 2>/dev/null' EXIT
    echo "$1" > "$BUSY"; shift
    status
    "$@"
    rm -f "$BUSY"
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    status
}

turn_on() {
    [ -e "$BIN/tailscaled" ] || { log "Tailscale isn't installed yet: tap Install"; return 1; }
    case $(mode) in proxy) s=start_tailscaled_proxy.sh ;; tun) s=start_tailscaled_tun.sh ;; *) s=start_tailscaled.sh ;; esac
    log "Turning on ($(mode) mode)"
    sh "$BIN/$s"
    # The auth-key login in start_tailscale.sh has no timeout of its own and can hang without Wi-Fi.
    timeout 90 sh "$BIN/start_tailscale.sh"
    awake 1
}

turn_off() {
    log "Turning off"
    sh "$BIN/stop_tailscale.sh"
    sh "$BIN/stop_tailscaled.sh"
    awake 0
}

case $1 in
    status) status ;;
    on) run "Turning on..." turn_on ;;
    off) run "Turning off..." turn_off ;;
    boot)
        # Give Wi-Fi up to 2 minutes; if it never connects, tailscaled still connects once it does.
        i=0
        while [ $i -lt 60 ] && [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" != CONNECTED ]; do sleep 2; i=$((i + 1)); done
        run "Turning on..." turn_on ;;
    install) run "Installing Tailscale (about 31 MB)..." sh "$BIN/update_tailscale.sh" ;;
    autostart)
        if [ "$2" = 1 ]; then rm -f "$BIN/no-autostart"; else touch "$BIN/no-autostart"; fi
        status ;;
    awake)
        if [ "$2" = 1 ]; then touch "$BIN/awake"; running && awake 1; else awake 0; rm -f "$BIN/awake"; fi
        status ;;
    mode)
        case $2 in std | proxy | tun) echo "$2" > "$BIN/mode" ;; *) exit 1 ;; esac
        if running; then run "Switching mode..." turn_on; else status; fi ;;
    key)
        # Runs as root with text typed in the app: allow only what a Tailscale key can contain.
        case $2 in tskey-*[!A-Za-z0-9_-]* | tskey-) exit 1 ;; tskey-*) ;; *) exit 1 ;; esac
        printf '%s\n' "$2" > "$BIN/auth.key"
        log "Auth key saved"
        status ;;
    rename)
        case $2 in "" | -* | *[!A-Za-z0-9-]*) exit 1 ;; esac
        [ ${#2} -le 63 ] || exit 1
        run "Renaming..." sh -c '"$1/tailscale" set --hostname="$2" >> "$3" 2>&1 && echo "$(date +%H:%M:%S) Renamed to $2" >> "$3"' _ "$BIN" "$2" "$LOG" ;;
    *) echo "usage: ctl.sh status|on|off|boot|install|autostart 0|1|awake 0|1|mode std|proxy|tun|key KEY|rename NAME"; exit 1 ;;
esac
