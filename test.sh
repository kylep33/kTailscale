#!/bin/sh
# Checks on a PC: ctl.sh's input checks that guard root commands, rename's up.args, the status JSON,
# and that update_tailscale.sh swaps in both binaries or neither.
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp ctl.sh "$T/" && mkdir "$T/bin" && cp -r stub "$T/"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/tailscale" && chmod +x "$T/bin/tailscale"  # stand-in: "tailscale set" succeeds
export KT_BIN="$T/bin"
fail=0
no() { echo "FAIL: $*"; fail=1; }
rejects() { if sh "$T/ctl.sh" "$@" >/dev/null 2>&1; then no "accepted: $*"; fi; }

rejects key 'tskey-a;reboot'
rejects key 'tskey-$(reboot)'
rejects key 'tskey-a b'
rejects key tskey-
rejects key notakey
rejects rename -x
rejects rename 'a b'
rejects rename 'a;reboot'
rejects rename ''
rejects rename "$(printf '%064d' 0)"
rejects mode 'proxy;reboot'
[ -e "$T/bin/auth.key" ] && no "a rejected key was written"

sh "$T/ctl.sh" key tskey-auth-Ab_9-x >/dev/null 2>&1 || no "rejected a valid key"
[ "$(cat "$T/bin/auth.key")" = tskey-auth-Ab_9-x ] || no "key not saved"

echo '--ssh --hostname=old' > "$T/bin/up.args"
sh "$T/ctl.sh" rename kindle2 >/dev/null 2>&1 || no "rename failed"
[ "$(cat "$T/bin/up.args")" = '--ssh --hostname=kindle2' ] || no "up.args after rename: $(cat "$T/bin/up.args")"
rm "$T/bin/up.args"
sh "$T/ctl.sh" rename kindle3 >/dev/null 2>&1
[ "$(cat "$T/bin/up.args")" = '--hostname=kindle3' ] || no "up.args from nothing: $(cat "$T/bin/up.args")"

printf 'localhost:1080"\\\r\n' > "$T/bin/proxy.address"  # Windows line ending plus JSON-breaking characters
sh "$T/ctl.sh" status
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["proxy"]=="localhost:1080", d["proxy"]' "$T/app/state/ui.txt" || no "status JSON"

echo '[::1]:1080' > "$T/bin/proxy.address"
sh "$T/ctl.sh" status
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["proxy"]=="[::1]:1080", d["proxy"]' "$T/app/state/ui.txt" || no "IPv6 proxy"

# update_tailscale.sh, with a fake curl that serves a local tarball for version 1.2.3.
mkdir -p "$T/fake" "$T/pkg/tailscale_1.2.3_arm"
cat > "$T/fake/curl" <<'CURL'
#!/bin/sh
case "$*" in
    *http_code*) echo 200 ;;
    *" -o "*) while [ "$1" != -o ]; do shift; done; cp "$FAKE_TGZ" "$2" ;;
    *) echo '[{"tag_name":"v1.2.3"}]' ;;
esac
CURL
chmod +x "$T/fake/curl"
export FAKE_TGZ="$T/ts.tgz"
echo new > "$T/pkg/tailscale_1.2.3_arm/tailscale"; echo new > "$T/pkg/tailscale_1.2.3_arm/tailscaled"
tar czf "$FAKE_TGZ" -C "$T/pkg" tailscale_1.2.3_arm
upd() { PATH="$T/fake:$T/stub:$PATH" sh tailscale/bin/update_tailscale.sh; }
echo old > "$T/bin/tailscaled"; cp "$T/bin/tailscale" "$T/bin/tailscale.orig"; echo old > "$T/bin/tailscale.bak"

mkdir "$T/bin/tailscaled.new" && chmod 555 "$T/bin/tailscaled.new"  # the second copy fails (unless run as root)
upd 2>/dev/null && no "update with a failed copy succeeded"
[ "$(cat "$T/bin/tailscaled")" = old ] && cmp -s "$T/bin/tailscale" "$T/bin/tailscale.orig" || no "a failed update changed the binaries"
ls "$T/bin" | grep -q '\.new$' && no "a failed update left .new files"

upd || no "update failed: $(tail -n 3 "$T/bin/update_log.txt")"
[ "$(cat "$T/bin/tailscale")" = new ] && [ "$(cat "$T/bin/tailscaled")" = new ] || no "update did not replace both binaries"
ls "$T/bin" | grep -q '\.new$\|\.bak$' && no "update left .new or .bak files"

[ $fail = 0 ] && echo "ctl.sh and update_tailscale.sh: all checks passed"
exit $fail
