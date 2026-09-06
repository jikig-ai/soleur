#!/usr/bin/env bash
# (#7855) Better Stack round-trip: does the warehouse STORE what it acknowledges?
#
# THE QUESTION NO OTHER INSTRUMENT IN THIS REPO ASKS. `scripts/betterstack-ingest-probe.sh`
# establishes that the write endpoint ACKNOWLEDGES a batch; it posts an empty one by design and
# has nothing to read back. During the 27-hour window of #7811 it printed a 2xx on every run
# while the warehouse stored nothing at all. An acknowledgement is not storage, and only a
# readback can tell them apart: write a marker, then read it out again.
#
# AP-024 CARVE-OUT, CLAIMED EXPLICITLY RATHER THAN BY SILENCE. The principle is that a
# verification surface does not actuate. This probe actuates — it performs the write it judges.
# That is the whole point: the property under test is a round trip, and no passive read can
# establish it. The carve-out is bounded by the two rules below, which keep the write from
# becoming evidence for anything OTHER than its own retrievability.
#
# ── RULE 1: THE MARKER CARRIES NO host_name KEY ──────────────────────────────────────────────
# Two positive controls in this repo are satisfied by the mere PRESENCE of a row, scoped only by
# host_name:
#
#   * scripts/followthroughs/git-data-rung2-evidence-capture.sh — ANCHOR_SQL asks for rows where
#     `host_name != '' AND host_name != '<the rehearsal host>'`. Any host_name at all makes this
#     marker foreign-host liveness for a capture that gates a production host's BIRTH.
#   * scripts/betterstack-assert-absence.sh — scopes both its absence and control reads to an
#     exact `--host`, so a row with no host_name can never be its control either.
#
# A marker with no host_name key satisfies neither. `JSONExtractString(raw,'host_name')` returns
# the empty string for an absent key, which both predicates exclude. This is asserted by the
# suite against the payload's FIELD SET, not against the source id — the field is the property.
#
# ── RULE 2: NEVER WRITE TO THE SHARED SOURCE 2457081 ─────────────────────────────────────────
# Rule 1 is not sufficient, because a third control is NOT host-scoped: `bs_absence_classify`
# (scripts/lib/betterstack-absence.sh) asks "does this source carry ANY row in the window", and
# the rung-2 capture now calls it against 2457081 as its control read. A marker written there
# would answer that question affirmatively forever — so this probe would manufacture the very
# liveness the capture consults it for, and a dark warehouse would read as LIVE. That is the
# ADR-192 blind spot, at the source that gates a host birth.
#
# The write therefore goes to the git-data source (2734275), whose table this probe also
# creates as a side effect — Better Stack creates the ClickHouse table lazily on the first
# STORED row, which is why the rung-2 rehearsal reads 500 CLUSTER_DOESNT_EXIST today.
#
# ── EXIT CONTRACT ────────────────────────────────────────────────────────────────────────────
# The sweeper has THREE actions and this probe has FOUR verdicts, so two verdicts share an
# action and the stdout token is what separates them. Recorded here because the asymmetry is
# invisible from the exit code alone:
#
#   ROUNDTRIP_STORED     exit 0  PASS      -> sweeper CLOSES the tracker
#   ROUNDTRIP_NOT_STORED exit 1  FAIL      -> sweeper comments, tracker STAYS OPEN. This is the
#                                             decider: the warehouse is demonstrably storing
#                                             other producers' rows and did not store ours.
#   ROUNDTRIP_DARK       exit 2  TRANSIENT -> the warehouse is storing nothing from anyone
#                                             (#7811). Not our finding; retry next sweep.
#   ROUNDTRIP_UNKNOWN    exit 3  TRANSIENT -> not established. Missing credential, failed read,
#                                             or a non-observation below the latency floor.
#
# 2 and 3 are both TRANSIENT to the sweeper, which collapses every non-0/1 code identically.
# They are kept distinct because their REMEDIES differ (ADR-199 commitment 3): one waits on a
# vendor incident, the other on provisioning.
#
# Observability layer: 3 (the producer path into Better Stack). `hr-observability-layer-citation`.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"

# ── Latency budget ───────────────────────────────────────────────────────────────────────────
# ADR-172 §2 records a MEASURED POST -> queryable latency of 17 s (2026-08-06, source 2457081).
# The budget is a stated multiple of that floor rather than a round number picked for feeling
# generous, and the multiple is named so a future reader can re-derive it: 20 x 17 s = 340 s.
#
# BELOW THE FLOOR, A NON-OBSERVATION IS NOT A FINDING. If the poll ends before the measured
# latency could plausibly have elapsed, the correct answer is UNKNOWN, never NOT_STORED — that
# is the same "silence is not evidence" error this whole issue is about, one level down.
RT_LATENCY_FLOOR_S=17
RT_MULTIPLE=20
RT_DEADLINE_S="${BETTERSTACK_ROUNDTRIP_DEADLINE_S:-$(( RT_LATENCY_FLOOR_S * RT_MULTIPLE ))}"
RT_POLL_INTERVAL_S="${BETTERSTACK_ROUNDTRIP_POLL_S:-10}"

