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
# Lock mechanics: ALWAYS pg_advisory_xact_lock (transaction-scoped) — over
# DATABASE_URL_POOLER when set, else DATABASE_URL. Xact scope is the only
# safe shape over a transaction-mode pooler: the pooler pins the backend for
# the life of the transaction and the lock survives pooler hand-off. Xact
# scope is equally correct on a direct connection, so there is deliberately
# NO session-scoped arm: the session-lock-over-pooler leak class (a still-
# locked session handed to an unrelated renter) is unexpressible here rather
# than merely refused.
#
# RELEASE LATENCY, load-bearing: a single pg_sleep(HOLD_S) parks the backend
# in a WaitLatch that never touches the client socket — Postgres learns of
# client death only at the NEXT socket I/O, so a killed psql would leave the
# xact lock granted for the whole sleep remainder (up to ~19.5min — a zombie
# hold, the very thing this design claims not to have). The holder instead
# parks on a column of pg_sleep(10) statements: each statement boundary
# writes a result row, and the first write to a dead socket fails (EPIPE/
# RST), aborting the transaction and releasing the lock within ~10-20s. No
# heartbeat machinery and no GUC dependency — works on every Postgres.
#
# The lock is held by a background `psql` parked on those chunked sleeps for
# the duration of the critical section. SURVIVAL INVARIANT: the holder must
# outlive the GitHub Actions step that spawned it — non-interactive bash does not SIGHUP
# background children on exit and the runner does not reap orphans between
# steps (observed live: holder survives the acquire→release boundary). If a
# future runner ever reaps orphans between steps the run silently
# unserializes — `release` emits DEV_SUITE_MUTEX_HOLDER_LOST when the holder
# pid is already gone, so a reap is greppable in the log.
#
# Wait design: `acquire` polls the lock state on TRANSIENT connections (each
# probe returns its pooled backend between polls) and only spawns the
# blocking holder once the lock reads free. Parking the blocking holder for
# the whole budget would pin one pooled backend per contended waiter for up
# to WAIT_S — a burst of contended runs could exhaust the pool and starve the
# suite the lock exists to protect.
#
# Holder SQL pins statement_timeout/lock_timeout/idle_in_transaction_session_
# timeout to 0 inside the transaction. Without the pins a role- or
# database-level timeout (config this repo does not own) would cancel the
# pg_sleep or the blocking lock call mid-hold — psql exits, the next chunked
# result write then EPIPEs on the dead socket and the transaction aborts,
# releasing the lock — and the suite continues unserialized while believing
# it holds the mutex.
#
# Failure policy is deliberate (see the plan):
#   - lock wait budget exhausted -> DEV_SUITE_MUTEX_CONTENDED_PROCEEDING and
#     exit 0 (fail-OPEN with a loud banner). A hard refusal would recreate the
#     required-check queue starvation that killed repo-wide concurrency
#     (#7986/#8048). The drift probes downstream are the fail-closed layer for
#     authoritative refs. NOTE: a full-budget wait (WAIT_S + up to ~30s of
#     probe overshoot) after ~2-3min of pre-acquire setup leaves ~8-10min of
#     the timeout-minutes:15 job for a section that runs 5-9min — a CONTENDED
#     run is likely to finish but is not guaranteed to. The banner is the
#     signal; completion is not guaranteed.
#   - missing/unusable inputs -> DEV_SUITE_MUTEX_UNAVAILABLE + exit 0. The mutex
#     is an orchestration primitive, not a hard gate; the suite must never be
#     red because the lock primitive itself was unreachable.
#
# Banner tokens (asserted by tests/scripts/test-dev-suite-mutex.sh and greppable
# in run logs):
#   DEV_SUITE_MUTEX_WAITING                 lock confirmed held; waiting
#   DEV_SUITE_MUTEX_ACQUIRED wait_ms=<N>    lock held (always mode=xact)
#   DEV_SUITE_MUTEX_CONTENDED_PROCEEDING    budget exhausted, proceeding anyway
#   DEV_SUITE_MUTEX_RELEASED                release ran (idempotent)
#   DEV_SUITE_MUTEX_HOLDER_LOST             holder pid already dead/recycled at
#                                           release — the section may have run
#                                           unserialized
#   DEV_SUITE_MUTEX_RELEASE_FAILED          holder survived TERM+KILL
#   DEV_SUITE_MUTEX_UNAVAILABLE             primitive unusable, proceeding
#   probe-only:
#   DEV_SUITE_MUTEX_HELD_BY <app>           holder's application_name. The
#                                           holder re-asserts it server-side via
#                                           SET LOCAL (transaction-mode
#                                           Supavisor masks the startup-packet
#                                           PGAPPNAME); if a 'Supavisor' value
#                                           ever appears the mask won and the
#                                           banner still proves a holder exists
#   DEV_SUITE_MUTEX_FREE                    no holder
#   DEV_SUITE_MUTEX_PROBE_UNAVAILABLE       could not ask (no URL/query failed)
#   DEV_SUITE_MUTEX_HELD is the SQL-side marker the holder writes to holder.out
#   after the lock is granted — it never appears in run logs.
#
# Env:
#   DATABASE_URL_POOLER          preferred connection (xact lock)
#   DATABASE_URL                 fallback connection (same xact lock, direct)
#   DEV_SUITE_MUTEX_IDENTITY     PGAPPNAME value — ref/run identity only, no
#                                secrets. Put the run id FIRST: PGAPPNAME
#                                truncates at 63 bytes, tail-first.
#   DEV_SUITE_MUTEX_WAIT_S       wait budget before CONTENDED (default 180 —
#                                sized so a full-budget wait still leaves
#                                ~8-10min of the timeout-minutes:15 job for
#                                a 5-9min section; raising it erodes that
#                                margin, see the note above)
#   DEV_SUITE_MUTEX_HOLD_S       holder's pg_sleep ceiling (default 1170 —
#                                must EXCEED the job's timeout-minutes:15 so
#                                the holder outlives any in-job cancellation;
#                                raising the job timeout past ~19.5min requires
#                                raising this in step)
#   DEV_SUITE_MUTEX_STATE_DIR    per-run state dir (default RUNNER_TEMP/TMPDIR
#                                + GITHUB_RUN_ID, or local-<caller pid> when
#                                run outside CI — the per-invoker suffix keeps
#                                two concurrent local/agent sessions from
#                                treating each other's live holder as stale).
#                                Local caveat: `doppler run -- … acquire` and
#                                a separate `… release` get different caller
#                                pids — wrap both in ONE invocation or set
#                                this var explicitly.
#   DEV_SUITE_MUTEX_DISABLE      =1 disables the mutex (emergency valve;
#                                UNAVAILABLE reason=disabled)
#
# Threat model: the credentialed URL sits on the holder's argv and its
# environ carries the Doppler-injected secrets. Safe today because GitHub-
# hosted runners are single-tenant per job and the PR-controlled code in the
# job already executes inside `doppler run` with the same env. If runners go
# self-hosted/shared, revisit argv/env exposure AND the state-dir guards.
set -uo pipefail

