#!/usr/bin/env bash
# Tests the MONOTONIC re-flush latch in inngest-cutover-flip.sh (#7228 Phase 3; the defect the
# plan review found as P0-5). Sibling of inngest-cutover-flip.test.sh, which covers the FSM's
# state transitions — this suite covers ONLY the catastrophe guard that decides whether a
# FLUSHALL may run at all.
#
# THE BUG THIS EXISTS FOR. `emit_state()` writes the state slot on EVERY branch, including the
# terminal no-ops, and the `rolled-back` arm stamps {"flag":"rolled-back"} over it.
# `flip_already_done()` returned true only for exactly "done". So:
#
#     done  ->  rollback  ->  (poll) rolled-back  ->  armed
#      |            |                                   |
#   latch armed   slot OVERWRITTEN                  latch reads "rolled-back"
#                 (the `done` record is GONE)       => not done => run_preflush_flip
#                                                   => FLUSHALL against a LIVE prod Redis
#
# Today that fails SAFE only by accident: the slot lives on /var/lock, i.e. the ephemeral root
# disk, so a host replace wipes it and a genuine first flip proceeds. The first draft of this
# plan proposed relocating the slot onto the durable /mnt/data volume — which would have made it
# strictly WORSE by PERSISTING the erasure across a replace, converting a latch that fails safe
# by amnesia into one that fails unsafe by false memory. Hence: monotonic, not relocated.
#
# THE FIX, AND WHY IT IS A DISJUNCTION. The predicate becomes "has a FLUSHALL EVER been
# performed?", answered by EITHER a durable append-only latch file on /mnt/data OR the legacy
# state slot recording `done`. Both arms are needed and each is fixtured ALONE below:
#   * durable latch — the reliable arm. Existence-based, never rewritten, so no branch can erase
#     it, and it lives on the volume that SURVIVES the replace. Survival is the whole point: the
#     replace is the operation that disarms the current latch.
#   * legacy state slot — the compatibility arm. A host that already completed a flip BEFORE this
#     change ships has no latch file, only a slot. Dropping this arm would silently disarm the
#     guard on exactly those hosts until their next flip. It is best-effort by construction (it
#     is the erasable one), so it only ever ADDS refusals.
#
# AND THE LATCH MUST NOT LIE ABOUT BEING DURABLE. cloud-init mounts the volume with `|| true`
# and fstab carries `nofail`, so a FAILED mount leaves /mnt/data as a plain directory on the
# ephemeral root disk. A latch written there looks durable and is not — it would vanish on the
# very replace it exists to survive. So the write is mountpoint-gated, and both the gate and the
# write are FATAL rather than `2>/dev/null || true`: a latch that cannot be recorded means the
# catastrophe guard is disarmed, which must fail loud (cq-silent-fallback-must-mirror-to-sentry).
#
# Run: bash apps/web-platform/infra/inngest-cutover-latch.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-cutover-flip.sh"
SVC="$SCRIPT_DIR/inngest-cutover-flip.service"
CAT_STATE="$SCRIPT_DIR/cat-inngest-cutover-state.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc";
  else fail "$desc"; echo "    expected: $expected"; echo "    actual:   $actual"; fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$desc";
  else fail "$desc (needle '$needle' not in '$haystack')"; fi
}
assert_absent() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then pass "$desc";
  else fail "$desc (unexpected '$needle' in '$haystack')"; fi
}

# INSTRUMENT SELF-TEST (#7695 mutation audit). Every claim in this file is dispatched through
# pass()/fail(), and the LATCH_MIN_ASSERTIONS floor at the bottom dispatches through fail()
# too. One edit — `fail() { echo ...; }` stops incrementing FAIL — makes all 45 assertions AND
# the floor that backstops them report green together. No assertion can catch that, because
# every assertion is downstream of it. So prove both counters move before trusting anything,
# then reset. Reported directly with printf + exit (ADR-193): a check routed through the
# helper it backstops dies with the same edit that disarms the helper. Output suppressed so
# the deliberate FAIL row cannot be misread as a real one.
pass "instrument self-test" >/dev/null
fail "instrument self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: assertion counters are broken (PASS=%s FAIL=%s, expected 1/1).\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

