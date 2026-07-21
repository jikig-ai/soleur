#!/usr/bin/env bash
#
# Behavioral test for workspaces-cutover.sh :: freeze_writers / resume_writers / app_canary /
# assert_mount_quiesced / arm_dead_man / cleanup (#6588 freeze-quiesce).
#
# Context: on 2026-07-19 two consecutive REAL /workspaces LUKS freezes safe-aborted on the C1
# byte-identity verify with exactly ONE difference:
#   SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF count=1 idx=0 icode=>fcst......
#     path=redis/appendonlydir/appendonly.aof.94.incr.aof
# `>fcst......` = checksum + size + mtime differ — a live-appending file, NOT a copy defect. Redis
# persists its AOF to /mnt/data/redis and runs as the SYSTEMD UNIT inngest-redis.service, not as a
# container, so `docker stop $CONTAINER` never touched it. The C1 gate was RIGHT; the writer was not
# quiesced. AC11 pins verify_byte_identity/emit_verify_diff as byte-identical to main.
#
# HARNESS: run_case, the stub set and every predicate live in workspaces-luks-harness.sh, shared
# with workspaces-luks-staging.test.sh (#6588 staging-target guards). The no-pipe rule that file
# documents is the reason this suite was rewritten once already: `calls | grep -q PAT` under
# `set -o pipefail` returns 141 when grep matches EARLY and the producer takes SIGPIPE, so a
# NEGATIVE assertion (`if ! ...`) fails OPEN — and because `HARNESS_UNDEFINED:` is line 1 and
# always an early match, `undef()` itself failed open and the vacuity guard was vacuous.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/workspaces-luks-cutover.yml"
# #6807 — the VERIFY workflow. Named here because the /api/health gate below must cover BOTH
# workflows: the cutover's canary was corrected in #6701 but the sweep never reached the verify
# workflow, which then sat structurally incapable of passing until #6807. (Note that
# workspaces-luks-verify.test.sh does NOT cover this file — despite the name it covers
# verify_byte_identity.)
VERIFY_WF="$SCRIPT_DIR/../../../.github/workflows/workspaces-luks-verify.yml"

# --- #6807 per-arm probe accounting -----------------------------------------
# Sleeps MUST be attributed per endpoint arm, never summed: the curl stub serves both /health and
# readyz through one `case`, so a global total lets readyz retries satisfy a /health assertion.
# awk, not `head | grep -c`: no pipe, per the harness no-pipe rule.
sleeps_before_readyz() { awk '/^curl .*readyz/{exit} /^sleep /{n++} END{print n+0}' "$CALLS"; }
health_probe_count()   { awk '/^curl .*readyz/{exit} /^curl /{n++} END{print n+0}' "$CALLS"; }
readyz_probe_count()   { awk '/^curl .*readyz/{n++} END{print n+0}' "$CALLS"; }
# Any sleep whose ARGUMENT is not the expected interval. Recording the argument (not just the call)
# is what makes the INTERVAL seam observable without a second channel.
bad_sleep_args()       { awk -v want="$1" '/^sleep /{if ($2 != want) n++} END{print n+0}' "$CALLS"; }

# shellcheck source=apps/web-platform/infra/workspaces-luks-harness.sh
. "$SCRIPT_DIR/workspaces-luks-harness.sh"

# ---------------------------------------------------------------------------
# freeze_writers — quiesce set, order, closed-world, persisted state
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'freeze_writers' 'freeze_writers' LSOF_OUT="" LSOF_RC=1
ran && ok "T0 freeze_writers succeeds on a clean mount (happy-path positive control)" \
     || no "T0 freeze_writers did not exit 0 on a clean mount: rc=$CASE_RC ${CASE_OUT:0:200}"
has '^systemctl stop .*inngest-redis\.service' \
  && ok "T1 freeze_writers stops inngest-redis.service (the unquiesced AOF writer)" \
  || no "T1 freeze_writers did NOT stop inngest-redis.service — the quiescence gap is unfixed"

wh="$(idx '^systemctl stop webhook\.service')"; dk="$(idx '^docker stop')"; rd="$(idx '^systemctl stop .*inngest-redis\.service')"
if [ -n "$wh" ] && [ -n "$dk" ] && [ -n "$rd" ] && [ "$wh" -lt "$dk" ] && [ "$dk" -lt "$rd" ]; then
  ok "T2 quiesce order: webhook, then the container drain, then the remaining writers"
else
  no "T2 quiesce order wrong (webhook=$wh docker=$dk redis=$rd; want webhook<docker<redis)"
fi

# T2b — the drain timeout is the C8 property, not an incidental number. `-t 1` truncates an
# in-flight write(); the whole point of -t 120 is to let it finish.
hasF 'docker stop -t 120' && ok "T2b the container drain keeps its 120s C8 timeout" \
                          || no "T2b the container drain timeout changed — a short -t SIGKILLs mid-write() (C8)"

grep -qE '^QUIESCED_UNITS=.*inngest-redis\.service' "$STATE/state" 2>/dev/null \
  && ok "T3 freeze_writers persists QUIESCED_UNITS naming inngest-redis.service" \
  || no "T3 QUIESCED_UNITS not persisted (or omits inngest-redis.service)"

# T3b — CLOSED-WORLD. "the right units are stopped" needs an upper bound too, else a unit added to
# the stop set but restored by NO exit path passes every other assertion.
# Anchored at end-of-line so this matches only SINGLE-unit stops (the _quiesce_list loop). The
# timer quiesce uses the two-argument `stop <x>.timer <x>.service` pair form and is asserted
# separately by T3c/T3d — folding both shapes into one set would hide a drift in either.
stops="$(grep -oE '^systemctl stop [a-z0-9@.-]+$' "$CALLS" | awk '{print $3}' | sort -u || true)"
expected_stops="$(printf '%s\n' inngest-redis.service webhook.service | sort -u)"
if [ "$stops" = "$expected_stops" ]; then
  ok "T3b closed-world: the set of stopped .service units is EXACTLY _quiesce_list"
else
  no "T3b stop-set drift — stopped=[$(echo $stops)] expected=[$(echo $expected_stops)]"
fi

# T3c — the timer/service PAIRS. Stopping a .timer does not stop the instance it already launched.
hasF 'systemctl stop orphan-reaper.timer orphan-reaper.service' \
  && ok "T3c orphan-reaper timer AND service are stopped (6h root rm -rf over \$MOUNT/workspaces)" \
  || no "T3c orphan-reaper not quiesced as a timer+service pair — a mid-freeze reap yields the same C1 abort as the AOF"
