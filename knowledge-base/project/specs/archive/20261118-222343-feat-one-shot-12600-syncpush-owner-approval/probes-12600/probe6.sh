#!/usr/bin/env bash
# Synthesized fixture probe (copied from the deepen-plan scratch probe6.sh; root parameterized).
# Usage: probe6.sh [scratch-root]   (default: a fresh mktemp dir)
set -euo pipefail
if [ -n "${1:-}" ]; then BASE=$1; else BASE=$(mktemp -d); trap 'rm -rf "$BASE"' EXIT; fi
R="$BASE/p6-$$"
mkdir -p "$R"; cd "$R" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }
# Portable KB-entry swap (no awk: mawk in the runner image has no NUL RS and no {40} intervals, which silently
# left the tree unchanged on the first runner run). Reads `ls-tree -z` records, rewrites the knowledge-base entry.
kbswap() { local base=$1 kb=$2 rec; while IFS= read -r -d '' rec; do
  if [[ "$rec" == *$'\t'knowledge-base ]]; then printf '040000 tree %s\tknowledge-base\0' "$kb"; else printf '%s\0' "$rec"; fi
done < <(git ls-tree -z "$base"); }
git init -q -b main --bare remote.git
g init -q -b main seed; cd seed; mkdir -p knowledge-base src; echo a > knowledge-base/a.md; echo s > src/s.ts
g add -A; g commit -qm init; g remote add origin ../remote.git; g push -q origin main; cd ..
git clone -q --depth 1 "file://$R/remote.git" ws; cd ws
T=$(git rev-parse HEAD)
mkdir -p .github/workflows; echo evil > .github/workflows/x.yml; g add -A; g commit -qm foreign
echo b >> knowledge-base/a.md; g add -A; g commit -qm "Auto-commit after session"
echo dirty >> src/s.ts   # dirty tracked non-KB edit
H=$(git rev-parse HEAD); cd ..
# isolated dir with workspace objects as alternate
git init -q --bare iso.git
export GIT_DIR="$R/iso.git" GIT_ALTERNATE_OBJECT_DIRECTORIES="$R/ws/.git/objects"
cp "$R/ws/.git/shallow" "$R/iso.git/shallow"
echo "count: $(git rev-list --count --full-history --simplify-merges $T..$H -- . ':(exclude)knowledge-base/')"
KB=$(git rev-parse "$H:knowledge-base")
TREE=$(kbswap $T "$KB" | git mktree -z)
echo "S tree differs from T tree: $([ "$TREE" != "$(git rev-parse $T^{tree})" ] && echo yes || echo NO)"
S=$(git -c user.name="Soleur Agent" -c user.email=agent@soleur.ai commit-tree $TREE -p $T -m "Soleur: sync knowledge-base")
M=$(git -c user.name="Soleur Agent" -c user.email=agent@soleur.ai commit-tree "$H^{tree}" -p $H -p $S -m "Soleur: merge knowledge-base sync")
echo "S non-KB diff vs T: $(git diff-tree -r --name-only $T $S -- . ':(exclude)knowledge-base/' | wc -l)"
echo "objects to hand over: $(git rev-list --objects $M ^$H ^$T | wc -l)"
git rev-list --objects $M ^$H ^$T | git pack-objects -q --stdout > "$R/x.pack"
unset GIT_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES
cd ws
git unpack-objects -q < "$R/x.pack"
git update-ref refs/heads/main $M $H && echo "CAS ok"
git update-ref refs/heads/main $M 0000000000000000000000000000000000000001 2>/dev/null || echo "CAS with wrong old value refused (expected)"
echo "status: $(git status --porcelain | tr '\n' ' ')"
# push S from isolated dir
cd ..; GIT_DIR="$R/iso.git" GIT_ALTERNATE_OBJECT_DIRECTORIES="$R/ws/.git/objects" git push -q "file://$R/remote.git" $S:refs/heads/main && echo "push S ok"
FOREIGN=$(git -C ws rev-parse HEAD~1^1~1 2>/dev/null || git -C ws log --format=%H --grep=foreign -1)
git -C remote.git cat-file -e "$(git -C ws log --format=%H --grep=foreign -1)" 2>/dev/null && echo "LEAK: foreign on remote" || echo "foreign absent on remote (expected)"
cd ws; git update-ref refs/remotes/origin/main $S
echo "ahead count @{u}..HEAD: $(git rev-list --count @{u}..HEAD)"
git -c user.name=t -c user.email=t@t pull -q --ff-only && echo "pull --ff-only ok"
echo "status after pull: $(git status --porcelain | tr '\n' ' ')"
git merge-base --is-ancestor $S HEAD && echo "remote tip is ancestor of HEAD (ADR-068 ok)"
# turn 2: T2=S ancestor of new HEAD
echo c >> knowledge-base/a.md; g add knowledge-base; g commit -qm "Auto-commit after session"
git merge-base --is-ancestor $S HEAD && echo "turn2: T is ancestor"
echo "turn2 count: $(git rev-list --count --full-history --simplify-merges $S..HEAD -- . ':(exclude)knowledge-base/')"
git --version
