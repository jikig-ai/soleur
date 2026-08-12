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

# --- #7228 (3.5/3.6): `done` must be DERIVED FROM A PROBE, never asserted -------------------
# THE DEFECT. `done` was set immediately after `start_server`, which is `systemctl start` — a
# call that returns success when systemd ACCEPTED the unit, not when inngest bound :8288. So
# `done` asserted a live host condition it never measured. Worse, the flag lives in Doppler,
# which OUTLIVES THE HOST: the 2026-07-30 host recorded `done`, never bound, and the flag stayed
# `done` for twelve days across a host that served nothing. That is why nothing self-healed, and
# it is the ADR-100 Decision 6a defect this PR amends the ADR to record.
#
# The rule extracted from it: a terminal state asserting a live host condition must be re-derived
# from a probe and must not outlive what it asserts.
#
# TWO conditions, because either alone is satisfiable by a broken host:
#   /health 200      — the listener is bound. Alone, it is satisfied by a server serving an EMPTY
#                      registry, which during a cutover is the difference between "healthy" and
#                      "the scheduler owns nothing".
#   non-empty registry — the scheduler actually adopted the functions. Alone, it cannot be
#                      reached at all without a listener, but asserting both makes the failure
#                      DISTINGUISHABLE in the marker, which is what an operator reads.
#
# BOUNDED WINDOW, not a single shot: inngest takes seconds to bind after `systemctl start`, so a
# single immediate probe would fail on a perfectly healthy cutover. Bounded rather than unbounded
# because this runs from a 30s timer — an unbounded wait would stack overlapping oneshots.
CUTOVER_HEALTH_URL="${CUTOVER_HEALTH_URL:-http://127.0.0.1:8288/health}"
CUTOVER_GQL_URL="${CUTOVER_GQL_URL:-http://127.0.0.1:8288/v0/gql}"
# THE WINDOW MUST DOMINATE THE SERVER'S POLL INTERVAL, and 90s did not. The dedicated host
# does not learn its registry at startup — it DISCOVERS it by polling the web-platform's
# --sdk-url, and inngest-bootstrap.sh starts the unit with `--poll-interval 60`. At a 90s
# window that is 1.5 poll cycles: a perfectly healthy cutover whose registry populates on the
# second poll is read as EMPTY and driven to TERMINAL `aborted`, which is not retryable and
# needs an operator re-arm. The failure is indistinguishable from a genuinely dark host.
# 240s is four poll cycles, so two consecutive missed polls still converge.
# The relationship is the thing that matters, not the number: inngest-cutover-flip.test.sh
# pins `default >= 3 x the --poll-interval literal`, extracting BOTH operands by shape so
# neither side can drift silently. Raising the window costs nothing on the failure path — the
# FSM is a systemd oneshot and its timer cannot re-trigger while the unit is active, so a
# longer wait delays a verdict rather than stacking invocations.
CUTOVER_VERIFY_WINDOW_S="${CUTOVER_VERIFY_WINDOW_S:-240}"
CUTOVER_VERIFY_INTERVAL_S="${CUTOVER_VERIFY_INTERVAL_S:-3}"

# DRIFT-PINNED (#7228). Byte-identical to inngest-registry-probe.sh's FUNCTIONS_GQL_QUERY, and
# inngest-consumer-probe.test.sh's drift block asserts all THREE copies agree. It is inlined here
# rather than sourced because inngest-registry-probe.sh is delivered to the WEB host only
# (server.tf + the infra-config push); this FSM runs on the DEDICATED host, where that file does
# not exist. Sourcing a file that is not there would make the `done` gate fail-closed on an
# asset-delivery problem — i.e. wedge a cutover for a reason unrelated to whether the host serves.
# shellcheck disable=SC2016  # GraphQL query, not a shell expansion
readonly FUNCTIONS_GQL_QUERY='query RegistryProbe { functions { id } }'

# --- curl: fixture seam CUTOVER_CURL_CMD else the real binary. Seamed at the COMMAND, not at
# the verdict, so the bounded-window logic below stays under test rather than stubbed away.
curl_cmd() {
  if [[ -n "${CUTOVER_CURL_CMD:-}" ]]; then
    "$CUTOVER_CURL_CMD" "$@"
  else
    curl "$@"
  fi
}