# The git-data source. Its table is `t<team>_<table_name>_logs` per betterstack-query.sh.
RT_INGEST_URL="${GIT_DATA_BETTERSTACK_INGEST_URL:-https://s2734275.eu-central-1a.betterstackdata.com/}"
RT_TABLE="${BETTERSTACK_ROUNDTRIP_TABLE:-t520508_soleur_git_data_prd_logs}"
RT_TABLE_S3="${BETTERSTACK_ROUNDTRIP_TABLE_S3:-t520508_soleur_git_data_prd_s3}"
# The control source, read ONLY — never written. See RULE 2.
RT_CONTROL_TABLE="${BETTERSTACK_ROUNDTRIP_CONTROL_TABLE:-t520508_soleur_inngest_vector_prd_3_logs}"

emit() { printf 'SOLEUR_BETTERSTACK_ROUNDTRIP verdict=%s detail=%s\n' "$1" "$2"; }

# NOT `: "${VAR:?msg}"`. That word-expansion aborts with status 1, which this contract reads as
# FAIL -- so an unprovisioned secret would report "the warehouse did not store our row" rather
# than "we could not run". `scripts/lint-followthrough-varq-ban.sh` enforces this mechanically.
if [[ -z "${GIT_DATA_BETTERSTACK_LOGS_TOKEN:-}" ]]; then
  emit "ROUNDTRIP_UNKNOWN" "GIT_DATA_BETTERSTACK_LOGS_TOKEN is not set in this environment; no write was attempted and nothing is known about storage"
  exit 3
fi
for _v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!_v:-}" ]]; then
    emit "ROUNDTRIP_UNKNOWN" "${_v} is not set; the readback leg cannot run, so a write would be unverifiable"
    exit 3
  fi
done

# ── RULE 2, ENFORCED IN CODE ─────────────────────────────────────────────────────────────────
# The refusal is on the DESTINATION, evaluated before the credential is forwarded. Matching the
# authority rather than the whole URL, for the same reason betterstack-ingest-probe.sh does: a
# glob's `*` crosses `/` and `?`, so a whole-URL pattern pins nothing (#7855).
_rt_rest="${RT_INGEST_URL#https://}"
if [[ "$_rt_rest" == "$RT_INGEST_URL" ]]; then
  emit "ROUNDTRIP_UNKNOWN" "the ingest URL is not https://; refusing to forward the credential"
  exit 3
fi
_rt_auth="${_rt_rest%%/*}"; _rt_auth="${_rt_auth%%\?*}"; _rt_auth="${_rt_auth%%#*}"
if [[ "$_rt_auth" == *"@"* ]]; then
  emit "ROUNDTRIP_UNKNOWN" "the ingest URL carries userinfo, which puts the real host after an @; refusing to forward the credential"
  exit 3
fi
_rt_host="${_rt_auth%%:*}"
case "$_rt_host" in
  *.betterstackdata.com) : ;;
  *)
    emit "ROUNDTRIP_UNKNOWN" "ingest host '${_rt_host}' is not a betterstackdata.com endpoint; refusing to forward the credential"
    exit 3
    ;;
esac
# The shared source is refused BY NAME. Its liveness is consulted as a control by the rung-2
# capture, so a marker landing there would manufacture the answer that capture reads.
case "$_rt_host" in
  s2457081.*)
    emit "ROUNDTRIP_UNKNOWN" "refusing to write to shared source 2457081: the rung-2 capture reads it as an any-row control, so a marker here would manufacture the liveness it consults"
    exit 3
    ;;
esac

# ── The marker ───────────────────────────────────────────────────────────────────────────────
# Unique per run so a stale row from a previous sweep cannot satisfy this one -- a readback that
# matched any historical marker would report STORED forever after the first success.
RT_MARKER="SOLEUR_BS_ROUNDTRIP_7855_$(date -u +%Y%m%dT%H%M%SZ)_$$"

# NO host_name KEY. See RULE 1 -- this is the field the suite asserts on. `dt` is assigned by the
# vendor at ingest; `message` is the field betterstack-query.sh's readback anchors on.
RT_PAYLOAD="$(printf '[{"message":"%s","source":"betterstack-roundtrip-latency-7855"}]' "$RT_MARKER")"

_t0="$(date -u +%s)"
rc=0
http="$(curl -sS -m 20 --proto '=https' -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${GIT_DATA_BETTERSTACK_LOGS_TOKEN}" \
  -H 'Content-Type: application/json' \
  "$RT_INGEST_URL" \
  --data-raw "$RT_PAYLOAD")" || rc=$?

if [[ "$rc" -ne 0 ]]; then
  emit "ROUNDTRIP_UNKNOWN" "curl exited ${rc} before an HTTP status was observed; no write is known to have been attempted"
  exit 3
fi
case "$http" in
  2*) : ;;
  *)
    # A non-2xx is a refusal, not a storage finding. It is the ingest probe's question, and it
    # is answered there; here it just means the round trip never started.
    emit "ROUNDTRIP_UNKNOWN" "the write endpoint returned http=${http}, so no row was submitted; this is a refusal to investigate via betterstack-ingest-probe.sh, not a storage verdict"
    exit 3
    ;;
