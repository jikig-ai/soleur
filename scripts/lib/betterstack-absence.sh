#!/usr/bin/env bash
# Shared Better Stack absence/ingest discriminator (#7569).
#
# THE DISTINCTION THIS FILE EXISTS TO MAKE. An empty warehouse query has three causes and they
# are not interchangeable:
#
#   1. the query FAILED          → we learned nothing            → TRANSPORT_FAIL (probe fault)
#   2. the query SUCCEEDED and the warehouse holds no rows at all → INGEST_DARK   (writes refused)
#   3. the query SUCCEEDED and rows are present                   → LIVE
#
# Before #7569, `scripts/zot-restart-loop-alarm.sh` collapsed (1) and (2) into a single
# `[[ "$rc" -ne 0 || -z "$out" ]]` arm and reported TRANSIENT — a non-alarming verdict whose
# message named two causes ("Better Stack unreachable / creds unset") that the run had just
# measured FALSE, since rc was 0. On 2026-08-14 19:06:58Z Better Stack began refusing every
# ingest POST with HTTP 402 {"error": "Quota exceeded"} while the READ path kept answering 200.
# That is state (2) exactly. The alarm reported success every 30 minutes for two days.
#
# Observability layer: 3 (the journald → Better Stack producer path) for what is being measured;
# layer 6 (workflow-run log, ::error::, filed issue) for this classifier's own operator-visible
# signal. `hr-observability-layer-citation`.
#
# WHY THE CONTROL IS PRODUCER-ANCHORED. The predicate this replaces was an unanchored
# `raw LIKE '%SOLEUR_PROBE_CANARY%'` scoped only by `host_name`. `host_name` is Vector-injected
# and not attacker-settable, but it pins the HOST, not the PRODUCER — and the web container runs
# on that host, reachable by an unauthenticated party who can write attacker-chosen text into
# this shared source. The only thing separating an HTTP `Host` header from a forged "the channel
# is alive" was that ClickHouse `LIKE` is byte-case-sensitive while the origin resolver
# lowercases — a call that exists for origin comparison, is not documented as a log-safety
# control, and is tested by nothing.
#
# The anchor adopted here is the one already proven in production: the envelope-prefix form at
# `zot-restart-loop-alarm.sh`'s NIC leg, which survived the live 2026-07-15 incident where three
# GitHub-webhook rows quoting a marker were returned by a substring match. A genuine producer
# emits the marker at the START of the message value; a row that merely CONTAINS the marker
# somewhere inside a field an attacker influences does not match.
#
# INVARIANT (ADR-187, I-1): no marker predicate may be satisfiable by a row an attacker can
# influence.

# Guard against double-sourcing: this file is sourced by both the alarm and the assert script.
[[ -n "${_BS_ABSENCE_LIB_LOADED:-}" ]] && return 0
_BS_ABSENCE_LIB_LOADED=1

# LC_ALL is pinned by callers; assert rather than assume, because a locale-dependent match here
# would make the anchor itself environment-sensitive.
: "${LC_ALL:=C}"

_bs_absence_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolution order for the query script. `BETTERSTACK_QUERY_SCRIPT` is the canonical seam;
# `ZOT_BQ_OVERRIDE` is kept as a deprecated alias so the two pre-existing override paths cannot
# diverge (R13 — otherwise a test can stub one while the other reaches the network).
bs_absence_query_script() {
  if [[ -n "${BETTERSTACK_QUERY_SCRIPT:-}" ]]; then
    printf '%s' "$BETTERSTACK_QUERY_SCRIPT"
  elif [[ -n "${ZOT_BQ_OVERRIDE:-}" ]]; then
    printf '%s' "$ZOT_BQ_OVERRIDE"
  else
    printf '%s' "$_bs_absence_lib_dir/../betterstack-query.sh"
  fi
}

# The marker a live channel must carry. Overridable per-caller, but the ANCHORING is not.
: "${BS_CONTROL_MARKER:=SOLEUR_PROBE_CANARY}"
# Window for the control read. Kept small: the control proves liveness, not history.
: "${BS_CONTROL_WINDOW:=6h}"

