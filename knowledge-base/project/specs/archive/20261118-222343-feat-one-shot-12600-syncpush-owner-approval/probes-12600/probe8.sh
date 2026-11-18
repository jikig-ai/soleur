#!/usr/bin/env bash
# Synthesized fixture probe (copied from the deepen-plan scratch probe8.sh; root parameterized).
# Usage: probe8.sh [scratch-root]   (default: a fresh mktemp dir)
set -uo pipefail
if [ -n "${1:-}" ]; then BASE=$1; else BASE=$(mktemp -d); trap 'rm -rf "$BASE"' EXIT; fi
R="$BASE/p8-$$"
mkdir -p "$R"; cd "$R"; export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }
g init -q -b main ws; cd ws; mkdir -p knowledge-base src; echo a > knowledge-base/a.md; echo s > src/s.ts; g add -A; g commit -qm T; T=$(git rev-parse HEAD); TT=$(git rev-parse "$T^{tree}")
v() { local t=$1 id=$2; local h; h=$(git cat-file "$t" "$id" 2>/dev/null | git hash-object -t "$t" --stdin) ; [ "$h" = "$id" ] && echo "verify $t ok" || echo "verify $t FAIL (got '${h}')"; }
v commit $T; v tree $TT
# forge T's root tree bytes with another tree's bytes
echo evil > src/s.ts; g add -A; g commit -qm F; FT=$(git rev-parse HEAD^{tree})
chmod u+w .git/objects/${TT:0:2}/${TT:2}; cp .git/objects/${FT:0:2}/${FT:2} .git/objects/${TT:0:2}/${TT:2}
echo "after forging T's tree:"; v tree $TT
echo "packed object case:"; g gc -q 2>&1 | head -2; v tree $TT; v commit $T