WORK="" TRACE="" STATE="" LOGTRACE="" LATCH="" MOUNTDIR=""
SYSCTL="" REDIS="" FLAGSET="" LOGGER=""

# Owning trap (ADR-129). teardown_case already removes $WORK on the happy path, but only
# there — a die between setup_case and teardown_case (a failed assertion under `set -e`, an
# interrupt) leaks the whole tempdir. Single-quoted so it resolves $WORK at EXIT time, i.e.
# the case that was in flight when the script died; empty $WORK is a no-op via the guard.
trap '[[ -n "$WORK" ]] && rm -rf "$WORK"' EXIT

setup_case() {
  WORK=$(mktemp -d)
  TRACE="$WORK/trace"; STATE="$WORK/state.json"; LOGTRACE="$WORK/logtrace"
  MOUNTDIR="$WORK/mnt"; LATCH="$MOUNTDIR/inngest-cutover/flip-done.latch"
  mkdir -p "$MOUNTDIR"
  : > "$TRACE"; : > "$LOGTRACE"
  SYSCTL="$WORK/sysctl.sh"; REDIS="$WORK/redis.sh"; FLAGSET="$WORK/flagset.sh"; LOGGER="$WORK/logger.sh"
  # The seams additionally stamp WHETHER THE LATCH EXISTS at the moment they are called. A file
  # write is invisible to a command trace, so this is how the suite proves the latch is recorded
  # at the flush rather than at completion — without adding a seam to the SUT for the very write
  # under test.
  cat > "$SYSCTL"  <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$TRACE"
[ -e "$LATCH" ] && printf 'latch@%s\n' "\$1" >> "$TRACE"
exit 0
EOF
  cat > "$REDIS"   <<EOF
#!/usr/bin/env bash
op="\$(printf '%s' "\$1" | tr '[:upper:]' '[:lower:]')"
printf '%s\n' "\$op" >> "$TRACE"
[ -e "$LATCH" ] && printf 'latch@%s\n' "\$op" >> "$TRACE"
exit 0
EOF
  cat > "$FLAGSET" <<EOF
#!/usr/bin/env bash
printf 'flag:%s\n' "\$1" >> "$TRACE"
EOF
  cat > "$LOGGER"  <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOGTRACE"
EOF
  # #7228: a HEALTHY host fixture. This suite's contract is the LATCH, so verification must be
  # satisfiable and out of the way — but it cannot be BYPASSED, because the latch is recorded at
  # the flush and the cases below assert its presence at points AFTER the verification runs.
  CURLSTUB="$WORK/curl.sh"
  cat > "$CURLSTUB" <<'CURLEOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in '%{http_code}') printf '%s' "${STUB_HEALTH_CODE:-200}"; exit 0 ;; esac
done
if [ -n "${STUB_REGISTRY_BODY:-}" ]; then
  printf '%s' "$STUB_REGISTRY_BODY"
else
  printf '%s' '{"data":{"functions":[{"id":"fn-1"}]}}'
fi
CURLEOF
  # #7228: the done-owner marker is a FILE, not a command, so it needs a writable path here —
  # without one the forward cases abort on verify-owner-unrecordable instead of exercising the
  # latch contract this suite owns.
  OWNER_MARKER="$WORK/owner/done-owner"
  chmod +x "$SYSCTL" "$REDIS" "$FLAGSET" "$LOGGER" "$CURLSTUB"
}
teardown_case() { rm -rf "$WORK"; }

