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
# WHAT THIS DOES NOT DO. It does not fix F14. The forgeable predicate
# (`raw LIKE '%SOLEUR_PROBE_CANARY%'`, scoped only by a Vector-injected `host_name` that pins
# the HOST and not the PRODUCER) is still live in `scripts/betterstack-assert-absence.sh` and is
# untouched by this change. The anchoring analysis and the invariant it implies are recorded in
# ADR-192; the fix belongs in that script's SQL WHERE clause, with its consumer.
#
# INVARIANT (ADR-192, I-2): no marker predicate may be satisfiable by a row an attacker can
# influence.

# Guard against double-sourcing. Today the only consumer is scripts/zot-restart-loop-alarm.sh;
# the guard is kept because sourcing is cheap to get wrong and this file defines functions.
[[ -n "${_BS_ABSENCE_LIB_LOADED:-}" ]] && return 0
_BS_ABSENCE_LIB_LOADED=1

# EXPORT, not `: "${LC_ALL:=C}"`. The previous form set a SHELL variable and claimed in its own
# comment to "assert rather than assume" — it did neither: `:=` assigns a default, and a
# non-exported value is invisible to the `grep` child. The only production caller never exports
# LC_ALL, so the pin existed solely in the test suite, i.e. the suite passed under a guarantee
# production did not have.
export LC_ALL=C

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

# Window for the control read. Kept small: the control proves liveness, not history.
: "${BS_CONTROL_WINDOW:=6h}"

# bs_absence_control_satisfied <query-output>
# TRUE when the output carries at least one row.
#
# THIS ASKS "IS THE WAREHOUSE RECEIVING ANYTHING AT ALL", which is the right question for an
# ACCOUNT-WIDE refusal: when every producer's writes are 402'd, no row of any kind lands. It is
# deliberately NOT producer-anchored — anchoring it would change what it measures and misreport
# a live source carrying only other hosts' rows as dark.
#
# An earlier revision shipped a second, producer-anchored `marker` mode for a future consumer.
# It was cut before merge for three reasons, in ascending order of force: it had zero callers;
# it was the DEFAULT, so any new caller silently inherited the mode both live call sites
# override; and it does not fit the consumer it was built for, because
# `betterstack-assert-absence.sh` establishes its control with a `SELECT count()` returning an
# integer — its F14 fix is a change to that query's WHERE clause, not a bash grep over row text.
# Review also defeated the anchor itself: it pinned the marker's OFFSET within a message value
# and nothing about which producer wrote it, so any component logging an untrusted string at
# position 0 satisfied it. The anchoring REASONING is retained in ADR-192; the predicate lands
# with its consumer.
#
# RECORDED RESIDUAL, not papered over: a single row masks darkness, and it need not be forged —
# any residual producer still landing rows reads LIVE. Reader-side hardening (well-formed JSON,
# a dt inside the window, >= 2 distinct host_name values) would raise that bar without closing
# it, so "not fixable from the reader side" would be too strong; rate-capping the unauthenticated
# write path is the actual control and is tracked separately.
bs_absence_control_satisfied() {
  local out="$1"
  [[ -n "${out//[[:space:]]/}" ]]
}

# bs_absence_response_is_answer <query-output>
# ClickHouse can return HTTP 200 with a mid-stream exception; curl reports success. A body that
# carries an error alongside its rows is a PARTIAL answer, and a partial answer is not an answer.
#
# SHAPE, NOT CONTENT — and this distinction is the whole correctness of the function.
# The obvious implementation greps the body for `exception|DB::Err|Code: [0-9]+|syntax error`,
# and that is what `scripts/betterstack-assert-absence.sh` does. It is sound THERE because it
# scans a `SELECT count()` body — `{"n":"0"}` — which structurally cannot contain application
# text. It is WRONG here: this scans `SELECT dt, raw … LIMIT 1`, i.e. the newest row in the
# source, `raw` payload included, and `raw` is arbitrary application log text.
#
# Measured: with the content grep, a newest row of
#   {"dt":"…","raw":"{\"message\":\"TypeError: unhandled exception in handler\"}"}
# classified TRANSPORT_FAIL instead of LIVE — which suppresses the PRODUCER_SILENT and NIC
# SILENT legs to the non-alarming TRANSIENT, and emits a detail naming a probe fault the run
# had measured false. That is the exact AP-021 defect this file exists to remove, reintroduced
# by the removal. The web container is ~75% of this source's volume and logs errors, so the
# newest row hitting one of those words is ordinary, not a tail case.
#
# A ClickHouse mid-stream exception arrives as a BARE line outside the JSONEachRow stream, so
# the discriminator is the line's shape: every legitimate row from this query begins `{"dt":`.
bs_absence_response_is_answer() {
  local out="$1" line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" == '{"dt":'* ]] && continue
    return 1
  done <<<"$out"
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
