#!/usr/bin/env bash
# The cutover orchestrator for the Inngest durable-backend Phase 2 migration (#7002).
#
# WORKFLOW-INVOKED. This file IS the body of the single `run:` step in
# .github/workflows/cutover-inngest.yml, moved out of the YAML verbatim. It reads only
# process environment supplied by that step's `env:` map (OP, WEBHOOK_SECRET, the two
# CF_ACCESS_* values, DOPPLER_TOKEN, DOPPLER_TOKEN_INNGEST_ARM, SUPABASE_ACCESS_TOKEN and
# the CUTOVER_* knobs), which a child bash inherits, so the move required no edits.
#
# WHY IT WAS MOVED. actionlint pipes every `run:` body into shellcheck over a pipe. This
# body was 118,722 bytes against a 65,536-byte pipe buffer, so actionlint blocked writing
# while shellcheck blocked reading and the process NEVER RETURNED — measured rc=124, with
# the threshold bisected to exactly the buffer size (65,043 completes, 65,564 hangs). The
# consequence was not "one file is unlinted": a bare `actionlint .github/workflows/` never
# terminated, so the repo's only workflow linter reported nothing at all, on every file.
#
# The move is behaviour-preserving by construction and is verified byte-for-byte against
# the parsed block scalar. `set -euo pipefail` below is the body's OWN first line, carried
# across unchanged — do not add a second one.
#
# `::add-mask::` still works from here: GitHub parses workflow commands from the STEP's
# stdout, which this child process inherits.
#
# RUNTIME DEPENDENCY. The workflow's `actions/checkout` step is required by ALL ops now,
# not just the arm/rollback Better Stack confirm it was originally added for. Gating it on
# `inputs.op` would break every cutover op, on a workflow_dispatch-only path where no CI
# signal would catch it. See ADR-150.
#
# NO COMPANION TEST SUITE, deliberately — a suite for a 1,596-line cutover orchestrator is
# its own project (tracked in #6753's refactor census). This is still a strict improvement:
# the body had no test AND could not be linted before; `shellcheck scripts/cutover-inngest.sh`
# now covers it. See ADR-150.
set -euo pipefail
# xtrace refusal (#7797): this script binds live credentials (WEBHOOK_SECRET, CF Access, the
# Better Stack API token, Doppler service tokens); `-x` would print them into the run log.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
BASE="https://deploy.soleur.ai/hooks"

# Shared no-SSH confirm of the on-host inngest-cutover-flip FSM terminal state via Better
# Stack Logs (source 2457081), used by op=arm (G6) and op=rollback (#6369). The emitter
# (apps/web-platform/infra/inngest-cutover-flip.sh:125-137, `emit_state exit_code dbsize
# reason flag`) puts the TERMINAL STATE in the `flag` field (done/aborted/rolled-back) and
# a CAUSE in `reason` (flip-complete/dbsize-nonzero/…) — so we key on `"flag":"<state>"`,
# NOT `reason` (which never equals `done`/`aborted`). Arg $1 = floor timestamp in the
# `betterstack-query.sh` literal `--since` form `YYYY-MM-DD HH:MM:SS` (its ClickHouse cast
# rejects the ISO `T…Z` form). Echoes EXACTLY one terminal token to stdout: done |
# rolled-back | aborted | timeout. NEVER echoes a raw Better Stack row (a value could ride
# along) — only the extracted flag token. A confirm-PATH (query) failure is announced on
# stderr distinctly from an FSM-not-terminal state, so a timeout names the right subsystem.
# The dedicated host's identity in Better Stack, as TWO fields — and both are required.
#
# `host_name` is the per-host discriminator #6396 introduced (`@@HOST_NAME@@`), and vector.toml
# says it is the sole discriminator for the ONE multiplexed Logs source 2457081. That is the
# right field to filter on and it is NOT sufficient on its own: **#6616 is OPEN — "host_name
# telemetry is lying"** — because `inngest-bootstrap.sh` sed-renders the literal
# `soleur-inngest-prd`, and a WEB host has been observed self-labelling with it.
#
# CORRECTED (#7674 review): an earlier draft of this comment blamed
# `lifecycle{ignore_changes=[user_data]}` for the stale render. That is the wrong host —
# `hcloud_server.inngest` carries `ignore_changes = [ssh_keys]` and `inngest-host.tf` says
# "Deliberately NO lifecycle.ignore_changes=[user_data]" twice, because the force-replace IS its
# reprovision path. The stale-render mechanism belongs to the WEB hosts, which is where the #6616
# mislabel actually lives. The conclusion is unchanged and the premise now names the right host.
#
# `host` is Vector's auto-derived OS hostname, which for this node is the Hetzner server name
# `hcloud_server.inngest` = `soleur-inngest`. `scripts/followthroughs/hostname-mislabel-web1-6616.sh`
# pins that as the authoritative identity, and it cannot be forged by a stale sed literal.
#
# Requiring BOTH is strictly stronger than either: under the #6616 collision a web host supplies
# a matching `host_name` and its own `host`, so the conjunction excludes it. Measured 2026-08-25:
# 84/84 flip rows carry host=soleur-inngest host_name=soleur-inngest-prd, so the conjunction is
# satisfied on every real row today — this narrows a latent fail-open, it does not narrow the
# live signal.
INNGEST_HOST="${INNGEST_HOST:-soleur-inngest}"
INNGEST_HOST_NAME="${INNGEST_HOST_NAME:-soleur-inngest-prd}"

# THE SHARED flip-FSM READER (#7674). One reader, two callers: confirm_flip_state (below) and
# _flip_liveness_count (G3.7's H signal), and — since #8054 — op=execute 2.0's two reads.
# Extracted rather than duplicated so the transport, credential config and query shape cannot
# drift between the confirm path, the gate path and the cutover's own pre-flight.
#
#   $1  --since value
#   $2  --grep term — EXACTLY ONE. Better Stack's `--grep` is OR-combined, and an OR of two
#       streams was measured (2026-09-11) returning 500 rows and ZERO probe rows: the dedicated
#       host's refuse-loop noise fills the window in ~13 minutes and starves the hourly probe
#       row out of the limit. Host isolation happens after decoding, never in `--grep`.
#   $3  --limit
#   $4  (optional) file to capture the reader's stderr into. The default discards it, as the
#       pre-#8054 reader always did; 2.0 keeps it so an `unreadable` refusal can name the CAUSE.
#       That stderr is NOT credential-free by construction — betterstack-query.sh's allowlist
#       refusal prints the derived HOST, and the transport's rc 6/7/35 messages name the host too — so
#       `_bs_read_remedy` scrubs it before any echo.
# Echoes the raw betterstack-query.sh rows on stdout and RETURNS THE QUERY'S rc, so each caller
# owns its own failure semantics: confirm warns and keeps polling, the liveness counter and the
# execute gate fail closed. No-SSH by construction — betterstack-query.sh is the only transport.
_bs_query_rows() {
  local since="$1" term="$2" limit="$3" errfile="${4:-/dev/null}" rows rc=0
  rows=$(doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since "$since" --grep "$term" --limit "$limit" 2>"$errfile") || rc=$?
  printf '%s\n' "$rows"
  return "$rc"
}

# _bs_read_remedy <label> <rc> <errfile> <rowsfile> — the operator-facing diagnosis of a failed
# Better Stack read, branched on the reader's rc (measured partition: 3 = credentials absent;
# 1 = `doppler run` or the reader exited 1; 22 = the transport's `--fail-with-body` saw an HTTP
# error; 6/7/28/35 = transport faults (DNS/connect/timeout/TLS); 2/64/78 = the reader's own refusals).
#
# THIS RUNS ON A PUBLIC REPO'S RUN LOG, and the credentials enter via `doppler run` INSIDE the
# reader, so GitHub's secret masking never sees them. Two egress rules, both measured at review
# (2026-09-11): (1) the HTTP error BODY is never printed — a ClickHouse 403 body is
# `Code: 516. DB::Exception: <BETTERSTACK_QUERY_USERNAME>: Authentication failed…`, i.e. half of
# the Basic-auth pair; only its LENGTH and a two-way classification (credentials rejected /
# source under maintenance) are echoed; (2) the first stderr line is scrubbed of quoted values
# and of `*.betterstackdata.com` hostnames before it is echoed. Every pipeline here is `|| true`
# so this function — whose only job is to print the remedy — cannot itself die mute under `set -e`.
_bs_read_remedy() {
  local label="$1" rc="$2" errfile="$3" rowsfile="$4" err1 body_len body_class
  err1="$(head -1 "$errfile" 2>/dev/null | tr -d '\r\n' | sed -E "s/'[^']*'/'<redacted>'/g; s/[A-Za-z0-9.-]*betterstackdata\.com/<host>/g" | cut -c1-200 || true)"
  case "$rc" in
    3)  echo "::error::2.0 $label read: betterstack-query.sh rc=3 — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not injected. Check: doppler secrets get BETTERSTACK_QUERY_HOST -p soleur -c prd_terraform --plain | wc -c (value-silent) must be non-zero. stderr: ${err1:-<none>}" ;;
    1)  echo "::error::2.0 $label read: doppler run or the reader exited 1 — read stderr: if it begins 'Doppler Error' check the DOPPLER_TOKEN repo secret; otherwise file an issue with this run URL. stderr: ${err1:-<none>}" ;;
    22) body_len="$(wc -c < "$rowsfile" 2>/dev/null | tr -d '[:space:]' || true)"
        body_class="other"
        grep -qiE 'Authentication failed|Code: 516|password is incorrect' "$rowsfile" 2>/dev/null && body_class="credentials-rejected"
        grep -qi 'maintenance' "$rowsfile" 2>/dev/null && body_class="source-under-maintenance"
        case "$body_class" in
          credentials-rejected) echo "::error::2.0 $label read: the ClickHouse read path REJECTED the credentials (HTTP error under --fail-with-body, rc=22; body ${body_len:-?} bytes, not printed — it names the username). Rotate/verify BETTERSTACK_QUERY_{USERNAME,PASSWORD} in prd_terraform against the Better Stack query endpoint; re-dispatching without that will not clear it." ;;
          source-under-maintenance) echo "::error::2.0 $label read: the ClickHouse read path is under maintenance (HTTP error under --fail-with-body, rc=22; the 2026-09-03 503 precedent; body ${body_len:-?} bytes, not printed). Re-dispatch later." ;;
          *) echo "::error::2.0 $label read: the ClickHouse read path returned an HTTP error (transport rc=22 under --fail-with-body; body ${body_len:-?} bytes, not printed). Re-dispatch later; if it persists, file an issue with this run URL. stderr: ${err1:-<none>}" ;;
        esac ;;
    6|7|28|35) echo "::error::2.0 $label read: the transport could not reach the read path (rc=$rc: DNS / connect / timeout / TLS from the runner) — a transient network fault on the RUNNER side, not a host state. Re-dispatch later. stderr: ${err1:-<none>}" ;;
    2|64|78) echo "::error::2.0 $label read: betterstack-query.sh refused (rc=$rc: destination pin / usage / trace) — a reader misconfiguration, not a host state. File an issue with this run URL. stderr: ${err1:-<none>}" ;;
    *)  echo "::error::2.0 $label read: betterstack-query.sh rc=$rc (unclassified). File an issue with this run URL. stderr: ${err1:-<none>}" ;;
  esac
  echo "::error::2.0 $label read failed — NOTHING about the dedicated host was measured. This is a read-path fault, not a host verdict; do not proceed and do not SSH the host."
}

confirm_flip_state() {
  local since="$1" i rows raw rc
  for i in $(seq 1 40); do   # 40 x 15s = 600s (30s on-host timer + FLUSHALL/assert + journald->Vector->BS latency)
    rc=0
    rows=$(_bs_query_rows "$since" inngest-cutover-flip 50) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      echo "::warning::confirm: betterstack-query.sh returned non-zero (the CONFIRM PATH failed, NOT the on-host FSM) — verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform" >&2
    fi
    raw=$(printf '%s\n' "$rows" | jq -r 'try (.raw) catch empty' 2>/dev/null || true)
    # aborted first (fail-safe if somehow both terminal flags appear in the window).
    if printf '%s\n' "$raw" | grep -qE '"flag":"aborted"'; then echo "aborted"; return 0; fi
    if printf '%s\n' "$raw" | grep -E '"flag":"rolled-back"' | grep -qE '"exit_code":0'; then echo "rolled-back"; return 0; fi
    if printf '%s\n' "$raw" | grep -E '"flag":"done"' | grep -qE '"exit_code":0'; then echo "done"; return 0; fi
    echo "confirm: awaiting a terminal FSM flag (attempt $i/40 since $since)" >&2
    sleep 15
  done
  echo "timeout"; return 0
}

# #6178 — the TRUST ANCHOR for the coexistence window (ADR-143, amends ADR-106).
#
# Echoes the EARLIEST flip-FSM *transition* timestamp (the ClickHouse `dt` column), or
# nothing when none is derivable. This is the instant the dedicated host's scheduler
# went live, i.e. the start of the coexistence region the double-fire check must cover.
#
# TRANSITION, NOT "ANY FLIP ROW" — this distinction is the whole correctness of the
# anchor. inngest-cutover-flip runs on a ~30s on-host timer and re-emits
# flag:"done" reason:"noop-done" on EVERY tick: ~2,880 rows/day, so a 400-row query
# spans about four HOURS. Anchoring on "the earliest row returned" would therefore
# resolve to a few hours ago rather than the cutover instant, silently producing a
# window NARROWER than the coexistence region — the unsafe direction, and precisely
# the vacuous-clean verdict AC-V3 exists to reject. The transition reasons below are
# disjoint from the noop-* heartbeat reasons (inngest-cutover-flip.sh emit_state).
# Measured 2026-07-24: exactly ONE transition row (done/flip-complete @ 10:20:51Z)
# against thousands of heartbeats.
#
# The reasons are matched in their QUOTED form because `noop-rolled-back` CONTAINS the
# substring `rolled-back` — a bare grep would re-admit the entire heartbeat firehose.
#
# DECISIVE PROPERTY: this row is stamped on 10.0.1.40's journald — the SAME CLOCK that
# stamps `startedAt` on the runs being bucketed — which collapses the operator
# clock-skew class entirely (an operator typing Europe/Paris local time in July lands
# 120 minutes off, several times any workable margin).
#
# PURITY: extracts ONLY `dt`. The standing contract of the Better Stack readers in this
# step is that they NEVER echo a raw row (a value could ride along).
# ANCHOR RETENTION BOUND. This literal — not vendor retention — is the operative limit
# on how long after a cutover an `fsm` anchor can be derived at all. Past it, op=verify
# degrades to `var` and then fails closed.
FSM_ANCHOR_SINCE="${FSM_ANCHOR_SINCE:-30d}"
# Set by _flip_transition_dt on failure so the caller's fail-closed message can name
# what actually happened instead of asserting a cause it never established.
FSM_FAIL_REASON=""
_flip_transition_dt() {
  local limit=50 rows n dt rc=0
  FSM_FAIL_REASON=""
  # TRANSITION REASONS. Derived from inngest-cutover-flip.sh `emit_state` — EVERY reason
  # that is not a `noop-*` heartbeat. `unexpected-exit` is the ERR-trap terminal
  # transition and is load-bearing: it is the ONLY row emitted on the path where
  # `start_server` SUCCEEDS (coexistence begins) but the subsequent `flag_set` — a
  # Doppler network write — fails. Omitting it would skip that row and return a LATER
  # one, i.e. a window NARROWER than the coexistence region: the exact unsafe direction
  # this anchor exists to prevent. Its `--grep` is deliberately UNTERMINATED because the
  # reason interpolates a `(from=…)` suffix.
  #
  # Including a reason can only ever move the anchor EARLIER — earliest(A ∪ B) ≤
  # earliest(A) — so a SUPERSET is always the safe direction. The abort reasons are kept
  # for that reason even though they fire on flips where `start_server` never ran.
  # A cross-file parity test pins this set against the emitter.
  rows=$(doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
    --since "$FSM_ANCHOR_SINCE" \
    --grep '"reason":"flip-complete"' \
    --grep '"reason":"flushed-resume-no-reflush"' \
    --grep '"reason":"unexpected-exit' \
    --grep '"reason":"rolled-back"' \
    --grep '"reason":"dbsize-nonzero"' \
    --grep '"reason":"flushall-failed"' \
    --grep '"reason":"refuse-rearm-after-done"' \
    --grep '"reason":"latch-unrecordable"' \
    `# --- #7228: the probe-derived done refusals. These fire on the path where start_server` \
    `# SUCCEEDED and the host then failed to serve — i.e. squarely inside the coexistence` \
    `# region, which is exactly what this anchor must not start after. Omitting them would` \
    `# return a LATER row and narrow the window, the unsafe direction. A cross-file parity` \
    `# test pins this set against the emitter, so a new reason without an entry here reds.` \
    --grep '"reason":"verify-health"' \
    --grep '"reason":"verify-registry-empty"' \
    --grep '"reason":"verify-registry-unreadable"' \
    --grep '"reason":"verify-owner-unrecordable"' \
    --grep '"reason":"verify-unknown"' \
    --limit "$limit") || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    FSM_FAIL_REASON="query-failed rc=$rc"
    echo "::warning::anchor-derive: betterstack-query.sh returned $rc (the DERIVE PATH failed, NOT the on-host FSM) — verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform" >&2
    return 1
  fi
  n=$(printf '%s\n' "$rows" | grep -c '^{' || true)
  if [[ "$n" -eq 0 ]]; then
    FSM_FAIL_REASON="no-transition-row within $FSM_ANCHOR_SINCE"
    echo "::warning::anchor-derive: no flip-FSM transition row within $FSM_ANCHOR_SINCE" >&2
    return 1
  fi
  # TRUNCATION GUARD. betterstack-query.sh's LIMIT takes the NEWEST N rows (inner
  # ORDER BY dt DESC) before re-sorting ascending, so a FULL page means the earliest
  # transition may lie beyond it and the row we would pick is LATER than the true
  # anchor — a narrower window. Refuse rather than derive an under-covering anchor;
  # the caller then falls through to a WIDER source, never a narrower one.
  if [[ "$n" -ge "$limit" ]]; then
    FSM_FAIL_REASON="truncated n=$n limit=$limit (transitions EXIST but the earliest may be hidden)"
    echo "::warning::anchor-derive: response filled the page (n=$n limit=$limit) — the earliest transition may be truncated away; refusing a possibly-narrower anchor" >&2
    return 1
  fi
  # `sort` makes earliest-selection independent of betterstack-query.sh's outer
  # ORDER BY: a future edit there (or a second consumer wanting newest-first) would
  # otherwise silently flip this to the LATEST transition and narrow the window, with
  # both suites green. ISO-ish `dt` sorts lexicographically == chronologically.
  # `|| true` on the pipeline: `head -1` closing the pipe early SIGPIPEs the producer,
  # which `pipefail` would surface as a spurious failure.
  dt=$( { printf '%s\n' "$rows" | jq -r 'select(type == "object") | .dt' | sort | head -1; } 2>/dev/null || true)
  # Shape-guard before the value reaches `date -d`: both a parse guard and an
  # injection guard on externally-sourced text.
  if ! [[ "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
    FSM_FAIL_REASON="dt-malformed"
    echo "::warning::anchor-derive: transition row carried no parseable dt" >&2
    return 1
  fi
  printf '%s\n' "$dt"
}

# G3.7's off-host READ (#7462 review). The flush latch is a FILE on the dedicated host's
# /mnt/data volume (inngest-cutover-flip.sh `flush_already_performed`), and this script may not
# SSH — so the readable proxy is the marker the on-host FSM emits at the two moments that PROVE
# a FLUSHALL has already been performed for this host:
#
#   "reason":"flip-complete"            the forward flip COMPLETED, i.e. FLUSHALL ran and
#                                       record_flush_latch wrote the durable latch.
#   "reason":"refuse-rearm-after-done"  the on-host latch has ALREADY refused a re-arm.
#
# Both are emitted by inngest-cutover-flip.sh `emit_state` as STRING LITERALS and both already
# sit in _flip_transition_dt's pinned reason set above — this is the SAME no-SSH reader, asked a
# different question, so no new transport, credential or fixture class is introduced.
#
# CORRECTED (#7674). This comment used to claim the read was "SCOPED TO THIS HOST BY THE TABLE"
# because BS_TABLE's source "ships ONLY the dedicated inngest host's journald", and that a
# hostname filter "would add nothing". That is FALSE, and the two sources that settle it are in
# this repo: vector.toml says "ALL hosts multiplex into the ONE Logs source 2457081 — host_name
# is the sole discriminator", and betterstack-query.sh defaults BS_TABLE to exactly that source.
# Measured 2026-08-25: a default-table query returned rows carrying host_name=soleur-web-platform.
#
# It remains true that THIS latch reader does not strictly need the filter — its two `reason`
# literals are emitted only by the on-host flip FSM, so in practice the reason terms are
# themselves host-discriminating (measured 2026-08-25: 84/84 flip rows came from this host).
# "In practice" is the honest strength: that is an argument from who RUNS the emitter, not a
# property the query enforces, and #6616 is the open issue about identity fields not meaning what
# they appear to. The liveness reader below therefore filters explicitly rather than inheriting
# this reasoning — see its guard note 2, which supersedes any reading of this paragraph as
# licensing an unfiltered read. The correction matters because the FALSE justification was
# about to be inherited by the liveness reader below, where the terms are NOT host-discriminating
# and an unfiltered read would count web-1's rows as this host's liveness — a fail-open.
#
# NO TRUNCATION GUARD, deliberately — and the asymmetry with _flip_transition_dt is the point.
# That function needs the EARLIEST transition, so a full page can hide the row it must return and
# it refuses rather than derive a narrower window. This one needs only EXISTENCE, which is
# monotone in the page: a full page means n >= limit >= 1, i.e. latched, and the only way to read
# 0 is that the window genuinely holds no such row. Truncation cannot manufacture an absence.
#
# THE WINDOW IS A PRE-FILTER'S WINDOW, not the latch's. The on-host latch is unbounded in time;
# Better Stack retention is not. Neither error direction can authorise a flush: too WIDE costs a
# refused dispatch on a legitimately-recut host (recoverable by narrowing FLUSH_LATCH_SINCE — the
# reason it is a variable and not a literal), and too NARROW degrades to the pre-gate behaviour,
# where the on-host latch still refuses. Deliberately NOT FSM_ANCHOR_SINCE: that constant bounds
# how long a COEXISTENCE anchor stays derivable and is tuned for that; this one approximates a
# MONOTONIC "has this host ever been flushed?" and wants the widest window it can get.
FLUSH_LATCH_SINCE="${FLUSH_LATCH_SINCE:-365d}"
_flush_latch_count() {
  local rows rc=0 n
  rows=$(doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
    --since "$FLUSH_LATCH_SINCE" \
    --grep '"reason":"flip-complete"' \
    --grep '"reason":"refuse-rearm-after-done"' \
    --limit 5) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::warning::G3.7 flush-latch read: betterstack-query.sh returned $rc (the READ PATH failed, NOT the on-host latch) — verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform" >&2
    printf '%s' '__UNREADABLE__'
    return 0
  fi
  # Count rows, never echo one: the standing purity contract of every Better Stack reader here.
  n=$(printf '%s\n' "$rows" | grep -c '^{' || true)
  # Explicit decimal predicate (#7674) rather than trusting bash arithmetic coercion downstream:
  # an empty string compares FALSE under -gt, which is the documented destroy-guard bypass class.
  case "$n" in
    ''|*[!0-9]*) printf '%s' '__UNREADABLE__'; return 0 ;;
  esac
  printf '%s' "$n"
}

# G3.7's SECOND signal (#7674): H, the dedicated host's own liveness witness.
#
# WHY THIS EXISTS. L (the latch count above) alone cannot tell "no flush has happened" from
# "I cannot tell". Measured 2026-08-25: G3.7's query returned 0 rows at 7d, 30d AND 365d, so the
# gate reported `clear` — full coverage — on a question it had no evidence for. H closes that by
# asking a question with a known-positive answer on a healthy host: is this host emitting flip-FSM
# rows at all? Measured the same day, it emits ~1.4/min continuously.
#
# THREE WAYS THIS READER COULD BE SILENTLY DEFEATED, each guarded and each asserted in
# cutover-inngest-workflow.test.sh:
#
#   1. KEY ON THE TAG, NEVER AN ENUMERATED `reason` SET. run_flip's catch-all arm emits
#      `noop-unset`, and that is the arm that fires in the state G3.7 actually gates (a genuine
#      first arm, flag unset). A reader keyed on {noop-rolled-back, noop-done, noop-aborted}
#      would read H=0 on a perfectly healthy host and refuse every legitimate arm — converting a
#      fail-OPEN gate into an unconditionally-closed one.
#
#   2. HOST ISOLATION IS MANDATORY HERE. Unlike the latch reader's `reason` literals, the bare tag
#      is NOT host-discriminating, and all hosts multiplex into one Logs source (see the corrected
#      comment above). Without the filter, web-1's rows would be counted as this host's liveness.
#
#   3. THE FILTER MUST NOT RIDE `--grep`, AND MUST MATCH AFTER DECODING. betterstack-query.sh
#      OR-combines its --grep terms, so a host term there WIDENS the query rather than narrowing
#      it — a fail-open wearing a filter's clothes. And ClickHouse stores `raw` DOUBLE-ENCODED, so
#      a literal "host_name":"..." grep against the outer row matches NOTHING, EVER — which would
#      pin H at 0 and refuse every arm. Decode `.raw`, then match the field literal.
#
# WINDOW. 15 minutes: wide enough to tolerate both today's ~42s terminal-arm cadence (1.42/min measured) and any
# future rate-limit, which the follow-up issue constrains to stay under 15 minutes. It must not be
# tightened below the slower of the two. (Measured 2026-08-25: 170 rows in 2h = 1.42/min ~= one
# row every 42s. An earlier draft said "~35s cadence" beside "~1.4/min"; those disagree — 35s
# would be 1.7/min — and 1.42/min is the measured figure.)
# DELIBERATELY A LITERAL, not an env override (#7674 review). Two reasons, and either alone
# settles it. (1) It is not mapped into cutover-inngest.yml's step env, and GitHub does not
# export repo vars to a step unless the workflow names them — so an override here would be an
# unperformable remediation, the exact #6617 dead-remediation class this file's sibling comment
# at `FLUSH_LATCH_SINCE` already names. (2) `FLUSH_LATCH_SINCE` earns its override because the
# `latched` message TELLS the operator to narrow it; widening THIS window is the FAIL-OPEN
# direction (more rows -> more likely `clear`), so an operator-reachable knob whose only effect
# is to weaken the gate is not a knob worth shipping.
FLIP_LIVENESS_SINCE="15m"
_flip_liveness_count() {
  local rows rc=0 n
  rows=$(_bs_query_rows "$FLIP_LIVENESS_SINCE" inngest-cutover-flip 50) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::warning::G3.7 liveness read: betterstack-query.sh returned $rc (the READ PATH failed, NOT the host) — verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform" >&2
    printf '%s' '__UNREADABLE__'
    return 0
  fi
  # Decode `.raw` first (it is double-encoded), then match the host field literal. Counts only;
  # never echoes a row, the standing purity contract of every Better Stack reader here.
  n=$(printf '%s\n' "$rows" \
    | jq -R -r --arg h "$INNGEST_HOST" --arg hn "$INNGEST_HOST_NAME" \
        'fromjson? | .raw? | fromjson? | select(.host == $h and .host_name == $hn) | 1' 2>/dev/null \
    | grep -c '^1$' || true)
  case "$n" in
    ''|*[!0-9]*) printf '%s' '__UNREADABLE__'; return 0 ;;
  esac
  printf '%s' "$n"
}

# ── #6894: the LUKS cutover FSM's own liveness + confirm readers ────────────────────────────────
# Keyed on the CUTOVER unit's tag, NOT the flip's. They are two units with two timers, and the
# question these gates ask is "can the host act on this write?" — which for a write to
# INNGEST_LUKS_CUTOVER is answered only by inngest-luks-cutover.service. Using the flip's rows
# would report audible on a host where the cutover trio never installed (the install_missing arm
# in inngest-bootstrap.sh), i.e. exactly the silently-dead-delivery case this estate has paid for.
LUKS_LIVENESS_SINCE="15m"
_luks_liveness_count() {
  local rows rc=0 n
  rows=$(_bs_query_rows "$LUKS_LIVENESS_SINCE" inngest-luks-cutover 50) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::warning::LUKS liveness read: betterstack-query.sh returned $rc (the READ PATH failed, NOT the host) — verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform" >&2
    printf '%s' '__UNREADABLE__'
    return 0
  fi
  n=$(printf '%s\n' "$rows" \
    | jq -R -r --arg h "$INNGEST_HOST" --arg hn "$INNGEST_HOST_NAME" \
        'fromjson? | .raw? | fromjson? | select(.host == $h and .host_name == $hn) | 1' 2>/dev/null \
    | grep -c '^1$' || true)
  case "$n" in
    ''|*[!0-9]*) printf '%s' '__UNREADABLE__'; return 0 ;;
  esac
  printf '%s' "$n"
}