hasF 'systemctl stop luks-monitor.timer luks-monitor.service' \
  && ok "T3d luks-monitor timer AND service are stopped (a running instance holds \$MOUNT)" \
  || no "T3d luks-monitor not quiesced as a timer+service pair"

nhas '^systemctl stop .*inngest-server\.service' \
  && ok "T14 freeze_writers never stops inngest-server.service (deepen decision pinned)" \
  || no "T14 freeze_writers stops inngest-server.service — 180s TimeoutStopSec for zero quiescence benefit"

# T16 — a failed stop must abort. Unchecked, the freeze proceeds with a live writer: #6588 exactly.
run_case "$CUTOVER" 'systemctl() { rec "systemctl $*"; [ "${1:-}" = "stop" ] && return 1; return 0; }; freeze_writers' 'freeze_writers' LSOF_OUT="" LSOF_RC=1
died && ok "T16 a failed systemctl stop aborts the freeze" \
     || no "T16 a failed systemctl stop did NOT abort — the freeze proceeds with a live writer"

# T17 — an unclean stop (SIGKILL at TimeoutStopSec) must abort: `systemctl stop` still returns 0, so
# the process is gone and G4 is clean, but the AOF tail is torn and C1 would certify the corruption.
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers' LSOF_OUT="" LSOF_RC=1 STOP_RESULT="timeout"
died && ok "T17 a Result=timeout (SIGKILLed) stop aborts — byte-identity is not integrity" \
     || no "T17 an unclean stop did NOT abort — C1 would certify a byte-perfect copy of a torn AOF"

# ---------------------------------------------------------------------------
# assert_mount_quiesced — G4: fail-closed, no pipe, positive control, logs-before-die
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'freeze_writers' 'freeze_writers ensure_lsof' LSOF_ABSENT=1 LSOF_OUT="" LSOF_RC=1
died && ok "T7 G4 is fail-closed: absent+un-installable lsof aborts the freeze" \
     || no "T7 G4 silently skipped on a missing lsof — the gate evaporates exactly when needed"

# -p "$RUN_SCRATCH", NOT a trap: a `trap … EXIT` here would REPLACE workspaces-luks-harness.sh:42's `trap cleanup_scratch EXIT INT TERM HUP` and leak the whole RUN_SCRATCH tree (#6713).
BIGF="$(mktemp -p "$RUN_SCRATCH" bigf.XXXXXX)"; yes 'redis-server 1234 root  7w REG 0,42 /mnt/data/redis/appendonlydir/appendonly.aof' 2>/dev/null | head -20000 > "$BIGF"
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers' LSOF_OUT_FILE="$BIGF"
died && ok "T8 G4 still aborts on a large holder list (no pipefail/SIGPIPE fail-open)" \
     || no "T8 G4 returned success on a large holder list — the pipe fail-open is present"

# T18 — POSITIVE CONTROL. lsof exits 1 both when clean and when it errors, and writes diagnostics
# only to stderr, so "empty output" is not evidence the scan happened. A blind probe must abort.
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers assert_mount_quiesced' LSOF_BLIND=1 LSOF_OUT="" LSOF_RC=1
died && outF 'BLIND' && ok "T18 G4 aborts when lsof does not report the script own probe fd (blind, not clean)" \
                     || no "T18 a BLIND lsof scan passed G4 — 'empty output' is being read as 'mount is clean'"

# T19 — an outright probe failure (rc>1) must abort, not be swallowed by `|| true`.
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers assert_mount_quiesced' LSOF_OUT="" LSOF_RC=7
died && ok "T19 G4 aborts when the lsof probe itself fails (rc>1)" \
     || no "T19 an lsof probe failure was swallowed — the same fail-open class one layer down"

# T9 — holders logged before die. Sampled at n>1 (a single-holder fixture cannot catch a cap of 1).
MULTI=$'redis-server 1234 root 7w REG /mnt/data/redis/appendonlydir/appendonly.aof\nnode 5678 root 12w REG /mnt/data/workspaces/u1/a.ts\nbash 9012 root cwd DIR /mnt/data/workspaces/u2'
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers emit_freeze_holders' LSOF_OUT="$MULTI"
markerF 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER' \
  && ok "T9 G4 emits SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER to the Better Stack channel" \
  || no "T9 no FREEZE_HOLDER marker — a G4 abort stays undiagnosable without SSH"
emit_line="$(grep -n 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER' <<<"$CASE_OUT" | head -1 | cut -d: -f1)"
die_line="$(grep -n '^DIE:' <<<"$CASE_OUT" | head -1 | cut -d: -f1)"
if [ -n "$emit_line" ] && [ -n "$die_line" ] && [ "$emit_line" -lt "$die_line" ]; then
  ok "T9b the holder emit PRECEDES die (evidence survives the abort)"
else
  no "T9b holder emit does not precede die (emit=$emit_line die=$die_line)"
fi
# T9c — EVERY holder is named, not just the first. The count must also exclude lsof's header row
# and the script's own probe fd, or `count=` misreports and idx=0 names a column header.
n_rows=0
for p in redis-server node bash; do markerF "$p" && n_rows=$((n_rows + 1)); done
if [ "$n_rows" -eq 3 ] && markerF 'count=3'; then
  ok "T9c all 3 holders are named and count=3 (header row + own probe fd excluded)"
else
  no "T9c holder emission is incomplete or miscounted (named=$n_rows, expected count=3)"
fi

# ---------------------------------------------------------------------------
# resume_writers — mount guard, order, reconcile, degraded signal
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'resume_writers' 'resume_writers' ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
ran && ok "T4z resume_writers succeeds when everything comes back (positive control)" \
    || no "T4z resume_writers did not exit 0 on the happy path: rc=$CASE_RC"
has '^systemctl start .*inngest-redis\.service' \
  && ok "T4 resume_writers starts inngest-redis.service" \
  || no "T4 resume_writers does not start inngest-redis.service — the durable queue stays down"
has '^systemctl reset-failed .*inngest-redis\.service' \
  && ok "T4b resume_writers clears failed state before starting (a mount race leaves it 'failed')" \
  || no "T4b no reset-failed before the start — a mount-race failure silently outlives the run"

# T5b — ORDER: webhook must come back LAST. Starting it first re-exposes the CI-deploy-restarts-the-
# container race that the stop order exists to prevent. A count assertion cannot see this.
s_wh="$(idx '^systemctl start webhook\.service')"; s_rd="$(idx '^systemctl start .*inngest-redis\.service')"
if [ -n "$s_wh" ] && [ -n "$s_rd" ] && [ "$s_rd" -lt "$s_wh" ]; then
  ok "T5b resume order is the reverse of the stop order (webhook comes back LAST)"
else
  no "T5b webhook is not restored last (redis=$s_rd webhook=$s_wh) — re-exposes the CI-deploy race"
