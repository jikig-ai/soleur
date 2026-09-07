#!/usr/bin/env bash
# (#7855) Better Stack round-trip: does the warehouse STORE what it acknowledges?
#
# THE QUESTION NO OTHER INSTRUMENT IN THIS REPO ASKS. `scripts/betterstack-ingest-probe.sh`
# establishes that the write endpoint ACKNOWLEDGES a batch; it posts an empty one by design and
# has nothing to read back. Throughout the ~31 hours #7811 was open (2026-09-03 20:55Z -> 2026-09-05 04:02Z,
# measured) it printed a 2xx on every run
# while the warehouse stored nothing at all. An acknowledgement is not storage, and only a
# readback can tell them apart: write a marker, then read it out again.
#
# AP-024 CARVE-OUT, CLAIMED EXPLICITLY RATHER THAN BY SILENCE. The principle is that a
# verification surface does not actuate. This probe actuates — it performs the write it judges.
# That is the whole point: the property under test is a round trip, and no passive read can
# establish it. The carve-out is bounded by the three rules below, which keep the write from
# becoming evidence for anything OTHER than its own retrievability — plus an explicit statement
# of which AP-024 limbs are WAIVED rather than covered.
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
# A THIRD control is NOT host-scoped and Rule 1 does not reach it: `bs_absence_classify` asks
# "does this source carry ANY row in the window". That is what Rule 2 is for.
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
# The write therefore goes to the git-data source (2734275). Both sides of that constraint are
# derived from `scripts/lib/betterstack-sources.sh`, so the refusal MOVES if the capture's
# control source ever moves — it is derived from the invariant, not restated alongside it.
#
# ── RULE 3: THE FIRST SUCCESSFUL RUN PERMANENTLY ALTERS THE BIRTH INTERLOCK'S INSTRUMENT ─────
# Better Stack creates the ClickHouse table lazily on the first STORED row, which is why the
# rung-2 rehearsal reads 500 CLUSTER_DOESNT_EXIST today. So a successful round trip CREATES
# `t520508_soleur_git_data_prd_logs` permanently, moving the capture's target read from rc=22 to
# rc=0-with-zero-rows. That is a durable production effect on the instrument that gates the
# git-data host's birth, and it is one-way. It does not weaken the capture (ANCHOR_SQL excludes
# rows with an empty host_name, so this marker cannot satisfy the anchor), but a reader of the
# two rules above would not otherwise learn that a success rewrites the interlock's instrument.
#
# ── WHICH AP-024 LIMBS ARE WAIVED, NOT COVERED ───────────────────────────────────────────────
# AP-024's remedy is that the write belongs to a separate step, independently credentialed and
# independently shape-graded — separating the write, the blast radius, the credentials and the
# verdict. Rules 1-3 bound the BLAST RADIUS only. This process holds a live ingest write token
# and the ClickHouse read credential at once and publishes its own verdict, so the CREDENTIAL and
# VERDICT limbs are waived, not satisfied. That is defensible here — a round trip is inherently
# one actor, and this verdict's only actuation is a sweeper comment, never a deploy gate — but it
# is a waiver and is recorded as one rather than implied by the two rules above.
#
# ── RETIREMENT: BOUNDED, BUT NOT ZERO ────────────────────────────────────────────────────────
# An earlier revision of this header claimed the probe becomes a "perpetual production writer"
# once the tracker closes. That is FALSE, and it was corrected against `sweep-followthroughs.sh`
# rather than reasoned about. Two independent mechanisms bound it:
#
#   * `closed_precheck` returns 1 — "not re-litigating" — when the issue carries the sweeper's own
#     `### Sweeper run: PASS` block, BEFORE the script runs. A ROUNDTRIP_STORED close is authored
#     by the sweeper, so in the expected exit path the probe never runs again. Not once.
#   * The closed set is `closed:>=$(date -d "${CLOSED_LOOKBACK_DAYS} days ago")`, default 14, and
#     `REOPEN_MAX` is 3.
#
# So the real residual is: if a HUMAN closes the tracker (no sweeper PASS block), the probe keeps
# writing a marker daily for up to 14 days, and can reopen the issue at most 3 times with
# "Better Stack acknowledged a write it did not store". Bounded and small — but not nothing, and
# a reopen carrying a vendor accusation is the wrong artifact to leave to chance.
#
# RETIREMENT CONDITION, stated so it is checkable rather than remembered: once the tracker records
# a measured POST->queryable latency for this source, remove the `soleur:followthrough` directive
# from the tracker body. That un-enrols the probe on every path, including the human-close one;
# the script stays in the tree as the reproduction. The instruction lives in the tracker body
# itself, not only here, because that is where the action has to be taken.
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
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment the sweeper posts).
# NOT layer 3 — an earlier revision said 3, the Vector journald shipper on the Hetzner host. This
# script runs in a GitHub Actions runner under `env -i`; it never touches journald or Vector, so a
# layer-3 citation names a channel this code cannot reach. `hr-observability-layer-citation`.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797, and #7855's own subject).
#
# This script binds an ingest WRITE token and the warehouse read credential in the same process
# — the AP-024 limb this probe waives rather than satisfies — so a `set -x` anywhere above it
# would trace both into whatever collects this job's output. The sweeper publishes probe stdout
# verbatim into a public GitHub issue comment, which is precisely the surface that must never
# receive a token. `case "$-" in *x*)` tests whether tracing is ON rather than enumerating the
# eight ways to turn it on, two of which carry no `-x` token at all.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${GIT_DATA_BETTERSTACK_LOGS_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"