# run_flip <flag> [EXTRA=val ...] -> exit code. INNGEST_CUTOVER_LATCH_MOUNT is set to "" by
# default so the mountpoint gate is OFF for the behavioural cases (a mktemp dir is not a
# mountpoint); the gate itself gets dedicated cases below.
run_flip() {
  local flag="$1"; shift
  local -a extra=("$@")
  local rc=0
  env CUTOVER_FLIP_FLAG="$flag" \
      CUTOVER_SYSTEMCTL_CMD="$SYSCTL" \
      CUTOVER_REDIS_CLI_CMD="$REDIS" \
      CUTOVER_FLAG_SET_CMD="$FLAGSET" \
      CUTOVER_LOGGER_CMD="$LOGGER" \
      INNGEST_CUTOVER_STATE="$STATE" \
      INNGEST_CUTOVER_LATCH="$LATCH" \
      INNGEST_CUTOVER_LATCH_MOUNT="" \
      `# --- #7228: the serving-verification seams. This suite owns the LATCH contract, not the` \
      `# verification one, so it fixtures a HEALTHY host and the window is collapsed to zero.` \
      `# Without these the FSM would run its real bounded-window curl against 127.0.0.1:8288 —` \
      `# a closed port in CI — retrying for 90s PER CASE, which does not fail the suite so much` \
      `# as hang it. A seam added to the FSM has to reach every harness that drives the FSM.` \
      CUTOVER_CURL_CMD="$CURLSTUB" \
      CUTOVER_DONE_OWNER_MARKER="$OWNER_MARKER" \
      CUTOVER_VERIFY_WINDOW_S=0 \
      CUTOVER_VERIFY_INTERVAL_S=0 \
      ${extra[@]+"${extra[@]}"} \
      bash "$TARGET" --fixture-seams >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}
trace_csv() { paste -sd, "$TRACE" 2>/dev/null || true; }

echo "=== inngest cutover monotonic re-flush latch (#7228 P0-5) ==="

# --- 1. THE HEADLINE REGRESSION: done -> rolled-back -> armed must REFUSE ------------------
# This is the exact sequence the first draft would have shipped as a live FLUSHALL against prod.
echo "TEST: done -> rollback -> rolled-back poll -> armed => REFUSE (no FLUSHALL)"
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
assert_eq "(1a) genuine first flip completes" "0" "$rc"
assert_contains "(1a) it FLUSHALLed" "$(trace_csv)" "flushall"
assert_eq "(1b) the durable latch was recorded" "yes" "$([[ -e "$LATCH" ]] && echo yes || echo no)"
# Now drive the erasure: rollback, then the terminal no-op poll. Both call emit_state, which
# overwrites the state slot — the mechanism that destroyed the `done` record.
: > "$TRACE"
run_flip rollback >/dev/null
run_flip rolled-back >/dev/null
assert_eq "(1c) the state slot no longer records done (the erasure really happens)" \
  "rolled-back" "$(jq -r '.flag' "$STATE" 2>/dev/null)"
assert_eq "(1d) the durable latch SURVIVED the erasure (monotonic)" \
  "yes" "$([[ -e "$LATCH" ]] && echo yes || echo no)"
# The payload: re-arm after the erasure.
: > "$TRACE"; : > "$LOGTRACE"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
order=$(trace_csv)
assert_eq "(1e) re-arm after erasure exits 1 (refuses)" "1" "$rc"
assert_absent "(1e) NO FLUSHALL against the live prod Redis" "$order" "flushall"
assert_absent "(1e) NO stop" "$order" "stop"
assert_absent "(1e) NO start" "$order" "start"
assert_contains "(1e) flag driven to terminal aborted" "$order" "flag:aborted"
assert_contains "(1e) loud refuse marker emitted" "$(cat "$LOGTRACE")" "refuse-rearm-after-done"
teardown_case

# --- 2. NEGATIVE CONTROL: without the durable latch the same sequence FLUSHES --------------
# Proves the latch is what saves it, not some other guard. Identical inputs, latch removed
# between the erasure and the re-arm.
echo "TEST: negative control — same sequence with the latch deleted DOES flush"
setup_case
run_flip armed CUTOVER_REDIS_DBSIZE=0 >/dev/null
run_flip rollback >/dev/null
run_flip rolled-back >/dev/null
rm -f "$LATCH"
: > "$TRACE"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
assert_contains "(2) with NO latch and an erased slot, the flush proceeds — the latch is load-bearing" \
  "$(trace_csv)" "flushall"
teardown_case

# --- 3. EACH DISJUNCT ALONE ---------------------------------------------------------------
# A fixture satisfying both arms at once would prove only that the set is non-empty: dropping
# either arm would keep the suite green. Drive each in isolation.
echo "TEST: durable-latch arm ALONE refuses (no state slot at all)"
setup_case
mkdir -p "$(dirname "$LATCH")"; printf 'flushed_at=x\n' > "$LATCH"
rm -f "$STATE"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
assert_eq "(3a) latch alone => exit 1" "1" "$rc"
assert_absent "(3a) latch alone => NO FLUSHALL" "$(trace_csv)" "flushall"
teardown_case

