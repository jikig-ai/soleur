#!/usr/bin/env bash
# Unit tests for scripts/supabase-watchdog-classify.sh (#9168) — the bounded
# Supabase Postgres-hang auto-restart classifier.
#
# The Guard Contract (plan's mutation matrix) says a restart may issue ONLY on
# the EXACT observed signature — db, auth, rest ALL UNHEALTHY while pooler
# reports ACTIVE_HEALTHY — sustained across EVERY read in the >=3-read window
# AND corroborated by an independent signal (app /health's `supabase` field).
# Everything else — a partially-unhealthy window, a pooler that is also down
# (total-outage shape), an extra service UNHEALTHY, a missing key, an
# unreachable corroborator, a non-200/unparseable probe response — must NEVER
# produce hang-signature.
#
# Two surfaces are exercised:
#   - the sourceable functions (classify_health_read / classify_window /
#     parse_restart_ledger / watchdog_decision), the same entry points the
#     workflow's bash steps call;
#   - the CLI (bash <script> --corroborator ... --read CODE BODY ... and
#     --ledger / --decide / --self-test), which the workflow invokes and the
#     observability discoverability_test greps.
#
# Restart-side state (cooldown, give-up, fail-closed) is a pure function of the
# audit-issue sentinel ledger — parse_restart_ledger turns the comments text
# into {attempts, last_epoch, corrupt} and watchdog_decision folds that with
# the verdict + WATCHDOG_ARMED into an action token. Both are tested here so a
# weaking of the signature AND a weakening of the restart gate are caught by
# the same suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/supabase-watchdog-classify.sh"
# shellcheck source=/dev/null
source "$SCRIPT"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

echo "=== supabase-watchdog-classify.sh tests ==="

# --- fixtures ---------------------------------------------------------------
# The observed 2026-09-15 / 2026-09-28 hang shape (runbook
# app-database-readiness-alarm.md step 4): db, auth, rest UNHEALTHY while the
# pooler stays ACTIVE_HEALTHY.
SIG='[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'
HEALTHY='[{"name":"db","status":"ACTIVE_HEALTHY"},{"name":"auth","status":"ACTIVE_HEALTHY"},{"name":"rest","status":"ACTIVE_HEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'
# Total-outage shape — pooler ALSO down. NOT the proven signature (mutation 1).
POOLER_DOWN='[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"UNHEALTHY"}]'
# Signature plus an extra UNHEALTHY service — the observed set is a strict
# superset of the signature, not the signature itself (mutation: extra service).
EXTRA_UNHEALTHY='[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"},{"name":"storage","status":"UNHEALTHY"}]'
# Extra service HEALTHY alongside the signature — tolerated (the observed set
# still names the signature exactly on the services that matter).
EXTRA_HEALTHY='[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"},{"name":"storage","status":"ACTIVE_HEALTHY"}]'
# Mid-restart shape: rest COMING_UP (post-restart window veto).
COMING_UP='[{"name":"db","status":"COMING_UP"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"COMING_UP"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'
# Missing a required key — an incomplete observation, not the signature.
MISSING_DB='[{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'
# A partial outage that is NOT the signature (db still healthy).
PARTIAL='[{"name":"db","status":"ACTIVE_HEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'
# Unknown status vocabulary on a required service — never pattern-match a hang
# out of a state we do not recognise.
UNKNOWN_STATE='[{"name":"db","status":"UNREACHABLE"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'

# --- classify_health_read: one Management-API health response ---------------

assert_eq "signature body → hang-signature" "hang-signature" \
  "$(classify_health_read 200 "$SIG")"
assert_eq "all ACTIVE_HEALTHY → healthy" "healthy" \
  "$(classify_health_read 200 "$HEALTHY")"
assert_eq "mutation 1: pooler ALSO UNHEALTHY → ambiguous (total-outage, not the hang)" "ambiguous" \
  "$(classify_health_read 200 "$POOLER_DOWN")"
assert_eq "extra service UNHEALTHY alongside signature → ambiguous" "ambiguous" \
  "$(classify_health_read 200 "$EXTRA_UNHEALTHY")"
assert_eq "extra service ACTIVE_HEALTHY alongside signature → hang-signature" "hang-signature" \
  "$(classify_health_read 200 "$EXTRA_HEALTHY")"
assert_eq "mutation 2: COMING_UP mid-window → ambiguous (post-restart veto)" "ambiguous" \
  "$(classify_health_read 200 "$COMING_UP")"
