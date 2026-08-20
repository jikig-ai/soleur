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
confirm_flip_state() {
  local since="$1" i rows raw rc
  for i in $(seq 1 40); do   # 40 x 15s = 600s (30s on-host timer + FLUSHALL/assert + journald->Vector->BS latency)
    rows=$(doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since "$since" --grep inngest-cutover-flip --limit 50 2>/dev/null)
    rc=$?
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
  # Pinned on the ROUTING position, not on mere presence (#7462 review). Supabase resolves the
  # tenant from the pooler USERNAME, so the ref must appear in the userinfo as
  # `://postgres.<ref>:` (session pooler — MEASURED against the live prd_terraform value, which
  # carries a password, so the ref is followed by `:` and not by `@`), or in the direct host as
  # `@db.<ref>.`. A bare `*<ref>*` substring would also accept a DSN carrying the ref in a
  # password, dbname or query parameter while host and user point somewhere else entirely —
  # which, as the only guard left, is the whole safety argument.
  case "$pg" in
    *://postgres.pigsfuxruiopinouvjwy:*|*@db.pigsfuxruiopinouvjwy.*) : ;;
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
    CODE=$(curl -s --max-time 30 -o /tmp/enum-body -w '%{http_code}' \
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
    CODE=$(curl -s --max-time 30 -o /tmp/registry-probe-body -w '%{http_code}' \
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
    CODE=$(curl -s --max-time 120 -o /tmp/doublefire-probe-body -w '%{http_code}' \
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
    RUN_COUNT=$(echo "$BODY" | jq '.runs | length')
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
    if [[ "$TOTAL_COUNT" == "unknown" || "$TOTAL_COUNT" == "absent" ]]; then
      echo "::warning::doublefire-probe: the server did not report a usable totalCount (total_count=$TOTAL_COUNT) — the page-1 feasibility gate did not run and the scan's scale is unmeasured."
    fi
    echo "::notice::doublefire-probe: $RUN_COUNT run(s) in window (server total_count=$TOTAL_COUNT, anchor_source=$DF_ANCHOR_SOURCE, from=$DF_FROM); bucketing by (functionID, floor(startedAt / ${CRON_PERIOD}s))"
    DUPES=$(echo "$BODY" | jq -c --argjson period "$CRON_PERIOD" '
      [ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | fromdateiso8601) / $period | floor) } ]
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
    echo "::notice::doublefire-probe SCOPE CAVEAT (P2-a / DI-C3): the doublefire-probe reads ONLY the dedicated host's (10.0.1.40) run history. It is NOT a web-2 double-fire detector — a surviving weight-0 web-2 scheduler fires against prod Postgres via its OWN loopback backend PRE-repoint, whose runs never appear on the dedicated host. The operator's MANDATORY web-2 quiesce (op=execute SEAM, web-2 freeze/recreate) is the control against a web-2 double-fire — this probe cannot substitute for it."
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
    # self-enumerates the post-deploy empty backend (#5542). A 503 means
    # INNGEST_CUTOVER_QUIESCE is still set (clear it first); aborts loud.

    # ---- Precondition (P1-9 / P2-17): the dedicated registry MUST be NON-empty
    # before we re-arm against prod scheduling — a still-empty registry means 2.4
    # (app-repoint → functions re-synced onto 10.0.1.40) has not landed and a
    # re-arm would target a backend with no registered functions. GET the web-host
    # registry probe (HMAC over empty body); require function_count > 0.
    RSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/rearm-probe
    RCODE=$(curl -s --max-time 30 -o /tmp/rearm-probe -w '%{http_code}' \
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
    CODE=$(curl -s --max-time 120 -o /tmp/rearm-body -w '%{http_code}' \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      -d "$PAYLOAD" \
      "$BASE/inngest-rearm-reminders" || echo "000")
    echo "re-arm response:"; cat /tmp/rearm-body 2>/dev/null || true; echo
    if [[ "$CODE" != "200" ]]; then
      echo "::error::re-arm returned HTTP $CODE (a non-200 includes the host script's loud abort, e.g. quiesce still set)"; exit 1
    fi
    # ---- Partial-rearm reconciliation (P1-11): the host script's CombinedOutput
    # carries `inngest-rearm-reminders: re-armed=N failed=M total=K`. Surface the
    # Σcaptured(=total) vs rearmed delta LOUDLY on any shortfall (do NOT silently
    # reconcile) and offer the re-arm retry path. total==rearmed ⇒ full success.
    RBODY=$(cat /tmp/rearm-body 2>/dev/null || echo "")
    REARMED=$(printf '%s' "$RBODY" | sed -n 's/.*re-armed=\([0-9]\+\).*/\1/p' | tail -n1)
    RTOTAL=$(printf '%s' "$RBODY" | sed -n 's/.*total=\([0-9]\+\).*/\1/p' | tail -n1)
    # P2-b: a NON-EMPTY body that lacks the `re-armed=N ... total=K` pattern must NOT
    # default both counts to 0 and read as a false 0==0 success (silent undercount).
    # Assert BOTH counts parsed from the real (200) response; fail LOUD otherwise.
    if [[ -z "$REARMED" || -z "$RTOTAL" ]]; then
      CAUSE="${RBODY//[$'\n\r']/ }"
      echo "::error::re-arm reconciliation FAILED (P2-b): could not parse 're-armed=N ... total=K' from the host response (rearmed='${REARMED:-<unparsed>}' total='${RTOTAL:-<unparsed>}'). The re-arm returned HTTP 200 but its reconciliation counts are unreadable — refusing to report a false 0==0 success on an unparsed body. Response: ${CAUSE:-<empty body>}. Do NOT proceed to op=verify; re-run op=rearm (the on-host capture is retained on any failure)."
      exit 1
    fi
    if [[ "$REARMED" != "$RTOTAL" ]]; then
      # Missing reminder_ids the host script named on each failure (ids only, no bodies).
      MISSING=$(printf '%s' "$RBODY" | sed -n 's/.*re-arm failed for reminder_id=\([^ )]*\).*/\1/p' | paste -sd, -)
      echo "::error::re-arm PARTIAL (P1-11): Σcaptured(total)=$RTOTAL != rearmed=$REARMED — $((RTOTAL - REARMED)) reminder(s) NOT re-armed. Missing reminder_id(s): [${MISSING:-<unparsed; see body above>}]. RETRY: the on-host capture is retained on any failure, so re-dispatch op=rearm to finish the residual set (the route recomputes dedup ids — no double-fire). Do NOT proceed to op=verify until Σcaptured==rearmed."
      exit 1
    fi
    echo "::notice::re-arm completed: rearmed=$REARMED == Σcaptured=$RTOTAL (no partial-rearm delta, P1-11)"
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
    CODE=$(curl -s --max-time 60 -o /tmp/capture-body -w '%{http_code}' \
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
    echo "::notice::capture: persisted $N reminder(s) to $FILE for post-deploy re-arm — [$IDS]"
    ;;

  verify-wiped-volume)
    # Async (202) destructive op → poll the dedicated verify-status GET
    # for a fresh terminal exit_code. The stop+wipe+restart+settle exceeds
    # the CF 120s edge timeout, so it MUST be async + poll (not synchronous).
    PAYLOAD='{}'
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    CODE=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' \
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
      curl -s --max-time 10 -o /tmp/verify-body -w '%{http_code}' \
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
    CODE=$(curl -s --max-time 30 -o /tmp/backup-body -w '%{http_code}' \
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
      curl -s --max-time 15 -o /tmp/backup-action \
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
      CODE=$(curl -s --max-time 30 -o /tmp/inv-body -w '%{http_code}' \
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
    POOL_RESP="$(curl --silent --show-error \
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
    CODE=$(curl -s --max-time 30 -o /tmp/exec-probe -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-registry-probe" || echo "000")
    BODY=$(cat /tmp/exec-probe 2>/dev/null || echo "")
    if [[ "$CODE" != "200" ]]; then
      CAUSE="${BODY//[$'\n\r']/ }"
      echo "::error::2.0 registry-probe returned HTTP $CODE: ${CAUSE:-<empty body>}"; exit 1
    fi
    if ! echo "$BODY" | jq -e 'type == "object" and has("registry_empty")' >/dev/null 2>&1; then
      echo "::error::2.0 registry-probe did not return a {registry_empty,...} object"; echo "$BODY"; exit 1
    fi
    REG_EMPTY=$(echo "$BODY" | jq -r '.registry_empty')
    REG_COUNT=$(echo "$BODY" | jq -r '.function_count // 0')
    if [[ "$REG_EMPTY" != "true" ]]; then
      echo "::error::2.0 ABORT — dark registry is NON-empty (function_count=$REG_COUNT). The cutover flip must only run against an EMPTY dark registry or a second scheduler double-fires against prod Postgres."
      echo "::error::Remediation (P1-6): (1) read INNGEST_POSTGRES_URI on soleur-inngest/prd and record which backend it targets — do NOT assume it is non-prod: a successful op=arm writes the PROD DSN there and op=rollback has no inverse for that write, so since the first arm (2026-07-23) it holds the prod value as its documented steady state (ADR-100 addendum 2026-08-20); (2) stop the dark inngest-server so nothing re-syncs functions; (3) clear the registry this host serves (drop the stray functions); (4) re-run op=execute. Do NOT proceed to the flip."
      exit 1
    fi
    echo "::notice::2.0 registry-probe: dark registry EMPTY (function_count=$REG_COUNT) — pre-flight clear"

    # ---- 2.1 capture (HONESTY-SCOPED, DI-C3, tracked #6227). This
    # is a SINGLE LB-routed POST to the inngest-rearm-reminders hook — it captures
    # ONLY the LB-reachable host's local Redis. There is NO per-host fan-out today
    # (no firewall rule for web→web:8288 + no host-targeting capture hook — that
    # infra is DEFERRED, see the tracking issue), so the weight-0 warm-standby web-2
    # (10.0.1.11), which self-arms oneshots into its OWN Redis independent of LB
    # weight, is NOT captured here. web-2's reminders are covered by the OPERATOR
    # web-2 freeze/recreate step in the SEAM below — NOT by this capture. The host
    # script persists the still-armed records on-host; only counts + reminder_ids
    # surface here (P2-sec-a / AC-NOBODY). Σcaptured feeds the D.4 rearm reconciliation.
    PAYLOAD='{"mode":"capture"}'
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/exec-capture
    CODE=$(curl -s --max-time 60 -o /tmp/exec-capture -w '%{http_code}' \
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
    echo "::notice::2.1 capture: Σcaptured=$SIGMA_CAPTURED across host-set [$CUTOVER_HOSTS] (records on-host; reminder_ids-only surfaced)"

    # ---- 2.2 QUIESCE HARD GATE (P1-7) — HONESTY-SCOPED (DI-C3, tracked
    # #6227). The old web-host scheduler MUST be provably down BEFORE
    # the SEAM is printed — arming the flip while an old scheduler survives creates a
    # second live scheduler on prod Postgres (the double-fire).
    #   LIMITATION (DI-C3): this gate reads inngest state via the inngest-inventory
    # web-host hook, which resolves over the LOAD BALANCER to 127.0.0.1:8288 on
    # WHICHEVER host the LB routed the webhook to. There is NO host-targeting
    # mechanism today (no firewall rule for web→web:8288 + no host-targeting
    # inventory hook — that per-host fan-out infra is DEFERRED; see the tracking
    # issue). So this gate can only POSITIVELY confirm the LB-REACHABLE host(s); it
    # CANNOT individually probe the weight-0 warm-standby web-2 (10.0.1.11), which
    # self-arms oneshots into its OWN Redis independent of LB weight. Iterating
    # $CUTOVER_HOSTS here would re-probe the SAME LB-routed host every time and
    # falsely imply per-host coverage, so we DO NOT loop the host-set and we DO NOT
    # claim "zero inngest across all $CUTOVER_HOSTS". web-2 quiesce is a MANDATORY
    # OPERATOR step (the SEAM below, via the plan's web-2 freeze/recreate lifecycle)
    # — NOT auto-verified here.
    # Classification of the LB-reachable probe (fail-CLOSED), re-probed
    # CUTOVER_QUIESCE_PROBES (default 3) times so a TRANSIENT non-200 from a surviving
    # scheduler cannot slip through as "quiesced":
    #   * HTTP 200 (any probe)             → inngest SERVING the GQL → STILL RUNNING → block.
    #   * a STABLE real webhook non-200    → the inventory hook ran and reported inngest
    #     across every probe (no 200)        DOWN (inngest-inventory.sh exits 1 → non-200
    #                                        when the GQL is unreachable) → quiesced.
    #   * transport failure / unreadable   → UNKNOWN → FAIL-CLOSED: we cannot PROVE it is
    #     (000) only                          quiesced, so we do NOT arm.
    # STILL_RUNNING **and** UNKNOWN both withhold the SEAM + exit non-zero. On the
    # DEDICATED host the inngest-server ExecStartPre flip-guard (P1-5) additionally
    # blocks a second prod scheduler on a dedicated-host restart — but it does NOT stop
    # a surviving WEB-host scheduler, so this gate + the no-SSH op=quiesce-web
    # stop+disable + the operator web-2 freeze/recreate are what cover the web hosts.
    GSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    QUIESCE_PROBES="${CUTOVER_QUIESCE_PROBES:-3}"
    STILL_RUNNING=0
    UNKNOWN_COUNT=0
    serving=false
    reached_non200=false
    for _probe in $(seq 1 "$QUIESCE_PROBES"); do
      rm -f /tmp/exec-inv
      ICODE=$(curl -s --max-time 30 -o /tmp/exec-inv -w '%{http_code}' \
        -X GET \
        -H "X-Signature-256: sha256=$GSIG" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "$BASE/inngest-inventory" || echo "000")
      if [[ "$ICODE" == "200" ]]; then
        serving=true; break
      elif [[ "$ICODE" =~ ^[1-5][0-9][0-9]$ ]]; then
        # A real HTTP answer that is not 200 → the inventory hook ran and reported
        # inngest not serving (down) on the LB-reachable host.
        reached_non200=true
      fi
      # ICODE=000 (transport failure / unreadable) leaves both flags false here.
    done
    if [[ "$serving" == true ]]; then
      STILL_RUNNING=1
      echo "quiesce check (LB-reachable host): inngest STILL RUNNING (inventory HTTP 200)"
    elif [[ "$reached_non200" == true ]]; then
      echo "quiesce check (LB-reachable host): inngest not serving (stable webhook non-200 across ${QUIESCE_PROBES} probe(s)) — quiesced"
    else
      UNKNOWN_COUNT=1
      echo "quiesce check (LB-reachable host): UNREADABLE (no HTTP answer across ${QUIESCE_PROBES} probe(s)) — UNKNOWN, fail-closed"
    fi
    if [[ "$STILL_RUNNING" -gt 0 || "$UNKNOWN_COUNT" -gt 0 ]]; then
      echo "::error::2.2 QUIESCE HARD GATE FAILED (P1-7): the LB-reachable host is still-running=$STILL_RUNNING / UNKNOWN=$UNKNOWN_COUNT. WITHHOLDING THE SEAM (fail-closed). NO-SSH REMEDIATION: run 'gh workflow run cutover-inngest.yml --field op=quiesce-web' (stop+disables inngest across the host-set over the private net, no SSH), confirm it reports 'quiesced', then re-run op=execute. If UNKNOWN (000) the webhook was unreachable — check CF-Access/HMAC + the run log and re-dispatch. Arming the flip now could create a second live scheduler on prod Postgres. Do NOT SSH the host."
      exit 1
    fi
    echo "::notice::2.2 QUIESCE HARD GATE PASSED: the LB-REACHABLE host(s) POSITIVELY confirmed not-serving (fail-closed). SCOPE (DI-C3, tracked #6227): this LB-routed path did NOT individually probe the weight-0 warm-standby web-2 (10.0.1.11). op=quiesce-web (when run) now stop+disables web-2's scheduler too (an ACT), but CI still cannot VERIFY web-2 AND web-2's local reminders were never captured — the MANDATORY web-2 freeze/recreate step in the SEAM below is NOT superseded; do NOT read a green op=quiesce-web as 'web-2 handled'."

    # ---- SEAM: operator maintenance-window steps. As of #6369 the 2.2b/2.3 arm-flip is NO
    # LONGER an out-of-band Doppler write — it is the no-SSH `op=arm` dispatch (a prod-write
    # behind explicit dispatch + the inngest-cutover environment required-reviewer gate, which
    # satisfies hr-menu-option-ack-not-prod-write-auth: the dispatch + approval IS the ack).
    # The remaining true operator seams are 2.2a (web-2 lifecycle) and 2.4 (app-repoint).
    # This block still echoes only step text; no secrets / bodies / connection strings (AC-NOBODY).
    echo "::notice::SEAM — operator maintenance-window steps (2.2a web-2 lifecycle + 2.4 app-repoint are operator; 2.2b/2.3 arm-flip is now the no-SSH op=arm dispatch):"
    echo "  2.2a WEB-2 QUIESCE — MANDATORY, NOT AUTO-VERIFIED (DI-C3, tracked #6227). op=quiesce-web (when run) now stop+disables web-2's SCHEDULER over the private net (an ACT — a real improvement over operator-only web-2 handling), BUT CI still cannot VERIFY web-2 (LB-scoped) AND web-2's local reminders were NEVER captured (2.1 capture is also LB-scoped). The weight-0 warm-standby web-2 (10.0.1.11) self-arms oneshots into its OWN Redis independent of LB weight. So the web-2 freeze/recreate lifecycle REMAINS MANDATORY — do NOT read a green op=quiesce-web as 'web-2 handled'. Before arming the flip you MUST recreate web-2 onto the post-cutover config: take web-2 OUT of the warm-standby rotation and recreate it so no surviving web-2 scheduler self-arms a reminder into its local Redis. RISK IF SKIPPED: a reminder self-armed on an un-quiesced web-2 is silently dropped at cutover (its local Redis is never captured/re-armed). This is a lifecycle action (freeze → recreate), NOT a host shell step (AC-NOSSH). Do NOT proceed to arm the flip until web-2 is recreated. Tracks #6227 (real per-host fan-out to auto-verify web-2)."
    echo "  2.2b+2.3 ARM THE FLIP — NO LONGER a manual Doppler write. Dispatch the no-SSH op=arm verb: it writes the 3 values on soleur-inngest/prd (INNGEST_POSTGRES_URI + INNGEST_HEARTBEAT_URL read-through from prd_terraform, then INNGEST_CUTOVER_FLIP=armed LAST — the enabled 30s poll timer picks it up), then CONFIRMS the on-host FSM reached done (exit_code:0) via Better Stack. No secret is echoed (AC-NOBODY; #6369). Run: gh workflow run cutover-inngest.yml --field op=arm  (then APPROVE the inngest-cutover environment required-reviewer gate — that approval IS the prod-write ack)."
    echo "  2.4 APP-REPOINT — merge the ci-deploy.sh INNGEST_BASE_URL → http://10.0.1.40:8288 change (canary + prod sites) and redeploy so functions re-sync onto the dedicated host."
    echo "  THEN: op=rearm (re-arm the Σ=$SIGMA_CAPTURED captured reminders; gated on registry-non-empty) → op=verify (exactly-once)."
    echo "  ROLLBACK / aborted-recovery (P0-1/P0-3/P1-13): (1) dispatch op=rollback — it now writes INNGEST_CUTOVER_FLIP=rollback on soleur-inngest/prd NO-SSH (via the inngest-cutover environment token, value on stdin), confirms rolled-back via Better Stack, THEN runs the SINGLE no-SSH 'enable inngest _ _' fan-out that re-enables (restores the [Install] symlink the 2.2 disable removed) AND starts the web scheduler across [$CUTOVER_HOSTS] in one flock-held handler, polling deploy-status for the 'enabled' verdict; (2) revert the ci-deploy.sh INNGEST_BASE_URL repoint back to loopback + redeploy. No operator Doppler write or systemctl step is needed (op=arm/op=rollback/op=quiesce-web are the no-SSH arm/reverse/quiesce verbs)."
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
        echo "::error::op=arm: G3 — could not read the current dark INNGEST_POSTGRES_URI from soleur-inngest/prd (empty despite a readable config). G1 already proved the config readable, so an empty read here is anomalous — most plausibly a token-scope or wrong-project fault. Refusing FAIL-CLOSED (no value echoed). Do NOT SSH the host."; exit 1 ;;
      refuse-txn-pooler)
        echo "::error::op=arm: G3 — INNGEST_POSTGRES_URI uses the :6543 transaction pooler; inngest sqlc requires the :5432 session pooler (inngest-host.tf:157). Refusing (no value echoed)."; exit 1 ;;
      refuse-not-session-pooler)
        echo "::error::op=arm: G3 — INNGEST_POSTGRES_URI does not contain the :5432 session-pooler port. Refusing (no value echoed)."; exit 1 ;;
      refuse-not-prod-project)
        echo "::error::op=arm: G3 — INNGEST_POSTGRES_URI does not target the TF-known prod inngest Postgres project (ref pigsfuxruiopinouvjwy). Refusing (no value echoed)."; exit 1 ;;
      skip-already-current)
        # NOT a refusal (#7462), and NOT a skipped write — the token is INFORMATIONAL only.
        # The value is already in place: the expected steady state after any previous
        # successful arm, because op=rollback has no inverse for the G4 DSN write. G4 below
        # still writes it unconditionally (see the comment there for why branching on this
        # outcome was removed). The arm proceeds.
        #
        # POST-FLUSH RE-ARM: if a FLUSHALL has already been performed for this host, the
        # on-host monotonic latch (/mnt/data, #7228 P0-5) will refuse the re-arm and drive
        # INNGEST_CUTOVER_FLIP to terminal `aborted` — this job will still report success,
        # and the refusal surfaces only on the host's Better Stack channel. The correct
        # re-entry for that case is INNGEST_CUTOVER_FLIP=flushed, not another arm
        # (inngest-server-flip-guard.sh:161).
        echo "::notice::op=arm: G3 — INNGEST_POSTGRES_URI on soleur-inngest/prd already equals the prod value (expected after any prior arm; op=rollback has no inverse for that write). Proceeding; G4 rewrites it unconditionally. If a FLUSHALL already ran for this host, the on-host latch will refuse this arm into terminal 'aborted' — re-enter with INNGEST_CUTOVER_FLIP=flushed instead." ;;
      write)
        : ;;
      *)
        echo "::error::op=arm: G3 — g3_decide returned an unrecognised outcome. Refusing FAIL-CLOSED (no value echoed)."; exit 1 ;;
    esac
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
        echo "::error::op=arm: G3.5 channel-key parity FAIL-CLOSED — $CK unreadable (app$([[ -n "$APP_CK" ]] && echo =set || echo =empty) host$([[ -n "$HOST_CK" ]] && echo =set || echo =empty)). Cannot prove app<->host channel parity; refusing to arm (no value echoed)."; PARITY_FAIL=1; continue
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
        echo "::error::op=arm: G6 — the on-host FSM reached terminal '$G6_STATE' (NOT done) since $ARM_ISO. The cutover flip FAILED on-host (e.g. DBSIZE!=0 abort / FLUSHALL-failed / unexpected-exit). REMEDIATION: confirm the dark backend + DBSIZE via op=inventory; do NOT proceed to 2.4 (app-repoint). Inspect the inngest-cutover-flip Better Stack line. Do NOT SSH the host."; exit 1 ;;
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
    echo "::notice::quiesce-web: stop+disabling inngest across host-set [$CUTOVER_HOSTS] (${#HOSTS[@]} host(s)) — no-SSH remediation for the 2.2 gate"
    PAYLOAD=$(printf '{"command":"quiesce inngest _ _","peers":"%s"}' "$CUTOVER_HOSTS")
    SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/quiesce-body
    CODE=$(curl -s --max-time 60 -o /tmp/quiesce-body -w '%{http_code}' \
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
    # POLL /hooks/deploy-status for the LB-reachable host's terminal inngest verdict.
    # The host writes `quiesced` only AFTER its own verify_inngest_quiesced passes
    # (not-serving AND unit-inactive AND not-enabled), so reason==quiesced/exit_code==0
    # is the authoritative synchronous not-serving proof — STRONGER than the LB-routed
    # inventory read. FRESH_FLOOR anchors on this trigger so a stale prior green isn't
    # read (deploy-state is a single slot).
    TRIGGER_TS=$(date +%s)
    FRESH_FLOOR=$((TRIGGER_TS - 60))
    GSIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    # Poll window ≥ host quiesce worst case (verify attempts × (interval+5) +
    # TimeoutStopSec 180 + margin) — drift-guarded by ci-deploy.test.sh (#6178). The
    # distinct QMAX_POLLS/QPOLL_INTERVAL names keep that grep unambiguous. 120×5=600s.
    QMAX_POLLS=120
    QPOLL_INTERVAL=5
    QUIESCED=0
    for i in $(seq 1 "$QMAX_POLLS"); do
      rm -f /tmp/quiesce-status
      curl -s --max-time 10 -o /tmp/quiesce-status -w '%{http_code}' \
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
      case "$REASON" in
        quiesced)
          echo "::notice::quiesce-web: host-side QUIESCED confirmed (reason=quiesced exit_code=$EXIT_CODE) — inngest not-serving AND not-enabled on the LB-reachable host"; QUIESCED=1; break ;;
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
      echo "::error::quiesce-web did not reach the terminal 'quiesced' verdict within $((QMAX_POLLS * QPOLL_INTERVAL))s. If the webhook was UNKNOWN/unreachable, re-dispatch; otherwise pull reason= from /hooks/deploy-status + Better Stack (logger -t ci-deploy). Do NOT SSH the host."; exit 1
    fi
    # SECONDARY confirm (LB-scoped, DI-C3): an inventory-non-200 mirrors the 2.2 gate's
    # classification. The deploy-status `quiesced` reason above is the PRIMARY gate
    # (host-side synchronous verify, stronger than the LB-routed inventory read).
    GSIG2=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    rm -f /tmp/quiesce-inv
    ICODE=$(curl -s --max-time 30 -o /tmp/quiesce-inv -w '%{http_code}' \
      -X GET \
      -H "X-Signature-256: sha256=$GSIG2" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
      -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      "$BASE/inngest-inventory" || echo "000")
    if [[ "$ICODE" == "200" ]]; then
      echo "::warning::quiesce-web: SECONDARY inventory read still returns HTTP 200 on the LB-reachable host — the host-side deploy-status reported quiesced but the LB may have routed this read to a still-serving host. Re-run op=execute's 2.2 gate to re-confirm before arming."
    else
      echo "::notice::quiesce-web: SECONDARY inventory confirm HTTP $ICODE (non-200) on the LB-reachable host — consistent with quiesced (DI-C3 LB-scoped)."
    fi
    # DI-C3 / web-2 scope (spec-flow Finding 4): the fan-out ACTs on web-2 but CI
    # cannot VERIFY web-2 (LB-scoped) AND web-2's local reminders were never captured.
    echo "::notice::quiesce-web complete (LB-reachable host verified quiesced via deploy-status). SCOPE (DI-C3): op=quiesce-web now stop+disables web-2's scheduler (an ACT), but CI cannot VERIFY web-2 AND web-2's local reminders were never captured — the operator web-2 freeze/recreate lifecycle (op=execute 2.2a) REMAINS MANDATORY. Do NOT read this green as 'web-2 handled'. Now re-run op=execute."
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
      CODE=$(curl -s --max-time 30 -o /tmp/verify-probe -w '%{http_code}' \
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
      CODE=$(curl -s --max-time 120 -o /tmp/verify-runs -w '%{http_code}' \
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
    RUN_COUNT=$(echo "$BODY" | jq '.runs | length')
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
    echo "::notice::2.6 doublefire-probe: $RUN_COUNT run(s) in window (server total_count=$TOTAL_COUNT); bucketing by (functionID, floor(startedAt / ${CRON_PERIOD}s))"
    # Any (functionID, floor(startedAt/period)) group with >1 run is a double-fire.
    DUPES=$(echo "$BODY" | jq -c --argjson period "$CRON_PERIOD" '
      [ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | fromdateiso8601) / $period | floor) } ]
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
    echo "::notice::2.6 SCOPE CAVEAT (P2-a / DI-C3): the doublefire-probe reads ONLY the dedicated host's (10.0.1.40) run history. It is NOT a web-2 double-fire detector — a surviving weight-0 web-2 scheduler fires against prod Postgres via its OWN loopback backend PRE-repoint, whose runs never appear on the dedicated host. The operator's MANDATORY web-2 quiesce (op=execute SEAM, web-2 freeze/recreate) is the control against a web-2 double-fire — op=verify cannot substitute for it."

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
        '[ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | fromdateiso8601) / $period | floor) } ] | unique')
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
      HB_ID=$(curl -fsS --max-time 20 -H "Authorization: Bearer $BS_API" \
        'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' 2>/dev/null \
        | jq -r '.data[] | select(.attributes.name == "soleur-inngest-consumer-prd") | .id' 2>/dev/null | head -1 || true)
      if [[ -z "$HB_ID" ]]; then
        echo "::warning::op=rollback: could not resolve the 'soleur-inngest-consumer-prd' heartbeat id from the Better Stack API — NOT pausing it. It will alarm ~4min after the dedicated scheduler stops. NOT blocking the web re-enable."
      elif curl -fsS --max-time 20 -X PATCH -H "Authorization: Bearer $BS_API" -H 'Content-Type: application/json' \
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
    CODE=$(curl -s --max-time 60 -o /tmp/rollback-body -w '%{http_code}' \
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
    # POLL /hooks/deploy-status for the LB-reachable host's terminal inngest verdict —
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
      curl -s --max-time 10 -o /tmp/rollback-status -w '%{http_code}' \
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
          echo "::notice::rollback: host-side ENABLED confirmed (reason=enabled exit_code=$EXIT_CODE) — inngest re-enabled + serving on the LB-reachable host"; ENABLED=1; break ;;
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
    # web-2 is ACTed by the fan-out but its verdict is acceptance-only (DI-C3, same
    # honesty as quiesce) — the LB-reachable host is the only one CI positively verified.
    echo "::notice::rollback complete (LB-reachable host verified enabled via deploy-status). SCOPE (DI-C3): web-2 is re-enabled by the fan-out but not individually VERIFIED here — confirm web-2 via its freeze/recreate lifecycle."
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
    #     queue that was never flushed. Read no-SSH via the deploy-status hook, never by SSH.
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
    printf '%s' 'flushed' | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets set INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --no-interactive >/dev/null || { echo "::error::op=resume: writing INNGEST_CUTOVER_FLIP=flushed FAILED. Re-dispatch op=resume. Do NOT SSH the host."; exit 1; }
    echo "::notice::op=resume: wrote INNGEST_CUTOVER_FLIP=flushed to soleur-inngest/prd. The enabled 30s on-host timer takes the post-flush resume arm: start -> verify it SERVES -> record the done-owner marker -> done, with NO re-FLUSHALL."
    ;;

  *)
    echo "::error::unknown op '$OP'"; exit 1
    ;;
esac