# bs_absence_control_satisfied <query-output>
# TRUE only when the output carries a row whose message VALUE BEGINS with the control marker.
#
# Two envelope shapes are legitimate, both measured against production bytes:
#   - direct POST      : raw = {"message":"<MARKER> …"}
#   - Vector journald  : raw = {"PRIORITY":"6",…,"message":"<MARKER> …"}
# In both, the marker is the first token of the message value. A row that merely mentions the
# marker mid-value (`"message":"origin=https://x/<MARKER>"`) is NOT a producer heartbeat.
#
# grep -F against the JSON-escaped bytes, not a regex: `raw` is a JSON string, so the quotes are
# backslash-escaped and a naive pattern would need escaping we would get wrong once.
bs_absence_control_satisfied() {
  local out="$1"
  # Read from a herestring, never `printf | grep -q`: under `set -o pipefail` an early match
  # makes grep close the pipe, the producer takes SIGPIPE (141), and the pipeline reports
  # failure even though the pattern matched.
  grep -qF -- "\\\"message\\\":\\\"${BS_CONTROL_MARKER}" <<<"$out"
}

# bs_absence_response_is_answer <query-output>
# ClickHouse can return HTTP 200 with a mid-stream exception; curl reports success. A body that
# carries an error alongside its rows is a PARTIAL answer, and a partial answer is not an answer.
bs_absence_response_is_answer() {
  local out="$1"
  if grep -qiE 'exception|DB::Err|Code: [0-9]+|syntax error' <<<"$out"; then
    return 1
  fi
  return 0
}

# bs_absence_classify
# Emits exactly one verdict token on stdout: LIVE | INGEST_DARK | TRANSPORT_FAIL
# Returns 0 for LIVE, 4 for INGEST_DARK, 2 for TRANSPORT_FAIL — matching the alarm's exit
# contract so a caller can propagate without re-mapping.
#
# The rc test and the emptiness test are DELIBERATELY SEPARATE branches. Collapsing them with
# `||` is the defect this library was extracted to remove; keep them apart.
bs_absence_classify() {
  local bq out rc=0
  bq="$(bs_absence_query_script)"

  if [[ ! -x "$bq" ]]; then
    printf 'TRANSPORT_FAIL'
    return 2
  fi

  out="$("$bq" --since "$BS_CONTROL_WINDOW" --limit 1 2>/dev/null)" || rc=$?

  # (1) The probe itself failed. We learned nothing about the channel. Never darkness.
  if [[ "$rc" -ne 0 ]]; then
    printf 'TRANSPORT_FAIL'
    return 2
  fi

  # (1b) A 200 that carries an exception is the same epistemic state as (1).
  if ! bs_absence_response_is_answer "$out"; then
    printf 'TRANSPORT_FAIL'
    return 2
  fi

  # (3) The channel is demonstrably carrying producer rows.
  if bs_absence_control_satisfied "$out"; then
    printf 'LIVE'
    return 0
  fi

  # (2) The query answered, and nothing a producer wrote came back. Either every producer on
  # this source stopped at once, or the warehouse is refusing writes. Both are alarming, and
  # neither is a probe fault — which is the whole point of keeping this arm separate.
  printf 'INGEST_DARK'
  return 4
}

# bs_absence_max_dt
# Freshness read: the newest `dt` in the source, independent of any marker. Detects the outage
# with no probe at all (the row clock stops advancing).
#
# The `--max-dt` argv is deliberately distinguishable (R12): the existing alarm stub ladder
# branches on argv substrings, and a freshness read carrying no `--grep` would otherwise land in
# the branch serving the control fixture — every freshness case would silently read the control.
bs_absence_max_dt() {
  local bq out rc=0
  bq="$(bs_absence_query_script)"
  out="$("$bq" --max-dt 2>/dev/null)" || rc=$?
  [[ "$rc" -ne 0 ]] && return 1
  bs_absence_response_is_answer "$out" || return 1
  printf '%s' "$out"
}

# bs_absence_staleness_threshold_secs
# R14: AC4 asserts a staleness threshold is enforced mechanically, so there must be a number to
# enforce against. Derived from the control window rather than a second magic constant — three
# windows of silence is unambiguous while tolerating one missed scrape and one retry.
#
# Never assert equality against a wall-clock quantity (R15); callers bound it (`-le`).
bs_absence_staleness_threshold_secs() {
  local n unit secs
  [[ "$BS_CONTROL_WINDOW" =~ ^([0-9]+)([hmd])$ ]] || { printf '%s' "64800"; return 0; }
  n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
  case "$unit" in
    m) secs=$(( n * 60 )) ;;
    h) secs=$(( n * 3600 )) ;;
    d) secs=$(( n * 86400 )) ;;
  esac
  printf '%s' "$(( secs * 3 ))"
}