# ── Latency budget ───────────────────────────────────────────────────────────────────────────
# ADR-172 records a MEASURED POST -> queryable latency of 17 s, in its "What was measured before
# writing this (2026-08-06)" table (§2 references it rather than recording it). That row reads
# "Better Stack Logs ingest POST from a workstation" and does NOT name a source id — attributing
# it to 2457081 is an inference from that being the repo's default ingest URL, not something the
# ADR states. Which makes the floor even more borrowed than the next paragraph says.
# The budget is a stated multiple of that floor rather than a round number picked for feeling
# generous, and the multiple is named so a future reader can re-derive it: 20 x 17 s = 340 s.
#
# BELOW THE FLOOR, A NON-OBSERVATION IS NOT A FINDING. If the poll ends before the measured
# latency could plausibly have elapsed, the correct answer is UNKNOWN, never NOT_STORED — that
# is the same "silence is not evidence" error this whole issue is about, one level down.
RT_LATENCY_FLOOR_S=17
# WHY 20, stated rather than implied. The 17 s floor was measured against source 2457081 — a
# `vector`-platform source on `eu-fsn-3` — and this probe writes to 2734275, an `http`-platform
# source on `eu-central-1a` whose table does not yet exist. So the floor is BORROWED, and the
# multiple is doing the work of "we do not know this source's latency". 20x is chosen to be
# comfortably longer than any plausible same-vendor excursion while still fitting inside a sweeper
# run; it is not a measurement, and replacing it with one is this probe's entire purpose. Naming
# that is the point — absorbing an unknown into an unexplained constant is the move #7855 forbids.
RT_MULTIPLE=20
RT_DEADLINE_S="${BETTERSTACK_ROUNDTRIP_DEADLINE_S:-$(( RT_LATENCY_FLOOR_S * RT_MULTIPLE ))}"
RT_POLL_INTERVAL_S="${BETTERSTACK_ROUNDTRIP_POLL_S:-10}"

# Source identities come from the shared declaration so the write-refusal below is DERIVED from
# the capture's control rather than restated alongside it (see that file's header).
# shellcheck source=../../lib/betterstack-sources.sh
source "${REPO_ROOT}/scripts/lib/betterstack-sources.sh"
# shellcheck source=../../lib/betterstack-absence.sh
source "${REPO_ROOT}/scripts/lib/betterstack-absence.sh"