fi

# T20 — THE MOUNT GUARD. webhook.service has NO RequiresMountsFor (only ReadWritePaths=/mnt/data),
# so on a failed remount it starts SUCCESSFULLY onto the bare root-disk mountpoint dir — and it is
# the CI deploy receiver, so a deploy then writes user data to the root filesystem.
run_case "$CUTOVER" 'resume_writers' 'resume_writers' MOUNTPOINT_RC=1 ACTIVE_UNITS=""
if nhas '^systemctl start webhook\.service'; then
  ok "T20 resume_writers refuses to start writers when \$MOUNT is not mounted"
else
  no "T20 webhook started onto an UNMOUNTED \$MOUNT — a CI deploy would write to the root disk"
fi
outF 'EMIT_DRIFT: resume_without_mount' \
  && ok "T20b the refusal is reported (resume_without_mount), not silent" \
  || no "T20b resume skipped the writers silently — no drift emitted"

run_case "$CUTOVER" 'resume_writers' 'resume_writers' ACTIVE_UNITS="inngest-server.service"
nhas '^systemctl start .*inngest-server\.service' \
  && ok "T13 no redundant inngest-server start when it is already active" \
  || no "T13 redundant inngest-server start issued although it was already active"

run_case "$CUTOVER" 'resume_writers' 'resume_writers' ACTIVE_UNITS=""
has '^systemctl start .*inngest-server\.service' \
  && ok "T13b inactive inngest-server IS reconciled (started) post-freeze" \
  || no "T13b inactive inngest-server was not reconciled"
# T21 — a unit that fails to come back must produce a DURABLE signal, not just a WARN on a green run.
markerF 'SOLEUR_WORKSPACES_LUKS_RESUME_DEGRADED' \
  && ok "T21 a failed resume emits RESUME_DEGRADED to the durable channel" \
  || no "T21 a failed resume is invisible off-box — a green run with a dead queue reads as success"
# T21b — the drift reason must discriminate WHICH unit; two units share one reason otherwise.
outF 'quiesced_unit_not_active_inngest-redis' \
  && ok "T21b the drift reason names the failing unit" \
  || no "T21b undiscriminated drift reason — 'webhook down' is indistinguishable from 'queue down'"

# T5/T6 — rollback restores, and only after the remount.
run_case "$CUTOVER" 'DRY_RUN=0 rollback' 'rollback resume_writers' ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
has '^systemctl start .*inngest-redis\.service' \
  && ok "T5 rollback() restores inngest-redis.service (DP-6 leaves the host as it found it)" \
  || no "T5 rollback() does not restore inngest-redis.service"
m_i="$(idx '^mount ')"; r_i="$(idx '^systemctl start .*inngest-redis\.service')"
if [ -n "$m_i" ] && [ -n "$r_i" ] && [ "$m_i" -lt "$r_i" ]; then
  ok "T6 rollback() remounts BEFORE starting redis (RequiresMountsFor=/mnt/data)"
else
  no "T6 redis start races the remount (mount=$m_i start=$r_i)"
fi
# T6b — the dead-man must be disarmed after a rollback, else it fires DEAD_MAN_MIN later and takes a
# SECOND outage that now stops inngest-redis too.
has '^systemctl stop workspaces-luks-deadman' \
  && ok "T6b rollback() disarms the dead-man (no second, unannounced outage 30 min later)" \
  || no "T6b rollback() leaves the dead-man armed — it fires again after the host is already restored"

# T15 — stop/restore symmetry under an override.
run_case "$CUTOVER" 'freeze_writers' 'freeze_writers' LSOF_OUT="" LSOF_RC=1 WORKSPACES_QUIESCE_UNITS="inngest-redis.service"
stopped_wh=$(cnt '^systemctl stop webhook\.service')
run_case "$CUTOVER" 'resume_writers' 'resume_writers' ACTIVE_UNITS="webhook.service inngest-redis.service inngest-server.service" WORKSPACES_QUIESCE_UNITS="inngest-redis.service"
started_wh=$(cnt '^systemctl start webhook\.service')
if [ "$stopped_wh" -ge 1 ] && [ "$started_wh" -ge 1 ]; then
  ok "T15 webhook stop/restore stays symmetric even when QUIESCE_UNITS omits it"
else
  no "T15 asymmetric stop/restore (stopped=$stopped_wh started=$started_wh)"
fi

# ---------------------------------------------------------------------------
# app_canary — liveness AND mount-coupled readiness
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200
ran && ok "T10z app_canary succeeds on 200 + ready=true (positive control)" \
    || no "T10z app_canary did not pass the happy path: rc=$CASE_RC ${CASE_OUT:0:200}"
hasF 'https://app.soleur.ai/health' \
  && ok "T10 app_canary probes https app.soleur.ai/health (liveness)" \
  || no "T10 app_canary does not probe /health over https"
nhas 'app\.soleur\.ai/api/health' \
  && ok "T11 app_canary never probes /api/health (no route; 307s to /login)" \
  || no "T11 app_canary still probes /api/health — it would abort every good cutover"

# T22 — THE GATE THAT MATTERS. /health is `res.writeHead(200)` unconditionally and never touches
# $MOUNT (readiness.ts states the no-mount-coupling invariant explicitly), so it CANNOT fail on an
# empty or unmounted volume. /internal/readyz asserts workspaces_writable + workspaces_populated.
hasF '/internal/readyz' \
  && ok "T22 app_canary also asserts /internal/readyz (mount-coupled readiness)" \
  || no "T22 app_canary relies on /health alone — a 200-always probe that cannot fail on an empty \$MOUNT"
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 READYZ_BODY='{"ready":false,"checks":{"workspaces_populated":false}}'
died && ok "T22b app_canary FAILS when readyz reports ready=false (empty /workspaces)" \
     || no "T22b a cutover serving an EMPTY /workspaces was declared green"
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 READYZ_BODY=''
died && ok "T22c app_canary fails closed when readyz is unreachable" \
     || no "T22c an unreachable readyz was treated as success"

# ---------------------------------------------------------------------------
# T23/T24 — #6807 bounded, classifying canary retry.
#
# On 2026-07-20 the real cutover (run 29782780158) probed /health ~590ms after `docker start`, took
# Cloudflare's instant 521, and aborted a cutover that had in fact SUCCEEDED. `--max-time 20` was no
# defence: a 521 is a FAST response, not a hang, so the timeout budget is never consumed.
#
# Every case pins a REASON CODE via outF 'EMIT_DRIFT: <reason>' (the harness stub echoes it at
# harness:289). `died()` alone cannot distinguish a structural abort from a deadline abort — both
# exit non-zero — and the two demand opposite operator responses.
# ---------------------------------------------------------------------------