echo "TEST: legacy state-slot arm ALONE refuses (no latch file — the pre-change host)"
setup_case
printf '%s\n' '{"exit_code":0,"dbsize":"0","reason":"flip-complete","flag":"done","start_ts":"x"}' > "$STATE"
rm -f "$LATCH"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
assert_eq "(3b) slot alone => exit 1 (compat arm keeps already-flipped hosts guarded)" "1" "$rc"
assert_absent "(3b) slot alone => NO FLUSHALL" "$(trace_csv)" "flushall"
teardown_case

echo "TEST: neither arm => a genuine first flip proceeds"
setup_case
rm -f "$STATE" "$LATCH"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
assert_eq "(3c) neither => exit 0" "0" "$rc"
assert_contains "(3c) neither => FLUSHALL runs (guard does not block a first flip)" "$(trace_csv)" "flushall"
teardown_case

# --- 4. THE LATCH IS RECORDED AT THE FLUSH, NOT AT COMPLETION -----------------------------
# It means "a FLUSHALL has been performed", so it must land before start_server — otherwise a
# crash between the flush and the start leaves a later re-arm free to flush a prod queue.
echo "TEST: latch lands after the DBSIZE assert and BEFORE start"
setup_case
run_flip armed CUTOVER_REDIS_DBSIZE=0 >/dev/null
order=$(trace_csv)
assert_contains "(4a) the latch EXISTED by the time the server was started" "$order" "latch@start"
assert_absent "(4b) the latch did NOT exist when the FLUSHALL ran (it is recorded by this flip, not pre-existing)" \
  "$order" "latch@flushall"
# #7228 adds `instance:` between `start` and `flag:done`: `done` is now probe-derived, and the
# instance stamp is written BEFORE the flag so a crash in between cannot leave a `done` with no
# stamp (which the flip guard must treat as foreign). The latch's own position — recorded at the
# flush, present by the time the server starts — is unchanged, which is what this suite owns.
assert_eq "(4c) full ordering unchanged apart from the latch stamp" \
  "flag:flipping,stop,flushall,flag:flushed,start,latch@start,flag:done" "$order"
teardown_case

# --- 5. `flushed` RESUME BACKFILLS THE LATCH ----------------------------------------------
# Reaching `flushed` proves the flush succeeded. If the latch is absent there (crash between
# flush and latch write on a pre-change host), record it rather than leaving the guard disarmed.
echo "TEST: flushed-resume backfills a missing latch and never re-flushes"
setup_case
rm -f "$LATCH"
rc=$(run_flip flushed)
assert_eq "(5) flushed resume exits 0" "0" "$rc"
assert_absent "(5) flushed resume does NOT re-FLUSHALL (#5450 trap)" "$(trace_csv)" "flushall"
assert_eq "(5) flushed resume recorded the latch" "yes" "$([[ -e "$LATCH" ]] && echo yes || echo no)"
teardown_case

# --- 6. THE WRITE IS FATAL, NOT BEST-EFFORT ------------------------------------------------
# An unrecordable latch means the catastrophe guard is disarmed for every future poll. Silently
# swallowing that is exactly the shape cq-silent-fallback-must-mirror-to-sentry forbids.
echo "TEST: an unwritable latch path is FATAL, not swallowed"
setup_case
mkdir -p "$MOUNTDIR/inngest-cutover"
chmod 500 "$MOUNTDIR/inngest-cutover"
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0)
assert_eq "(6) unwritable latch => non-zero exit" "1" "$rc"
assert_contains "(6) unwritable latch => loud marker naming the latch" "$(cat "$LOGTRACE")" "latch"
assert_absent "(6) unwritable latch => server NOT started (fail closed)" "$(trace_csv)" "start"
chmod 700 "$MOUNTDIR/inngest-cutover"
teardown_case