esac

# ── The readback ─────────────────────────────────────────────────────────────────────────────
# TWO-STAGE PREDICATE (ADR-192 I-2). The SQL `LIKE` is a cheap prefilter over the double-encoded
# `raw` column; the decision is a FIELD anchor applied after decoding. A substring match on the
# raw line is not a field match -- `raw` is arbitrary application text, so any row that merely
# QUOTED this marker would satisfy a bare LIKE.
#
# `_row_type = 1` on the archive arm and the `dt`/`ingest_time` columns are the measured
# warehouse schema. NOTE: that schema was verified against the `vector`-platform inngest source;
# this source is `http`-platform and its schema is INFERRED, not verified. If the columns differ
# the read fails loudly (a transport error), which degrades to UNKNOWN rather than to a verdict.
rt_read() {
  local sql
  sql="SELECT dt, ingest_time, raw
       FROM (SELECT dt, ingest_time, raw FROM remote(\$BS_TABLE)
             UNION ALL SELECT dt, ingest_time, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
       WHERE raw LIKE '%${RT_MARKER}%'
       ORDER BY dt DESC LIMIT 5 FORMAT JSONEachRow"
  BS_TABLE="$RT_TABLE" BS_TABLE_S3="$RT_TABLE_S3" bash "$QUERY" "$sql" 2>&1
}

_observed=""
_read_rc=0
while :; do
  _elapsed=$(( $(date -u +%s) - _t0 ))
  [[ "$_elapsed" -ge "$RT_DEADLINE_S" ]] && break
  sleep "$RT_POLL_INTERVAL_S"
  _out="$(rt_read)"; _read_rc=$?
  if [[ "$_read_rc" -eq 0 ]]; then
    # FIELD ANCHOR, not a line grep. `raw` is a JSON string containing a JSON document.
    if printf '%s\n' "$_out" \
       | jq -e --arg m "$RT_MARKER" 'select(.raw != null) | .raw | fromjson
                                     | select(.message != null and (.message | startswith($m)))' \
       >/dev/null 2>&1; then
      _observed="$_out"
      break
    fi
  fi
done
_elapsed=$(( $(date -u +%s) - _t0 ))

if [[ -n "$_observed" ]]; then
  # Record BOTH latencies: wall clock (what a caller waits) and the vendor's own
  # ingest_time - dt (what the warehouse did). They answer different questions.
  _lat="$(printf '%s\n' "$_observed" | jq -r 'select(.dt != null and .ingest_time != null)
            | "dt=\(.dt) ingest_time=\(.ingest_time)"' 2>/dev/null | head -1)"
  emit "ROUNDTRIP_STORED" "a marker written to ${_rt_host} was read back out of the warehouse after ${_elapsed}s (budget ${RT_DEADLINE_S}s = ${RT_MULTIPLE} x the ${RT_LATENCY_FLOOR_S}s floor recorded in ADR-172); ${_lat:-vendor timestamps unavailable}"
  exit 0
fi

# Not observed. The reason decides the verdict, and it is the same composed reading the rung-2
# capture uses: ask a source that is NOT this one whether the warehouse is storing anything.
_ctl_rc=0
_ctl_out="$(BS_TABLE="$RT_CONTROL_TABLE" bash "$QUERY" --since 6h --limit 1 2>/dev/null)" || _ctl_rc=$?

if [[ "$_ctl_rc" -ne 0 ]]; then
  emit "ROUNDTRIP_UNKNOWN" "the marker was not read back within ${_elapsed}s AND the control read failed (rc=${_ctl_rc}); with no working control this run cannot tell a storage failure from a broken reader"
  exit 3
fi
if [[ -z "${_ctl_out//[[:space:]]/}" ]]; then
  emit "ROUNDTRIP_DARK" "the marker was not read back within ${_elapsed}s, and the control source is storing nothing either — the warehouse is dark for every producer (#7811), so this is not a finding about this source"
  exit 2
fi
if [[ "$RT_DEADLINE_S" -lt "$RT_LATENCY_FLOOR_S" ]]; then
  # BELOW THE FLOOR, A NON-OBSERVATION IS NOT A FINDING. The comparison is on the BUDGET, not on
  # elapsed time: the budget is the design parameter, and a run configured to wait less than the
  # measured latency could never have observed the row regardless of how long it actually took.
  # Reporting NOT_STORED from such a run would be the same "silence is evidence" error this
  # whole issue exists to remove, one level down.
  emit "ROUNDTRIP_UNKNOWN" "the poll budget (${RT_DEADLINE_S}s) is below the ${RT_LATENCY_FLOOR_S}s latency floor measured in ADR-172, so a non-observation after ${_elapsed}s is not evidence of anything"
  exit 3
fi

emit "ROUNDTRIP_NOT_STORED" "the warehouse is demonstrably storing other producers' rows, and a marker acknowledged by ${_rt_host} was NOT retrievable after ${_elapsed}s (${RT_MULTIPLE} x the ${RT_LATENCY_FLOOR_S}s floor). Better Stack acknowledged a write it did not store"
exit 1
