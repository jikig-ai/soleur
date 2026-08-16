#!/usr/bin/env bash
# Follow-through verification for #7556 — did the raised zot HTTP deadlines LAND, and did the
# deadline sub-mode STOP?
#
# WHY TWO SIGNALS AND NOT ONE. The change (#7555, ADR-190) is delivered by a `user_data` ForceNew
# replace, so "the config in the repo says 1800s" proves nothing about the running host. And a
# quiet log proves nothing either, because the failure is INTERMITTENT at roughly 1 in 13 — a
# window with zero failures is the expected outcome ~92% of the time even fully unfixed. So this
# probe requires BOTH:
#
#   (1) DELIVERY  — zot's own boot `configuration settings` line, on the NEWEST boot, reports both
#                   deadlines at the intended nanosecond value. This is zot reporting its own
#                   parsed config, not the repo describing itself.
#   (2) ABSENCE   — over a window long enough to matter, ZERO PatchBlobUpload rows carrying
#                   `i/o timeout`. Any duration counts: a cut at the RAISED deadline is still
#                   a finding, and requiring `latency:1m0s` made this criterion unmatchable.
#
# Neither alone is a pass. (1) without (2) says the config landed and says nothing about effect;
# (2) without (1) is the ~92% coincidence above.
#
# ── SCOPED TO THE DEADLINE SUB-MODE, DELIBERATELY ──────────────────────────────────────────
# zot's `PatchBlobUpload` fails in at least TWO shapes. This probe grades only the `i/o timeout`
# shape — the deadline, at whatever duration it cuts. `unexpected EOF` is a DIFFERENT sub-mode, observed
# during a run that SUCCEEDED, and it is explicitly out of scope for #7555. A PASS here is not
# evidence that EOF is gone, and the verdict text says so rather than leaving a reader to infer
# a broader claim from a green.
#
# ── WHAT THIS PROBE MUST NOT DO ────────────────────────────────────────────────────────────
# It must never report PASS for a state it could not establish. Every unestablished state is
# TRANSIENT (exit 2) with a distinct `reason=`, because this exit code auto-closes a tracker and
# "I could not tell" auto-closing a P1 follow-up is the failure this whole class exists to stop.
# `${VAR:?msg}` is BANNED here: under `set -u` it aborts with a bare bash diagnostic and no
# verdict line, which the sweeper records as an unclassified crash rather than a TRANSIENT.
#
# EXIT CONTRACT (the sweeper reads these numerically):
#   0  PASS       — window >= MIN_WINDOW_DAYS, >= MIN_SAMPLES on the newest boot, BOTH deadlines
#                   at DEADLINE_NS, and zero timed-out PatchBlobUpload rows.
#   1  FAIL       — a deadline is absent/wrong on the newest boot, OR an upload timed out.
#                   Both are real findings about the running host.
#   2  TRANSIENT  — the state could not be established. Never a pass.
#
# Usage: bash scripts/followthroughs/zot-upload-ceiling-7556.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${ZOT_CEILING_QUERY:-${REPO_ROOT}/scripts/betterstack-query.sh}"

# The intended value, in the nanoseconds zot itself reports. Derived from the 1800s setting in
# cloud-init-registry.yml; if that setting changes, this must change with it and the ADR-190
# comment there is the single source for WHY the number is what it is.
DEADLINE_NS="${ZOT_CEILING_DEADLINE_NS:-1800000000000}"
WINDOW="${ZOT_CEILING_WINDOW:-7d}"
MIN_WINDOW_DAYS="${ZOT_CEILING_MIN_DAYS:-7}"
MIN_SAMPLES="${ZOT_CEILING_MIN_SAMPLES:-12}"

verdict() { echo "zot-upload-ceiling[#7556]: $1"; }

[[ -x "$QUERY" ]] || { verdict "TRANSIENT reason=query-not-executable"; echo "TRANSIENT: ${QUERY} is not executable."; exit 2; }
command -v python3 >/dev/null || { verdict "TRANSIENT reason=no-python3"; echo "TRANSIENT: python3 is not on PATH."; exit 2; }