assert_eq "mutation 2b: missing db key → ambiguous" "ambiguous" \
  "$(classify_health_read 200 "$MISSING_DB")"
assert_eq "partial outage (db healthy) → ambiguous" "ambiguous" \
  "$(classify_health_read 200 "$PARTIAL")"
assert_eq "required service in an unknown state (UNREACHABLE) → ambiguous" "ambiguous" \
  "$(classify_health_read 200 "$UNKNOWN_STATE")"
assert_eq "pooler COMING_UP with trio UNHEALTHY → ambiguous (pooler must be ACTIVE_HEALTHY)" "ambiguous" \
  "$(classify_health_read 200 '[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"COMING_UP"}]')"

# Probe-failure side: non-200 or unparseable → probe-unavailable (NEVER restart).
assert_eq "401 (bad PAT) → probe-unavailable" "probe-unavailable" \
  "$(classify_health_read 401 '{"message":"Unauthorized"}')"
assert_eq "500 → probe-unavailable" "probe-unavailable" \
  "$(classify_health_read 500 'Internal Server Error')"
assert_eq "000 (curl transport failure) → probe-unavailable" "probe-unavailable" \
  "$(classify_health_read 000 '')"
assert_eq "200 + non-JSON body → probe-unavailable" "probe-unavailable" \
  "$(classify_health_read 200 'not json at all')"
assert_eq "200 + JSON object (not array) → probe-unavailable" "probe-unavailable" \
  "$(classify_health_read 200 '{"status":"UNHEALTHY"}')"
assert_eq "200 + empty body → probe-unavailable" "probe-unavailable" \
  "$(classify_health_read 200 '')"
assert_eq "200 + empty array (answered but shapeless) → ambiguous" "ambiguous" \
  "$(classify_health_read 200 '[]')"

# --- classify_window: >=3 reads + corroborator --------------------------------

assert_eq "3x signature + corroborator error → hang-signature" "hang-signature" \
  "$(classify_window error hang-signature hang-signature hang-signature)"
assert_eq "mutation 3: signature + corroborator 'connected' → ambiguous (single-surface never restarts)" "ambiguous" \
  "$(classify_window connected hang-signature hang-signature hang-signature)"
assert_eq "corroborator unreachable → ambiguous (never restart blind)" "ambiguous" \
  "$(classify_window unreachable hang-signature hang-signature hang-signature)"
assert_eq "mutation 5: signature in 1 of 3 reads (others healthy) → ambiguous, NOT hang-signature" "ambiguous" \
  "$(classify_window error hang-signature healthy healthy)"
assert_eq "signature, ambiguous, signature → ambiguous (window not sustained)" "ambiguous" \
  "$(classify_window error hang-signature ambiguous hang-signature)"
assert_eq "all-healthy window → healthy" "healthy" \
  "$(classify_window connected healthy healthy healthy)"
assert_eq "any probe-unavailable read poisons the window → probe-unavailable" "probe-unavailable" \
  "$(classify_window error hang-signature probe-unavailable hang-signature)"
assert_eq "fewer than 3 reads → probe-unavailable (under-observed window)" "probe-unavailable" \
  "$(classify_window error hang-signature hang-signature)"
assert_eq "all-healthy + unreachable corroborator → healthy (corroborator gates only the signature)" "healthy" \
  "$(classify_window unreachable healthy healthy healthy)"

# --- CLI path: the executable the workflow invokes ----------------------------

cli() { # echoes "<rc>|<stdout>"; stderr stays on the log
  local rc=0 out
  out="$(bash "$SCRIPT" "$@" 2>/dev/null)" || rc=$?
  printf '%s|%s' "$rc" "$out"
}

assert_eq "CLI: 3 signature reads + corroborator error → exit 0, hang-signature" "0|hang-signature" \
  "$(cli --corroborator error --read 200 "$SIG" --read 200 "$SIG" --read 200 "$SIG")"
assert_eq "CLI: signature + corroborator connected → exit 0, ambiguous" "0|ambiguous" \
  "$(cli --corroborator connected --read 200 "$SIG" --read 200 "$SIG" --read 200 "$SIG")"
assert_eq "CLI: signature + corroborator unreachable → ambiguous" "0|ambiguous" \
  "$(cli --corroborator unreachable --read 200 "$SIG" --read 200 "$SIG" --read 200 "$SIG")"