# T23a — recovers THROUGH the loop. The retry is load-bearing: without it this case is the exact
# 2026-07-20 abort. Exactly 2 sleeps, both before readyz is ever reached.
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODES="521 521 200"
if ran && [ "$(sleeps_before_readyz)" = "2" ]; then
  ok "T23a app_canary recovers through a 521,521,200 sequence with exactly 2 /health-arm sleeps"
else
  no "T23a app_canary did not recover through the boot race (rc=$CASE_RC sleeps=$(sleeps_before_readyz) want ran+2) ${CASE_OUT:0:200}"
fi

# T23b — STRUCTURAL codes fail fast. A 307 is the /api/health regression itself: retrying it would
# burn the whole budget (and, during a real cutover, dead-man margin) on an answer that will never
# change. ZERO sleeps is the assertion that proves fail-fast, not merely that it failed.
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODES="307"
if died && [ "$(sleeps_before_readyz)" = "0" ] && outF 'EMIT_DRIFT: health_probe_structural'; then
  ok "T23b a structural 307 aborts on the FIRST attempt, zero sleeps, reason health_probe_structural"
else
  no "T23b structural 307 mishandled (rc=$CASE_RC sleeps=$(sleeps_before_readyz)) ${CASE_OUT:0:200}"
fi

# T23c — an unknown/retryable code fails SAFE: it burns the full budget, then aborts with a
# DIFFERENT reason than T23b. 530 is CF 1033 ("tunnel connector not connected"), the code this stack
# most likely emits during a restart window; classifying it structural would re-create the 2026-07-20
# bug in a new coat. Sleeps == ATTEMPTS-1 (29), because the loop shape is pinned to NOT sleep after
# the final attempt — a trailing sleep buys no probe and costs a whole interval of dead-man budget.
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODES="530"
if died && [ "$(sleeps_before_readyz)" = "29" ] && outF 'EMIT_DRIFT: health_probe_deadline'; then
  ok "T23c a saturating retryable 530 burns the full bound (29 sleeps) then aborts health_probe_deadline"
else
  no "T23c retryable-unknown mishandled (rc=$CASE_RC sleeps=$(sleeps_before_readyz) want 29) ${CASE_OUT:0:200}"
fi

# T23d/T23e — THE SEAM-UNSET CASE. Every case above drives the knobs, so all of them would pass
# against a build whose PRODUCTION defaults were broken (or absent). `env -u` genuinely UNSETS the
# knobs, sealing the subshell against inherited env — run_case's `env "$@"` has no -i, so without
# this an exported knob in the operator's shell would silently rewrite the assertion.
# The expected 30 is HARDCODED on purpose: deriving it from the source would make the test agree
# with whatever the source says, which is not a test.
run_case "$CUTOVER" 'app_canary' 'app_canary' \
  -u WORKSPACES_CANARY_ATTEMPTS -u WORKSPACES_CANARY_INTERVAL_S CURL_CODES="530"
if died && [ "$(health_probe_count)" = "30" ]; then
  ok "T23d with the knobs UNSET the canary probes exactly the literal production count (30)"
else
  no "T23d production default drifted or the env seal leaked (probes=$(health_probe_count) want 30) ${CASE_OUT:0:200}"
fi
if [ "$(bad_sleep_args 3)" = "0" ] && [ "$(sleeps_before_readyz)" -gt 0 ]; then
  ok "T23e with the knobs UNSET every recorded sleep argument is the literal production interval (3)"
else
  no "T23e sleep interval drifted (non-3 args=$(bad_sleep_args 3) sleeps=$(sleeps_before_readyz))"
fi

# T23f — THE FLOOR. `:-` substitutes only for unset-or-empty, so it catches NEITHER of the two real
# silent-disable hazards: =0 makes the loop zero-iteration (a canary that cannot fail — it would
# have certified 2026-07-20 green) and a non-numeric value makes `[ abc -le n ]` error. Both must
# still probe at least once.
for bad in 0 abc; do
  run_case "$CUTOVER" 'app_canary' 'app_canary' WORKSPACES_CANARY_ATTEMPTS="$bad" CURL_CODES="530"
  # EXACTLY 1, not >=1: `>=1` is satisfied by a single-shot probe, so it would pass identically
  # against a build with no floor at all. Pinning 1 asserts the clamp actually took the value to 1
  # rather than the loop happening to run.
  if died && [ "$(health_probe_count)" = "1" ]; then
    ok "T23f WORKSPACES_CANARY_ATTEMPTS=$bad clamps to exactly 1 probe (the floor holds)"
  else
    no "T23f WORKSPACES_CANARY_ATTEMPTS=$bad produced a canary that cannot fail (probes=$(health_probe_count) want 1, rc=$CASE_RC)"
  fi
done

# T24 — readyz classification, four arms, one reason code each.
#
# The arm that matters most is the gate regression: readiness.ts:113 answers a non-loopback request
# with `403 {"error":"forbidden"}` — VALID JSON that simply is not ready:true. Classified body-first
# it lands in the not-ready arm and pages "the container is serving an EMPTY /workspaces": a
# confidently-wrong sole-copy DATA-LOSS verdict for what is really a routing bug. Status before body.
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 \
  READYZ_CODES="000 200" READYZ_BODIES='{"ready":true} {"ready":true}'
# The probe COUNT is the load-bearing half. `ran` alone passes against a single-shot probe that
# happened to get ready:true on its only attempt — it would not prove a retry occurred at all.
if ran && [ "$(readyz_probe_count)" = "2" ]; then
  ok "T24a readyz retries an unreachable first attempt and succeeds on the second (2 probes)"
else
  no "T24a readyz did not retry a transport failure (probes=$(readyz_probe_count) want 2, rc=$CASE_RC) ${CASE_OUT:0:200}"
fi

run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 \
  READYZ_BODIES='{"ready":false,"checks":{"workspaces_writable":true,"workspaces_populated":false}}'
if died && outF 'EMIT_DRIFT: readyz_not_ready'; then
  ok "T24b a saturating ready:false aborts readyz_not_ready"
else
  no "T24b ready:false mishandled (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi
# ready:false is answered with 503, not 200 (readiness.ts:119). A 503 sits in the generic RETRYABLE
# set — correct for /health, fatal here: retrying a DETERMINATE not-ready answer would burn the
# budget and report a timeout for a host that plainly said it is not ready, converting a real
# data-loss signal into a deadline. Terminal on the first answer, hence exactly one probe.
[ "$(readyz_probe_count)" = "1" ] \
  && ok "T24b2 a determinate 503 ready:false is TERMINAL — not retried into a false deadline verdict" \
  || no "T24b2 readyz retried a determinate not-ready answer (probes=$(readyz_probe_count) want 1)"

