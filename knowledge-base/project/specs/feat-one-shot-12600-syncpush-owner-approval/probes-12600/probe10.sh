#!/usr/bin/env bash
# Phase 0.3 (synthesized fixture): a two-parent side commit (P, T) built on an older side tip P, pushed to soleur/kb-sync;
# after a simulated PR merge into main, `pull --ff-only` in the workspace (whose main = side by CAS) is a fast-forward.
# Usage: probe10.sh [scratch-root]
set -euo pipefail
if [ -n "${1:-}" ]; then BASE=$1; else BASE=$(mktemp -d); trap 'rm -rf "$BASE"' EXIT; fi
R="$BASE/p10-$$"; mkdir -p "$R"; cd "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }
# Portable KB-entry swap (no awk: mawk in the runner image has no NUL RS and no {40} intervals, which silently
# left the tree unchanged on the first runner run). Reads `ls-tree -z` records, rewrites the knowledge-base entry.
kbswap() { local base=$1 kb=$2 rec; while IFS= read -r -d '' rec; do
  if [[ "$rec" == *$'\t'knowledge-base ]]; then printf '040000 tree %s\tknowledge-base\0' "$kb"; else printf '%s\0' "$rec"; fi
done < <(git ls-tree -z "$base"); }
git init -q -b main --bare remote.git
g init -q -b main seed; cd seed; mkdir -p knowledge-base src; echo a > knowledge-base/a.md; echo s > src/s.ts
g add -A; g commit -qm T0; g remote add origin ../remote.git; g push -q origin main; T0=$(git rev-parse HEAD)
# older side tip P on T0
g checkout -q -b side; echo p >> knowledge-base/a.md; g commit -qam P; P=$(git rev-parse HEAD); g push -q origin side:refs/heads/soleur/kb-sync
# upstream main moves on (code change) -> T
g checkout -q main; echo t >> src/s.ts; g commit -qam T; g push -q origin main; T=$(git rev-parse HEAD); cd ..
git clone -q --depth 1 "file://$R/remote.git" ws; cd ws
echo k >> knowledge-base/a.md; g commit -qam "Auto-commit after session"; H=$(git rev-parse HEAD)
KB=$(git rev-parse "$H:knowledge-base")
TREE=$(kbswap "$T" "$KB" | git mktree -z)
echo "S tree differs from T tree: $([ "$TREE" != "$(git rev-parse "$T"^{tree})" ] && echo yes || echo NO)"
git fetch -q --depth 1 origin refs/heads/soleur/kb-sync
SIDE=$(g commit-tree "$TREE" -p "$P" -p "$T" -m "Soleur: sync knowledge-base")
git push -q origin "$SIDE:refs/heads/soleur/kb-sync" && echo "side push (non-force) ok"
git update-ref --no-deref refs/heads/main "$SIDE" "$H" && echo "local main CAS to side ok"
git update-ref --no-deref refs/remotes/origin/main "$SIDE"
cd ..; g clone -q "file://$R/remote.git" merger; cd merger
g merge -q --no-ff -m "Merge PR" origin/soleur/kb-sync && g push -q origin main && echo "PR merge simulated"
cd ../ws
if g pull -q --ff-only origin main; then echo "pull --ff-only after PR merge: fast-forward ok"; else echo "pull --ff-only FAILED"; fi
git merge-base --is-ancestor "$SIDE" HEAD && echo "side is an ancestor of local HEAD"
git --version