# confirm_luks_state <since-space-timestamp> — the terminal flag the on-host FSM reached, or
# `timeout`. Keys on the emitter's `flag` field, never `reason`. Never echoes a raw row.
# `aborted` is tested FIRST so a window containing both terminals reports the unsafe one.
# The window is generous because this FSM COPIES the store before it swaps.
confirm_luks_state() {
  local since="$1" i rows raw rc
  for i in $(seq 1 60); do   # 60 x 15s = 900s, matching the unit's TimeoutStartSec plus shipping lag
    rc=0
    rows=$(_bs_query_rows "$since" inngest-luks-cutover 100) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      echo "::warning::confirm: betterstack-query.sh returned non-zero (the CONFIRM PATH failed, NOT the on-host FSM) — verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform" >&2
    fi
    raw=$(printf '%s\n' "$rows" | jq -r 'try (.raw) catch empty' 2>/dev/null || true)
    if printf '%s\n' "$raw" | grep -qE '"flag":"aborted"'; then echo "aborted"; return 0; fi
    if printf '%s\n' "$raw" | grep -qE '"flag":"rolled-back"'; then echo "rolled-back"; return 0; fi
    if printf '%s\n' "$raw" | grep -E '"flag":"done"' | grep -qE '"exit_code":0'; then echo "done"; return 0; fi
    echo "confirm: awaiting a terminal LUKS FSM flag (attempt $i/60 since $since)" >&2
    sleep 15
  done
  echo "timeout"; return 0
}

# _luks_pointer_state — `present`, `absent`, or `unreadable`. The pointer is what makes the
# encrypted volume canonical, so "is this host already cut over?" is answered by it, never by the
# flag. ABSENCE IS READ FROM THE NAME LIST, never from a failed `get`: a get failure is equally
# consistent with a dead token, and treating that as "absent" would authorise a second cutover on
# a host that already has one.
_luks_pointer_state() {
  local names rc=0
  names=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets --only-names --json -p soleur-inngest -c prd 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 || -z "$names" ]]; then printf '%s' 'unreadable'; return 0; fi
  if printf '%s' "$names" | jq -e 'has("INNGEST_LUKS_ACTIVE_VOLUME_ID")' >/dev/null 2>&1; then
    printf '%s' 'present'
  else
    printf '%s' 'absent'
  fi
}

# #6178 — the doublefire probe's STARTED_AT lower bound, forwarded as ?from=.
#
# Emits TWO space-separated fields: "<ISO-8601 Z> <anchor_source>", where
# anchor_source is one of fsm | var | floor | wide. The source is not decoration: a
# clean verdict over a var-sourced or floor-clamped window is a materially weaker
# claim than one over an fsm-anchored window, and without the field that difference
# is invisible off-box on an otherwise-green run.
#
#   $1 = fallback days (REQUIRED, positive int — passed per-arm, never an ambient
#        global read from ~900 lines away)
#   $2 = mode: "fsm"  → derive the anchor, FAIL CLOSED if none (op=verify)
#               "wide" → no anchor exists yet (op=doublefire-probe, PRE-cutover)
#
#   DF_FROM = min( bucket_floor(anchor) − 2×cron_period , now − fallback_days )
#
# min() is the SKEW CLAMP: an operator-supplied anchor can only ever WIDEN the window,
# never narrow it below the floor. bucket_floor() is exact and self-documenting — it
# IS the boundary the downstream group_by([.fn, .bucket]) uses — and the extra
# 2×cron_period is straggler margin.
#
# THERE IS NO SAFE WIDE FALLBACK, which is why an underivable anchor fails closed
# instead of scanning some default. At the measured 728 runs/day a 7-day window is
# ~5,100 runs ≈ 51 pages ≈ 214 s — not exhaustible. Scanning it would trade a deadline
# abort for a deadline abort while LOOKING safer, and this probe is fail-loud on
# non-exhaustion (it emits nothing), so the operator would learn nothing either way.
doublefire_from() {
  local fallback_days="${1:-}" mode="${2:-}"
  local period="${CUTOVER_CRON_PERIOD_SECONDS:-3600}"
  [[ "$period" =~ ^[1-9][0-9]*$ ]] || period=3600
  if ! [[ "$fallback_days" =~ ^[1-9][0-9]*$ ]]; then
    echo "doublefire_from: fallback days must be a positive integer (got '$fallback_days')" >&2
    return 1
  fi
  # FAIL CLOSED on an unrecognized mode. A `${2:-wide}` default plus a `!= fsm` test
  # would silently route a typo (or a future third caller) onto the UNANCHORED wide
  # path — fail-open on the safety-relevant argument, while `fallback_days` right above
  # fails closed on the same class of error.
  case "$mode" in
    fsm|wide) ;;
    *) echo "doublefire_from: mode must be 'fsm' or 'wide' (got '$mode')" >&2; return 1 ;;
  esac
  local now_e floor_e
  now_e=$(date -u +%s)
  floor_e=$(( now_e - fallback_days * 86400 ))

  # PRE-cutover dark-host detector: there is no coexistence instant to anchor on yet,
  # so it keeps its wide window and makes no Better Stack call at all.
  if [[ "$mode" == "wide" ]]; then
    printf '%s wide\n' "$(date -u -d "@$floor_e" +%Y-%m-%dT%H:%M:%SZ)"
    return 0
  fi

  local anchor_e="" src="" dt=""
  # PRECEDENCE: override > fsm > var > fail closed.
  #
  # CUTOVER_ANCHOR_FROM is the operator's NARROWING lever, and it must outrank the FSM
  # row or it cannot do its job. This is the fix for a dead-remediation defect: the
  # page-1 feasibility gate tells the operator to move the window later, but the only
  # variable it used to name (CUTOVER_WINDOW_FROM) is consulted ONLY when the fsm anchor
  # is absent — so on the normal path, following the remediation changed DF_FROM by
  # exactly nothing and the next dispatch aborted identically. That is the same
  # dead-advice class this change removed from the deadline surfaces, relocated.
  #
  # It is a SEPARATE variable from CUTOVER_WINDOW_FROM on purpose: that one is also
  # consumed by the missed-tick auto-enumeration as the quiesce→register gap START, and
  # quiesce PRECEDES the cutover. Overloading it would silently re-base the expected-tick
  # window so the gap ticks stop being enumerated — the omission half.
  #
  # An override NARROWS by construction, so it yields a window-limited verdict; the
  # verify arm downgrades VERIFIED accordingly.
  if [[ -n "${CUTOVER_ANCHOR_FROM:-}" ]]; then
    anchor_e=$(date -u -d "${CUTOVER_ANCHOR_FROM}" +%s 2>/dev/null || echo "")
    if [[ "$anchor_e" =~ ^[0-9]+$ ]]; then src=override; else anchor_e=""; fi
  fi
  if [[ -z "$anchor_e" ]] && dt=$(_flip_transition_dt); then
    anchor_e=$(date -u -d "$dt UTC" +%s 2>/dev/null || echo "")
    if [[ "$anchor_e" =~ ^[0-9]+$ ]]; then src=fsm; else anchor_e=""; fi
  fi
  if [[ -z "$anchor_e" && -n "${CUTOVER_WINDOW_FROM:-}" ]]; then
    anchor_e=$(date -u -d "${CUTOVER_WINDOW_FROM}" +%s 2>/dev/null || echo "")
    if [[ "$anchor_e" =~ ^[0-9]+$ ]]; then src=var; else anchor_e=""; fi
  fi
  if [[ -z "$anchor_e" ]]; then
    echo "doublefire_from: coexistence anchor underivable (${FSM_FAIL_REASON:-fsm-derive not attempted}); CUTOVER_ANCHOR_FROM and CUTOVER_WINDOW_FROM are both unset or unparseable. Set CUTOVER_ANCHOR_FROM to the quiesce instant (ISO-8601, at or before the cutover) and re-dispatch. Refusing to scan an unanchored window." >&2
    return 1
  fi

  local anchor_from=$(( anchor_e / period * period - 2 * period ))
  local from_e="$anchor_from"
  # The floor can only WIDEN (min picks the earlier bound). Record it as floor(<src>)
  # rather than plain `floor`: with a 1-day fallback, the floor wins on every dispatch
  # within ~24h of the cutover — i.e. the intended usage — so a bare `floor` would
  # discard whether an fsm anchor was derivable at all, which is exactly the fact AC-V3
  # asks the operator to demonstrate.
  if (( floor_e < anchor_from )); then from_e="$floor_e"; src="floor(${src})"; fi
  printf '%s %s\n' "$(date -u -d "@$from_e" +%Y-%m-%dT%H:%M:%SZ)" "$src"
}

# G3 arm-decision (#7462). PURE: no I/O, no globals read or written, no input value
# echoed — it returns one outcome TOKEN and the caller acts on it. That is what makes the
# decision executable by a test: every other assertion over this file greps its TEXT, and
# a text grep cannot see WHICH BRANCH a comparison takes.
#
#   $1  the prod value about to be written (G2 has already proven it non-empty)
#   $2  the value currently in place on soleur-inngest/prd
#
# Outcomes: refuse-empty-dark | refuse-txn-pooler | refuse-not-session-pooler
#           | refuse-not-prod-project | skip-already-current | write
#
# WHY THE EQUALITY ARM SKIPS RATHER THAN REFUSING (#7462). It used to `exit 1` when the
# prod value already equalled the dark one. But G4 writes the prod DSN and op=rollback has
# NO inverse for that write, so after the first successful arm (2026-07-23T15:46Z) the
# dark slot holds the prod DSN permanently and the equality refusal fires FOREVER — the
# cutover could never be re-armed after a rollback, which defeats rollback's purpose.
#
# Dropping the refusal costs no safety. The hazard its own message named ("would flip onto
# the DARK backend") is fully held by the prod project-ref pin below: the dark backend is a
# DISTINCT Supabase project (ADR-100 addendum 2026-07-15) and cannot carry the prod ref.
# The FLUSHALL hazard is held by the monotonic latch in inngest-cutover-flip.sh (#7228
# P0-5) — recorded AT the flush and fatal if unrecordable — never by this comparison.
# Equality therefore means only "this write would change nothing", which is a fact to
# record, not a reason to abort.
#
# EXTRACTION CONTRACT: cutover-inngest-workflow.test.sh sources this function by awk range
# `/^g3_decide\(\) \{$/,/^\}$/`. Keep the signature and the closing brace at column 0, and do
# not introduce a column-0 `}` inside the body, or the extraction truncates.

# G3.6's decision, extracted for the same reason g3_decide is (#7462 review): the first
# revision of that gate inlined a `case` in the arm body and was covered only by greps for
# its message strings — adding '1' to the pass-arm, i.e. arming while the diagnostic flag is
# SET, left the whole suite green. A guard whose decision cannot be driven RED is not a guard.
#
#   $1  the raw INNGEST_DIAGNOSTIC_BOOT value, or __UNREADABLE__ when the read failed
# Outcomes: clear | set | unreadable
#
# Same extraction contract as g3_decide: signature and closing brace at column 0.
diag_boot_decide() {
  case "$1" in
    '__UNREADABLE__') printf '%s' 'unreadable'; return 0 ;;
    ''|'0'|'false') printf '%s' 'clear'; return 0 ;;
    *) printf '%s' 'set'; return 0 ;;
  esac
}

# G3.7's decision (#7462 review), extracted for the same reason g3_decide and diag_boot_decide
# are: a guard whose decision cannot be driven RED is not a guard. The first revisions of BOTH
# of those inlined a `case` in the arm body and were covered only by greps for their message
# strings — which cannot see which branch a comparison takes.
#
#   $1  L — the row count from _flush_latch_count, or __UNREADABLE__ when the read failed
#   $2  H — the row count from _flip_liveness_count, or __UNREADABLE__ when the read failed
# Outcomes: clear | latched | unreadable | silent
#
# ANYTHING that is not a decimal count is `unreadable`, and the caller treats that as
# fail-closed — the same direction G1/G3/G3.6 take. It is the safe one here because the question
# this gate asks is "has a FLUSHALL EVER been performed for this host?", and an UNANSWERED
# question must never read as "no".
#
# `silent` (#7674) is a DISTINCT fourth outcome rather than being folded into `unreadable`,
# because the forward actions differ: `unreadable` points at BETTERSTACK_QUERY_* credentials in
# prd_terraform; `silent` points at the dedicated host having gone dark. Collapsing them prints
# the wrong remediation at the worst possible moment. That is also exactly why a non-decimal H
# routes to `unreadable` and NOT to `silent`: __UNREADABLE__ is emitted only on a query rc != 0,
# so routing it to `silent` would print the host-dark remediation for a credential fault —
# committing the very mis-remediation the outcome split exists to prevent.
#
# L dominates H: a recorded flush is decisive regardless of whether the host is currently audible.
#
# Same extraction contract as g3_decide: signature and closing brace at column 0, and no
# column-0 `}` inside the body.
flush_latch_decide() {
  case "$1" in
    ''|*[!0-9]*) printf '%s' 'unreadable'; return 0 ;;
  esac
  # L's VALUE is decisive before H is even consulted (#7674 review). A recorded flush is a refusal
  # regardless of whether the host is currently audible, and ordering it after H's readability
  # check meant (L>=1, H unreadable) printed the CREDENTIAL remediation for a state where a latch
  # had actually been detected — reintroducing, in one cell, the mis-remediation the silent/
  # unreadable split exists to prevent. No refuse/proceed decision changes; only the message.
  case "$1" in
    0) : ;;
    *) printf '%s' 'latched'; return 0 ;;
  esac
  case "$2" in
    ''|*[!0-9]*) printf '%s' 'unreadable'; return 0 ;;
  esac
  case "$2" in
    0) printf '%s' 'silent'; return 0 ;;
    *) printf '%s' 'clear';  return 0 ;;
  esac
}

# op=resume's G3 decision (#7674, CTO ruling). Same extraction contract as g3_decide and
# flush_latch_decide: signature and closing brace at column 0, no column-0 `}` in the body.
#
#   $1  H — the row count from _flip_liveness_count, or __UNREADABLE__ when the read failed
# Outcomes: audible | silent | unreadable
#
# DELIBERATELY NOT flush_latch_decide. L's POLARITY INVERTS between the two verbs: at op=arm
# `L >= 1` means REFUSE (a flush already happened), while at op=resume that same fact is the G2
# precondition being SATISFIED. Reusing the function would force the caller to invert two of four
# arms and would leave the token `latched` meaning opposite things at its two call sites.
resume_liveness_decide() {
  case "$1" in
    ''|*[!0-9]*) printf '%s' 'unreadable'; return 0 ;;
  esac
  case "$1" in
    0) printf '%s' 'silent';  return 0 ;;
    *) printf '%s' 'audible'; return 0 ;;
  esac
}

# G3's terminal ACTION, separated from its message text (#7462 review). The dispatcher used to
# carry `exit 1` inside each refusal arm, which meant nothing tested that a refusal actually
# aborts: stripping `exit 1` from all four arms turned G3 into a pure logger — every refusal
# printed its ::error:: and fell through to the prod write — with the whole suite green. Now the
# arms only choose the MESSAGE and a single gate below decides abort-vs-proceed, so the decision
# is drivable by a test and there is one exit to pin instead of four.
#
#   $1  an outcome token from g3_decide
# Outcomes: abort | proceed   (unknown tokens abort — fail-closed)
#
# Same extraction contract as g3_decide: signature and closing brace at column 0.
g3_action() {
  case "$1" in
    skip-already-current|write) printf '%s' 'proceed'; return 0 ;;
    *) printf '%s' 'abort'; return 0 ;;
  esac
}

g3_decide() {
  local pg="$1" pg_dark="$2"

  # FAIL-CLOSED on an unreadable dark value. The ORIGINAL rationale for this arm is now
  # obsolete and must not be restated: it was that an empty value makes the equality
  # comparison false and so SILENTLY passes. That cannot happen once the equality arm no
  # longer gates anything. The arm is retained on different, still-valid grounds — G1 has
  # already proven the config readable, so an empty read here is anomalous and most
  # plausibly a token-scope or wrong-project fault. Refusing costs one dispatch;
  # proceeding on an anomalous read is how a surprise gets armed.
  if [[ -z "$pg_dark" ]]; then printf '%s' 'refuse-empty-dark'; return 0; fi

  case "$pg" in
    *:6543*) printf '%s' 'refuse-txn-pooler'; return 0 ;;
  esac
  case "$pg" in
    *:5432*) : ;;
    *) printf '%s' 'refuse-not-session-pooler'; return 0 ;;
  esac
  # Positive prod-project pin (C3/D3). This is the SOLE remaining guard against arming onto
  # a non-prod Postgres now that equality no longer refuses — mutation-tested accordingly.
  #
  # Pin the DESTINATION by parsing the AUTHORITY (#7462 review, third revision). Three earlier
  # forms were each defeated, all measured against the shipped function:
  #   1. a bare `*<ref>*` substring — accepted the ref in a password, dbname or query param;
  #   2. pinning the pooler USERNAME — accepted `postgres.<prod-ref>` in front of ANY host,
  #      including `db.<dev-ref>.supabase.co`, i.e. armed onto the dev project;
  #   3. globbing the whole DSN for `*@*.pooler.supabase.com:5432/*` — the `*` after `@` spans
  #      the host AND the path, so the tail matched inside the PATH or QUERY while the real host
  #      was attacker-controlled (`…@attacker.example.com/x.pooler.supabase.com:5432/postgres`).
  #
  # A glob over the whole string cannot express "the authority is X", because every wildcard can
  # cross the delimiters that define it. So extract the authority and match THAT, whole. Pure
  # bash, no subprocesses, no I/O. Every predicate below was MEASURED against the live
  # prd_terraform value so none of them refuses the legitimate DSN.
  local _rest _auth _user _hostport _low
  _low="${pg,,}"
  # Connection-parameter overrides relocate the destination AFTER any authority check. Matched
  # case-insensitively and in percent-encoded form, because `?HOST=` and `%3d` both reach libpq.
  case "$_low" in
    *host=*|*host%3d*|*options=*|*service=*) printf '%s' 'refuse-not-prod-project'; return 0 ;;
  esac
  case "$pg" in
    postgresql://*|postgres://*) : ;;
    *) printf '%s' 'refuse-not-prod-project'; return 0 ;;
  esac
  _rest="${pg#*://}"
  _auth="${_rest%%/*}"        # authority ends at the first '/'
  _auth="${_auth%%\?*}"       # ...or at the first '?' when there is no path
  # Exactly one '@' INSIDE the authority. Go's net/url splits userinfo at the last '@' and
  # permits '@' within it, so a second one relocates the host past any prefix match.
  if [[ "${_auth//[!@]/}" != "@" ]]; then printf '%s' 'refuse-not-prod-project'; return 0; fi
  _user="${_auth%@*}"
  _hostport="${_auth##*@}"
  # A comma in the authority is a multi-host list; the first entry wins.
  case "$_hostport" in *,*) printf '%s' 'refuse-not-prod-project'; return 0 ;; esac
  # Accept exactly two destinations, matched whole against the extracted host:port.
  #   - session pooler: user must carry the prod ref, host must be a Supabase pooler on :5432
  #   - direct host:    the prod ref IS the host, so the username is irrelevant
  case "$_hostport" in
    *.pooler.supabase.com:5432)
      case "$_user" in
        postgres.pigsfuxruiopinouvjwy:*) : ;;
        *) printf '%s' 'refuse-not-prod-project'; return 0 ;;
      esac ;;
    db.pigsfuxruiopinouvjwy.supabase.co:5432) : ;;
    *) printf '%s' 'refuse-not-prod-project'; return 0 ;;
  esac

  if [[ "$pg" == "$pg_dark" ]]; then printf '%s' 'skip-already-current'; return 0; fi
  printf '%s' 'write'
  return 0
}

