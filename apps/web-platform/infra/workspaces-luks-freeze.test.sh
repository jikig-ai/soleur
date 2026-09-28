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
# #9098 D1 — prove ok()/no() count before any verdict runs through them (exit 2 on an instrument fault).
harness_selftest workspaces-luks-freeze.test.sh

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

# T5/T6 — rollback restores, and only after the remount. #9098 C: rollback() restarts only onto a
# mounted, NON-mapper source, so the fixture reports the retained plaintext device after the remount.
run_case "$CUTOVER" 'DRY_RUN=0 rollback' 'rollback resume_writers' ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" \
  FINDMNT_MOUNT_SRC=/dev/sdz9
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
  # Any indentation and a trailing comment are tolerated (Guard 2 harness row H2), but the call MUST
  # end in `|| die` (#9098 M1): `|| log …` or `|| true` would close the door on an unproven disarm.
  # The behavioural twin is staging's repoint_case "disarm fails" row, which RUNS the door.
  t25_disarm=$(grep -nE '^[[:space:]]*disarm_dead_man[[:space:]]+host_canary_passed[[:space:]]+\|\|[[:space:]]+die[[:space:]]' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  t25_cok=$(grep -nE '^[[:space:]]*CANARY_OK=1' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  t25_dstart=$(grep -nE '^[[:space:]]*docker start "\$CONTAINER"' "$T25BODY.main" | sed -n '1p' | cut -d: -f1 || true)
  t25_ndisarm=$(grep -cE '(^|[;&|{[:space:]])disarm_dead_man([[:space:]]|;|$)' "$T25BODY.main" || true)
fi
if [ -z "$t25_disarm" ]; then
  # Never a pass on an empty extraction: a renamed or deleted call must read as NOT FOUND.
  no "T25' \`disarm_dead_man host_canary_passed || die\` not found in the main body (renamed, deleted, reason changed, or its failure neutered) — the single disarm point is unproven"
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
  # The comparison itself (`= "$MAPPER" ]`, not a `-n` test that $MAPPER merely appears near — M2c)
  # and the die after the drift (not `; log` — M2) are part of the pattern. Staging's repoint_case
  # "source changed after the stop" row is the behavioural twin: it RUNS this line.
  t36c_n=$(awk -v a="$t25_disarm" -v b="$t25_cok" 'NR>a && NR<b && /\[ "\$\(findmnt -no SOURCE "\$MOUNT"[^)]*\)" = "\$MAPPER" \] \|\| \{ emit_drift deadman_fired_before_disarm; die / { n++ } END { print n+0 }' "$T25BODY.main")
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
# T41 — ARM CARDINALITY + POST-DOOR REACHABILITY (#9098 F; kills M22 and M9). T25d proves the FIRST
# arm precedes the freeze flag, but not that it is the ONLY one: a second `arm_dead_man` after
# `docker start` re-creates the #6812 hazard (a backstop armed across app_canary) with T25d still
# green. And T25c scans main-body TEXT only, so a disarm or arm hidden inside app_canary (or anything
# it calls) is invisible to it. So:
#   (a) exactly ONE arm_dead_man command in the main body, and it precedes FREEZE_HELD=1;
#   (b) NO arm_dead_man / disarm_dead_man in any function statically REACHABLE from the main body
#       after `docker start "$CONTAINER"` — the closure is computed over every function defined in
#       the cutover script and the emit helper it sources, to a fixpoint. The EXIT trap (cleanup) is
#       not a direct call and is excluded on purpose: its disarm is gated on DEADMAN_ARMED=1, which the
#       door resets, and T37/T42 assert behaviourally that a post-door cleanup never touches the timer.
# Both detectors carry positive controls on synthesized inputs, so a detector that can never fire
# (wrong region, empty closure) cannot pass.
T41_CALL_RE='(^|[;&|{[:space:]])arm_dead_man([[:space:]]|;|$)'
# Every T41 helper works on TEXT held in variables (here-strings), never on scratch files, so this
# block adds no fixture writes for the fixture-relative-assert ratchet to count.
t41_arms() { grep -cE "$T41_CALL_RE" <<<"$1" || true; }
T41_DEFS="$(grep -vhE '^[[:space:]]*#' "$CUTOVER" "$SCRIPT_DIR/workspaces-luks-emit.sh" || true)"
t41_names() { grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\) *\{' <<<"$1" | sed -E 's/\(\) *\{$//' | sort -u; }
t41_body() {  # <fn> <defs-text> -> the body text of fn (first definition)
  # A one-line definition (`log() { …; }`) ends on its own line; a multi-line one at the next `^}`.
  awk -v n="$1" 'index($0, n "()") == 1 { print; if ($0 !~ /\{[[:space:]]*$/) exit; f=1; next }
                 f { print } f && /^}/ { exit }' <<<"$2"
}
# Words in COMMAND position only (line start, after ; & | ( ! { $( or a then/do/else/if/while/until
# keyword): a function NAME that merely appears inside a message string ("…cleanup() rolls back…")
# is not a call, and counting it would drag rollback() into the closure as a false positive.
t41_calls() { grep -oE '(^|[;&|(!{]|\$\(|(then|do|else|if|while|until)[[:space:]])[[:space:]]*[A-Za-z_][A-Za-z0-9_]*' | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' | sort -u; }
t41_reach() {  # <seed-text> <defs-text> -> reachable function names, one per line
  local defs="$2" known seen="" frontier tok w next_f
  known="$(t41_names "$defs")"
  frontier="$(t41_calls <<<"$1")"
  while [ -n "$frontier" ]; do
    next_f=""
    for tok in $frontier; do
      grep -qxF -- "$tok" <<<"$known" || continue
      case " $seen " in *" $tok "*) continue ;; esac
      seen="$seen $tok"
      # Strip only the `name() {` header, so a one-line definition keeps its body.
      for w in $(t41_body "$tok" "$defs" | sed -E "1s/^${tok}\(\) *\{//" | t41_calls); do next_f="$next_f $w"; done
    done
    frontier="$next_f"
  done
  printf '%s\n' $seen
}
t41_violations() {  # <seed-text> <defs-text> -> count of arm/disarm calls in seed + reachable bodies
  local n=0 fn
  n=$(grep -cE '(^|[^A-Za-z0-9_])(arm_dead_man|disarm_dead_man)([^A-Za-z0-9_]|$)' <<<"$1" || true)
  for fn in $(t41_reach "$1" "$2"); do
    t41_body "$fn" "$2" | sed -E "1s/^${fn}\(\) *\{//" | grep -qE '(^|[^A-Za-z0-9_])(arm_dead_man|disarm_dead_man)([^A-Za-z0-9_]|$)' && n=$((n + 1))
  done
  printf '%s' "$n"
}
t41_main="$(cat "$T25BODY.main")"
t41_post="$(awk '/^[[:space:]]*docker start "\$CONTAINER"/ { seen=1 } seen { print }' <<<"$t41_main")"
t41_n_arm="$(t41_arms "$t41_main")"
t41_arm_ln=$(grep -nE "$T41_CALL_RE" <<<"$t41_main" | sed -n '1p' | cut -d: -f1 || true)
t41_reached="$(t41_reach "$t41_post" "$T41_DEFS" | tr '\n' ' ')"
t41_v="$(t41_violations "$t41_post" "$T41_DEFS")"
# Controls: a body with a second arm counts 2; a defs text hiding a disarm two calls deep (in a
# one-line definition) is caught, and its clean twin is not.
t41_c2="$(t41_arms "$(printf '%s\n' '  arm_dead_man' '  FREEZE_HELD=1' '  docker start "$CONTAINER"' '  arm_dead_man')")"
t41_cseed="$(printf '%s\n' '  docker start "$CONTAINER"' '  helper_a')"
t41_cbad="$(t41_violations "$t41_cseed" "$(printf '%s\n' 'helper_a() {' '  helper_b' '}' 'helper_b() { log x; disarm_dead_man x || true; }')")"
t41_cok="$(t41_violations "$t41_cseed" "$(printf '%s\n' 'helper_a() {' '  helper_b' '}' 'helper_b() {' '  log fine' '}')")"
if [ "$t41_n_arm" -eq 1 ] && [ -n "$t41_arm_ln" ] && [ -n "$t25d_frz" ] && [ "$t41_arm_ln" -lt "$t25d_frz" ] && [ "$t41_c2" -eq 2 ]; then
  ok "T41a exactly ONE arm_dead_man in the main body, before FREEZE_HELD=1 (control: a planted second arm counts 2)"
else
  no "T41a arm cardinality wrong (main-body arms=$t41_n_arm first=$t41_arm_ln FREEZE_HELD=1=$t25d_frz control=$t41_c2; want 1, before the freeze, control 2)"
fi
case " $t41_reached " in
  *" app_canary "*" resume_writers "*|*" resume_writers "*" app_canary "*) t41_has_both=1 ;;
  *) t41_has_both=0 ;;
esac
if [ -n "$t41_post" ] && [ "$t41_has_both" = 1 ] && [ "$t41_v" -eq 0 ] && [ "$t41_cbad" -eq 1 ] && [ "$t41_cok" -eq 0 ]; then
  ok "T41b no arm/disarm in the post-docker-start main body or any function it reaches [${t41_reached% }] (control: 2-deep planted disarm caught, clean twin 0)"
else
  no "T41b post-door reachability check failed (violations=$t41_v reached=[${t41_reached}] control-bad=$t41_cbad control-ok=$t41_cok; want 0, app_canary+resume_writers reached, 1, 0)"
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
# HS1b — the PAIRING production actually reads (#9098 H): the SERVICE ActiveState against the TIMER
# SubState. HS1 reads service.SubState, which production never reads, so a stub that answered
# service.ActiveState from the timer (or vice versa) would pass HS1. Values chosen so each mix-up
# yields a different string.
run_case "$CUTOVER" \
  'systemctl show workspaces-luks-deadman.service -p ActiveState --value; systemctl show workspaces-luks-deadman.timer -p SubState --value; systemctl show workspaces-luks-deadman.timer -p ActiveState --value; systemctl show workspaces-luks-deadman.service -p Job --value' \
  '' DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting DEADMAN_SVC_ACTIVESTATES=activating DEADMAN_SVC_JOB=4711
if [ "$CASE_OUT" = $'activating\nwaiting\ninactive\n4711' ]; then
  ok "HS1b service.ActiveState, timer.SubState, timer.ActiveState and service.Job each answer from their OWN unit+property"
else
  no "HS1b the stub crosses unit/property answers — got [$(tr '\n' '|' <<<"$CASE_OUT")], want [activating|waiting|inactive|4711]"
fi
# HS3 — the systemd-run stub REFUSES (rc 1, the measured H1 text) while the service is still loaded
# and failed, and accepts once reset-failed has collected it. Without this the arm pre-clear (T30c)
# would be proven only by call order, never by its effect.
run_case "$CUTOVER" \
  'systemd-run --on-active=1min --unit=workspaces-luks-deadman /bin/true; echo "rc1=$?"; systemctl reset-failed workspaces-luks-deadman.service; systemd-run --on-active=1min --unit=workspaces-luks-deadman /bin/true; echo "rc2=$?"' \
  '' DEADMAN_LOADED="service"
if [[ "$CASE_OUT" == *"was already loaded or has a fragment file."*"rc1=1"*"rc2=0"* ]]; then
  ok "HS3 systemd-run refuses (rc 1, already loaded) while the stale service is loaded, and arms once reset-failed collected it"
else
  no "HS3 the systemd-run stub does not model the H1 refusal — got [$(tr '\n' '|' <<<"$CASE_OUT")]"
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
# T30c — the pre-clear, proven by EFFECT (#9098 H): both units start LOADED and stale (the
# 2026-07-20 fire's end state), and the systemd-run stub refuses exactly as systemd does while either
# is loaded. The arm succeeds only because the stop + reset-failed collected both. Dropping the
# service from the reset-failed (or the stop of the timer) turns this into an arm_failed.
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man; echo PAST_ARM' 'arm_dead_man' DEADMAN_LOADED="timer service"
if ran && outF PAST_ARM && markerF "$DM result=armed reason=freeze_engaged" && ! markerF 'result=arm_failed'; then
  ok "T30c a STALE loaded timer+service (the post-fire state) is cleared and the arm succeeds — the pre-clear works by effect"
else
  no "T30c the arm did not clear a stale loaded dead-man (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T31 — systemd-run REFUSES (the H1 shape: a loaded failed unit). Fails closed: died, arm_failed with
# the named reason, drift deadman_arm_failed, and NO result=armed. The refusal text is captured,
# not discarded.
# #9098 M10: the first line carries a TAB, a CR and a raw \x01 — the printable-only scrub must drop all
# three, or a crafted refusal could split or corrupt the marker line.
T31_ERR="Failed"$'\t'"to start"$'\r'" transient"$'\x01'" timer unit: Unit workspaces-luks-deadman.service was already loaded or has a fragment file. result=armed $(printf 'x%.0s' $(seq 1 300))"$'\n''second-line-must-not-appear'
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man; echo PAST_ARM' 'arm_dead_man' SYSTEMD_RUN_RC=1 SYSTEMD_RUN_OUT="$T31_ERR"
if died && markerF "$DM result=arm_failed reason=systemd_run_refused" && ! markerF 'result=armed' \
  && has '^EMIT_DRIFT deadman_arm_failed$' && outF 'DIE:' && ! outF PAST_ARM; then
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
  && [[ "$t31_rest" != *$'\t'* ]] && [[ "$t31_rest" != *$'\r'* ]] && [[ "$t31_rest" != *$'\x01'* ]] \
  && [ "$(cnt '^EMIT_DRIFT ')" -eq 1 ] && has '^EMIT_DRIFT deadman_arm_failed$'; then
  ok "T31b detail= is last, first-line, <=200 chars, =-scrubbed (result=armed -> result_armed), TAB/CR/control-free, and absent from the drift reason"
else
  no "T31b detail scrub wrong (len=${#t31_rest}) [${t31_detail:0:260}]"
fi
# T32 — systemd-run returns 0 but the timer NEVER reads waiting: the bounded attempt-counted poll
# (5 reads, 4 x `sleep 1`) runs out, then it dies timer_not_waiting. No result=armed.
# `arm_dead_man; echo PAST_ARM` (#9098 F): the main body calls a BARE arm_dead_man under no `set -e`,
# so a `return 1` here would start the freeze behind an unverified backstop. It must DIE.
run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man; echo PAST_ARM' 'arm_dead_man' DEADMAN_TIMER_SUBSTATES=dead
if died && markerF "$DM result=arm_failed reason=timer_not_waiting substate=dead" && ! markerF 'result=armed' \
  && has '^EMIT_DRIFT deadman_arm_failed$' && [ "$(cnt '^sleep 1$')" -eq 4 ] && outF 'DIE:' && ! outF PAST_ARM; then
  ok "T32 an unverified arm dies timer_not_waiting after exactly 5 attempt-counted polls, never result=armed"
else
  no "T32 unverified arm mishandled (rc=$CASE_RC sleeps=$(cnt '^sleep 1$')) ${CASE_OUT:0:240}"
fi
# T32b — DEADMAN_ARMED=1 is set the moment systemd-run returns 0, BEFORE the verification, so the
# cleanup() that a timer_not_waiting die reaches disarms the timer this run created. Nothing is
# frozen yet, so the outcome is arm_aborted.
# #9098 H: it must prove the timer THIS run created was STOPPED — `disarmed`, never `disarm_failed`,
# and a timer stop recorded AFTER the systemd-run that created it.
run_case "$CUTOVER" 'trap cleanup EXIT; DRY_RUN=0; arm_dead_man' 'arm_dead_man cleanup disarm_dead_man' DEADMAN_TIMER_SUBSTATES=dead
t32b_run="$(idx '^systemd-run ')"
t32b_stop="$(awk -v r="${t32b_run:-999999}" 'NR>r && /^systemctl stop workspaces-luks-deadman\.timer/ { print NR; exit }' "$CALLS")"
if died && markerF "$DM result=disarmed reason=arm_aborted" && ! markerF 'result=disarm_failed' \
  && [ -n "$t32b_run" ] && [ -n "$t32b_stop" ] && markerF "$DM result=cutover_aborted outcome=arm_aborted"; then
  ok "T32b a failed arm verification still reaches the disarm in cleanup: the timer it created is stopped after its systemd-run and reads disarmed (outcome=arm_aborted)"
else
  no "T32b the timer this run created outlives a failed arm — no arm_aborted disarm/outcome (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T33 — a LIVE dead-man is never stopped by an arm: a waiting timer belongs to an earlier run's freeze,
# and a running service is a fire in progress. Refuse, and record neither a stop nor a systemd-run.
# #9098 Note A: a running fire of the transient SIMPLE service reads `active` (measured, systemd 261:
# a running /bin/sleep transient reads ActiveState=active), `activating` only for an instant before
# the fork, and `deactivating` while stopping. All three are pinned, so no member can be dropped.
for t33 in "already_armed DEADMAN_TIMER_SUBSTATES=waiting" "fire_in_progress DEADMAN_SVC_ACTIVESTATES=activating" \
           "fire_in_progress DEADMAN_SVC_ACTIVESTATES=active" "fire_in_progress DEADMAN_SVC_ACTIVESTATES=deactivating"; do
  t33_reason="${t33%% *}"; t33_knob="${t33#* }"
  run_case "$CUTOVER" 'DRY_RUN=0; arm_dead_man; echo PAST_ARM' 'arm_dead_man' DEADMAN_LOADED="timer service" "$t33_knob"
  if died && markerF "$DM result=arm_refused reason=$t33_reason" && has '^EMIT_DRIFT deadman_already_armed$' \
    && nhas '^systemctl stop workspaces-luks-deadman' && nhas '^systemd-run ' && outF 'DIE:' && ! outF PAST_ARM; then
    ok "T33 arm refuses a live dead-man ($t33_reason, ${t33_knob#*=}): dies, no stop, no systemd-run, drift deadman_already_armed"
  else
    no "T33 arm did not refuse a live dead-man ($t33_reason, ${t33_knob#*=}, rc=$CASE_RC) ${CASE_OUT:0:240}"
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
# (b) can see it: the service reads inactive before the stop and a live state after. #9098 Note A: a
# running fire of the transient SIMPLE service reads `active`; `activating` is the pre-fork instant.
for t36d in activating active; do
  run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; disarm_dead_man host_canary_passed' 'disarm_dead_man' \
    DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting \
    DEADMAN_SVC_ACTIVESTATES=inactive DEADMAN_SVC_ACTIVESTATE_AFTER_STOP="$t36d"
  if [ "$CASE_RC" -eq 1 ] && ! undef && markerF "$DM result=disarm_failed reason=host_canary_passed check=b"; then
    ok "T36d a fire racing the stop ($t36d after it) is caught by the POST-stop service read: rc 1, check=b"
  else
    no "T36d the post-stop service read missed a racing fire ($t36d, rc=$CASE_RC) ${CASE_OUT:0:240}"
  fi
done
# T36e — the timer elapsed and QUEUED the fire's start job, but systemd has not begun it: ActiveState
# still reads inactive and only the service's `Job` property shows it (#9098 D; measured: a queued
# start reads a non-empty Job, an idle unit an empty one). Check (b) must fail on it too.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; disarm_dead_man host_canary_passed' 'disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting DEADMAN_SVC_JOB=4711
if [ "$CASE_RC" -eq 1 ] && ! undef && markerF "$DM result=disarm_failed reason=host_canary_passed check=b" \
  && has '^systemctl show workspaces-luks-deadman\.service -p Job --value$'; then
  ok "T36e a queued start job (Job non-empty, ActiveState inactive) fails check=b"
else
  no "T36e a queued fire start job was not caught (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T35 — rollback() with an INEFFECTIVE stop (check c fails). The disarm handles the dead-man FIRST —
# its marker precedes the first umount — and its failure does not stop the rollback halfway: the
# plaintext remount, docker start and rollback_engaged (the last line) are all still recorded.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; rollback' 'rollback disarm_dead_man' \
  DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting DEADMAN_STOP_INEFFECTIVE=1 \
  ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" FINDMNT_MOUNT_SRC=/dev/sdz9
t35_m="$(idx '^logger .*result=disarm_failed reason=rollback_engaged check=c')"; t35_u="$(idx '^umount[[:space:]]')"
if ran && [ -n "$t35_m" ] && [ -n "$t35_u" ] && [ "$t35_m" -lt "$t35_u" ] \
  && has '^mount /dev/disk/by-label/workspaces_plain ' && has '^docker start ' && [ "$(drift_last)" = "rollback_engaged" ]; then
  ok "T35 rollback() disarms BEFORE any umount, and a failed disarm (check=c) never aborts it mid-way"
else
  no "T35 rollback() dead-man handling wrong (rc=$CASE_RC marker=$t35_m umount=$t35_u last-drift=$(drift_last)) ${CASE_OUT:0:240}"
fi
# T35b — nothing armed, EVER, by this run (a ROLLBACK=1 dispatch): the timer stop still runs (T6b),
# the marker is result=not_armed with the timer SubState read BEFORE that stop (prior=), and no false
# deadman_disarm_failed page. prior=waiting proves the read precedes the stop: after the stop the GC
# model answers dead.
run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" \
  FINDMNT_MOUNT_SRC=/dev/sdz9 DEADMAN_LOADED="timer" DEADMAN_TIMER_SUBSTATES=waiting
if ran && has '^systemctl stop workspaces-luks-deadman\.timer' && markerF "$DM result=not_armed reason=rollback_engaged prior=waiting" \
  && nhas '^EMIT_DRIFT deadman_disarm_failed$'; then
  ok "T35b rollback() with nothing armed stops the timer, logs result=not_armed prior=<pre-stop SubState>, and pages no disarm failure"
else
  no "T35b unarmed rollback wrong (rc=$CASE_RC) $(grep -F 'op=workspaces-luks-deadman' "$MARKER_LOG" | tr '\n' '|')"
fi
# T35b2 — THIS run armed and already disarmed at the door (DEADMAN_ARMED=0, DEADMAN_EVER_ARMED=1): the
# honest row is already_disarmed, never not_armed.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_EVER_ARMED=1; rollback' 'rollback' ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" \
  FINDMNT_MOUNT_SRC=/dev/sdz9
if ran && markerF "$DM result=already_disarmed reason=rollback_engaged" && ! markerF 'result=not_armed'; then
  ok "T35b2 a rollback after this run's own door disarm logs result=already_disarmed, not not_armed"
else
  no "T35b2 already-disarmed rollback row wrong: $(grep -F 'op=workspaces-luks-deadman' "$MARKER_LOG" | tr '\n' '|')"
fi
# T35c — a fire IN PROGRESS, nothing armed by this run: rollback() waits for the service to leave the
# live state before it touches the mount (three reads, two 3s waits), never unmounting under a
# running remount. `active` twin per Note A.
for t35c in activating active; do
  run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' DEADMAN_LOADED="service" \
    DEADMAN_SVC_ACTIVESTATES="$t35c $t35c inactive" ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" FINDMNT_MOUNT_SRC=/dev/sdz9
  if ran && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 3 ] && [ "$(reads_before_umount '^sleep 3$')" -eq 2 ] && has '^umount[[:space:]]'; then
    ok "T35c rollback() waits out a running fire ($t35c: 3 reads, 2 x 3s) before the first umount"
  else
    no "T35c rollback() did not wait for the fire ($t35c, reads=$(reads_before_umount "$DM_SVC_READ") sleeps=$(reads_before_umount '^sleep 3$')) ${CASE_OUT:0:200}"
  fi