# Window sanity BEFORE spending a query: a caller that shortens the window below the soak floor
# would otherwise get a PASS that means less than the contract advertises.
WIN_DAYS="$(printf '%s' "$WINDOW" | sed -n 's/^\([0-9][0-9]*\)d$/\1/p')"
if [[ -z "$WIN_DAYS" || "$WIN_DAYS" -lt "$MIN_WINDOW_DAYS" ]]; then
  verdict "TRANSIENT reason=window-too-short window=${WINDOW}"
  echo "TRANSIENT: the window must be >= ${MIN_WINDOW_DAYS}d for this verdict to mean anything."
  echo "  At the measured ~1-in-13 base rate, a short quiet window is the EXPECTED outcome even unfixed."
  exit 2
fi

qerr="$(mktemp)"
trap 'rm -f "$qerr"' EXIT INT TERM

# ── DECODE BEFORE MATCHING. The warehouse stores rows DOUBLE-ENCODED, and the producer's
# sanitize() runs `tr -d '"\\'` before shipping. So the bytes a naive grep sees are neither what
# zot emitted nor what this probe was written against. MEASURED against 200 real PatchBlobUpload
# rows: `grep -c 'PatchBlobUpload'` = 25, `grep -c 'i/o timeout'` = 0, and the same rows decoded
# give 21. A probe that greps the raw envelope computes deadline_hits=0 on data where 21 of 25
# uploads are deadline failures — and this exit code AUTO-CLOSES #7556.
#
# The same two-stage decode scripts/followthroughs/zot-log-channel-7440.sh performs. It IS
# duplicated here rather than shared — the Workflow-era `scripts/lib/` extraction is the right
# home once a THIRD caller appears; until then say so plainly instead of claiming a reuse that
# does not exist in the code.
decode() {
  jq -R -r 'fromjson? | .raw // empty' 2>/dev/null \
    | jq -R -r 'fromjson? | .message // empty' 2>/dev/null
}

# A ClickHouse error payload can arrive on a ZERO exit (betterstack-query.sh runs `set -uo
# pipefail` without `-e`). Without this the payload carries no PatchBlobUpload rows and falls
# through to the too-few-samples MEASUREMENT — reporting a sample shortage for a query that never
# ran. Same discriminator as the release workflow's bridge arm.
is_error_payload() {
  grep -qiE 'exception|DB::Err|Code: [0-9]+|syntax error' "$1"
}

# ── Signal 1: DELIVERY. zot's boot `configuration settings` line. ──────────────────────────
raw_cfg="$("$QUERY" --since "$WINDOW" --grep 'configuration settings' --limit 2000 2>"$qerr")"; crc=$?
if (( crc != 0 )); then
  verdict "TRANSIENT reason=query-failed-config query_rc=${crc}"
  echo "TRANSIENT: betterstack-query.sh exited ${crc}: $(head -c 400 "$qerr")"
  [[ "$crc" == "3" ]] && echo "  rc=3 is the credential guard — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY."
  echo "  NOT evidence about the registry host."
  exit 2
fi

CFG_RAW_F="$(mktemp)"; CFG_DEC_F="$(mktemp)"
trap 'rm -f "$qerr" "$CFG_RAW_F" "$CFG_DEC_F"' EXIT INT TERM
printf '%s\n' "$raw_cfg" > "$CFG_RAW_F"
if is_error_payload "$CFG_RAW_F"; then
  verdict "TRANSIENT reason=query-error-payload-config"
  echo "TRANSIENT: the config query returned an ERROR PAYLOAD on a zero exit, not rows."
  echo "  A failed read is not a measurement. NOT a pass."
  exit 2
fi
decode < "$CFG_RAW_F" > "$CFG_DEC_F"
cfg_rows="$(grep -c '[^[:space:]]' < "$CFG_DEC_F" || true)"
if [[ "${cfg_rows:-0}" -eq 0 ]]; then
  verdict "TRANSIENT reason=no-config-line window=${WINDOW}"
  echo "TRANSIENT: no zot 'configuration settings' line in the window. The host may not have been"
  echo "  replaced yet, or the #7440 log channel is not delivering. Either way the DELIVERY half is"
  echo "  unestablished — an empty channel is not evidence the deadlines landed."
  exit 2
fi

