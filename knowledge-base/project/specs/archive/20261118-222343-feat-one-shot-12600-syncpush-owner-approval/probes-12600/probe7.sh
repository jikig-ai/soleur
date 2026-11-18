#!/usr/bin/env bash
# Synthesized fixture probe (copied from the deepen-plan scratch probe7.sh; root parameterized).
# Usage: probe7.sh [scratch-root]   (default: a fresh mktemp dir)
set -uo pipefail
if [ -n "${1:-}" ]; then BASE=$1; else BASE=$(mktemp -d); trap 'rm -rf "$BASE"' EXIT; fi
R="$BASE/p7-$$"
mkdir -p "$R"; cd "$R" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }
g init -q -b main ws; cd ws
mkdir -p knowledge-base src; echo a > knowledge-base/a.md; echo s > src/s.ts; g add -A; g commit -qm T; T=$(git rev-parse HEAD)
# genuine foreign commit F (changes src)
echo evil > src/s.ts; g add -A; g commit -qm F; F=$(git rev-parse HEAD)
FTREE=$(git rev-parse "$F^{tree}")
# fake tree: same as T's tree (KB-only-looking) -> its bytes
TTREE=$(git rev-parse "$T^{tree}")
# build a fake commit body identical to F but with tree = TTREE... simpler: overwrite F's TREE object file with T's tree bytes
src=.git/objects/${TTREE:0:2}/${TTREE:2}; dst=.git/objects/${FTREE:0:2}/${FTREE:2}
chmod u+w "$dst"; cp "$src" "$dst"
echo "--- after planting T-tree bytes under F's tree name:"
echo "rev-list count: $(git rev-list --count --full-history --simplify-merges $T..$F -- . ':(exclude)knowledge-base/' 2>&1)"
git diff-tree -r --quiet $T $F -- . ':(exclude)knowledge-base/' 2>&1; echo "diff-tree rc=$? (0 = no non-KB change seen)"
echo "ls-tree F: $(git ls-tree $F 2>&1 | tr '\n' ' ')"
git cat-file -t $FTREE 2>&1
git fsck --no-dangling 2>&1 | head -3
echo "--- via alternate from another GIT_DIR:"
cd ..; git init -q --bare iso.git
GIT_DIR=$R/iso.git GIT_ALTERNATE_OBJECT_DIRECTORIES=$R/ws/.git/objects git rev-list --count --full-history --simplify-merges $T..$F -- . ':(exclude)knowledge-base/' 2>&1
git --version