MUTEX_NAME='tenant_integration_dev_suite'
MARKER='DEV_SUITE_MUTEX_HELD'
WAIT_S="${DEV_SUITE_MUTEX_WAIT_S:-180}"
HOLD_S="${DEV_SUITE_MUTEX_HOLD_S:-1170}"
# The local fallback discriminates on the CALLING shell's pid: sequential
# acquire/release invocations from one session share it, while two concurrent
# agent/operator sessions get distinct dirs — without it a second session's
# acquire would "clean up" the first session's live holder.
STATE_DIR="${DEV_SUITE_MUTEX_STATE_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dev-suite-mutex-${GITHUB_RUN_ID:-local-$PPID}}"
PID_FILE="$STATE_DIR/holder.pid"
SQL_FILE="$STATE_DIR/holder.sql"
OUT_FILE="$STATE_DIR/holder.out"
ERR_FILE="$STATE_DIR/holder.err"
CONN_URL=""

# Identity is stamped into PGAPPNAME AND a SET LOCAL application_name literal;
# strip ASCII control bytes AND the multi-byte UTF-8 separators
# (U+2028/2029/200B/FEFF/NEL — bash `tr` is byte-oriented, so the second stage
# is sed on the byte sequences, same pattern as tenant-integration.yml's
# env_safe strip) so a crafted value cannot smuggle an annotation line into
# the run log. The final pass maps everything outside a banner/SQL-safe set
# to '-' — no spaces (banner key=value fields stay parseable) and no single
# quote (the SQL literal stays closed).
IDENTITY=$(printf '%s' "${DEV_SUITE_MUTEX_IDENTITY:-ti-unknown}" \
  | LC_ALL=C tr -d '\000-\037\177' \
  | sed -E 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g; s/\xc2\x85//g' \
  | LC_ALL=C tr -c 'A-Za-z0-9._/-' '-')