case "$OP" in
  enumerate)
    # GET hook → records JSON in the response body. HMAC over empty body
    # (mirrors the deploy-status GET signature).
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/enum-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/enum-body -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-enumerate-reminders" || echo "000")
    BODY=$(cat /tmp/enum-body 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      # Surface the host script's cause in the run log (#5492). webhook
      # v2.8.2 CombinedOutput() returns stdout+stderr and
      # include-command-output-in-response-on-error carries it into the
      # response body — but it is only diagnosable if we dump it here.
      # Strip CR/LF so the ::error:: annotation stays one line.
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::enumerate returned HTTP $CODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e 'type == "array"' >/dev/null 2>&1; then
      echo "::error::enumerate did not return a JSON array"; echo "$BODY"; exit 1
    fi
    # P2-sec-a: surface counts + reminder_ids ONLY, never comment bodies.
    COUNT=$(echo "$BODY" | jq 'length')
    IDS=$(echo "$BODY" | jq -r '[.[].reminder_id] | join(",")')
    echo "::notice::$COUNT still-armed reminder(s): [$IDS]"
    ;;

  registry-probe)
    # #6617 — STANDALONE read-only registry probe. Same hook op=execute 2.0
    # calls, but this arm STOPS after reading: no capture, no quiesce, no
    # secret write, no state transition. It exists so double-scheduler state
    # is provable BEFORE the maintenance window rather than inside it —
    # previously the only route to this signal was op=execute, which then
    # proceeds to capture + quiesce.
    #
    # Proxied over the private net by the web host: the runner cannot reach
    # 10.0.1.40 directly (deny-all-public, SEC-H2), which is why CUTOVER_HOSTS
    # is irrelevant to this arm.
    #
    # Single-shot (no transport retry), mirroring op=execute 2.0: a verdict
    # here is diagnostic, not gating, so a transient is re-run by dispatching
    # again rather than by an in-arm loop.
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/registry-probe-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/registry-probe-body -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-registry-probe" || echo "000")
    BODY=$(cat /tmp/registry-probe-body 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::registry-probe returned HTTP $CODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e 'type=="object" and has("registry_empty")' >/dev/null 2>&1; then
      echo "::error::registry-probe did not return a {registry_empty,function_count,function_ids} object"; echo "$BODY"; exit 1
    fi
    REG_EMPTY=$(echo "$BODY" | jq -r '.registry_empty')
    REG_COUNT=$(echo "$BODY" | jq -r '.function_count // 0')
    # Counts + ids ONLY (AC-NOBODY) — never a payload.
    REG_IDS=$(echo "$BODY" | jq -r '[.function_ids[]?] | join(",")')
    echo "::notice::registry-probe: registry_empty=$REG_EMPTY function_count=$REG_COUNT ids=[$REG_IDS]"
    if [[ "$REG_EMPTY" == "false" ]]; then
      echo "::warning::registry-probe: the dedicated host (10.0.1.40) has $REG_COUNT REGISTERED function(s). Pre-cutover this is UNEXPECTED — it means an SDK has registered against the dark host. Run op=doublefire-probe to establish whether those registrations have also EXECUTED runs (registration alone is not proof of a double-fire)."
    else
      echo "::notice::registry-probe: dedicated registry is EMPTY — no SDK has registered functions against 10.0.1.40."
    fi
    ;;

  doublefire-probe)
    # #6617 — STANDALONE read-only double-fire probe. The STRONGER instrument:
    # registry-probe proves an SDK REGISTERED against the dark host;
    # this proves the dark host has actually EXECUTED cron runs — the harm
    # itself rather than a proxy for it. Read-only, stops after reading.
    #
    # Same bucketing invariant as op=verify 2.6: group every run by
    # (functionID, floor(startedAt / CRON_PERIOD)); a bucket with >1 run is a
    # DOUBLE-FIRE. There is no per-tick schedule field in v1.19.4, so the
    # invariant derives from startedAt alone (ADR-100 Decision 7).
    CRON_PERIOD="${CUTOVER_CRON_PERIOD_SECONDS:-3600}"
    if ! [[ "$CRON_PERIOD" =~ ^[1-9][0-9]*$ ]]; then
      echo "::error::doublefire-probe CRON_PERIOD invalid ('$CRON_PERIOD') — set CUTOVER_CRON_PERIOD_SECONDS to a positive integer ≤ the SHORTEST registered cron period (hour-aligned)."; exit 1
    fi
    echo "::warning::doublefire-probe CRON_PERIOD=${CRON_PERIOD}s is applied to ALL functions (P2-c). The verdict is SOUND ONLY IF every registered cron period ≥ ${CRON_PERIOD}s AND hour-aligned. If any cron fires faster, re-dispatch with CUTOVER_CRON_PERIOD_SECONDS set to the SHORTEST registered period before trusting the result."
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    # Forward the window lower bound + optional functionIDs scope as URL query params
    # (HMAC is over the empty GET body, so params don't affect the sig).
    # #6178 — PER-ARM fallback. This is the PRE-cutover dark-host detector: it runs
    # BEFORE any flip, so no coexistence instant exists to anchor on, and it keeps the
    # wide 200-day window (mode=wide makes no Better Stack call — this arm is read-only
    # and invokes no doppler). Only op=verify narrows; narrowing this arm too would have
    # been a false-clean on the plan's own stated harm.
    if ! DF_RAW=$(doublefire_from 200 wide); then
      echo "::error::doublefire-probe: could not compute the scan window lower bound — refusing to scan"; exit 1
    fi
    read -r DF_FROM DF_ANCHOR_SOURCE <<< "$DF_RAW"
    if ! [[ "$DF_FROM" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
      echo "::error::doublefire-probe: computed window lower bound is malformed ('$DF_FROM') — refusing to scan"; exit 1
    fi
    DF_FNIDS="${CUTOVER_DOUBLEFIRE_FUNCTION_IDS:-}"
    # OPEN-TOPPED (no `until`) — same invariant as the op=verify arm.
    DF_URL="$BASE/inngest-doublefire-probe?from=${DF_FROM}&function_ids=${DF_FNIDS}"
    echo "::notice::doublefire-probe: scanning from=${DF_FROM} anchor_source=${DF_ANCHOR_SOURCE} function_ids=[${DF_FNIDS:-<all>}]"
    rm -f /tmp/doublefire-probe-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 120 -o /tmp/doublefire-probe-body -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$DF_URL" || echo "000")
    BODY=$(cat /tmp/doublefire-probe-body 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::doublefire-probe returned HTTP $CODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e '.runs | type == "array"' >/dev/null 2>&1; then
      echo "::error::doublefire-probe did not return a {runs:[...]} object"; echo "$BODY"; exit 1
    fi
    # #6178 — PAGE-OVERLAP DEDUPE. The probe cursor-paginates runs(orderBy: STARTED_AT ASC) and a
    # run can come back on two pages (cause unconfirmed). Measured 2026-09-15: every reported
    # "double-fire" group equalled RUN_COUNT - total_count and was absent from trace_runs (one run
    # per tick). Dedupe by the run id (trace_runs.run_id PRIMARY KEY): a repeated page row shares
    # its id and two distinct runs never do. FALLBACK when the host's probe predates the id
    # projection: (functionID, startedAt) — startedAt is MILLISECOND precision, so two schedulers
    # firing in the same millisecond would collapse; that verdict is qualified, never silent.
    PRE_DEDUPE_N=$(echo "$BODY" | jq '.runs | length')
    DEDUPE_KEY=$(echo "$BODY" | jq -r 'if (.runs | length) > 0 and all(.runs[]; (.id | type) == "string") then "run-id" else "functionID+startedAt(ms)" end')
    BODY=$(echo "$BODY" | jq -c '.runs |= (if length > 0 and all(.[]; (.id | type) == "string") then unique_by(.id) else ([ .[] | select(.startedAt == null) ] + ([ .[] | select(.startedAt != null) ] | unique_by([.functionID, .startedAt]))) end)')
    RUN_COUNT=$(echo "$BODY" | jq '.runs | length')
    if (( PRE_DEDUPE_N > RUN_COUNT )); then
      echo "::notice::doublefire-probe: dropped $(( PRE_DEDUPE_N - RUN_COUNT )) page-overlap duplicate(s) (dedupe key: $DEDUPE_KEY)"
    fi
    # #6178 — NULL-SAFE BUCKETING. The probe projects {functionID, startedAt} from EVERY
    # returned node, and a run that is queued, running, or cancelled-before-start carries
    # startedAt:null. `fromdateiso8601` THROWS on null ("strptime/1 requires string
    # inputs"), and jq's runtime-error exit 5 propagates through `set -euo pipefail` —
    # killing the arm with no verdict. This sat directly behind the window defect on the
    # critical path: narrowing the window alone would have moved the failure from
    # reason=deadline to a jq crash. It stayed invisible because the scan had never once
    # completed far enough to REACH this step.
    #
    # A run with no startedAt has not fired, so it cannot be half of a double-fire —
    # dropping it is semantically right. But it must be dropped DELIBERATELY and
    # COUNTED: silently discarding runs is exactly the false-clean shape this gate
    # exists to prevent.
    NO_START=$(echo "$BODY" | jq '[ .runs[] | select(.startedAt == null) ] | length')
    if [[ "$NO_START" -gt 0 ]]; then
      echo "::notice::doublefire-probe: $NO_START run(s) carry no startedAt (queued/running/cancelled-before-start) and are excluded from bucketing — they have not fired, so they cannot be a double-fire."
    fi
    # #6178 — surface the server's own scan scale. Unlike op=verify (where an empty
    # scan is a VACUOUS verdict and hard-fails), ZERO runs here is the EXPECTED clean
    # state for a dark host, so this is a warning rather than a gate. It still matters:
    # a clean dark-host result over a scan whose scale was never measured is a weaker
    # statement than one over a measured scan.
    TOTAL_COUNT=$(echo "$BODY" | jq -r '.total_count // "absent"')
    if [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]] && (( RUN_COUNT < TOTAL_COUNT )); then
      echo "::warning::doublefire-probe: INCOMPLETE SCAN — deduped=$RUN_COUNT < total_count=$TOTAL_COUNT (pre_dedupe=$PRE_DEDUPE_N, dedupe key: $DEDUPE_KEY); runs were collapsed or missed, so a clean result here is not evidence."
    fi
    if [[ "$TOTAL_COUNT" == "unknown" || "$TOTAL_COUNT" == "absent" ]]; then
      echo "::warning::doublefire-probe: the server did not report a usable totalCount (total_count=$TOTAL_COUNT) — the page-1 feasibility gate did not run and the scan's scale is unmeasured."
    fi
    echo "::notice::doublefire-probe: $RUN_COUNT run(s) in window (server total_count=$TOTAL_COUNT, anchor_source=$DF_ANCHOR_SOURCE, from=$DF_FROM); bucketing by (functionID, floor(startedAt / ${CRON_PERIOD}s))"
    # #6178 — `fromdateiso8601` accepts only whole-second `…:SSZ`; the Postgres-backed dedicated host
    # returns microseconds (`…:34.101119Z`), so the fraction is stripped first (bucketing floors to
    # the cron period anyway). Without it op=verify dies at jq exit 5 on every real run (run 34961424195).
    DUPES=$(echo "$BODY" | jq -c --argjson period "$CRON_PERIOD" '
      [ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) / $period | floor) } ]
      | group_by([.fn, .bucket])
      | map(select(length > 1))
      | map({ functionID: .[0].fn, bucket: .[0].bucket, count: length }) ')
    DUPE_COUNT=$(echo "$DUPES" | jq 'length')
    # ADVERSE is set by either NO-GO branch and consumed at the END of the
    # arm, AFTER the scope caveat prints. This gives the operator the full
    # picture (runs + dupes + caveat) in ONE dispatch *and* a red run — an
    # earlier revision exited 0 to buy the former, which was a false trade:
    # nothing is truncated by deferring the exit to the last statement.
    ADVERSE=0
    if [[ "$DUPE_COUNT" -gt 0 ]]; then
      echo "::error::doublefire-probe: DOUBLE-FIRE detected — $DUPE_COUNT (functionID, tick-bucket) group(s) with >1 run. Details (ids + counts only, AC-NOBODY):"
      echo "$DUPES" | jq -c '.[]'
      ADVERSE=1
    elif [[ "$RUN_COUNT" -gt 0 ]]; then
      echo "::error::doublefire-probe: the dedicated host (10.0.1.40) has EXECUTED $RUN_COUNT cron run(s), with no duplicate tick-bucket. Pre-cutover, ANY run on the dark host means its scheduler is live against a registered SDK — treat this as a live double-scheduler condition even without a duplicate bucket, because the colocated scheduler's runs are NOT in this dataset."
      ADVERSE=1
    else
      echo "::notice::doublefire-probe: ZERO runs on the dedicated host — its scheduler has executed nothing in the window."
    fi
    # Scope caveat carried VERBATIM from op=verify 2.6 (P2-a / DI-C3).
    echo "::notice::doublefire-probe SCOPE CAVEAT (P2-a / DI-C3): the doublefire-probe reads ONLY the dedicated host's (10.0.1.40) run history. It is NOT a web-host double-fire detector — a surviving web-host (colocated) scheduler fires against prod Postgres via its OWN loopback backend PRE-repoint, whose runs never appear on the dedicated host. The web scheduler host (web-1) is the only colocated scheduler (web-2 scope: see op=execute SEAM 2.2a); op=quiesce-web + the op=execute 2.2 QUIESCED gate are the control against a web-host double-fire — this probe cannot substitute for it."
    # NO-GO must be red. Every sibling arm in this workflow exits non-zero on
    # its adverse verdict (re-arm precondition, re-arm PARTIAL, wiped-volume
    # verify); a green run whose annotation says "DOUBLE-FIRE detected" is the
    # #6374 shape — an operator surface presenting an adverse state as
    # non-adverse. The plan cites "workflow run summary" as this failure
    # mode's alert route, and that route is the run's conclusion.
    if [[ "$ADVERSE" -eq 1 ]]; then
      echo "::error::doublefire-probe verdict: NO-GO — do not proceed to the cutover until the above is explained."; exit 1
    fi
    ;;

  rearm)
    # POST hook (mode=rearm-from-capture) → the host script CONSUMES the
    # on-host capture persisted by op=capture (pre-deploy) and re-arms each
    # via the schedule-reminder route, deleting the capture on full success.
    # A missing/corrupt capture is FATAL (non-200) — it never silently
    # self-enumerates the post-deploy empty backend (#5542). A 503 from the
    # schedule-reminder route has TWO causes, named on the host script's own ERROR line:
    # X-Soleur-Unavailable: cutover-quiesce OR X-Soleur-Unavailable: backend-refused.
    # cutover-quiesce (or the header absent) = INNGEST_CUTOVER_QUIESCE is still set — clear
    # it first; backend-refused = the app's Inngest backend is not accepting connections
    # (the INNGEST_BASE_URL repoint has not deployed, or the dedicated host is restarting).
    # Both abort loud with the capture retained; read the body, not the status code.

    # ---- Precondition (P1-9 / P2-17): the dedicated registry MUST be NON-empty
    # before we re-arm against prod scheduling — a still-empty registry means 2.4
    # (app-repoint → functions re-synced onto 10.0.1.40) has not landed and a
    # re-arm would target a backend with no registered functions. GET the web-host
    # registry probe (HMAC over empty body); require function_count > 0.
    RSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/rearm-probe
    RCODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/rearm-probe -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$RSIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-registry-probe" || echo "000")
    RPROBE=$(cat /tmp/rearm-probe 2>/dev/null || echo "")
    if [[ "$RCODE" != "200" ]]; then
      CAUSE="${RPROBE//[$'\n\r']/ }"
      echo "::error::re-arm precondition: registry-probe returned HTTP $RCODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    RCOUNT=$(echo "$RPROBE" | jq -r '.function_count // 0')
    # registry_empty is a BOOLEAN. Do NOT use `.registry_empty // "true"`: jq's `//`
    # treats boolean `false` as empty and returns the RHS, so `false // "true"` = "true"
    # — i.e. a HEALTHY non-empty registry (registry_empty:false) reads as EMPTY and this
    # precondition can never pass against the real post-2.4 backend (#6178). Read the
    # boolean directly, behind a has() presence guard (fail-closed on a malformed body).
    # This is the exact shape op=verify's own `has("registry_empty")` precondition uses —
    # the two guards are meant to mirror each other and had drifted (op=verify's was correct).
    if ! echo "$RPROBE" | jq -e 'type=="object" and has("registry_empty")' >/dev/null 2>&1 \
       || [[ "$(echo "$RPROBE" | jq -r '.registry_empty')" != "false" ]]; then
      echo "::error::re-arm precondition FAILED (P1-9/P2-17): dedicated registry is EMPTY (function_count=$RCOUNT). 2.4 app-repoint has not landed — refusing to re-arm against a backend with no registered functions. Complete 2.4 (repoint INNGEST_BASE_URL → 10.0.1.40 + redeploy) then re-run op=rearm."
      exit 1
    fi
    echo "::notice::re-arm precondition PASSED: dedicated registry NON-empty (function_count=$RCOUNT) — 2.4 landed"
    # P3-c: non-empty ≠ fully-synced. function_count>0 proves the re-sync STARTED, not
    # that EVERY pre-cutover function re-registered. If the pre-cutover op=inventory
    # baseline count is supplied (CUTOVER_REGISTRY_BASELINE), require the dedicated
    # registry to have caught up (>= baseline) so a half-sync cannot pass; else caveat loud.
    BASELINE="${CUTOVER_REGISTRY_BASELINE:-}"
    if [[ -n "$BASELINE" ]]; then
      if ! [[ "$BASELINE" =~ ^[0-9]+$ ]]; then
        echo "::error::CUTOVER_REGISTRY_BASELINE must be an integer (the pre-cutover op=inventory 'functions' count)"; exit 1
      fi
      if [[ "$RCOUNT" -lt "$BASELINE" ]]; then
        echo "::error::re-arm precondition FAILED (P3-c): dedicated registry function_count=$RCOUNT < pre-cutover baseline=$BASELINE — the app re-sync is only PARTIAL (half-synced). Wait for the redeploy to finish registering all functions, confirm function_count>=$BASELINE, then re-run op=rearm."
        exit 1
      fi
      echo "::notice::re-arm precondition: registry fully re-synced (function_count=$RCOUNT >= baseline=$BASELINE, P3-c)"
    else
      echo "::warning::re-arm precondition (P3-c): function_count=$RCOUNT is NON-EMPTY but that only proves the re-sync STARTED, not that EVERY pre-cutover function re-registered. Confirm $RCOUNT matches the pre-cutover op=inventory 'functions' count (or set CUTOVER_REGISTRY_BASELINE to enforce function_count>=baseline) before trusting the re-arm."
    fi

    PAYLOAD='{"mode":"rearm-from-capture"}'
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/rearm-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 120 -o /tmp/rearm-body -w '%{http_code}' \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/inngest-rearm-reminders" || echo "000")
    echo "re-arm response:"; cat /tmp/rearm-body 2>/dev/null || true; echo
    if [[ "$CODE" != "200" ]]; then
      echo "::error::re-arm returned HTTP $CODE (a non-200 includes the host script's loud abort — e.g. a 503 that is cutover-quiesce (INNGEST_CUTOVER_QUIESCE still set) OR backend-refused (the app's Inngest backend is not serving); the response above names which). The capture is retained."; exit 1
    fi
    # ---- Partial-rearm reconciliation (P1-11): the host script's CombinedOutput
    # carries the canonical `inngest-rearm-reminders: re-armed=N failed=F held_back=H total=K`.
    # K is the record count of the persisted capture — the Σcaptured op=execute 2.1 reported
    # (this op runs in a different workflow run, so CI holds no independent Σcaptured; compare
    # K against the SEAM's Σ= line). H counts records the host held back as due before the
    # quiesce (its cutoff is the later of the marker epoch and the unit's stop, computed
    # on-host): they were due while the web scheduler was still running and already fired
    # there, so they are deliberately NOT re-armed. The terms reconcile two ways, both LOUD:
    #   N + F + H == K   else the host's counts are inconsistent → refuse (never a success);
    #   F == 0           else PARTIAL → name the missing reminder_ids and offer the retry.
    # `held_back=` is optional (absent ⇒ 0) so a host script that predates it still parses.
    RBODY=$(cat /tmp/rearm-body 2>/dev/null || echo "")
    RCOUNTS=$(printf '%s\n' "$RBODY" | sed -n 's/^.*re-armed=\([0-9]\{1,\}\) failed=\([0-9]\{1,\}\)\( held_back=\([0-9]\{1,\}\)\)\{0,1\} total=\([0-9]\{1,\}\).*$/\1:\2:\4:\5/p' | tail -n1)
    REARMED=""; RFAILED=""; RHELD=""; RTOTAL=""
    IFS=':' read -r REARMED RFAILED RHELD RTOTAL <<< "$RCOUNTS"
    RHELD="${RHELD:-0}"
    # P2-b: a NON-EMPTY body that lacks the canonical count line must NOT default the counts to
    # 0 and read as a false 0==0 success (silent undercount). Assert the counts parsed from the
    # real (200) response; fail LOUD otherwise.
    if [[ -z "$REARMED" || -z "$RFAILED" || -z "$RTOTAL" ]]; then
      CAUSE="${RBODY//[$'\n\r']/ }"
      echo "::error::re-arm reconciliation FAILED (P2-b): could not parse 're-armed=N failed=F [held_back=H] total=K' from the host response (rearmed='${REARMED:-<unparsed>}' failed='${RFAILED:-<unparsed>}' total='${RTOTAL:-<unparsed>}'). The re-arm returned HTTP 200 but its reconciliation counts are unreadable — refusing to report a false 0==0 success on an unparsed body. Response: ${CAUSE:-<empty body>}. Do NOT proceed to op=verify; re-run op=rearm (the on-host capture is retained on any failure)."
      exit 1
    fi
    if (( 10#$REARMED + 10#$RFAILED + 10#$RHELD != 10#$RTOTAL )); then
      echo "::error::re-arm reconciliation FAILED (P2-b): re-armed=$REARMED + failed=$RFAILED + held_back=$RHELD != total=$RTOTAL — the host's counts do not account for every captured record, so neither success nor the partial-retry path can be trusted. Do NOT proceed to op=verify; pull the inngest-rearm-reminders lines from Better Stack (doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep inngest-rearm-reminders) and file an issue with this run URL."
      exit 1
    fi
    if [[ "$RFAILED" -ne 0 ]]; then
      # Missing reminder_ids the host script named on each failure (ids only, no bodies).
      MISSING=$(printf '%s' "$RBODY" | sed -n 's/.*re-arm failed for reminder_id=\([^ )]*\).*/\1/p' | paste -sd, -)
      echo "::error::re-arm PARTIAL (P1-11): Σcaptured(total)=$RTOTAL = rearmed=$REARMED + held_back=$RHELD + failed=$RFAILED — $RFAILED reminder(s) NOT re-armed. Missing reminder_id(s): [${MISSING:-<unparsed; see body above>}]. RETRY: the on-host capture is retained on any failure, so re-dispatch op=rearm to finish the residual set (the route recomputes dedup ids — no double-fire). Do NOT proceed to op=verify until failed=0."
      exit 1
    fi
    if [[ "$RHELD" -ne 0 ]]; then
      HELD_IDS=$(printf '%s\n' "$RBODY" | sed -n 's/^.*held back [0-9]\{1,\} reminder(s) due before the quiesce: \([^ ]*\).*$/\1/p' | tail -n1)
      echo "::notice::re-arm held back $RHELD reminder(s) due before the quiesce (already fired on the web scheduler, not re-armed): [${HELD_IDS:-<unparsed; see body above>}]"
    fi
    echo "::notice::re-arm completed: rearmed=$REARMED held_back=$RHELD == Σcaptured(total)=$RTOTAL (failed=0; no partial-rearm delta, P1-11)"
    ;;

  capture)
    # POST hook (mode=capture) → the host script self-enumerates the OLD
    # server and persists the still-armed records to an on-host file
    # (/var/lib/inngest/cutover-capture.json) for post-deploy re-arm. Run
    # BEFORE the deploy: a post-deploy self-enumerate sees the empty new
    # backend and would lose every reminder (#5542). Records stay on-host
    # (P2-sec-a) — only counts + reminder_ids surface here.
    PAYLOAD='{"mode":"capture"}'
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/capture-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 60 -o /tmp/capture-body -w '%{http_code}' \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/inngest-rearm-reminders" || echo "000")
    BODY=$(cat /tmp/capture-body 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::capture returned HTTP $CODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e 'type == "object" and has("captured") and has("reminder_ids") and has("capture_file")' >/dev/null 2>&1; then
      echo "::error::capture did not return the expected {captured,reminder_ids,capture_file} object"; echo "$BODY"; exit 1
    fi
    N=$(echo "$BODY" | jq -r '.captured')
    IDS=$(echo "$BODY" | jq -r '.reminder_ids | join(",")')
    FILE=$(echo "$BODY" | jq -r '.capture_file')
    # A quiesced host answers from the capture its quiesce handler persisted (source:"persisted"
    # + captured_at); a serving host enumerates live and carries no `source`. Surface which, so a
    # resumed capture is never read as a fresh one.
    SOURCE=$(echo "$BODY" | jq -r '.source // "live"')
    CAPTURED_AT=$(echo "$BODY" | jq -r '.captured_at // ""')
    echo "::notice::capture: $N reminder(s) in $FILE for post-deploy re-arm (source=$SOURCE captured_at=${CAPTURED_AT:-<now, live>}) — [$IDS]"
    ;;

  verify-wiped-volume)
    # Async (202) destructive op → poll the dedicated verify-status GET
    # for a fresh terminal exit_code. The stop+wipe+restart+settle exceeds
    # the CF 120s edge timeout, so it MUST be async + poll (not synchronous).
    PAYLOAD='{}'
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /dev/null -w '%{http_code}' \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/inngest-wiped-volume-verify" || echo "000")
    if [[ "$CODE" != "202" ]]; then
      echo "::error::wiped-volume verify webhook rejected (HTTP $CODE)"; exit 1
    fi
    # Freshness anchor: the verify-state is a single slot; only honor a
    # terminal state written at/after this trigger (minus clock skew).
    TRIGGER_TS=$(date +%s)
    FRESH_FLOOR=$((TRIGGER_TS - 60))
    GSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    MAX_POLLS=120
    POLL_INTERVAL=10
    for i in $(seq 1 "$MAX_POLLS"); do
      rm -f /tmp/verify-body
      curl --disable --noproxy '*' -s --max-time 10 -o /tmp/verify-body -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$GSIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/inngest-verify-status" >/dev/null || true
      BODY=$(cat /tmp/verify-body 2>/dev/null || echo "")
      if [[ -z "$BODY" ]] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
        echo "Attempt $i/$MAX_POLLS: non-JSON/empty — retrying"; sleep "$POLL_INTERVAL"; continue
      fi
      EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
      START_TS=$(echo "$BODY" | jq -r '.start_ts // 0')
      REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
      case "$EXIT_CODE" in
        -2|-3) echo "Attempt $i/$MAX_POLLS: no/corrupt verify state — retrying" ;;
        0)
          if [ "$START_TS" -lt "$FRESH_FLOOR" ]; then
            echo "Attempt $i/$MAX_POLLS: state predates this trigger — waiting"
          else
            echo "::notice::wiped-volume verify PASSED (reason=$REASON)"; echo "$BODY" | jq .; exit 0
          fi
          ;;
        *)
          if [ "$START_TS" -lt "$FRESH_FLOOR" ]; then
            echo "Attempt $i/$MAX_POLLS: stale state (exit_code=$EXIT_CODE) — waiting"
          else
            echo "::error::wiped-volume verify FAILED (exit_code=$EXIT_CODE, reason=$REASON)"; echo "$BODY" | jq .; exit 1
          fi
          ;;
      esac
      sleep "$POLL_INTERVAL"
    done
    echo "::error::wiped-volume verify did not reach a terminal state within $((MAX_POLLS * POLL_INTERVAL))s"; exit 1
    ;;

  backup)
    # #5509 pre-cutover recovery point: a Hetzner SERVER snapshot of the
    # whole root disk (incl. /var/lib/inngest SQLite). No webhook, no SSH —
    # pure hcloud API. HCLOUD_TOKEN read from the prd_terraform-scoped
    # DOPPLER_TOKEN (never echoed). server id 123931471 = soleur-web-platform.
    HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain)
    TS=$(date -u +%Y%m%dT%H%M%SZ)
    rm -f /tmp/backup-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/backup-body -w '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer $HCLOUD_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"snapshot\",\"description\":\"inngest-cutover-pre-$TS\",\"labels\":{\"purpose\":\"inngest-cutover-pre\",\"ts\":\"$TS\"}}" \
      "https://api.hetzner.cloud/v1/servers/123931471/actions/create_image" || echo "000")
    if [[ "$CODE" != "201" ]]; then
      echo "::error::hcloud create_image returned HTTP $CODE: $(cat /tmp/backup-body 2>/dev/null)"; exit 1
    fi
    IMAGE_ID=$(jq -r '.image.id' < /tmp/backup-body)
    ACTION_ID=$(jq -r '.action.id' < /tmp/backup-body)
    echo "::notice::backup snapshot started: image id=$IMAGE_ID action=$ACTION_ID (label inngest-cutover-pre-$TS)"
    # Poll the action to terminal (snapshot of a running server takes minutes).
    for i in $(seq 1 60); do
      rm -f /tmp/backup-action
      curl --disable --noproxy '*' -s --max-time 15 -o /tmp/backup-action \
        -H "Authorization: Bearer $HCLOUD_TOKEN" \
        "https://api.hetzner.cloud/v1/actions/$ACTION_ID" >/dev/null || true
      ST=$(jq -r '.action.status // "running"' < /tmp/backup-action 2>/dev/null || echo running)
      case "$ST" in
        success) echo "::notice::backup image id=$IMAGE_ID ready (label inngest-cutover-pre-$TS); DELETE after cutover confirmed: DELETE /v1/images/$IMAGE_ID"; exit 0 ;;
        error) echo "::error::backup snapshot action $ACTION_ID failed"; cat /tmp/backup-action 2>/dev/null; exit 1 ;;
        *) echo "Attempt $i/60: snapshot status=$ST — waiting"; sleep 10 ;;
      esac
    done
    echo "::error::backup snapshot did not reach success within 600s (image id=$IMAGE_ID may still complete; check hcloud console)"; exit 1
    ;;

  inventory)
    # #5509 full-state baseline. GET hook → a single JSON OBJECT
    # {functions, event_names, armed_reminders} in the response body. Run
    # ONCE before the cutover and ONCE after; diff the payload-free
    # projections (the runbook documents the expected diff).
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    # #6258 bounded TRANSPORT retry (Deepen Finding 11): the in-script scan is now
    # abandon-safe (the deadline halts the loop that drives the PG load → releases the
    # pool), so a transient two-writer 500 / a 000 stall clears on attempt-2. This wraps
    # ONLY the transport request (000/5xx) — NOT any verdict. Fail-CLOSED after 2 attempts.
    CODE=000; BODY=""
    for attempt in 1 2; do
      rm -f /tmp/inv-body
      CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/inv-body -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$SIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/inngest-inventory" || echo "000")
      BODY=$(cat /tmp/inv-body 2>/dev/null || echo "")
      [[ "$CODE" == "200" ]] && break
      if [[ "$attempt" -lt 2 ]]; then
        echo "::warning::inventory transport HTTP $CODE (attempt $attempt/2) — retrying in 5s (the abandon-safe scan should have released the pool)"; sleep 5
      fi
    done
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::inventory returned HTTP $CODE after 2 attempts: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e 'type == "object" and has("functions") and has("event_names") and has("armed_reminders")' >/dev/null 2>&1; then
      echo "::error::inventory did not return the expected {functions,event_names,armed_reminders} object"; echo "$BODY"; exit 1
    fi
    FN=$(echo "$BODY" | jq '.functions | length')
    EV=$(echo "$BODY" | jq '.event_names | length')
    AR=$(echo "$BODY" | jq '.armed_reminders | length')
    echo "::notice::inventory: functions=$FN event_names=$EV armed_reminders=$AR"
    # Payload-free, key-sorted baseline for the before/after diff (P2-sec-a:
    # names + reminder_ids only — armed_reminders bodies stay out of the run log).
    echo "Inventory baseline (capture this block for the BEFORE/AFTER diff):"
    echo "$BODY" | jq -S '{functions, event_names, armed_reminder_ids: ([.armed_reminders[].reminder_id] | sort)}'
    ;;

  execute)
    # op=execute — PRE-FLIP orchestrator (#6178, ADR-100 Phase-2). AUTHORING
    # only: it runs the CI-expressible web-host spine (2.0 empty-registry probe →
    # 2.1 capture → 2.2 quiesce HARD GATE) and then GATES the operator
    # maintenance-window steps (Doppler flip arm + 2.4 app-repoint) as a printed
    # SEAM. It NEVER performs a prod-write from CI
    # (hr-menu-option-ack-not-prod-write-auth; inngest-host.tf keeps the flip out
    # of CI) and NEVER SSHes (hr-no-ssh-fallback-in-runbooks) — every host touch
    # is a web-host webhook that forwards over the private net.

    # ---- $CUTOVER_HOSTS computed ONCE in the step env (P1-8 / DI-C3): the SAME
    # host-set is used for 2.1 capture and 2.2 quiesce — they cannot drift because
    # there is exactly one variable. Min-cardinality guard: refuse an empty set.
    if [[ -z "${CUTOVER_HOSTS:-}" ]]; then
      echo "::error::CUTOVER_HOSTS is empty — refusing to run execute against an empty host-set"; exit 1
    fi
    IFS=',' read -r -a HOSTS <<< "$CUTOVER_HOSTS"
    if [[ "${#HOSTS[@]}" -lt 1 ]]; then
      echo "::error::CUTOVER_HOSTS parsed to zero hosts (value: '$CUTOVER_HOSTS')"; exit 1
    fi
    echo "::notice::execute: cutover host-set (2.1 capture == 2.2 quiesce, P1-8) = [$CUTOVER_HOSTS] (${#HOSTS[@]} host(s))"

    # ---- 2.-1 POOL PRE-CHECK (#6258). Runs BEFORE the 2.0 registry probe on
    # purpose: 2.0 itself opens a GQL→Postgres connection that would otherwise be
    # counted against this readiness baseline. Reads inngest-attributable backends
    # on the dedicated soleur-inngest-prd project (ref pigsfuxruiopinouvjwy) via the
    # read-only Management API — the SAME filter scheduled-inngest-health.yml uses.
    # GATE INTENT: refuse the flip unless the pool has enough free headroom that the
    # 2.1 capture + 2.2 quiesce scans cannot ratchet it to EMAXCONNSESSION MID-FLIP.
    # We gate on a READINESS BASELINE + BURST HEADROOM, NOT the 80%-of-cap pressure
    # line (a pool at 79% passes that alert but capture+quiesce then push it over the
    # cap — the exact failure this gate exists to prevent). Assert:
    #   inngest_conns + EXPECTED_BURST_COST ≤ POOL_SIZE − SUPAVISOR_WARM_RESERVE
    # POOL_SIZE=30 (Supavisor default_pool_size — stays 30 per ADR-105); reserve ~8
    # for Supavisor warm + the mgmt probe; ~10 for the capture+quiesce burst draw →
    # readiness ceiling = 30−8−10 = 12. FAIL-CLOSED on EVERY non-clean state (count
    # ≥ ceiling / EMAXCONNSESSION / 401/403/non-2xx / non-JSON / empty / token-unset /
    # curl-fail) — never a false 0==0 "clean" on an unparsed count.
    # POOL_SIZE mirrors the inngest project's Supavisor default_pool_size, kept at
    # 30 per ADR-105 (the #5562 30→15 revert is superseded). If that decision is ever
    # revisited (decision-challenges.md), reconcile this constant + READINESS_CEILING —
    # a stale 30 here would over-permit the gate against a smaller live pool.
    POOL_SIZE=30
    SUPAVISOR_WARM_RESERVE=8
    EXPECTED_BURST_COST=10
    READINESS_CEILING=$(( POOL_SIZE - SUPAVISOR_WARM_RESERVE - EXPECTED_BURST_COST ))
    if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): SUPABASE_ACCESS_TOKEN unset — cannot read pg_stat_activity. Refusing to flip against an unverifiable pool. Set the GH secret (TF github_actions_secret.supabase_access_token) + Doppler prd."; exit 1
    fi
    # Endpoint pinned to api.supabase.com — NO env override (a host seam is a
    # PAT-exfil-via-redirect surface). The 2>/dev/null redirect keeps the
    # Authorization header out of $POOL_RESP. NOTE: this block runs under
    # `set -euo pipefail` (unlike the `set -uo` sibling in scheduled-inngest-health.yml),
    # so the rc is captured via `|| POOL_RC=$?` — a bare `$(…)` capture + `$?`
    # would let `set -e` abort at the assignment on a non-zero exit BEFORE the rc read,
    # making the failure branch dead (still fail-closed via the abort, but non-diagnostic).
    POOL_RC=0
    POOL_RESP="$(curl --disable --noproxy '*' --silent --show-error \
      --request POST \
      --url "https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query" \
      --header "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
      --header "Content-Type: application/json" \
      --data '{"query":"select coalesce(application_name,'\''(none)'\'') as app, usename, state, count(*)::int as n from pg_stat_activity where backend_type = '\''client backend'\'' and query not ilike '\''%pg_stat_activity%'\'' group by 1,2,3 order by 4 desc"}' \
      --max-time 15 \
      -w $'\n%{http_code}' \
      2>/dev/null)" || POOL_RC=$?
    POOL_HTTP="${POOL_RESP##*$'\n'}"
    POOL_BODY="${POOL_RESP%$'\n'*}"
    # Bounded, newline-stripped body for logs (app_name is client-settable —
    # never echo it unbounded; head -c 300 defense-in-depth against log injection).
    # `sed` redacts any sbp_ Management-API PAT for parity with the sibling's scrub_pat
    # (defense-in-depth — the response body cannot contain the request Authorization
    # header, but a future error-body reflecting request context would). Trailing
    # `|| true` stops a head -c 300 SIGPIPE from aborting the step under set -e/pipefail.
    PAT_SCRUB='s/sbp_[A-Za-z0-9]{20,}/[REDACTED-PAT]/g'
    POOL_BODY_SAFE="$(printf '%s' "$POOL_BODY" | tr -d '\r' | tr '\n' ' ' | sed -E "$PAT_SCRUB" | head -c 300 || true)"
    if [[ "$POOL_RC" != "0" ]]; then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): curl(rc=$POOL_RC) against the Management API — pool unverifiable, refusing to flip."; exit 1
    fi
    if printf '%s' "$POOL_BODY" | grep -qF 'EMAXCONNSESSION'; then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): pool ALREADY at the cap (EMAXCONNSESSION in body). Restart web-host inngest (restart-inngest-server.yml) to drop the pinned pool, re-run op=inventory clean, THEN re-run op=execute. body=${POOL_BODY_SAFE}"; exit 1
    fi
    if [[ "$POOL_HTTP" != 2?? ]]; then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): Management API HTTP $POOL_HTTP (401/403 = token/scope; 5xx = pooler). Refusing to flip on an unreadable pool. body=${POOL_BODY_SAFE}"; exit 1
    fi
    if ! printf '%s' "$POOL_BODY" | jq -e 'type == "array"' >/dev/null 2>&1; then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): body is not a JSON array — cannot compute a count, refusing to flip. body=${POOL_BODY_SAFE}"; exit 1
    fi
    INNGEST_CONNS=$(printf '%s' "$POOL_BODY" | jq '[.[] | select(.usename == "postgres" and (.app | startswith("Supavisor") | not) and .app != "mgmt-api") | .n] | add // 0')
    POOL_BREAKDOWN="$(printf '%s' "$POOL_BODY" | jq -r '.[] | "\(.usename // "?")/\(.app)/\(.state // "null")=\(.n)"' | tr '\n' ' ' | sed -E "$PAT_SCRUB" | head -c 300 || true)"
    if ! [[ "$INNGEST_CONNS" =~ ^[0-9]+$ ]]; then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): inngest-attributable count non-numeric ('$INNGEST_CONNS') — refusing to flip. breakdown: ${POOL_BREAKDOWN}"; exit 1
    fi
    if (( INNGEST_CONNS + EXPECTED_BURST_COST > POOL_SIZE - SUPAVISOR_WARM_RESERVE )); then
      echo "::error::2.-1 POOL PRE-CHECK FAIL-CLOSED (#6258): inngest_conns=$INNGEST_CONNS + burst=$EXPECTED_BURST_COST exceeds readiness ceiling $READINESS_CEILING (pool_size $POOL_SIZE − warm $SUPAVISOR_WARM_RESERVE). Capture/quiesce would ratchet the pool over the cap mid-flip. Restart web-host inngest (restart-inngest-server.yml) + confirm op=inventory clean, THEN re-run op=execute. breakdown: ${POOL_BREAKDOWN}"; exit 1
    fi
    echo "::notice::2.-1 pool pre-check CLEAN — inngest_conns=$INNGEST_CONNS ≤ readiness ceiling $READINESS_CEILING (burst headroom OK). breakdown: ${POOL_BREAKDOWN}"

    # ---- 2.0 empty-registry pre-flight (P1-6). GET the web-host registry probe
    # (HMAC over empty body); it forwards the { functions { id } } query to the
    # dedicated host GQL over the private net. registry_empty MUST be true — a
    # non-empty dark registry means a second scheduler would register + double-fire
    # against prod Postgres, the exact failure this cutover exists to prevent.
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/exec-probe
    CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/exec-probe -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-registry-probe" || echo "000")
    BODY=$(cat /tmp/exec-probe 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      # ---- 2.0 DARK ARM (#8054). A non-200 here is the EXPECTED pre-arm state, not a fault:
      # inngest-server-flip-guard.sh (P1-5) refuses a prod-URI start while INNGEST_CUTOVER_FLIP is
      # outside {armed,flipping,flushed,done}, every pre-arm value is outside it, and the flag
      # leaves that set only via op=arm — which runs AFTER this step. So the webhook's GQL forward
      # cannot succeed on the first execute of a cutover, and until #8054 this branch was
      # `exit 1`, making 2.0 unrunnable in the very sequence it guards (same class as #8017).
      #
      # 2.0's real property is "the dedicated host carries no registry that could double-fire".
      # A host that CANNOT START satisfies it more strongly than one that answered empty — so
      # darkness is graded POSITIVELY from the host's own rows: the hourly SOLEUR_INNGEST_SERVER_PROBE
      # row (http_code=000, server_active!=active, registry_fns=__UNREADABLE__, cutover_flag pre-arm,
      # current boot) plus the flip FSM's ~1/min heartbeat on the SAME boot attesting the flag is
      # still pre-arm within 15 min. Silence is not darkness: every state in which darkness cannot
      # be established refuses. The gate is tests/scripts/lib/inngest-host-dark-gate.sh's second
      # entry point; its E-table names every lib token below and the remedy each one carries. One
      # refusal is this script's own and precedes the gate: `webhook_path` (below).
      # THE NON-200 MUST BE THE DEDICATED HOST'S FETCH FAILURE, NOT THE WEBHOOK PATH'S. The web-host
      # probe (inngest-registry-probe.sh) exits 1 — HTTP 500 through the hook's error passthrough —
      # with `errors=["__FETCH_FAILED__"]` when ITS OWN fetch of 10.0.1.40:8288/v0/gql failed:
      # connection refused, connect-timeout (host off / private-net drop), or a mid-request
      # failure — curl's rc is not preserved, so this is "the GQL endpoint did not answer the web
      # host just now", not specifically "refused". It is still the only SYNCHRONOUS reading this
      # step ever sees; the hourly probe row (up to 90 min old) and the FSM heartbeat (a flag, not
      # a port) cannot supply it, and the gate's E14 closes the window in which a stale probe row
      # could outlive an FSM transition. A CF Access 403, a WAF 5xx, webhook.service down (000/502)
      # or a GQL error from a REACHABLE server all arrive here as non-200 too, and none of them
      # says anything about the host — so they refuse, naming the webhook path (2.1 capture uses
      # the same path and would have failed on them anyway). Only the fetch-failure signature
      # enters the dark arm. `webhook_path` is a script-level refusal, not one of the lib's tokens.
      if [[ "$CODE" != "500" || "$BODY" != *"__FETCH_FAILED__"* ]]; then
        echo "::error::2.0 REFUSED (webhook_path): the registry-probe webhook returned HTTP $CODE without the dedicated host's fetch-failure signature (inngest-registry-probe: FATAL … __FETCH_FAILED__), so this is a WEBHOOK-PATH fault, not evidence about the host. Check the path first: gh workflow run cutover-inngest.yml -f op=registry-probe (CF Access / WAF / webhook.service on the web host); when it returns the __FETCH_FAILED__ refusal or HTTP 200, re-dispatch op=execute. Do NOT SSH the host."
        echo "2.0 webhook body (HTTP $CODE): ${CAUSE:-<empty body>}"
        exit 1
      fi
      echo "::notice::2.0 expected pre-arm (P1-5): webhook probe HTTP $CODE carries the dedicated host's fetch-failure signature (the web host could not reach 10.0.1.40:8288 just now) — grading darkness from the host's own rows"
      # The webhook body is a question phrased as a fault ("is the dedicated inngest-server
      # reachable?") and must not sit bare inside an annotation next to a green step — but it is
      # the live corroboration the gate below cannot read, so it IS printed: once, as a plain line,
      # CR/LF-stripped.
      echo "2.0 webhook body (HTTP $CODE, informational — grading from host rows): ${CAUSE:-<empty body>}"
      # shellcheck source=tests/scripts/lib/inngest-host-dark-gate.sh
      source tests/scripts/lib/inngest-host-dark-gate.sh || { echo "::error::2.0: gate library tests/scripts/lib/inngest-host-dark-gate.sh not found on this ref — dispatch with --ref main"; exit 1; }
      # Two reads, two files, ONE --grep term each (see _bs_query_rows). The rows are full journald
      # payloads from the prod host: `mktemp -d` creates the directory 0700 (so every file under it
      # is unreadable to other users without a process-wide umask change), removed on exit, and
      # NEVER echoed — the gate's stdout is exactly one token and its notice fields come back
      # through --emit-file, each written only after the predicate that validated it.
      ERG_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/erg.XXXXXXXX") || { echo "::error::2.0: mktemp -d failed under ${RUNNER_TEMP:-/tmp}"; exit 1; }
      trap 'rm -rf "$ERG_DIR"' EXIT
      PROBE_ROWS="$ERG_DIR/probe.rows"; PROBE_ERR="$ERG_DIR/probe.err"
      HB_ROWS="$ERG_DIR/hb.rows";       HB_ERR="$ERG_DIR/hb.err"
      ERG_EMIT="$ERG_DIR/emit.txt"
      # WINDOWS ARE NOT BOUNDS. Freshness is decided by the gate (`--max-row-age` 5400 s on the probe
      # row, `--hb-max-age` 900 s on the heartbeat); the `--since` windows only have to be WIDER than
      # those bounds so that `stale_row` / `fsm_silent` are reachable verdicts — a 90m probe window
      # would return no row older than the bound and collapse `stale_row` into `silent`. 24h at
      # --limit 500 holds ~48 hourly probe rows (BOTH hosts run the shared renderer and ship to one
      # source; the gate isolates the dedicated host after decoding) plus the previous boot's; the
      # reader returns the NEWEST rows under --limit, so the graded row is never displaced. 30m at
      # --limit 200 holds the ~30-60 heartbeats a live FSM emits in that window, and 30m > 900 s
      # keeps the age bound a real bound (the arm-side liveness read's 15m window is a different
      # operand for a different gate and is not reused here).
      PROBE_RC=0; _bs_query_rows 24h SOLEUR_INNGEST_SERVER_PROBE 500 "$PROBE_ERR" > "$PROBE_ROWS" || PROBE_RC=$?
      HB_RC=0;    _bs_query_rows 30m inngest-cutover-flip 200 "$HB_ERR" > "$HB_ROWS" || HB_RC=$?
      # The emit file exists BEFORE the gate runs: the gate truncates it after argument parsing, so a
      # refusal inside the parser would otherwise leave nothing for the read loop below to open, and
      # under `set -e` a failed redirection aborts the script before the `case` prints the token.
      : > "$ERG_EMIT"
      # THE CALL SHAPE IS LOAD-BEARING under `set -e`: every refusal returns non-zero, and a bare
      # `ERG_VERDICT=$(…)` would abort the script before the `case` — fail-closed but MUTE, with no
      # `::error::` and no remedy ever printed. `|| ERG_RC=$?` lets every token reach the `case`.
      ERG_RC=0
      ERG_VERDICT="$(inngest_execute_registry_gate --rows-file "$PROBE_ROWS" --query-rc "$PROBE_RC" --hb-file "$HB_ROWS" --hb-rc "$HB_RC" --emit-file "$ERG_EMIT" --host "$INNGEST_HOST" --host-name "$INNGEST_HOST_NAME")" || ERG_RC=$?
      # Every field this arm ever prints comes from the emit file, read ONCE here behind a shape
      # regex — no second selection, no re-parse of a raw row in this script. A field the gate did
      # not reach (it refused earlier) stays at its sentinel.
      ERG_FLAG="__UNREAD__"; ERG_BOOT="__UNREAD__"; ERG_ROW_AGE="__UNREAD__"; ERG_HB_AGE="__UNREAD__"; ERG_HB_FLAG="__UNREAD__"
      while IFS= read -r _erg_line; do
        [[ "$_erg_line" =~ ^(flag|boot_id|row_age|hb_age|hb_flag)=([A-Za-z0-9_-]{1,64})$ ]] || continue
        case "${BASH_REMATCH[1]}" in
          flag)    ERG_FLAG="${BASH_REMATCH[2]}" ;;
          boot_id) ERG_BOOT="${BASH_REMATCH[2]}" ;;
          row_age) ERG_ROW_AGE="${BASH_REMATCH[2]}" ;;
          hb_age)  ERG_HB_AGE="${BASH_REMATCH[2]}" ;;
          hb_flag) ERG_HB_FLAG="${BASH_REMATCH[2]}" ;;
        esac
      done < "$ERG_EMIT"
      case "$ERG_VERDICT" in
        dark)
          # Token AND rc. `_ihdg_verdict` maps `dark` to rc 0; a `dark` with any other rc is a gate
          # defect and is treated as one, never as a pass.
          if [[ "$ERG_RC" -ne 0 ]]; then
            echo "::error::2.0 REFUSED: the dark-host gate printed dark but exited rc=$ERG_RC — token and exit code disagree. This is a defect in the gate, not a host state — file an issue with this run URL; do not proceed."; exit 1
          fi
          echo "::notice::2.0 dark-host arm PASSED — the dedicated host is positively dark on boot_id=$ERG_BOOT: probe row ${ERG_ROW_AGE}s old with flag=$ERG_FLAG, FSM heartbeat ${ERG_HB_AGE}s old with flag=$ERG_HB_FLAG. The dedicated host is intentionally refusing to start until op=arm; a non-200 loopback with the server not active is the correct pre-flip posture, not a fault. No registry can double-fire from a host that cannot start — pre-flight clear." ;;
        unreadable)
          if [[ "$PROBE_RC" -ne 0 ]]; then
            _bs_read_remedy probe "$PROBE_RC" "$PROBE_ERR" "$PROBE_ROWS"
          else
            echo "::error::2.0 REFUSED (unreadable): the probe read answered (rc=0) but the dedicated host's newest row could not be graded — rows arrived but did not decode, two rows at the newest dt disagree, or a field is absent/malformed/incoherent (a truncated row is the #7674 field-order lesson; a numeric registry_fns beside http_code=000 is the emitter contradicting itself). If it is a tie, wait one probe period (<= 60 min) and re-dispatch; otherwise file an issue with this run URL against inngest-bootstrap.sh. Nothing was changed."
          fi
          exit 1 ;;
        silent)
          echo "::error::2.0 REFUSED (silent): the read path answered but the dedicated host emitted NO probe row in the window — silence is not darkness. Read the latest health run: gh run list --workflow scheduled-inngest-health.yml --limit 1, then gh run view <id> --log | grep '#7674 dedicated host'. Two consecutive probe-unavailable readings there make it: gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason=<why> (the only no-SSH path to a dead Vector/timer). Do NOT SSH the host."; exit 1 ;;
        wrong_host)
          echo "::error::2.0 REFUSED (wrong_host): probe rows are present but none carries the dedicated host's identity (host=$INNGEST_HOST AND host_name=$INNGEST_HOST_NAME AND host_role=dedicated) — an identity mislabel (#6616 class). File an issue with this run URL; the host is not the problem and needs no action."; exit 1 ;;
        stale_row)
          echo "::error::2.0 REFUSED (stale_row): the dedicated host's newest probe row is older than the gate's bound (or future-dated). Wait for the next hourly probe and re-dispatch op=execute; if it stays stale, treat it as silent (see that remedy). There is no no-SSH way to fire the probe early."; exit 1 ;;
        stale_schema)
          echo "::error::2.0 REFUSED (stale_schema): the dedicated host's probe row is not probe_schema=${_IHDG_EXPECTED_SCHEMA} — the emitter is BAKED, so it needs a host replace on a pin that carries the schema-${_IHDG_EXPECTED_SCHEMA} emitter. Confirm first: git show vinngest-<pin>:apps/web-platform/infra/inngest-bootstrap.sh | grep -c "^probe_schema=${_IHDG_EXPECTED_SCHEMA}$" (a replace on an unbumped pin re-delivers the same bytes), then gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason=<why>."; exit 1 ;;
        host_serving)
          echo "::error::2.0 REFUSED (host_serving): the dedicated host's own row says it is serving (loopback 200 or unit active) while the webhook returned HTTP $CODE — the row and the webhook disagree. Check the WEBHOOK path first: gh workflow run cutover-inngest.yml -f op=registry-probe (CF Access / WAF / web host). If that returns 200 the host IS serving pre-arm: gh workflow run cutover-inngest.yml -f op=doublefire-probe -f cron_period_seconds=1200; a double-fire means op=rollback; clean means re-dispatch op=execute. Do NOT SSH the host."; exit 1 ;;
        flag_armed)
          # TWO SOURCES, DIFFERENT AGES. E11 grades the HOURLY probe row's flag (up to 90 min old)
          # before E13 grades the ~1/min heartbeat, so `hb_flag` is still unread here when the probe
          # row refused — and a probe row sampled mid-arm reads `armed` for up to an hour after the
          # arm has aborted. The remedy must say which sample it is quoting.
          if [[ "$ERG_HB_FLAG" == "__UNREAD__" ]]; then
            echo "::error::2.0 REFUSED (flag_armed): the dedicated host's newest HOURLY probe row (${ERG_ROW_AGE}s old) reads INNGEST_CUTOVER_FLIP='$ERG_FLAG' — inside the P1-5 arm set. If that arm is still in flight, read its run and do NOT re-dispatch execute; if it has since aborted or rolled back, this row is a stale sample and the refusal is conservative — wait for the next hourly probe row (<= 60 min) and re-dispatch op=execute. done => the cutover already completed: dispatch op=verify. flushed => dispatch op=resume."
          else
            echo "::error::2.0 REFUSED (flag_armed): the flip FSM's newest same-boot heartbeat (${ERG_HB_AGE}s old) reads INNGEST_CUTOVER_FLIP='$ERG_HB_FLAG' — inside the P1-5 arm set, so execute is out of sequence. done => the cutover already completed: dispatch op=verify. armed/flipping => an arm is in flight: read that run, do NOT re-dispatch execute. flushed => dispatch op=resume."
          fi
          exit 1 ;;
        flag_unreadable)
          if [[ "$ERG_HB_FLAG" == "__UNREAD__" ]]; then
            echo "::error::2.0 REFUSED (flag_unreadable): the dedicated host's newest HOURLY probe row (${ERG_ROW_AGE}s old) reads a cutover flag that is neither pre-arm nor in the arm set — the emitter could not read it ('unknown': a Doppler read failure, OR a host that has NEVER been armed and so has no INNGEST_CUTOVER_FLIP at all) or it is mid-transition ('rollback'). Mid-transition: wait for the next hourly probe row (<= 60 min) and re-dispatch op=execute. Never-armed host: this gate refuses it by design (positive allowlist); file an issue naming this run so the first execute on a fresh host can be planned — do NOT write the flag by hand."
          else
            echo "::error::2.0 REFUSED (flag_unreadable): the flip FSM's newest same-boot heartbeat (${ERG_HB_AGE}s old) reads a cutover flag that is neither pre-arm nor in the arm set ('${ERG_HB_FLAG}' — 'rollback' is mid-transition; 'unset' is a never-armed host). Mid-transition: re-dispatch op=execute in a few minutes (the FSM ticks every 30 s). Never-armed host: this gate refuses it by design; file an issue naming this run — do NOT write the flag by hand."
          fi
          exit 1 ;;
        fsm_silent)
          echo "::error::2.0 REFUSED (fsm_silent): the probe row is dark but the flip FSM has not reported on THIS boot within the gate's 15-minute heartbeat bound — freshness cannot be established. Re-dispatch op=execute after >= 15 min. A SECOND fsm_silent with the probe row still dark means inngest-cutover-flip.timer or Vector is down on a host the probe still sees: gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason=<why> (the health workflow reads the probe stream, not the heartbeat, so it cannot supply that second reading). Do NOT SSH the host."; exit 1 ;;
        fsm_unreadable)
          if [[ "$HB_RC" -ne 0 ]]; then
            _bs_read_remedy heartbeat "$HB_RC" "$HB_ERR" "$HB_ROWS"
          else
            echo "::error::2.0 REFUSED (fsm_unreadable): the heartbeat read answered (rc=0) but its rows could not be graded — bytes that did not decode; two rows at the newest dt that disagree; or same-boot heartbeat rows PRESENT with none (or not the newest JSON-shaped one) parsed to an object. The FSM logs each heartbeat as a JSON string, Vector ships it as a string, and Better Stack parses it at ingest — so an unparsed JSON heartbeat is a READ-PATH change on the warehouse, not a dead timer: do NOT replace the host for it. (The FSM also logs plain-text lines under the same tag — VERIFY_FAILED, latch-unrecordable — those are skipped, never graded.) File an issue with this run URL. Nothing was changed."
          fi
          exit 1 ;;
        *)
          # The gate's stdout is the WHOLE of ERG_VERDICT; this arm exists for a gate defect, and a
          # defect is exactly when stdout might carry something other than a token — so print it
          # sanitised (32 chars, lowercase/underscore only) with both rcs, never raw.
          ERG_SAN="${ERG_VERDICT:0:32}"; ERG_SAN="${ERG_SAN//[^a-z_]/?}"
          echo "::error::2.0 REFUSED: the dark-host gate returned an unrecognised verdict '${ERG_SAN}' (gate rc=$ERG_RC, probe read rc=$PROBE_RC, heartbeat read rc=$HB_RC). This is a defect in the gate, not a host state — file an issue with this run URL; do not proceed."; exit 1 ;;
      esac
    else
      if ! echo "$BODY" | jq -e 'type == "object" and has("registry_empty")' >/dev/null 2>&1; then
        echo "::error::2.0 registry-probe did not return a {registry_empty,...} object"; echo "$BODY"; exit 1
      fi
      REG_EMPTY=$(echo "$BODY" | jq -r '.registry_empty')
      REG_COUNT=$(echo "$BODY" | jq -r '.function_count // 0')
      if [[ "$REG_EMPTY" != "true" ]]; then
        echo "::error::2.0 ABORT — dark registry is NON-empty (function_count=$REG_COUNT). The cutover flip must only run against an EMPTY dark registry or a second scheduler double-fires against prod Postgres."
        # D4 (#8054): step (2) used to tell the operator to stop a server that P1-5 already
        # keeps from starting — an unperformable remedy. This path never runs the gate, so no
        # ERG_* value exists here (under set -u an interpolation would abort with no remedy
        # printed): the replacement names a read the OPERATOR performs.
        echo "::error::Remediation (P1-6): (1) read INNGEST_POSTGRES_URI on soleur-inngest/prd and record which backend it targets — do NOT assume it is non-prod: a successful op=arm writes the PROD DSN there and op=rollback has no inverse for that write, so since the first arm (2026-07-23) it holds the prod value as its documented steady state (ADR-100 addendum 2026-08-20); (2) read the cutover flag from the latest health run — gh run list --workflow scheduled-inngest-health.yml --limit 1, then gh run view <id> --log | grep -oE \"cutover_flag='?[a-z-]+\". If it is done, the cutover already completed — dispatch op=verify; if armed/flipping, an arm is in flight — read that run, do not re-dispatch execute; if flushed, dispatch op=resume; (3) if the flag is pre-arm and the registry is still non-empty, the dedicated server started outside the guard — dispatch op=doublefire-probe -f cron_period_seconds=1200, then op=rollback. Do NOT proceed to the flip."
        exit 1
      fi
      echo "::notice::2.0 registry-probe: dark registry EMPTY (function_count=$REG_COUNT) — pre-flight clear"
      echo "::warning::2.0: a dedicated host that ANSWERS pre-arm is out of sequence (P1-5 should keep it dark); the empty registry still satisfies 2.0 — see #8072"
    fi

    # ---- 2.1 capture (web-1, DI-C3, tracked #6227). This is a SINGLE POST to the
    # inngest-rearm-reminders hook. The deploy. tunnel ingress pins its origin to web-1
    # (tunnel.tf `web_hosts["web-1"]`), so every /hooks/* call lands on the web scheduler
    # host — there is no load balancer in front of it. The host script persists the
    # still-armed records on-host; only counts + reminder_ids surface here
    # (P2-sec-a / AC-NOBODY). Σcaptured feeds the D.4 rearm reconciliation.
    #   SCOPE: no per-host capture fan-out — web-2 holds no scheduler (see SEAM 2.2a below).
    #   RESUME (#6921): after op=quiesce-web the web scheduler is stopped, so a live
    # enumeration is impossible. The quiesce handler captured the still-armed reminders
    # BEFORE it stopped the unit; while the unit is in the quiesced shape the host answers
    # from that persisted capture with source:"persisted" + captured_at. A serving host
    # answers live and carries no `source` field, so the absent field IS the live marker.
    # A serving host whose enumeration fails still fails here (never a stale-file fallback).
    # SOURCE is kept for 2.2: its UNKNOWN remedy branches on it.
    PAYLOAD='{"mode":"capture"}'
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/exec-capture
    CODE=$(curl --disable --noproxy '*' -s --max-time 60 -o /tmp/exec-capture -w '%{http_code}' \
      -X POST -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/inngest-rearm-reminders" || echo "000")
    BODY=$(cat /tmp/exec-capture 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::2.1 capture returned HTTP $CODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    SIGMA_CAPTURED=$(echo "$BODY" | jq -r '.captured // 0')
    SOURCE=$(echo "$BODY" | jq -r '.source // "live"')
    CAPTURED_AT=$(echo "$BODY" | jq -r '.captured_at // ""')
    QUIESCED_SINCE=$(echo "$BODY" | jq -r '.quiesced_since // ""')
    # A BOOLEAN — never `// ""`: jq's `//` treats `false` as empty (the registry_empty trap), so a
    # rebooted=false resume would print blank. Absent → "", present → its literal true|false.
    REBOOTED_SINCE_QUIESCE=$(echo "$BODY" | jq -r '.rebooted_since_quiesce | if . == null then "" else tostring end')
    CAPTURED_AT_NOTE=""
    if [[ "$SOURCE" == "persisted" ]]; then
      CAPTURED_AT_NOTE=" captured_at=$CAPTURED_AT quiesced_since=$QUIESCED_SINCE rebooted_since_quiesce=$REBOOTED_SINCE_QUIESCE"
    fi
    echo "::notice::2.1 capture: Σcaptured=$SIGMA_CAPTURED source=$SOURCE${CAPTURED_AT_NOTE} across host-set [$CUTOVER_HOSTS] (records on-host; reminder_ids-only surfaced)"

    # ---- 2.2 QUIESCE HARD GATE (P1-7) — web-1 (DI-C3, tracked #6227). The web-host
    # scheduler MUST be provably quiesced BEFORE the SEAM is printed — arming the flip while
    # an old scheduler survives creates a second live scheduler on prod Postgres (the
    # double-fire).
    #   SCOPE: the inngest-inventory hook reaches 127.0.0.1:8288 on web-1 — the deploy. tunnel
    # ingress origin (tunnel.tf pins it to web_hosts["web-1"]; no load balancer). web-2 holds no
    # scheduler to probe (see SEAM 2.2a below). Iterating $CUTOVER_HOSTS here would re-probe
    # the SAME web-1 every time and falsely imply per-host coverage, so we DO NOT loop the host-set.
    #   WHAT IS CERTIFIED (#6921, Guard 3): not a "stable non-200" proxy — a crash-looping
    # still-ENABLED unit or a broken inventory script also answers non-200, and an enabled
    # scheduler can come back mid-flip. The gate certifies the quiesced UNIT SHAPE
    # (is-active inactive|failed AND is-enabled disabled AND a valid quiesce marker), which
    # only op=quiesce-web's quiesce handler writes and only op=rollback's enable handler
    # clears; the on-host inventory script reports it as a body line starting
    # `inngest-inventory: QUIESCED` (anchored — a FATAL that merely mentions the word does not).
    # Classification, re-probed CUTOVER_QUIESCE_PROBES (default 3) times (fail-CLOSED):
    #   * HTTP 200 (any probe)                    → inngest SERVING → STILL RUNNING → block.
    #   * any body `inngest-inventory:            → the unit is disabled with NO valid marker (not
    #     DISABLED_UNATTRIBUTED`                    a deliberate quiesce) → UNKNOWN → op=rollback.
    #   * ≥1 answered non-200 AND EVERY answered  → the host reported the quiesced shape → PASSED.
    #     non-200 body carries the sentinel         One sentinel is not a quorum: a QUIESCED answer
    #                                               beside a FATAL one certifies nothing.
    #   * answered, not every body certified      → UNKNOWN → block. The remedy branches on the HTTP
    #                                               class FIRST (403 CF-Access/HMAC, 404 hook not
    #                                               deployed, an answer with no inngest-inventory:
    #                                               line = the gateway), because such an answer says
    #                                               nothing about the unit; only a real inventory
    #                                               answer branches on 2.1's SOURCE (persisted ⇒ the
    #                                               rearm script from the same push saw the quiesced
    #                                               shape, so the inventory script is stale; live ⇒
    #                                               the unit is not in the shape yet).
    #   * transport failure only (000)            → UNREADABLE → UNKNOWN → block. A 000 is no answer:
    #                                               it neither certifies nor disqualifies.
    # The loop never stops on a sentinel: a 200 on a LATER probe still wins.
    # STILL_RUNNING **and** UNKNOWN both withhold the SEAM + exit non-zero. On the
    # DEDICATED host the inngest-server ExecStartPre flip-guard (P1-5) additionally blocks a
    # second prod scheduler on a dedicated-host restart — but it does NOT stop a surviving
    # WEB-host scheduler, so this gate + the no-SSH op=quiesce-web stop+disable are what
    # cover the web host.
    GSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    QUIESCE_PROBES="${CUTOVER_QUIESCE_PROBES:-3}"
    STILL_RUNNING=0
    UNKNOWN_COUNT=0
    serving=false
    answered_n=0
    quiesced_n=0
    unattributed_seen=false
    forbidden_seen=false
    notfound_seen=false
    gateway_code=""
    INV_LAST_BODY=""
    INV_BAD_BODY=""
    for _probe in $(seq 1 "$QUIESCE_PROBES"); do
      rm -f /tmp/exec-inv
      ICODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/exec-inv -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$GSIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/inngest-inventory" || echo "000")
      INV_BODY=$(cat /tmp/exec-inv 2>/dev/null || echo "")
      if [[ -n "$INV_BODY" ]]; then
        INV_LAST_BODY="$INV_BODY"
      fi
      if [[ "$ICODE" == "200" ]]; then
        serving=true; break
      elif [[ "$ICODE" =~ ^[1-5][0-9][0-9]$ ]]; then
        # A real HTTP answer that is not 200. It counts toward the certification only if its body
        # carries the ANCHORED sentinel; every other answer is recorded by class for the remedy.
        answered_n=$((answered_n + 1))
        if grep -qE '^inngest-inventory: DISABLED_UNATTRIBUTED' /tmp/exec-inv 2>/dev/null; then
          unattributed_seen=true
        elif grep -qE '^inngest-inventory: QUIESCED' /tmp/exec-inv 2>/dev/null; then
          quiesced_n=$((quiesced_n + 1))
          continue
        elif [[ "$ICODE" == "403" ]]; then
          forbidden_seen=true
        elif [[ "$ICODE" == "404" ]]; then
          notfound_seen=true
        elif ! grep -qE '^inngest-inventory: ' /tmp/exec-inv 2>/dev/null; then
          gateway_code="$ICODE"
        fi
        if [[ -n "$INV_BODY" ]]; then
          INV_BAD_BODY="$INV_BODY"
        fi
      fi
      # ICODE=000 (transport failure / unreadable) is no answer: it changes no counter.
    done
    # What the host said, for the run log: the last non-empty body that did NOT certify (else the
    # last non-empty body at all — a trailing 000 must not hide an earlier FATAL), CR/LF-stripped
    # (one line — a body line can never start a workflow command) and cut to 120 chars. Plain
    # echo, never an annotation.
    INV_EXCERPT="${INV_BAD_BODY:-$INV_LAST_BODY}"
    INV_EXCERPT="${INV_EXCERPT//[$'\n\r']/ }"
    INV_EXCERPT="${INV_EXCERPT:0:120}"
    GATE_REMEDY=""
    WARN_BEFORE_QUIESCE_VERB=0
    if [[ "$serving" == true ]]; then
      STILL_RUNNING=1
      WARN_BEFORE_QUIESCE_VERB=1
      GATE_REMEDY="run 'gh workflow run cutover-inngest.yml --field op=quiesce-web' (stop+disables inngest across the host-set over the private net, no SSH), confirm it reports 'quiesced', then re-run op=execute"
      echo "quiesce check (web-1, the deploy tunnel origin): inngest STILL RUNNING (inventory HTTP 200)"
    elif [[ "$unattributed_seen" == true ]]; then
      UNKNOWN_COUNT=1
      GATE_REMEDY="the host reported DISABLED_UNATTRIBUTED — the scheduler unit is disabled but carries no valid quiesce marker (it was disabled by something other than a deliberate quiesce, or it started after the quiesce), so neither its capture nor its shape can be trusted. Run 'gh workflow run cutover-inngest.yml --field op=rollback' (re-enables the web scheduler and retires the stale capture), then re-run op=execute from the top"
      echo "quiesce check (web-1, the deploy tunnel origin): UNKNOWN, fail-closed — the host reported DISABLED_UNATTRIBUTED (quiesced=$quiesced_n of $answered_n answered probe(s)); host said: ${INV_EXCERPT:-<empty body>}"
    elif [[ "$answered_n" -ge 1 && "$quiesced_n" -eq "$answered_n" ]]; then
      echo "quiesce check (web-1, the deploy tunnel origin): inngest QUIESCED — no HTTP 200 across ${QUIESCE_PROBES} probe(s) and every answered probe ($quiesced_n of $answered_n) reported the quiesced unit shape (inngest-inventory: QUIESCED)"
    elif [[ "$answered_n" -ge 1 ]]; then
      UNKNOWN_COUNT=1
      if [[ "$forbidden_seen" == true ]]; then
        GATE_REMEDY="the inventory hook answered HTTP 403 — CF-Access or the webhook HMAC was rejected, so the answer says nothing about the unit. Check this workflow's CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET and WEBHOOK_SECRET against the deploy service token + hook secret, then re-dispatch op=execute"
      elif [[ "$notfound_seen" == true ]]; then
        GATE_REMEDY="the inventory hook answered HTTP 404 — the inngest-inventory hook is not deployed in the host's hooks.json. Confirm the apply-deploy-pipeline-fix.yml run for the merge registered it (read /hooks/infra-config-status for /etc/webhook/hooks.json), then re-dispatch op=execute"
      elif [[ -n "$gateway_code" ]]; then
        GATE_REMEDY="the inventory hook answered HTTP $gateway_code with no inngest-inventory: line — a gateway/edge answer (the deploy tunnel or the webhook listener), not the inventory script, so it says nothing about the unit. Read /hooks/deploy-status to confirm the listener answers, then re-dispatch op=execute"
      elif [[ "$SOURCE" == "persisted" ]]; then
        GATE_REMEDY="the on-host inngest-inventory.sh likely predates the QUIESCED verdict; confirm the apply-deploy-pipeline-fix.yml run for the merge wrote /usr/local/bin/inngest-inventory.sh (read /hooks/infra-config-status sha256) and re-dispatch op=execute — do NOT re-run quiesce-web"
      else
        WARN_BEFORE_QUIESCE_VERB=1
        GATE_REMEDY="the unit is not in the quiesced shape (2.1 answered live) — read the ::warning:: above first, then run 'gh workflow run cutover-inngest.yml --field op=quiesce-web', confirm it reports 'quiesced', then re-run op=execute"
      fi
      echo "quiesce check (web-1, the deploy tunnel origin): UNKNOWN, fail-closed — inngest not serving (no HTTP 200 across ${QUIESCE_PROBES} probe(s)) but only $quiesced_n of $answered_n answered probe(s) carried the inngest-inventory: QUIESCED sentinel (2.1 source=$SOURCE); host said: ${INV_EXCERPT:-<empty body>}"
    else
      UNKNOWN_COUNT=1
      GATE_REMEDY="the inventory hook was unreachable (HTTP 000 — no answer at all, a transport failure between the runner and the deploy tunnel) — re-dispatch op=execute; if it repeats, read /hooks/deploy-status to confirm the listener answers"
      echo "quiesce check (web-1, the deploy tunnel origin): UNREADABLE (no HTTP answer across ${QUIESCE_PROBES} probe(s)) — UNKNOWN, fail-closed"
    fi
    if [[ "$STILL_RUNNING" -gt 0 || "$UNKNOWN_COUNT" -gt 0 ]]; then
      if [[ "$WARN_BEFORE_QUIESCE_VERB" -eq 1 && "$STILL_RUNNING" -gt 0 ]]; then
        # THE WARNING COMES BEFORE THE VERB. An operator reads top-down; the remedy below names
        # `op=quiesce-web`, and that op STOPS production scheduling for every user (crons and
        # reminders) on the web scheduler host — it opens the maintenance window, with no reviewer
        # gate of its own. Say so first, at warning level, and say what the loop does next: the
        # quiesce handler captures before it stops, a second op=execute resumes 2.1 from that
        # capture, and neither the watchdog nor a restart/bootstrap deploy starts a quiesced unit.
        echo "::warning::2.2: On the first execute of a cutover this is the designed stop and the run is red by design. op=quiesce-web STOPS production scheduling (every user's crons and reminders) on the web scheduler host — it opens the maintenance window — and has no reviewer gate. Its quiesce handler captures the still-armed reminders BEFORE it stops the unit (a failed capture stops nothing), so a second op=execute resumes 2.1 from the persisted capture taken at the quiesce boundary, and 2.2 then certifies the QUIESCED unit shape. scheduled-inngest-health.yml reads that state as QUIESCED and leaves a quiesced unit alone (no restart is dispatched); only op=rollback re-arms scheduling. If you are not ready to open the window, do not dispatch op=quiesce-web yet."
      elif [[ "$WARN_BEFORE_QUIESCE_VERB" -eq 1 ]]; then
        # Same rule on the UNKNOWN (live) branch: its remedy also names the verb.
        echo "::warning::2.2: op=quiesce-web STOPS production scheduling (every user's crons and reminders) on the web scheduler host — it opens the maintenance window — and has no reviewer gate. The unit is not serving and not in the quiesced shape, so the quiesce handler may refuse to capture (quiesce_capture_unavailable) and stop nothing; if it does capture, a second op=execute resumes 2.1 from that capture. Only op=rollback re-arms scheduling. If you are not ready to open the window, do not dispatch op=quiesce-web yet."
      fi
      echo "::error::2.2 QUIESCE HARD GATE FAILED (P1-7): web-1 (the deploy tunnel origin) is still-running=$STILL_RUNNING / UNKNOWN=$UNKNOWN_COUNT. WITHHOLDING THE SEAM (fail-closed). NO-SSH REMEDIATION: $GATE_REMEDY. Arming the flip now could create a second live scheduler on prod Postgres. Do NOT SSH the host."
      exit 1
    fi
    echo "::notice::2.2 QUIESCE HARD GATE PASSED: web-1 (the deploy tunnel origin, the web scheduler host) reported the QUIESCED unit shape (inactive|failed + disabled + a valid quiesce marker — written only by op=quiesce-web) on every answered probe with no HTTP 200 across ${QUIESCE_PROBES} probe(s) (fail-closed). web-2 scope: see SEAM 2.2a."

    # ---- SEAM: operator maintenance-window steps. As of #6369 the 2.2b/2.3 arm-flip is NO
    # LONGER an out-of-band Doppler write — it is the no-SSH `op=arm` dispatch (a prod-write
    # behind explicit dispatch + the inngest-cutover environment required-reviewer gate, which
    # satisfies hr-menu-option-ack-not-prod-write-auth: the dispatch + approval IS the ack).
    # The remaining true operator seam is 2.4 (app-repoint). 2.2a is a statement, not a step,
    # and it is the ONE authoritative web-2 statement in this file — every other site points here.
    # This block still echoes only step text; no secrets / bodies / connection strings (AC-NOBODY).
    echo "::notice::SEAM — operator maintenance-window steps (2.4 app-repoint is operator; 2.2a web-2 needs no step; 2.2b/2.3 arm-flip is now the no-SSH op=arm dispatch):"
    echo "  2.2a WEB-2 — NO STEP. web-2 (10.0.1.11) is a scheduler-less cattle standby born with web_colocate_inngest=false: it has no inngest-server.service and holds no local reminders, so there is nothing on it to quiesce, capture or re-arm. The peer fan-outs still reach it and are tolerated, not no-ops: op=quiesce-web's stop+disable finds an absent unit, and op=rollback's enable on the absent unit reports inngest_enable_failed on web-2's OWN deploy-status slot, which CI does not read (CI polls web-1's slot — the deploy tunnel origin). There is no web-2 freeze or recreate step before arming the flip."
    echo "  2.2b+2.3 ARM THE FLIP — NO LONGER a manual Doppler write. Dispatch the no-SSH op=arm verb: it writes the 3 values on soleur-inngest/prd (INNGEST_POSTGRES_URI + INNGEST_HEARTBEAT_URL read-through from prd_terraform, then INNGEST_CUTOVER_FLIP=armed LAST — the enabled 30s poll timer picks it up), then CONFIRMS the on-host FSM reached done (exit_code:0) via Better Stack. No secret is echoed (AC-NOBODY; #6369). Run: gh workflow run cutover-inngest.yml --field op=arm  (then APPROVE the inngest-cutover environment required-reviewer gate — that approval IS the prod-write ack)."
    echo "  2.4 APP-REPOINT — merge the INNGEST_BASE_URL → http://10.0.1.40:8288 change in all four places (ci-deploy.sh canary + prod sites, cloud-init.yml, the watchdog INNGEST_HOST_FALLBACK — parity-pinned) and redeploy so functions re-sync onto the dedicated host."
    echo "  THEN: op=rearm (re-arm the Σ=$SIGMA_CAPTURED captured reminders; gated on registry-non-empty) → op=verify (exactly-once)."
    echo "  ROLLBACK / aborted-recovery (P0-1/P0-3/P1-13): (1) dispatch op=rollback — it now writes INNGEST_CUTOVER_FLIP=rollback on soleur-inngest/prd NO-SSH (via the inngest-cutover environment token, value on stdin), confirms rolled-back via Better Stack, THEN runs the SINGLE no-SSH 'enable inngest _ _' fan-out that re-enables (restores the [Install] symlink the 2.2 disable removed) AND starts the web scheduler across [$CUTOVER_HOSTS] in one flock-held handler, polling deploy-status for the 'enabled' verdict; (2) git revert the 2.4 app-repoint PR (all four places: ci-deploy.sh canary + prod, cloud-init.yml, the watchdog fallback) back to http://host.docker.internal:8288 + redeploy — pre-stage that revert green BEFORE step (1), since sends are refused until it deploys. No operator Doppler write or systemctl step is needed (op=arm/op=rollback/op=quiesce-web are the no-SSH arm/reverse/quiesce verbs)."
    echo "::notice::execute complete — SEAM emitted. CI performed NO prod-write; the flip + app-repoint are the operator's maintenance-window steps."
    ;;

  arm)
    # op=arm (#6369) — the no-SSH arm-flip: the three Doppler writes on soleur-inngest/prd
    # that were op=execute's 2.2b/2.3 operator SEAM (:607-611). FORWARD-ONLY — the reverse
    # INNGEST_CUTOVER_FLIP=rollback write lives in op=rollback (ADR-100 Decision 6b keeps the
    # symmetric forward/reverse pair as SEPARATE verbs). A prod-write behind explicit
    # dispatch (same trust model as op=quiesce-web/op=rollback) PLUS the inngest-cutover
    # environment required-reviewer gate. The two SOURCE values are read read-through from
    # soleur/prd_terraform via the existing read-only DOPPLER_TOKEN (CTO 2026-07-12 /
    # ADR-100 6b: the prod DSN is already CI-readable there, SHA-identical to canonical prd;
    # no operator seed). Writes go to the ISOLATED soleur-inngest/prd via the read/write
    # DOPPLER_TOKEN_INNGEST_ARM. AC-NOBODY: no value is EVER echoed — every source value is
    # ::add-mask::'d on its own capture line and every write reads from stdin (never argv,
    # which /proc/<pid>/cmdline exposes).
    if [[ -z "${DOPPLER_TOKEN_INNGEST_ARM:-}" ]]; then
      echo "::error::op=arm: DOPPLER_TOKEN_INNGEST_ARM is empty — the repo secret did not resolve (approve the inngest-cutover environment required-reviewer gate on this dispatch; if it is still empty, the per-merge apply has not yet published the token — check 'gh secret list | grep DOPPLER_TOKEN_INNGEST_ARM'). Refusing to arm."; exit 1
    fi

    # G1 — pre-write FSM-state guard (DI-C2, P1 — prevents PROD-Redis re-FLUSHALL data loss).
    # Re-arming over armed/flipping/flushed/done re-drives the on-host FSM stop -> FLUSHALL
    # against the now-PROD Redis, wiping the live cron sorted-set + in-flight jobs. FAIL-CLOSED
    # on a read error (user-impact F1 / DI): a swallowed read must NOT be mistaken for a safe
    # `unset`. First PROVE the config is readable via a Doppler built-in (DOPPLER_PROJECT,
    # always present, not a secret) — if THAT read fails it is a read/API failure, refuse. Only
    # then read the flip; a missing flip on a proven-readable config is a genuine safe first-arm.
    # The deploy-inngest-restart concurrency group (cancel-in-progress:false) serializes
    # dispatches, so this read is TOCTOU-safe. The flip state is a public enum (not a secret).
    if ! DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get DOPPLER_PROJECT -p soleur-inngest -c prd --plain >/dev/null 2>&1; then
      echo "::error::op=arm: G1 — cannot read soleur-inngest/prd (config-readability probe failed: read/API/auth failure). A swallowed read must NOT be treated as a safe pre-arm state; refusing FAIL-CLOSED. Retry once the read path is healthy. Do NOT SSH the host."; exit 1
    fi
    CUR_FLIP=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain 2>/dev/null || echo "unset")
    case "$CUR_FLIP" in
      ""|unset|aborted|rolled-back)
        echo "::notice::op=arm: G1 pre-write FSM-state guard passed (config readability proven; INNGEST_CUTOVER_FLIP is a safe pre-arm state: '${CUR_FLIP:-unset}')" ;;
      *)
        echo "::error::op=arm: G1 REFUSING — INNGEST_CUTOVER_FLIP is already '$CUR_FLIP' on soleur-inngest/prd (armed/flipping/flushed/done). Re-arming would re-drive stop -> FLUSHALL against the PROD Redis and wipe the live cron queue (DI-C2). If a prior arm is mid-flight, let it reach done; if it aborted, drive it via op=rollback to rolled-back before re-arming. Do NOT SSH the host."; exit 1 ;;
    esac

    # G2 — read the two SOURCE values read-through from prd_terraform (existing DOPPLER_TOKEN),
    # masking EACH on its OWN capture line (security F7 — never batch; a mid-sequence set -e
    # exit must not leave an unmasked captured value in scope before its mask lands).
    PG=$(doppler secrets get INNGEST_POSTGRES_URI --plain 2>/dev/null || true)
    printf '::add-mask::%s\n' "$PG"
    HB=$(doppler secrets get INNGEST_HEARTBEAT_URL --plain 2>/dev/null || true)
    printf '::add-mask::%s\n' "$HB"
    if [[ -z "$PG" || -z "$HB" ]]; then
      echo "::error::op=arm: a source value (INNGEST_POSTGRES_URI / INNGEST_HEARTBEAT_URL) is empty or unreadable from prd_terraform via DOPPLER_TOKEN. Refusing to arm (no value echoed)."; exit 1
    fi

    # G3 — positive prod-URI assertion (DI-C3, P1 — the :5432/:6543 guard alone MISSES the
    # dark backend; both dark and prod DSNs use :5432). Read the CURRENT (dark)
    # INNGEST_POSTGRES_URI from soleur-inngest/prd via the arm token, mask it, and assert the
    # value we are about to write targets the prod session pooler on the prod project.
    #
    # It does NOT require that value to DIFFER from dark (#7462). It used to, and after the
    # first successful arm that condition is permanently false — op=rollback has no inverse
    # for the G4 write — so the refusal fired forever and the cutover could never be re-armed
    # after a rollback. Equality is now informational. All comparisons value-silent (only
    # booleans/tokens reach the log).
    PG_DARK=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get INNGEST_POSTGRES_URI -p soleur-inngest -c prd --plain 2>/dev/null || true)
    printf '::add-mask::%s\n' "$PG_DARK"
    # FAIL-CLOSED on an empty/failed dark read (observability F1 / user-impact / DI): the
    # config is proven readable by G1, so an empty PG_DARK is anomalous — most plausibly a
    # token-scope or wrong-project fault. Refusing costs one dispatch; proceeding on an
    # anomalous read is how a surprise gets armed.
    #
    # The ORIGINAL rationale for this arm is OBSOLETE and must not be restated (#7462): it
    # was that an empty PG_DARK makes the equality comparison false and so SILENTLY passes.
    # That cannot happen now the equality arm no longer gates anything — it yields an
    # informational `skip-already-current`. What distinguishes prod from dark is the positive
    # prod project-ref pin in g3_decide, NOT the equality.
    # The decision itself lives in g3_decide (a pure function, defined above) so it can be
    # driven RED by a test. This case is the SINGLE call site — the Assembly contract in the
    # plan's Guard Contract — and no G3 predicate may be evaluated inline here.
    G3_OUTCOME="$(g3_decide "$PG" "$PG_DARK")"
    case "$G3_OUTCOME" in
      refuse-empty-dark)
        echo "::error::op=arm: G3 — could not read the current dark INNGEST_POSTGRES_URI from soleur-inngest/prd (empty despite a readable config). G1 already proved the config readable, so an empty read here is anomalous — most plausibly a token-scope or wrong-project fault. Refusing FAIL-CLOSED (no value echoed). Do NOT SSH the host." ;;
      refuse-txn-pooler)
        echo "::error::op=arm: G3 — INNGEST_POSTGRES_URI uses the :6543 transaction pooler; inngest sqlc requires the :5432 session pooler (inngest-host.tf:157). Refusing (no value echoed)." ;;
      refuse-not-session-pooler)
        echo "::error::op=arm: G3 — INNGEST_POSTGRES_URI does not contain the :5432 session-pooler port. Refusing (no value echoed)." ;;
      refuse-not-prod-project)
        echo "::error::op=arm: G3 — INNGEST_POSTGRES_URI does not target the TF-known prod inngest Postgres project (ref pigsfuxruiopinouvjwy). Refusing (no value echoed)." ;;
      skip-already-current)
        # NOT a refusal (#7462), and NOT a skipped write — the token is INFORMATIONAL only.
        # The value is already in place: the expected steady state after any previous
        # successful arm, because op=rollback has no inverse for the G4 DSN write. G4 below
        # still writes it unconditionally (see the comment there for why branching on this
        # outcome was removed). The arm proceeds.
        #
        # POST-FLUSH RE-ARM. If a FLUSHALL has already been performed for this host, the
        # on-host monotonic latch (/mnt/data, #7228 P0-5) refuses the re-arm and drives
        # INNGEST_CUTOVER_FLIP to terminal `aborted`. Two corrections to an earlier draft of
        # this comment, both MEASURED rather than reasoned (#7462 review):
        #
        #  - This job does NOT report success. confirm_flip_state matches "flag":"aborted"
        #    first, and G6 exits 1 on that arm. The failure is loud in the run.
        #  - `INNGEST_CUTOVER_FLIP=flushed` is NOT reachable from `aborted`. op=resume is the
        #    only verb that writes it and its G1 accepts `done` ONLY, so once a re-arm has
        #    driven the flag to `aborted` there is no dispatchable path forward. The safe
        #    post-flush resume must be dispatched BEFORE re-arming, while the flag is still
        #    `done`. Naming an unreachable remedy is worse than naming none.
        echo "::notice::op=arm: G3 — INNGEST_POSTGRES_URI on soleur-inngest/prd already equals the prod value (expected after any prior arm; op=rollback has no inverse for that write). Proceeding; G4 rewrites it unconditionally. NOTE: if a FLUSHALL already ran for this host, the on-host latch refuses this arm into terminal 'aborted' and G6 below fails the job. Recovery from 'aborted' is NOT op=resume (its G1 accepts 'done' only) — dispatch op=resume BEFORE re-arming a flushed host." ;;
      write)
        : ;;
      *)
        echo "::error::op=arm: G3 — g3_decide returned an unrecognised outcome. Refusing FAIL-CLOSED (no value echoed)." ;;
    esac
    # SINGLE abort gate. The arms above choose only the message; this decides. Keeping the
    # exit out of the arms is what makes "a refusal actually aborts" testable rather than
    # a property of four separate lines nothing exercises.
    if [[ "$(g3_action "$G3_OUTCOME")" == "abort" ]]; then exit 1; fi
    echo "::notice::op=arm: G3 positive prod-URI assertion passed (:5432 session pooler, prod project-ref present, dark value readable — all value-silent; outcome=${G3_OUTCOME})"

    # G3.5 — CHANNEL-KEY PARITY HARD GATE (#6178 durability). INNGEST_EVENT_KEY +
    # INNGEST_SIGNING_KEY are a SHARED app<->host CHANNEL auth token, NOT an
    # isolation-sensitive per-host secret (ADR-100 §4 Amendment). The app (soleur/prd)
    # and the dedicated host (soleur-inngest/prd) MUST hold BYTE-IDENTICAL values or
    # every app-originated inngest.send() to 10.0.1.40:8288 is rejected. The #6178
    # cutover 502 was exactly this: the host-repoint minted FRESH host keys (Decision 4)
    # but NEVER reconciled them into soleur/prd, so post-2.4 the app kept sending the
    # STALE event key -> op=rearm returned HTTP 502. This gate makes the divergence a
    # HARD PRE-FLIP failure instead of a silent post-cutover 502. The app value is read
    # read-through from prd_terraform via the read-only DOPPLER_TOKEN (exactly as G2
    # reads INNGEST_POSTGRES_URI); the host value via the arm token on soleur-inngest/prd.
    # AC-NOBODY: every value is ::add-mask::'d and compared by sha256 ONLY — never echoed;
    # only MATCH/MISMATCH per key reaches the log.
    PARITY_FAIL=0
    for CK in INNGEST_EVENT_KEY INNGEST_SIGNING_KEY; do
      APP_CK=$(doppler secrets get "$CK" --plain 2>/dev/null || true)
      printf '::add-mask::%s\n' "$APP_CK"
      HOST_CK=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get "$CK" -p soleur-inngest -c prd --plain 2>/dev/null || true)
      printf '::add-mask::%s\n' "$HOST_CK"
      if [[ -z "$APP_CK" || -z "$HOST_CK" ]]; then
        echo "::error::op=arm: G3.5 channel-key parity FAIL-CLOSED — $CK unreadable (app$([[ -n "$APP_CK" ]] && echo '=set' || echo '=empty') host$([[ -n "$HOST_CK" ]] && echo '=set' || echo '=empty')). Cannot prove app<->host channel parity; refusing to arm (no value echoed)."; PARITY_FAIL=1; continue
      fi
      APP_CK_H=$(printf '%s' "$APP_CK" | sha256sum | cut -d' ' -f1)
      HOST_CK_H=$(printf '%s' "$HOST_CK" | sha256sum | cut -d' ' -f1)
      if [[ "$APP_CK_H" == "$HOST_CK_H" ]]; then
        echo "::notice::op=arm: G3.5 channel-key parity — $CK MATCH (soleur/prd == soleur-inngest/prd, sha256-verified, value-silent)"
      else
        echo "::error::op=arm: G3.5 channel-key parity — $CK MISMATCH: the app (soleur/prd) key differs from the dedicated host (soleur-inngest/prd) key. This is the #6178 cutover-502 condition — post-repoint every app inngest.send() to 10.0.1.40:8288 is rejected (op=rearm 502). RECONCILE the app to the host's SHARED channel key, then redeploy: the host key is TF-owned in soleur-inngest/prd (fresh, no ignore_changes); the app key in soleur/prd carries lifecycle ignore_changes=[value] (inngest.tf), so a naive 'terraform apply' does NOT propagate it. Copy the host value INTO soleur/prd out-of-band (supported by ignore_changes): read it (DOPPLER_TOKEN=\$DOPPLER_TOKEN_INNGEST_ARM doppler secrets get $CK -p soleur-inngest -c prd --plain) and pipe it on STDIN into 'doppler secrets set $CK -p soleur -c prd' (never argv/log), THEN REDEPLOY web-platform (ci-deploy regenerates env each deploy) so the app bakes the shared key. Re-run op=arm. See runbook §2.4 + ADR-100 §4 Amendment. Do NOT SSH the host."; PARITY_FAIL=1
      fi
    done
    if [[ "$PARITY_FAIL" -ne 0 ]]; then
      echo "::error::op=arm: G3.5 CHANNEL-KEY PARITY GATE FAILED — refusing to arm the flip while the app<->host channel keys diverge (the #6178 durability gate). Reconcile + redeploy per the per-key remediation above, then re-run op=arm. Do NOT SSH the host."; exit 1
    fi
    echo "::notice::op=arm: G3.5 channel-key parity gate PASSED — app (soleur/prd) and host (soleur-inngest/prd) share both channel keys (sha256-verified). The post-2.4 app->host channel will authenticate."

    # G3.6 — DIAGNOSTIC-BOOT HARD GATE (#7462). inngest-bootstrap.sh states this precondition
    # in prose and NOTHING enforced it: "This is NOT a cutover state: clear
    # INNGEST_DIAGNOSTIC_BOOT before arming." Measured 2026-08-20 — op=arm contained ZERO
    # references to it while the flag was live at "1" on soleur-inngest/prd.
    #
    # Why it must refuse BEFORE the writes. With the flag set, the host's ExecStart renders the
    # diagnostic arm: `unset INNGEST_POSTGRES_URI` (SQLite-only) with --sdk-url pointed at a
    # closed loopback port, so it adopts NO function registry. Arming in that state runs the
    # whole FSM to `done` — quiescing the web scheduler and cutting over to a host that serves
    # nothing. The cutover reports success and production crons simply stop. That is a strictly
    # worse instance of the failure G3 exists to prevent: arming onto no Postgres at all.
    #
    # Fail-closed on an unreadable value for the same reason G3 does: the config is proven
    # readable by G1, so an unreadable read here is anomalous, and proceeding would arm blind.
    DIAG_BOOT=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get INNGEST_DIAGNOSTIC_BOOT -p soleur-inngest -c prd --plain 2>/dev/null || printf '%s' '__UNREADABLE__')
    case "$(diag_boot_decide "$DIAG_BOOT")" in
      clear) echo "::notice::op=arm: G3.6 diagnostic-boot gate passed (INNGEST_DIAGNOSTIC_BOOT is clear; the host will render its durable-backend ExecStart)." ;;
      unreadable)
        echo "::error::op=arm: G3.6 — could not read INNGEST_DIAGNOSTIC_BOOT from soleur-inngest/prd despite a G1-readable config. Refusing FAIL-CLOSED: arming while that flag is set cuts over to a host that serves no registry. Do NOT SSH the host."; exit 1 ;;
      set)
        echo "::error::op=arm: G3.6 REFUSING — INNGEST_DIAGNOSTIC_BOOT is set on soleur-inngest/prd. A diagnostic boot renders an SQLite-only ExecStart with --sdk-url on a closed loopback port, so the host adopts NO function registry; arming now would quiesce the web scheduler and complete the cutover onto a host that serves nothing, reporting success. Clear INNGEST_DIAGNOSTIC_BOOT on soleur-inngest/prd, then REPLACE the host (apply_target=inngest-host-replace) so it re-renders its ExecStart, then re-run op=arm. CORRECTED #7674: clearing the flag alone does NOT re-render a RUNNING host — inngest-bootstrap.sh consumes it in runcmd, at FIRST BOOT only, so a cleared flag changes nothing until the host boots again. The previous wording here told operators to wait for a re-render that cannot happen. Do NOT SSH the host."; exit 1 ;;
      *)
        echo "::error::op=arm: G3.6 — diag_boot_decide returned an unrecognised outcome. Refusing FAIL-CLOSED."; exit 1 ;;
    esac


    # G3.7 — PRE-FLUSH-LATCH GATE (#7462 review). Refuses a DOOMED arm before ANY prod write.
    #
    # THE HAZARD IT CLOSES, precisely. Once a flip has completed, the monotonic latch on
    # /mnt/data (inngest-cutover-flip.sh `flush_already_performed`, #7228 P0-5) refuses every
    # subsequent re-arm and drives the flag to terminal `aborted`. That refusal is correct and is
    # NOT what this gate second-guesses. What it fixes is everything op=arm did on the way there:
    # G4 wrote both prod secrets and G5 wrote `armed`, and for the ~30-60s until the on-host 30s
    # timer fired, INNGEST_CUTOVER_FLIP sat at `armed` — a value INSIDE
    # inngest-server-flip-guard.sh's prod-start allowlist {armed,flipping,flushed,done} — while
    # op=rollback had already re-enabled the co-located web schedulers. A reboot inside that
    # window starts a SECOND prod scheduler: a double-fire, not data loss.
    #
    # THIS PR OWNS IT. Before #7462 that window was unreachable, but only incidentally: G3's
    # equality refusal blocked the re-arm outright once the prod DSN was in the dark slot. Making
    # op=arm idempotent removed that accidental block, so the window is PR-introduced and is
    # closed here rather than deferred.
    #
    # IT ALSO IMPLEMENTS A PRECONDITION THAT WAS ONLY EVER DOCUMENTED. op=resume's header has
    # named a "G2 the durable flush latch must EXIST" precondition since #7228 — to be answered
    # off-host, never by SSH — and nothing enforced it. This is that predicate, read from the same
    # side, applied at the verb that can act on it, over the same betterstack-query.sh reader
    # _flip_transition_dt already uses: no new transport, credential or fixture class.
    # (The literal name of the off-host read path is deliberately not spelled here: a sibling
    # assertion greps this arm body for it to prove op=arm adds no polling hook, and a bare-token
    # grep cannot tell a comment from code — cq-assert-anchor-not-bare-token.)
    #
    # PRE-FILTER, NOT THE AUTHORITY. The on-host latch remains the guard that actually prevents a
    # second FLUSHALL; this gate can only ever ADD a refusal, never remove one. That is why the
    # remediation below is allowed to narrow its window: doing so returns to the pre-gate
    # behaviour, in which the on-host latch still refuses.
    FLUSH_LATCH_N="$(_flush_latch_count)"
    FLIP_LIVENESS_N="$(_flip_liveness_count)"
    FL_OUTCOME="$(flush_latch_decide "$FLUSH_LATCH_N" "$FLIP_LIVENESS_N")"
    case "$FL_OUTCOME" in
      clear)
        echo "::notice::op=arm: G3.7 flush-latch gate passed — no flip-complete / refuse-rearm-after-done row within $FLUSH_LATCH_SINCE, AND the host is audible ($FLIP_LIVENESS_N inngest-cutover-flip row(s) from $INNGEST_HOST_NAME within $FLIP_LIVENESS_SINCE). NOTE: 'clear' is a WEAK verdict — it means 'the host is reporting and no flush evidence is visible in this window', NOT 'no flush has happened'. Better Stack retention against a $FLUSH_LATCH_SINCE window is UNMEASURED (#7674 H5/H6), so the on-host monotonic latch remains the authority; this gate can only ever ADD a refusal. Note the two signals cover DIFFERENT windows: H proves the host is audible NOW ($FLIP_LIVENESS_SINCE), which does not prove it was audible across the whole $FLUSH_LATCH_SINCE window L was read over — so an outage inside L's window could still have hidden a flush row." ;;
      latched)
        echo "::error::op=arm: G3.7 REFUSING — the dedicated host's log source carries $FLUSH_LATCH_N flip-complete / refuse-rearm-after-done row(s) within $FLUSH_LATCH_SINCE, so a FLUSHALL has ALREADY been performed for this host. The monotonic latch that records it lives on /mnt/data and survives BOTH a rollback and a host replace, so this arm is doomed: it would write both prod secrets, park INNGEST_CUTOVER_FLIP at 'armed' (inside inngest-server-flip-guard.sh's prod-start allowlist, so a reboot would start a SECOND prod scheduler) and then be refused on-host into terminal 'aborted'. Refusing BEFORE any write; nothing was changed. There is no re-arm path while that latch stands, and op=resume is NOT it (its G1 accepts 'done' only). The latch is cleared ONLY by recutting the host's /mnt/data volume, never by SSH. CORRECTED #7674: an inngest-host-replace does NOT recut it — the replace re-ATTACHES the same hcloud volume, and the latch file survives (measured: volume 106261946 was created 2026-07-07 and is attached to a host created 2026-08-20, six weeks later, latch intact). No apply_target recuts THIS volume yet (`registry-luks-recut` and `workspaces-luks-recut` exist, but for other volumes); the inngest one is designed and tracked in #7695, and until it is built there is no in-repo mechanism that clears this latch. If that recut has ALREADY happened, set the repo variable FLUSH_LATCH_SINCE to a window starting after it (e.g. '1h') and re-dispatch — that narrows this pre-filter only, and the on-host latch still refuses if it is in fact present. Do NOT SSH the host." ;;
      silent)
        echo "::error::op=arm: G3.7 REFUSING — the flush-latch window is empty, but so is the host's own liveness window: ZERO inngest-cutover-flip rows from host=$INNGEST_HOST host_name=$INNGEST_HOST_NAME within $FLIP_LIVENESS_SINCE, while the read path itself succeeded. A silent host cannot supply evidence of ANYTHING, so the empty latch window proves nothing and must not be read as 'no flush has happened'. This is NOT a credential fault (that reports 'unreadable' and names prd_terraform) — the dedicated host has gone dark or stopped shipping journald. Note this measured the FULL conjunction host=$INNGEST_HOST AND host_name=$INNGEST_HOST_NAME, so an equally consistent cause is that the host's identity fields stopped matching (a rename, or a #6616 remediation that re-derives host_name) — check that before concluding the box is gone. Unit/timer state is NOT in the SOLEUR_INNGEST_SERVER_PROBE row; it is in the post-boot-health marker's svc=[...] field. Refusing BEFORE any write; nothing was changed. Do NOT SSH the host." ;;
      unreadable)
        echo "::error::op=arm: G3.7 — could not read the flip-FSM markers from Better Stack (the ::warning:: above names the read-path failure). Refusing FAIL-CLOSED: an unanswered 'has this host already been flushed?' must not be read as 'no', and G6 below confirms the flip over the SAME read path, so an arm dispatched now could not be confirmed either. Fix BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform and re-dispatch. Do NOT SSH the host." ;;
      *)
        echo "::error::op=arm: G3.7 — flush_latch_decide returned an unrecognised outcome. Refusing FAIL-CLOSED." ;;
    esac
    # ONE gate, and it is a positive allowlist rather than a blocklist of refusals: a future
    # outcome token then fails CLOSED by construction instead of falling through to the prod
    # write. That fall-through is exactly how G3 became a pure logger at 381/0 green.
    if [[ "$FL_OUTCOME" != "clear" ]]; then exit 1; fi

    # G4 — write the two DATA secrets FIRST, each via stdin (never argv), each exit-gated
    # before the next. Order is a correctness invariant: the URIs must land before `armed`.
    # UNCONDITIONAL, including on `skip-already-current` (#7462 review). An earlier revision
    # branched this write on the G3 outcome and skipped it when the value was already current.
    # That was wrong twice over. It bought nothing — writing a secret to the value it already
    # holds is a no-op — and it introduced a branch whose INVERSION is catastrophic and which
    # no behavioural test covered: flipping the guard's polarity skipped the write on the
    # FIRST-arm transition, so the host booted against the DARK backend and the cutover
    # reported success, with the whole suite green. It was also asymmetric with the
    # INNGEST_HEARTBEAT_URL write immediately below, which has always been unconditional and
    # is equally redundant on a re-arm.
    #
    # Writing unconditionally is strictly stronger: the arm ESTABLISHES the invariant rather
    # than observing it, so a dark value that drifted into the slot between G3's read and this
    # write is overwritten rather than trusted. Idempotence comes from G3 no longer REFUSING,
    # never from skipping the write.
    printf '%s' "$PG" | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_POSTGRES_URI -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=arm: G4 — writing INNGEST_POSTGRES_URI to soleur-inngest/prd FAILED. armed NOT written. Job aborts (no value echoed)."; exit 1; }
    echo "::notice::op=arm: G4 wrote INNGEST_POSTGRES_URI to soleur-inngest/prd (value not echoed)"
    printf '%s' "$HB" | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_HEARTBEAT_URL -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=arm: G4 — writing INNGEST_HEARTBEAT_URL to soleur-inngest/prd FAILED. armed NOT written. Job aborts (no value echoed)."; exit 1; }
    echo "::notice::op=arm: G4 wrote INNGEST_HEARTBEAT_URL to soleur-inngest/prd (value not echoed)"
    # #7228: op=arm deliberately does NOT touch betteruptime_heartbeat.inngest_consumer, the
    # consumer-side monitor its symmetric op=rollback pauses. Unpausing here would arm a monitor
    # BEFORE the FSM has run, i.e. before any beat exists — the green-but-inert state ADR-117
    # forbids and #6537 spent nine days in. The ONLY unpause path is the measured-beat arm gate in
    # apply-web-platform-infra.yml, which PATCHes paused=false, polls for a REAL beat, and rolls
    # back to paused if none lands. It is self-clearing: the first apply after this host actually
    # serves will arm it. Nothing to do here — stated because the ASYMMETRY with op=rollback is
    # deliberate and a future edit "restoring symmetry" would reintroduce the inert monitor.
    echo "::notice::op=arm: consumer heartbeat left PAUSED by design — the ADR-117 measured-beat gate arms it on the first apply after the host serves (never armed ahead of a real beat)."

    # G5 — arm LAST. The enabled 30s on-host .timer picks up `armed` and drives the FSM
    # armed -> flipping -> flushed -> done (ADR-100 Decision 6a). `armed` is a literal, not a
    # secret, but use the same stdin form for a uniform (test-asserted) write shape.
    ARM_TS=$(date +%s)
    printf '%s' 'armed' | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=arm: G5 — writing INNGEST_CUTOVER_FLIP=armed FAILED (both URIs already landed). Re-dispatch op=arm — G1 will allow re-arm from a non-terminal state. Do NOT SSH the host."; exit 1; }
    echo "::notice::op=arm: G5 armed — INNGEST_CUTOVER_FLIP=armed written LAST to soleur-inngest/prd. The on-host 30s timer now drives the flip FSM."

    # G6 — confirm the on-host FSM reached `done` via Better Stack (AC9; security F1 + DI-Q4).
    # TIME-BOUND to >= the armed-write moment (ARM_TS captured just before G5) so a stale
    # terminal line from a prior run/dry-run on the SAME source cannot false-succeed. The
    # shared confirm_flip_state keys on the emitter's `flag` field (done/aborted/rolled-back),
    # NOT `reason` (which is a cause string, never `done`) — and uses the space-timestamp form
    # betterstack-query.sh's ClickHouse cast accepts. It never echoes a raw row.
    ARM_ISO=$(date -u -d "@$ARM_TS" +'%Y-%m-%d %H:%M:%S')
    G6_STATE=$(confirm_flip_state "$ARM_ISO")
    case "$G6_STATE" in
      done)
        echo "::notice::op=arm: G6 — FSM confirmed done (flag:done exit_code:0) via Better Stack (since $ARM_ISO)" ;;
      aborted|rolled-back)
        echo "::error::op=arm: G6 — the on-host FSM reached terminal '$G6_STATE' (NOT done) since $ARM_ISO. Two DIFFERENT causes land here and the remediation differs (#7462): (a) reason=refuse-rearm-after-done means the monotonic flush latch refused this arm because the host has ALREADY been flushed — nothing was flushed again and nothing is broken; do NOT re-arm, and note op=resume is only reachable while the flag is still 'done', so from terminal 'aborted' there is no dispatchable path forward. (b) reason=dbsize-nonzero / FLUSHALL-failed / unexpected-exit is a genuine flip fault — confirm DBSIZE + backend via op=inventory. Read the reason field on the inngest-cutover-flip Better Stack line before acting; do NOT proceed to 2.4 (app-repoint). Do NOT SSH the host."; exit 1 ;;
      *)  # timeout — could be the FSM OR the confirm path (a ::warning:: fired above if the query failed)
        echo "::error::op=arm: G6 — no terminal FSM flag (done/aborted) within 600s since $ARM_ISO (armed WAS written). If the on-host 30s timer looks healthy, re-run scripts/betterstack-query.sh manually (runbook §3) to rule out a confirm-path failure (a betterstack-query.sh ::warning:: above names that case). Do NOT proceed to 2.4. Do NOT SSH the host."; exit 1 ;;
    esac
    echo "::notice::op=arm complete — arm-flip written no-SSH (3 values, armed last) + FSM confirmed done. Remaining cutover steps: op=rearm (re-arm captured reminders) -> op=verify (exactly-once), plus the operator 2.4 app-repoint. NO secret value was echoed (AC-NOBODY)."
    ;;

  quiesce-web)
    # op=quiesce-web (#6178) — the no-SSH remediation for a `2.2 QUIESCE HARD GATE
    # FAILED / STILL RUNNING` verdict. Operators have NO SSH, so the co-located web
    # scheduler cannot be stop+disabled by hand (hr-no-ssh-fallback-in-runbooks).
    # POSTs `quiesce inngest _ _` + peers to /hooks/deploy (HMAC + CF-Access) which
    # fans the stop+disable out per-host over the private net (mirrors op=rollback's
    # restart fan-out), then re-run op=execute. This is a prod-write behind explicit
    # dispatch (same trust model as op=rollback).
    if [[ -z "${CUTOVER_HOSTS:-}" ]]; then
      echo "::error::CUTOVER_HOSTS is empty — refusing to run quiesce-web against an empty host-set"; exit 1
    fi
    IFS=',' read -r -a HOSTS <<< "$CUTOVER_HOSTS"
    if [[ "${#HOSTS[@]}" -lt 1 ]]; then
      echo "::error::CUTOVER_HOSTS parsed to zero hosts (value: '$CUTOVER_HOSTS')"; exit 1
    fi
    # ---- quiesce-web PREFLIGHT (#6921 §9) — BEFORE anything is dispatched. The quiesce handler
    # (ci-deploy.sh), the inventory QUIESCED verdict, the persisted-capture resume and the
    # enumerate scrub all ship in ONE config push (apply-deploy-pipeline-fix.yml → FILE_MAP in
    # infra-config-apply.sh). A quiesce dispatched before that push lands STOPS production
    # scheduling with an older handler that neither captures nor writes the marker 2.2 certifies.
    # So read the host's per-file sha256 from /hooks/infra-config-status (the same frame
    # infra-config-verify.sh adjudicates) and require each script to equal this checkout's bytes.
    # Unreadable, missing or different → refuse, nothing stopped. Same signed-GET shape as the
    # deploy-status polls below (HMAC over the empty body + CF-Access).
    PF_SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/quiesce-preflight
    PF_CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/quiesce-preflight -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$PF_SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/infra-config-status" || echo "000")
    PF_CODE="${PF_CODE:0:3}"
    PF_REMEDY="Dispatch 'gh workflow run apply-deploy-pipeline-fix.yml' for the merged commit, wait for its verify to go green (it adjudicates the same per-file sha256), then re-dispatch op=quiesce-web. NOTHING was stopped — production scheduling is unchanged. Do NOT SSH the host."
    if [[ "$PF_CODE" != "200" ]]; then
      echo "::error::quiesce-web PREFLIGHT: config push not landed — /hooks/infra-config-status is unreadable (HTTP $PF_CODE), so the on-host cutover scripts cannot be proven current. A 403 is CF-Access/HMAC; 000 is no answer. $PF_REMEDY"; exit 1
    fi
    if ! jq -e '(.files | type) == "array"' /tmp/quiesce-preflight >/dev/null 2>&1; then
      echo "::error::quiesce-web PREFLIGHT: config push not landed — /hooks/infra-config-status answered HTTP 200 with no files[] frame (no prior apply, or a corrupt state file). $PF_REMEDY"; exit 1
    fi
    PF_FAIL=0
    for _pf_name in ci-deploy.sh inngest-inventory.sh inngest-rearm-reminders.sh inngest-enumerate-reminders.sh; do
      _pf_checkout=""
      if [[ -r "apps/web-platform/infra/$_pf_name" ]]; then
        _pf_checkout=$(sha256sum < "apps/web-platform/infra/$_pf_name") || _pf_checkout=""
        _pf_checkout="${_pf_checkout%% *}"
      fi
      [[ "$_pf_checkout" =~ ^[0-9a-f]{64}$ ]] || _pf_checkout="unreadable"
      _pf_host=$(jq -r --arg f "/usr/local/bin/$_pf_name" '[.files[] | select(.file == $f) | .sha256] | if length == 1 then .[0] else "" end' /tmp/quiesce-preflight 2>/dev/null) || _pf_host=""
      [[ "$_pf_host" =~ ^[0-9a-f]{64}$ ]] || _pf_host="missing"
      if [[ "$_pf_checkout" == "unreadable" || "$_pf_host" != "$_pf_checkout" ]]; then
        echo "::error::quiesce-web PREFLIGHT: config push not landed: /usr/local/bin/$_pf_name host=$_pf_host checkout=$_pf_checkout"
        PF_FAIL=1
      fi
    done
    if [[ "$PF_FAIL" -ne 0 ]]; then
      echo "::error::quiesce-web PREFLIGHT FAILED: the host's cutover scripts are not this checkout's (see the per-file lines above). $PF_REMEDY"; exit 1
    fi
    echo "::notice::quiesce-web PREFLIGHT: ci-deploy.sh, inngest-inventory.sh, inngest-rearm-reminders.sh and inngest-enumerate-reminders.sh on the host match this checkout (sha256) — the config push landed"
    echo "::warning::quiesce-web: this STOPS production scheduling (every user's crons and reminders) on host-set [$CUTOVER_HOSTS] — the maintenance window opens NOW. The quiesce handler captures the still-armed reminders BEFORE it stops the unit (a failed or timed-out capture stops nothing and reports quiesce_capture_failed), so a second op=execute resumes 2.1 from the persisted capture taken at the quiesce boundary. scheduled-inngest-health.yml reads the stopped+disabled unit as QUIESCED and leaves a quiesced unit alone — nothing restarts it until op=rollback. If you did not mean to open the window, dispatch op=rollback."
    echo "::notice::quiesce-web: stop+disabling inngest across host-set [$CUTOVER_HOSTS] (${#HOSTS[@]} host(s)) — no-SSH remediation for the 2.2 gate"
    PAYLOAD=$(printf '{"command":"quiesce inngest _ _","peers":"%s"}' "$CUTOVER_HOSTS")
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/quiesce-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 60 -o /tmp/quiesce-body -w '%{http_code}' \
      -X POST -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/deploy" || echo "000")
    if [[ "$CODE" != "202" ]]; then
      CAUSE="$(tr -d '\n\r' < /tmp/quiesce-body 2>/dev/null)"
      echo "::error::quiesce-web webhook rejected (HTTP $CODE): ${CAUSE:-<empty body>}. UNKNOWN (000) means the webhook was unreachable — check CF-Access/HMAC + the run log, then re-dispatch. Do NOT SSH the host."; exit 1
    fi
    echo "::notice::quiesce-web: fan-out accepted (202) for [$CUTOVER_HOSTS] — polling deploy-status for the host-side quiesced verdict (do NOT immediate-probe: TimeoutStopSec=180 means the async stop can lag the 202)"
    # POLL /hooks/deploy-status for web-1's terminal inngest verdict (the deploy tunnel origin;
    # a peer's verdict lands on the peer's own slot, which this read never sees).
    # The host writes `quiesced` only AFTER its own verify_inngest_quiesced passes
    # (not-serving AND unit-inactive AND not-enabled) and the tri-state reads quiesced, so
    # reason==quiesced/exit_code==0 is the authoritative synchronous not-serving proof —
    # STRONGER than the inventory read. FRESH_FLOOR anchors on this trigger so a stale prior
    # green isn't read (deploy-state is a single slot).
    TRIGGER_TS=$(date +%s)
    FRESH_FLOOR=$((TRIGGER_TS - 60))
    GSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    # Poll window ≥ the host worst case (capture bound + kill-after + stop + verify + peer fan-out)
    # — drift-guarded by ci-deploy.test.sh (#6178), which computes the total from the live
    # literals, so no total is restated here. The terms: the 120 s quiesce capture bound and its
    # kill-after, both BEFORE the stop (#6921), + TimeoutStopSec + verify attempts × (interval+5)
    # + the peer fan-out. The distinct QMAX_POLLS/QPOLL_INTERVAL names keep that grep unambiguous.
    QMAX_POLLS=120
    QPOLL_INTERVAL=5
    QUIESCED=0
    LAST_REASON=""
    for i in $(seq 1 "$QMAX_POLLS"); do
      rm -f /tmp/quiesce-status
      curl --disable --noproxy '*' -s --max-time 10 -o /tmp/quiesce-status -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$GSIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/deploy-status" >/dev/null || true
      BODY=$(cat /tmp/quiesce-status 2>/dev/null || echo "")
      if [ -z "$BODY" ] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
        echo "Attempt $i/$QMAX_POLLS: non-JSON/empty deploy-status — retrying"; sleep "$QPOLL_INTERVAL"; continue
      fi
      EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
      REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
      COMPONENT=$(echo "$BODY" | jq -r '.component // "unknown"')
      START_TS=$(echo "$BODY" | jq -r '.start_ts // 0')
      if [ "$COMPONENT" != "inngest" ]; then
        echo "Attempt $i/$QMAX_POLLS: last op was for $COMPONENT, not inngest — waiting"; sleep "$QPOLL_INTERVAL"; continue
      fi
      if [ "$START_TS" -lt "$FRESH_FLOOR" ]; then
        echo "Attempt $i/$QMAX_POLLS: state predates this trigger (start_ts=$START_TS < floor=$FRESH_FLOOR) — waiting"; sleep "$QPOLL_INTERVAL"; continue
      fi
      LAST_REASON="$REASON"
      case "$REASON" in
        quiesced)
          echo "::notice::quiesce-web: host-side QUIESCED confirmed (reason=quiesced exit_code=$EXIT_CODE) — inngest not-serving AND not-enabled on web-1 (the deploy tunnel origin)"; QUIESCED=1; break ;;
        lock_contention)
          # NOT terminal for this poll. deploy-state is ONE slot: a ci-deploy invocation that loses
          # the flock (e.g. a watchdog restart racing the quiesce mid-stop) stamps lock_contention
          # over the winner's in-progress state, and the winner's verdict overwrites it when it
          # finishes. Keep polling; the timeout message names this reason if it never clears.
          echo "Attempt $i/$QMAX_POLLS: reason=lock_contention — another ci-deploy invocation lost the flock and overwrote the status slot; the in-flight quiesce's verdict will replace it — polling" ;;
        quiesce_capture_failed)
          echo "::error::quiesce-web FAILED (reason=quiesce_capture_failed): the host's pre-stop capture of the still-armed reminders failed or timed out, so NOTHING was stopped or disabled — production scheduling is still running and no quiesce marker was written. Read the capture's scrubbed stderr tail: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep INNGEST_QUIESCE_CAPTURE_FAILED. If the unit is active but its GraphQL is dead (connection refused / timeout), dispatch 'gh workflow run restart-inngest-server.yml', wait for it to go green, then re-dispatch op=quiesce-web. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        quiesce_capture_unavailable)
          echo "::error::quiesce-web FAILED (reason=quiesce_capture_unavailable): the unit is neither active (so a capture cannot run) nor already quiesced — NOTHING was captured, disabled or stopped. Read its shape: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep INNGEST_QUIESCE_CAPTURE_UNAVAILABLE (logs unit= enabled= state=). If state=disabled_unattributed, dispatch 'gh workflow run cutover-inngest.yml --field op=rollback' (re-enables + retires the stale capture); otherwise (failed / activating / inactive but enabled) dispatch 'gh workflow run restart-inngest-server.yml'. Once the unit is active, re-dispatch op=quiesce-web. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        quiesce_marker_write_failed)
          echo "::error::quiesce-web FAILED (reason=quiesce_marker_write_failed): the capture succeeded but the quiesce marker could not be written atomically under /var/lib/inngest — NOTHING was disabled or stopped, and 2.2 could not certify a quiesce without it. Check /var/lib/inngest is writable (root disk full or remounted read-only): doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep INNGEST_QUIESCE_MARKER_WRITE_FAILED, clear the cause, then re-dispatch op=quiesce-web. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        quiesced_shape_unrecognized)
          echo "::error::quiesce-web FAILED (reason=quiesced_shape_unrecognized): the unit was stopped and verified not-serving, so production scheduling IS stopped — but its final shape did not read as quiesced (not inactive|failed + disabled with a valid marker), so op=execute 2.2 will not certify it. Read the shape: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep 'final shape not recognised'. Then dispatch 'gh workflow run cutover-inngest.yml --field op=rollback' (re-opens scheduling and retires the capture + marker), and re-dispatch op=quiesce-web for a fresh capture and marker. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        inngest_still_serving|inngest_still_enabled)
          echo "::error::2.2 quiesce FAILED (reason=$REASON): a persistent still-serving/still-enabled means the unit is being RESURRECTED — pull reason= from /hooks/deploy-status + Better Stack (logger -t ci-deploy) and investigate what restarts/re-enables it (e.g. a stray deploy re-enabling the unit). Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        quiesced_peer_fanout_unaccepted)
          echo "::error::2.2 quiesce: a PEER fan-out was NOT accepted (unreachable/HMAC-rejected — this is NON-ACCEPTANCE, NOT peer-not-quiesced; the peer's own verdict lands on the peer's deploy-status slot, DI-C3). Check the peer host's reachability + the run log, then re-dispatch. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        *)
          if [ "$EXIT_CODE" == "-1" ]; then
            echo "Attempt $i/$QMAX_POLLS: quiesce still running (reason=$REASON)"
          else
            # TERMINAL (exit_code != -1) but the reason matched no enumerated verdict —
            # fast-fail instead of polling to the full timeout (a reason rename would
            # otherwise silently degrade to a $((QMAX_POLLS * QPOLL_INTERVAL))s wait).
            echo "::error::unrecognized terminal reason $REASON (exit_code=$EXIT_CODE) — quiesce-web reached a terminal state that matched no known verdict; failing fast. Pull reason= from /hooks/deploy-status + Better Stack (logger -t ci-deploy). Do NOT SSH the host."; echo "$BODY" | jq .; exit 1
          fi
          ;;
      esac
      sleep "$QPOLL_INTERVAL"
    done
    if [[ "$QUIESCED" -ne 1 ]]; then
      echo "::error::quiesce-web did not reach the terminal 'quiesced' verdict within $((QMAX_POLLS * QPOLL_INTERVAL))s (last reason read: ${LAST_REASON:-<none>}). If the last reason was lock_contention, the quiesce itself may have lost the flock to an in-flight deploy — wait for that deploy, then re-dispatch op=quiesce-web. If the webhook was UNKNOWN/unreachable, re-dispatch; otherwise pull reason= from /hooks/deploy-status + Better Stack (logger -t ci-deploy). Do NOT SSH the host."; exit 1
    fi
    # SECONDARY confirm (web-1, DI-C3): an inventory read mirrors the 2.2 gate's classification.
    # The deploy-status `quiesced` reason above is the PRIMARY gate (host-side synchronous
    # verify, stronger than the inventory read).
    GSIG2=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/quiesce-inv
    ICODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/quiesce-inv -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$GSIG2" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-inventory" || echo "000")
    # It also reports whether the body carried the anchored QUIESCED sentinel — the exact
    # signal op=execute 2.2 certifies, so a missing sentinel here predicts 2.2's UNKNOWN.
    ICODE="${ICODE:0:3}"
    if [[ "$ICODE" == "200" ]]; then
      echo "::warning::quiesce-web: SECONDARY inventory read still returns HTTP 200 — the deploy tunnel reaches only web-1, the same host whose deploy-status just reported quiesced, so the unit came back after the verify (a resurrection) or the status slot was overwritten. Re-run op=execute's 2.2 gate to re-confirm before arming; if it reads STILL RUNNING, find what restarts the unit (Better Stack, logger -t ci-deploy)."
    elif [[ ! "$ICODE" =~ ^[1-5][0-9][0-9]$ ]]; then
      echo "::warning::quiesce-web: SECONDARY inventory confirm UNREADABLE (HTTP 000 — no answer from the deploy tunnel), so the QUIESCED sentinel could not be read. The deploy-status verdict above stands; op=execute 2.2 re-probes the inventory 3 times, so re-run op=execute."
    elif grep -qE '^inngest-inventory: QUIESCED' /tmp/quiesce-inv 2>/dev/null; then
      echo "::notice::quiesce-web: SECONDARY inventory confirm HTTP $ICODE (non-200), QUIESCED sentinel=present on web-1 — the quiesced unit shape op=execute 2.2 certifies."
    else
      QINV_EXCERPT="$(cat /tmp/quiesce-inv 2>/dev/null || true)"
      QINV_EXCERPT="${QINV_EXCERPT//[$'\n\r']/ }"
      echo "::warning::quiesce-web: SECONDARY inventory confirm HTTP $ICODE (non-200), QUIESCED sentinel=absent on web-1 — not serving, but op=execute 2.2 will read UNKNOWN until the host reports the quiesced shape. The PREFLIGHT above proved the inventory script is current, so re-run op=execute and follow its 2.2 remedy (a DISABLED_UNATTRIBUTED body means op=rollback)."
      echo "quiesce-web: SECONDARY inventory body (first 120 chars): ${QINV_EXCERPT:0:120}"
    fi
    echo "::notice::quiesce-web complete (web-1, the web scheduler host, verified quiesced via deploy-status). web-2 scope: see op=execute SEAM 2.2a. Now re-run op=execute: 2.1 resumes from the persisted capture and 2.2 certifies the QUIESCED unit shape."
    ;;

  verify)
    # op=verify — POST-FLIP exactly-once check (#6178, ADR-100 Decision 7). Run
    # AFTER 2.2b/2.3 (Doppler flip) + 2.4 (app-repoint) + op=rearm.

    # ---- Precondition (P1-9 / P2-17): dedicated registry NON-empty. 2.4
    # app-repoint must have re-synced functions onto 10.0.1.40; a still-empty
    # registry means 2.4 did not land and there is nothing to verify. This is the
    # post-2.4 NON-empty mirror of the 2.0 gate. GET the web-host registry probe.
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    # #6258 bounded TRANSPORT retry (Finding 11): wraps ONLY the registry-probe transport
    # request (000/5xx) — NOT the registry_empty precondition VERDICT below (a still-empty
    # dark registry is a legitimate verdict, not a transient, and must NOT be retried).
    CODE=000; BODY=""
    for attempt in 1 2; do
      rm -f /tmp/verify-probe
      CODE=$(curl --disable --noproxy '*' -s --max-time 30 -o /tmp/verify-probe -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$SIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/inngest-registry-probe" || echo "000")
      BODY=$(cat /tmp/verify-probe 2>/dev/null || echo "")
      [[ "$CODE" == "200" ]] && break
      if [[ "$attempt" -lt 2 ]]; then
        echo "::warning::verify registry-probe transport HTTP $CODE (attempt $attempt/2) — retrying in 5s"; sleep 5
      fi
    done
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::verify precondition: registry-probe returned HTTP $CODE after 2 attempts: ${CAUSE:-<empty body>}"; exit 1
    fi
    REG_COUNT=$(echo "$BODY" | jq -r '.function_count // 0')
    if ! echo "$BODY" | jq -e 'type=="object" and has("registry_empty")' >/dev/null 2>&1 \
       || [[ "$(echo "$BODY" | jq -r '.registry_empty')" != "false" ]]; then
      echo "::error::verify precondition FAILED (P1-9/P2-17): dedicated registry is EMPTY (function_count=$REG_COUNT). 2.4 app-repoint did not land — functions never re-synced onto 10.0.1.40. Complete 2.4 (repoint INNGEST_BASE_URL → 10.0.1.40 + redeploy) before op=verify."
      exit 1
    fi
    echo "::notice::verify precondition PASSED: dedicated registry NON-empty (function_count=$REG_COUNT) — 2.4 landed"
    # P3-c: non-empty ≠ fully-synced (mirror of the op=rearm guard). function_count>0
    # proves the re-sync STARTED, not that EVERY pre-cutover function re-registered; a
    # half-synced registry would let op=verify bucket an incomplete function-set and read
    # clean. If the pre-cutover op=inventory baseline is supplied, enforce catch-up.
    BASELINE="${CUTOVER_REGISTRY_BASELINE:-}"
    if [[ -n "$BASELINE" ]]; then
      if ! [[ "$BASELINE" =~ ^[0-9]+$ ]]; then
        echo "::error::CUTOVER_REGISTRY_BASELINE must be an integer (the pre-cutover op=inventory 'functions' count)"; exit 1
      fi
      if [[ "$REG_COUNT" -lt "$BASELINE" ]]; then
        echo "::error::verify precondition FAILED (P3-c): dedicated registry function_count=$REG_COUNT < pre-cutover baseline=$BASELINE — the app re-sync is only PARTIAL. op=verify would bucket an incomplete function-set. Wait for the redeploy to finish, confirm function_count>=$BASELINE, then re-run op=verify."
        exit 1
      fi
      echo "::notice::verify precondition: registry fully re-synced (function_count=$REG_COUNT >= baseline=$BASELINE, P3-c)"
    else
      echo "::warning::verify precondition (P3-c): function_count=$REG_COUNT is NON-EMPTY but that only proves the re-sync STARTED. Confirm $REG_COUNT matches the pre-cutover op=inventory 'functions' count (or set CUTOVER_REGISTRY_BASELINE) before trusting an exactly-once verdict over a possibly-incomplete function-set."
    fi

    # ---- 2.6 exactly-once double-fire check. GET the web-host doublefire probe
    # (it forwards the runs(first, filter: RunsFilterV2!, orderBy) query with
    # { timeField: STARTED_AT, functionIDs } to the dedicated GQL over the private
    # net; P1-12 — the runner cannot reach 10.0.1.40 directly). Bucket every run by
    # (functionID, floor(startedAt / cron_period)); a bucket with >1 run is a
    # DOUBLE-FIRE. There is NO per-tick schedule field in v1.19.4 — the invariant
    # is derived from startedAt alone (ADR-100 Decision 7).
    CRON_PERIOD="${CUTOVER_CRON_PERIOD_SECONDS:-3600}"
    # P2-c CAVEAT + GUARD: ONE global CRON_PERIOD buckets EVERY function. The bucketing
    # is correctness-honest ONLY when every registered cron period ≥ CRON_PERIOD and is
    # hour-aligned to it: a cron firing FASTER than CRON_PERIOD yields >1 legitimate run
    # per bucket → false-positive (blocks verify — SAFE direction), and a real double-fire
    # straddling a bucket boundary → false-negative (UNSAFE). There is no per-tick schedule
    # field in v1.19.4 to source per-function periods, so this single-period assumption is
    # load-bearing. Guard: CRON_PERIOD must be a positive integer; then LOUDLY qualify the
    # verdict so no one reads "exactly-once VERIFIED" without the assumption.
    if ! [[ "$CRON_PERIOD" =~ ^[1-9][0-9]*$ ]]; then
      echo "::error::2.6 CRON_PERIOD invalid ('$CRON_PERIOD') — set CUTOVER_CRON_PERIOD_SECONDS to a positive integer ≤ the SHORTEST registered cron period (hour-aligned)."; exit 1
    fi
    echo "::warning::2.6 CRON_PERIOD=${CRON_PERIOD}s is applied to ALL functions (P2-c). The exactly-once verdict is SOUND ONLY IF every registered cron period ≥ ${CRON_PERIOD}s AND hour-aligned. If any cron fires faster than ${CRON_PERIOD}s, re-run op=verify with CUTOVER_CRON_PERIOD_SECONDS set to the SHORTEST registered cron period before trusting the result."
    # Forward the window lower bound + optional functionIDs scope as URL query params.
    # HMAC is over the empty GET body, so params don't alter it.
    # #6178 — anchor the scan window on the flip-FSM transition instant (fsm), else the
    # operator variable (var), else FAIL CLOSED. The 1-day floor is a SKEW CLAMP, not a
    # safety net: at the measured 728 runs/day a 7-day floor would be ~5,100 runs
    # ≈ 51 pages ≈ 214 s — not exhaustible — so a "safe" wide fallback would just trade
    # one deadline abort for another.
    if ! DF_RAW=$(doublefire_from 1 fsm); then
      echo "::error::2.6 doublefire-probe: coexistence anchor underivable (cause above). Refusing to scan an unanchored window — a clean verdict over the wrong window proves nothing."; exit 1
    fi
    read -r DF_FROM DF_ANCHOR_SOURCE <<< "$DF_RAW"
    # Fail-closed on the REACHABLE failure. `date -u -d ''` SUCCEEDS — it returns today's
    # midnight — so `2>/dev/null` is not a guard on its own. An empty DF_FROM would build
    # `?from=` and the probe would silently fall back to its OWN 365-day default,
    # restoring the exact unscannable window this change exists to remove.
    if ! [[ "$DF_FROM" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
      echo "::error::2.6 doublefire-probe: computed window lower bound is malformed ('$DF_FROM') — refusing to scan"; exit 1
    fi
    DF_FNIDS="${CUTOVER_DOUBLEFIRE_FUNCTION_IDS:-}"
    # OPEN-TOPPED on purpose — no `until` parameter. The post-repoint region (when the
    # dedicated host first had functions registered and therefore first COULD
    # double-fire) lies AFTER CUTOVER_WINDOW_UNTIL, as does every op=rollback-initiated
    # interval. Bounding the top reads like a symmetric tidy-up and would cut out the
    # highest-risk region. Do not "tidy" it.
    DF_URL="$BASE/inngest-doublefire-probe?from=${DF_FROM}&function_ids=${DF_FNIDS}"
    echo "::notice::2.6 doublefire-probe: scanning from=${DF_FROM} anchor_source=${DF_ANCHOR_SOURCE} function_ids=[${DF_FNIDS:-<all>}]"
    # #6258 bounded TRANSPORT retry (Finding 11): wraps ONLY the doublefire transport curl.
    # The 120s outer budget > the probe's 90s in-script deadline + 8s per-page floor (SUM bound).
    CODE=000; BODY=""
    for attempt in 1 2; do
      rm -f /tmp/verify-runs
      CODE=$(curl --disable --noproxy '*' -s --max-time 120 -o /tmp/verify-runs -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$SIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$DF_URL" || echo "000")
      BODY=$(cat /tmp/verify-runs 2>/dev/null || echo "")
      [[ "$CODE" == "200" ]] && break
      if [[ "$attempt" -lt 2 ]]; then
        echo "::warning::2.6 doublefire-probe transport HTTP $CODE (attempt $attempt/2) — retrying in 5s"; sleep 5
      fi
    done
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::2.6 doublefire-probe returned HTTP $CODE after 2 attempts: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e '.runs | type == "array"' >/dev/null 2>&1; then
      echo "::error::2.6 doublefire-probe did not return a {runs:[...]} object"; echo "$BODY"; exit 1
    fi
    # #6178 — PAGE-OVERLAP DEDUPE. The probe cursor-paginates runs(orderBy: STARTED_AT ASC) and a
    # run can come back on two pages (cause unconfirmed). Measured 2026-09-15: every reported
    # "double-fire" group equalled RUN_COUNT - total_count and was absent from trace_runs (one run
    # per tick). Dedupe by the run id (trace_runs.run_id PRIMARY KEY): a repeated page row shares
    # its id and two distinct runs never do. FALLBACK when the host's probe predates the id
    # projection: (functionID, startedAt) — startedAt is MILLISECOND precision, so two schedulers
    # firing in the same millisecond would collapse; that verdict is qualified, never silent.
    PRE_DEDUPE_N=$(echo "$BODY" | jq '.runs | length')
    DEDUPE_KEY=$(echo "$BODY" | jq -r 'if (.runs | length) > 0 and all(.runs[]; (.id | type) == "string") then "run-id" else "functionID+startedAt(ms)" end')
    BODY=$(echo "$BODY" | jq -c '.runs |= (if length > 0 and all(.[]; (.id | type) == "string") then unique_by(.id) else ([ .[] | select(.startedAt == null) ] + ([ .[] | select(.startedAt != null) ] | unique_by([.functionID, .startedAt]))) end)')
    RUN_COUNT=$(echo "$BODY" | jq '.runs | length')
    if (( PRE_DEDUPE_N > RUN_COUNT )); then
      echo "::notice::2.6 doublefire-probe: dropped $(( PRE_DEDUPE_N - RUN_COUNT )) page-overlap duplicate(s) (dedupe key: $DEDUPE_KEY)"
    fi
    # #6178 — NULL-SAFE BUCKETING (see the full rationale on the op=doublefire-probe arm).
    # fromdateiso8601 throws on a null startedAt and jq's exit 5 propagates through
    # `set -euo pipefail`; a run with no startedAt has not fired and cannot be a
    # double-fire, but the drop is counted rather than silent.
    NO_START=$(echo "$BODY" | jq '[ .runs[] | select(.startedAt == null) ] | length')
    if [[ "$NO_START" -gt 0 ]]; then
      echo "::notice::2.6 doublefire-probe: $NO_START run(s) carry no startedAt (queued/running/cancelled-before-start) and are excluded from bucketing — they have not fired, so they cannot be a double-fire."
    fi
    # #6178 — NON-VACUITY HARD GATE (AC-V3), enforced HERE rather than left to an
    # operator reading markers after a green run.
    #
    # "No duplicates found" and "nothing was looked at" produce the SAME verdict string
    # and are opposite facts. The probe reports the server's own totalCount precisely so
    # this arm can tell them apart — but a verdict that depends on a human noticing
    # `total_count=0` in Better Stack is operator diligence, and this plan's own
    # User-Brand Impact section requires non-vacuity BY CONSTRUCTION. A green op=verify
    # authorizes closing #6178 and DELETING the rollback snapshot, so the empty-scan
    # case must be loud and red.
    #
    # Two real inputs reach {runs:[]} on an HTTP 200: a mis-scoped
    # CUTOVER_DOUBLEFIRE_FUNCTION_IDS whose UUIDs no longer resolve post-repoint, and a
    # partial GraphQL error that nulls totalCount while leaving edges an empty array.
    TOTAL_COUNT=$(echo "$BODY" | jq -r '.total_count // "absent"')
    if [[ "$TOTAL_COUNT" == "0" || "$TOTAL_COUNT" == "unknown" || "$TOTAL_COUNT" == "absent" || "$RUN_COUNT" -eq 0 ]]; then
      echo "::error::2.6 VACUOUS SCAN — refusing to report a verdict. total_count=$TOTAL_COUNT run_count=$RUN_COUNT anchor_source=$DF_ANCHOR_SOURCE from=$DF_FROM. 'No duplicates' over a scan that examined nothing is not an exactly-once proof, and must not close #6178 or release the rollback snapshot. Check the function_ids scope and the anchor, then re-dispatch."
      exit 1
    fi
    # #6178 — COMPLETENESS FLOOR. After the dedupe, the distinct runs must be at least the server's
    # total_count (>=, not ==: the window is open-topped and the scheduler keeps inserting). Fewer
    # means runs were wrongly collapsed or MISSED by pagination, and a clean verdict over an
    # incomplete scan is the false-CLEAN this gate must never print.
    if [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]] && (( RUN_COUNT < TOTAL_COUNT )); then
      echo "::error::2.6 INCOMPLETE SCAN — refusing to report a verdict. pre_dedupe=$PRE_DEDUPE_N deduped=$RUN_COUNT total_count=$TOTAL_COUNT (dedupe key: $DEDUPE_KEY). Fewer distinct runs than the server reports means runs were collapsed or missed; re-dispatch op=verify."
      exit 1
    fi
    echo "::notice::2.6 doublefire-probe: $RUN_COUNT run(s) in window (server total_count=$TOTAL_COUNT); bucketing by (functionID, floor(startedAt / ${CRON_PERIOD}s))"
    # Any (functionID, floor(startedAt/period)) group with >1 run is a double-fire.
    DUPES=$(echo "$BODY" | jq -c --argjson period "$CRON_PERIOD" '
      [ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) / $period | floor) } ]
      | group_by([.fn, .bucket])
      | map(select(length > 1))
      | map({ functionID: .[0].fn, bucket: .[0].bucket, count: length }) ')
    DUPE_COUNT=$(echo "$DUPES" | jq 'length')
    if [[ "$DUPE_COUNT" -gt 0 ]]; then
      echo "::error::2.6 DOUBLE-FIRE detected: $DUPE_COUNT (functionID, tick-bucket) group(s) with >1 run — two schedulers fired the same cron tick. Details (ids + counts only, AC-NOBODY):"
      echo "$DUPES" | jq -c '.[]'
      exit 1
    fi
    # #6178 — QUALIFY the verdict rather than printing one string for materially
    # different claims. A clean result over a scoped population, a narrowed override
    # window, or an unverified operator-typed anchor is a WEAKER claim than one over an
    # fsm-anchored full-population scan, and AC-V4 keys on this distinction.
    VERDICT_QUALIFIERS=""
    if [[ "$DEDUPE_KEY" != "run-id" ]]; then
      VERDICT_QUALIFIERS="${VERDICT_QUALIFIERS}page-overlap dedupe fell back to (functionID, startedAt) at millisecond precision, so a same-millisecond double-fire is indistinguishable from a repeated page row (the host probe predates the run-id projection); "
    fi
    if [[ -n "$DF_FNIDS" ]]; then
      VERDICT_QUALIFIERS="${VERDICT_QUALIFIERS}population scoped to function_ids=[$DF_FNIDS] (the destructive crons may be excluded); "
    fi
    case "$DF_ANCHOR_SOURCE" in
      override*|floor\(override\)) VERDICT_QUALIFIERS="${VERDICT_QUALIFIERS}window NARROWED by the CUTOVER_ANCHOR_FROM override, so it may not cover the whole coexistence region; " ;;
      var|floor\(var\)) VERDICT_QUALIFIERS="${VERDICT_QUALIFIERS}anchor came from an operator-typed variable on a different clock, not the on-host flip-FSM row; " ;;
      floor\(\)) VERDICT_QUALIFIERS="${VERDICT_QUALIFIERS}no anchor was derivable; the window is the bare fallback floor; " ;;
    esac
    if [[ -n "$VERDICT_QUALIFIERS" ]]; then
      echo "::warning::2.6 exactly-once VERIFIED (QUALIFIED) — no double-fire found, but this is NOT a full exactly-once proof: ${VERDICT_QUALIFIERS%%; }. Do not treat a qualified verdict as satisfying AC-V3/AC-V4 without demonstrating the scanned window covers the quiesce instant."
    else
      echo "::notice::2.6 exactly-once VERIFIED: every (functionID, tick-bucket) has exactly one run (no double-fire), over $RUN_COUNT run(s) anchored on the flip-FSM transition (anchor_source=$DF_ANCHOR_SOURCE, from=$DF_FROM) — SOUND ONLY IF every registered cron period ≥ ${CRON_PERIOD}s and hour-aligned (see the CRON_PERIOD caveat above; P2-c)"
    fi
    echo "::notice::2.6 SCOPE CAVEAT (P2-a / DI-C3): the doublefire-probe reads ONLY the dedicated host's (10.0.1.40) run history. It is NOT a web-host double-fire detector — a surviving web-host (colocated) scheduler fires against prod Postgres via its OWN loopback backend PRE-repoint, whose runs never appear on the dedicated host. The web scheduler host (web-1) is the only colocated scheduler (web-2 scope: see op=execute SEAM 2.2a); op=quiesce-web + the op=execute 2.2 QUIESCED gate are the control against a web-host double-fire — op=verify cannot substitute for it."

    # ---- Missed-tick auto-enumeration (P2-16): ticks that fell in the
    # quiesce→register gap have no run; AUTO-emit a ready-to-run soleur:trigger-cron
    # set rather than asking the operator to enumerate. From the recorded window
    # [CUTOVER_WINDOW_FROM, CUTOVER_WINDOW_UNTIL] we compute the expected tick
    # buckets at cron_period cadence and diff against the observed run buckets; any
    # expected bucket with ZERO runs is a missed tick.
    WIN_FROM="${CUTOVER_WINDOW_FROM:-}"
    WIN_UNTIL="${CUTOVER_WINDOW_UNTIL:-}"
    if [[ -z "$WIN_FROM" || -z "$WIN_UNTIL" ]]; then
      echo "::notice::missed-tick auto-enumeration (P2-16): set CUTOVER_WINDOW_FROM + CUTOVER_WINDOW_UNTIL (ISO-8601, the quiesce→register gap) to auto-emit the trigger-cron list; skipping (window not supplied)."
    else
      FROM_EPOCH=$(date -u -d "$WIN_FROM" +%s 2>/dev/null || echo "")
      UNTIL_EPOCH=$(date -u -d "$WIN_UNTIL" +%s 2>/dev/null || echo "")
      if [[ -z "$FROM_EPOCH" || -z "$UNTIL_EPOCH" || "$UNTIL_EPOCH" -le "$FROM_EPOCH" ]]; then
        echo "::error::missed-tick auto-enumeration: invalid window [$WIN_FROM,$WIN_UNTIL]"; exit 1
      fi
      # Observed buckets (per function) from the runs.
      # #6178 — the SAME null-startedAt guard as the bucketing above: this is the
      # identical construct, so it carried the identical jq exit-5 crash.
      OBSERVED=$(echo "$BODY" | jq -c --argjson period "$CRON_PERIOD" \
        '[ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) / $period | floor) } ] | unique')
      FROM_BUCKET=$(( FROM_EPOCH / CRON_PERIOD ))
      UNTIL_BUCKET=$(( UNTIL_EPOCH / CRON_PERIOD ))
      # Guard the tick loop with a hard cap so a mis-set window cannot spin.
      SPAN=$(( UNTIL_BUCKET - FROM_BUCKET + 1 ))
      if [[ "$SPAN" -lt 1 || "$SPAN" -gt 10000 ]]; then
        echo "::error::missed-tick auto-enumeration: window spans $SPAN tick-buckets (out of [1,10000]) — check CRON_PERIOD/window"; exit 1
      fi
      echo "::notice::missed-tick auto-enumeration (P2-16): scanning $SPAN tick-bucket(s) in [$WIN_FROM,$WIN_UNTIL] for functions with no run — ready-to-run trigger-cron set:"
      MISSED=0
      # Enumerate the DISTINCT functions observed, then find their empty in-window buckets.
      for fn in $(echo "$BODY" | jq -r '[.runs[].functionID] | unique | .[]'); do
        for (( b=FROM_BUCKET; b<=UNTIL_BUCKET; b++ )); do
          HAS=$(echo "$OBSERVED" | jq --arg fn "$fn" --argjson b "$b" 'any(.[]; .fn == $fn and .bucket == $b)')
          if [[ "$HAS" != "true" ]]; then
            TICK_TS=$(date -u -d "@$(( b * CRON_PERIOD ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "bucket-$b")
            echo "  soleur:trigger-cron --function-id $fn --missed-tick $TICK_TS"
            MISSED=$((MISSED + 1))
          fi
        done
      done
      echo "::notice::missed-tick auto-enumeration: $MISSED missed tick(s) enumerated (re-fire the list above via soleur:trigger-cron; in-window ticks are not auto-backfilled)"
    fi
    echo "::notice::op=verify complete"
    ;;

  rollback)
    # op=rollback — the AUTHORED reverse of the cutover (P1-13). As of #6369 it has TWO
    # halves: (A) the DEDICATED-host stop is now a NO-SSH Doppler write
    # INNGEST_CUTOVER_FLIP=rollback on soleur-inngest/prd (folded here from the former
    # operator SEAM D.5 step 1 — the enabled on-host timer picks it up and drives the FSM to
    # rolled-back); (B) the WEB re-enable + restart across EVERY $CUTOVER_HOSTS host via the
    # deploy hook over the private net (no SSH). op=rollback stays a SEPARATE verb from op=arm
    # (ADR-100 Decision 6b forward/reverse symmetry). Half (A) is value-silent + behind the same
    # inngest-cutover environment required-reviewer gate + conditional DOPPLER_TOKEN_INNGEST_ARM
    # as op=arm; it writes ONLY the flip value (never POSTGRES_URI/HEARTBEAT). This is also the
    # P0-3 `aborted`-state recovery (the DBSIZE gate disabled the web schedulers; (B) restores them).
    if [[ -z "${CUTOVER_HOSTS:-}" ]]; then
      echo "::error::CUTOVER_HOSTS is empty — refusing to run rollback against an empty host-set"; exit 1
    fi
    IFS=',' read -r -a HOSTS <<< "$CUTOVER_HOSTS"
    if [[ "${#HOSTS[@]}" -lt 1 ]]; then
      echo "::error::CUTOVER_HOSTS parsed to zero hosts (value: '$CUTOVER_HOSTS')"; exit 1
    fi

    # ---- Half (A): the no-SSH reverse flip write (#6369). Behind the environment gate.
    if [[ -z "${DOPPLER_TOKEN_INNGEST_ARM:-}" ]]; then
      echo "::error::op=rollback: DOPPLER_TOKEN_INNGEST_ARM is empty — the repo secret did not resolve (approve the inngest-cutover environment required-reviewer gate on this dispatch; else check 'gh secret list | grep DOPPLER_TOKEN_INNGEST_ARM'). Refusing the reverse flip write."; exit 1
    fi
    # G1' decides ONLY whether to WRITE the reverse flip — it must NOT gate Half (B). Half (B),
    # the web re-enable, is the pre-#6369 UNCONDITIONAL reverse of 2.2 quiesce and the documented
    # P0-3 aborted-state recovery, so it runs for EVERY state (arch review P1). Write `rollback`
    # when the forward flip is armed OR progressing (∈ {armed,flipping,flushed,done}) — armed
    # included so a pending arm is stopped before the timer completes it; idempotent-skip when
    # already rollback/rolled-back; for a non-forward state (unset/empty/aborted) there is nothing
    # on the dedicated host to reverse. Fail-CLOSED on a read error (a swallowed read must not be
    # mistaken for 'unset'). The flip state is a public enum — not masked.
    if ! DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get DOPPLER_PROJECT -p soleur-inngest -c prd --plain >/dev/null 2>&1; then
      echo "::error::op=rollback: cannot read soleur-inngest/prd (config-readability probe failed). Refusing the reverse-flip decision FAIL-CLOSED; retry once the read path is healthy. Do NOT SSH the host."; exit 1
    fi
    RB_CUR=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain 2>/dev/null || echo "unset")
    case "$RB_CUR" in
      armed|flipping|flushed|done)
        echo "::notice::op=rollback: G1' — forward flip is '$RB_CUR'; writing the reverse flip to stop the dedicated scheduler BEFORE re-enabling the web schedulers (prevents two live schedulers double-firing prod crons)."
        RB_TS=$(date +%s)
        printf '%s' 'rollback' | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=rollback: writing INNGEST_CUTOVER_FLIP=rollback FAILED. Re-dispatch op=rollback. Do NOT SSH the host."; exit 1; }
        echo "::notice::op=rollback: wrote INNGEST_CUTOVER_FLIP=rollback to soleur-inngest/prd (no value echoed) — the enabled on-host timer stops the dedicated scheduler and drives the FSM to rolled-back."
        # BLOCKING confirm: the dedicated scheduler MUST be confirmed stopped BEFORE Half (B)
        # re-enables the web schedulers — else both run and double-fire prod crons (user-impact
        # F2 / DI, an exactly-once violation). On timeout, FAIL (exit 1) WITHOUT re-enabling web:
        # that leaves at most ONE potentially-live scheduler (the dedicated one), never two.
        RB_ISO=$(date -u -d "@$RB_TS" +'%Y-%m-%d %H:%M:%S')
        RB_STATE=$(confirm_flip_state "$RB_ISO")
        case "$RB_STATE" in
          rolled-back)
            echo "::notice::op=rollback: FSM confirmed rolled-back (flag:rolled-back exit_code:0) via Better Stack (since $RB_ISO) — dedicated scheduler stopped; safe to re-enable the web schedulers." ;;
          *)
            echo "::error::op=rollback: the FSM did not confirm rolled-back within 600s (state='$RB_STATE'; the write DID land). WITHHOLDING the web re-enable to avoid two live schedulers double-firing prod crons — at most one scheduler is live now. Verify the dedicated scheduler stopped via the inngest-cutover-flip Better Stack line (re-run scripts/betterstack-query.sh, runbook §3), then re-dispatch op=rollback. Do NOT SSH the host."; exit 1 ;;
        esac
        ;;
      rollback|rolled-back)
        echo "::notice::op=rollback: INNGEST_CUTOVER_FLIP is already '$RB_CUR' — the dedicated scheduler is stopping/stopped; skipping the (idempotent) reverse write, proceeding to the web re-enable." ;;
      *)
        echo "::notice::op=rollback: INNGEST_CUTOVER_FLIP is '${RB_CUR:-unset}' (not armed/forward-progressed) — nothing on the dedicated host to reverse (aborted = already stopped by the DBSIZE gate; unset = never armed). This is the documented P0-3 aborted-state recovery; proceeding to the web re-enable." ;;
    esac

    # ---- #6552: DELETE the armed INNGEST_HEARTBEAT_URL (inverse of op=arm G4, :760).
    # UNCONDITIONAL — it lives in Half (B), which runs for EVERY entry state, NOT in the
    # forward-state case arm above. op=arm writes the URL at G4 BEFORE the FSM runs, so it
    # persists in `aborted`, the partial-arm state (G4 wrote it, then G5 `armed` failed),
    # and the `rolled-back` re-dispatch path — all of which the forward-state arm skips.
    # Leaving it stranded there re-creates the two-pushers-on-one-monitor bug #6552 closes:
    # the dedicated host keeps pinging the shared Better Stack heartbeat monitor while the
    # re-enabled co-located host also pings, so the monitor stays green on either host and
    # stops being evidence about either. After the delete, the dedicated heartbeat dark arm
    # sees url_present=no and skips its ping -> ONE unambiguous pusher (co-located) per
    # monitor (inngest-host.tf:137-171). Runs AFTER Half (A)'s `rolled-back` confirm (a
    # forward-state rollback only reaches Half (B) once the dedicated scheduler is confirmed
    # stopped), so a `done`-state rollback never blanks the monitor while the dedicated
    # scheduler is still live. Idempotent (absent -> no-op) + value-silent; a delete error
    # WARNs but does NOT block the safety-critical web re-enable below — a lingering monitor
    # false-green is strictly less severe than withholding the double-fire prevention.
    # Capture stderr (NOT stdout — the CLI prints remaining secrets to stdout, so it stays
    # >/dev/null) so a real Doppler error's cause is visible inline in the ::warning::,
    # not just "transient error". Safe: delete only ever handled the secret NAME, never a
    # value, so the stderr tail carries no secret.
    if DELETE_ERR=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets delete INNGEST_HEARTBEAT_URL -p soleur-inngest -c prd --yes 2>&1 >/dev/null); then
      echo "::notice::op=rollback: deleted INNGEST_HEARTBEAT_URL from soleur-inngest/prd (inverse of op=arm G4) — the dedicated heartbeat dark arm now skips its ping; one pusher per monitor restored (no value echoed)."
    else
      ERR_TAIL=$(printf '%s' "$DELETE_ERR" | tr -d '\r' | tr '\n' ' ' | tail -c 300)
      echo "::warning::op=rollback: could not delete INNGEST_HEARTBEAT_URL from soleur-inngest/prd (already absent, or a transient Doppler error: ${ERR_TAIL:-<no stderr>}). NOT blocking the web re-enable. If a stale URL persists the dedicated host may remain a second heartbeat pusher (monitor false-green) — re-dispatch op=rollback, or verify via cat-deploy-state.sh inngest_heartbeat_dark_arm."
    fi

    # ---- #7228: PAUSE the consumer heartbeat, the exact inverse of the delete above --------
    # THE FALSE PAGE THIS PREVENTS. betteruptime_heartbeat.inngest_consumer (inngest.tf) is fed by
    # inngest-consumer-probe.timer on the WEB host, which pings ONLY while 10.0.1.40 serves a
    # non-empty registry and SUPPRESSES otherwise, so that absence alarms. That is exactly the
    # property that makes it detect #7228 — and exactly why a DELIBERATE rollback trips it: the
    # rollback's whole purpose is to stop the dedicated scheduler, the probe correctly suppresses,
    # and ~4 minutes later (period 180 + grace 60) the operator is paged for a state they just
    # asked for. A monitor that pages on intended operator actions is one the operator learns to
    # ignore, which is how the NEXT real outage goes unnoticed.
    #
    # Symmetric to the URL delete above: that one removes the dedicated host's pusher for the
    # SHARED monitor; this one quiesces the monitor whose feeder the rollback has just silenced.
    #
    # PAUSE, never delete: the ADR-117 measured-beat arm gate in apply-web-platform-infra.yml
    # re-arms it automatically on the first apply after the host serves again, and it gates on a
    # live `status=="paused"`. Deleting the resource would instead force a terraform recreate and
    # mint a NEW url, stranding the one already in Doppler under ignore_changes=[value].
    #
    # op=arm deliberately does NOT unpause. ADR-117's whole rule is that a monitor is unpaused
    # only after a REAL beat has been measured; arming it here — before the FSM has even run —
    # would create precisely the green-but-inert monitor #6537 spent nine days as.
    #
    # Resolved BY NAME rather than from an id output: the name is pinned in inngest.tf, and a
    # name lookup keeps working across a terraform recreate that would change the id. Fail-open
    # with a WARN, matching the delete above — a monitor left un-paused pages the operator, which
    # is strictly less severe than withholding the safety-critical web re-enable below.
    # SCOPED explicitly. This was the only Doppler read in the file with no -p/-c, so it depended
    # on ambient DOPPLER_PROJECT/DOPPLER_CONFIG that the workflow env map does not document —
    # while the warning below asserts "unreadable from prd_terraform". Fail-open is correct here
    # (a missed pause pages the operator; blocking would withhold the safety-critical web
    # re-enable), but the unscoped read made that the LIKELY path rather than the exceptional one.
    BS_API=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain 2>/dev/null || true)
    # Mask only a value that exists: an unconditional add-mask on an empty read emits a bare
    # `::add-mask::`, which is noise in the log and masks nothing.
    [[ -n "$BS_API" ]] && printf '::add-mask::%s\n' "$BS_API"
    if [[ -z "$BS_API" ]]; then
      echo "::warning::op=rollback: BETTERSTACK_API_TOKEN unreadable from prd_terraform — NOT pausing the consumer heartbeat. It will alarm ~4min after the dedicated scheduler stops, for a state this rollback created on purpose. Pause 'soleur-inngest-consumer-prd' manually if it pages, or re-dispatch once the token reads."
    else
      HB_ID=$(curl --disable --noproxy '*' -fsS --max-time 20 -H "Authorization: Bearer $BS_API" \
        'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' 2>/dev/null \
        | jq -r '.data[] | select(.attributes.name == "soleur-inngest-consumer-prd") | .id' 2>/dev/null | head -1 || true)
      if [[ -z "$HB_ID" ]]; then
        echo "::warning::op=rollback: could not resolve the 'soleur-inngest-consumer-prd' heartbeat id from the Better Stack API — NOT pausing it. It will alarm ~4min after the dedicated scheduler stops. NOT blocking the web re-enable."
      elif curl --disable --noproxy '*' -fsS --max-time 20 -X PATCH -H "Authorization: Bearer $BS_API" -H 'Content-Type: application/json' \
             --data-binary '{"paused":true}' \
             "https://uptime.betterstack.com/api/v2/heartbeats/$HB_ID" >/dev/null 2>&1; then
        echo "::notice::op=rollback: paused the consumer heartbeat (soleur-inngest-consumer-prd) — its feeder is deliberately silenced by this rollback, so pausing prevents a page for an intended state. The ADR-117 measured-beat arm gate re-arms it on the first apply after the host serves again."
      else
        echo "::warning::op=rollback: PATCH paused=true on the consumer heartbeat FAILED. It will alarm ~4min after the dedicated scheduler stops, for a state this rollback created on purpose. NOT blocking the web re-enable; pause 'soleur-inngest-consumer-prd' or re-dispatch op=rollback."
      fi
    fi

    # ---- Half (B): the web re-enable + restart fan-out (the pre-#6369 behaviour).
    echo "::notice::rollback: re-enabling inngest across host-set [$CUTOVER_HOSTS] (${#HOSTS[@]} host(s)) — reverse of 2.2 quiesce (P1-13)"
    # The reverse of 2.2 quiesce is now a SINGLE no-SSH `enable inngest _ _` verb
    # (ci-deploy.sh) = enable + start + verify-serving-and-enabled in ONE flock-held
    # handler. This is deliberately NOT two POSTs (an enable POST then a restart POST):
    # the second POST races `flock -n` and can leave the unit enabled-but-stopped,
    # reported as success (arch P1-1 / DI P2-C). The enable verb re-arms the
    # [Install] symlink a quiesce-disable removed (a `restart` never touches it) so the
    # web scheduler survives a reboot — no operator systemctl step. The peers fan-out
    # forwards it to every host over the private net.
    PAYLOAD=$(printf '{"command":"enable inngest _ _","peers":"%s"}' "$CUTOVER_HOSTS")
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/rollback-body
    CODE=$(curl --disable --noproxy '*' -s --max-time 60 -o /tmp/rollback-body -w '%{http_code}' \
      -X POST -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/deploy" || echo "000")
    if [[ "$CODE" != "202" ]]; then
      CAUSE="$(tr -d '\n\r' < /tmp/rollback-body 2>/dev/null)"
      echo "::error::rollback enable webhook rejected (HTTP $CODE): ${CAUSE:-<empty body>}. The webhook was unreachable — check CF-Access/HMAC + the run log, then re-dispatch. Do NOT SSH the host."; exit 1
    fi
    echo "::notice::rollback: enable fan-out accepted (202) for [$CUTOVER_HOSTS] (the deploy peers path forwards enable+start to EVERY host's private IP — this fan-out IS per-host) — polling deploy-status for the host-side enabled verdict"
    # POLL /hooks/deploy-status for web-1's (the deploy tunnel origin) terminal inngest verdict —
    # mirror the op=quiesce-web poll so the receiving host's inngest_enable_failed /
    # inngest_start_failed / inngest_reenable_unverified / enabled_peer_fanout_unaccepted
    # verdict is reachable from the run (not a fire-and-forget 202). FRESH_FLOOR-anchored.
    TRIGGER_TS=$(date +%s)
    FRESH_FLOOR=$((TRIGGER_TS - 60))
    GSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    RMAX_POLLS=120
    RPOLL_INTERVAL=5
    ENABLED=0
    for i in $(seq 1 "$RMAX_POLLS"); do
      rm -f /tmp/rollback-status
      curl --disable --noproxy '*' -s --max-time 10 -o /tmp/rollback-status -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$GSIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/deploy-status" >/dev/null || true
      BODY=$(cat /tmp/rollback-status 2>/dev/null || echo "")
      if [ -z "$BODY" ] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
        echo "Attempt $i/$RMAX_POLLS: non-JSON/empty deploy-status — retrying"; sleep "$RPOLL_INTERVAL"; continue
      fi
      EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
      REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
      COMPONENT=$(echo "$BODY" | jq -r '.component // "unknown"')
      START_TS=$(echo "$BODY" | jq -r '.start_ts // 0')
      if [ "$COMPONENT" != "inngest" ]; then
        echo "Attempt $i/$RMAX_POLLS: last op was for $COMPONENT, not inngest — waiting"; sleep "$RPOLL_INTERVAL"; continue
      fi
      if [ "$START_TS" -lt "$FRESH_FLOOR" ]; then
        echo "Attempt $i/$RMAX_POLLS: state predates this trigger (start_ts=$START_TS < floor=$FRESH_FLOOR) — waiting"; sleep "$RPOLL_INTERVAL"; continue
      fi
      case "$REASON" in
        enabled)
          echo "::notice::rollback: host-side ENABLED confirmed (reason=enabled exit_code=$EXIT_CODE) — inngest re-enabled + serving on web-1 (the deploy tunnel origin)"; ENABLED=1; break ;;
        inngest_enable_failed|inngest_start_failed|inngest_reenable_unverified)
          echo "::error::rollback re-enable FAILED (reason=$REASON): pull reason= from /hooks/deploy-status + Better Stack (logger -t ci-deploy) and investigate. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        enabled_peer_fanout_unaccepted)
          echo "::error::rollback: a PEER enable fan-out was NOT accepted (unreachable/HMAC-rejected — NON-ACCEPTANCE, not peer-not-enabled; DI-C3). Check the peer host + re-dispatch. Do NOT SSH the host."; echo "$BODY" | jq .; exit 1 ;;
        *)
          if [ "$EXIT_CODE" == "-1" ]; then
            echo "Attempt $i/$RMAX_POLLS: enable still running (reason=$REASON)"
          else
            # TERMINAL (exit_code != -1) but the reason matched no enumerated verdict —
            # fast-fail instead of polling to the full timeout (a reason rename would
            # otherwise silently degrade to a $((RMAX_POLLS * RPOLL_INTERVAL))s wait).
            echo "::error::unrecognized terminal reason $REASON (exit_code=$EXIT_CODE) — rollback enable reached a terminal state that matched no known verdict; failing fast. Pull reason= from /hooks/deploy-status + Better Stack (logger -t ci-deploy). Do NOT SSH the host."; echo "$BODY" | jq .; exit 1
          fi
          ;;
      esac
      sleep "$RPOLL_INTERVAL"
    done
    if [[ "$ENABLED" -ne 1 ]]; then
      echo "::error::rollback did not reach the terminal 'enabled' verdict within $((RMAX_POLLS * RPOLL_INTERVAL))s. If the webhook was unreachable, re-dispatch; otherwise pull reason= from /hooks/deploy-status + Better Stack. Do NOT SSH the host."; exit 1
    fi
    # web-2 scope (DI-C3): see op=execute SEAM 2.2a — the enable fan-out to web-2 is tolerated
    # (its failure lands on web-2's own slot, unread here); web-1 is the host CI verified.
    echo "::notice::rollback complete (web-1, the web scheduler host, verified enabled via deploy-status). web-2 scope: see op=execute SEAM 2.2a — the enable fan-out to web-2 is tolerated (it reports inngest_enable_failed on web-2's own deploy-status slot, which this run does not read) and needs no further step."
    ;;

  resume)
    # --- #7228: the POST-FLUSH re-entry, and the ONLY recovery the flip guard names -----------
    # WHY THIS VERB HAD TO EXIST. inngest-server-flip-guard.sh refuses a prod start when the flag
    # is `done` and this host carries no done-owner marker — the inherited-`done` case, i.e. every
    # REPLACED host. Its refusal message prescribes INNGEST_CUTOVER_FLIP=flushed. Nothing wrote
    # that value: op=arm writes `armed`, op=rollback writes `rollback`, and op=arm's G1 explicitly
    # REFUSES when the flag is already armed/flipping/flushed/done. So the named recovery was a
    # bare out-of-band Doppler write against a deny-all-public host — an unowned operator step of
    # exactly the class hr-no-ssh-fallback-in-runbooks and
    # hr-never-label-any-step-as-manual-without forbid, on the critical recovery path.
    #
    # WHY `flushed` AND NOT A RE-ARM. Re-arming is refused by design: the monotonic flush latch
    # lives on /mnt/data and SURVIVES the replace, so the armed arm hits refuse_rearm_after_done
    # and drives the flag terminal — correctly, because post-flush that Redis holds the live prod
    # queue and re-flushing is the #5450 catastrophe. The `flushed` arm is the safe re-entry: it
    # starts the server, verifies it actually serves, records the owner marker and completes to
    # `done` WITHOUT re-running FLUSHALL.
    #
    # GATED, because `flushed` authorises a prod start. Two preconditions, both fail-closed:
    #  G1 the flag must currently be a TERMINAL non-serving state (done/aborted/rolled-back).
    #     Writing `flushed` over an in-flight armed/flipping flip would race the running FSM.
    #  G2 the durable flush latch must EXIST. `flushed` asserts "the flush already happened"; if
    #     no latch is recorded that assertion is unfounded, and starting the server would adopt a
    #     queue that was never flushed. Answered off-host, never by SSH.
    #
    #     ENFORCED SINCE #7462, AND NOT HERE — read this clause as a statement about the SYSTEM,
    #     not about this verb. From #7228 until #7462 it was documentation only: nothing anywhere
    #     evaluated it. `op=arm`'s G3.7 now does, over betterstack-query.sh, keyed on the two
    #     emit_state literals that prove a flush happened (`flip-complete`,
    #     `refuse-rearm-after-done`). It lives at `op=arm` because that is the verb the predicate
    #     can act on: `op=arm` must refuse when a latch EXISTS, `op=resume` must refuse when one
    #     does NOT, and only the first is answerable off-host — absence of a Better Stack row is
    #     also what a retention lapse looks like, so an off-host reader can only ever prove
    #     presence. G1 below is what protects this verb, by scoping it to `done`: only a completed
    #     flip evidences that a FLUSHALL actually happened. The earlier wording named the
    #     deploy-status hook as the read path; the implemented reader is Better Stack.
    #
    #     KNOWN DEAD END, stated rather than left to be rediscovered: from terminal `aborted`
    #     there is no dispatchable path forward. G1 accepts `done` ONLY, and `op=arm` is refused by
    #     its own G3.7 whenever the latch that drove the FSM to `aborted` is still recorded. That
    #     is pre-existing and correct — the latch is what stops a second FLUSHALL — but it means
    #     recovery from `aborted` is a /mnt/data recut via the inngest-host-replace window, not a
    #     dispatch. #7462 did not change it; it made the refusal happen before the prod writes.
    if [[ -z "${DOPPLER_TOKEN_INNGEST_ARM:-}" ]]; then
      echo "::error::op=resume: DOPPLER_TOKEN_INNGEST_ARM is empty — the repo secret did not resolve (approve the inngest-cutover environment required-reviewer gate on this dispatch). Refusing the post-flush re-entry write."; exit 1
    fi
    RS_CUR=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain 2>/dev/null || echo "__READ_FAILED__")
    # SCOPED TO `done`, and that scoping IS the safety argument. `done` is the only value that
    # evidences a COMPLETED flip, i.e. that a FLUSHALL actually happened — which is exactly what
    # writing `flushed` asserts. Widening this to aborted/rolled-back would let the resume arm
    # start a scheduler against a queue that was never flushed, and those states have a correct
    # verb already: op=arm, whose monotonic-latch refusal is the intended answer there.
    # It is also precisely the guard's case: a REPLACED host inherits `done` and carries no
    # done-owner marker, which is the only state whose named recovery had no dispatchable verb.
    case "$RS_CUR" in
      __READ_FAILED__)
        echo "::error::op=resume: cannot read INNGEST_CUTOVER_FLIP from soleur-inngest/prd. Refusing FAIL-CLOSED — a swallowed read must not be mistaken for a terminal state. Do NOT SSH the host."; exit 1 ;;
      done)
        echo "::notice::op=resume: G1 — flag is 'done', which evidences a completed flip; the post-flush re-entry is permitted." ;;
      armed|flipping|flushed)
        echo "::error::op=resume: G1 REFUSING — INNGEST_CUTOVER_FLIP is '$RS_CUR', an IN-FLIGHT state. The on-host FSM is mid-flip; writing 'flushed' now would race it. Let it reach a terminal state, then re-dispatch."; exit 1 ;;
      *)
        echo "::error::op=resume: G1 REFUSING — INNGEST_CUTOVER_FLIP is '${RS_CUR:-unset}', not 'done'. op=resume exists for ONE case: a replaced host that inherited a completed flip's 'done' and carries no done-owner marker, so the flip guard refuses its start. Only 'done' evidences that a FLUSHALL happened; from any other state, writing 'flushed' would start a scheduler against a queue that may never have been flushed. Use op=arm for a fresh cutover — its monotonic-latch refusal is the correct answer if a flush already occurred."; exit 1 ;;
    esac
    # G2 (the latch must EXIST) stays deferred here, and its absence is NOT the #7674 hole:
    # op=arm's PERMITTING condition is an ABSENCE (L=0), which a dark host manufactures for free,
    # whereas op=resume's is the PRESENCE of a `done` that only a completed flip writes — so a
    # silent host can BLOCK this verb but can never AUTHORISE it. H is checked below for
    # DELIVERABILITY, not for evidence.
    #
    # G3 — HOST-AUDIBILITY GATE (#7674, CTO ruling). `flushed` is acted on ONLY by the on-host 30s
    # timer. Writing it to a dark host recovers nothing AND parks the flag in a state op=resume's
    # own G1 rejects as IN-FLIGHT, while op=arm is separately refused by G3.7 — stranding the only
    # dispatchable re-entry the system has, i.e. manufacturing a fresh instance of the KNOWN DEAD
    # END this arm already documents, which has no clearing apply_target today (#7695). Refusing is
    # strictly dominant: it forfeits nothing the write would have achieved.
    #
    # Known false-negative, accepted: H=0 also covers "host fine, Vector down". That is the only
    # case this refuses a workable recovery, and it is acceptable because H is known-POSITIVE in
    # this verb's exact target state — a guard-refused host still runs inngest-cutover-flip.timer
    # and emits noop-* rows (measured ~1.4/min, the basis of #7674).
    RS_LIVE_N="$(_flip_liveness_count)"
    case "$(resume_liveness_decide "$RS_LIVE_N")" in
      audible)
        echo "::notice::op=resume: G3 — host is audible ($RS_LIVE_N inngest-cutover-flip row(s) from $INNGEST_HOST_NAME within $FLIP_LIVENESS_SINCE), so the on-host FSM can act on this write." ;;
      silent)
        echo "::error::op=resume: G3 REFUSING — ZERO inngest-cutover-flip rows from host=$INNGEST_HOST host_name=$INNGEST_HOST_NAME within $FLIP_LIVENESS_SINCE, while the read path itself SUCCEEDED: the dedicated host is dark or has stopped shipping journald. 'flushed' is acted on ONLY by the on-host 30s timer, so writing it now recovers nothing AND parks the flag in a state op=resume's own G1 rejects as IN-FLIGHT — stranding the only dispatchable re-entry this system has (op=arm is separately refused by G3.7). Refusing BEFORE the write; nothing was changed. Check inngest-cutover-flip.timer and Vector via the SOLEUR_INNGEST_SERVER_PROBE row (it carries server_active and cutover_flag in one line). If the host is genuinely gone, the path forward is an inngest-host-replace, then re-dispatch op=resume. Do NOT SSH the host."; exit 1 ;;
      unreadable)
        echo "::error::op=resume: G3 REFUSING FAIL-CLOSED — the liveness READ PATH failed (this is NOT a statement about the host). Verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform, then re-dispatch. Refusing BEFORE the write; nothing was changed. Do NOT SSH the host."; exit 1 ;;
      *)
        echo "::error::op=resume: G3 — resume_liveness_decide returned an unrecognised outcome. Refusing FAIL-CLOSED."; exit 1 ;;
    esac

    printf '%s' 'flushed' | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=resume: writing INNGEST_CUTOVER_FLIP=flushed FAILED. Re-dispatch op=resume. Do NOT SSH the host."; exit 1; }
    echo "::notice::op=resume: wrote INNGEST_CUTOVER_FLIP=flushed to soleur-inngest/prd. The enabled 30s on-host timer takes the post-flush resume arm: start -> verify it SERVES -> record the done-owner marker -> done, with NO re-FLUSHALL."
    ;;

  luks-cutover|luks-rollback)
    # --- #6894 / ADR-142: the additive blue-green cutover of the Redis AOF store onto the LUKS
    # volume, and its reverse. Both are ONE Doppler write to INNGEST_LUKS_CUTOVER on
    # soleur-inngest/prd; every byte of work happens on-host, in inngest-luks-cutover.service.
    #
    # THE FLAG IS NOT THE FLIP'S. INNGEST_CUTOVER_FLIP owns the one authorized FLUSHALL; this flag
    # owns a copy that PRESERVES data. Sharing them would put a destructive verb and a preserving
    # one behind one value, and the wrong terminal state would authorise the wrong action.
    #
    # Four guards, in this order, every one fail-closed and every one BEFORE the write:
    #   G1 the flag is not in-flight and not already `done`
    #   G2 the durable pointer says whether this host is already cut over — required ABSENT for
    #      luks-cutover and PRESENT for luks-rollback
    #   G3 the host is audible ON THIS UNIT'S OWN TAG, so the write can actually be acted on
    #   G4 the write itself is stdin-fed and stdout-discarded
    # then a Better Stack confirm that the on-host FSM reached the expected terminal flag.
    if [[ -z "${DOPPLER_TOKEN_INNGEST_ARM:-}" ]]; then
      echo "::error::op=$OP: DOPPLER_TOKEN_INNGEST_ARM is empty — the repo secret did not resolve (approve the inngest-cutover environment required-reviewer gate on this dispatch). Refusing before any write."; exit 1
    fi
    LK_CUR=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get INNGEST_LUKS_CUTOVER -p soleur-inngest -c prd --plain 2>/dev/null || echo "__UNSET_OR_UNREADABLE__")
    # An absent name and a failed read are the same CLI outcome, so they are separated by the name
    # list — the same reasoning as _luks_pointer_state. Unset is a legitimate pre-cutover state.
    if [[ "$LK_CUR" == "__UNSET_OR_UNREADABLE__" ]]; then
      LK_NAMES=$(DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets --only-names --json -p soleur-inngest -c prd 2>/dev/null || true)
      if [[ -z "$LK_NAMES" ]]; then
        echo "::error::op=$OP: G1 REFUSING FAIL-CLOSED — soleur-inngest/prd could not be read at all (token or network), so the current FSM state is UNKNOWN. This is NOT a statement about the host. Nothing was written."; exit 1
      fi
      if printf '%s' "$LK_NAMES" | jq -e 'has("INNGEST_LUKS_CUTOVER")' >/dev/null 2>&1; then
        echo "::error::op=$OP: G1 REFUSING FAIL-CLOSED — INNGEST_LUKS_CUTOVER EXISTS but its value could not be read. A swallowed read must never be treated as unset. Nothing was written."; exit 1
      fi
      LK_CUR=""
    fi
    LK_WANT=armed;      LK_EXPECT=done
    [[ "$OP" == "luks-rollback" ]] && { LK_WANT=rollback; LK_EXPECT=rolled-back; }
    if [[ "$OP" == "luks-cutover" ]]; then
      case "$LK_CUR" in
        ''|aborted|rolled-back)
          echo "::notice::op=luks-cutover: G1 — flag is '${LK_CUR:-unset}', a non-terminal-for-this-verb state; arming is permitted." ;;
        done)
          echo "::error::op=luks-cutover: G1 REFUSING — INNGEST_LUKS_CUTOVER is 'done': this host has ALREADY been cut over to the encrypted volume. Re-arming would re-copy the live store over itself. If you meant to go back, dispatch op=luks-rollback."; exit 1 ;;
        *)
          echo "::error::op=luks-cutover: G1 REFUSING — INNGEST_LUKS_CUTOVER is '$LK_CUR', an IN-FLIGHT state. The on-host FSM is mid-cutover (it re-fires every 30s and resumes from its own state); writing 'armed' now would race it. Wait for a terminal flag on the inngest-luks-cutover Better Stack rows, then re-dispatch. Do NOT SSH the host."; exit 1 ;;
      esac
    else
      case "$LK_CUR" in
        done)
          echo "::notice::op=luks-rollback: G1 — flag is 'done', which evidences a COMPLETED cutover; the reverse is permitted." ;;
        rolled-back)
          echo "::error::op=luks-rollback: G1 REFUSING — INNGEST_LUKS_CUTOVER is already 'rolled-back'; this host is on the plaintext volume. Nothing to roll back."; exit 1 ;;
        *)
          echo "::error::op=luks-rollback: G1 REFUSING — INNGEST_LUKS_CUTOVER is '${LK_CUR:-unset}', not 'done'. Only a completed cutover can be reversed: from an in-flight or aborted state the on-host FSM has already restored the plaintext store itself (every refusal resumes the writers before it lands). Read the reason field on the inngest-luks-cutover rows. Do NOT SSH the host."; exit 1 ;;
      esac
    fi
    # G2 — the DURABLE pointer. It outlives the host (Doppler), unlike the root-disk marker whose
    # loss on a replace is #7228, so it is the authority on "which volume holds the store".
    LK_PTR="$(_luks_pointer_state)"
    case "$LK_PTR:$OP" in
      unreadable:*)
        echo "::error::op=$OP: G2 REFUSING FAIL-CLOSED — the INNGEST_LUKS_ACTIVE_VOLUME_ID pointer could not be read. Nothing was written."; exit 1 ;;
      present:luks-cutover)
        echo "::error::op=luks-cutover: G2 REFUSING — the durable pointer INNGEST_LUKS_ACTIVE_VOLUME_ID is SET, so this host already serves from the encrypted volume, whatever the flag says. Arming would copy the live encrypted store onto the staging volume and swap again."; exit 1 ;;
      absent:luks-rollback)
        echo "::error::op=luks-rollback: G2 REFUSING — the durable pointer is ABSENT, so no swap is recorded and there is nothing to roll back. (The on-host arm refuses this too; refusing here means the flag is not parked in a state the operator then has to clear.)"; exit 1 ;;
      *)
        echo "::notice::op=$OP: G2 — pointer is $LK_PTR, as this verb requires." ;;
    esac
    # G3 — HOST-AUDIBILITY, on inngest-luks-cutover rows specifically (#7674's ruling, applied to
    # this unit). A write to a host that is not running THIS timer recovers nothing and parks the
    # flag in a state G1 then refuses. Refusing forfeits nothing the write would have achieved.
    LK_LIVE_N="$(_luks_liveness_count)"
    case "$(resume_liveness_decide "$LK_LIVE_N")" in
      audible)
        echo "::notice::op=$OP: G3 — host is audible ($LK_LIVE_N inngest-luks-cutover row(s) from $INNGEST_HOST_NAME within $LUKS_LIVENESS_SINCE), so the on-host FSM can act on this write." ;;
      silent)
        echo "::error::op=$OP: G3 REFUSING — ZERO inngest-luks-cutover rows from host=$INNGEST_HOST host_name=$INNGEST_HOST_NAME within $LUKS_LIVENESS_SINCE, while the read path itself SUCCEEDED. Either the host is dark, or the cutover trio never installed — inngest-bootstrap.sh emits reason=install_missing on that path, and the unit polls every 30s once it is installed, so silence here is a real finding. Refusing BEFORE the write; nothing was changed. Do NOT SSH the host."; exit 1 ;;
      unreadable)
        echo "::error::op=$OP: G3 REFUSING FAIL-CLOSED — the liveness READ PATH failed (this is NOT a statement about the host). Verify BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in prd_terraform, then re-dispatch. Nothing was changed."; exit 1 ;;
      *)
        echo "::error::op=$OP: G3 — resume_liveness_decide returned an unrecognised outcome. Refusing FAIL-CLOSED."; exit 1 ;;
    esac
    # G4 — the write. Captured BEFORE it so the confirm window cannot admit a terminal row from an
    # earlier run of the same FSM. Value on STDIN, never argv (/proc is world-readable), stdout
    # discarded (`doppler secrets set` prints every remaining secret of the config).
    LK_TS=$(date -u +%s)
    printf '%s' "$LK_WANT" | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_LUKS_CUTOVER -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=$OP: writing INNGEST_LUKS_CUTOVER=$LK_WANT FAILED. Nothing on the host has changed — re-dispatch. Do NOT SSH the host."; exit 1; }
    echo "::notice::op=$OP: wrote INNGEST_LUKS_CUTOVER=$LK_WANT to soleur-inngest/prd. The 30s on-host timer picks it up: freeze writers -> copy the whole mount -> prove it byte-identical -> swap -> verify, rolling back automatically if the verification fails."
    LK_ISO=$(date -u -d "@$LK_TS" +'%Y-%m-%d %H:%M:%S')
    LK_STATE=$(confirm_luks_state "$LK_ISO")
    if [[ "$LK_STATE" == "$LK_EXPECT" ]]; then
      echo "::notice::op=$OP: FSM confirmed '$LK_EXPECT' via Better Stack (since $LK_ISO). The store is on $( [[ "$OP" == luks-cutover ]] && echo 'the ENCRYPTED volume' || echo 'the PLAINTEXT volume' ), proven byte-identical before the swap."
    else
      case "$LK_STATE" in
        rolled-back)
          echo "::error::op=luks-cutover: the FSM rolled back. The post-swap verification failed, so the host reverse-copied to the plaintext volume and cleared the pointer — THE STORE IS INTACT and the scheduler is running on it. Read the reason field (t3-failed-rc*) on the inngest-luks-cutover rows before re-dispatching. Do NOT SSH the host."; exit 1 ;;
        aborted)
          echo "::error::op=$OP: the FSM aborted. Every refusal resumes the writers before it lands, so the scheduler is running on the store it was on before this dispatch. The reason field on the inngest-luks-cutover rows names which guard refused (t1-unreadable, t2-*, mount-not-quiesced, staging-*, pointer-*, luks-key-absent). Fix that condition and re-dispatch; the flag is terminal, so nothing re-fires meanwhile. Do NOT SSH the host."; exit 1 ;;
        *)
          echo "::error::op=$OP: no terminal LUKS FSM flag within 900s since $LK_ISO (the write DID land). That is not itself a statement about the store: the confirm path may have failed (a betterstack-query.sh ::warning:: above names that case). The on-host FSM holds a flock and resumes from its own state on the next 30s tick, so do NOT re-dispatch blind — read the inngest-luks-cutover rows first. Do NOT SSH the host."; exit 1 ;;
      esac
    fi
    ;;

  *)
    echo "::error::unknown op '$OP'"; exit 1
    ;;
esac