# Echoes a reason token on FAILURE and returns non-zero; silent + 0 when the host truly serves.
# Reason tokens are stable short strings: scripts/cutover-inngest.sh greps the marker's literal
# `"reason":"<token>"`, so they are part of that contract and variable detail belongs in the
# sibling logger line, never in the token.
# BOTH conditions are retried against ONE deadline. An earlier revision broke out of the loop as
# soon as /health returned 200 and then sampled the registry EXACTLY ONCE — which made the whole
# window inapplicable to the condition it was raised for. /health comes up within seconds of
# `systemctl start`, but the registry is DISCOVERED by polling the web-platform's --sdk-url at
# --poll-interval 60, so a single shot taken seconds after start reads EMPTY on a perfectly
# healthy cutover and drives the flag to terminal `aborted`. That is the exact scenario the
# window exists to prevent, and the loop shape was silently exempting it.
#
# The reported reason is the LAST observed failure, not the first: a host whose listener comes up
# and whose registry never populates should report verify-registry-empty (what is actually wrong),
# not verify-health (what was wrong at t=0).
verify_serving() {
  local deadline=$(( SECONDS + CUTOVER_VERIFY_WINDOW_S ))
  local code="" body count last="verify-health"
  while :; do
    code="$(curl_cmd -s -o /dev/null -w '%{http_code}' --max-time 5 "$CUTOVER_HEALTH_URL" 2>/dev/null || true)"
    if [[ "$code" == "200" ]]; then
      # The listener is up. Now: has it adopted the registry? A well-formed but EMPTY function
      # list is a server that serves and owns nothing — every reachability check passes and the
      # cutover has silently moved zero work.
      body="$(curl_cmd -s --max-time 10 -H 'Content-Type: application/json' \
        --data-binary "$(jq -nc --arg q "$FUNCTIONS_GQL_QUERY" '{query:$q}')" \
        "$CUTOVER_GQL_URL" 2>/dev/null || true)"
      # jq indexes null as null, so an `{"errors":…,"data":null}` envelope yields type "null" and
      # lands on the non-numeric arm rather than being read as a count of zero.
      count="$(printf '%s' "$body" | jq -r '(.data.functions // null) | if type == "array" then length else "nan" end' 2>/dev/null || true)"
      case "$count" in
        ''|*[!0-9]*) last="verify-registry-unreadable" ;;
        *) [[ "$count" -gt 0 ]] && return 0; last="verify-registry-empty" ;;
      esac
    else
      last="verify-health"
    fi
    (( SECONDS >= deadline )) && { printf '%s' "$last"; return 1; }
    sleep "$CUTOVER_VERIFY_INTERVAL_S"
  done
}

# --- #7228 (3.6): the done-OWNER marker, on the ROOT DISK -----------------------------------
# THE HAZARD. The cutover flag lives in Doppler, which OUTLIVES THE HOST, so `done` says a flip
# completed without saying on WHICH machine — and a REPLACED host boots into its predecessor's
# `done`, which the flip guard's allowlist reads as ALLOW. That reaches the second-prod-scheduler
# state P1-5 exists to prevent THROUGH the guard rather than around it.
#
# EXISTENCE, NOT IDENTITY. The question the guard must answer is not "which instance earned this
# `done`" but the strictly weaker "did the machine currently booting earn it?" — a yes/no. So the
# record is an empty file on the ROOT DISK, whose persistence semantics ARE that predicate:
#   reboot after a legitimate flip -> present -> ALLOW   (root disk survives a reboot)
#   host replaced / re-imaged      -> absent  -> BLOCK   (fresh root disk, by construction)
# /mnt/data is the ONLY mount on this host (cloud-init-inngest.yml), so /var/lib has exactly
# host-lifetime persistence. This is the same durable-vs-ephemeral axis the flush latch reasons
# about one tier up: that latch lives on /mnt/data BECAUSE it must survive a replace; this marker
# lives on the root disk BECAUSE it must NOT.
#
# WHY NOT A DOPPLER KEY (rejected at review — it boot-bricks the host it protects). A new
# `INNGEST_CUTOVER_DONE_INSTANCE` secret in soleur-inngest/prd is admitted by NOTHING: the boot
# isolation self-check in cloud-init-inngest.yml is an EXACT-SET match
# (`n_total -ne n_inngest` -> FATAL -> "refusing to bootstrap"), so from the first stamped flip
# onward EVERY re-provision of this host would FATAL at boot — with no Vector, no inngest-server
# and no flip timer — precisely when an operator is trying to recover it. That is byte-for-byte
# the #6178 recurrence the same file's comment already records for CUTOVER_FLIP. Admitting the
# key to the allowlist would work, and would make this guard's correctness depend on remembering
# an allowlist in a different file; the marker has no such coupling. It also drops the IMDS call
# (a network dependency on a boot-critical path) and the whole verify-instance-unknown arm.
#
# Nothing here touches the flag VALUE, so the guard's exact `case` match on `done` and
# inngest-server-flip-guard.test.sh's `flag_set`-literal EXPECTED_START_SITES derivation are
# both untouched — which was the original constraint.
DONE_OWNER_MARKER="${CUTOVER_DONE_OWNER_MARKER:-/var/lib/inngest-cutover/done-owner}"

