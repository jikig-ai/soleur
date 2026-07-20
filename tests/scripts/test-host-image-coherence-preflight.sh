#!/usr/bin/env bash
# Tests for apps/web-platform/infra/scripts/host-image-coherence-preflight.sh — the
# LOAD-BEARING coherence preflight (AC10b, spec-flow P1-2/P1-4). Drives the script
# through its test seams (HOST_SCRIPTS_SEED_DIR + HOST_SCRIPTS_WANT_HASH) so a
# mismatching-digest scenario asserts a non-zero exit WITHOUT any prod write /
# docker / network. Synthesized fixtures only (cq-test-fixtures-synthesized-only).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/apps/web-platform/infra/scripts/host-image-coherence-preflight.sh"
pass=0; fail=0
VALID_DIGEST="sha256:$(printf 'a%.0s' {1..64})"
VALID_PINNED="ghcr.io/jikig-ai/soleur-web-platform@${VALID_DIGEST}"

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

if [[ ! -f "$PREFLIGHT" ]]; then
  echo "ERROR: $PREFLIGHT does not exist — RED phase expected this." >&2
  exit 1
fi

# A synthesized "baked host-scripts" seed dir + its BOOT-IDENTICAL recomputed hash
# (same pipeline as the `GOT=$(cd "$SEED"` line in cloud-init.yml and the script
# under test).
make_seed() {
  local d; d="$(mktemp -d)"
  printf 'ci-deploy stub\n' > "$d/ci-deploy.sh"
  printf 'bootstrap stub\n' > "$d/soleur-host-bootstrap.sh"
  printf 'hooks tmpl stub\n' > "$d/hooks.json.tmpl"
  echo "$d"
}
seed_hash() {
  ( cd "$1" && find . -type f -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort | tr -d '\n' | sha256sum | awk '{print $1}' )
}

SEED="$(make_seed)"
MATCH_HASH="$(seed_hash "$SEED")"
# A different-but-well-formed 64-hex hash (drift/mismatch).
MISMATCH_HASH="$(printf 'deadbeef%.0s' {1..8})"
trap 'rm -rf "$SEED"' EXIT

# T1: coherent digest (WANT == recomputed GOT) → exit 0.
t_coherent_passes() {
  if PINNED="$VALID_PINNED" HOST_SCRIPTS_SEED_DIR="$SEED" HOST_SCRIPTS_WANT_HASH="$MATCH_HASH" \
      bash "$PREFLIGHT" >/dev/null 2>&1; then
    _report "T1 coherent digest (GOT==WANT) exits 0" ok
  else
    _report "T1 coherent digest (GOT==WANT) exits 0" fail "expected exit 0"
  fi
}

# T2 (core AC10b): mismatching applied hash → non-zero exit BEFORE any -replace.
# Assert the DISCRIMINATING reason (COHERENCE MISMATCH), not just rc≠0 — otherwise
# the test stays green if the script exits non-zero for an unrelated reason (e.g.
# format-validation firing first), masking a regression in the load-bearing check.
t_mismatch_aborts() {
  local rc=0 err
  err=$(PINNED="$VALID_PINNED" HOST_SCRIPTS_SEED_DIR="$SEED" HOST_SCRIPTS_WANT_HASH="$MISMATCH_HASH" \
    bash "$PREFLIGHT" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"COHERENCE MISMATCH"* ]]; then
    _report "T2 hash mismatch aborts on COHERENCE MISMATCH (the durable :latest fix, pre-destruction)" ok
  else
    _report "T2 hash mismatch aborts on COHERENCE MISMATCH" fail "rc=$rc err='$err'"
  fi
}

# T3: malformed PINNED (a bare tag, no @digest) → non-zero, on the digest-shape reason.
t_bare_tag_aborts() {
  local rc=0 err
  err=$(PINNED="ghcr.io/jikig-ai/soleur-web-platform:latest" HOST_SCRIPTS_SEED_DIR="$SEED" \
    HOST_SCRIPTS_WANT_HASH="$MATCH_HASH" bash "$PREFLIGHT" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"immutable digest ref"* ]]; then
    _report "T3 bare tag (no @sha256 digest) aborts on 'immutable digest ref'" ok
  else
    _report "T3 bare tag aborts on 'immutable digest ref'" fail "rc=$rc err='$err'"
  fi
}

# T4: malformed digest hex (not 64 hex) → non-zero, on the hex-shape reason.
t_bad_digest_hex_aborts() {
  local rc=0 err
  err=$(PINNED="ghcr.io/jikig-ai/soleur-web-platform@sha256:notahex" HOST_SCRIPTS_SEED_DIR="$SEED" \
    HOST_SCRIPTS_WANT_HASH="$MATCH_HASH" bash "$PREFLIGHT" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"refusing to proceed"* ]]; then
    _report "T4 malformed digest hex aborts on 'refusing to proceed'" ok
  else
    _report "T4 malformed digest hex aborts on 'refusing to proceed'" fail "rc=$rc err='$err'"
  fi
}

# T5: malformed WANT hash (terraform-console-failure shape) → non-zero, on the WANT reason.
t_bad_want_aborts() {
  local rc=0 err
  err=$(PINNED="$VALID_PINNED" HOST_SCRIPTS_SEED_DIR="$SEED" HOST_SCRIPTS_WANT_HASH="not-a-hash" \
    bash "$PREFLIGHT" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"applied hash WANT"* ]]; then
    _report "T5 malformed applied-hash WANT aborts on 'applied hash WANT'" ok
  else
    _report "T5 malformed applied-hash WANT aborts on 'applied hash WANT'" fail "rc=$rc err='$err'"
  fi
}

# T6: missing PINNED → non-zero (required input), on the ':?' required-var reason.
t_missing_pinned_aborts() {
  local rc=0 err
  err=$(HOST_SCRIPTS_SEED_DIR="$SEED" HOST_SCRIPTS_WANT_HASH="$MATCH_HASH" \
    bash "$PREFLIGHT" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"is required"* ]]; then
    _report "T6 missing PINNED aborts on 'is required'" ok
  else
    _report "T6 missing PINNED aborts on 'is required'" fail "rc=$rc err='$err'"
  fi
}

t_coherent_passes
t_mismatch_aborts
t_bare_tag_aborts
t_bad_digest_hex_aborts
t_bad_want_aborts
t_missing_pinned_aborts

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
