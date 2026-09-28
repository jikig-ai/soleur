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
has '^docker stop -t 120 ' && ok "T2b the container drain keeps its 120s C8 timeout" \
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
has '^systemctl stop orphan-reaper\.timer orphan-reaper\.service' \
  && ok "T3c orphan-reaper timer AND service are stopped (6h root rm -rf over \$MOUNT/workspaces)" \
  || no "T3c orphan-reaper not quiesced as a timer+service pair — a mid-freeze reap yields the same C1 abort as the AOF"
has '^systemctl stop luks-monitor\.timer luks-monitor\.service' \
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
emit_line="$(grep -n 'SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER' <<<"$CASE_OUT" | sed -n '1p' | cut -d: -f1)"
die_line="$(grep -n '^DIE:' <<<"$CASE_OUT" | sed -n '1p' | cut -d: -f1)"
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
has '^curl .*https://app\.soleur\.ai/health' \
  && ok "T10 app_canary probes https app.soleur.ai/health (liveness)" \
  || no "T10 app_canary does not probe /health over https"
nhas '^(curl|docker) .*app\.soleur\.ai/api/health' \
  && ok "T11 app_canary never probes /api/health (no route; 307s to /login)" \
  || no "T11 app_canary still probes /api/health — it would abort every good cutover"

# T22 — THE GATE THAT MATTERS. /health is `res.writeHead(200)` unconditionally and never touches
# $MOUNT (readiness.ts states the no-mount-coupling invariant explicitly), so it CANNOT fail on an
# empty or unmounted volume. /internal/readyz asserts workspaces_writable + workspaces_populated.
has '^curl .*/internal/readyz' \
  && ok "T22 app_canary also asserts /internal/readyz (mount-coupled readiness)" \
  || no "T22 app_canary relies on /health alone — a 200-always probe that cannot fail on an empty \$MOUNT"
# T22d — the readyz probe runs INSIDE the container (docker exec), not a bare host curl. A host-side
# curl of the bridge-published port reaches the app with the docker bridge gateway as its peer → 403
# (readyz_gate_regression) → app_canary can never pass. Anchor on the FULL transport, per
# cq-assert-anchor-not-bare-token: a silent revert to a bare host curl (which still probes readyz and
# would satisfy T22) must red HERE. The container literal `soleur-web-platform` is asserted
# DELIBERATELY (not wildcarded) — it locks that the probe targets the RIGHT container and reds on an
# incomplete rename. SIBLING: luks-monitor.test.sh (n2) covers the OTHER consumer (daily monitor)
# through the OTHER docker stub (the $d/bin/docker PATH-stub form).
has '^docker exec soleur-web-platform curl ' \
  && ok "T22d app_canary probes readyz via docker exec into the container (genuine-loopback peer, not the bridge gateway)" \
  || no "T22d app_canary readyz probe is a bare host curl — in prod the bridge-gateway peer gets 403 and the cutover can never certify"
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

# T24e — the gate-regression set is {307,401,403,404,405} and only 403 was ever a fixture. Dropping
# 404|405 (or 307|401) from wl_probe_readyz reclassifies them as data-loss/unreachable and SURVIVES
# a 403-only suite. Iterate EVERY member so the set is proven, not sampled. (503 is NOT here — it is
# the determinate not-ready status; 200 is success.)
for gr in 307 401 404 405; do
  run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODE=200 \
    READYZ_CODES="$gr" READYZ_BODIES='{"error":"blocked"}'
  if died && outF 'EMIT_DRIFT: readyz_gate_regression'; then
    ok "T24e readyz $gr => readyz_gate_regression (structural, never data-loss)"
  else
    no "T24e readyz $gr misclassified — a de-routed readyz would page data-loss or burn the budget (rc=$CASE_RC) ${CASE_OUT:0:200}"
  fi
done

# T23g — the /health STRUCTURAL set is {307,401,403,404,405,525,526} and only 307 was ever a fixture.
# Dropping 525|526 reclassifies them retryable → a determinate CF-edge structural fault burns the
# full ~237s budget (and dead-man margin) instead of failing fast. Iterate every member.
for st in 401 403 404 405 525 526; do
  run_case "$CUTOVER" 'app_canary' 'app_canary' CURL_CODES="$st"
  if died && [ "$(sleeps_before_readyz)" = "0" ] && outF 'EMIT_DRIFT: health_probe_structural'; then
    ok "T23g /health $st fails fast (structural, zero sleeps)"
  else
    no "T23g /health $st is not fail-fast structural (sleeps=$(sleeps_before_readyz) rc=$CASE_RC) — budget-burn on a determinate fault ${CASE_OUT:0:160}"
  fi
done

# T23h — the INTERVAL floor's untested twin. T23e only asserts the DEFAULT 3; nothing pins the
# `-ge 0` clamp on a bad interval, so removing it survives. A negative/non-numeric interval must
# fall back to 3, not to `sleep -1` (error) or `sleep abc` (error → hot loop under a real sleep).
for badint in -1 abc; do
  run_case "$CUTOVER" 'app_canary' 'app_canary' \
    WORKSPACES_CANARY_INTERVAL_S="$badint" CURL_CODES="530"
  if died && [ "$(bad_sleep_args 3)" = "0" ] && [ "$(sleeps_before_readyz)" -gt 0 ]; then
    ok "T23h WORKSPACES_CANARY_INTERVAL_S=$badint clamps to the literal 3 (interval floor holds)"
  else
    no "T23h bad interval $badint was not clamped (non-3 args=$(bad_sleep_args 3) sleeps=$(sleeps_before_readyz))"
  fi
done

