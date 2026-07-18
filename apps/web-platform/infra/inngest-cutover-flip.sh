#!/usr/bin/env bash
# inngest-cutover-flip.sh — the 2.2b+2.3 dedicated-host cutover flip oneshot (#6178,
# ADR-100). Runs ON the dedicated Inngest host (10.0.1.40) as a systemd oneshot
# (inngest-cutover-flip.service) fired every 30s by inngest-cutover-flip.timer. It is
# NOT a web-host webhook script — the deny-all-public dedicated host has no inbound
# control channel, so a Doppler-flag poll is the only no-SSH trigger.
#
# It is an 8-state FINITE STATE MACHINE keyed on INNGEST_CUTOVER_FLIP (an out-of-band
# Doppler value on soleur-inngest/prd, delivered as an env var by the unit's
# `doppler run` wrapper). Branches (§Flow-Review Reconciliation of the plan):
#
#   armed       set flipping -> STOP inngest-server -> Redis FLUSHALL -> assert
#               DBSIZE==0 -> set flushed -> START inngest-server -> set done  (P1-4 order)
#   flipping    PRE-flush resume (crash before the flush completed; server still dark):
#               re-run the FULL STOP -> FLUSHALL -> assert -> flushed -> start -> done.
#               SAFE to re-FLUSHALL — nothing is on prod yet (#5450).
#   armed/flipping,DBSIZE!=0  do NOT start; set terminal `aborted`; exit 1   (P0-3)
#   flushed     POST-flush resume (crash after the DBSIZE assert, before/at start): ensure
#               started -> set done. Does NOT re-FLUSHALL — the queue may be on prod (#5450).
#   rollback    STOP inngest-server -> set terminal `rolled-back`            (P0-1)
#   done / rolled-back / aborted / unset   idempotent no-op, exit 0
#
# LOAD-BEARING invariants:
#   * Order is stop -> FLUSHALL -> assert -> flushed -> start (P1-4): the dark server is
#     stopped FIRST so it cannot write between the flush and the DBSIZE check.
#   * The transient is SPLIT into two checkpoints so a crash can neither SKIP the flush
#     nor RE-flush a prod queue (P1-5 / #5450):
#       - `flipping` (written armed->flipping BEFORE Redis is touched): a resume here
#         re-runs the WHOLE stop->FLUSHALL->assert. SAFE — the server is still stopped/
#         dark, nothing is on prod, so a re-FLUSHALL cannot wipe a live prod queue. This
#         closes the skip-flush window (a crash between set-flipping and the flush would
#         otherwise resume straight into start against an un-flushed dark Redis).
#       - `flushed` (written AFTER the DBSIZE==0 assert passes, BEFORE start): a resume
#         here ONLY ensures started->done and NEVER re-FLUSHALLs (the #5450 trap — the
#         queue is now on prod Postgres). Reaching `flushed` proves the flush succeeded.
#   * This script NEVER disables inngest-cutover-flip.timer (P0-1): the timer stays
#     enabled for the host's whole life so a later `rollback` write is observable on
#     the next poll. The FSM flag is the sole gate; the terminal no-ops make a benign
#     30s poll safe.
#   * EVERY branch emits a `logger -t inngest-cutover-flip` JSON line (P0-2) — INCLUDING
#     an unexpected non-zero exit (a Doppler/systemctl failure): an ERR trap emits an
#     `unexpected-exit` marker AND drives the flag to terminal `aborted`, so the poll
#     halts loudly instead of resuming into a no-flush false `done` (the #5934 class — a
#     stop_server failure after flag->flipping must not later read as success). The
#     marker rides the on-host Vector->Better Stack journald shipper (commit c890464ce),
#     the no-SSH state channel the operator reads; and writes a host-path state slot for
#     cat-inngest-cutover-state.sh (on-host debug aid ONLY, never the operator gate).
#   * Purity (P2-sec-a / AC-NOBODY): log lines + the state slot carry state + counts
#     ONLY — never the Redis password, the Postgres URI, or any connection string.
#
# Fixture seams (CI has no redis / systemd / doppler): CUTOVER_FLIP_FLAG (flag value),
# CUTOVER_REDIS_DBSIZE (injected post-FLUSHALL DBSIZE), CUTOVER_FLAG_SET_CMD (flag
# transitions), CUTOVER_SYSTEMCTL_CMD (start/stop), CUTOVER_REDIS_CLI_CMD (the FLUSHALL
# "flush seam"), CUTOVER_LOGGER_CMD (the logger sink), INNGEST_CUTOVER_STATE (state slot
# path). Real sources: the env-delivered flag, `systemctl`, `redis-cli`, `doppler`.
# -E (errtrace): the ERR trap in run_flip must be inherited by the shared flip functions
# so an unhandled failure inside them still fails LOUD (marker + aborted), never silent.
set -Eeuo pipefail