run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 \
  READYZ_CODES="200" READYZ_BODIES='<html>502-from-a-proxy</html>'
if died && outF 'EMIT_DRIFT: readyz_unparseable'; then
  ok "T24c an unparseable 200 body aborts readyz_unparseable — a proxy fault is never reported as data loss"
else
  no "T24c unparseable body mishandled (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi

run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 \
  READYZ_CODES="403" READYZ_BODIES='{"error":"forbidden"}'
if died && outF 'EMIT_DRIFT: readyz_gate_regression'; then
  ok "T24d a 403 gate regression aborts readyz_gate_regression, NOT readyz_not_ready (status before body)"
else
  no "T24d a loopback-gate regression was classified as data loss — the confidently-wrong verdict (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi

# T25 — ORDERING. app_canary must precede disarm_dead_man. CANARY_OK=1 is set by the HOST canary
# before this point, so cleanup() will not roll back; if the dead-man were disarmed FIRST, an
# app-level failure would have zero automated recovery on the one gate that proves user-facing
# health. Comments stripped first: this file discusses the ordering in prose right above the code.
#
# SCOPED TO THE MAIN BODY. rollback() also calls disarm_dead_man on its own line, and it is defined
# far ABOVE the main body — so an unscoped `head -1` picks the rollback call and compares two lines
# that have no ordering relationship, failing (or passing) for a reason unrelated to the property.
# The sourced-detection guard is the boundary between definitions and the main body.
T25BODY="$RUN_SCRATCH/t25body"
grep -vE '^[[:space:]]*#' "$CUTOVER" > "$T25BODY" || :
t25_guard=$(grep -nE 'BASH_SOURCE\[0\]:-\$0.*!=' "$T25BODY" | head -1 | cut -d: -f1 || true)
if [ -z "$t25_guard" ]; then
  no "T25 could not locate the sourced-detection guard — the main-body boundary is unfindable, so the ordering assertion would be scoped to the wrong region"
  t25_canary=""; t25_disarm=""
else
  awk -v g="$t25_guard" 'NR>g' "$T25BODY" > "$T25BODY.main"
  t25_canary=$(grep -nE '^[[:space:]]*app_canary[[:space:]]*$' "$T25BODY.main" | head -1 | cut -d: -f1 || true)
  t25_disarm=$(grep -nE '^[[:space:]]*disarm_dead_man[[:space:]]*$' "$T25BODY.main" | head -1 | cut -d: -f1 || true)
fi
if [ -n "$t25_canary" ] && [ -n "$t25_disarm" ] && [ "$t25_canary" -lt "$t25_disarm" ]; then
  ok "T25 app_canary is invoked BEFORE disarm_dead_man (the unattended backstop spans the canary)"
else
  no "T25 canary/disarm ordering wrong or unfindable (canary=$t25_canary disarm=$t25_disarm)"
fi
# T11b/T11c — the gate strength itself: exactly 200, not any 2xx.
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=307
died && ok "T11b app_canary fails closed on a 307" || no "T11b app_canary accepted a 307"
run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=204
died && ok "T11c app_canary requires exactly 200, not any 2xx" \
     || no "T11c app_canary accepted a 204 — the gate is looser than it reads"

# ---------------------------------------------------------------------------
# arm_dead_man — the unattended restore path
# ---------------------------------------------------------------------------

run_case "$CUTOVER" 'DRY_RUN=0 arm_dead_man' 'arm_dead_man'
dm="$RUN_SCRATCH/case-$CASE_N/dm"; grep -E '^systemd-run ' "$CALLS" > "$dm" 2>/dev/null || : > "$dm"
dm_missing=""
for u in webhook.service inngest-redis.service; do
  grep -qF -- "start $u" "$dm" || dm_missing="$dm_missing $u"
done
grep -qF -- "restart orphan-reaper.timer" "$dm" || dm_missing="$dm_missing orphan-reaper.timer"
[ -z "$dm_missing" ] \
  && ok "T12 the dead-man restores every quiesced unit + timer (the unattended path)" \
  || no "T12 dead-man command omits:$dm_missing"
# T12b — restores GATED on the remount. Previously `&&` bound only `docker start`, so every
# appended start ran even when mount failed — and webhook has no RequiresMountsFor.
grep -qE 'if mount [^;]*; then' "$dm" \
  && ok "T12b dead-man restores are gated on the remount succeeding" \
  || no "T12b dead-man restores are NOT mount-gated — webhook can start onto the bare mountpoint"
# T12c — derived from _quiesce_list, not hardcoded.
run_case "$CUTOVER" 'DRY_RUN=0 arm_dead_man' 'arm_dead_man' WORKSPACES_QUIESCE_UNITS="inngest-redis.service extra-writer.service"
dm2="$RUN_SCRATCH/case-$CASE_N/dm"; grep -E '^systemd-run ' "$CALLS" > "$dm2" 2>/dev/null || : > "$dm2"
grep -qF -- 'start extra-writer.service' "$dm2" \
  && ok "T12c dead-man derives its units from _quiesce_list (an override reaches the unattended path)" \
  || no "T12c dead-man hardcodes its units — an override is stopped but never restored unattended"

# ---------------------------------------------------------------------------
# cleanup() — the rollback decision. Replacing this guard with `if true` must NOT stay green: it
# would tear down a SUCCESSFUL cutover, unmounting the authoritative LUKS volume.
# ---------------------------------------------------------------------------

cleanup_case() {  # <canary_ok> <flip_done> <freeze_held> -> sets CASE_OUT/CASE_RC
  run_case "$CUTOVER" \
    "CANARY_OK=$1 FLIP_DONE=$2 FREEZE_HELD=$3 DRY_RUN=0; rollback() { echo ROLLBACK_FIRED; }; (exit 9); cleanup" \
    'cleanup rollback'
}
cleanup_case 1 1 1
outF 'ROLLBACK_FIRED' && no "T23 cleanup rolled back a canary-PASSED cutover — tears down the authoritative LUKS volume" \
                      || ok "T23 cleanup does NOT roll back once the canary passed (CANARY_OK=1)"
cleanup_case 0 0 1
outF 'ROLLBACK_FIRED' && ok "T23b cleanup DOES roll back when the freeze is held and the canary never passed" \
                      || no "T23b cleanup failed to roll back a held freeze — the host stays frozen"
cleanup_case 0 1 0
outF 'ROLLBACK_FIRED' && ok "T23c cleanup DOES roll back after the flip when the canary never passed" \
                      || no "T23c cleanup failed to roll back after a flip"
