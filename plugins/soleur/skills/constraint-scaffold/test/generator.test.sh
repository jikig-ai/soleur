#!/usr/bin/env bash
# Generator-script coverage for constraint-scaffold.sh (ADR-070). Exercises the
# script's guard/exit-matrix paths against HERMETIC fixture repos — the real
# apps/web-platform emitted files are never read or written. Each fixture is a
# throwaway `git init` repo under a mktemp dir, targeted via the
# CONSTRAINT_SCAFFOLD_REPO_ROOT override. None of these paths reach baseline
# capture (they bail at a precondition/guard), so dependency-cruiser is not
# needed.
#
# Covers:
#   exit 65  not-a-Next.js-app detection (no next.config / no anchored "next").
#   exit 66  refuse-if-exists: default mode on an already-emitted tree.
#   exit 67  --refresh-baseline on a dirty working tree refuses.
#
# Runs in the scripts shard (scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh). Accumulate-then-exit.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
GEN="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"

passes=0
fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Build a throwaway git repo with an apps/web-platform-shaped app dir. $1 = name,
# $2 = "next" to make it a valid Next.js app (next.config + anchored "next" dep).
make_repo() {
  local fx="$TMPROOT/$1"
  mkdir -p "$fx/apps/web-platform/app"
  git -C "$fx" init -q
  git -C "$fx" config user.email "test@example.com"
  git -C "$fx" config user.name "test"
  if [[ "${2:-}" == "next" ]]; then
    printf 'module.exports = {};\n' > "$fx/apps/web-platform/next.config.js"
    printf '{ "dependencies": { "next": "15.0.0" } }\n' > "$fx/apps/web-platform/package.json"
  fi
  printf '%s' "$fx"
}

run_gen() {
  # $1 = repo root, rest = args. Captures rc; never aborts the suite.
  local root="$1"; shift
  set +e
  CONSTRAINT_SCAFFOLD_REPO_ROOT="$root" bash "$GEN" "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# --- exit 65: not a Next.js app ----------------------------------------------
FX="$(make_repo notnext)"   # no next.config, no package.json
RC="$(run_gen "$FX")"
if [[ "$RC" == "65" ]]; then
  pass "exit 65: not-a-Next.js-app detected (no next.config / anchored \"next\")"
else
  fail "exit 65 expected for non-Next.js target, got rc=$RC"
fi

# --- exit 66: refuse-if-exists (default mode on an already-emitted tree) ------
FX="$(make_repo emitted next)"
# Pre-place an emitted artifact (untracked -> the clean-tree guard still passes,
# since git diff ignores untracked files) so refuse-if-exists fires.
printf '// already here\n' > "$FX/apps/web-platform/.dependency-cruiser.cjs"
RC="$(run_gen "$FX")"
if [[ "$RC" == "66" ]]; then
  pass "exit 66: default mode refuses when an artifact already exists (no --force)"
else
  fail "exit 66 expected for already-emitted tree, got rc=$RC"
fi

# --- exit 67: --refresh-baseline on a dirty tree refuses ----------------------
FX="$(make_repo dirty next)"
printf '// gate config\n' > "$FX/apps/web-platform/.dependency-cruiser.cjs"
git -C "$FX" add apps/web-platform
git -C "$FX" commit -q -m "seed gate"
# Dirty a TRACKED file so `git diff --quiet` reports the tree dirty.
printf '// edited\n' >> "$FX/apps/web-platform/.dependency-cruiser.cjs"
RC="$(run_gen "$FX" --refresh-baseline)"
if [[ "$RC" == "67" ]]; then
  pass "exit 67: --refresh-baseline refuses on a dirty working tree"
else
  fail "exit 67 expected for --refresh-baseline on dirty tree, got rc=$RC"
fi

echo "---"
echo "generator.test.sh: $passes passed, $fails failed"
[[ "$fails" -eq 0 ]]
