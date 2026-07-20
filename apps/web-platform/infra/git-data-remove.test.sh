#!/usr/bin/env bash
#
# Tests for the git-data per-workspace bare-repo ERASURE wrapper
# (git-data-remove.sh, #5274 Phase 3 / ADR-068 GDPR Art. 17). Exercises: a valid id
# erases the repo (and its in-repo fence sidecar); erasing an absent id is an
# idempotent no-op; traversal / unsafe ids are rejected BEFORE any rm and never
# touch an existing repo; a symlink planted at the repo path cannot redirect the rm
# outside the root; a missing id fails closed.
#
# Run: bash apps/web-platform/infra/git-data-remove.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${DIR}/git-data-remove.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# Run the wrapper with SSH_ORIGINAL_COMMAND=<id> against a test repo root. Echoes
# the exit code. Runs WITHOUT set -e propagation (reject cases exit 1 by design).
run_remove() {
  local root="$1" id="$2"
  env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" SSH_ORIGINAL_COMMAND="$id" \
    bash "$WRAPPER" >/dev/null 2>&1
  echo $?
}

fresh_root() {
  local r
  r="$(mktemp -d "${TMPDIR:-/tmp}/gdrm.XXXXXX")"
  echo "$r"
}

# Fabricate a "bare repo" dir with an in-repo fence sidecar to prove both go.
make_repo() {
  local root="$1" id="$2"
  mkdir -p "${root}/${id}.git/fence"
  touch "${root}/${id}.git/HEAD" "${root}/${id}.git/fence/primary.gen"
}

# --- T1: a valid id erases the repo AND its fence sidecar (exit 0, gone) ---
root=$(fresh_root)
make_repo "$root" "ws-abc-123"
rc=$(run_remove "$root" "ws-abc-123")
if [ "$rc" = "0" ]; then pass; else fail "T1 valid id: expected 0, got $rc"; fi
if [ ! -e "${root}/ws-abc-123.git" ]; then pass; else fail "T1 repo still present after erase"; fi
rm -rf "$root"

# --- T2: erasing an absent id is an idempotent no-op (exit 0) ---
root=$(fresh_root)
rc=$(run_remove "$root" "ws-never-existed")
if [ "$rc" = "0" ]; then pass; else fail "T2 absent id: expected idempotent 0, got $rc"; fi
rm -rf "$root"

# --- T3: traversal / unsafe ids are REJECTED and never erase a real repo ---
root=$(fresh_root)
make_repo "$root" "ws-keep"
# shellcheck disable=SC2016 # the $(whoami) is a LITERAL string under test — must NOT expand
for bad in ".." "." "a/b" "a b" "a;rm -rf /" '$(whoami)' "" ; do
  rc=$(run_remove "$root" "$bad")
  if [ "$rc" != "0" ]; then pass; else fail "T3 unsafe id '$bad': expected reject (non-zero), got 0"; fi
done
if [ -e "${root}/ws-keep.git/HEAD" ]; then pass; else fail "T3 an unsafe id erased the real repo"; fi
rm -rf "$root"

# --- T4: a traversal id cannot escape the repo root (parent-canonicalize guard) ---
root=$(fresh_root)
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-outside.XXXXXX")"
touch "${outside}/SENTINEL"
rc=$(run_remove "$root" "../$(basename "$outside")")
if [ "$rc" != "0" ]; then pass; else fail "T4 escape attempt: expected reject, got 0"; fi
if [ -e "${outside}/SENTINEL" ]; then pass; else fail "T4 escape erased outside the root"; fi
rm -rf "$root" "$outside"

# --- T5: a symlink planted AT the repo path cannot redirect rm outside the root ---
root=$(fresh_root)
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-sym.XXXXXX")"
touch "${outside}/SENTINEL"
ln -s "$outside" "${root}/ws-sym.git" # repo_path is a symlink to outside
rc=$(run_remove "$root" "ws-sym")
if [ "$rc" != "0" ]; then pass; else fail "T5 symlink repo: expected reject, got 0"; fi
if [ -e "${outside}/SENTINEL" ]; then pass; else fail "T5 symlink rm escaped and erased the target"; fi
rm -rf "$root" "$outside"

# --- Minimum-cardinality guard (mirrors the provision/fence tests) ---
total=$((passes + fails))
if [ "$total" -lt 13 ]; then
  echo "FAIL: ran only ${total} assertions (<13) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-remove: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
