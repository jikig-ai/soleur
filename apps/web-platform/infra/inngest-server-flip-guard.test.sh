#!/usr/bin/env bash
# Tests for inngest-server-flip-guard.sh — the P1-5 arm-atomicity ExecStartPre guard
# (#6178, ADR-100). Driven via the GUARD_POSTGRES_URI / GUARD_FLIP_FLAG fixture seams
# (no doppler). The guard blocks inngest-server start ONLY when the URI is prod AND the
# flag is not in {armed, flipping, flushed, done}; every other combination allows the start.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-server-flip-guard.sh"

# A representative prod URI (contains the dedicated Supabase project ref marker) and a
# dark/non-prod URI (a different ref). Synthesized fixtures — no real credentials.
readonly PROD_URI="postgres://postgres.pigsfuxruiopinouvjwy:REDACTED@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"
readonly DARK_URI="postgres://postgres.darkdevref00000000:REDACTED@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# run_guard <uri> <flag-present:0|1> <flag> -> echoes exit code.
# #7228: the done-owner marker is a FILE on the root disk, so the seam is a PATH.
# GUARD_OWNER_PRESENT points at a marker that exists; GUARD_OWNER_ABSENT at one that
# does not. Every pre-existing case gets the PRESENT path so it keeps testing what it
# always tested — "does the flag allowlist admit this state?" — rather than silently
# becoming a test of the new marker check.
GUARD_OWNER_DIR="$(mktemp -d)"
GUARD_OWNER_PRESENT="$GUARD_OWNER_DIR/present"
: > "$GUARD_OWNER_PRESENT"
GUARD_OWNER_ABSENT="$GUARD_OWNER_DIR/absent"
run_guard() {
  local uri="$1" has_flag="$2" flag="${3:-}"
  local rc=0
  if [[ "$has_flag" == "1" ]]; then
    GUARD_POSTGRES_URI="$uri" GUARD_FLIP_FLAG="$flag" \
      GUARD_DONE_OWNER_MARKER="$GUARD_OWNER_PRESENT" \
      bash "$TARGET" >/dev/null 2>&1 || rc=$?
  else
    # Flag genuinely unset in the env (no GUARD_FLIP_FLAG, no INNGEST_CUTOVER_FLIP).
    GUARD_POSTGRES_URI="$uri" \
      GUARD_DONE_OWNER_MARKER="$GUARD_OWNER_PRESENT" \
      bash "$TARGET" >/dev/null 2>&1 || rc=$?
  fi
  printf '%s' "$rc"
}

# Drives the #7228 done-owner check directly: <marker-path> -> rc.
run_guard_owner() {
  local marker="$1" rc=0
  GUARD_POSTGRES_URI="$PROD_URI" GUARD_FLIP_FLAG="done" \
    GUARD_DONE_OWNER_MARKER="$marker" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

assert_rc() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc";
  else fail "$desc (expected rc=$expected, got rc=$actual)"; fi
}
assert_blocks() {
  local desc="$1" rc="$2"
  if [[ "$rc" != "0" ]]; then pass "$desc"; else fail "$desc (expected non-zero, got rc=0 — start NOT blocked)"; fi
}

echo "=== inngest-server-flip-guard.sh test suite ==="

# --- Blocked: prod URI + flag unset / empty / stray ---
echo "TEST: prod URI + unset flag => BLOCK (non-zero)"
assert_blocks "prod + unset flag blocks" "$(run_guard "$PROD_URI" 0)"
echo "TEST: prod URI + empty flag => BLOCK (non-zero)"
assert_blocks "prod + empty flag blocks" "$(run_guard "$PROD_URI" 1 "")"
echo "TEST: prod URI + rollback flag => BLOCK (non-zero; rollback is not an allowed start state)"
assert_blocks "prod + rollback blocks" "$(run_guard "$PROD_URI" 1 "rollback")"
echo "TEST: prod URI + aborted flag => BLOCK (non-zero)"
assert_blocks "prod + aborted blocks" "$(run_guard "$PROD_URI" 1 "aborted")"

# --- Allowed: prod URI + flag in {armed, flipping, flushed, done} ---
# `flushed` is the #6553 fix: the flip FSM sets flag=flushed then calls start_server
# (inngest-cutover-flip.sh:188-189, and the flushed-resume arm :240), so the guard MUST
# allow a prod-URI start at flushed — else it blocks the FSM's own controlled start.
for flag in armed flipping flushed "done"; do
  echo "TEST: prod URI + '$flag' flag => ALLOW (exit 0)"
  assert_rc "prod + '$flag' allows start" "0" "$(run_guard "$PROD_URI" 1 "$flag")"
