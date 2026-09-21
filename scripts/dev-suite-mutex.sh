#!/usr/bin/env bash
# dev-suite-mutex.sh — cross-ref advisory mutex for the dev-Supabase
# tenant-integration critical section (#7964).
#
# Why this exists: workflow-level concurrency `dev-supabase-${{ github.ref }}`
# serializes runs within a ref, but different refs still interleave DDL against
# the same hosted dev project (unmerged migrations, CREATE OR REPLACE
# FUNCTION). A database-scoped advisory lock serializes that critical section
# regardless of which ref or workflow run is the writer.
#
# Lock mechanics:
#   - Preferred path: pg_advisory_xact_lock over DATABASE_URL_POOLER
#     (transaction-mode pooler). A transaction-scoped lock survives pooler
#     hand-off of the server connection because the pooler pins the connection
#     for the life of the transaction; a dead holder's TCP drop releases the
#     lock at the database/kernel level — no heartbeat or TTL machinery.
#   - Fallback: session-scoped pg_advisory_lock over DATABASE_URL ONLY.
#     NEVER pair a session-scoped lock with the pooler — transaction-mode
#     pooling can hand a still-locked session to an unrelated renter.
#
# Failure policy is deliberate (see the plan):
#   - lock wait budget exhausted -> DEV_SUITE_MUTEX_CONTENDED_PROCEEDING and
#     exit 0 (fail-OPEN with a loud banner). A hard refusal would recreate the
#     required-check queue starvation that killed repo-wide concurrency
#     (#7986/#8048). The drift probes downstream are the fail-closed layer for
#     authoritative refs.
#   - missing/unusable inputs -> DEV_SUITE_MUTEX_UNAVAILABLE + exit 0. The mutex
#     is an orchestration primitive, not a hard gate; the suite must never be
#     red because the lock primitive itself was unreachable.
#
# Banner tokens (asserted by tests/scripts/test-dev-suite-mutex.sh and greppable
# in run logs):
#   DEV_SUITE_MUTEX_WAITING               sustained wait past the grace window
#   DEV_SUITE_MUTEX_HELD_BY <app>         probe: holder's application_name
#                                         (transaction-mode Supavisor masks the
#                                         client PGAPPNAME — holder shows as
#                                         'Supavisor', still proof of a holder)
#   DEV_SUITE_MUTEX_ACQUIRED after <N>ms  lock held (mode=xact|session)
#   DEV_SUITE_MUTEX_CONTENDED_PROCEEDING  budget exhausted, proceeding anyway
#   DEV_SUITE_MUTEX_RELEASED              release ran (idempotent)
#   DEV_SUITE_MUTEX_UNAVAILABLE           primitive unusable, proceeding
#
# Env:
#   DATABASE_URL_POOLER          preferred connection (xact lock)
#   DATABASE_URL                 fallback connection (session lock, direct only)
#   DEV_SUITE_MUTEX_IDENTITY     PGAPPNAME value — ref/run identity only, no secrets
#   DEV_SUITE_MUTEX_WAIT_S       wait budget before CONTENDED (default 480)
#   DEV_SUITE_MUTEX_HOLD_S       holder's pg_sleep ceiling (default 1170)
#   DEV_SUITE_MUTEX_STATE_DIR    per-runner state dir (default $RUNNER_TEMP or TMPDIR)
set -uo pipefail

MUTEX_NAME='tenant_integration_dev_suite'
MARKER='DEV_SUITE_MUTEX_HELD'
WAIT_S="${DEV_SUITE_MUTEX_WAIT_S:-480}"
HOLD_S="${DEV_SUITE_MUTEX_HOLD_S:-1170}"
STATE_DIR="${DEV_SUITE_MUTEX_STATE_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dev-suite-mutex}"
PID_FILE="$STATE_DIR/holder.pid"
SQL_FILE="$STATE_DIR/holder.sql"
OUT_FILE="$STATE_DIR/holder.out"
ERR_FILE="$STATE_DIR/holder.err"
CONN_URL=""
LOCK_MODE=""

# Identity is stamped into PGAPPNAME; strip control chars so a crafted value
# cannot smuggle an annotation line into the run log.
IDENTITY=$(printf '%s' "${DEV_SUITE_MUTEX_IDENTITY:-ti-unknown}" | tr -d '\000-\037\177')
[[ "$WAIT_S" =~ ^[0-9]+$ ]] || WAIT_S=480
[[ "$HOLD_S" =~ ^[0-9]+$ ]] || HOLD_S=1170

usage() {
  cat <<'EOF'
Usage: dev-suite-mutex.sh acquire|release|probe

  acquire   take the dev-suite advisory lock (bounded wait, fail-open)
  release   drop the lock held by this runner (idempotent, safe under if:always())
  probe     report the current holder's application_name, or DEV_SUITE_MUTEX_FREE

Env: DATABASE_URL_POOLER (xact lock, preferred), DATABASE_URL (session lock,
fallback only), DEV_SUITE_MUTEX_IDENTITY, DEV_SUITE_MUTEX_WAIT_S,
DEV_SUITE_MUTEX_HOLD_S, DEV_SUITE_MUTEX_STATE_DIR.
EOF
}

_now_ms() {
  local v
  v=$(date +%s%3N 2>/dev/null || true)
  [[ "$v" =~ ^[0-9]+$ ]] || v=$(( $(date +%s) * 1000 ))
  printf '%s\n' "$v"
}

# resolve_conn — set CONN_URL/LOCK_MODE. Pooler => xact only; direct => session.
# The coupling is structural: session mode is unreachable while the pooler is
# set, so a session-scoped lock can never ride a transaction-mode pooler.
resolve_conn() {
  if [[ -n "${DATABASE_URL_POOLER:-}" ]]; then
    CONN_URL="$DATABASE_URL_POOLER"; LOCK_MODE="xact"; return 0
  fi
  if [[ -n "${DATABASE_URL:-}" ]]; then
    CONN_URL="$DATABASE_URL"; LOCK_MODE="session"; return 0
  fi
  return 1
}