readonly LOG_TAG="inngest-cutover-flip"
readonly SERVER_UNIT="inngest-server.service"
STATE_FILE="${INNGEST_CUTOVER_STATE:-/var/lock/inngest-cutover-flip.state}"
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# --- Flag read: fixture seam CUTOVER_FLIP_FLAG else the env-delivered Doppler value.
# `${VAR+x}` distinguishes set-but-empty (an explicit "unset" test case) from absent.
read_flag() {
  local raw
  if [[ -n "${CUTOVER_FLIP_FLAG+x}" ]]; then
    raw="${CUTOVER_FLIP_FLAG}"
  else
    raw="${INNGEST_CUTOVER_FLIP:-}"
  fi
  printf '%s' "$raw" | tr -d '[:space:]'
}

# --- Flag transition: fixture seam CUTOVER_FLAG_SET_CMD else `doppler secrets set`.
# The scoped soleur-inngest boot token (DOPPLER_TOKEN, EnvironmentFile) authorizes the
# write on soleur-inngest/prd. Not `|| true`: a failed transition must fail LOUD so the
# next poll re-derives the true host state rather than reading a false `done`.
flag_set() {
  local value="$1"
  if [[ -n "${CUTOVER_FLAG_SET_CMD:-}" ]]; then
    "$CUTOVER_FLAG_SET_CMD" "$value"
  else
    doppler secrets set INNGEST_CUTOVER_FLIP "$value" \
      --project soleur-inngest --config prd --silent
  fi
}

# --- systemctl start/stop: fixture seam CUTOVER_SYSTEMCTL_CMD else `systemctl`.
systemctl_cmd() {
  if [[ -n "${CUTOVER_SYSTEMCTL_CMD:-}" ]]; then
    "$CUTOVER_SYSTEMCTL_CMD" "$@"
  else
    systemctl "$@"
  fi
}
stop_server() { systemctl_cmd stop "$SERVER_UNIT"; }
# LOCKSTEP CONSTRAINT (#6553): the ExecStartPre flip-guard (inngest-server-flip-guard.sh) BLOCKS a
# prod-URI start unless the cutover flag is in its allowlist, and inngest-server-flip-guard.test.sh
# derives "the FSM states that start the server" by walking this file for `start_server` calls and
# attributing the nearest preceding `flag_set <state>` / case-arm label. Keep every `start_server`
# call TEXTUALLY PRECEDED (nearest, no intervening flag_set) by the `flag_set <state>` for the state
# it runs in, and keep the guard allowlist a superset of those states — else the guard blocks the
# FSM's own controlled start. A new start site changes the test's EXPECTED_START_SITES count (a
# deliberate re-review latch).
start_server() { systemctl_cmd start "$SERVER_UNIT"; }