# T25' — PLACEMENT, INVERTED BY #9045. The dead-man guards the FREEZE WINDOW, not app health: it is
# disarmed exactly once in the main body, at the host-canary door — AFTER the last host-canary
# assert (`not_mounted`) and BEFORE both `CANARY_OK=1` and `docker start "$CONTAINER"`. Before
# #9045 it stayed armed across app_canary, and on 2026-07-20 an app-level abort let it fire 27
# minutes later and silently remount the plaintext over a correct LUKS mount (#6812). ADR-119 §(b):
# "The rollback door closes at `docker start`" — so nothing unattended may stay armed past it.
# Moving CANARY_OK=1 above the disarm is also RED: a failed disarm would then skip the rollback.
#
# SCOPED TO THE MAIN BODY. rollback() and cleanup() also call disarm_dead_man, and they are defined
# far ABOVE the main body; an unscoped search would compare lines that have no ordering
# relationship. The sourced-detection guard is the boundary between definitions and the main body.
# Comments are stripped first: this file discusses the ordering in prose right above the code.
T25BODY="$RUN_SCRATCH/t25body"
grep -vE '^[[:space:]]*#' "$CUTOVER" > "$T25BODY" || :
t25_guard=$(grep -nE 'BASH_SOURCE\[0\]:-\$0.*!=' "$T25BODY" | sed -n '1p' | cut -d: -f1 || true)
t25_nm=""; t25_disarm=""; t25_cok=""; t25_dstart=""; t25_ndisarm=0
if [ -z "$t25_guard" ]; then
  no "T25' could not locate the sourced-detection guard — the main-body boundary is unfindable, so the placement assertion would be scoped to the wrong region"
  : > "$T25BODY.main"