RT_INGEST_URL="${GIT_DATA_BETTERSTACK_INGEST_URL:-$BS_GIT_DATA_INGEST_URL}"
RT_TABLE="$BS_GIT_DATA_TABLE"
RT_TABLE_S3="$BS_GIT_DATA_TABLE_S3"
# The control source, read ONLY — never written. See RULE 2.
RT_CONTROL_TABLE="$BS_CONTROL_TABLE"
RT_CONTROL_TABLE_S3="$BS_CONTROL_TABLE_S3"

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
# A POSITIVE ALLOWLIST, not a URL parser (ADR-199 commitment 2: allowlist the permitted value and
# abort on every other). This probe has exactly ONE legal destination — Rule 1 in the header says
# the write must land on git-data and nowhere else — so there is nothing for a parser to decide.
# The parser this replaced re-implemented the authority extraction from
# `scripts/betterstack-ingest-probe.sh`, which is the right shape THERE (that probe's URL varies
# by source and is env-overridable) and is strictly weaker here: no query/path/userinfo/lookalike
# reasoning can be got wrong if none is performed, and two hand-copied parsers cannot drift apart.
#
# The refusal is stated in terms of the control source's identity, so it MOVES if the capture's
# control moves — the whole reason `scripts/lib/betterstack-sources.sh` exists.
if [[ "$RT_INGEST_URL" != "$BS_GIT_DATA_INGEST_URL" ]]; then
  _rt_why="it is not the git-data source (${BS_GIT_DATA_INGEST_URL})"
  case "$RT_INGEST_URL" in
    *"${BS_CONTROL_INGEST_HOST}"*)
      # Named explicitly because this one is not merely wrong, it is the hazard: the rung-2
      # capture reads this source's any-row liveness as its CONTROL, so a marker here would
      # manufacture the answer that capture consults it for — at the gate authorising a
      # production host's birth. ADR-192 I-2.
      _rt_why="it is the SHARED CONTROL source ${BS_CONTROL_SOURCE_ID}, whose any-row liveness the rung-2 capture reads as its control; a marker here would manufacture the liveness it consults"
      ;;
  esac
  emit "ROUNDTRIP_UNKNOWN" "refusing to forward the credential: ${_rt_why}"
  exit 3
fi

# The destination is now known to be exactly the git-data URL, so the host is derivable rather
# than parsed. Assigned explicitly because the emit() sites below interpolate it and this script
# runs under `set -u`.
_rt_host="${RT_INGEST_URL#https://}"
_rt_host="${_rt_host%%/*}"

# ── THE BUDGET IS CHECKED BEFORE THE WRITE, NOT AFTER ────────────────────────────────────────
# `RT_DEADLINE_S` is static — nothing below changes it — so a run configured to wait less than the
# measured latency is known to be unjudgeable HERE, before a credential is forwarded, before a
# marker is written into a production log source, and before the poll burns its budget. Checking
# it after the poll (where it used to live) spends the AP-024 actuation on a run that had already
# decided it could conclude nothing.
if [[ "$RT_DEADLINE_S" -lt "$RT_LATENCY_FLOOR_S" ]]; then
  emit "ROUNDTRIP_UNKNOWN" "the poll budget (${RT_DEADLINE_S}s) is below the ${RT_LATENCY_FLOOR_S}s latency floor measured in ADR-172, so this run could not observe a stored row however long it took; no write attempted"
  exit 3
fi

# ── The marker ───────────────────────────────────────────────────────────────────────────────
# Unique per run so a stale row from a previous sweep cannot satisfy this one -- a readback that
# matched any historical marker would report STORED forever after the first success.
RT_MARKER="SOLEUR_BS_ROUNDTRIP_7855_$(date -u +%Y%m%dT%H%M%SZ)_$$"

# NO host_name KEY. See RULE 1 -- this is the field the suite asserts on. `dt` is assigned by the
# vendor at ingest; `message` is the field betterstack-query.sh's readback anchors on.
RT_PAYLOAD="$(printf '[{"message":"%s","source":"betterstack-roundtrip-latency-7855"}]' "$RT_MARKER")"

_t0="$(date -u +%s)"
rc=0
http="$(curl --disable --noproxy '*' -sS -m 20 --proto '=https' -o /dev/null -w '%{http_code}' \
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
# this source is `http`-platform and its schema is INFERRED, not verified. A column mismatch
# surfaces as a transport error, and the `_read_ever_answered` gate below turns "the read never
# worked" into ROUNDTRIP_UNKNOWN rather than into a storage verdict. That gate is what makes the
# previous sentence true; before it existed the same condition produced ROUNDTRIP_NOT_STORED.
rt_read() {
  local sql
  # HOT WINDOW ONLY, no archive arm. A marker written seconds ago cannot have reached the
  # archive, so `s3Cluster` adds nothing to what this query can find — and it can take the whole
  # query away: measured 2026-09-04, `s3Cluster(primary, t520508_soleur_git_data_prd_s3)` answers
  # 669 NAMED_COLLECTION_DOESNT_EXIST for this source, and a UNION ALL fails if EITHER arm fails.
  # With the archive arm present the readback errored on every poll whether or not the row was
  # stored, which is the readback equivalent of the defect this whole issue is about.
  #
  # `_` IS A SINGLE-CHARACTER WILDCARD IN SQL LIKE, and the marker is full of them, so this
  # prefilter is looser than it reads. That is deliberate and safe: the DECISION is the jq field
  # anchor below, which is a literal `startswith`. Do not delete the jq leg on the grounds that
  # the SQL already anchors the marker — it does not.
  sql="SELECT dt, ingest_time, raw
       FROM remote(\$BS_TABLE)
       WHERE raw LIKE '%${RT_MARKER}%'
       ORDER BY dt DESC LIMIT 5 FORMAT JSONEachRow"
  BS_TABLE="$RT_TABLE" BS_TABLE_S3="$RT_TABLE_S3" bash "$QUERY" "$sql" 2>&1
}