done
# T35c2 — ORDERING (#9098 C): when THIS run armed, the verifying disarm (which STOPS the timer) runs
# BEFORE the wait, so no new fire can start while rollback() waits out the current one. Every service
# ActiveState read comes after the timer stop, the disarm reports check=b once, the wait then sees
# the fire finish, and no fire_stuck row or second page is emitted.
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; rollback' 'rollback disarm_dead_man' DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting \
  DEADMAN_SVC_ACTIVESTATES="active active inactive" ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" FINDMNT_MOUNT_SRC=/dev/sdz9
t35c2_stop="$(idx '^systemctl stop workspaces-luks-deadman\.timer')"; t35c2_read="$(idx "$DM_SVC_READ")"
if ran && [ -n "$t35c2_stop" ] && [ -n "$t35c2_read" ] && [ "$t35c2_stop" -lt "$t35c2_read" ] \
  && markerF "$DM result=disarm_failed reason=rollback_engaged check=b" && ! markerF 'check=fire_stuck' \
  && [ "$(cnt '^EMIT_DRIFT deadman_disarm_failed$')" -eq 1 ] && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 3 ]; then
  ok "T35c2 an armed rollback STOPS the timer (disarm) before the first fire-state read, then waits the fire out — one check=b row, one page"
else
  no "T35c2 armed-rollback ordering wrong (stop=$t35c2_stop first-read=$t35c2_read pages=$(cnt '^EMIT_DRIFT deadman_disarm_failed$') reads=$(reads_before_umount "$DM_SVC_READ")) ${CASE_OUT:0:200}"