[[ -n "$IDENTITY" ]] || IDENTITY='ti-unknown'
[[ "$WAIT_S" =~ ^[0-9]+$ ]] || WAIT_S=180
[[ "$HOLD_S" =~ ^[0-9]+$ ]] || HOLD_S=1170
(( HOLD_S >= 1 )) || HOLD_S=1170  # 0 would emit no hold at all -> instant release

usage() {
  cat <<'EOF'
Usage: dev-suite-mutex.sh acquire|release|probe

  acquire   take the dev-suite advisory lock (bounded wait, fail-open)
  release   drop the lock held by this runner (idempotent, safe under if:always())
  probe     report the current holder's application_name, or DEV_SUITE_MUTEX_FREE

Exit contract: acquire/release/probe ALWAYS exit 0 (fail-open) — the only
non-zero exit is 2, for a usage error or a REFUSED DEV_SUITE_MUTEX_STATE_DIR
(empty/relative/../-bearing; the guard exits 2 rather than write under CWD).
rc is uninformative; grep the banners:

  DEV_SUITE_MUTEX_WAITING / ACQUIRED wait_ms=<N> /
  CONTENDED_PROCEEDING / RELEASED / HOLDER_LOST / RELEASE_FAILED /
  UNAVAILABLE / HELD_BY <app> / FREE / PROBE_UNAVAILABLE

Env: DATABASE_URL_POOLER (preferred), DATABASE_URL (direct fallback — the
lock is transaction-scoped on BOTH paths, so a direct URL pointing at the
pooler is still safe), DEV_SUITE_MUTEX_IDENTITY, DEV_SUITE_MUTEX_WAIT_S,
DEV_SUITE_MUTEX_HOLD_S, DEV_SUITE_MUTEX_STATE_DIR, DEV_SUITE_MUTEX_DISABLE.
EOF
}

_now_ms() {
  local v
  v=$(date +%s%3N 2>/dev/null || true)
  [[ "$v" =~ ^[0-9]+$ ]] || v=$(( $(date +%s) * 1000 ))
  printf '%s\n' "$v"
}

# resolve_conn — set CONN_URL. Pooler preferred, direct fallback; the lock is
# transaction-scoped on BOTH paths so there is no mode to resolve and no
# session-over-pooler refusal to enforce.
resolve_conn() {
  if [[ -n "${DATABASE_URL_POOLER:-}" ]]; then
    CONN_URL="$DATABASE_URL_POOLER"; return 0
  fi
  if [[ -n "${DATABASE_URL:-}" ]]; then
    CONN_URL="$DATABASE_URL"; return 0
  fi
  return 1
}

# Bounded psql: PGCONNECT_TIMEOUT covers connect stalls, -w forbids password
# prompts, and `timeout` (where present — GNU coreutils, absent on macOS)
# covers post-connect stalls for the short probe queries. A wrapper function,
# not a `"${TIMEOUT_CMD[@]}"` array — an EMPTY array under `set -u` aborts on
# bash 3.2 (stock macOS), exactly the platform the no-timeout arm exists for.
with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 15 "$@"
  else
    "$@"
  fi
}

# sanitize_field — DB-returned text destined for a GH annotation: collapse all
# control characters (incl. CR/LF and the multi-byte UTF-8 separators) so it
# cannot inject a workflow command line.
sanitize_field() {
  LC_ALL=C tr '\r\n\t' '   ' | LC_ALL=C tr -d '\000-\037\177' \
    | sed -E 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g; s/\xc2\x85//g' \
    | LC_ALL=C tr -s ' '
}

# `assert_fixture_dir` refuses a RELATIVE (or empty, or `..`-bearing) STATE_DIR
# before the redirects below can root writes at the caller's CWD — the P1b
# guard (fixture-relative-assert.test.sh) recognises only this helper, executed
# as a statement in the writing function. Byte-identical to the canonical
# definition in plugins/soleur/test/test-helpers.sh, whose equality fixture-
# dir-operand-assert.test.sh asserts across every tracked copy; do not reword
# it here alone. Copied rather than sourced because this is a production
# script, not a suite.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