# --- redis-cli: fixture seam CUTOVER_REDIS_CLI_CMD else `redis-cli -a <pw>` (loopback
# :6379). The password is passed via -a from the env-injected INNGEST_REDIS_PASSWORD and
# is NEVER echoed to stdout/stderr or a log line.
redis_cli_cmd() {
  if [[ -n "${CUTOVER_REDIS_CLI_CMD:-}" ]]; then
    "$CUTOVER_REDIS_CLI_CMD" "$@"
  else
    redis-cli -a "${INNGEST_REDIS_PASSWORD:-}" "$@"
  fi
}
redis_flushall() { redis_cli_cmd FLUSHALL >/dev/null; }
# DBSIZE value: the injected fixture seam short-circuits the real query. On a real
# query failure emit a non-numeric sentinel so the DBSIZE==0 assert fails LOUD (abort)
# rather than silently reading a false-clean 0.
redis_dbsize() {
  if [[ -n "${CUTOVER_REDIS_DBSIZE+x}" ]]; then
    printf '%s' "${CUTOVER_REDIS_DBSIZE}"
  else
    redis_cli_cmd DBSIZE 2>/dev/null || printf '%s' "__DBSIZE_QUERY_FAILED__"
  fi
}

# --- emit: write the host-path state slot AND the no-SSH logger line. Counts/state only.
emit_state() {
  local exit_code="$1" dbsize="$2" reason="$3" flag="$4" json
  json="$(jq -nc \
    --argjson exit_code "$exit_code" \
    --arg dbsize "$dbsize" \
    --arg reason "$reason" \
    --arg flag "$flag" \
    --arg start_ts "$START_TS" \
    '{exit_code:$exit_code, dbsize:$dbsize, reason:$reason, flag:$flag, start_ts:$start_ts}')"
  # Debug-aid state slot (cat-inngest-cutover-state.sh) — best-effort, never fatal.
  printf '%s\n' "$json" > "$STATE_FILE" 2>/dev/null || true
  # No-SSH state channel: journald -> Vector -> Better Stack (P0-2).
  "${CUTOVER_LOGGER_CMD:-logger}" -t "$LOG_TAG" "$json" 2>/dev/null || true
}

# --- P2-d re-arm-after-done latch (#5450 catastrophe guard). A flip that reached terminal
# `done` means the queue is now on LIVE prod Postgres/Redis; a stray flag flip back to
# `armed` (or `flipping`) must NEVER re-enter the flush path and FLUSHALL a now-live prod
# Redis. Reuses the EXISTING host-path state slot (no new file): a completed flip records
# {"flag":"done",...} there, and the `done`/no-op polls keep it stamped `done`. Reading it
# back proves the flush already happened. Best-effort: an absent/unreadable slot ⇒ NOT done
# (a genuine first flip proceeds — the DBSIZE==0 assert still guards that path).
flip_already_done() {
  [[ -f "$STATE_FILE" ]] || return 1
  local recorded
  recorded="$(jq -r '.flag // ""' "$STATE_FILE" 2>/dev/null || printf '')"
  [[ "$recorded" == "done" ]]
}

# --- Loud refuse: a re-arm arrived after a terminal `done`. Do NOT stop, do NOT FLUSHALL.
# Emit the refuse marker FIRST (guaranteed on-box + Better Stack), then latch terminal
# `aborted` so the 30s poll HALTS, then exit non-zero.
refuse_rearm_after_done() {
  emit_state 1 "" "refuse-rearm-after-done" aborted
  flag_set aborted
  exit 1
}