done

# --- Allowed: dark (non-prod) URI + ANY flag (incl. unset) ---
echo "TEST: dark URI + unset flag => ALLOW (exit 0)"
assert_rc "dark + unset allows start" "0" "$(run_guard "$DARK_URI" 0)"
for flag in armed rollback aborted "" garbage; do
  echo "TEST: dark URI + '${flag:-unset}' flag => ALLOW (exit 0)"
  assert_rc "dark + '${flag:-unset}' allows start" "0" "$(run_guard "$DARK_URI" 1 "$flag")"
done

# --- Purity: the guard must not echo the connection string (AC-NOBODY) ---
echo "TEST: guard never echoes the Postgres URI (AC-NOBODY)"
out=$(GUARD_POSTGRES_URI="$PROD_URI" GUARD_FLIP_FLAG="" bash "$TARGET" 2>&1 || true)
if [[ "$out" == *"pigsfuxruiopinouvjwy"* || "$out" == *"pooler.supabase.com"* || "$out" == *"REDACTED"* ]]; then
  fail "guard leaked a connection-string fragment into its output"
else
  pass "guard output carries no connection-string fragment"
fi

# --- DIAGNOSTIC BOOT (#7228) --------------------------------------------------------------
# The flag rests at `rollback` after the 2026-08-11 rollback, which the allowlist excludes, so
# the guard refuses every prod-URI start — correct, but it also means a REPLACED host can never
# attempt a bind and every hypothesis stays UNKNOWN. Diagnostic boot exists to break that, and
# the whole question is whether it can be abused into starting a second prod scheduler.
#
# The guard does not trust INNGEST_DIAGNOSTIC_BOOT; it verifies the UNIT. So the fixtures below
# are unit files, and each direction is driven separately.
echo "TEST: diagnostic boot is gated on the unit, not on the flag (#7228)"
DIAG_TMP="$(mktemp -d)"
DURABLE_UNIT="$DIAG_TMP/durable.service"
SQLITE_UNIT="$DIAG_TMP/sqlite.service"
# Mirrors inngest-bootstrap.sh's two BACKEND_FLAGS forms: the durable one carries the
# --postgres-max-open-conns sentinel FIRST; the SQLite-only one carries no backend flags.
printf '%s\n' \
  "ExecStart=/usr/bin/doppler run --config prd -- /usr/bin/bash -c 'exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest --postgres-max-open-conns 5 --postgres-max-idle-conns 2 --poll-interval 60'" \
  > "$DURABLE_UNIT"
printf '%s\n' \
  "ExecStart=/usr/bin/doppler run --config prd -- /usr/bin/bash -c 'unset INNGEST_POSTGRES_URI; exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest --poll-interval 60'" \
  > "$SQLITE_UNIT"