write_holder_sql() {
  assert_fixture_dir "$STATE_DIR"
  # The timeout pins are load-bearing: a role/database-level statement_timeout
  # would cancel pg_sleep mid-hold and release the lock silently; a
  # lock_timeout would cap the blocking acquire far below WAIT_S. SET LOCAL
  # scopes the pins to this transaction. idle_in_transaction_session_timeout
  # covers PG14+ idle-txn reapers.
  # SET LOCAL application_name is best-effort holder attribution: Supavisor
  # masks the startup-packet PGAPPNAME, but this GUC is set server-side and
  # surfaces in pg_stat_activity while the transaction pins the backend.
  # IDENTITY is charset-normalized at the top of this script — it can never
  # contain a single quote, so the literal stays closed.
  # hashtextextended matches the repo's advisory-key precedent (migrations
  # 029/093/116/133); the 64-bit key keeps the single-key objsubid=1 space
  # free of foreign-lock collisions.
  {
    cat <<SQL
BEGIN;
SET LOCAL statement_timeout = 0;
SET LOCAL lock_timeout = 0;
SET LOCAL idle_in_transaction_session_timeout = 0;
SET LOCAL application_name = '$IDENTITY';
SELECT pg_advisory_xact_lock(hashtextextended('$MUTEX_NAME', 0));
SELECT '$MARKER' AS marker;
SQL
    # NOT one pg_sleep($HOLD_S) — a parked backend never touches the client
    # socket mid-statement, so a killed psql would leave the lock granted
    # until the sleep ended (zombie hold, ~19.5min). Chunked statements make
    # the backend write a result every ~10s; the first write to a dead
    # socket fails and the transaction aborts — the lock actually releases.
    local remaining=$HOLD_S chunk
    while (( remaining > 0 )); do
      chunk=$(( remaining > 10 ? 10 : remaining ))
      printf 'SELECT pg_sleep(%s);\n' "$chunk"
      remaining=$(( remaining - chunk ))
    done
    printf 'COMMIT;\n'
  } >"$SQL_FILE"
}