# Both deadlines, read off the NEWEST such line. zot reports them as integer nanoseconds under
# the HTTP object, e.g. "ReadTimeout":1800000000000.
# POST-SANITIZE FORM. The producer strips every `"` before shipping, so the shipped text reads
# `ReadTimeout:1800000000000`; a `"ReadTimeout":` pattern can never match and the probe would
# return TRANSIENT reason=deadlines-unparseable forever, accreting a daily comment on #7556 and
# never rendering a verdict.
#
# Both values are taken from the SAME newest line: a genuine Arm-C split across two different
# boot lines would otherwise read as a match — the split-brain this FAIL text claims to catch.
CFG_LINE="$(grep -E 'ReadTimeout:[0-9]+' "$CFG_DEC_F" | tail -1)"
read_ns="$(printf '%s' "$CFG_LINE" | grep -oE 'ReadTimeout:[0-9]+' | head -1 | cut -d: -f2)"
write_ns="$(printf '%s' "$CFG_LINE" | grep -oE 'WriteTimeout:[0-9]+' | head -1 | cut -d: -f2)"

if [[ -z "$read_ns" || -z "$write_ns" ]]; then
  verdict "TRANSIENT reason=deadlines-unparseable read=${read_ns:-<none>} write=${write_ns:-<none>}"
  echo "TRANSIENT: a 'configuration settings' line exists but its ReadTimeout/WriteTimeout could not"
  echo "  be parsed. The line's shape may have changed across a zot bump — re-read it before trusting"
  echo "  any verdict here. NOT a pass and NOT a failure."
  exit 2
fi

if [[ "$read_ns" != "$DEADLINE_NS" || "$write_ns" != "$DEADLINE_NS" ]]; then
  verdict "FAIL reason=deadline-mismatch read_ns=${read_ns} write_ns=${write_ns} expected_ns=${DEADLINE_NS}"
  echo "FAIL: the running host does not carry the intended deadlines."
  echo "  Expected both at ${DEADLINE_NS} ns. If both read 60000000000, this host predates the"
  echo "  #7555 replace and the change has not been delivered — dispatch registry-host-replace."
  echo "  If exactly ONE matches, that is the Arm C split-brain ADR-190 exists to prevent."
  exit 1
fi

# ── Signal 2: ABSENCE of the deadline sub-mode. ────────────────────────────────────────────
raw_log="$("$QUERY" --since "$WINDOW" --grep 'PatchBlobUpload' --limit 5000 2>"$qerr")"; lrc=$?
if (( lrc != 0 )); then
  verdict "TRANSIENT reason=query-failed-log query_rc=${lrc}"
  echo "TRANSIENT: betterstack-query.sh exited ${lrc}: $(head -c 400 "$qerr")"
  echo "  The DELIVERY half passed, but absence was not established. NOT a pass."
  exit 2
fi

# SAMPLE FLOOR. A window with too few rows cannot support an absence claim: zero failures out of
# three uploads is not evidence. Counted over PatchBlobUpload rows of ANY shape — the denominator
# is "did uploads happen at all", not "did they fail".
LOG_RAW_F="$(mktemp)"; LOG_DEC_F="$(mktemp)"
trap 'rm -f "$qerr" "$CFG_RAW_F" "$CFG_DEC_F" "$LOG_RAW_F" "$LOG_DEC_F"' EXIT INT TERM
printf '%s\n' "$raw_log" > "$LOG_RAW_F"
if is_error_payload "$LOG_RAW_F"; then
  verdict "TRANSIENT reason=query-error-payload-log"
  echo "TRANSIENT: the PatchBlobUpload query returned an ERROR PAYLOAD on a zero exit."
  echo "  The DELIVERY half passed, but absence was NOT established. NOT a pass."
  exit 2
fi
decode < "$LOG_RAW_F" > "$LOG_DEC_F"
patch_rows="$(grep -c 'PatchBlobUpload' < "$LOG_DEC_F" || true)"
if [[ "${patch_rows:-0}" -lt "$MIN_SAMPLES" ]]; then
  verdict "TRANSIENT reason=too-few-samples patch_rows=${patch_rows:-0} min=${MIN_SAMPLES} window=${WINDOW}"
  echo "TRANSIENT: only ${patch_rows:-0} PatchBlobUpload rows in ${WINDOW}; need >= ${MIN_SAMPLES} before"
  echo "  an absence means anything. Too little upload traffic to conclude, NOT a clean run."
  exit 2
fi

