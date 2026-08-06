#!/usr/bin/env bash
# zot-inventory-assert-marker.sh — read the `SOLEUR_ZOT_INVENTORY` marker BACK out of Better
# Stack and adjudicate whether this run's sweep is durably recorded (#7278).
#
# WHY THIS IS A SCRIPT AND NOT A `run:` BLOCK. The pass condition of the whole lever lives
# here. In workflow YAML no test can reach it, and two of the three rules below are ones a
# YAML-embedded grep gets wrong by construction rather than by accident.
#
# RULE 1 — DECODE BEFORE MATCHING. `betterstack-query.sh` returns JSONEachRow rows whose
# `raw` column is DOUBLE-ENCODED JSON: a JSON document serialised into a JSON string. Every
# quote inside it is backslash-escaped, so a grep for the marker text against the transport's
# stdout matches NOTHING. That failure is silent and self-consistent: the gate reports "not
# observed" forever, which is byte-identical to a genuine absence, so a broken readback and a
# dark ingest channel are the same output. The decode is therefore the first thing that
# happens to every row, and the suite carries a mutation arm that replaces it with a
# pass-through and requires the pass arm to go red.
#
# RULE 2 — AN ABSENCE NEEDS A LIVE POSITIVE CONTROL. Zero matching rows means nothing until
# the channel is known to be carrying rows at all: a revoked credential, an unreachable
# region pin and a genuinely missing marker all return zero. The control here is FREE —
# `SOLEUR_ZOT_DISK` lands on the same Better Stack source every 5 minutes, so the 15-minute
# window holds ~3 of them. Zero control rows is `channel_dark`; it is NEVER reported as
# `marker_absent`, and only a measured absence WITH a live control may be cited as evidence
# that CI egress cannot reach the ingest endpoint.
#
# RULE 3 — BELOW THE MEASURED INGEST FLOOR, A NON-OBSERVATION IS NOT A VERDICT. The
# POST -> queryable latency was measured at 17 seconds on 2026-08-06 (a synthetic
# `SOLEUR_INVENTORY_HALFPROBE` line round-tripped from a workstation; the POST answered 202
# and the row became queryable 17 s later). No such constant existed anywhere in this repo
# before, and five in-repo consumers classify "not present yet" as TRANSIENT rather than as a
# result. The poll budget is stated as a MULTIPLE of that measured floor and printed in the
# verdict line, and a budget below the floor forces `unknown` rather than an absence.
# # MEASURED-BY: knowledge-base/project/specs/feat-one-shot-7278-registry-restart-lever/session-state.md §"Phase 0 — preconditions MEASURED" task 0.8
#
# WINDOW: `--no-archive --since 15m`. The hot window is ~40 minutes, so a seconds-old row is
# always inside it, and betterstack-query.sh errors the WHOLE query if its archive arm errors
# — so including the S3 arm could only ever contribute failure to a read of a fresh row.
#
# OUTCOMES. The exit shape is adopted from scripts/betterstack-assert-absence.sh (3/2/1/0,
# with 0 the only pass and unreachable without a live control). The NAMES are inverted from
# that script because this gate asserts PRESENCE, not absence — reporting a found marker as
# `present` with exit 1 would make the success case look like a finding:
#
#   outcome        condition                                                     exit
#   unknown        the query did not answer, the ingest POST was rejected, or     3
#                  the poll budget was below the measured ingest floor
#   channel_dark   the free positive control returned 0 rows                      2
#   marker_absent  control is live, and no row carries this run_id with           1
#                  enumeration_complete=true
#   observed       a row carries this run_id AND enumeration_complete=true        0
#
# Usage:
#   doppler run -p soleur -c prd_terraform -- \
#     scripts/zot-inventory-assert-marker.sh --run-id "$GITHUB_RUN_ID" \
#       [--ingest-http-code <code>] [--since 15m]
set -uo pipefail

# Locale-pinned: the numeric shape gates below use [[ =~ ]] with [0-9], which under a UTF-8
# locale also matches the FULLWIDTH digits.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${BETTERSTACK_QUERY_SCRIPT:-$SCRIPT_DIR/betterstack-query.sh}"

readonly MARKER="SOLEUR_ZOT_INVENTORY"
readonly CONTROL="SOLEUR_ZOT_DISK"
readonly VERDICT_NAME="SOLEUR_ZOT_INVENTORY_ASSERT"

# The measured POST -> queryable latency. See RULE 3 above for its provenance. It is a
# constant, not a knob: the budget is expressed as a multiple of it so that any future
# re-measurement moves every derived window at once.
readonly MEASURED_INGEST_LATENCY_S=17

RUN_ID=""
INGEST_HTTP_CODE=""
SINCE="15m"
LIMIT=400