fi
# T35d — a STUCK fire: the wait is bounded by ATTEMPTS (exactly 30 reads), then it reports
# check=fire_stuck, PAGES deadman_disarm_failed (#9098 M20), and proceeds — the remount the fire was
# performing is the same end state.
for t35d in activating active; do
  run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' DEADMAN_LOADED="service" DEADMAN_SVC_ACTIVESTATES="$t35d" \
    ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" FINDMNT_MOUNT_SRC=/dev/sdz9
  if ran && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 30 ] && markerF "$DM result=disarm_failed reason=rollback_engaged check=fire_stuck" \
    && [ "$(cnt '^EMIT_DRIFT deadman_disarm_failed$')" -eq 1 ] && has '^umount[[:space:]]' && [ "$(drift_last)" = "rollback_engaged" ]; then
    ok "T35d a stuck fire ($t35d) is waited out for exactly 30 attempts, reported check=fire_stuck with ONE deadman_disarm_failed page, and the rollback proceeds"
  else
    no "T35d stuck-fire wait wrong ($t35d, reads=$(reads_before_umount "$DM_SVC_READ") pages=$(cnt '^EMIT_DRIFT deadman_disarm_failed$') rc=$CASE_RC) ${CASE_OUT:0:200}"
  fi
done
# T35c3 — a QUEUED fire (the timer elapsed; the service still reads inactive but carries a start Job):
# rollback() must wait on the Job too, never unmount under a fire systemd is about to begin. The Job
# never clears in this model, so the wait expires: 30 reads, check=fire_stuck, one page.
run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' DEADMAN_LOADED="service" DEADMAN_SVC_ACTIVESTATES=inactive DEADMAN_SVC_JOB=4711 \
  ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" FINDMNT_MOUNT_SRC=/dev/sdz9