_observed=""
_read_rc=0
# DID THE TARGET READ EVER ANSWER? Without this, a readback that failed on EVERY poll is
# indistinguishable from one that answered and found nothing — and the code below would then
# consult the CONTROL source (a different, healthy table), find it LIVE, and emit
# ROUNDTRIP_NOT_STORED: a public vendor data-loss accusation derived from a query that never
# ran. That is the AP-021 defect this issue exists to remove, reintroduced in its own fix.
_read_ever_answered=0
_undecodable_rows=0
_last_read_err=""
while :; do
  _elapsed=$(( $(date -u +%s) - _t0 ))
  [[ "$_elapsed" -ge "$RT_DEADLINE_S" ]] && break
  sleep "$RT_POLL_INTERVAL_S"
  _out="$(rt_read)"; _read_rc=$?
  #
  # rc 0 IS NOT AN ANSWER, AND THAT IS THE SAME DOOR P1-B CAME THROUGH (#7855, found at ship).
  # The paragraph above is right about WHY this gate exists and was wrong about WHAT it measures:
  # it keyed on the transport rc alone, and `betterstack-query.sh` runs curl `--fail-with-body`,
  # which returns 0 for an HTTP 200 carrying a ClickHouse mid-stream exception. Measured: a
  # readback answering `Code: 241. DB::Exception: ...` with rc 0 set `_read_ever_answered=1`, the
  # marker was of course not found in it, the CONTROL source (a different, healthy table) then
  # answered LIVE, and this script emitted ROUNDTRIP_NOT_STORED — exit 1, a public vendor
  # data-loss accusation off a query that never ran. That is the defect the archive-arm fix
  # removed, reached through the other door. The control leg below already applied this lesson
  # via `bs_absence_classify`; the readback one screen up did not.
  if ! bs_absence_response_is_answer "$_out"; then
    _last_read_err="$(printf '%s\n' "$_out" | tail -3 | tr '\n' ' ')"
    _read_rc="${_read_rc}(http-200-carrying-an-error)"
    continue
  fi
  if [[ "$_read_rc" -ne 0 ]]; then
    _last_read_err="$(printf '%s\n' "$_out" | tail -3 | tr '\n' ' ')"
  fi
  if [[ "$_read_rc" -eq 0 ]]; then
    _read_ever_answered=1
    # ROWS CAME BACK AND *NONE OF THEM DECODED* — narrower than "rows came back", deliberately.
    # A row that decodes cleanly but carries ANOTHER run's marker is a correct non-observation and
    # must still reach NOT_STORED; only a row we cannot decode at all is evidence about the
    # SCHEMA rather than about storage. Recomputed each poll (not OR-ed) so the value describes
    # the last answer, which is the one the verdict is about.
    if [[ -n "${_out//[[:space:]]/}" ]]; then
      if printf '%s\n' "$_out" \
         | jq -e 'select(.raw != null) | .raw | (try fromjson catch empty) | select(.message != null)' \
         >/dev/null 2>&1; then
        _undecodable_rows=0
      else
        _undecodable_rows=1
      fi
    fi
    # FIELD ANCHOR, not a line grep. `raw` is a JSON string containing a JSON document.
    if printf '%s\n' "$_out" \
       | jq -e --arg m "$RT_MARKER" 'select(.raw != null) | .raw | (try fromjson catch empty)
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

# THE INSTRUMENT BEFORE THE VERDICT. If the target read never once answered, this run learned
# nothing about storage — the control source is a DIFFERENT table, so its health says nothing
# about whether our read of THIS table works. Carry the ClickHouse error so the next reader does
# not have to re-derive it (the capture does the same with its anchor tail).
if [[ "$_read_ever_answered" -eq 0 ]]; then
  emit "ROUNDTRIP_UNKNOWN" "the readback never answered in ${_elapsed}s (last transport rc=${_read_rc}: ${_last_read_err:-no output}); with no working read of the target table this run cannot tell a storage failure from a broken query, and must not accuse the vendor of either"
  exit 3