usage() {
  cat >&2 <<'EOF'
usage: zot-inventory-assert-marker.sh --run-id <numeric-run-id>
                                      [--ingest-http-code <3-digit code>]
                                      [--since <Nm|Nh>] [--limit <N>]

  --run-id            REQUIRED, NUMERIC. The GitHub run id the marker was emitted under.
                      Numeric is load-bearing: it is half the discriminator that stops a
                      GitHub webhook echo of this plan's own prose from counting as an
                      observation (the other half is the prefix anchor).
  --ingest-http-code  The status the inventory run's ingest POST returned. A non-2xx code is
                      adjudicated BEFORE any polling — a marker the sink refused cannot be
                      read back, and spending the budget on it would report the refusal as a
                      non-observation.
  --since             Read window. Default 15m (hot window only).
EOF
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)           RUN_ID="${2:-}"; shift 2 ;;
    --ingest-http-code) INGEST_HTTP_CODE="${2:-}"; shift 2 ;;
    --since)            SINCE="${2:-}"; shift 2 ;;
    --limit)            LIMIT="${2:-}"; shift 2 ;;
    -h|--help)          usage ;;
    *) echo "zot-inventory-assert-marker: unknown flag: $1" >&2; usage ;;
  esac
done

[[ -n "$RUN_ID" ]] || { echo "zot-inventory-assert-marker: --run-id is required." >&2; usage; }
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || {
  echo "zot-inventory-assert-marker: --run-id '$RUN_ID' is not numeric. The match is anchored on a numeric run id; a non-numeric one cannot discriminate the marker from prose quoting it." >&2
  usage
}
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "zot-inventory-assert-marker: --limit must be an integer." >&2; usage; }

POLL_BUDGET_MULTIPLE="${ZOT_ASSERT_POLL_BUDGET_MULTIPLE:-6}"
[[ "$POLL_BUDGET_MULTIPLE" =~ ^[0-9]+$ ]] || { echo "zot-inventory-assert-marker: ZOT_ASSERT_POLL_BUDGET_MULTIPLE must be an integer." >&2; exit 64; }
POLL_BUDGET_S="${ZOT_ASSERT_POLL_BUDGET_S:-$(( POLL_BUDGET_MULTIPLE * MEASURED_INGEST_LATENCY_S ))}"
[[ "$POLL_BUDGET_S" =~ ^[0-9]+$ ]] || { echo "zot-inventory-assert-marker: ZOT_ASSERT_POLL_BUDGET_S must be an integer." >&2; exit 64; }
POLL_INTERVAL_S="${ZOT_ASSERT_POLL_INTERVAL_S:-15}"
[[ "$POLL_INTERVAL_S" =~ ^[0-9]+$ ]] || { echo "zot-inventory-assert-marker: ZOT_ASSERT_POLL_INTERVAL_S must be an integer." >&2; exit 64; }

STEP="$POLL_INTERVAL_S"
[[ "$STEP" -lt 1 ]] && STEP=1
MAX_POLLS=$(( (POLL_BUDGET_S + STEP - 1) / STEP ))
[[ "$MAX_POLLS" -lt 1 ]] && MAX_POLLS=1

MARKER_ROWS=0
CONTROL_ROWS=0
RUN_ID_ROWS=0
POLLS=0
TRANSPORT_OK=0

verdict() {  # $1 outcome, $2 reason, $3 exit
  printf '%s outcome=%s reason=%s run_id=%s marker_rows=%s run_id_rows=%s control_rows=%s polls=%s since=%s poll_budget_s=%s poll_budget_multiple=%s measured_ingest_latency_s=%s\n' \
    "$VERDICT_NAME" "$1" "$2" "$RUN_ID" "$MARKER_ROWS" "$RUN_ID_ROWS" "$CONTROL_ROWS" \
    "$POLLS" "$SINCE" "$POLL_BUDGET_S" "$POLL_BUDGET_MULTIPLE" "$MEASURED_INGEST_LATENCY_S"
  exit "$3"
}