if ran && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 30 ] && markerF "$DM result=disarm_failed reason=rollback_engaged check=fire_stuck" \
  && [ "$(cnt '^EMIT_DRIFT deadman_disarm_failed$')" -eq 1 ]; then
  ok "T35c3 rollback() waits on a QUEUED start job (ActiveState inactive, Job set) before the first umount"
else
  no "T35c3 rollback() ignored a queued fire (reads=$(reads_before_umount "$DM_SVC_READ") pages=$(cnt '^EMIT_DRIFT deadman_disarm_failed$')) ${CASE_OUT:0:200}"
fi
# T35d2 — armed AND stuck: the disarm already reported check=b and paged; the expired wait adds its
# fire_stuck row but NOT a second deadman_disarm_failed page (#9098 C: no duplicate pages).
run_case "$CUTOVER" 'DRY_RUN=0; DEADMAN_ARMED=1; rollback' 'rollback disarm_dead_man' DEADMAN_LOADED="timer service" DEADMAN_TIMER_SUBSTATES=waiting \
  DEADMAN_SVC_ACTIVESTATES=active ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service" FINDMNT_MOUNT_SRC=/dev/sdz9
if ran && markerF "$DM result=disarm_failed reason=rollback_engaged check=b" && markerF "$DM result=disarm_failed reason=rollback_engaged check=fire_stuck" \
  && [ "$(cnt '^EMIT_DRIFT deadman_disarm_failed$')" -eq 1 ] && [ "$(reads_before_umount "$DM_SVC_READ")" -eq 31 ]; then
  ok "T35d2 an armed rollback over a stuck fire: check=b (disarm) + check=fire_stuck (wait expiry), ONE page"
else
  no "T35d2 duplicate or missing stuck-fire reporting (pages=$(cnt '^EMIT_DRIFT deadman_disarm_failed$') reads=$(reads_before_umount "$DM_SVC_READ")) $(grep -F 'op=workspaces-luks-deadman' "$MARKER_LOG" | tr '\n' '|')"