fi

# ROWS CAME BACK FOR THIS MARKER AND THE ANCHOR NEVER DECODED (#7855, found at ship).
#
# The `raw LIKE '%marker%'` prefilter matched, so the row is almost certainly ours — but
# `jq ... .raw | fromjson | .message` never resolved it. The stored schema for this source is
# INFERRED, not verified: `dt`/`raw`/`_row_type`/`ingest_time` were checked against a
# `vector`-platform table and source 2734275 is `http` platform. If `raw` is not a JSON document,
# or the payload sits under a key other than `message`, `_observed` stays empty and every path
# below leads to the control consult — which, with a healthy control, publishes
# ROUNDTRIP_NOT_STORED. That would accuse the vendor of losing a row we had just read back.
#
# A schema we have not verified must degrade to UNKNOWN, exactly like a read that did not answer.
if [[ "$_undecodable_rows" -eq 1 ]]; then
  emit "ROUNDTRIP_UNKNOWN" "the readback returned row(s) matching this run's marker but the message anchor did not decode from \`raw\` in ${_elapsed}s; this source is http-platform and its stored schema is INFERRED, so the likeliest reading is a schema mismatch (raw not a JSON document, or the payload under a key other than 'message') and NOT a storage failure. Refusing to convert an undecoded row into a vendor accusation"
  exit 3
fi

# Not observed, and the readback DID work at least once. The reason decides the verdict, and it is
# the same composed reading the rung-2 capture uses: ask a source that is NOT this one whether the
# warehouse is storing anything.
#
# THIS USES THE SHARED CLASSIFIER, and that is not a style preference. The hand-rolled version
# this replaced tested the control read for EMPTINESS
# (`[[ -z "${_ctl_out//[[:space:]]/}" ]]`), which is `bs_absence_classify` with one leg missing:
# ClickHouse can return HTTP 200 carrying a mid-stream exception, so `curl` reports success and
# the body is NON-EMPTY. That body would have read as "the control has rows", and this script
# would then have emitted ROUNDTRIP_NOT_STORED — exit 1, a vendor data-loss accusation posted to
# the tracker — off a control read that had actually failed. That is precisely the AP-021 defect
# `scripts/lib/betterstack-absence.sh` was extracted to remove, and #7855 exists to remove; the
# library's `bs_absence_response_is_answer` carries the measured case in its own comment.
#
# Reusing it also collapses a duplicated `--since 6h`, which had to stay in sync with
# `BS_CONTROL_WINDOW`'s default by hand, and makes both composed readings in this PR the same
# mechanism — which is what makes the ADR-192 amendment true rather than aspirational.
# (sourced at top level, beside betterstack-sources.sh — the poll loop needs it too.)

_ctl_token="$(
  BS_TABLE="$RT_CONTROL_TABLE" \
  BS_TABLE_S3="$RT_CONTROL_TABLE_S3" \
  BETTERSTACK_QUERY_SCRIPT="$QUERY" \
    bs_absence_classify
)"

case "$_ctl_token" in
  INGEST_DARK)
    emit "ROUNDTRIP_DARK" "the marker was not read back within ${_elapsed}s, and the control source (${RT_CONTROL_TABLE}) is storing nothing either. That is ONE source, shared and multi-tenant, so an empty result there is the account-wide signal #7811 tracks — but this run read one source, not the account, so it is not a finding about THIS source either way"
    exit 2
    ;;
  LIVE)
    emit "ROUNDTRIP_NOT_STORED" "the warehouse is demonstrably storing other producers' rows, and a marker acknowledged by ${_rt_host} was NOT retrievable after ${_elapsed}s (${RT_MULTIPLE} x a ${RT_LATENCY_FLOOR_S}s floor BORROWED from a different source on a different platform and region — this source has no measured latency, which is what this probe exists to establish). On that budget: Better Stack acknowledged a write it did not store"
    exit 1
    ;;
  *)
    # TRANSPORT_FAIL, or any token a future library revision adds. Fail closed: with no working
    # control this run cannot tell a storage failure from a broken reader, and the expensive
    # mistake here is accusing the vendor of losing data on the strength of an instrument that
    # did not answer.
    emit "ROUNDTRIP_UNKNOWN" "the marker was not read back within ${_elapsed}s AND the control read did not answer (classifier said ${_ctl_token:-<empty>}); with no working control this run cannot tell a storage failure from a broken reader"
    exit 3
    ;;
esac