# ANY `i/o timeout` on a PatchBlobUpload row is a finding. One operand, deliberately.
#
# This comment used to describe a PAIRING with `latency:1m0s` and claim the pattern "does NOT
# generalise to any timeout". Both halves were false once `latency_hits` was deleted: that field
# lives on the paired HTTP-API row and is 0 on PatchBlobUpload rows by construction, so requiring
# it made the probe unable to fire at all. The comment survived the deletion and told a future
# reader the probe cannot see a 1800s cut — the opposite of what this line does, and the opposite
# of what is wanted. A 30m0s cut IS a finding: it means the raised deadline is also too small.
#
# Scope: an upload row that timed out is a real failure whatever the duration, so the narrower
# question ("was it exactly 60 s?") is answered by reading the rows, not by filtering them out.
deadline_hits="$(grep 'PatchBlobUpload' < "$LOG_DEC_F" 2>/dev/null | { grep -c 'i/o timeout' || true; })"

if [[ "${deadline_hits:-0}" -gt 0 ]]; then
  verdict "FAIL reason=deadline-submode-present hits=${deadline_hits} window=${WINDOW}"
  echo "FAIL: ${deadline_hits} PatchBlobUpload row(s) carrying 'i/o timeout' in ${WINDOW}, on a host whose"
  echo "  deadlines DO read ${DEADLINE_NS} ns. The deadline was raised and uploads are still being cut,"
  echo "  so the ceiling is not the (only) constraint — re-open the diagnosis rather than raising the"
  echo "  number again. Read the paired HTTP-API row's Content-Length and latency for the new wall."
  exit 1
fi

# RETENTION MUST COVER THE WINDOW, or the PASS asserts an absence the warehouse cannot support.
# MEASURED 2026-08-14: the archive held ~1.3 days (oldest 08-13 11:43 -> newest 08-14 19:07),
# while this probe requests --since 7d. Reporting "zero in 7d" off 1.3 days of data is a claim
# about six days nobody looked at. Derive the OBSERVED span from the rows themselves.
SPAN_H="$(printf '%s\n' "$raw_log" | jq -R -r 'fromjson? | .dt // empty' 2>/dev/null \
  | sort | awk 'NR==1{f=$0} {l=$0} END{if(f=="")exit; print f"\t"l}' \
  | python3 -c '
import sys,datetime
line=sys.stdin.readline().strip()
if not line: sys.exit(0)
parts=line.split("\t")
if len(parts)!=2: sys.exit(0)
def parse(x):
    for f in ("%Y-%m-%d %H:%M:%S","%Y-%m-%dT%H:%M:%S"):
        try: return datetime.datetime.strptime(x[:19],f)
        except ValueError: pass
    return None
a,b=parse(parts[0]),parse(parts[1])
if a and b: print(int((b-a).total_seconds()//3600))
' 2>/dev/null || true)"
if [[ -n "$SPAN_H" ]] && [[ "$SPAN_H" =~ ^[0-9]+$ ]]; then
  MIN_SPAN_H=$(( MIN_WINDOW_DAYS * 24 ))
  if [[ "$SPAN_H" -lt "$MIN_SPAN_H" ]]; then
    verdict "TRANSIENT reason=retention-shorter-than-window observed_h=${SPAN_H} required_h=${MIN_SPAN_H}"
    echo "TRANSIENT: the rows span only ${SPAN_H}h but this verdict requires ${MIN_SPAN_H}h."
    echo "  Warehouse retention cannot support a ${WINDOW} absence claim. NOT a pass — asserting"
    echo "  'zero in ${WINDOW}' off ${SPAN_H}h of data is a claim about time nobody observed."
    exit 2
  fi
else
  verdict "TRANSIENT reason=span-underivable"
  echo "TRANSIENT: could not derive the observed time span from the returned rows, so the"
  echo "  window this PASS would assert is unknown. NOT a pass."
  exit 2
fi

verdict "PASS deadlines_ns=${DEADLINE_NS} patch_rows=${patch_rows} deadline_hits=0 observed_span_h=${SPAN_H} window=${WINDOW}"
echo "PASS: both zot HTTP deadlines report ${DEADLINE_NS} ns on the running host, and across ${patch_rows}"
echo "  PatchBlobUpload rows in ${WINDOW} there are ZERO carrying 'i/o timeout'."
echo "  SCOPE: this grades the DEADLINE sub-mode only. 'unexpected EOF' is a separate shape, was"
echo "  observed during a SUCCESSFUL run, and is out of scope for #7555 — this PASS is not evidence"
echo "  about it. It is also not a claim that any particular release succeeded."
exit 0