fi
# T35e — rollback() restarts the app ONLY onto a mounted, non-mapper $MOUNT (#9098 C). A failed
# remount (not a mountpoint) or a source that is still the mapper leaves the app DOWN with
# rollback_remount_failed; the control (plaintext source) restarts it.
for t35e in "MOUNTPOINT_RC=1:/dev/sdz9:down" "MOUNTPOINT_RC=0:$T_MAPPER:down" "MOUNTPOINT_RC=0::down" "MOUNTPOINT_RC=0:/dev/sdz9:up"; do
  t35e_mp="${t35e%%:*}"; t35e_rest="${t35e#*:}"; t35e_src="${t35e_rest%%:*}"; t35e_want="${t35e_rest##*:}"
  run_case "$CUTOVER" 'DRY_RUN=0; rollback' 'rollback' "$t35e_mp" FINDMNT_MOUNT_SRC="$t35e_src" \
    ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service"
  if [ "$t35e_want" = down ] && ran && nhas '^docker start ' && nhas '^systemctl start webhook\.service' && has '^EMIT_DRIFT rollback_remount_failed$'; then
    ok "T35e rollback() leaves the app DOWN on ${t35e_mp} source=[${t35e_src:-empty}] (rollback_remount_failed)"
  elif [ "$t35e_want" = up ] && ran && has '^docker start ' && nhas '^EMIT_DRIFT rollback_remount_failed$'; then
    ok "T35e (control) rollback() restarts the app on a mounted plaintext source"
  else
    no "T35e rollback restart gate wrong for ${t35e_mp} source=[${t35e_src:-empty}] want=$t35e_want (rc=$CASE_RC) ${CASE_OUT:0:200}"
  fi
done
# T40 — the host-canary POPULATION assert (#9098 E): the workspace count on the LIVE mount must equal
# the IN-PROCESS G3 count ($WS_INVENTORY) — never read_state, whose file is append-only across runs,
# so an earlier run's WORKSPACES_COUNT could stand in for this run's. Every failure dies before any
# disarm (T40b pins the placement; staging repoint_case RUNS the door).
t40_case() {  # <n dirs> <invocation prefix>
  local k inv='DRY_RUN=0; '
  for k in $(seq 1 "$1"); do inv="${inv}mkdir -p \"\$WORKSPACES_MOUNT/workspaces/ws-$k\"; "; done
  run_case "$CUTOVER" "${inv}$2; assert_host_canary_population" 'assert_host_canary_population'
}
t40_case 2 'WS_INVENTORY=3'
died && has '^EMIT_DRIFT host_canary_workspace_count_mismatch$' \
  && ok "T40 a LOWER population on \$MOUNT (2 vs G3's 3) dies host_canary_workspace_count_mismatch" \
  || no "T40 lower population not refused (rc=$CASE_RC) ${CASE_OUT:0:200}"
t40_case 3 'WS_INVENTORY=2'
died && has '^EMIT_DRIFT host_canary_workspace_count_mismatch$' \
  && ok "T40 a HIGHER population (3 vs G3's 2) dies too — the check is equality, not a floor (#9098 M3)" \
  || no "T40 higher population accepted (rc=$CASE_RC) ${CASE_OUT:0:200}"
t40_case 0 'rmdir "$WORKSPACES_MOUNT/workspaces"; WS_INVENTORY=2'
died && has '^EMIT_DRIFT host_canary_workspace_count_mismatch$' && outF '<uncountable>' \
  && ok "T40 an UNCOUNTABLE \$MOUNT/workspaces (removed) dies — unreadable is not a match (#9098 M4)" \
  || no "T40 an uncountable workspaces dir passed (rc=$CASE_RC) ${CASE_OUT:0:200}"
for t40w in "unset WS_INVENTORY" "WS_INVENTORY=" "WS_INVENTORY=abc" "WS_INVENTORY=0"; do
  t40_case 2 "$t40w"
  if died && has '^EMIT_DRIFT host_canary_baseline_missing$' && nhas '^EMIT_DRIFT host_canary_workspace_count_mismatch$'; then
    ok "T40 a missing/invalid G3 baseline ($t40w) fails CLOSED with host_canary_baseline_missing (#9098 M19)"
  else
    no "T40 baseline [$t40w] not refused as missing (rc=$CASE_RC) ${CASE_OUT:0:200}"
  fi
done
# The in-process count, never the state file: a stale persisted count that happens to MATCH must not
# rescue a mismatch, and a stale one that DIFFERS must not fail a match.
t40_case 2 'persist_state WORKSPACES_COUNT 2; WS_INVENTORY=3'
died && has '^EMIT_DRIFT host_canary_workspace_count_mismatch$' \
  && ok "T40 a stale persisted WORKSPACES_COUNT equal to the live count does NOT satisfy the assert (in-process G3 count 3 wins)" \
  || no "T40 the assert read the append-only state file instead of the in-process G3 count (rc=$CASE_RC)"
t40_case 3 'persist_state WORKSPACES_COUNT 7; WS_INVENTORY=3'
ran && nhas '^EMIT_DRIFT ' \
  && ok "T40 (control) a matching in-process population (3 == 3) passes, whatever a stale state file says" \
  || no "T40 (control) a matching population was refused (rc=$CASE_RC) ${CASE_OUT:0:200}"