run_guard_diag() {  # <uri> <flag> <diagnostic> <unit-file> -> rc
  local uri="$1" flag="$2" diag="$3" unit="$4" rc=0
  GUARD_POSTGRES_URI="$uri" GUARD_FLIP_FLAG="$flag" \
    GUARD_DIAGNOSTIC_BOOT="$diag" GUARD_UNIT_FILE="$unit" \
    GUARD_DONE_OWNER_MARKER="$GUARD_OWNER_PRESENT" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# The payload: prod URI + the CURRENT LIVE flag (`rollback`) + a SQLite-only unit => ALLOW.
assert_rc "diagnostic boot ALLOWs a prod-URI host at flag=rollback when the unit is SQLite-only" \
  "0" "$(run_guard_diag "$PROD_URI" rollback 1 "$SQLITE_UNIT")"
# The abuse direction: the same request against a DURABLE unit must be refused. This is the one
# state where allowing would start a real second prod scheduler.
assert_rc "diagnostic boot BLOCKS when the unit still carries the durable sentinel (halves disagree)" \
  "1" "$(run_guard_diag "$PROD_URI" rollback 1 "$DURABLE_UNIT")"
# Fail closed on an unprovable backend: an unreadable unit must not be read as non-durable.
assert_rc "diagnostic boot BLOCKS when the unit file is missing (cannot prove non-durable)" \
  "1" "$(run_guard_diag "$PROD_URI" rollback 1 "$DIAG_TMP/nonexistent.service")"
# And it must not become a general bypass: with diagnostic OFF the SQLite unit changes nothing,
# because the guard's job in that case is still governed by the flag allowlist.
assert_rc "without the diagnostic flag, a SQLite unit does NOT relax the guard (prod URI + rollback still blocks)" \
  "1" "$(run_guard_diag "$PROD_URI" rollback 0 "$SQLITE_UNIT")"
# Non-prod URIs were already allowed; diagnostic mode must not change that either way.
assert_rc "diagnostic boot leaves a non-prod URI allowed" \
  "0" "$(run_guard_diag "$DARK_URI" rollback 1 "$SQLITE_UNIT")"
# A legitimate post-cutover start must remain allowed with diagnostic off.
assert_rc "flag=done with a durable unit and diagnostic off still allows (no regression)" \
  "0" "$(run_guard_diag "$PROD_URI" done 0 "$DURABLE_UNIT")"
rm -rf "$DIAG_TMP"

# --- #7228: the done-owner PATH must agree between writer and reader ------------------------
# The writer (inngest-cutover-flip.sh) and the reader (this guard) each declare the default
# independently. Nothing pinned them, which is the one cross-file invariant in this change whose
# divergence is SILENT AND FAIL-OPEN: if the guard's path drifts onto anything that exists on a
# fresh host — most cheaply the parent directory the writer's own `mkdir -p` creates — the `-e`
# test becomes a permanent ALLOW and the inherited-`done` prod start this whole gate exists to
# refuse sails through, with every suite green.
#
# Every OTHER cross-file invariant in this PR is already pinned this way (the GQL query byte
# identity, the verify window vs --poll-interval, DURABLE_SENTINEL vs BACKEND_FLAGS). This one
# was the omission. Both operands extracted BY SHAPE — a restated literal would agree with
# itself while disagreeing with the file it came from.
echo "TEST: the done-owner marker path agrees between the FSM writer and this guard (#7228)"
FLIP_SH="$SCRIPT_DIR/inngest-cutover-flip.sh"
GUARD_PATH=$(grep -oE '^DONE_OWNER_MARKER="\$\{GUARD_DONE_OWNER_MARKER:-[^}]+\}"' "$TARGET" \
  | sed -E 's/.*:-([^}]+)\}"/\1/' | head -1 || true)
FLIP_PATH=$(grep -oE '^DONE_OWNER_MARKER="\$\{CUTOVER_DONE_OWNER_MARKER:-[^}]+\}"' "$FLIP_SH" \
  | sed -E 's/.*:-([^}]+)\}"/\1/' | head -1 || true)
if [[ -z "$GUARD_PATH" || -z "$FLIP_PATH" ]]; then
  fail "could not extract the marker path from both files by shape (guard='$GUARD_PATH' flip='$FLIP_PATH') — this pin is vacuous"
elif [[ "$GUARD_PATH" != "$FLIP_PATH" ]]; then
  fail "done-owner path DRIFT: the guard reads '$GUARD_PATH' but the FSM writes '$FLIP_PATH' — the guard would never see a legitimately-recorded owner, or would see a path that always exists"
else
  pass "done-owner marker path agrees across writer and reader ($GUARD_PATH)"
fi
# And it must not be a bare directory: `-e` on the parent that record_done_owner mkdir -p's would
# be true on every host that ever ran the FSM, including a replaced one.
assert_rc "the marker path is a FILE under its directory, not the directory itself" \
  "0" "$([[ "$(basename "$FLIP_PATH")" != "$(basename "$(dirname "$FLIP_PATH")")" && "$FLIP_PATH" == */*/* ]] && echo 0 || echo 1)"

# --- #7228 (3.7): a `done` INHERITED from another host must not authorize a prod start -------
# THE HAZARD THE ALLOWLIST CANNOT SEE. The flag lives in Doppler, which OUTLIVES THE HOST.
# `done` says the flip completed — it does not say on WHICH machine. The 2026-07-30 host recorded
# `done`, never bound :8288, and the flag still read `done` twelve days later. A REPLACED host
# boots, inherits a `done` it never earned, the allowlist says ALLOW, and if the co-located
# scheduler is still carrying the registry that is the double-fire race ADR-100's P1-5 guard
# exists to prevent — reached THROUGH the guard rather than around it.
echo "TEST: a done flag with no owner marker on THIS host is refused (#7228)"
assert_rc "own marker: prod + done + a present owner marker ALLOWs (the legitimate post-cutover start)" \
  "0" "$(run_guard_owner "$GUARD_OWNER_PRESENT")"
# The inheritance case: a replaced host has a fresh root disk, so the marker cannot be there.
assert_rc "ABSENT marker: prod + done on a host that never recorded ownership BLOCKS (inherited done)" \
  "1" "$(run_guard_owner "$GUARD_OWNER_ABSENT")"
# A path whose PARENT does not exist is the same absence, and must not error differently.
assert_rc "ABSENT marker (missing parent dir): still BLOCKS rather than erroring" \
  "1" "$(run_guard_owner "$GUARD_OWNER_DIR/no/such/dir/done-owner")"
# SCOPE. Only `done` is terminal and therefore inheritable; the other allowlisted states belong
# to a flip actively in progress on THIS host, and the FSM has not written a stamp yet when they
# are read. Gating them would DEADLOCK the cutover — the guard would block the very start the FSM
# is driving. These two prove the check did not leak into the transient states.
echo "TEST: the owner check is scoped to done, not to the transient flip states (#7228)"
for _st in armed flipping flushed; do
  rc=0
  GUARD_POSTGRES_URI="$PROD_URI" GUARD_FLIP_FLAG="$_st" \
    GUARD_DONE_OWNER_MARKER="$GUARD_OWNER_ABSENT" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_rc "flag=$_st with NO owner marker still ALLOWs (transient states are not inheritable)" "0" "$rc"
done
# And a non-prod URI is unaffected: the stamp check only guards against a second PROD scheduler.
rc=0
GUARD_POSTGRES_URI="$DARK_URI" GUARD_FLIP_FLAG="done" \
  GUARD_DONE_OWNER_MARKER="$GUARD_OWNER_ABSENT" \
  bash "$TARGET" >/dev/null 2>&1 || rc=$?
assert_rc "non-prod URI + absent marker still ALLOWs (no second prod scheduler is possible)" "0" "$rc"

# --- TWO-HALF AGREEMENT: both consumers must read the SAME variable and the SAME sentinel ----
# Diagnostic boot is only safe because the guard's relaxation and the bootstrap's backend
# selection are driven by one variable and adjudicated by one sentinel. If a future edit renames
# either in one file alone, the host would start DURABLY while the guard believed it was
# diagnostic — the exact second-prod-scheduler state this is built to prevent. Anchor on the
# syntactic read/assignment, not a bare word a comment could satisfy.
echo "TEST: diagnostic-boot halves are pinned in lockstep"
BOOTSTRAP="$SCRIPT_DIR/inngest-bootstrap.sh"
if grep -qE '(GUARD_DIAGNOSTIC_BOOT-\$\{INNGEST_DIAGNOSTIC_BOOT|INNGEST_DIAGNOSTIC_BOOT:-)' "$TARGET"; then
  pass "guard reads INNGEST_DIAGNOSTIC_BOOT"
else
  fail "guard no longer reads INNGEST_DIAGNOSTIC_BOOT — the diagnostic half is disconnected"
fi
if grep -qE '^DIAGNOSTIC_BOOT="\$\(printf .*INNGEST_DIAGNOSTIC_BOOT' "$BOOTSTRAP"; then
  pass "bootstrap reads the SAME INNGEST_DIAGNOSTIC_BOOT variable"
else
  fail "bootstrap no longer reads INNGEST_DIAGNOSTIC_BOOT — the halves have drifted apart"
fi
if grep -qE '^readonly DURABLE_SENTINEL="--postgres-max-open-conns"' "$TARGET" \
   && grep -qE "BACKEND_FLAGS='--postgres-max-open-conns" "$BOOTSTRAP"; then
  pass "guard's durable sentinel matches the token bootstrap actually emits"
else
  fail "the durable sentinel drifted between the guard and inngest-bootstrap.sh — the guard can no longer tell a durable unit from a SQLite one"
fi
# The bootstrap's diagnostic branch must produce a unit the guard will accept: no backend flags.
if awk '/DIAGNOSTIC_BOOT" == "1"/,/^elif/' "$BOOTSTRAP" | grep -qE "^[[:space:]]*BACKEND_FLAGS=''[[:space:]]*$"; then
  pass "bootstrap's diagnostic branch emits EMPTY backend flags (so the guard can prove non-durable)"
else
  fail "bootstrap's diagnostic branch does not clear BACKEND_FLAGS — the guard would block its own diagnostic unit"
fi

# --- FSM<->guard lockstep drift guard (#6553 / ADR-100 class invariant) ---
# The guard's ALLOW allowlist MUST be a SUPERSET of every FSM state in which the cutover
# flip oneshot invokes `start_server`. Otherwise the guard blocks the FSM's own controlled
# start (the #6553 bug). Both sets are derived from source, so a future `flag_set <X>;
# start_server` (or a `<X>)` case arm that starts the server) that the guard omits FAILS here.
echo "TEST: FSM start-states are a subset of the guard allowlist (lockstep drift guard)"
FSM="$SCRIPT_DIR/inngest-cutover-flip.sh"
if [[ ! -f "$FSM" ]]; then
  fail "FSM source $FSM not found — cannot verify lockstep"
else
  # Guard allowlist: the tokens before ')' on the `flag_ok=true` case line.
  guard_allow=$(grep -E 'flag_ok=true' "$TARGET" | head -1 | sed -E 's/\).*//' \
    | tr '|' '\n' | sed -E 's/[[:space:]]//g' | grep -E '^[a-z-]+$' | LC_ALL=C sort -u)
  # FSM start-states: walk top-down tracking the nearest preceding `flag_set <arg>` OR case-arm
  # label `<state>)`, and emit that state at every line that STARTS THE SERVER. "Starts the
  # server" is deliberately BROAD — ANY `start_server` call shape (bare, `if ! start_server`,
  # `start_server || flag_set aborted`, …) OR a direct `systemctl_cmd start "$SERVER_UNIT"` (the
  # helper's body — a future arm could inline it, bypassing the `start_server` name). A narrow
  # "bare `start_server` on its own line" match is VACUOUS: the FSM's own idiom is compound
  # (`if ! redis_flushall`), so a resume/repair arm written `if ! start_server` in a
  # non-allowlisted state would run the server where the runtime guard blocks it — the #6553 bug —
  # with this test green. The `start_server()`/`flag_set()` DEFINITION lines and comments are
  # skipped first, so the helper body's own `systemctl_cmd start` is not counted as a call.
  raw_starts=$(awk '
    /^[[:space:]]*#/                                   { next }
    /^[[:space:]]*flag_set[[:space:]]+["'\'']?[a-z-]+/  { s=$2; gsub(/["'\'']/,"",s); cur=s; next }
    /^[[:space:]]*[a-z][a-z_-]*\)[[:space:]]*$/         { s=$1; sub(/\).*/,"",s); cur=s; next }
    /^[[:space:]]*start_server\(\)/                     { next }
    /(^|[^A-Za-z_])start_server([^A-Za-z_(]|$)/         { if (cur!="") print cur; next }
    /systemctl_cmd start[[:space:]]+"\$SERVER_UNIT"/    { if (cur!="") print cur; next }
  ' "$FSM")
  fsm_states=$(printf '%s\n' "$raw_starts" | grep -vE '^$' | LC_ALL=C sort -u)
  start_site_count=$(printf '%s\n' "$raw_starts" | grep -cE '^[a-z-]+$' || true)

  # Count-drift latch (also gives the case-arm-label rule independent coverage): the FSM starts
  # the server at exactly EXPECTED_START_SITES places today — the forward-path
  # `flag_set flushed; start_server` and the `flushed)` resume arm. A change to this count means a
  # start site was added/removed OR a derivation rule silently dropped one; re-verify each new
  # state is in the guard allowlist, then bump EXPECTED_START_SITES.
  EXPECTED_START_SITES=2

  if [[ "$start_site_count" -ne "$EXPECTED_START_SITES" ]]; then
    fail "FSM start_server call-site count = $start_site_count, expected $EXPECTED_START_SITES — a start site was added/removed (or a derivation rule dropped one). Re-verify each new state is in the guard allowlist, then update EXPECTED_START_SITES. Derived states: [$(printf '%s' "$fsm_states" | tr '\n' ' ')]"
  # Non-vacuity: the derivation MUST find the known start-state (flushed). A silent empty
  # derivation would make the subset check pass vacuously.
  elif ! printf '%s\n' "$fsm_states" | grep -qx 'flushed'; then
    fail "lockstep derivation did not find the known 'flushed' start-state (derivation broken?); got: [$(printf '%s' "$fsm_states" | tr '\n' ' ')]"
  else
    missing=$(LC_ALL=C comm -23 <(printf '%s\n' "$fsm_states") <(printf '%s\n' "$guard_allow"))
    if [[ -n "$missing" ]]; then
      fail "FSM starts the server in state(s) the guard allowlist OMITS: [$(printf '%s' "$missing" | tr '\n' ' ')] — widen inngest-server-flip-guard.sh (ADR-100 class invariant: allowlist must cover every start_server state)"
    else
      pass "guard allowlist [$(printf '%s' "$guard_allow" | tr '\n' ' ')] covers all FSM start-states [$(printf '%s' "$fsm_states" | tr '\n' ' ')] ($start_site_count start sites)"
    fi
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