assert_eq "CLI: mid-window recovery (sig, sig, healthy) → ambiguous, exit 0" "0|ambiguous" \
  "$(cli --corroborator error --read 200 "$SIG" --read 200 "$SIG" --read 200 "$HEALTHY")"
assert_eq "CLI: all-healthy → exit 0, healthy" "0|healthy" \
  "$(cli --corroborator connected --read 200 "$HEALTHY" --read 200 "$HEALTHY" --read 200 "$HEALTHY")"
# mutation 6: an empty/unparseable response must exit NON-ZERO with verdict
# probe-unavailable — an exit-0 hang-verdict on garbage is the vacuous arm.
assert_eq "CLI (mutation 6): 200 + empty body → non-zero + probe-unavailable" "2|probe-unavailable" \
  "$(cli --corroborator error --read 200 "$SIG" --read 200 '' --read 200 "$SIG")"
assert_eq "CLI: a 401 read poisons the window → non-zero + probe-unavailable" "2|probe-unavailable" \
  "$(cli --corroborator error --read 200 "$SIG" --read 401 '{}' --read 200 "$SIG")"
assert_eq "CLI: only 2 reads → non-zero + probe-unavailable" "2|probe-unavailable" \
  "$(cli --corroborator error --read 200 "$SIG" --read 200 "$SIG")"
assert_eq "CLI: --self-test prints hang-signature, exit 0 (discoverability contract)" "0|hang-signature" \
  "$(cli --self-test)"

# --- parse_restart_ledger: the audit-issue sentinel protocol ------------------

NOW=1800000000
LEDGER_NONE='## audit issue body\nStill failing at 2026-09-28.'
LEDGER_ONE='probe detail\n<!-- watchdog:restart epoch=1799999000 -->\nnext comment text'
LEDGER_THREE='<!-- watchdog:restart epoch=1799990000 -->\nmiddle\n<!-- watchdog:restart epoch=1799999000 -->\n<!-- watchdog:restart epoch=1799980000 -->'
# A `watchdog:restart` comment marker whose epoch is not digits — the ledger a
# claimed-restart run must refuse to act on (fail-closed).
LEDGER_CORRUPT='<!-- watchdog:restart epoch=abc -->\nbody'
LEDGER_TRUNC='<!-- watchdog:restart\npartial marker, no epoch -->\nbody'

assert_eq "ledger: no sentinels → attempts=0 last_epoch=none corrupt=0" "attempts=0 last_epoch=none corrupt=0" \
  "$(printf '%b' "$LEDGER_NONE" | parse_restart_ledger)"
assert_eq "ledger: one sentinel → attempts=1, its epoch" "attempts=1 last_epoch=1799999000 corrupt=0" \
  "$(printf '%b' "$LEDGER_ONE" | parse_restart_ledger)"
assert_eq "ledger: three sentinels → attempts=3, last_epoch = newest" "attempts=3 last_epoch=1799999000 corrupt=0" \
  "$(printf '%b' "$LEDGER_THREE" | parse_restart_ledger)"
assert_eq "ledger (mutation 10): unparseable epoch → corrupt=1" "attempts=0 last_epoch=none corrupt=1" \
  "$(printf '%b' "$LEDGER_CORRUPT" | parse_restart_ledger)"
assert_eq "ledger: truncated marker (no epoch field) → corrupt=1" "attempts=0 last_epoch=none corrupt=1" \
  "$(printf '%b' "$LEDGER_TRUNC" | parse_restart_ledger)"
assert_eq "ledger: valid + corrupt mix → corrupt=1 (and the valid count is still read)" "attempts=1 last_epoch=1799999000 corrupt=1" \
  "$(printf '%b' '<!-- watchdog:restart epoch=1799999000 -->\n<!-- watchdog:restart epoch=oops -->\n' | parse_restart_ledger)"

# --- watchdog_decision: verdict + armed + ledger → action ---------------------

# watchdog_decision VERDICT ARMED CORRUPT CLAIMED ATTEMPTS LAST_EPOCH NOW [COOLDOWN_SEC] [MAX_ATTEMPTS]
assert_eq "clean run, armed, no history → restart" "restart" \
  "$(watchdog_decision hang-signature 1 0 0 0 none "$NOW")"
assert_eq "mutation 8: WATCHDOG_ARMED unset (0) + full signature → detect-only, never restart" "detect-only" \
  "$(watchdog_decision hang-signature 0 0 0 0 none "$NOW")"