# T40f — the G3 counter failure DIES at G3 (#9098 E): the door can no longer pass without a baseline, so
# a warn-and-continue at G3 would only defer the abort to after the repoint.
t40f_blk="$(awk '/^[[:space:]]*if WS_INVENTORY="\$\(wl_count_workspace_dirs /{f=1} f{print} f && /^[[:space:]]*fi[[:space:]]*$/{exit}' "$T25BODY.main")"
if grep -qE 'emit_drift workspace_count_persist_failed' <<<"$t40f_blk" && grep -qE '(^|[;{[:space:]])die[[:space:]]' <<<"$t40f_blk"; then
  ok "T40f a G3 workspace-count failure emits workspace_count_persist_failed AND dies at G3"
else
  no "T40f the G3 count failure is not fatal at G3: [$(tr '\n' '|' <<<"$t40f_blk")]"
fi

# ---------------------------------------------------------------------------
# #9045 — cleanup() records ONE outcome on every non-zero exit, and rolls FORWARD after the canary.
# Each case injects `(exit 9)` and asserts CASE_RC=9, so an injected failure cannot be confused
# with a die inside cleanup (exit 1).
# ---------------------------------------------------------------------------
T37_ACT="inngest-server.service webhook.service inngest-redis.service"
# T37 — CANARY_OK=1 on the mapper: roll FORWARD (docker start + resume_writers), never unmount, and
# never touch the (already disarmed) dead-man. docker start PRECEDES the writers (#9098 M16).
run_case "$CUTOVER" 'CANARY_OK=1; DRY_RUN=0; (exit 9); cleanup' 'cleanup' FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
t37_ds="$(idx '^docker start ')"; t37_wh="$(idx '^systemctl start webhook\.service')"
if [ "$CASE_RC" -eq 9 ] && ! undef && nhas '^umount[[:space:]]' && nhas '^mount[[:space:]]' && nhas '^cryptsetup close' \
  && [ -n "$t37_ds" ] && [ -n "$t37_wh" ] && [ "$t37_ds" -lt "$t37_wh" ] \
  && nhas '^systemctl stop workspaces-luks-deadman' && nhas '^systemd-run ' \
  && markerF "$DM result=cutover_aborted outcome=post_canary_luks_retained" && ! markerF 'abnormal_exit=' && has '^EMIT_DRIFT cutover_aborted_post_canary$'; then
  ok "T37 a post-canary abort rolls FORWARD on the LUKS mount (docker start, THEN resume_writers; no umount, no dead-man touch), outcome=post_canary_luks_retained"
else
  no "T37 post-canary cleanup wrong (rc=$CASE_RC want 9, docker_start=$t37_ds webhook=$t37_wh) ${CASE_OUT:0:240}"
fi
# T37b — the mapper re-assert FAILS, on a wrong source OR an empty one (#9098 M11): do not start the
# app on a wrong mount — actively STOP it and the writers, and page.
for t37b in /dev/sdz9 ""; do
  run_case "$CUTOVER" 'CANARY_OK=1; DRY_RUN=0; (exit 9); cleanup' 'cleanup' FINDMNT_MOUNT_SRC="$t37b" ACTIVE_UNITS="$T37_ACT"
  if [ "$CASE_RC" -eq 9 ] && ! undef && nhas '^docker start ' && nhas '^systemctl start webhook\.service' \
    && has '^docker stop -t 30 ' && has '^systemctl stop webhook\.service' && has '^systemctl stop inngest-redis\.service' \
    && markerF "$DM result=cutover_aborted outcome=post_canary_mount_not_mapper" \
    && has '^EMIT_DRIFT cleanup_mount_not_mapper$' && has '^EMIT_DRIFT cutover_aborted_post_canary$'; then
    ok "T37b a post-canary abort on source [${t37b:-empty}] does not roll forward: app + writers STOPPED, outcome=post_canary_mount_not_mapper"
  else
    no "T37b post-canary cleanup on source [${t37b:-empty}] wrong (rc=$CASE_RC) ${CASE_OUT:0:240}"
  fi
done
# T37c — the roll-forward docker start FAILS: its first stderr line reaches the OUTCOME row as a
# scrubbed detail= (never the drift reason), and the outcome says restart_failed, not luks_retained.
run_case "$CUTOVER" 'docker() { rec "docker $*"; if [ "${1:-}" = start ]; then printf "Error response from daemon: boom=1\tbad\nsecond-line\n" >&2; return 1; fi; return 0; }; CANARY_OK=1; DRY_RUN=0; (exit 9); cleanup' 'cleanup' \
  FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
t37c_row="$(grep -F 'outcome=post_canary_restart_failed' "$MARKER_LOG" | sed -n '1p')"
if [ "$CASE_RC" -eq 9 ] && ! undef && has '^EMIT_DRIFT cleanup_docker_start_failed$' \
  && [[ "$t37c_row" == *" detail=Error response from daemon: boom_1bad" ]] && [[ "$t37c_row" != *second-line* ]] \
  && nhas '^EMIT_DRIFT .*Error' && ! markerF 'outcome=post_canary_luks_retained'; then
  ok "T37c a failed roll-forward docker start: outcome=post_canary_restart_failed with a scrubbed first-line detail=, drift cleanup_docker_start_failed"
else
  no "T37c a failed roll-forward docker start was not reported truthfully (rc=$CASE_RC) row=[$t37c_row]"
fi
# T37d — ABNORMAL termination (#9098 A): `$?` is 0 in an EXIT trap run by a signal, so rc==0 with
# RUN_COMPLETE unset is an abort, not a success. Post-canary it rolls FORWARD and says abnormal_exit=1.
run_case "$CUTOVER" 'CANARY_OK=1; DRY_RUN=0; (exit 0); cleanup' 'cleanup' FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -eq 1 ] && ! undef && has '^docker start ' && has '^systemctl start webhook\.service' \
  && markerF "$DM result=cutover_aborted outcome=post_canary_luks_retained abnormal_exit=1"; then
  ok "T37d rc 0 without RUN_COMPLETE=1 is an ABNORMAL exit: rolled forward, exit 1, outcome row carries abnormal_exit=1"
else
  no "T37d an abnormal (rc 0, incomplete) exit was treated as success (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T37e — the genuine success exit (RUN_COMPLETE=1, rc 0) does NOTHING: no restart, no outcome row.
run_case "$CUTOVER" 'CANARY_OK=1; DRY_RUN=0; RUN_COMPLETE=1; (exit 0); cleanup' 'cleanup' FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -eq 0 ] && ! undef && nhas '^docker ' && nhas '^systemctl ' && ! markerF 'result=cutover_aborted'; then
  ok "T37e a completed run (RUN_COMPLETE=1, rc 0) exits 0 through cleanup with no action and no outcome row"
else
  no "T37e cleanup acted on a completed run (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# T38 — pre-canary with the freeze held: the REAL rollback runs, and the outcome is read off the
# post-rollback mount: exactly one plaintext source with the mapper closed = rolled_back; the mapper
# or nothing = rollback_remount_failed; two stacked sources = rollback_stacked (#9098 B).
for t38 in "/dev/sdz9|rolled_back" "$T_MAPPER|rollback_remount_failed" "|rollback_remount_failed" \
           $'/dev/sdz9\n/dev/sdz8|rollback_stacked' $'/dev/sdz9\n'"$T_MAPPER|rollback_stacked"; do
  t38_src="${t38%%|*}"; t38_want="${t38##*|}"
  run_case "$CUTOVER" 'FREEZE_HELD=1; CANARY_OK=0; DRY_RUN=0; (exit 9); cleanup' 'cleanup rollback' \
    FINDMNT_MOUNT_SRC="$t38_src" ACTIVE_UNITS="$T37_ACT"
  if [ "$CASE_RC" -eq 9 ] && ! undef && has '^umount[[:space:]]' && markerF "$DM result=cutover_aborted outcome=$t38_want" \
    && { [ "$t38_want" != rollback_stacked ] || has '^EMIT_DRIFT rollback_stacked$'; }; then
    ok "T38 a pre-canary abort rolls back and records outcome=$t38_want (post-rollback source [$(tr '\n' '+' <<<"${t38_src:-empty}")])"
  else
    no "T38 pre-canary outcome wrong for source [$(tr '\n' '+' <<<"${t38_src:-empty}")] (rc=$CASE_RC want outcome=$t38_want): $(grep -F 'cutover_aborted' "$MARKER_LOG" | tr '\n' '|')"
  fi
done
# T38b — one plaintext source, but the MAPPER is still open (a close that failed EBUSY): the data
# plane is plaintext, yet a decrypted copy is still live — never call that rolled_back.
run_case "$CUTOVER" 'MAPPER="$WORKSPACES_STAGING"; FREEZE_HELD=1; CANARY_OK=0; DRY_RUN=0; (exit 9); cleanup' 'cleanup rollback' \
  FINDMNT_MOUNT_SRC=/dev/sdz9 ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -eq 9 ] && ! undef && markerF "$DM result=cutover_aborted outcome=rollback_stacked" && has '^EMIT_DRIFT rollback_stacked$' \
  && ! markerF 'outcome=rolled_back'; then
  ok "T38b a plaintext remount with the mapper STILL OPEN records outcome=rollback_stacked (+ drift), never rolled_back"
else
  no "T38b an open mapper after rollback was reported as rolled_back (rc=$CASE_RC): $(grep -F 'cutover_aborted' "$MARKER_LOG" | tr '\n' '|')"