cleanup_case 0 0 0
outF 'ROLLBACK_FIRED' && no "T23d cleanup rolled back although nothing was ever frozen or flipped" \
                      || ok "T23d cleanup does nothing when neither the freeze nor the flip happened"

# ---------------------------------------------------------------------------
# Static guards (AC5 / AC7 / AC8 / AC9)
# ---------------------------------------------------------------------------
G4BODY="$RUN_SCRATCH/g4body"
awk '/^assert_mount_quiesced\(\)/,/^}/' "$CUTOVER" | grep -vE '^[[:space:]]*#' > "$G4BODY" || :
[ "$(grep -cE 'lsof.*\| *grep' "$G4BODY" || true)" -eq 0 ] \
  && ok "AC5 the G4 body contains no \`lsof … | grep\` pipe (comments stripped first)" \
  || no "AC5 a pipe is back in the G4 predicate — size-dependent SIGPIPE fail-open"
# AC7 — WIDENED to both workflows (#6807). The cutover's canary was corrected in #6701 on
# 2026-07-19, ONE DAY before the cutover, and the sweep never reached the verify workflow — which
# then sat structurally incapable of passing. A gate scoped to one file is what let that happen.
#
# The pattern is now BARE `/api/health` rather than the host-qualified form: only one of the seven
# sites in the repo carried `app.soleur.ai`, so the qualified pattern would have missed the very
# regression it exists to catch. `/api/health/team-membership` is a REAL route and is allowlisted.
#
# Comment handling differs per file, deliberately. The cutover is comment-STRIPPED, because its
# comments legitimately discuss the old endpoint to explain why it was wrong. The verify workflow is
# NOT stripped: its prose is in scope for this sweep, so a stale claim cannot outlive the assertion
# it describes. (That is why this file's own explanation above says "/api/health" while the workflow
# spells it "the API-prefixed health path".)
AC7BODY="$RUN_SCRATCH/ac7body"
grep -vE '^[[:space:]]*#' "$CUTOVER" > "$AC7BODY" || :
ac7_cut=$(grep -oE '/api/health[a-z/-]*' "$AC7BODY" | grep -vcF '/api/health/team-membership' || true)
ac7_wf=$(grep -oE '/api/health[a-z/-]*' "$VERIFY_WF" | grep -vcF '/api/health/team-membership' || true)
if [ "$ac7_cut" -eq 0 ] && [ "$ac7_wf" -eq 0 ]; then
  ok "AC7 no /api/health reference remains in the cutover script OR the verify workflow (team-membership allowlisted)"
else
  no "AC7 /api/health still referenced (cutover=$ac7_cut verify-workflow=$ac7_wf) — the #6701 sweep gap is open again"
fi
# Non-vacuity: the allowlist must not be so broad that it swallows the bare form. If this pattern
# ever stops matching, the two counts above become structurally 0 and the gate reports clean forever.
[ "$(printf '%s\n' 'x /api/health y' | grep -coE '/api/health[a-z/-]*' || true)" -eq 1 ] \
  && ok "AC7b the /api/health detector still matches a bare occurrence (gate is not vacuous)" \
  || no "AC7b the /api/health detector matches nothing — the gate above cannot fail"

# AC8 — the dead-man margin. The retry budget added by #6807 extends the window in which
# app_canary can fail WITHOUT rolling back (CANARY_OK=1 is set by the host canary before it) and
# WITHOUT reaching disarm_dead_man. On 2026-07-20 that window was 27 minutes and the timer won:
# it remounted the plaintext volume over a healthy LUKS mount and stranded 27 minutes of sole-copy
# writes (#6812). So the inequality is not decorative — it is the thing that keeps the retry from
# eating the backstop.
#
# Every operand is EXTRACTED BY SHAPE from its own source file. Hardcoding any of them would let a
# future knob change (attempts 30 -> 300) sail past a guard that still asserts the old arithmetic.
ac8_attempts=$(grep -oE 'WORKSPACES_CANARY_ATTEMPTS:-[0-9]+' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9]+$' | head -1 || true)
ac8_interval=$(grep -oE 'WORKSPACES_CANARY_INTERVAL_S:-[0-9]+' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9]+$' | head -1 || true)
ac8_maxtime=$(grep -oE '\-\-max-time [0-9]+' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9]+$' | head -1 || true)
ac8_deadman=$(grep -oE 'WORKSPACES_DEAD_MAN_MIN:-[0-9]+' "$CUTOVER" | grep -oE '[0-9]+$' | head -1 || true)
# MEASURED, not assumed: freeze/arm 22:11:49.09 -> canary 22:14:50.31 on run 29782780158.
ac8_precanary=181
if [ -n "$ac8_attempts" ] && [ -n "$ac8_interval" ] && [ -n "$ac8_maxtime" ] && [ -n "$ac8_deadman" ]; then
  # Worst case per probe: every attempt burns the full curl timeout, plus (attempts-1) intervals
  # (the loop shape does not sleep after the final attempt). TWO probes: /health and readyz.
  ac8_per=$(( ac8_attempts * ac8_maxtime + (ac8_attempts - 1) * ac8_interval ))
  ac8_total=$(( 2 * ac8_per + ac8_precanary ))
  ac8_budget=$(( ac8_deadman * 60 ))
  if [ "$ac8_total" -lt "$ac8_budget" ]; then
    ok "AC8 worst-case canary spend + measured pre-canary elapsed (${ac8_total}s) is inside DEAD_MAN_MIN (${ac8_budget}s)"
  else
    no "AC8 the retry budget can now outlive the dead-man (${ac8_total}s >= ${ac8_budget}s) — a canary failure would let the timer remount plaintext over a healthy LUKS mount (#6812)"
  fi
else
  no "AC8 could not extract every operand (attempts=$ac8_attempts interval=$ac8_interval maxtime=$ac8_maxtime deadman=$ac8_deadman) — an unextractable operand makes this guard vacuous"
fi
[ "$(grep -c 'no C1 verify' "$WORKFLOW" || true)" -ge 1 ] \
  && ok "AC9 the dry_run description states the rehearsal does not run the C1 verify" \
  || no "AC9 dry_run description still misrepresents what a rehearsal covers"
# AC9b — the COVERS clauses must be accurate too, not just the C1 disclaimer. luksFormat/luksOpen
# and the luksOpen --test-passphrase escrow PROOF are all DRY_RUN-gated, so claiming the rehearsal
# covers "LUKS target prep" or "escrow proof" is a fresh misrepresentation inside the correction.
if grep -qF 'no luksFormat/luksOpen/staging mount' "$WORKFLOW" && grep -qF 'no luksOpen --test-passphrase escrow proof' "$WORKFLOW"; then
  ok "AC9b the description names the gated LUKS-prep and escrow-proof steps as NOT covered"