assert_eq "mutation 7: last restart 10 min ago (<30 min cooldown) → cooldown" "cooldown" \
  "$(watchdog_decision hang-signature 1 0 1 1 1799999400 "$NOW")"
assert_eq "cooldown expired (>30 min) → restart" "restart" \
  "$(watchdog_decision hang-signature 1 0 1 1 1799997000 "$NOW")"
assert_eq "mutation 9: attempts exhausted (3) → give-up" "give-up" \
  "$(watchdog_decision hang-signature 1 0 1 3 1799990000 "$NOW")"
assert_eq "give-up wins over cooldown (3 attempts, recent last) → give-up" "give-up" \
  "$(watchdog_decision hang-signature 1 0 1 3 1799999400 "$NOW")"
assert_eq "mutation 10: corrupt sentinel ledger → fail-closed" "fail-closed" \
  "$(watchdog_decision hang-signature 1 1 1 1 1799999400 "$NOW")"
assert_eq "mutation 10b: claimed restart but ZERO parseable sentinels → fail-closed" "fail-closed" \
  "$(watchdog_decision hang-signature 1 0 1 0 none "$NOW")"
assert_eq "non-signature verdict never reaches a write → no-action (healthy)" "no-action" \
  "$(watchdog_decision healthy 1 0 0 0 none "$NOW")"
assert_eq "no-action on ambiguous" "no-action" \
  "$(watchdog_decision ambiguous 1 0 0 0 none "$NOW")"
assert_eq "no-action on probe-unavailable" "no-action" \
  "$(watchdog_decision probe-unavailable 1 0 0 0 none "$NOW")"
assert_eq "detect-only is reported even when armed=0 with a stale ledger entry" "detect-only" \
  "$(watchdog_decision hang-signature 0 0 1 1 1799997000 "$NOW")"
# fail-closed BEATS detect-only (order is load-bearing: an unarmed watchdog
# still surfaces a corrupt/claimed ledger as the defect it is, not silence).
assert_eq "corrupt=1 + armed=0 → fail-closed (beats detect-only)" "fail-closed" \
  "$(watchdog_decision hang-signature 0 1 0 0 none "$NOW")"
assert_eq "claimed-without-sentinel + armed=0 → fail-closed (beats detect-only)" "fail-closed" \
  "$(watchdog_decision hang-signature 0 0 1 0 none "$NOW")"
# far-FUTURE epoch (edited/forged sentinel or clock skew past tolerance) →
# fail-closed, never a silent permanent cooldown.
assert_eq "last_epoch in the future → fail-closed (no silent perma-cooldown)" "fail-closed" \
  "$(watchdog_decision hang-signature 1 0 1 1 99999999999 "$NOW")"
# Cooldown boundary — strict <: exactly 1800s since last attempt → restart.
assert_eq "cooldown boundary: diff==1799 → cooldown" "cooldown" \
  "$(watchdog_decision hang-signature 1 0 1 1 $((NOW - 1799)) "$NOW")"
assert_eq "cooldown boundary: diff==1800 → restart" "restart" \
  "$(watchdog_decision hang-signature 1 0 1 1 $((NOW - 1800)) "$NOW")"
assert_eq "attempts=2 (< 3 give-up) → restart" "restart" \
  "$(watchdog_decision hang-signature 1 0 1 2 1799990000 "$NOW")"

# --- hardening: duplicates, malformed tokens, crafted bodies ----------------
# A DUPLICATED service name is a malformed observation (last-wins would let a
# second ACTIVE_HEALTHY hide an earlier UNHEALTHY).
DUP_DB='[{"name":"db","status":"UNHEALTHY"},{"name":"db","status":"ACTIVE_HEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'
assert_eq "duplicate service name (db twice) → ambiguous" "ambiguous" \
  "$(classify_health_read 200 "$DUP_DB")"
assert_eq "duplicate extra service hiding UNHEALTHY behind ACTIVE_HEALTHY → ambiguous" "ambiguous" \
  "$(classify_health_read 200 '[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"},{"name":"storage","status":"UNHEALTHY"},{"name":"storage","status":"ACTIVE_HEALTHY"}]')"
# Out-of-vocabulary name/status tokens (lowercase status, digit name, missing
# fields, non-object element) — every malformed shape is ambiguous, and the
# jq-side validation holds the line BEFORE the pairs are emitted as lines.
assert_eq "lowercase status vocabulary → ambiguous" "ambiguous" \
  "$(classify_health_read 200 '[{"name":"db","status":"unhealthy"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]')"