fi
# T38c — the non-rollback outcomes are asserted too (#9098 M12/M13): a dry-run abort is dry_run even
# with the freeze flag set (nothing was frozen), an abort with every flag 0 is pre_freeze, and a
# CLEAN_STRAY abort is clean_stray. None of them unmounts anything.
for t38c in "FREEZE_HELD=1 DRY_RUN=1|dry_run" "FREEZE_HELD=0 DRY_RUN=0|pre_freeze" "CLEAN_STRAY=1 DRY_RUN=0|clean_stray"; do
  t38c_set="${t38c%%|*}"; t38c_want="${t38c##*|}"
  run_case "$CUTOVER" "$t38c_set; CANARY_OK=0; (exit 9); cleanup" 'cleanup rollback' FINDMNT_MOUNT_SRC=/dev/sdz9 ACTIVE_UNITS="$T37_ACT"
  if [ "$CASE_RC" -eq 9 ] && ! undef && nhas '^umount[[:space:]]' && markerF "$DM result=cutover_aborted outcome=$t38c_want" \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ]; then
    ok "T38c an abort with [$t38c_set] records exactly one outcome=$t38c_want and unmounts nothing"
  else
    no "T38c outcome wrong for [$t38c_set] (rc=$CASE_RC want $t38c_want): $(grep -F 'cutover_aborted' "$MARKER_LOG" | tr '\n' '|')"
  fi
done
# T42 — REAL SIGNALS (#9098 A), not a simulated `(exit 0)`. The case arms the real EXIT trap and then
# (a) is killed with SIGTERM after the canary, (b) writes into a CLOSED stdout pipe with the freeze
# held — the SSH-drop shape: SIGPIPE, the EXIT trap, and a cleanup whose own log() writes into the
# same dead pipe. The outcome row is cleanup's LAST act, so its presence proves the whole branch ran
# without cleanup re-raising SIGPIPE on itself.
run_case "$CUTOVER" 'trap cleanup EXIT; DRY_RUN=0; CANARY_OK=1; kill -TERM $$; echo PAST_KILL' 'cleanup' \
  FINDMNT_MOUNT_SRC="$T_MAPPER" ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -ne 0 ] && ! undef && ! outF PAST_KILL && has '^docker start ' \
  && markerF "$DM result=cutover_aborted outcome=post_canary_luks_retained abnormal_exit=1"; then
  ok "T42a a real SIGTERM after the canary reaches cleanup, rolls forward, and records abnormal_exit=1"
else
  no "T42a SIGTERM did not produce a rolled-forward abnormal outcome (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# `--default-signal=PIPE` (GNU env, the FIRST run_case env arg so env parses it as an option): a runner
# that starts this suite with SIGPIPE IGNORED (measured: the CI deploy-script-tests leg) hands that
# disposition down, and bash cannot reset a signal ignored on entry. The write then fails EPIPE, the
# script dies through `die` (rc=1, no abnormal_exit), and this case tests the wrong path. Production
# receives the default disposition from sshd, which is what this row pins.
run_case "$CUTOVER" 'trap cleanup EXIT; DRY_RUN=0; FREEZE_HELD=1; exec 1> >(:); wait $! 2>/dev/null; log "write into the dead pipe"; printf PAST_PIPE >&2' 'cleanup rollback' \
  --default-signal=PIPE FINDMNT_MOUNT_SRC=/dev/sdz9 ACTIVE_UNITS="$T37_ACT"
if [ "$CASE_RC" -ne 0 ] && ! undef && ! outF PAST_PIPE && has '^umount[[:space:]]' && has '^mount /dev/disk/by-label/workspaces_plain ' \
  && markerF "$DM result=cutover_aborted outcome=rolled_back abnormal_exit=1"; then
  ok "T42b a closed stdout pipe mid-freeze (SIGPIPE) aborts into cleanup, which rolls back and records abnormal_exit=1 despite logging into the dead pipe"
else
  no "T42b SIGPIPE mid-freeze did not roll back with a recorded outcome (rc=$CASE_RC) calls=[$(tr '\n' '|' < "$CALLS" | cut -c1-300)]"
fi

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

# AC8 — RETIRED (#9098 K). It bounded app_canary's retry budget inside DEAD_MAN_MIN because the
# dead-man used to stay armed across the canary (#6812). Since #9045 the dead-man is disarmed at the
# host-canary door, BEFORE docker start (T25', staging repoint_case), so no timer races app_canary and
# the inequality no longer protects anything.
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
# #9098 A — every INTENTIONAL success exit sets RUN_COMPLETE=1 first. cleanup() treats rc 0 without
# it as an abnormal termination (T37d/T42), so a success exit that forgot it would page and roll
# forward/back on every green run. Every `exit 0` in the main body (comment-stripped) must carry
# RUN_COMPLETE=1 on its own line or the line before; the count is pinned so a new exit path is a
# deliberate edit here. Control: a synthesized body missing it is caught.
# ---------------------------------------------------------------------------
t43_bad() {  # <text> -> count of `exit 0` lines not preceded (same or previous line) by RUN_COMPLETE=1
  awk '{ cur=$0 } /(^|[;[:space:]])exit 0([[:space:]]|;|$)/ { if (cur !~ /RUN_COMPLETE=1/ && prev !~ /RUN_COMPLETE=1/) n++ }
       { if ($0 !~ /^[[:space:]]*$/) prev=$0 } END { print n+0 }' <<<"$1"
}
t43_n="$(grep -cE '(^|[;[:space:]])exit 0([[:space:]]|;|$)' "$T25BODY.main" || true)"
t43_real="$(t43_bad "$t41_main")"
t43_ctl="$(t43_bad "$(printf '%s\n' 'if x; then' '  rollback' '  exit 0' 'fi')")"
# #6604 step 7 took this 3 -> 4: the CONFIRM_WIPE mode block ends `RUN_COMPLETE=1; exit 0` too.
if [ "$t43_n" -eq 4 ] && [ "$t43_real" -eq 0 ] && [ "$t43_ctl" -eq 1 ]; then
  ok "T43 all 4 intentional exit-0 paths (ROLLBACK end, CLEAN_STRAY end, CONFIRM_WIPE end, the normal/dry-run end) set RUN_COMPLETE=1 (control caught)"
else
  no "T43 exit-0 paths: count=$t43_n (want 4) missing RUN_COMPLETE=$t43_real (want 0) control=$t43_ctl (want 1)"
fi

# ---------------------------------------------------------------------------
# #9098 J — ROLLBACK=1 after a SUCCESSFUL cutover strands every write made on the LUKS mount since
# docker start. The mode block is EXTRACTED from the script and executed (not grepped), so the guard's
# placement before rollback() is proven by behaviour.
# ---------------------------------------------------------------------------
RB_TEXT="$(awk '/^if \[ "\$ROLLBACK" = "1" \]; then$/{f=1} f{print} f && /^fi$/{exit}' "$CUTOVER")"
if ! grep -qE '^[[:space:]]*rollback$' <<<"$RB_TEXT" || ! bash -n <<<"$RB_TEXT" 2>/dev/null; then
  no "J0 the ROLLBACK mode block could not be extracted — treat J1-J5 as UN-RUN"
