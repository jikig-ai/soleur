#!/usr/bin/env bash
# Wiring gate: scripts/assert-dev-doppler-scope.sh (#8028 DC-1, #9947) is the
# ONE mechanical guard that a dev-scoped job never holds the account-wide
# Supabase Management-API token — but it guards only the consumers that CALL
# it. A consumer that drops the call, or re-inlines the assertion, never
# fails: a dev job then runs dev writes UNASSERTED — the silent shape every
# shared-boundary extraction needs a wiring gate for (the
# test-dev-suite-mutex-wiring.sh precedent this file follows).
#
# What this pins (anchored, not bare tokens):
#   W1 all three consumers invoke `bash scripts/assert-dev-doppler-scope.sh`
#      (comment-stripped: tenant-integration.yml,
#      scheduled-integration-suites.yml, dev-ledger-reconcile.yml)
#   W2 no consumer retains an INLINE env=dev or DC-1 assertion
#      (`doppler configs get dev_scheduled`, `doppler secrets --only-names`)
#      — re-inlining recreates the drift the extraction closed
#   W3 tenant-integration.yml's detect-changes anchors the script — an
#      assertion edit must run the consuming leg
#   W4 each consumer binds DOPPLER_TOKEN to the dev_scheduled secret — the
#      script fails closed on an empty token, but a consumer wired to the
#      wrong secret would silently change what "dev" means
#
# Idiom follows tests/scripts/test-dev-suite-mutex-wiring.sh:
# `set -uo pipefail` + comment-stripped greps + anchored assertions +
# an anti-vacuity exact-count floor.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUT="${ROOT}/scripts/assert-dev-doppler-scope.sh"
TENANT="${ROOT}/.github/workflows/tenant-integration.yml"
SCHED="${ROOT}/.github/workflows/scheduled-integration-suites.yml"
RECON="${ROOT}/.github/workflows/dev-ledger-reconcile.yml"

passes=0
fails=0
_report() {
  if [[ "$2" == "ok" ]]; then passes=$((passes + 1)); printf '  ok   %s\n' "$1"
  else fails=$((fails + 1)); printf '  FAIL %s%s\n' "$1" "${3:+ — $3}"; fi
}

for f in "$SUT" "$TENANT" "$SCHED" "$RECON"; do
  [[ -f "$f" ]] || { printf 'harness: missing %s\n' "$f" >&2; exit 2; }
done

_strip() { grep -vE '^[[:space:]]*#'; }

# Stripped bodies materialized ONCE — `_strip | grep -q` in an `if` is a
# SIGPIPE race under pipefail (grep -q exits on first match and kills the
# upstream grep mid-write, propagating 141).
TENANT_BODY="$(_strip < "$TENANT")"
SCHED_BODY="$(_strip < "$SCHED")"
RECON_BODY="$(_strip < "$RECON")"

# ── W1: every consumer calls the script ────────────────────────────────────
_w1() {
  if grep -qE 'bash scripts/assert-dev-doppler-scope\.sh' <<<"$2"; then
    _report "W1 $1 invokes assert-dev-doppler-scope.sh" ok
  else
    _report "W1 $1 invokes assert-dev-doppler-scope.sh" fail \
      "consumer dropped or re-inlined the call — dev writes would run unasserted"
  fi
}
_w1 TENANT "$TENANT_BODY"
_w1 SCHED "$SCHED_BODY"
_w1 RECON "$RECON_BODY"

# ── W2: no inline assertion survives in any consumer ───────────────────────
_w2() {
  if grep -qE 'doppler configs get dev_scheduled|doppler secrets --only-names' <<<"$2"; then
    _report "W2 $1 retains no inline env=dev/DC-1 assertion" fail \
      "an inline copy recreates the drift the extraction closed"
  else
    _report "W2 $1 retains no inline env=dev/DC-1 assertion" ok
  fi
}
_w2 TENANT "$TENANT_BODY"
_w2 SCHED "$SCHED_BODY"
_w2 RECON "$RECON_BODY"

# ── W3: detect-changes anchors the script ──────────────────────────────────
# The anchor literal is `assert-dev-doppler-scope\.sh` (regex-escaped dot);
# the invocation `assert-dev-doppler-scope.sh` does NOT match this pattern,
# so the row pins the anchor specifically, not the call.
if grep -qE 'scripts/assert-dev-doppler-scope\\\.sh' <<<"$TENANT_BODY"; then
  _report "W3 detect-changes anchors scripts/assert-dev-doppler-scope.sh" ok
else
  _report "W3 detect-changes anchors scripts/assert-dev-doppler-scope.sh" fail \
    "an assertion edit would not trigger the consuming leg"
fi

# ── W4: every consumer binds the dev_scheduled secret ──────────────────────
_w4() {
  if grep -qE 'DOPPLER_TOKEN:.*DOPPLER_TOKEN_DEV_SCHEDULED' <<<"$2"; then
    _report "W4 $1 binds DOPPLER_TOKEN to DOPPLER_TOKEN_DEV_SCHEDULED" ok
  else
    _report "W4 $1 binds DOPPLER_TOKEN to DOPPLER_TOKEN_DEV_SCHEDULED" fail \
      "a differently-scoped token would change what 'dev' means"
  fi
}
_w4 TENANT "$TENANT_BODY"
_w4 SCHED "$SCHED_BODY"
_w4 RECON "$RECON_BODY"

# ── Anti-vacuity assertion floor ───────────────────────────────────────────
EXPECTED_ASSERTIONS=10
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — rows were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_ASSERTIONS"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