# ---------------------------------------------------------------------------------
# The ingest status is adjudicated FIRST. A wrong-region POST answers 401; that is a
# measured transport refusal and it is the bucket the "can CI reach the ingest endpoint"
# question attaches to. Attributing it to a non-observation instead would send the next
# reader looking at the query side of a problem that happened on the write side.
# ---------------------------------------------------------------------------------
if [[ -n "$INGEST_HTTP_CODE" ]]; then
  if [[ ! "$INGEST_HTTP_CODE" =~ ^[0-9]{3}$ ]]; then
    echo "zot-inventory-assert-marker: --ingest-http-code '$INGEST_HTTP_CODE' is not a 3-digit status." >&2
    usage
  fi
  if [[ ! "$INGEST_HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    echo "zot-inventory-assert-marker: the inventory run's ingest POST returned http_code=${INGEST_HTTP_CODE} (verdict=ingest_rejected_http_${INGEST_HTTP_CODE}). The sink did not accept the marker, so no readback is attempted." >&2
    verdict unknown "ingest_rejected_http_${INGEST_HTTP_CODE}" 3
  fi
fi

# ---------------------------------------------------------------------------------
# DECODE, then match. Two `fromjson?` stages, one per encoding layer: the transport line is
# JSON whose `.raw` is a STRING, and that string is itself a JSON document with `.message`.
# The `?` on each stage drops a row that does not parse rather than killing the pipeline —
# a mixed source carries rows this gate has no business reading.
# ---------------------------------------------------------------------------------
decode() {
  jq -R -r 'fromjson? | .raw // empty' | jq -R -r 'fromjson? | .message // empty'
}

poll_once() {  # sets MARKER_ROWS / RUN_ID_ROWS / CONTROL_ROWS; returns 0 if the query answered
  local raw rc decoded run_rows
  raw="$(bash "$QUERY" --no-archive --since "$SINCE" --limit "$LIMIT" \
           --grep "$MARKER" --grep "$CONTROL" 2>/dev/null)"
  rc=$?
  if [[ $rc -ne 0 ]]; then return 1; fi

  decoded="$(printf '%s\n' "$raw" | decode)"

  # PREFIX-ANCHORED, and the trailing space after the run id is load-bearing: without it
  # `run_id=1777` would match `run_id=17772222`. Prose that QUOTES the marker cannot satisfy
  # a `^`-anchored match, which is the other half of the E10 discriminator.
  #
  # `grep -c` rather than `grep -q`: under pipefail an early `-q` match closes the pipe, the
  # producer takes SIGPIPE, and the pipeline reports failure on the very input that matched.
  run_rows="$(printf '%s\n' "$decoded" | grep -E "^${MARKER} run_id=${RUN_ID} " || true)"
  RUN_ID_ROWS="$(printf '%s' "$run_rows" | grep -cE '.' || true)"
  MARKER_ROWS="$(printf '%s' "$run_rows" | grep -cE '(^| )enumeration_complete=true( |$)' || true)"
  CONTROL_ROWS="$(printf '%s\n' "$decoded" | grep -cE "^${CONTROL}( |$)" || true)"
  [[ "$RUN_ID_ROWS" =~ ^[0-9]+$ ]] || RUN_ID_ROWS=0
  [[ "$MARKER_ROWS"  =~ ^[0-9]+$ ]] || MARKER_ROWS=0
  [[ "$CONTROL_ROWS" =~ ^[0-9]+$ ]] || CONTROL_ROWS=0
  return 0
}

while [[ "$POLLS" -lt "$MAX_POLLS" ]]; do
  POLLS=$((POLLS + 1))
  # AP-022: errexit is never enabled in this file, so this status read is reachable.
  poll_once
  rc=$?
  if [[ $rc -eq 0 ]]; then
    TRANSPORT_OK=1
    if [[ "$MARKER_ROWS" -ge 1 ]]; then break; fi
  fi
  if [[ "$POLLS" -lt "$MAX_POLLS" && "$POLL_INTERVAL_S" -gt 0 ]]; then sleep "$POLL_INTERVAL_S"; fi
done

if [[ "$MARKER_ROWS" -ge 1 ]]; then
  printf 'the marker for run_id=%s was read back from Better Stack with enumeration_complete=true (marker_rows=%s, control_rows=%s, polls=%s).\n' \
    "$RUN_ID" "$MARKER_ROWS" "$CONTROL_ROWS" "$POLLS"
  verdict observed none 0
fi

if [[ "$TRANSPORT_OK" -eq 0 ]]; then
  echo "zot-inventory-assert-marker: the query did not answer on any of ${POLLS} attempts (verdict=transport_did_not_answer). An unanswered query is not an absence." >&2
  verdict unknown transport_did_not_answer 3
fi

if [[ "$POLL_BUDGET_S" -lt "$MEASURED_INGEST_LATENCY_S" ]]; then
  echo "zot-inventory-assert-marker: the poll budget (${POLL_BUDGET_S}s) is below the measured POST-to-queryable floor of ${MEASURED_INGEST_LATENCY_S}s (verdict=below_measured_ingest_floor). Non-observation inside that window is not a result." >&2
  verdict unknown below_measured_ingest_floor 3
fi

if [[ "$CONTROL_ROWS" -eq 0 ]]; then
  echo "zot-inventory-assert-marker: the free positive control '${CONTROL}' returned ZERO rows over ${SINCE} (verdict=channel_dark). It lands every 5 minutes on this source, so the read path is not carrying rows and an absence result would be unearned. This does not discriminate a revoked query credential from a stopped shipper." >&2
  verdict channel_dark channel_dark 2
fi

if [[ "$RUN_ID_ROWS" -ge 1 ]]; then
  echo "zot-inventory-assert-marker: a marker for run_id=${RUN_ID} was read back, but none carried enumeration_complete=true (verdict=enumeration_incomplete). An incomplete sweep licenses no conclusion about the store; re-dispatch." >&2
  verdict marker_absent enumeration_incomplete 1
fi

echo "zot-inventory-assert-marker: no row carried '${MARKER} run_id=${RUN_ID}' over ${SINCE} while the positive control returned ${CONTROL_ROWS} row(s) (verdict=marker_not_observed). The read path is live, so this is a measured absence of the marker." >&2
verdict marker_absent marker_not_observed 1