write_holder_sql() {
  if [[ "$LOCK_MODE" == "xact" ]]; then
    cat >"$SQL_FILE" <<SQL
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('$MUTEX_NAME'));
SELECT '$MARKER' AS marker;
SELECT pg_sleep($HOLD_S);
COMMIT;
SQL
  else
    cat >"$SQL_FILE" <<SQL
SELECT pg_advisory_lock(hashtext('$MUTEX_NAME'));
SELECT '$MARKER' AS marker;
SELECT pg_sleep($HOLD_S);
SQL
  fi
}

# sanitize_field — DB-returned text destined for a GH annotation: collapse all
# control characters (incl. CR/LF) so it cannot inject a workflow command line.
sanitize_field() {
  tr '\r\n\t' '   ' | tr -d '\000-\037\177' | tr -s ' '
}

# holder_identity — application_name(s) of sessions holding our advisory lock.
# Prints nothing (rc 0) when free; rc non-zero on query failure.
holder_identity() {
  local url="$1" raw
  raw=$(psql "$url" --no-psqlrc -tAq -v ON_ERROR_STOP=1 -c "
    SELECT string_agg(COALESCE(NULLIF(a.application_name,''),'<unset>'), ', ')
    FROM pg_locks l
    JOIN pg_stat_activity a ON a.pid = l.pid
    WHERE l.locktype = 'advisory' AND l.granted
      AND l.classid = ((hashtext('$MUTEX_NAME')::bigint >> 32) & 4294967295)
      AND l.objid   = (hashtext('$MUTEX_NAME')::bigint & 4294967295)
  " 2>/dev/null) || return 1
  printf '%s' "$raw" | sanitize_field
}

acquire() {
  if ! resolve_conn; then
    echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=no_database_url -- proceeding unserialized (fail-open)"
    return 0
  fi
  if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=state_dir_unwritable -- proceeding unserialized (fail-open)"
    return 0
  fi
  # Defensive: a stale pid file on this runner means a prior acquire leaked.
  [[ -f "$PID_FILE" ]] && release >/dev/null 2>&1 || true

  write_holder_sql
  : >"$OUT_FILE"; : >"$ERR_FILE"
  PGAPPNAME="$IDENTITY" psql "$CONN_URL" --no-psqlrc -tAq -v ON_ERROR_STOP=1 \
    -f "$SQL_FILE" >"$OUT_FILE" 2>"$ERR_FILE" &
  local pid=$!
  printf '%s\n' "$pid" >"$PID_FILE"

  local start_ms deadline_ms elapsed now announced=0 holder tail_err
  start_ms=$(_now_ms)
  deadline_ms=$(( start_ms + WAIT_S * 1000 ))
  while :; do
    if grep -qF "$MARKER" "$OUT_FILE" 2>/dev/null; then
      elapsed=$(( $(_now_ms) - start_ms ))
      printf 'DEV_SUITE_MUTEX_ACQUIRED after %dms (mode=%s identity=%s)\n' \
        "$elapsed" "$LOCK_MODE" "$IDENTITY"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      tail_err=$(tail -n 3 "$ERR_FILE" 2>/dev/null | sanitize_field || true)
      echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=holder_exited detail=${tail_err:-unknown} -- proceeding unserialized (fail-open)"
      rm -f "$PID_FILE"
      return 0
    fi
    now=$(_now_ms)
    if (( now >= deadline_ms )); then
      holder=$(holder_identity "$CONN_URL" || true)
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
      printf '::warning::DEV_SUITE_MUTEX_CONTENDED_PROCEEDING holder=%s -- wait budget %ss exhausted; proceeding unserialized\n' \
        "${holder:-unknown}" "$WAIT_S"
      return 0
    fi
    # WAITING means "sustained wait", not "polled once" — a free acquire still
    # pays connect latency (~750ms observed against the pooler), which must not
    # masquerade as contention. Grace = a quarter of the budget, clamped to
    # [250ms, 1500ms].
    local grace_ms=$(( WAIT_S * 250 ))
    (( grace_ms > 1500 )) && grace_ms=1500
    (( grace_ms < 250 )) && grace_ms=250
    if (( announced == 0 && now - start_ms >= grace_ms )); then
      printf 'DEV_SUITE_MUTEX_WAITING identity=%s budget=%ss\n' "$IDENTITY" "$WAIT_S"
      announced=1
    fi
    sleep 0.1
  done
}

release() {
  local pid=""
  if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    rm -f "$PID_FILE" "$SQL_FILE" "$OUT_FILE" "$ERR_FILE"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
    echo "DEV_SUITE_MUTEX_RELEASED identity=$IDENTITY"
  else
    echo "DEV_SUITE_MUTEX_RELEASED (nothing held) identity=$IDENTITY"
  fi
  return 0
}

probe() {
  if ! resolve_conn; then
    echo "DEV_SUITE_MUTEX_PROBE_UNAVAILABLE reason=no_database_url"
    return 0
  fi
  local holder
  holder=$(holder_identity "$CONN_URL" || true)
  if [[ -n "$holder" ]]; then
    echo "DEV_SUITE_MUTEX_HELD_BY $holder"
  else
    echo "DEV_SUITE_MUTEX_FREE"
  fi
}

case "${1:-}" in
  acquire) acquire ;;
  release) release ;;
  probe)   probe ;;
  -h|--help|help|"") usage ;;
  *) echo "FATAL: unknown subcommand '$1'" >&2; usage >&2; exit 2 ;;
esac