# --- Shared forward-flip body for the `armed` entry AND the `flipping` PRE-flush resume.
# Both run the FULL stop->FLUSHALL->assert: reaching here proves we are still pre-start
# (server dark) — `armed` has just set `flipping`, and a `flipping` resume means the crash
# landed before the post-assert `flushed` checkpoint. Re-running the flush is therefore
# SAFE (nothing on prod) and closes the skip-flush window (P1-5 / #5450).
run_preflush_flip() {
  # P1-4 ORDER: stop the dark scheduler's write path, THEN flush, THEN assert.
  stop_server
  if ! redis_flushall; then
    flag_set aborted
    emit_state 1 "" "flushall-failed" aborted
    exit 1
  fi
  local dbsize
  dbsize="$(redis_dbsize)"
  if [[ "$dbsize" != "0" ]]; then
    # P0-3: explicit terminal `aborted` so the 30s poll HALTS (no re-attempt storm)
    # and never reads as success (only `done` does). Do NOT start inngest-server.
    flag_set aborted
    emit_state 1 "$dbsize" "dbsize-nonzero" aborted
    exit 1
  fi
  # POST-assert checkpoint (P1-5 / #5450): the flush provably succeeded (DBSIZE==0) and the
  # queue is about to be adopted by the prod scheduler. A resume from `flushed` MUST NOT
  # re-FLUSHALL — write the checkpoint BEFORE start_server so the window is covered.
  flag_set flushed
  start_server
  flag_set "done"
  emit_state 0 "$dbsize" "flip-complete" "done"
}

# --- ERR trap: any unhandled non-zero (flag_set/stop_server/start_server failure) must
# fail LOUD, not silently exit with NO marker (the #5934 class — and a stop_server failure
# after flag->flipping would otherwise leave the flag mid-transition and enable a later
# false `done`). Emit an `unexpected-exit` marker AND drive the flag to terminal `aborted`
# so the next 30s poll HALTS on the no-op instead of resuming into a no-flush `done`. Reads
# the current flag defensively (best-effort; never re-triggers the trap).
on_unexpected_exit() {
  local rc=$?
  local cur
  cur="$(read_flag 2>/dev/null || printf '')"
  flag_set aborted 2>/dev/null || true
  emit_state "$rc" "" "unexpected-exit(from=${cur:-unknown})" "aborted"
  exit "$rc"
}

run_flip() {
  trap on_unexpected_exit ERR
  local flag
  flag="$(read_flag)"

  case "$flag" in
    armed)
      # P2-d (#5450): refuse to re-enter the flush path if a terminal `done` was already
      # recorded — re-arming after a completed flip would FLUSHALL a now-LIVE prod Redis.
      if flip_already_done; then
        refuse_rearm_after_done
      fi
      # Transition BEFORE touching Redis so a mid-flip reboot resumes via `flipping` and
      # RE-RUNS the full flush (server still dark — safe), never skipping it (P1-5 / #5450).
      flag_set flipping
      run_preflush_flip
      ;;
    flipping)
      # PRE-flush resume (#5450): landing in `flipping` (not `flushed`) means the crash
      # happened BEFORE the flush completed and the server is still stopped/dark, so
      # re-running stop->FLUSHALL->assert is SAFE and closes the skip-flush window.
      # P2-d: same latch — never re-FLUSHALL if a terminal `done` was already recorded.
      if flip_already_done; then
        refuse_rearm_after_done
      fi
      run_preflush_flip
      ;;
    flushed)
      # POST-flush resume (#5450 trap): the flush already completed (proven by the
      # `flushed` checkpoint) and the queue is now on prod Postgres. Do NOT re-FLUSHALL;
      # just ensure inngest-server is started and complete to `done`.
      start_server
      flag_set "done"
      emit_state 0 "" "flushed-resume-no-reflush" "done"
      ;;
    rollback)
      # P0-1: the armed rollback mode. Stop the dedicated scheduler; the timer stays
      # enabled so this write was observable in the first place.
      stop_server
      flag_set rolled-back
      emit_state 0 "" "rolled-back" rolled-back
      ;;
    done)
      emit_state 0 "" "noop-done" "done"
      ;;
    rolled-back)
      emit_state 0 "" "noop-rolled-back" rolled-back
      ;;
    aborted)
      emit_state 0 "" "noop-aborted" aborted
      ;;
    *)
      emit_state 0 "" "noop-unset" "${flag:-unset}"
      ;;
  esac
}

# Run only when executed directly — sourcing (unit tests) must NOT act on host state.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_flip
fi
