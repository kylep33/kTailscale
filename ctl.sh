#!/bin/sh
# kTailscale backend. The app runs it through utild; the boot job runs "ctl.sh boot".
# usage: ctl.sh status|on|off|boot|install|autostart 0|1|awake 0|1|mode std|proxy|tun|key KEY|rename NAME
# It drives mitanshu7's KUAL scripts in extensions/tailscale/bin and writes app/state/ui.txt for the app to read.
PKG=$(cd "$(dirname "$0")" && pwd)
BIN=${KT_BIN:-/mnt/us/extensions/tailscale/bin}  # test.sh points this at a temp folder
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
# Only address characters, so a hand-edited file can't break the JSON.
proxy() { if [ -s "$BIN/proxy.address" ]; then tr -cd '][A-Za-z0-9.:-' < "$BIN/proxy.address"; else echo localhost:1055; fi; }
awake() { [ -e "$BIN/awake" ] && lipc-set-prop com.lab126.powerd preventScreenSaver "$1" 2>/dev/null; }

status() {
    ts=null
    if running; then
        out=$(timeout 5 "$BIN/tailscale" status --json --peers=false 2>/dev/null) && [ -n "$out" ] && ts=$out
    fi
    # tailscaled writes to its start log for as long as it runs. It opened the log to append, so emptying it is safe.
    find "$BIN" -maxdepth 1 -name 'tailscaled*_log.txt' -size +1024k 2>/dev/null | while read -r f; do : > "$f"; done
    printf '{"installed":%s,"autostart":%s,"awake":%s,"haskey":%s,"mode":"%s","proxy":"%s","busy":"%s","ts":%s}\n' \
        "$(yes_if [ -e "$BIN/tailscaled" ])" "$(yes_if [ ! -e "$BIN/no-autostart" ])" "$(yes_if [ -e "$BIN/awake" ])" \
        "$(yes_if [ -s "$BIN/auth.key" ])" "$(mode)" "$(proxy)" "$(cat "$BUSY" 2>/dev/null)" "$ts" > "$ST/ui.$$" &&
        mv "$ST/ui.$$" "$ST/ui.txt"
}

# Long actions: one at a time, shown in the app as busy until done.
run() {
    if ! mkdir "$LOCK" 2>/dev/null; then
        # A run that was killed outright (say, out of memory mid-install) leaves its lock behind. Take the lock once that process is gone.
        # shortcut: two runs started within the same millisecond could both get in; taps are much further apart than that.
        kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null && { log "Busy with something else, try again in a moment"; exit 1; }
    fi
    echo $$ > "$LOCK/pid"
    trap 'rm -rf "$BUSY" "$LOCK"' EXIT
    echo "$1" > "$BUSY"; shift
    status
    "$@"
    rm -f "$BUSY"
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    status
}

turn_on() {
    [ -e "$BIN/tailscaled" ] || { log "Tailscale isn't installed yet: tap Install"; return 1; }
    # Files edited on Windows end their lines with \r, which breaks the flags and the key.
    for f in auth.key up.args proxy.address; do [ -f "$BIN/$f" ] && sed -i 's/\r$//' "$BIN/$f"; done
    log "Turning on ($(mode) mode)"
    sh "$BIN/start_tailscaled.sh" "$(mode)"
    # The auth-key login in start_tailscale.sh has no timeout of its own and can hang without Wi-Fi.
    timeout 90 sh "$BIN/start_tailscale.sh" && awake 1
}

turn_off() {
    log "Turning off"
    sh "$BIN/stop_tailscale.sh"
    sh "$BIN/stop_tailscaled.sh"
    awake 0
}

update() {
    old=$("$BIN/tailscale" version 2>/dev/null | head -1)
    sh "$BIN/update_tailscale.sh"
    # The update puts the new binaries in place even while tailscaled runs. Restart it so the new version is the one running.
    running && [ "$("$BIN/tailscale" version 2>/dev/null | head -1)" != "$old" ] && turn_on
}

rename_to() {
    "$BIN/tailscale" set --hostname="$1" >> "$LOG" 2>&1 || return 1
    # "tailscale up" refuses to run unless it repeats every setting changed earlier, so put the name in up.args too.
    a=$(tr -d '\r\n' < "$BIN/up.args" 2>/dev/null | sed 's/ *--hostname[= ][^ ]*//g')
    printf '%s--hostname=%s\n' "${a:+$a }" "$1" > "$BIN/up.args"
    log "Renamed to $1"
}

case $1 in
    status) status ;;
    on) run "Turning on..." turn_on ;;
    off) run "Turning off..." turn_off ;;
    boot)
        # Give Wi-Fi up to 2 minutes; if it never connects, tailscaled still connects once it does.
        i=0
        while [ $i -lt 60 ] && [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" != CONNECTED ]; do sleep 2; i=$((i + 1)); done
        # The user may have turned it on from the app while we waited.
        running || run "Turning on..." turn_on ;;
    install) run "Installing Tailscale (about 31 MB)..." update ;;
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
        run "Renaming..." rename_to "$2" ;;
    *) sed -n '3s/^# //p' "$0"; exit 1 ;;
esac
