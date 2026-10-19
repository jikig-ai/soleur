#!/usr/bin/env bash
# Discoverability probe for the user-mode lint ratchet (ADR-290 Amendment 1, slice 2 of #10331).
#
#   bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh   ->   LINT_RATCHET_PROBE_OK
#
# Two stages, both decided before any ruff is provisioned, so it needs no network and no ruff:
#   1. a repository with a ruff config and no baseline is "not adopted" and nothing is installed;
#   2. a committed baseline that is then deleted from the working tree blocks (exit 1).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
engine="$(cd "$here/../../../../plugins/soleur/scripts" && pwd -P)/lint-ratchet.py"
[[ -f "$engine" ]] || { echo "lint-ratchet engine not found at $engine" >&2; exit 2; }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

work="$(mktemp -d "${TMPDIR:-/var/tmp}/lint-ratchet-probe.XXXXXXXX")"
assert_fixture_dir "$work"
trap 'rm -rf "$work"' EXIT
mkdir "$work/home" "$work/tmp" "$work/repo"
cd "$work/repo"

g() {
  env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE git -c user.name=probe -c user.email=probe@example.invalid \
    -c commit.gpgsign=false "$@"
}
run() {
  # No inherited cache location: a provisioned ruff must land under $work or the probe cannot see it.
  env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u CI -u XDG_CACHE_HOME HOME="$work/home" TMPDIR="$work/tmp" \
    python3 "$engine" "$@"
}

g init -q -b main
printf '[tool.ruff]\nline-length = 100\n' >pyproject.toml
printf 'x = 1\n' >demo.py
g add -A
g commit -q -m "demo"

# Stage 1: not adopted, asked from a subdirectory (the engine must find the repository root itself).
mkdir -p sub/inner
printf 'y = 2\n' >sub/inner/mod.py
g add -A
g commit -q -m "sub"
cd sub/inner
rc=0
out="$(run auto 2>/dev/null)" || rc=$?
cd "$work/repo"
[[ "$rc" -eq 0 ]] || { echo "stage 1: expected exit 0, got $rc" >&2; exit 1; }
[[ "$out" == *"not adopted. Ask the user whether to adopt"* && "$out" == *"run: python3 $engine user-ruff --update"* ]] \
  || { echo "stage 1: missing the not-adopted line; got: $out" >&2; exit 1; }
written="$(find "$work/home" "$work/tmp" -mindepth 1 | head -n 3)"
[[ -z "$written" ]] || { echo "stage 1: something was written for a repository that did not opt in: $written" >&2; exit 1; }

# Stage 2: a committed baseline deleted from the working tree.
mkdir .lint-ratchet
printf '# hand-written empty baseline for the probe\n' >.lint-ratchet/ruff.baseline.txt
g add -A
g commit -q -m "adopt"
rm -r .lint-ratchet
rc=0
err="$(run auto --base HEAD 2>&1 >/dev/null)" || rc=$?
[[ "$rc" -eq 1 ]] || { echo "stage 2: expected exit 1, got $rc: $err" >&2; exit 1; }
[[ "$err" == *"baseline deleted since the merge base"* ]] || { echo "stage 2: missing the deleted-baseline line; got: $err" >&2; exit 1; }

echo LINT_RATCHET_PROBE_OK