# --- 7. THE MOUNTPOINT GATE ---------------------------------------------------------------
# /mnt/data is mounted `|| true` + `nofail`. On a failed mount it is a plain directory on the
# ephemeral root, and a latch written there would vanish on the replace it exists to survive.
echo "TEST: a latch directory that is NOT a mountpoint is refused"
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 INNGEST_CUTOVER_LATCH_MOUNT="$MOUNTDIR")
assert_eq "(7) non-mountpoint => non-zero exit" "1" "$rc"
assert_contains "(7) non-mountpoint => marker names the durability failure" \
  "$(cat "$LOGTRACE")" "latch"
assert_absent "(7) non-mountpoint => server NOT started" "$(trace_csv)" "start"
assert_eq "(7) non-mountpoint => NO fake-durable latch was left behind" \
  "no" "$([[ -e "$LATCH" ]] && echo yes || echo no)"
teardown_case

# --- 8. MONOTONICITY: no branch may clear the latch ----------------------------------------
# The failure mode was an erasing WRITE, so assert directly that every terminal branch leaves it.
echo "TEST: no FSM branch erases the latch"
setup_case
run_flip armed CUTOVER_REDIS_DBSIZE=0 >/dev/null
for f in rollback rolled-back done aborted unset flushed; do
  run_flip "$f" >/dev/null
  assert_eq "(8) latch survives the '$f' branch" "yes" "$([[ -e "$LATCH" ]] && echo yes || echo no)"
done
teardown_case

# --- 9. STATIC: the unit must not race the mount, and the read surface must show the latch --
echo "TEST: static unit + operator read-surface contract"
assert_eq "(9a) inngest-cutover-flip.service ORDERS after mnt-data.mount without REQUIRING it" "yes" \
  "$(grep -qE '^After=mnt-data\.mount$' "$SVC" && ! grep -qE '^RequiresMountsFor=' "$SVC" && echo yes || echo no)"
# The 30s timer can otherwise fire before the volume mounts, and the mountpoint gate would then
# abort a legitimate flip on a cold boot.
assert_eq "(9b) cat-inngest-cutover-state.sh surfaces the latch, not just the erasable slot" "yes" \
  "$(grep -qE 'INNGEST_CUTOVER_LATCH' "$CAT_STATE" && echo yes || echo no)"

# --- #7228: an UNPROVABLE mount must not reach FLUSHALL ------------------------------------
# Every other case here sets INNGEST_CUTOVER_LATCH_MOUNT="" to disable the gate, because a mktemp
# dir is not a mountpoint — so the gate itself had no fixture. That mattered: the write-path gate
# sits AFTER stop_server + redis_flushall, so on an absent /mnt/data the queue was destroyed
# before the guard spoke, and the READ path returned "not flushed" (latch invisible) which is the
# arm that authorises the flush. The catastrophe guard failed OPEN on exactly its own condition.
echo "TEST: #7228 an unprovable /mnt/data refuses the flush BEFORE anything destructive"
setup_case
rc=$(run_flip armed CUTOVER_REDIS_DBSIZE=0 INNGEST_CUTOVER_LATCH_MOUNT="$WORK/not-a-mountpoint")
order=$(trace_csv)
assert_eq "unprovable mount => non-zero exit" "1" "$rc"
assert_absent "unprovable mount => FLUSHALL never ran" "$order" "flushall"
assert_absent "unprovable mount => the server was never stopped" "$order" "stop"
assert_absent "unprovable mount => never reached done" "$order" "flag:done"
assert_contains "unprovable mount => terminal aborted" "$order" "flag:aborted"
assert_eq "unprovable mount => state reason is latch-unrecordable" \
  "latch-unrecordable" "$(jq -r '.reason' "$STATE")"
teardown_case

# --- assertion-count FLOOR ------------------------------------------------------------------
LATCH_MIN_ASSERTIONS=45  # derived from a green run; raise in lockstep when adding assertions
if [[ "$PASS" -lt "$LATCH_MIN_ASSERTIONS" ]]; then
  # printf + exit, NOT fail() (ADR-193, and #7695's mutation audit): routing the floor through
  # the counter it exists to protect means one edit disarms both.
  printf 'FAIL: assertion-count floor: only %s assertions ran, expected >= %s — a block was skipped or emptied.\n' \
    "$PASS" "$LATCH_MIN_ASSERTIONS" >&2
  exit 1
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