else
  awk -v g="$t25_guard" 'NR>g' "$T25BODY" > "$T25BODY.main"
  t25_nm=$(grep -nE '^[[:space:]]*mountpoint -q "\$MOUNT" \|\| \{ emit_drift not_mounted;' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  # A trailing `|| die …` or comment and any indentation are tolerated (Guard 2 harness row H2).
  t25_disarm=$(grep -nE '^[[:space:]]*disarm_dead_man[[:space:]]+host_canary_passed([[:space:]]|$)' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  t25_cok=$(grep -nE '^[[:space:]]*CANARY_OK=1' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  t25_dstart=$(grep -nE '^[[:space:]]*docker start "\$CONTAINER"' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  t25_ndisarm=$(grep -cE '(^|[;&|{[:space:]])disarm_dead_man([[:space:]]|;|$)' "$T25BODY.main" || true)
fi
if [ -z "$t25_disarm" ]; then
  # Never a pass on an empty extraction: a renamed or deleted call must read as NOT FOUND.
  no "T25' disarm_dead_man host_canary_passed not found in the main body (renamed, deleted, or reason changed) — the single disarm point is unproven"
elif [ -n "$t25_nm" ] && [ -n "$t25_cok" ] && [ -n "$t25_dstart" ] \
  && [ "$t25_nm" -lt "$t25_disarm" ] && [ "$t25_disarm" -lt "$t25_cok" ] && [ "$t25_disarm" -lt "$t25_dstart" ] \
  && [ "$t25_ndisarm" -eq 1 ]; then
  ok "T25' the main body disarms EXACTLY once, after the not_mounted host-canary assert and before CANARY_OK=1 and docker start"
else
  no "T25' disarm placement wrong (not_mounted=$t25_nm disarm=$t25_disarm CANARY_OK=$t25_cok docker_start=$t25_dstart main-body disarms=$t25_ndisarm; want not_mounted<disarm<CANARY_OK, disarm<docker_start, exactly 1)"
fi
# T25b' — PLACEMENT is not EXECUTION. The ordering grep passes even when a call is neutered behind an
# extra conditional (the 2026-07-20 failure class). The disarm is an UNCONDITIONAL sibling of
# `CANARY_OK=1` inside the host-canary `if [ "$DRY_RUN" != "1" ]` block, and app_canary is an
# unconditional sibling of resume_writers inside the docker-start block: each pair's leading
# whitespace must be EQUAL, and neither call may appear nested deeper anywhere in the main body.
t25_ws() {  # <ERE for the own-line call> -> the exact indent of its first main-body occurrence
  grep -E "$1" "$T25BODY.main" 2>/dev/null | sed -n '1p' | sed -E 's/^([[:space:]]*).*/\1/' | cat -A | sed 's/\$$//'
}
t25b_disarm_ws="$(t25_ws '^[[:space:]]*disarm_dead_man[[:space:]]+host_canary_passed([[:space:]]|$)')"
t25b_cok_ws="$(t25_ws '^[[:space:]]*CANARY_OK=1')"
t25b_canary_ws="$(t25_ws '^[[:space:]]*app_canary[[:space:]]*$')"
t25b_resume_ws="$(t25_ws '^[[:space:]]*resume_writers[[:space:]]*$')"
t25b_deeper="$(awk -v a="$t25b_canary_ws" -v d="$t25b_disarm_ws" '
  /^[[:space:]]*app_canary[[:space:]]*$/ { match($0,/^[[:space:]]*/); if (RLENGTH > length(a)) n++ }
  /^[[:space:]]*disarm_dead_man[[:space:]]/ { match($0,/^[[:space:]]*/); if (RLENGTH > length(d)) n++ }
  END { print n+0 }' "$T25BODY.main" 2>/dev/null)"
if [ -n "$t25b_disarm_ws" ] && [ "$t25b_disarm_ws" = "$t25b_cok_ws" ] \
  && [ -n "$t25b_canary_ws" ] && [ "$t25b_canary_ws" = "$t25b_resume_ws" ] && [ "${t25b_deeper:-0}" -eq 0 ]; then
  ok "T25b' the disarm is an UNCONDITIONAL sibling of CANARY_OK=1 and app_canary of resume_writers (never nested deeper) — a neutered call is caught, not just a moved one"
else
  no "T25b' indent mismatch (disarm=[$t25b_disarm_ws] CANARY_OK=[$t25b_cok_ws] app_canary=[$t25b_canary_ws] resume_writers=[$t25b_resume_ws] deeper=$t25b_deeper) — a call may be gated behind an extra conditional"
fi
# T25c — NEGATIVE SENTINEL: no disarm_dead_man anywhere in the main body after `docker start`. A
# SECOND disarm kept "for safety" after the app canary is exactly the pre-#9045 shape, and T25'
# (first occurrence) cannot see it. The detector carries its own positive control on synthesized
# bodies, so a detector that can never fire (say, one pointed at the wrong region) cannot pass.
t25c_after() {  # <file> -> count of disarm_dead_man command lines after the first docker start "$CONTAINER"
  awk '/^[[:space:]]*docker start "\$CONTAINER"/ { seen=1; next }
       seen && /(^|[;&|{[:space:]])disarm_dead_man([[:space:]]|;|$)/ { n++ }
       END { print n+0 }' "$1"
}
printf '%s\n' '  disarm_dead_man host_canary_passed || die "x"' '  CANARY_OK=1' '  docker start "$CONTAINER"' '  app_canary' > "$T25BODY.ctl-ok"
printf '%s\n' '  disarm_dead_man host_canary_passed || die "x"' '  CANARY_OK=1' '  docker start "$CONTAINER"' '  app_canary' '  disarm_dead_man host_canary_passed' > "$T25BODY.ctl-bad"
t25c_real="$(t25c_after "$T25BODY.main")"; t25c_ok="$(t25c_after "$T25BODY.ctl-ok")"; t25c_bad="$(t25c_after "$T25BODY.ctl-bad")"
if [ -n "$t25_dstart" ] && [ "$t25c_real" -eq 0 ] && [ "$t25c_ok" -eq 0 ] && [ "$t25c_bad" -eq 1 ]; then
  ok "T25c no disarm_dead_man follows docker start in the main body (detector control: compliant=0, planted second disarm=1)"
else
  no "T25c post-docker-start disarm check failed (docker_start=$t25_dstart real=$t25c_real control-ok=$t25c_ok control-bad=$t25c_bad; want real=0 ok=0 bad=1)"
fi
# T25d — the ARM precedes the freeze flag, on SEPARATE lines. `arm_dead_man` fails closed now (it
# dies on a refused or unverified arm), so it must run before FREEZE_HELD=1: a refused arm then
# aborts with nothing frozen and nothing to roll back. A same-line pair is refused outright,
# because a line-number comparison cannot order two statements on one line.
t25d_arm=$(grep -nE '^[[:space:]]*arm_dead_man[[:space:]]*$' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
t25d_frz=$(grep -nE '^[[:space:]]*FREEZE_HELD=1' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
t25d_same=$(grep -cE 'arm_dead_man.*FREEZE_HELD=1|FREEZE_HELD=1.*arm_dead_man' "$T25BODY.main" || true)
if [ -n "$t25d_arm" ] && [ -n "$t25d_frz" ] && [ "$t25d_arm" -lt "$t25d_frz" ] && [ "$t25d_same" -eq 0 ]; then
  ok "T25d arm_dead_man runs on its own line BEFORE FREEZE_HELD=1 (a refused arm aborts with nothing frozen)"
else
  no "T25d arm/freeze order wrong (arm=$t25d_arm FREEZE_HELD=1=$t25d_frz same-line=$t25d_same; want arm<freeze on separate lines)"
fi
# T36c — the GC-PROOF re-assert. A fire unmounts $MOUNT, and garbage collection can erase every
# property disarm_dead_man reads, but it cannot hide a changed mount source. So between the host-
# canary disarm and CANARY_OK=1 there must be a `findmnt -no SOURCE "$MOUNT"` compared against
# $MAPPER. Searched ONLY inside that window: the earlier canary findmnt sits outside it.
t36c_n=0
if [ -n "$t25_disarm" ] && [ -n "$t25_cok" ] && [ "$t25_disarm" -lt "$t25_cok" ]; then
  t36c_n=$(awk -v a="$t25_disarm" -v b="$t25_cok" 'NR>a && NR<b && /findmnt -no SOURCE "\$MOUNT"/ && /\$MAPPER/ && /deadman_fired_before_disarm/ { n++ } END { print n+0 }' "$T25BODY.main")
fi
[ "$t36c_n" -ge 1 ] \
  && ok "T36c a findmnt SOURCE == \$MAPPER re-assert (deadman_fired_before_disarm) sits between the host-canary disarm and CANARY_OK=1" \
  || no "T36c no GC-proof findmnt re-assert between the disarm (line $t25_disarm) and CANARY_OK=1 (line $t25_cok) — a fire that raced the disarm would be certified"
# T40b — the population assert runs INSIDE the door: after not_mounted, before the disarm.
t40_pop=$(grep -nE '^[[:space:]]*assert_host_canary_population[[:space:]]*$' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
if [ -n "$t40_pop" ] && [ -n "$t25_nm" ] && [ -n "$t25_disarm" ] && [ "$t25_nm" -lt "$t40_pop" ] && [ "$t40_pop" -lt "$t25_disarm" ]; then
  ok "T40b the host-canary population assert runs after not_mounted and before the disarm (rollback is still lossless when it fails)"
else
  no "T40b population assert missing or misplaced (not_mounted=$t25_nm population=$t40_pop disarm=$t25_disarm)"
fi
# T39 — the arm is NOT swallowed. Over un-commented LOGICAL lines (backslash continuations folded)
# there is exactly ONE `systemd-run --on-active` command, and it carries no `|| true`. A bare
# `grep -c` is wrong here: comments name the command too, and the command spans many physical
# lines. The 2026-07-23 arm was refused ("already loaded") into /dev/null and `|| true`, and
# `result=armed` was logged anyway (#9045 H1).
t39_logical=$(awk '{ if (buf != "") buf = buf " " $0; else buf = $0
       if (buf ~ /\\$/) { sub(/\\$/, "", buf); next }
       print buf; buf = "" }
     END { if (buf != "") print buf }' "$T25BODY")
t39_n=$(grep -cE 'systemd-run[[:space:]]+--on-active' <<<"$t39_logical" || true)
t39_swallow=$(awk '/systemd-run[[:space:]]+--on-active/ && index($0, "|| true") { n++ } END { print n+0 }' <<<"$t39_logical")
if [ "$t39_n" -eq 1 ] && [ "$t39_swallow" -eq 0 ]; then
  ok "T39 exactly one systemd-run --on-active logical command, with no || true swallow"
else
  no "T39 systemd-run --on-active logical commands=$t39_n (want 1), swallowed=$t39_swallow (want 0)"
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
# #9045 — HARNESS SELF-TEST for the dead-man unit model. Every T30-T38 verdict below reads this
# stub, so the stub is proven first: a `systemctl show` fake that ignored its unit operand would
# answer the SERVICE with the timer's `waiting`, and the arm/disarm rows would then pass or fail
# for a reason unrelated to the code under test.
# ---------------------------------------------------------------------------
run_case "$CUTOVER" \
  'systemctl show workspaces-luks-deadman.service -p SubState --value; systemctl show -p SubState --value workspaces-luks-deadman.timer' \
  '' DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting
if [ "$CASE_OUT" = $'dead\nwaiting' ]; then
  ok "HS1 the systemctl show stub is keyed on the UNIT (service SubState is not the timer's waiting; unit read in any argv position)"
else
  no "HS1 the systemctl show stub is not unit-keyed — got [$(tr '\n' '|' <<<"$CASE_OUT")], want [dead|waiting]"
fi
# HS2 — last event wins: a stop collects a loaded unit, a second stop exits 5 (not loaded), a later
# systemd-run revives it, and an unset knob then answers the real just-armed shape (waiting).
run_case "$CUTOVER" \
  'systemctl stop workspaces-luks-deadman.timer; echo "rc1=$?"; systemctl show workspaces-luks-deadman.timer -p LoadState --value; systemctl stop workspaces-luks-deadman.timer; echo "rc2=$?"; systemd-run --on-active=1min --unit=workspaces-luks-deadman /bin/true; systemctl show workspaces-luks-deadman.timer -p SubState --value; systemctl show workspaces-luks-deadman.timer -p LastTriggerUSec' \
  '' DEADMAN_LOADED="timer"
if [ "$CASE_OUT" = $'rc1=0\nnot-found\nrc2=5\nwaiting\nLastTriggerUSec=' ]; then
  ok "HS2 the GC model: stop collects (not-found), a second stop exits 5, systemd-run revives (waiting), no --value prints Prop="
else
  no "HS2 the dead-man GC model is wrong — got [$(tr '\n' '|' <<<"$CASE_OUT")]"
fi

# ---------------------------------------------------------------------------
# #9045 — the dead-man ARM is verified, and fails closed. Every invocation sets DRY_RUN=0 inline:
# the script defaults DRY_RUN=1, arm_dead_man/rollback return early under it, and sourcing resets
# every global, so a flag set outside the invocation string would never reach the code.
# Markers are asserted on the full SOLEUR_WORKSPACES_LUKS_DEADMAN prefix, drift as `EMIT_DRIFT <r>`.
# ---------------------------------------------------------------------------
DM='SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman'
# The script's OWN mapper path, read from the script rather than hardcoded (T37/T38 compare to it).
T_MAPPER="$(env -u WORKSPACES_MAPPER_NAME bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$MAPPER"' _ "$CUTOVER")"
[ -n "$T_MAPPER" ] || no "T_MAPPER could not be read from the script — T37/T38 would compare against an empty mapper"
# drift_last — the LAST drift recorded (rollback_engaged is rollback()'s last line).
drift_last() { awk '/^EMIT_DRIFT /{l=$2} END{print l}' "$CALLS"; }
# reads_before_umount <ERE> — how many recorded calls match <ERE> before the first ^umount.
reads_before_umount() { RB_RE="$1" awk '/^umount[[:space:]]/{exit} $0 ~ ENVIRON["RB_RE"] {n++} END{print n+0}' "$CALLS"; }
DM_SVC_READ='^systemctl show workspaces-luks-deadman\.service -p ActiveState --value$'

# T30 — the happy path, from a FRESH host (both units not-found, so the pre-clear stop exits 5 and
# must be tolerated). Pre-clear strictly BEFORE systemd-run; --description= set (the journal must
# not echo the command line); the unchanged armed marker; DEADMAN_ARMED=1.
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man; r=$?; echo "ARMED=$DEADMAN_ARMED"; exit $r' 'arm_dead_man' \
  DEADMAN_TIMER_SUBSTATES=waiting
t30_stop="$(idx '^systemctl stop workspaces-luks-deadman\.timer')"
t30_rft="$(idx '^systemctl reset-failed .*workspaces-luks-deadman\.timer')"
t30_rfs="$(idx '^systemctl reset-failed .*workspaces-luks-deadman\.service')"
t30_run="$(idx '^systemd-run ')"
if ran && outF 'ARMED=1' && [ -n "$t30_stop" ] && [ -n "$t30_rft" ] && [ -n "$t30_rfs" ] && [ -n "$t30_run" ] \
  && [ "$t30_stop" -lt "$t30_run" ] && [ "$t30_rft" -lt "$t30_run" ] && [ "$t30_rfs" -lt "$t30_run" ] \
  && has '^systemd-run .*--description=' && markerF "$DM result=armed reason=freeze_engaged deadline_min=30"; then
  ok "T30 arm: stale units cleared (stop tolerates exit 5, reset-failed both) BEFORE systemd-run --description=, verified waiting, result=armed"
else
  no "T30 arm happy path wrong (rc=$CASE_RC stop=$t30_stop rf.timer=$t30_rft rf.service=$t30_rfs run=$t30_run) ${CASE_OUT:0:240}"
fi
# T30b — Guard 1 harness row H2 (must PASS, non-canonical): waiting only on the SECOND verify read.
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man' 'arm_dead_man' DEADMAN_TIMER_SUBSTATES="dead waiting"
if ran && markerF "$DM result=armed reason=freeze_engaged" && [ "$(cnt '^sleep 1$')" -eq 1 ]; then
  ok "T30b a timer that reads waiting on the second poll arms (exactly one 1s poll interval)"
else
  no "T30b a late-waiting timer did not arm cleanly (rc=$CASE_RC sleeps=$(cnt '^sleep 1$')) ${CASE_OUT:0:200}"
fi
# T31 — systemd-run REFUSES (the H1 shape: a loaded failed unit). Fails closed: died, arm_failed with
# the named reason, drift deadman_arm_failed, and NO result=armed. The refusal text is captured,
# not discarded.
T31_ERR="Failed to start transient timer unit: Unit workspaces-luks-deadman.service was already loaded or has a fragment file. result=armed $(printf 'x%.0s' $(seq 1 300))"$'\n''second-line-must-not-appear'
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man' 'arm_dead_man' SYSTEMD_RUN_RC=1 SYSTEMD_RUN_OUT="$T31_ERR"
if died && markerF "$DM result=arm_failed reason=systemd_run_refused" && ! markerF 'result=armed' \
  && has '^EMIT_DRIFT deadman_arm_failed$' && outF 'DIE:'; then
  ok "T31 a refused systemd-run dies with result=arm_failed reason=systemd_run_refused + deadman_arm_failed, never result=armed"
else
  no "T31 a refused arm was not fail-closed (rc=$CASE_RC) — the 2026-07-23 swallow: ${CASE_OUT:0:240}"
fi
# T31b — detail= is SCRUBBED and LAST: first line only, <=200 chars, every `=` mapped to `_` (so the
# refusal text `result=armed` cannot spoof a marker field), and it never reaches the Sentry reason.
t31_detail="$(grep -oE 'reason=systemd_run_refused .*$' "$MARKER_LOG" | sed -n '1p')"
t31_rest="${t31_detail##* detail=}"
if [[ "$t31_detail" == *" detail="* ]] && [[ "$t31_rest" == *"already loaded"* ]] && [[ "$t31_rest" != *"="* ]] \
  && [[ "$t31_rest" != *"second-line"* ]] && [ "${#t31_rest}" -le 200 ] && [[ "$t31_rest" == *"result_armed"* ]] \
  && [ "$(cnt '^EMIT_DRIFT ')" -eq 1 ] && has '^EMIT_DRIFT deadman_arm_failed$'; then
  ok "T31b detail= is last, first-line, <=200 chars, =-scrubbed (result=armed -> result_armed), and absent from the drift reason"
else
  no "T31b detail scrub wrong (len=${#t31_rest}) [${t31_detail:0:260}]"
fi
# T32 — systemd-run returns 0 but the timer NEVER reads waiting: the bounded attempt-counted poll
# (5 reads, 4 x `sleep 1`) runs out, then it dies timer_not_waiting. No result=armed.
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man' 'arm_dead_man' DEADMAN_TIMER_SUBSTATES=dead
if died && markerF "$DM result=arm_failed reason=timer_not_waiting substate=dead" && ! markerF 'result=armed' \
  && has '^EMIT_DRIFT deadman_arm_failed$' && [ "$(cnt '^sleep 1$')" -eq 4 ]; then
  ok "T32 an unverified arm dies timer_not_waiting after exactly 5 attempt-counted polls, never result=armed"
else
  no "T32 unverified arm mishandled (rc=$CASE_RC sleeps=$(cnt '^sleep 1$')) ${CASE_OUT:0:240}"
fi
# T32b — DEADMAN_ARMED=1 is set the moment systemd-run returns 0, BEFORE the verification, so the
# cleanup() that a timer_not_waiting die reaches disarms the timer this run created. Nothing is
# frozen yet, so the outcome is arm_aborted.
run_case "$CUTOVER" 'trap cleanup EXIT; DRY_RUN=0; arm_dead_man' 'arm_dead_man cleanup disarm_dead_man' DEADMAN_TIMER_SUBSTATES=dead
if died && { markerF "$DM result=disarmed reason=arm_aborted" || markerF "$DM result=disarm_failed reason=arm_aborted"; } \
  && markerF "$DM result=cutover_aborted outcome=arm_aborted"; then
  ok "T32b a failed arm verification still reaches the disarm in cleanup (disarm reason=arm_aborted, outcome=arm_aborted)"
else
  no "T32b the timer this run created outlives a failed arm — no arm_aborted disarm/outcome (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T33 — a LIVE dead-man is never stopped by an arm: a waiting timer belongs to an earlier run's freeze,
# and a running service is a fire in progress. Refuse, and record neither a stop nor a systemd-run.
for t33 in "already_armed DEADMAN_TIMER_SUBSTATES=waiting" "fire_in_progress DEADMAN_SVC_ACTIVESTATES=activating"; do
  t33_reason="${t33%% *}"; t33_knob="${t33#* }"
  run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man' 'arm_dead_man' DEADMAN_LOADED="timer service" "$t33_knob"
  if died && markerF "$DM result=arm_refused reason=$t33_reason" && has '^EMIT_DRIFT deadman_already_armed$' \
    && nhas '^systemctl stop workspaces-luks-deadman' && nhas '^systemd-run '; then
    ok "T33 arm refuses a live dead-man ($t33_reason): no stop, no systemd-run, drift deadman_already_armed"
  else
    no "T33 arm did not refuse a live dead-man ($t33_reason, rc=$CASE_RC) ${CASE_OUT:0:240}"
  fi
done

# ---------------------------------------------------------------------------
# #9045 — the DISARM verifies itself, returns a status, and never dies.
# ---------------------------------------------------------------------------
# T36 — success: the four steps in race-free order — (a) LastTriggerUSec BEFORE the stop, the stop,
# (b) the service ActiveState AFTER the stop, then reset-failed — rc 0 and DEADMAN_ARMED=0.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; disarm_dead_man host_canary_passed; r=$?; echo "ARMED_AFTER=$DEADMAN_ARMED"; exit $r' \
  'disarm_dead_man' DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting
t36_a="$(idx '^systemctl show workspaces-luks-deadman\.timer -p LastTriggerUSec --value$')"
t36_s="$(idx '^systemctl stop workspaces-luks-deadman\.timer')"
t36_b="$(idx "$DM_SVC_READ")"
t36_r="$(idx '^systemctl reset-failed ')"
if ran && outF 'ARMED_AFTER=0' && markerF "$DM result=disarmed reason=host_canary_passed" \
  && [ -n "$t36_a" ] && [ -n "$t36_s" ] && [ -n "$t36_b" ] && [ -n "$t36_r" ] \
  && [ "$t36_a" -lt "$t36_s" ] && [ "$t36_s" -lt "$t36_b" ] && [ "$t36_b" -lt "$t36_r" ]; then
  ok "T36 disarm succeeds in order LastTriggerUSec < stop < service ActiveState < reset-failed, rc 0, DEADMAN_ARMED=0"
else
  no "T36 disarm order/result wrong (rc=$CASE_RC a=$t36_a stop=$t36_s b=$t36_b rf=$t36_r) ${CASE_OUT:0:240}"
fi
# T36a — fired then collected: the timer already carries a LastTriggerUSec. Read BEFORE the stop it
# is seen; read after, garbage collection has emptied it and a fired timer reports "disarmed".
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; disarm_dead_man host_canary_passed' 'disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting DEADMAN_TIMER_LASTTRIGGER="Mon 2026-09-28 10:00:00 UTC"
if [ "$CASE_RC" -eq 1 ] && ! undef && ! outF 'DIE:' && markerF "$DM result=disarm_failed reason=host_canary_passed check=a" \
  && ! markerF 'result=disarmed' && has '^EMIT_DRIFT deadman_disarm_failed$'; then
  ok "T36a a fired timer is caught by the PRE-stop LastTriggerUSec read: rc 1, check=a, no disarmed, never die"
else
  no "T36a a fired-then-collected timer was reported disarmed or died (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T36a twin + T36b — rollback() reaches the SAME check=a, with reason rollback_engaged, never the old
# canary_passed.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; rollback' 'rollback disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting DEADMAN_TIMER_LASTTRIGGER="Mon 2026-09-28 10:00:00 UTC"
markerF "$DM result=disarm_failed reason=rollback_engaged check=a" \
  && ok "T36a' rollback() reaches the same check=a through its verifying disarm" \
  || no "T36a' rollback() did not report the fired timer (check=a): ${CASE_OUT:0:240}"
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; rollback' 'rollback disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting \
  ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
if markerF "$DM result=disarmed reason=rollback_engaged" && ! grep -qF 'canary_passed' "$MARKER_LOG"; then
  ok "T36b rollback()'s disarm marker reads reason=rollback_engaged, never canary_passed"
else
  no "T36b rollback() disarm marker reason wrong: $(grep -F 'op=workspaces-luks-deadman' "$MARKER_LOG" | tr '\n' '|')"
fi
# T36d — a fire that starts just BEFORE the stop is still running AFTER it. Only the post-stop read
# (b) can see it: the service reads inactive before the stop and activating after.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; disarm_dead_man host_canary_passed' 'disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting \
  DEADMAN_SVC_ACTIVESTATES=inactive DEADMAN_SVC_ACTIVESTATE_AFTER_STOP=activating
if [ "$CASE_RC" -eq 1 ] && ! undef && markerF "$DM result=disarm_failed reason=host_canary_passed check=b"; then
  ok "T36d a fire racing the stop is caught by the POST-stop service read: rc 1, check=b"
else
  no "T36d the post-stop service read missed a racing fire (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T35 — rollback() with an INEFFECTIVE stop (check c fails). The disarm handles the dead-man FIRST —
# its marker precedes the first umount — and its failure does not stop the rollback halfway: the
# plaintext remount, docker start and rollback_engaged (the last line) are all still recorded.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; rollback' 'rollback disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting DEADMAN_STOP_INEFFECTIVE=1 \
  ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
t35_m="$(idx '^logger .*result=disarm_failed reason=rollback_engaged check=c')"; t35_u="$(idx '^umount[[:space:]]')"
if ran && [ -n "$t35_m" ] && [ -n "$t35_u" ] && [ "$t35_m" -lt "$t35_u" ] \
  && has '^mount /dev/disk/by-label/workspaces_plain ' && has '^docker start ' && [ "$(drift_last)" = "rollback_engaged" ]; then
  ok "T35 rollback() disarms BEFORE any umount, and a failed disarm (check=c) never aborts it mid-way"
else
  no "T35 rollback() dead-man handling wrong (rc=$CASE_RC marker=$t35_m umount=$t35_u last-drift=$(drift_last)) ${CASE_OUT:0:240}"
fi
# T35b — nothing armed (a ROLLBACK=1 dispatch after an earlier fire): the timer stop still runs
# (T6b), the marker is result=not_armed, and no false deadman_disarm_failed page.
run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
if ran && has '^systemctl stop workspaces-luks-deadman\.timer' && markerF "$DM result=not_armed reason=rollback_engaged" \
  && nhas '^EMIT_DRIFT deadman_disarm_failed$'; then
  ok "T35b rollback() with nothing armed stops the timer, logs result=not_armed, and pages no disarm failure"
else
  no "T35b unarmed rollback wrong (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T35c — a fire IN PROGRESS: rollback() waits for the service to leave activating before it touches
# the mount (three reads, two 3s waits), rather than unmounting under a running remount.
run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' DEADMAN_LOADED="service" \
  DEADMAN_SVC_ACTIVESTATES="activating activating inactive" ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
if ran && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 3 ] && [ "$(reads_before_umount '^sleep 3$')" -eq 2 ] && has '^umount[[:space:]]'; then
  ok "T35c rollback() waits out a running fire (3 reads, 2 x 3s) before the first umount"
else
  no "T35c rollback() did not wait for the fire (reads=$(reads_before_umount "$DM_SVC_READ") sleeps=$(reads_before_umount '^sleep 3$')) ${CASE_OUT:0:200}"
fi
# T35d — a STUCK fire: the wait is bounded by ATTEMPTS (exactly 30 reads), then it reports
# check=fire_stuck and proceeds — the remount the fire was performing is the same end state.
run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' DEADMAN_LOADED="service" DEADMAN_SVC_ACTIVESTATES=activating \
  ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
if ran && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 30 ] && markerF "$DM result=disarm_failed reason=rollback_engaged check=fire_stuck" \
  && has '^umount[[:space:]]' && [ "$(drift_last)" = "rollback_engaged" ]; then
  ok "T35d a stuck fire is waited out for exactly 30 attempts, reported check=fire_stuck, and the rollback proceeds"
else
  no "T35d stuck-fire wait wrong (reads=$(reads_before_umount "$DM_SVC_READ") rc=$CASE_RC) ${CASE_OUT:0:200}"
fi
# T40 — the host-canary POPULATION assert (user-impact review): the workspace count on the LIVE mount
# must equal the persisted WORKSPACES_COUNT before the door closes. 2 dirs vs 3 dies with no disarm.
run_case "$CUTOVER" 'DRY_RUN=0; mkdir -p "$WORKSPACES_MOUNT/workspaces/ws-a" "$WORKSPACES_MOUNT/workspaces/ws-b"; persist_state WORKSPACES_COUNT 3; assert_host_canary_population' \
  'assert_host_canary_population'
if died && has '^EMIT_DRIFT host_canary_workspace_count_mismatch$' && nhas '^logger .*result=disarm'; then
  ok "T40 a population mismatch on \$MOUNT (2 vs persisted 3) dies host_canary_workspace_count_mismatch, before any disarm"
else
  no "T40 population mismatch not refused (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi
run_case "$CUTOVER" 'DRY_RUN=0; mkdir -p "$WORKSPACES_MOUNT/workspaces/ws-a" "$WORKSPACES_MOUNT/workspaces/ws-b" "$WORKSPACES_MOUNT/workspaces/ws-c"; persist_state WORKSPACES_COUNT 3; assert_host_canary_population' \
  'assert_host_canary_population'
ran && nhas '^EMIT_DRIFT ' \
  && ok "T40 (control) a matching population (3 == 3) passes the host-canary assert" \
  || no "T40 (control) a matching population was refused (rc=$CASE_RC) ${CASE_OUT:0:200}"

# ---------------------------------------------------------------------------
# #9045 — cleanup() records ONE outcome on every non-zero exit, and rolls FORWARD after the canary.
# Each case injects `(exit 9)` and asserts CASE_RC=9, so an injected failure cannot be confused
# with a die inside cleanup (exit 1).
# ---------------------------------------------------------------------------
T37_ACT="inngest-server.service webhook.service inngest-redis.service"
# T37 — CANARY_OK=1 on the mapper: roll FORWARD (docker start + resume_writers), never unmount.
run_case "$CUTOVER" 'CANARY_OK=1; DRY_RUN=0; (exit 9); cleanup' 'cleanup' FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -eq 9 ] && ! undef && nhas '^umount[[:space:]]' && nhas '^mount[[:space:]]' && nhas '^cryptsetup close' \
  && has '^docker start ' && has '^systemctl start webhook\.service' \
  && markerF "$DM result=cutover_aborted outcome=post_canary_luks_retained" && has '^EMIT_DRIFT cutover_aborted_post_canary$'; then
  ok "T37 a post-canary abort rolls FORWARD on the LUKS mount (docker start + resume_writers, no umount), outcome=post_canary_luks_retained, fatal drift"
else
  no "T37 post-canary cleanup wrong (rc=$CASE_RC want 9) ${CASE_OUT:0:240}"
fi
# T37b — the mapper re-assert FAILS: do not start the app on a wrong mount; page instead.
run_case "$CUTOVER" 'CANARY_OK=1; DRY_RUN=0; (exit 9); cleanup' 'cleanup' FINDMNT_MOUNT_SRC=/dev/sdz9 ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -eq 9 ] && ! undef && nhas '^docker start ' && nhas '^systemctl start webhook\.service' \
  && has '^EMIT_DRIFT cleanup_mount_not_mapper$' && has '^EMIT_DRIFT cutover_aborted_post_canary$'; then
  ok "T37b a post-canary abort on a NON-mapper source does not roll forward (no docker start), drift cleanup_mount_not_mapper"
else
  no "T37b roll-forward ran on a wrong mount (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T37c — the roll-forward docker start FAILS: checked, and reported.
run_case "$CUTOVER" 'docker() { rec "docker $*"; [ "${1:-}" = start ] && return 1; return 0; }; CANARY_OK=1; DRY_RUN=0; (exit 9); cleanup' 'cleanup' \
  FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -eq 9 ] && ! undef && has '^EMIT_DRIFT cleanup_docker_start_failed$'; then
  ok "T37c a failed roll-forward docker start emits cleanup_docker_start_failed"
else
  no "T37c a failed roll-forward docker start was silent (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi
# T38 — pre-canary with the freeze held: the REAL rollback runs, and the outcome is read off the
# post-rollback mount source — plaintext = rolled_back; the mapper or nothing = rollback_remount_failed.
for t38 in "/dev/sdz9:rolled_back" "$T_MAPPER:rollback_remount_failed" ":rollback_remount_failed"; do
  t38_src="${t38%%:*}"; t38_want="${t38##*:}"
  run_case "$CUTOVER" 'FREEZE_HELD=1; CANARY_OK=0; DRY_RUN=0; (exit 9); cleanup' 'cleanup rollback' \
    FINDMNT_MOUNT_SRC="$t38_src" ACTIVE_UNITS="$T37_ACT"
  if [ "$CASE_RC" -eq 9 ] && ! undef && has '^umount[[:space:]]' && markerF "$DM result=cutover_aborted outcome=$t38_want"; then
    ok "T38 a pre-canary abort rolls back and records outcome=$t38_want (post-rollback source [${t38_src:-empty}])"
  else
    no "T38 pre-canary outcome wrong for source [${t38_src:-empty}] (rc=$CASE_RC want outcome=$t38_want): $(grep -F 'cutover_aborted' "$MARKER_LOG" | tr '\n' '|')"
  fi
done

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

# AC8 — the dead-man margin. The retry budget added by #6807 made app_canary slow to fail, and on
# 2026-07-20 the dead-man was still armed across it: a 27-minute window in which the timer won,
# remounted the plaintext volume over a healthy LUKS mount and stranded sole-copy writes (#6812).
# Since #9045 the dead-man is disarmed at the HOST-CANARY door, before `docker start`, so app_canary
# no longer races the timer at all (T25'). The bound is KEPT anyway, reworded rather than deleted:
# it now bounds the whole freeze-to-green span (pre-canary elapsed + both probes) inside the
# dead-man window, which is the margin an operator reading the run log assumes, and it costs nothing
# to hold. Removing it would let a future knob change (attempts 30 -> 300) grow a green run past
# DEAD_MAN_MIN with nothing noticing.
#
# Every operand is EXTRACTED BY SHAPE from its own source file. Hardcoding any of them would let a
# future knob change (attempts 30 -> 300) sail past a guard that still asserts the old arithmetic.
ac8_attempts=$(grep -oE 'WORKSPACES_CANARY_ATTEMPTS:-[0-9]+' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9]+$' | sed -n '1p' || true)
ac8_interval=$(grep -oE 'WORKSPACES_CANARY_INTERVAL_S:-[0-9]+' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9]+$' | sed -n '1p' || true)
ac8_maxtime=$(grep -oE '\-\-max-time [0-9]+' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9]+$' | sed -n '1p' || true)
ac8_deadman=$(grep -oE 'WORKSPACES_DEAD_MAN_MIN:-[0-9]+' "$CUTOVER" | grep -oE '[0-9]+$' | sed -n '1p' || true)
# MEASURED, not assumed: freeze/arm 22:11:49.09 -> canary 22:14:50.31 on run 29782780158. This is
# the ONE hardcoded operand (nothing in-repo to extract it from), and it is a LOWER BOUND: the
# arm->canary span contains the freeze + full rsync + G3 gate, which scale with total workspace
# bytes, so real pre-canary elapsed rises with the user base while this constant does not. The ~19min
# margin absorbs a lot, but a RUNTIME budget check in app_canary (read the arm timestamp, shrink the
# attempt count if the remaining budget is thin) is the durable fix — deliberately NOT built here
# (the plan chose a static AC), tracked with the dead-man's own failure modes on #6812.
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
# AC10 — RUNNER/HELPER structural-set parity. The verify workflow's runner-side /health loop cannot
# source the host helper (it runs on the GH runner), so it re-encodes wl_http_class's structural set
# by hand. That duplication is the #6807 drift class: adding 521 to the helper's structural set, or
# dropping 525 from the runner, silently reintroduces Bug B in one of the two copies. The workflow
# COMMENT claims this equality is enforced "by grep" — so it must actually be. Extract the sorted
# structural code list from each file's case-arm and assert byte-equality. The bound (10 vs 30) is
# deliberately NOT compared (see the workflow comment).
ac10_helper="$(grep -oE '^[[:space:]]*307\|[0-9|]+\)[[:space:]]*printf' "$SCRIPT_DIR/workspaces-luks-emit.sh" | grep -oE '[0-9|]+' | tr '|' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')"
ac10_runner="$(grep -oE '^[[:space:]]*307\|[0-9|]+\)' "$VERIFY_WF" | grep -oE '[0-9|]+' | tr '|' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')"
if [ -n "$ac10_helper" ] && [ "$ac10_helper" = "$ac10_runner" ]; then
  ok "AC10 runner /health structural set == wl_http_class structural set ([$ac10_helper])"
else
  no "AC10 structural-set DRIFT between the runner loop and wl_http_class (helper=[$ac10_helper] runner=[$ac10_runner]) — Bug B reintroduced in one copy"
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