# holder_identity — application_name(s) of sessions holding our advisory lock.
# Prints nothing (rc 0) when free; rc non-zero on query failure. The objsubid
# and database pins keep a same-key lock in another database (or a two-key
# objsubid=2 lock) from being misreported as our holder — pg_locks is
# cluster-wide.
holder_identity() {
  local url="$1" raw
  # env(1) cannot exec a shell function; the var-prefix on the call exports the
  # same variables into with_timeout and through to the psql child.
  raw=$(PGAPPNAME="${IDENTITY}-probe" PGCONNECT_TIMEOUT=10 \
    with_timeout psql "$url" -w --no-psqlrc -tAq -v ON_ERROR_STOP=1 -c "
    SELECT string_agg(COALESCE(NULLIF(a.application_name,''),'<unset>'), ', ')
    FROM pg_locks l
    JOIN pg_stat_activity a ON a.pid = l.pid
    WHERE l.locktype = 'advisory' AND l.granted AND l.objsubid = 1
      AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
      AND l.classid = ((hashtextextended('$MUTEX_NAME', 0) >> 32) & 4294967295)
      AND l.objid   = (hashtextextended('$MUTEX_NAME', 0) & 4294967295)
  " 2>/dev/null) || return 1
  printf '%s' "$raw" | sanitize_field
}

emit_contended() {
  local holder
  holder=$(holder_identity "$CONN_URL" || true)
  # holder= is application_name — SET LOCAL attribution restores the run
  # identity on the pooler path, but if it ever reads 'Supavisor' (or the
  # probe failed) the actionable attribution is the concurrent run, not
  # `probe` again: point next= there directly.
  printf '::warning::DEV_SUITE_MUTEX_CONTENDED_PROCEEDING holder=%s budget=%ss next="gh run list --workflow tenant-integration.yml (find the concurrent run)" -- wait budget exhausted; proceeding unserialized\n' \
    "${holder:-unknown}" "$WAIT_S"
}

acquire() {
  if [[ "${DEV_SUITE_MUTEX_DISABLE:-0}" == "1" ]]; then
    echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=disabled -- DEV_SUITE_MUTEX_DISABLE=1; proceeding unserialized (fail-open)"
    return 0
  fi
  if ! resolve_conn; then
    echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=no_database_url -- proceeding unserialized (fail-open)"
    return 0
  fi
  # A relative STATE_DIR would root every holder-file write below at the
  # caller's CWD; refuse it before install -d can create it.
  assert_fixture_dir "$STATE_DIR"
  if [[ -L "$STATE_DIR" ]] || ! install -d -m 700 "$STATE_DIR" 2>/dev/null; then
    echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=state_dir_unwritable -- proceeding unserialized (fail-open)"
    return 0
  fi
  # Defensive: a stale pid file on this runner means a prior acquire leaked.
  [[ -f "$PID_FILE" ]] && release >/dev/null 2>&1 || true

  local start_ms deadline_ms now announced=0 next_beat_ms holder tail_err pid elapsed f
  start_ms=$(_now_ms)
  deadline_ms=$(( start_ms + WAIT_S * 1000 ))
  next_beat_ms=$(( start_ms + 60000 ))

  # Phase 1 — poll the lock state on transient connections until it reads
  # free. Each probe returns its pooled backend between polls, so contended
  # waiters do not pin a backend for the whole budget.
  while :; do
    now=$(_now_ms)
    if (( now >= deadline_ms )); then
      emit_contended
      return 0
    fi
    if holder=$(holder_identity "$CONN_URL"); then
      [[ -z "$holder" ]] && break
      if (( announced == 0 )); then
        printf 'DEV_SUITE_MUTEX_WAITING identity=%s holder=%s budget=%ss\n' \
          "$IDENTITY" "$holder" "$WAIT_S"
        announced=1
      elif (( now >= next_beat_ms )); then
        printf 'DEV_SUITE_MUTEX_WAITING identity=%s holder=%s waited=%ds\n' \
          "$IDENTITY" "$holder" "$(( (now - start_ms) / 1000 ))"
        next_beat_ms=$(( now + 60000 ))
      fi
      sleep 2
    else
      # Probe failed — fall through to the blocking path; the holder spawn
      # fail-opens (holder_exited) if the DB is genuinely unreachable.
      break
    fi
  done

  # Phase 2 — the lock reads free (or the probe failed): spawn the holder.
  # If we lost a grab race it blocks until grant; the same deadline applies.
  # NOTE: advisory-lock grant order is not FIFO — under a free-boundary herd,
  # K waiters each pin one backend on the blocking call and a loser may
  # CONTENDED-retry repeatedly. Bounded by WAIT_S and the holder ceiling;
  # accepted (Postgres gives no grant-fairness primitive to do better).
  write_holder_sql
  for f in "$PID_FILE" "$SQL_FILE" "$OUT_FILE" "$ERR_FILE"; do
    [[ -L "$f" ]] && rm -f "$f"
  done
  : >"$OUT_FILE"; : >"$ERR_FILE"
  PGAPPNAME="$IDENTITY" PGCONNECT_TIMEOUT=10 psql "$CONN_URL" -w --no-psqlrc -tAq -v ON_ERROR_STOP=1 \
    -f "$SQL_FILE" >"$OUT_FILE" 2>"$ERR_FILE" &
  pid=$!
  printf '%s\n' "$pid" >"$PID_FILE"

  # Phase-2 grace for the WAITING banner: a free acquire still pays connect
  # latency (~750ms observed against the pooler), which must not masquerade as
  # contention. Grace = a quarter of the budget, clamped to [250ms, 1500ms].
  # Only reached when the probe failed or we lost a grab race — phase 1 emits
  # WAITING as soon as a holder is observed.
  local grace_ms=$(( WAIT_S * 250 ))
  (( grace_ms > 1500 )) && grace_ms=1500
  (( grace_ms < 250 )) && grace_ms=250
  while :; do
    # Liveness FIRST: a holder that flushed the marker then died would
    # otherwise report ACQUIRED over an already-released lock.
    if ! kill -0 "$pid" 2>/dev/null; then
      tail_err=$(tail -n 3 "$ERR_FILE" 2>/dev/null | sanitize_field || true)
      echo "::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=holder_exited detail=${tail_err:-unknown} -- proceeding unserialized (fail-open)"
      rm -f "$PID_FILE"
      return 0
    fi
    # Marker visibility depends on psql flushing each statement's output to
    # holder.out before it reaches pg_sleep — live-verified (~750ms ACQUIRED);
    # if a psql ever block-buffered, every acquire would degrade to
    # CONTENDED_PROCEEDING, loudly but unserialized.
    if grep -qF "$MARKER" "$OUT_FILE" 2>/dev/null; then
      elapsed=$(( $(_now_ms) - start_ms ))
      printf 'DEV_SUITE_MUTEX_ACQUIRED wait_ms=%d identity=%s\n' \
        "$elapsed" "$IDENTITY"
      return 0
    fi
    now=$(_now_ms)
    if (( now >= deadline_ms )); then
      # Same bounded reap as release(): TERM, ~1s grace, KILL — a bare
      # `wait` here could hang past the budget if the holder wedged in an
      # uninterruptible socket state.
      kill "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
      emit_contended
      return 0
    fi
    if (( announced == 0 && now - start_ms >= grace_ms )); then
      printf 'DEV_SUITE_MUTEX_WAITING identity=%s budget=%ss\n' "$IDENTITY" "$WAIT_S"
      announced=1
    elif (( announced == 1 && now >= next_beat_ms )); then
      printf 'DEV_SUITE_MUTEX_WAITING identity=%s waited=%ds\n' "$IDENTITY" "$(( (now - start_ms) / 1000 ))"
      next_beat_ms=$(( now + 60000 ))
    fi
    sleep 0.1
  done
}

# is_our_holder — the pid file records a pid written by the acquire step's
# shell, which has since exited; by release time the pid may have been
# recycled by an unrelated process on this runner. Verify the live process is
# actually our psql before signaling it — a bare kill minutes later can land
# on whatever now owns the pid (precedent: scripts/lib/test-contention.sh's
# signal-only-what-we-own rule, adapted for a cross-step orphan).
is_our_holder() {
  local pid="$1" cmdline=""
  if [[ -r "/proc/$pid/cmdline" ]]; then
    cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)
  else
    # Non-Linux fallback (operator macOS runs): ps -o args works there.
    cmdline=$(ps -p "$pid" -o args= 2>/dev/null || true)
  fi
  # Unverifiable is NOT ours: a pid we cannot inspect is never signalled —
  # the holder self-terminates at the pg_sleep ceiling anyway. Fail-safe,
  # never "best-effort" toward the kill.
  [[ -n "$cmdline" && "$cmdline" == *psql* && "$cmdline" == *"$SQL_FILE"* ]]
}