# Not `|| true`: an unrecordable marker leaves the guard unable to tell this host's `done` from
# an inherited one, which is the exact state the marker exists to end. Fail LOUD.
record_done_owner() {
  local dir
  dir="$(dirname "$DONE_OWNER_MARKER")"
  mkdir -p "$dir" || return 1
  : > "$DONE_OWNER_MARKER" || return 1
}

# --- The single place `done` may be reached from. Both start sites call THIS, never flag_set
# directly, so a future arm cannot acquire an unverified `done` by copying the shorter form.
# It deliberately contains NO `start_server` call and NO `flag_set` before the probe, so
# inngest-server-flip-guard.test.sh's start-site derivation is unaffected (still 2 sites, both
# attributing to `flushed`).
# EVERY emit_state below passes its reason as a STRING LITERAL, never through a variable. The
# #6178 emitter-parity test derives the anchor vocabulary by extracting the literal 3rd positional
# of each emit_state call, and scripts/cutover-inngest.sh's `--grep '"reason":"…"'` set is pinned
# against it. A `"$reason"` here extracts as the token `$reason`, which matches no row — the
# anchor would then silently skip these rows and return a LATER one, NARROWING the coexistence
# window, which is the unsafe direction that anchor exists to prevent.
verify_or_abort() {
  local dbsize="$1" reason=""
  if ! reason="$(verify_serving)"; then
    # STOP THE SERVER FIRST. `start_server` has already succeeded at every call site, and
    # inngest-server.service is Type=simple with Restart=on-failure — so returning here without
    # stopping it leaves a RUNNING scheduler while the flag records `aborted`. On the
    # verify-registry-empty arm that scheduler has already adopted PROD Postgres, and ADR-100's
    # own Context states scheduling is driven by the shared Postgres tables REGARDLESS of local
    # registration: it is a live prod scheduler the FSM has just declared dead. Worse, `aborted`
    # is outside the guard allowlist, so the process can never be legitimately restarted — but
    # it is already up, so the guard is never consulted. Every other abort in this FSM means
    # "no scheduler is running here" (dbsize-nonzero never starts; rollback stops); this arm
    # must mean the same thing or `aborted` stops being one state.
    # Best-effort: a stop failure must not prevent the flag reaching terminal, or a crash here
    # leaves the flag mid-transition and a later poll resumes into a no-flush false `done`.
    stop_server || true
    # LOUD and terminal. `aborted` (not a retry) because the 30s timer would otherwise storm,
    # and because a host that did not serve within the window needs a human to look — silently
    # retrying is how a cutover ends up believing it finished.
    # Sibling detail line, NOT the marker: emit_state's `reason` is the stable token the
    # cutover orchestrator greps, so variable detail belongs here. No backticks anywhere in
    # this string — inside double quotes they are command substitution, and the words being
    # quoted here are shell keywords.
    "${CUTOVER_LOGGER_CMD:-logger}" -t "$LOG_TAG" \
      "SOLEUR_INNGEST_CUTOVER_VERIFY_FAILED reason=$reason health_url=$CUTOVER_HEALTH_URL window_s=$CUTOVER_VERIFY_WINDOW_S — inngest-server was started but did NOT serve within the window, so it has been STOPPED, the terminal 'done' was REFUSED and the flag is 'aborted'. The host is not carrying the registry. #7228" 2>/dev/null || true
    flag_set aborted
    case "$reason" in
      verify-health)              emit_state 1 "$dbsize" "verify-health" aborted ;;
      verify-registry-empty)      emit_state 1 "$dbsize" "verify-registry-empty" aborted ;;
      verify-registry-unreadable) emit_state 1 "$dbsize" "verify-registry-unreadable" aborted ;;
      # A reason verify_serving grew without a matching arm here must still EMIT, or the one
      # path with no marker is the one nobody anticipated. Fail loud into a known token.
      *)                          emit_state 1 "$dbsize" "verify-unknown" aborted ;;
    esac
    exit 1
  fi
  # Record ownership BEFORE the flag. If the order were reversed, a crash in between would leave
  # a `done` with no owner marker — which the guard must treat as inherited, wedging a host that
  # actually served. An unrecordable marker is fatal for the same reason: see record_done_owner.
  if ! record_done_owner; then
    stop_server || true
    "${CUTOVER_LOGGER_CMD:-logger}" -t "$LOG_TAG" \
      "SOLEUR_INNGEST_CUTOVER_VERIFY_FAILED reason=verify-owner-unrecordable path=$DONE_OWNER_MARKER — the host SERVES, but its done-owner marker could not be written, so a terminal 'done' here would be indistinguishable from one INHERITED by a replacement host. Server STOPPED and refusing. #7228" 2>/dev/null || true
    flag_set aborted
    emit_state 1 "$dbsize" "verify-owner-unrecordable" aborted
    exit 1
  fi
}

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

