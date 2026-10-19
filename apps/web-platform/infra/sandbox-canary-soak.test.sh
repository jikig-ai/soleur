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

# 7. The #5863 OUTER-wrap ledger is RETIRED (#10454, ADR-079 addendum 2026-10-19): neither the writer nor the
# reader may carry its state-file variable or its ledger stamp any more (a surviving reader would serve a frozen
# 'pass' soak to nobody; a surviving writer would keep a dead ledger alive).
assert "outer-wrap ledger variable is gone from the writer and the reader" \
  "! grep -q 'SANDBOX_OUTER_WRAP_CANARY_STATE_FILE' \"$TARGET\" \"$CAT_TARGET\""

# 7b. The #2640 WORKSPACE-ISOLATION ledger — third ledger, same #5889
# durability/parity contract (WORKSPACE_ISOLATION_STATE_FILE). A drifted
# default would silently TRANSIENT the verdict-2640 followthrough forever.
WIWRITER_DEFAULT="$(grep -oE 'WORKSPACE_ISOLATION_STATE_FILE:-[^}]+' "$TARGET" | head -1 | sed 's/.*:-//')"
WIREADER_DEFAULT="$(grep -oE 'WORKSPACE_ISOLATION_STATE_FILE:-[^}]+' "$CAT_TARGET" | head -1 | sed 's/.*:-//')"
assert "WI writer default is durable (/mnt/data), not tmpfs" "[[ \"$WIWRITER_DEFAULT\" == /mnt/data/* ]]"
assert "WI reader default is durable (/mnt/data), not tmpfs" "[[ \"$WIREADER_DEFAULT\" == /mnt/data/* ]]"
assert "WI writer + reader defaults MATCH" "[[ \"$WIWRITER_DEFAULT\" == \"$WIREADER_DEFAULT\" ]]"
assert "WI ledger does not alias the canary ledger" "[[ \"$WIWRITER_DEFAULT\" != \"$WRITER_DEFAULT\" ]]"

# 7c. Ledger-stamp vocabulary pairing: the writer's `ledger` field must name a
# stamp the readers' expected-ledger arguments accept — a drift between the
# two restatements makes every ledger read `foreign_ledger_stamp` (all three
# deploy-status keys permanently 'unknown'). Pin the pairs on BOTH sides.
assert "writer stamps sandbox-canary / workspace-isolation and no longer outer-wrap" \
  "grep -q '\"sandbox_broken\" \"\$sentry_op\"' \"$TARGET\" && grep -q \"'workspace-isolation'\" \"$TARGET\" && grep -q '\"sandbox-canary\"' \"$TARGET\" && ! grep -q 'sandbox-canary-outer-wrap' \"$TARGET\""
assert "readers expect the same two stamps and no longer outer-wrap" \
  "grep -q '\"sandbox-canary\"' \"$CAT_TARGET\" && grep -q '\"workspace-isolation\"' \"$CAT_TARGET\" && ! grep -q 'sandbox-canary-outer-wrap' \"$CAT_TARGET\""

# 7d. Guard 5 (#10454): the outer-wrap deploy call, ledger and soak script are retired, so NO live reader or writer
# may remain anywhere in the repo. Historical records (the PIR, plans/specs/learnings archives), the ADR-079
# addendum and the runbook retirement note are the only allowed mentions; the three infra tests that carry the
# absence assertions are excluded by name. A surviving `.outer_wrap_canary` reader in a workflow or a skill would
# poll a key deploy-status no longer emits and sit TRANSIENT forever.
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
OUTER_RE='outer_wrap_canary|OUTER_WRAP_CANARY|run_outer_wrap_canary|OUTER_LEDGER_ALIAS|tenant-outer-wrap-soak|ci-deploy-outer-wrap-canary'
OUTER_HITS="$(git -C "$REPO_ROOT" grep -nE "$OUTER_RE" -- . \
  ':(exclude)knowledge-base/project/plans' ':(exclude)knowledge-base/project/specs' ':(exclude)knowledge-base/project/learnings' \
  ':(exclude)knowledge-base/engineering/operations/post-mortems' \
  ':(exclude)knowledge-base/engineering/architecture/decisions/ADR-079*' \
  ':(exclude)knowledge-base/engineering/operations/runbooks/canary-probe-set.md' \
  ':(exclude)apps/web-platform/infra/ci-deploy.test.sh' ':(exclude)apps/web-platform/infra/cat-deploy-state.test.sh' \
  ':(exclude)apps/web-platform/infra/sandbox-canary-soak.test.sh' || true)"
assert "no live reference to the retired outer-wrap canary outside the historical record" \
  "[[ -z \"\$OUTER_HITS\" ]]"
[[ -z "$OUTER_HITS" ]] || printf '%s\n' "$OUTER_HITS" | head -n 20 | sed 's/^/        hit: /'

# 7e. Positive controls for the grep above: the pattern matches the retired symbol (so an empty result is not a
# dead regex), and the KEPT pieces still exist (the retirement removed the deploy arm, not the replay mode).
assert "7d pattern is live: it matches a retired symbol name" "printf 'run_outer_wrap_canary' | grep -qE \"$OUTER_RE\""
assert "sandbox-canary.mjs still implements --replay-outer (kept for #9773 and the masked-proc docker suite)" \
  "grep -q 'replay-outer' \"$SCRIPT_DIR/../scripts/sandbox-canary.mjs\""

# 8. Capability parity (review ask — static check, no docker needed): the
# reverted arm-F posture has THREE pins that must never drift —
# (a) the image carries NO file-cap'd bwrap (released bwrap refuses to run
#     with caps — v0.333.1 canary_sandbox_failed), (b) the getcap audit
#     still asserts the zero-file-cap invariant, (c) the deployed argv
#     carries zero --unshare-*. A re-add of setcap without the elevation
#     redesign silently poisons every bwrap call in the container again.
DOCKERFILE="$SCRIPT_DIR/../Dockerfile"
CLOUD_INIT="$SCRIPT_DIR/../infra/cloud-init.yml"
FIXTURE="$SCRIPT_DIR/agent-outer-wrap-argv.json"
assert "Dockerfile does NOT setcap /usr/bin/bwrap (upstream bwrap refuses caps)" \
  "! grep -q 'setcap .*bwrap' \"$DOCKERFILE\""
assert "Dockerfile audits zero file-cap'd binaries (getcap -r /)" \
  "grep -q 'getcap -r /' \"$DOCKERFILE\""
CAP_ADD_CI="$(grep -c -- '--cap-add SYS_ADMIN' "$TARGET")"
assert "ci-deploy docker runs carry no --cap-add SYS_ADMIN (reverted with file-cap arm)" \
  "[[ \"$CAP_ADD_CI\" == 0 ]]"
assert "cloud-init first-boot docker run carries no --cap-add SYS_ADMIN" \
  "! grep -q -- '--cap-add SYS_ADMIN' \"$CLOUD_INIT\""
UNSHARE_FIXTURE="$(grep -c -- '"--unshare' "$FIXTURE" || true)"
assert "committed outer fixture carries zero --unshare-* tokens" \
  "[[ \"$UNSHARE_FIXTURE\" == 0 ]]"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