else
  no "AC9b the description still implies the rehearsal exercises LUKS prep / the escrow proof"
fi

# ---------------------------------------------------------------------------
# Mutation tests — each carries the did-the-sed-land guard.
# ---------------------------------------------------------------------------
mutate() {
  # -p "$RUN_SCRATCH", NOT a trap: a `trap … EXIT` here would REPLACE workspaces-luks-harness.sh:42's `trap cleanup_scratch EXIT INT TERM HUP` and leak the whole RUN_SCRATCH tree (#6713).
  local mut; mut="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"
  cp "$CUTOVER" "$mut"
  local e; for e in "$@"; do sed -i "$e" "$mut"; done
  printf '%s\n' "$mut"
}

MUT1="$(mutate 's|^QUIESCE_UNITS=.*$|QUIESCE_UNITS="webhook.service"|')"
if ! grep -qE '^QUIESCE_UNITS="webhook\.service"$' "$MUT1"; then
  no "mutation M1 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT1" 'freeze_writers' 'freeze_writers' LSOF_OUT="" LSOF_RC=1
  nhas '^systemctl stop .*inngest-redis\.service' \
    && ok "mutation M1 (drop redis from QUIESCE_UNITS): T1 flips (the set is load-bearing)" \
    || no "mutation M1 did not flip T1"
fi
rm -f "$MUT1"

MUT2="$(mutate 's|^ *ensure_lsof$|  command -v lsof >/dev/null 2>\&1 \|\| return 0|')"
if ! grep -qE '^ *command -v lsof >/dev/null 2>&1 \|\| return 0$' "$MUT2"; then
  no "mutation M2 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT2" 'freeze_writers' 'freeze_writers' LSOF_ABSENT=1 LSOF_OUT="" LSOF_RC=1
  { [ "$CASE_RC" -eq 0 ] && ! undef; } \
    && ok "mutation M2 (restore the command -v skip): T7 flips (fail-closed is load-bearing)" \
    || no "mutation M2 did not flip T7"
fi
rm -f "$MUT2"

MUT3="$(mutate 's|^ *lsof +D "\$MOUNT" 9<&- >"\$lout" 2>"\$lerr"; rc=\$?$|  holders=""; lsof +D "$MOUNT" 2>/dev/null \| grep -q . \&\& holders=x; rc=0; : >"$lout"; : >"$lerr"; printf "COMMAND     PID USER FD   TYPE DEVICE SIZE/OFF    NODE NAME\\nbash %s root 9r DIR 0,50 40 1 %s\\n" "$$" "$wsdir" >>"$lout"|')"
if ! grep -qF 'lsof +D "$MOUNT" 2>/dev/null | grep -q . && holders=x' "$MUT3"; then
  no "mutation M3 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT3" 'freeze_writers' 'freeze_writers' LSOF_OUT_FILE="$BIGF"
  { [ "$CASE_RC" -eq 0 ] && ! undef; } \
    && ok "mutation M3 (reintroduce the pipe): T8 flips (the no-pipe form is load-bearing)" \
    || no "mutation M3 did not flip T8"
fi
rm -f "$MUT3"

MUT4="$(mutate 's|^ *emit_freeze_holders "\$holders"$|  :|')"
if grep -qF 'emit_freeze_holders "$holders"' "$MUT4"; then
  no "mutation M4 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT4" 'freeze_writers' 'freeze_writers' LSOF_OUT="$MULTI"
  markerF 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER' \
    && no "mutation M4 did not flip T9 — the emit is not load-bearing" \
    || ok "mutation M4 (drop the holder emit): T9 flips (the emit is load-bearing)"
fi
rm -f "$MUT4"

MUT5="$(mutate 's|^  for u in \$(_quiesce_list); do rev=|  for u in $QUIESCE_UNITS; do rev=|')"
if ! grep -qF 'for u in $QUIESCE_UNITS; do rev=' "$MUT5"; then
  no "mutation M5 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT5" 'resume_writers' 'resume_writers' ACTIVE_UNITS="inngest-server.service" WORKSPACES_QUIESCE_UNITS="inngest-redis.service"
  [ "$(cnt '^systemctl start webhook\.service')" -eq 0 ] \
    && ok "mutation M5 (resume off raw QUIESCE_UNITS): T15 flips (the symmetric list is load-bearing)" \
    || no "mutation M5 did not flip T15"
fi
rm -f "$MUT5"

# M6 — neuter the mount guard => T20 MUST flip (webhook starts onto an unmounted $MOUNT).
MUT6="$(mutate 's|^  if ! mountpoint -q "\$MOUNT" 2>/dev/null; then$|  if false; then|')"
if ! grep -qE '^  if false; then$' "$MUT6"; then
  no "mutation M6 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT6" 'resume_writers' 'resume_writers' MOUNTPOINT_RC=1 ACTIVE_UNITS=""
  has '^systemctl start webhook\.service' \
    && ok "mutation M6 (drop the mount guard): T20 flips (the guard is load-bearing)" \
    || no "mutation M6 did not flip T20"
fi
rm -f "$MUT6"

# M7 — neuter the cleanup rollback guard => T23 MUST flip (a passed cutover gets torn down).
MUT7="$(mutate 's|^  if \[ "\$CANARY_OK" != "1" \] && { \[ "\$FLIP_DONE" = "1" \] \|\| \[ "\$FREEZE_HELD" = "1" \]; }; then$|  if true; then|')"
if ! grep -qE '^  if true; then$' "$MUT7"; then
  no "mutation M7 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MUT7" 'CANARY_OK=1 FLIP_DONE=1 FREEZE_HELD=1 DRY_RUN=0; rollback() { echo ROLLBACK_FIRED; }; (exit 9); cleanup' 'cleanup rollback'
  outF 'ROLLBACK_FIRED' \
    && ok "mutation M7 (neuter the cleanup guard): T23 flips (the rollback decision is load-bearing)" \
    || no "mutation M7 did not flip T23 — the cleanup guard is unpinned"
fi
rm -f "$MUT7"
rm -f "$BIGF"