fi
rb_case() {  # <persisted CANARY_OK> [env...]
  local pc="$1"; shift
  run_case "$CUTOVER" "persist_state CANARY_OK '$pc'; trap cleanup EXIT; eval \"\$RB_TEXT\"" 'rollback cleanup assert_rollback_not_post_cutover' \
    ROLLBACK=1 RB_TEXT="$RB_TEXT" ACTIVE_UNITS="$T37_ACT" CRYPTSETUP_DEV=/dev/sdz7 "$@"
}
rb_case "1:uuid-live" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=uuid-live
if died && has '^EMIT_DRIFT rollback_refused_post_cutover$' && outF 'strand' && nhas '^umount[[:space:]]' && nhas '^docker stop'; then
  ok "J1 ROLLBACK=1 on a cut-over host (mount = mapper, persisted CANARY_OK uuid = live header) is REFUSED before any umount"
else
  no "J1 a post-cutover ROLLBACK=1 was not refused (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
# The source flips to the plaintext once rollback() stops the (loaded) timer: the guard reads the
# mapper, the post-rollback outcome read sees the remount land.
rb_case "1:uuid-live" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=uuid-live ROLLBACK_ACK_LUKS_WRITES=1 \
  DEADMAN_LOADED=timer FINDMNT_MOUNT_SRC_AFTER_DEADMAN_STOP=/dev/sdz9
if ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_post_cutover$' && ! markerF 'result=cutover_aborted'; then
  ok "J2 ROLLBACK_ACK_LUKS_WRITES=1 lets the same post-cutover rollback run, and its green exit records no abort (RUN_COMPLETE=1)"
else
  no "J2 the acknowledged post-cutover rollback did not run cleanly (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
rb_case "1:uuid-live" FINDMNT_MOUNT_SRC=/dev/sdz9 CRYPTSETUP_UUID=uuid-live
if ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_post_cutover$'; then
  ok "J3 ROLLBACK=1 on a host NOT cut over (mount is the plaintext) runs without the ack"
else
  no "J3 a not-cut-over rollback was refused (rc=$CASE_RC) ${CASE_OUT:0:240}"
fi
rb_case "1:uuid-old" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=uuid-new \
  DEADMAN_LOADED=timer FINDMNT_MOUNT_SRC_AFTER_DEADMAN_STOP=/dev/sdz9
if ran && nhas '^EMIT_DRIFT rollback_refused_post_cutover$'; then
  ok "J4 a persisted CANARY_OK for a DIFFERENT header (uuid-old vs live uuid-new) does not block the rollback"
else
  no "J4 a stale CANARY_OK from another header blocked the rollback (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi
rb_case "1:uuid-live" FINDMNT_MOUNT_SRC="$T_MAPPER"
if died && has '^EMIT_DRIFT rollback_refused_post_cutover$' && nhas '^umount[[:space:]]'; then
  ok "J5 mapper mounted + CANARY_OK persisted but the live header UUID UNREADABLE: refused (fail-closed; the ack is the override)"
else
  no "J5 an unverifiable post-cutover state was rolled back without the ack (rc=$CASE_RC) ${CASE_OUT:0:200}"
fi
# J7 — a ROLLBACK=1 whose remount FAILED (the mount still reads the mapper afterwards) left the app
# and the writers DOWN. It must not exit 0: it records ONE outcome row (mode=rollback) and exits
# non-zero, and the EXIT trap does not add a second, false pre_freeze row.
rb_case "1:uuid-live" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=uuid-live ROLLBACK_ACK_LUKS_WRITES=1
if died && has '^umount[[:space:]]' && has '^EMIT_DRIFT rollback_remount_failed$' \
  && markerF "$DM result=cutover_aborted outcome=rollback_remount_failed mode=rollback" \
  && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ]; then
  ok "J7 a ROLLBACK=1 whose remount failed exits non-zero with ONE outcome=rollback_remount_failed mode=rollback row"
else
  no "J7 a failed-remount ROLLBACK=1 went green or mis-recorded (rc=$CASE_RC): $(grep -F 'cutover_aborted' "$MARKER_LOG" | tr '\n' '|')"
fi
# J8 — the plaintext remounted but the mapper is STILL OPEN (a close that failed EBUSY): a decrypted
# copy is live, so the rollback is not clean either — rollback_stacked, non-zero.
run_case "$CUTOVER" "MAPPER=\"\$WORKSPACES_STAGING\"; persist_state CANARY_OK '1:uuid-live'; trap cleanup EXIT; eval \"\$RB_TEXT\"" \
  'rollback cleanup assert_rollback_not_post_cutover' \
  ROLLBACK=1 RB_TEXT="$RB_TEXT" ACTIVE_UNITS="$T37_ACT" CRYPTSETUP_DEV=/dev/sdz7 FINDMNT_MOUNT_SRC=/dev/sdz9 CRYPTSETUP_UUID=uuid-live
if died && markerF "$DM result=cutover_aborted outcome=rollback_stacked mode=rollback" && has '^EMIT_DRIFT rollback_stacked$'; then
  ok "J8 a ROLLBACK=1 that leaves the mapper open exits non-zero with outcome=rollback_stacked mode=rollback"
else
  no "J8 an open mapper after ROLLBACK=1 was reported clean (rc=$CASE_RC): $(grep -F 'cutover_aborted' "$MARKER_LOG" | tr '\n' '|')"
fi
# J6 — the workflow plumbs the ack the same way `rollback` reaches the host: a boolean input
# defaulting to false, mapped to 0|1 in the Run step env, written into the 0600 .env, and refused
# by the ungated preflight unless rollback is also ticked.
if grep -qE '^      rollback_ack_luks_writes:$' "$WORKFLOW" \
  && awk '/^      rollback_ack_luks_writes:$/{f=1} f&&/type: boolean/{t=1} f&&/default: false/{d=1} f&&/^      [a-z_]+:$/&&!/rollback_ack/{exit} END{exit !(t&&d)}' "$WORKFLOW" \
  && grep -qF "ROLLBACK_ACK_LUKS_WRITES: \${{ inputs.rollback_ack_luks_writes && '1' || '0' }}" "$WORKFLOW" \
  && grep -qE "ROLLBACK_ACK_LUKS_WRITES=%s" "$WORKFLOW" && grep -qE '"\$ROLLBACK_ACK_LUKS_WRITES"' "$WORKFLOW" \
  && grep -qE 'ACK_IN(:-false)?\}?" == "true" && "\$ROLLBACK_IN" != "true"' "$WORKFLOW"; then
  ok "J6 the workflow plumbs rollback_ack_luks_writes (boolean, default false) into the host .env and refuses it without rollback"
else
  no "J6 the rollback_ack_luks_writes input is not plumbed to the host (input / env map / .env field / preflight refusal)"
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
# #9098 D1 — PASS FLOOR, set to the measured count. `fail -eq 0` alone is satisfied by a suite whose
# no() stopped counting (or whose cases stopped dispatching), so a real failure could print FAIL and
# still exit 0. harness_floor reports through printf + exit 1, never through no(). The inner
# self-check run (WL_SELF_CHECK=1) skips the three R0-R2 rows. Raise this when adding rows.
FREEZE_MIN_PASS=169
[ "${WL_SELF_CHECK:-0}" = "1" ] && FREEZE_MIN_PASS=$((FREEZE_MIN_PASS - 3))
harness_floor workspaces-luks-freeze.test.sh "$FREEZE_MIN_PASS"
[ "$fail" -eq 0 ]