release() {
  local pid="" pid_safe
  # Same guard as the writing path: a relative STATE_DIR would root the
  # reads/removes below at the caller's CWD.
  assert_fixture_dir "$STATE_DIR"
  if [[ ! -f "$PID_FILE" ]]; then
    echo "DEV_SUITE_MUTEX_RELEASED (nothing held) identity=$IDENTITY"
    return 0
  fi
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  pid_safe=$(printf '%s' "$pid" | sanitize_field)
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && is_our_holder "$pid"; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE" "$SQL_FILE" "$OUT_FILE" "$ERR_FILE"
    if kill -0 "$pid" 2>/dev/null; then
      echo "::warning::DEV_SUITE_MUTEX_RELEASE_FAILED pid=$pid survived TERM+KILL -- the hold still ends at the pg_sleep ceiling or the next result write to a dead socket"
    else
      echo "DEV_SUITE_MUTEX_RELEASED identity=$IDENTITY"
    fi
  elif [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    # Alive but not our psql — the pid was recycled; our holder already died
    # and the lock released when its next result write hit the dead socket.
    # Do NOT signal the current owner.
    rm -f "$PID_FILE" "$SQL_FILE" "$OUT_FILE" "$ERR_FILE"
    echo "::warning::DEV_SUITE_MUTEX_HOLDER_LOST pid=$pid_safe recycled -- holder died before release; the critical section may have run unserialized"
  else
    rm -f "$PID_FILE" "$SQL_FILE" "$OUT_FILE" "$ERR_FILE"
    echo "::warning::DEV_SUITE_MUTEX_HOLDER_LOST pid=${pid_safe:-unknown} exited -- holder died before release; the critical section may have run unserialized"
  fi
  return 0
}

probe() {
  if ! resolve_conn; then
    echo "DEV_SUITE_MUTEX_PROBE_UNAVAILABLE reason=no_database_url"
    return 0
  fi
  local holder rc=0
  holder=$(holder_identity "$CONN_URL") || rc=$?
  if (( rc != 0 )); then
    echo "DEV_SUITE_MUTEX_PROBE_UNAVAILABLE reason=query_failed"
    return 0
  fi
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