# ---------------------------------------------------------------------------
# Residue self-check (#6713) — re-invokes THIS suite under a PRIVATE TMPDIR and asserts it
# allocates no tempfile outside the harness's trapped scratch tree.
#
# RECURSION GUARD (mandatory): this suite has no sentinel and only `set -uo pipefail`, so a
# self-check that re-invokes the suite would recurse forever. WL_SELF_CHECK=1 is set for the inner
# run and skips this whole block. The inner run's stdout — including its OWN
# "N passed, N failed" line — is captured to a FILE, never to stdout, so the outer summary below
# stays the only summary on the wire and the outer parse cannot read the inner one as its own.
# ---------------------------------------------------------------------------
if [ "${WL_SELF_CHECK:-0}" != "1" ]; then
  SELF="$SCRIPT_DIR/workspaces-luks-freeze.test.sh"

  # R0 — POSITIVE CONTROL FOR THE PROBE. "0 residue" is only evidence if the counter can count.
  # A deliberately leaked tempfile under a private TMPDIR must register as 1. (Written with a
  # plain redirect rather than the allocator itself so the AC1 token count stays exactly 2.)
  sc_ctl="$RUN_SCRATCH/sc-control"; mkdir -p "$sc_ctl"
  TMPDIR="$sc_ctl" bash -c ': > "$TMPDIR/leaked-control.probe"' >/dev/null 2>&1
  [ "$(find "$sc_ctl" -mindepth 1 | wc -l)" -eq 1 ] \
    && ok "R0 residue probe positive control: a leaked tempfile IS counted (the probe is not blind)" \
    || no "R0 residue probe is BLIND — it did not count a deliberately leaked tempfile; R1/R2 prove nothing"

  # R1 — clean run => ZERO residue.
  sc_a="$RUN_SCRATCH/sc-clean"; mkdir -p "$sc_a"; sc_a_out="$RUN_SCRATCH/sc-clean.out"
  env TMPDIR="$sc_a" WL_SELF_CHECK=1 bash "$SELF" >"$sc_a_out" 2>&1
  sc_a_rc=$?
  sc_a_res="$(find "$sc_a" -mindepth 1 | wc -l)"
  if [ "$sc_a_rc" -ne 0 ] || ! grep -qE '[0-9]+ passed, 0 failed' "$sc_a_out"; then
    no "R1 the inner suite did not complete cleanly (rc=$sc_a_rc) — the residue result is not evidence, treat as UN-RUN"
  elif [ "$sc_a_res" -eq 0 ]; then
    ok "R1 a clean run under a private TMPDIR leaves ZERO residue"
  else
    no "R1 a clean run leaked $sc_a_res path(s) into TMPDIR: $(find "$sc_a" -mindepth 1 -printf '%f ' 2>/dev/null || true)"
  fi

  # R2 — forced mid-suite abort inside a >=2-tempfile window => ZERO residue outside the tree.
  sc_b="$RUN_SCRATCH/sc-term"; mkdir -p "$sc_b"; sc_b_out="$RUN_SCRATCH/sc-term.out"
  env TMPDIR="$sc_b" WL_SELF_CHECK=1 bash "$SELF" >"$sc_b_out" 2>&1 &
  sc_pid=$!

  # SYNCHRONIZE ON FILE EXISTENCE, NEVER ON ELAPSED TIME. mutate() returns immediately and each
  # MUT file lives only until its `rm -f` a few lines later; a fixed `sleep N; kill` lands outside
  # that window on a loaded runner and this case then PASSES FOR THE WRONG REASON (nothing was
  # live, so nothing could leak). SECONDS below is a failure CEILING only, never the trigger.
  # The poll globs in-process: a `find` fork per iteration is slow enough to miss the window
  # outright (measured). `*.sh` matches BOTH the fixed form (mut.XXXXXX.sh, depth 2 inside the
  # scratch tree) and the pre-fix form (tmp.XXXXXXXXXX.sh, depth 1 in TMPDIR), so a regression
  # cannot make the poll silently blind and report a vacuous pass.
  shopt -s nullglob
  sc_win=""; sc_deadline=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$sc_deadline" ]; do
    sc_glob=( "$sc_b"/*.sh "$sc_b"/*/*.sh )
    if [ "${#sc_glob[@]}" -gt 0 ]; then sc_win="${sc_glob[0]}"; break; fi
    kill -0 "$sc_pid" 2>/dev/null || break
  done
  # The >=2-tempfile requirement, verified AT the window rather than assumed: BIGF is ~1.6 MB and
  # is the only file this suite writes above 1 MB. A single-tempfile probe cannot discriminate the
  # trap-replacement class, so "no second file live" is reported as UN-RUN, never as a pass.
  sc_big="$(find "$sc_b" -type f -size +1M -print -quit 2>/dev/null || true)"

  kill -TERM "$sc_pid" 2>/dev/null || true
  # WHY A SIGKILL FOLLOWS THE SIGTERM: cleanup_scratch (workspaces-luks-harness.sh:41) does NOT
  # exit — bash runs the TERM handler and RESUMES — so a bare SIGTERM lets the suite run on to its
  # tail `rm -f` lines, which would scrub the stray files and mask the very leak this case exists
  # to detect (measured: bare SIGTERM => rc 0, 0 residue, even on the unfixed code). So: wait for
  # the trap to have removed the scratch tree (state, not elapsed time), then SIGKILL so the tail
  # `rm -f` can never run. What survives is then exactly "allocated OUTSIDE the trapped tree".
  sc_deadline=$((SECONDS + 60))
  while [ "$SECONDS" -lt "$sc_deadline" ]; do
    sc_tree=( "$sc_b"/wl-harness.* )
    [ "${#sc_tree[@]}" -eq 0 ] && break
    kill -0 "$sc_pid" 2>/dev/null || break
  done
  kill -KILL "$sc_pid" 2>/dev/null || true
  wait "$sc_pid" 2>/dev/null
  shopt -u nullglob

  # Residue that matters = depth-1 entries that are NOT the scratch tree. A run_case after the
  # trap fired can RE-create wl-harness.*, and because we deliberately SIGKILLed, that tree's own
  # EXIT-trap removal never runs — expected by construction, and not the #6713 defect.
  sc_stray() { find "$sc_b" -mindepth 1 -maxdepth 1 -not -name 'wl-harness.*' "$@" 2>/dev/null || true; }
  sc_b_res="$(sc_stray | wc -l)"
  if [ -z "$sc_win" ]; then
    no "R2 the mutation-block tempfile window never opened — the abort was not inside it; treat as UN-RUN, not evidence"
  elif [ -z "$sc_big" ]; then
    no "R2 only ONE tempfile was live at the abort (no >1M BIGF) — a single-tempfile probe cannot detect the trap-replacement class; treat as UN-RUN"
  elif [ "$sc_b_res" -eq 0 ]; then
    ok "R2 a forced mid-suite abort in a >=2-tempfile window leaves ZERO tempfiles outside the trapped scratch tree"
  else
    no "R2 mid-suite abort LEAKED $sc_b_res path(s) outside the harness scratch tree: $(sc_stray -printf '%f ') — an allocation is missing -p \"\$RUN_SCRATCH\""
  fi
fi

# ---------------------------------------------------------------------------
echo
echo "workspaces-luks-freeze.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