# --- P2-d re-arm-after-flush latch (#5450 catastrophe guard; made MONOTONIC by #7228 P0-5).
#
# A flip that performed a FLUSHALL means the queue is now on LIVE prod Postgres/Redis; a stray
# flag flip back to `armed` (or `flipping`) must NEVER re-enter the flush path and wipe it.
#
# THE DEFECT THIS FIXES. The latch used to read `.flag == "done"` out of the state slot — but
# emit_state() stamps that slot on EVERY branch including the terminal no-ops, and the
# `rolled-back` arm writes {"flag":"rolled-back"} straight over the `done` record. So
# `done -> rollback -> rolled-back -> armed` ERASED the latch and re-entered the flush path
# against a live prod Redis. It failed safe only by accident: /var/lock is the ephemeral root
# disk, so a host replace wiped the slot and a genuine first flip proceeded. Relocating that slot
# onto the durable volume — the obvious "make the latch survive a replace" fix, and the one the
# first draft of this plan proposed — would have made it strictly WORSE by PERSISTING the erasure,
# converting a latch that fails safe by amnesia into one that fails unsafe by false memory.
#
# The predicate is therefore MONOTONIC — "has a FLUSHALL EVER been performed?" — and answered by
# a DISJUNCTION over two independent records:
#
#   (a) the durable latch file. Existence-based and never rewritten, so no branch can erase it,
#       and it lives on /mnt/data, the volume that SURVIVES a host replace. Survival is the whole
#       point: the replace is the operation that disarms the old latch, which is why Phase 3 has
#       to land before any replace is dispatched.
#   (b) the legacy state slot recording `done`. The COMPATIBILITY arm: a host that already
#       completed a flip before this change ships has no latch file, only a slot. Dropping this
#       arm would silently disarm the guard on exactly those hosts until their next flip. It is
#       the erasable one by construction, so it can only ever ADD refusals, never remove them.
#
# Both absent ⇒ NOT flushed, and a genuine first flip proceeds (the DBSIZE==0 assert still guards
# that path). inngest-cutover-latch.test.sh fixtures each arm ALONE — a fixture satisfying both
# at once would prove only that the set is non-empty and would stay green if either were deleted.
LATCH_FILE="${INNGEST_CUTOVER_LATCH:-/mnt/data/inngest-cutover/flip-done.latch}"
# The mountpoint the latch MUST sit behind. `${VAR-default}` (not `:-`) so an explicitly-empty
# value disables the gate for tests without also disabling it for an empty-but-set production env.
LATCH_REQUIRE_MOUNT="${INNGEST_CUTOVER_LATCH_MOUNT-/mnt/data}"

flush_already_performed() {
  [[ -e "$LATCH_FILE" ]] && return 0
  [[ -f "$STATE_FILE" ]] || return 1
  local recorded
  recorded="$(jq -r '.flag // ""' "$STATE_FILE" 2>/dev/null || printf '')"
  [[ "$recorded" == "done" ]]
}

