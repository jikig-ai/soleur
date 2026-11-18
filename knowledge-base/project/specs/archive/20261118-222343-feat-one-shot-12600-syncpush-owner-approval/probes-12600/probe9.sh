#!/usr/bin/env bash
# Phase 0.2 (synthesized fixture): ls-remote --symref and fetch --depth 1 of soleur/kb-sync on the hardened isolated
# arm shape (server-written bare GIT_DIR, workspace objects as the only alternate, HOME = the isolated dir,
# GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1, the HARDENED_GIT_ARGS -c list) against a file:// bare remote,
# GIT_ALLOW_PROTOCOL widened to file exactly as test/push-branch-isolated-real-git.test.ts does.
# Usage: probe9.sh [scratch-root]
set -euo pipefail
if [ -n "${1:-}" ]; then BASE=$1; else BASE=$(mktemp -d); trap 'rm -rf "$BASE"' EXIT; fi
R="$BASE/p9-$$"; mkdir -p "$R"; cd "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main --bare remote.git
g init -q -b main seed; cd seed; mkdir -p knowledge-base src; echo a > knowledge-base/a.md; echo s > src/s.ts
g add -A; g commit -qm init; g remote add origin ../remote.git; g push -q origin main
g checkout -q -b soleur/kb-sync; echo side >> knowledge-base/a.md; g commit -qam side; g push -q origin soleur/kb-sync; cd ..
git clone -q --depth 1 "file://$R/remote.git" ws
ISO="$R/iso.git"; mkdir -p "$ISO/objects/info" "$ISO/objects/pack" "$ISO/refs/heads"; echo 'ref: refs/heads/main' > "$ISO/HEAD"
printf '[core]\n\trepositoryformatversion = 0\n\tbare = true\n' > "$ISO/config"; cp ws/.git/shallow "$ISO/shallow"
H=(--no-replace-objects -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.attributesFile=/dev/null -c http.proxy= -c http.extraHeader= -c push.followTags=false -c credential.helper=)
iso() { env -i PATH="$PATH" HOME="$ISO" GIT_DIR="$ISO" GIT_ALTERNATE_OBJECT_DIRECTORIES="$R/ws/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_NO_REPLACE_OBJECTS=1 GIT_ALLOW_PROTOCOL=file git "${H[@]}" "$@"; }
echo "--- ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync"
iso ls-remote --symref "file://$R/remote.git" HEAD refs/heads/soleur/kb-sync | sed -E 's/[0-9a-f]{40}/<sha>/'
echo "rc=${PIPESTATUS[0]}"
SIDE=$(git -C remote.git rev-parse refs/heads/soleur/kb-sync)
echo "side present in ws before fetch: $(iso cat-file -e "$SIDE^{commit}" 2>/dev/null && echo yes || echo no)"
echo "--- fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync"
iso fetch -q --depth 1 --no-tags "file://$R/remote.git" refs/heads/soleur/kb-sync; echo "rc=$?"
echo "FETCH_HEAD == side tip: $([ "$(iso rev-parse FETCH_HEAD)" = "$SIDE" ] && echo yes || echo no)"
echo "side present after fetch: $(iso cat-file -e "$SIDE^{commit}" 2>/dev/null && echo yes || echo no)"
echo "workspace shallow unchanged: $(cmp -s ws/.git/shallow <(git -C remote.git rev-parse main) && echo yes || echo no)"
echo "isolated shallow lines: $(wc -l < "$ISO/shallow")"
git --version
