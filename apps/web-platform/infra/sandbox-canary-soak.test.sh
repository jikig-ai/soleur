#!/usr/bin/env bash
# Tests for ci-deploy.sh write_sandbox_canary_state accumulation (#5875 / ADR-079).
#
# The soak signal ("5 green verdicts over ≥3 days") is accumulated on the host in
# the deploy-state so the canary-promotion follow-through is a single stateless
# GET. This gate exercises the increment / reset / hold / carry contract of the
# accumulator by extracting the function from ci-deploy.sh (no sourcing guard) and
# driving it against pre-seeded state files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/ci-deploy.sh"

PASS=0; FAIL=0; TOTAL=0
assert() {
  local d="$1" cond="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $d";
  else FAIL=$((FAIL + 1)); echo "  FAIL: $d"; echo "        cond: $cond"; fi
}

echo "=== ci-deploy.sh write_sandbox_canary_state accumulation tests ==="

# Extract just the function (from its definition to the first column-0 `}`) and
# eval it into this shell — ci-deploy.sh has no sourcing guard, so we cannot
# source the whole script.
FN="$(awk '/^write_sandbox_canary_state\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$TARGET")"
if [[ -z "$FN" ]]; then echo "  FAIL: could not extract write_sandbox_canary_state"; exit 1; fi
eval "$FN"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SANDBOX_CANARY_STATE_FILE="$TMP/canary.json"

field() { jq -r ".$1" "$SANDBOX_CANARY_STATE_FILE"; }

# 1. Fresh (no prior file) + pass → consecutive_pass=1, first_pass_at pinned (>0).
rm -f "$SANDBOX_CANARY_STATE_FILE"
write_sandbox_canary_state "pass" "ok" "0.3.197"
assert "fresh pass ⇒ consecutive_pass=1" "[[ \$(field consecutive_pass) == 1 ]]"
assert "fresh pass ⇒ first_pass_at pinned (>0)" "[[ \$(field first_pass_at) -gt 0 ]]"
assert "fresh pass ⇒ verdict recorded" "[[ \$(field verdict) == pass ]]"

# 2. Prior 2 greens (first_pass_at=1000000000) + pass → 3, first_pass_at CARRIED.
echo '{"verdict":"pass","reason":"ok","sdk_version":"0.3.197","checked_at":1000000005,"consecutive_pass":2,"first_pass_at":1000000000}' > "$SANDBOX_CANARY_STATE_FILE"
write_sandbox_canary_state "pass" "ok" "0.3.197"
assert "pass increments prior count (2→3)" "[[ \$(field consecutive_pass) == 3 ]]"
assert "pass CARRIES first_pass_at (not reset to now)" "[[ \$(field first_pass_at) == 1000000000 ]]"

# 3. canary_infra_error HOLDS prior counters (dark-launch / docker hiccup = non-signal).
echo '{"verdict":"pass","reason":"ok","sdk_version":"0.3.197","checked_at":1000000005,"consecutive_pass":3,"first_pass_at":1000000000}' > "$SANDBOX_CANARY_STATE_FILE"
write_sandbox_canary_state "canary_infra_error" "fixture_uncaptured" ""
assert "infra_error HOLDS consecutive_pass (3)" "[[ \$(field consecutive_pass) == 3 ]]"
assert "infra_error HOLDS first_pass_at" "[[ \$(field first_pass_at) == 1000000000 ]]"

# 4. sandbox_broken RESETS the soak (faithful FAIL restarts the window).
echo '{"verdict":"pass","reason":"ok","sdk_version":"0.3.197","checked_at":1000000005,"consecutive_pass":4,"first_pass_at":1000000000}' > "$SANDBOX_CANARY_STATE_FILE"
write_sandbox_canary_state "sandbox_broken" "bwrap_operation_not_permitted" "0.3.198"
assert "sandbox_broken RESETS consecutive_pass to 0" "[[ \$(field consecutive_pass) == 0 ]]"
assert "sandbox_broken RESETS first_pass_at to 0" "[[ \$(field first_pass_at) == 0 ]]"

# 5. pass after a reset re-pins first_pass_at (>0) and restarts count at 1.
write_sandbox_canary_state "pass" "ok" "0.3.198"
assert "pass after reset ⇒ consecutive_pass=1" "[[ \$(field consecutive_pass) == 1 ]]"
assert "pass after reset ⇒ first_pass_at re-pinned (>0)" "[[ \$(field first_pass_at) -gt 0 ]]"

# 6. DURABILITY (#5889 regression guard): the soak accumulator survives reboots
# ONLY if its DEFAULT path is on durable storage, not /var/run tmpfs (wiped every
# reboot → consecutive_pass + first_pass_at silently reset → soak can never reach
# "≥5 greens over ≥3 days"). Assert the writer (ci-deploy.sh) and the reader
# (cat-deploy-state.sh) BOTH default to /mnt/data and NEITHER defaults to /var/run.
CAT_TARGET="$SCRIPT_DIR/cat-deploy-state.sh"
WRITER_DEFAULT="$(grep -oE 'SANDBOX_CANARY_STATE_FILE:-[^}]+' "$TARGET" | head -1 | sed 's/.*:-//')"
READER_DEFAULT="$(grep -oE 'SANDBOX_CANARY_STATE_FILE:-[^}]+' "$CAT_TARGET" | head -1 | sed 's/.*:-//')"
assert "writer default is durable (/mnt/data), not tmpfs" "[[ \"$WRITER_DEFAULT\" == /mnt/data/* ]]"
assert "reader default is durable (/mnt/data), not tmpfs" "[[ \"$READER_DEFAULT\" == /mnt/data/* ]]"
assert "writer default is NOT /var/run tmpfs" "[[ \"$WRITER_DEFAULT\" != /var/run/* ]]"
assert "reader default is NOT /var/run tmpfs" "[[ \"$READER_DEFAULT\" != /var/run/* ]]"
assert "writer + reader defaults MATCH" "[[ \"$WRITER_DEFAULT\" == \"$READER_DEFAULT\" ]]"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
