#!/bin/sh
# Release to KPM: ./release.sh 0.0.2 "what changed"
# Bumps the version in manifest.json, app/config.xml and app/index.html, packs the .kpkg into the KPM repo
# (../kile-kpm-repo, or $KPM_REPO), lists it in the repo manifest, commits and pushes.
set -e
V=$1; MSG=$2
HERE=$(cd "$(dirname "$0")" && pwd); REPO=${KPM_REPO:-$HERE/../kile-kpm-repo}
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && [ -n "$MSG" ] || { echo 'usage: release.sh X.Y.Z "what changed"'; exit 1; }
OUT=$REPO/packages/ktailscale/artifacts/ktailscale_${V}_kindleany.kpkg
[ ! -e "$OUT" ] || { echo "$OUT already exists"; exit 1; }
[ -z "$(git -C "$REPO" status --porcelain)" ] || { echo "$REPO has uncommitted changes"; exit 1; }

cd "$HERE"
[ ! -s tailscale/bin/auth.key ] || { echo "tailscale/bin/auth.key is not empty, refusing to publish it"; exit 1; }
sed -i -E "s/\"version\": \[[0-9, ]+\]/\"version\": [$(echo "$V" | sed 's/\./, /g')]/" manifest.json
sed -i -E "s/(<widget [^>]*version=\")[0-9.]+\"/\1$V\"/" app/config.xml
sed -i -E "s/var VERSION = '[0-9.]+'/var VERSION = '$V'/" app/index.html

# A .kpkg is a gzipped tar with the package files at its root. Only tracked files, so local binaries and logs stay out.
[ -z "$(git status --porcelain -- . ':!manifest.json' ':!app/config.xml' ':!app/index.html')" ] || { echo "commit your changes first"; exit 1; }
mkdir -p "$(dirname "$OUT")"
tar czf "$OUT" $(git ls-files | grep -v -x -e release.sh -e README.md -e .gitignore)

python3 - "$REPO/manifest.json" "$V" manifest.json <<'PY'
import json, sys
path, v, pkg = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
m = json.load(open(path))
entry = m["packages"].setdefault("ktailscale", {"artifacts": []})
entry.update(name=pkg["name"], author=pkg["author"], description=pkg["description"])
entry["artifacts"].append({"url": f"packages/ktailscale/artifacts/ktailscale_{v}_kindleany.kpkg",
    "version": [int(x) for x in v.split(".")], "dependencies": [], "supported_platforms": None})
open(path, "w").write(json.dumps(m))
PY

cd "$REPO"
git add manifest.json "$OUT"
git commit -q -m "ktailscale $V: $MSG"
git push -q
gh workflow run publish.yml -R "$(git remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')"  # pushes have not been triggering the deploy
echo "released ktailscale $V"