# --- Record the durable latch. FATAL on failure, never best-effort.
#
# An unrecordable latch means the catastrophe guard is disarmed for every future poll, which is
# precisely the silent fallback cq-silent-fallback-must-mirror-to-sentry forbids — so this aborts
# to terminal `aborted` WITHOUT starting the server rather than proceeding unguarded. Aborting
# here is safe: the flush has just succeeded, so Redis is empty and a later re-arm would re-flush
# an already-empty store.
#
# The mountpoint gate is not paranoia. cloud-init mounts the volume with `|| true` and fstab
# carries `nofail`, so a FAILED mount leaves /mnt/data as an ordinary directory on the ephemeral
# root disk. A latch written there LOOKS durable and would vanish on the very replace it exists to
# survive — a guard that reports armed and is not.
#
# Append, never truncate: `>>` cannot destroy an existing record, so even a future caller that
# invokes this twice preserves the original. That is what makes the latch monotonic in the write
# path as well as in the predicate.
record_flush_latch() {
  local dbsize="$1" dir
  if [[ -n "$LATCH_REQUIRE_MOUNT" ]] && ! mountpoint -q "$LATCH_REQUIRE_MOUNT" 2>/dev/null; then
    emit_state 1 "$dbsize" "latch-unrecordable" aborted
    logger -t "$LOG_TAG" "latch-unrecordable detail=not-a-mountpoint path=${LATCH_REQUIRE_MOUNT} — a latch written here would sit on the ephemeral root disk and NOT survive a host replace" 2>/dev/null || true
    flag_set aborted
    exit 1
  fi
  dir="$(dirname "$LATCH_FILE")"
  if ! mkdir -p "$dir" 2>/dev/null; then
    emit_state 1 "$dbsize" "latch-unrecordable" aborted
    logger -t "$LOG_TAG" "latch-unrecordable detail=mkdir-failed path=${dir}" 2>/dev/null || true
    flag_set aborted
    exit 1
  fi
  if ! printf 'flushed_at=%s host=%s dbsize=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        "$(hostname 2>/dev/null || echo unknown)" "$dbsize" >> "$LATCH_FILE" 2>/dev/null; then
    emit_state 1 "$dbsize" "latch-unrecordable" aborted
    logger -t "$LOG_TAG" "latch-unrecordable detail=write-failed path=${LATCH_FILE}" 2>/dev/null || true
    flag_set aborted
    exit 1
  fi
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
  # MONOTONIC LATCH (#7228 P0-5): recorded HERE — at the flush, not at completion — because it
  # asserts "a FLUSHALL has been performed", not "the flip finished". Placing it after
  # start_server would leave a crash between the flush and the start free to re-flush a prod
  # queue on the next re-arm. FATAL if it cannot be recorded; see record_flush_latch.
  record_flush_latch "$dbsize"
  # POST-assert checkpoint (P1-5 / #5450): the flush provably succeeded (DBSIZE==0) and the
  # queue is about to be adopted by the prod scheduler. A resume from `flushed` MUST NOT
  # re-FLUSHALL — write the checkpoint BEFORE start_server so the window is covered.
  flag_set flushed
  start_server
  # #7228: `done` is now PROBE-DERIVED. verify_or_abort either verifies the host actually
  # serves and records this host as the owner, or drives the flag terminal-aborted and exits non-zero.
  # It contains no start_server call and no flag_set before its probe, so the flip-guard
  # lockstep derivation still attributes this start site to `flushed`.
  verify_or_abort "$dbsize"
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
      if flush_already_performed; then
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
      if flush_already_performed; then
        refuse_rearm_after_done
      fi
      run_preflush_flip
      ;;
    flushed)
      # POST-flush resume (#5450 trap): the flush already completed (proven by the
      # `flushed` checkpoint) and the queue is now on prod Postgres. Do NOT re-FLUSHALL;
      # just ensure inngest-server is started and complete to `done`.
      #
      # Reaching this state PROVES a FLUSHALL happened, so backfill the durable latch if it is
      # absent — the case on a host that checkpointed `flushed` before this change shipped, or
      # that crashed between the flush and the latch write. Leaving it absent here would let a
      # later re-arm flush a live prod queue, which is the whole failure this latch prevents.
      record_flush_latch ""
      start_server
      verify_or_abort ""
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