assert_eq "non-lowercase service name → ambiguous" "ambiguous" \
  "$(classify_health_read 200 '[{"name":"DB","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]')"
assert_eq "service element missing .name → ambiguous" "ambiguous" \
  "$(classify_health_read 200 '[{"status":"UNHEALTHY"},{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]')"
assert_eq "non-object array element → ambiguous" "ambiguous" \
  "$(classify_health_read 200 '[{"name":"db","status":"UNHEALTHY"},"x",{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]')"
assert_eq "field-injection: newline inside status → ambiguous (not a smuggled read)" "ambiguous" \
  "$(classify_health_read 200 '[{"name":"pooler","status":"ACTIVE_HEALTHY\ndb=UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"db","status":"UNHEALTHY"}]')"

# --- ledger edge cases --------------------------------------------------------
# An 8- or 12-digit epoch violates the strict marker regex → corrupt, not
# silent mis-parse.
assert_eq "ledger: 8-digit epoch → corrupt=1" "attempts=0 last_epoch=none corrupt=1" \
  "$(printf '%b' '<!-- watchdog:restart epoch=99999999 -->\n' | parse_restart_ledger)"
assert_eq "ledger: 12-digit epoch → corrupt=1" "attempts=0 last_epoch=none corrupt=1" \
  "$(printf '%b' '<!-- watchdog:restart epoch=999999999999 -->\n' | parse_restart_ledger)"
# A 0-prefixed epoch containing 8/9 must not silently lose the last_epoch max
# (octal arithmetic error inside (( ))). 10# pins base-10.
assert_eq "ledger: octal-looking epoch is counted and ordered" "attempts=2 last_epoch=0799999000 corrupt=0" \
  "$(printf '%b' '<!-- watchdog:restart epoch=0799999000 -->\n<!-- watchdog:restart epoch=0799998000 -->\n' | parse_restart_ledger)"
# "01799999400" is 11 digits (regex-legal), 0-prefixed, contains 8/9 — the
# normalization must make it read as 1799999400 (600 s ago) → cooldown, not a
# bash base error dying mid-function into an unbounded restart.
assert_eq "decide: octal-looking last_epoch normalizes via 10# → cooldown" "cooldown" \
  "$(watchdog_decision hang-signature 1 0 1 1 01799999400 "$NOW")"

# --- CLI: usage-error exits and mode coverage ---------------------------------
assert_eq "CLI --decide happy path → restart" "0|restart" \
  "$(cli --decide --verdict hang-signature --armed 1 --corrupt 0 --claimed 0 --attempts 0 --last-epoch none --now "$NOW")"
assert_eq "CLI --decide missing required flag → exit 64" "64|" \
  "$(cli --decide --verdict hang-signature --armed 1)"
assert_eq "CLI --decide bare flag (no value) → exit 64, not a hang" "64|" \
  "$(cli --decide --verdict hang-signature --armed 1 --corrupt 0 --claimed 0 --attempts 0 --last-epoch none --now)"
assert_eq "CLI --decide non-numeric attempts → exit 64" "64|" \
  "$(cli --decide --verdict hang-signature --armed 1 --corrupt 0 --claimed 0 --attempts abc --last-epoch none --now "$NOW")"
assert_eq "CLI --decide flag-shaped value → exit 64" "64|" \
  "$(cli --decide --verdict hang-signature --armed 1 --corrupt 0 --claimed --now --attempts 0 --last-epoch none --now "$NOW")"
assert_eq "CLI classify bare --corroborator → exit 64, not a hang" "64|" \
  "$(cli --corroborator)"
assert_eq "CLI --read with a code but no body → exit 64" "64|" \
  "$(cli --corroborator error --read 200 "$SIG" --read 200)"
ledger_rc=0
ledger_out="$(printf '%b' "$LEDGER_ONE" | bash "$SCRIPT" --ledger 2>/dev/null)" || ledger_rc=$?
assert_eq "CLI --ledger mode parses stdin" "0|attempts=1 last_epoch=1799999000 corrupt=0" \
  "${ledger_rc}|${ledger_out}"

echo "=== Results: $PASS passed, $FAIL failed ==="
# Exact assertion floor: a deleted or skipped row changes the dispatched count.
readonly EXPECTED_ASSERTIONS=78
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then
  printf '  FAIL: dispatched %s assertions, expected exactly %s — a row was added, removed or skipped\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
