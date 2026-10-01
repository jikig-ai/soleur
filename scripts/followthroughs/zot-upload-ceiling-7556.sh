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
#   (2) ABSENCE   — over a window long enough to matter, no deadline-shaped upload failure. Any
#                   duration counts as a cut at the RAISED deadline is still a finding.
#
# Neither alone is a pass. (1) without (2) says the config landed and says nothing about effect;
# (2) without (1) is the ~92% coincidence above. (2) is a TRIPWIRE, not a proof: at ~18 pushes a week
# an unfixed pipeline still looks clean about 24% of the time, so DELIVERY is the causal evidence.
#
# ── WHAT THE SAMPLE FLOOR COUNTS (the 2026-10 fix) ────────────────────────────────────────────
# The floor used to be `grep -c PatchBlobUpload`. That string is zot's handler FUNC NAME: it appears
# only on zot ERROR lines (`func:...PatchBlobUpload`) and on the SOLEUR_ZOT_DISK heartbeat's echo of the
# last error, never on a successful upload row. So a week with 44 real PATCH uploads read
# `too-few-samples patch_rows=2` — two heartbeat echoes of one stale EOF error — on every sweep from
# 2026-08-21. The denominator is now the PATCH `/blobs/uploads` HTTP API row itself, pinned to the
# SOLEUR_ZOT_LOG envelope and read in ONE python3 classifier (see CLASSIFIER_PY).
#
# Three further defects sat behind that one and would each have kept the probe from ever passing:
#   * the retention guard demanded `span(rows) >= 168h` over rows fetched with `--since 7d`; every row
#     satisfies dt >= now-7d, so the span is <= 168h with equality only at the endpoints. It is replaced
#     by a COVERAGE ANCHOR: at least one SOLEUR_ZOT_DISK heartbeat (5-minute cadence) inside
#     [window start, window start + 6h], which proves the warehouse reaches the window start;
#   * the real `PatchBlobUpload` error line is NOT in the shipper's cap-exempt classes (is_cap_exempt
#     keys on the zerolog message prefix, the handler name is only in `func:`), so an absence claim made
#     only of error rows is blind. The claim-bearing signal (n2) is the paired HTTP API row — a 5xx on
#     /v2/*/blobs/uploads/* at deadline-shaped latency — which IS exempt; n1 (the error row) is best-effort
#     corroboration. A guard over SOLEUR_ZOT_LOG_DROPPED rows protects n2's loss mode;
#   * the shared error-payload check grepped RAW rows for "exception|syntax error|Code: N", so one
#     GitHub-webhook row quoting an issue body wedged the probe for up to 7 days. It is now structural.
#
# ── WHAT THIS PROBE MUST NOT DO ────────────────────────────────────────────────────────────
# It must never report PASS for a state it could not establish. Every unestablished state is
# TRANSIENT (exit 2) with a distinct `reason=`, because this exit code auto-closes a tracker and
# "I could not tell" auto-closing a P1 follow-up is the failure this whole class exists to stop.
# `${VAR:?msg}` is BANNED here: under `set -u` it aborts with a bare bash diagnostic and no
# verdict line, which the sweeper records as an unclassified crash rather than a TRANSIENT.
# Nor may a helper's failure fold to zero: nothing that decides a verdict is `|| true`'d or `${x:-0}`'d.
#
# ── SCOPED TO THE DEADLINE SUB-MODE, DELIBERATELY ──────────────────────────────────────────
# zot's `PatchBlobUpload` fails in at least TWO shapes. This probe grades only the deadline shape.
# `unexpected EOF` is a DIFFERENT sub-mode, observed during a run that SUCCEEDED, and is out of scope
# for #7555 (a 5xx at EOF-shaped latency is printed as other5xx and not graded). A PASS here is not
# evidence that EOF is gone.
#
# OUTPUT IS PUBLIC. The sweeper posts stdout on a public issue; rows carry internal IPs, repo names and
# usernames, so this prints counts, reasons and enum values only — never a row excerpt.
#
# EXIT CONTRACT (the sweeper reads these numerically):
#   0  PASS       — both deadlines at DEADLINE_NS on the newest boot, a classifier-validated >= MIN_SAMPLES
#                   PATCH upload rows, no deadline-shaped failure, every read untruncated, no non-rate_cap
#                   shipper drop, and the coverage anchor present.
#   1  FAIL       — a deadline is absent/wrong on the newest boot, OR a deadline-shaped upload failure
#                   exists (decided BEFORE the floor and the truncation arm: a finding on a short or full
#                   page is still a finding). Both are real findings about the running host.
#   2  TRANSIENT  — the state could not be established. Never a pass.
# A bash crash (for example a `set -u` abort) exits 1, which the sweeper reads as FAIL; that is
# pre-existing and unchanged here (an EXIT-trap remap cannot be driven red without a test-only seam).
#
# DUPLICATION: decode() is a deliberate copy of scripts/followthroughs/zot-log-channel-7440.sh's; the
# scripts/lib/ extraction waits for a THIRD caller (there are still two).
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
# A ROW-count anti-vacuity floor ("the source actually emits"), not a push count and not statistical
# power. Measured: 44 PATCH rows in a week (18 pushes of 1-6 rows). 12 trips only on a near-silent week.
MIN_SAMPLES="${ZOT_CEILING_MIN_SAMPLES:-12}"
# Page limits. betterstack-query.sh keeps the NEWEST rows when more match, so a full page silently
# loses the OLDEST part of the window: a count == limit is truncation, never "all rows".
LOG_LIMIT=5000
DROP_LIMIT=20000
# Heartbeats land every 5 minutes, so any healthy window start has one within 6 hours. A constant,
# not a knob: probes run under `env -i`, so a knob would never be set.
ANCHOR_SLACK_H=6

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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# ── DECODE BEFORE MATCHING. The warehouse stores rows DOUBLE-ENCODED, and the producer's
# sanitize() runs `tr -d '"\\'` before shipping. So the bytes a naive grep sees are neither what
# zot emitted nor what this probe was written against. MEASURED against 200 real PatchBlobUpload
# rows: `grep -c 'PatchBlobUpload'` = 25, `grep -c 'i/o timeout'` = 0, and the same rows decoded
# give 21. The same two-stage decode scripts/followthroughs/zot-log-channel-7440.sh performs.
decode() {
  jq -R -r 'fromjson? | .raw // empty' 2>/dev/null \
    | jq -R -r 'fromjson? | .message // empty' 2>/dev/null
}

# STRUCTURAL row check. Every non-empty output line of a successful read must parse as a JSON object
# carrying `dt` and `raw`. A ClickHouse error payload can arrive on a ZERO exit (betterstack-query.sh
# runs `set -uo pipefail` without `-e`), and it does NOT look like a row. A TEXT grep for "exception"
# over raw rows is the wrong detector: a GitHub-webhook row quoting an issue body wedges it.
VALIDATE_PY='
import sys, json
rows = bad = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    rows += 1
    try:
        o = json.loads(line)
    except ValueError:
        bad += 1
        continue
    if not (isinstance(o, dict) and "dt" in o and "raw" in o):
        bad += 1
print("rows=%d bad=%d" % (rows, bad))
'

# fetch NAME TRUNC_AT ARGS...   — the ONE read helper. Exits 2 with query-failed-NAME on a nonzero rc,
# query-error-payload-NAME on a non-row output; otherwise sets FETCH_FILE (raw rows), FETCH_N and
# FETCH_TRUNC (1 when TRUNC_AT != 0 and the raw row count reached it). The caller decides what a
# truncated page means: a finding on a full page is still a finding.
FETCH_FILE=""; FETCH_N=0; FETCH_TRUNC=0
fetch() {
  local name="$1" trunc_at="$2"; shift 2
  local raw="$WORK/${name}.raw" err="$WORK/${name}.err" rc=0 shape=""
  "$QUERY" "$@" > "$raw" 2> "$err" || rc=$?
  if (( rc != 0 )); then
    verdict "TRANSIENT reason=query-failed-${name} query_rc=${rc}"
    echo "TRANSIENT: betterstack-query.sh exited ${rc}: $(head -c 400 "$err")"
    [[ "$rc" == "3" ]] && echo "  rc=3 is the credential guard — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY."
    echo "  NOT evidence about the registry host."
    exit 2
  fi
  shape="$(python3 -c "$VALIDATE_PY" "$raw" 2>/dev/null)" || shape=""
  if [[ ! "$shape" =~ ^rows=([0-9]+)\ bad=([0-9]+)$ ]] || [[ "${BASH_REMATCH[2]}" != "0" ]]; then
    verdict "TRANSIENT reason=query-error-payload-${name}"
    echo "TRANSIENT: the ${name} read returned something that is not rows (an ERROR PAYLOAD on a zero exit)."
    echo "  A failed read is not a measurement. NOT a pass."
    exit 2
  fi
  FETCH_FILE="$raw"
  FETCH_N="${BASH_REMATCH[1]}"
  FETCH_TRUNC=0
  if (( trunc_at != 0 && FETCH_N >= trunc_at )); then FETCH_TRUNC=1; fi
}

# ── Signal 1: DELIVERY. zot's boot `configuration settings` line. ──────────────────────────
fetch config 0 --since "$WINDOW" --grep 'configuration settings' --limit 2000
decode < "$FETCH_FILE" > "$WORK/config.dec"
cfg_rows="$(grep -c '[^[:space:]]' < "$WORK/config.dec" || true)"
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
CFG_LINE="$(grep -E 'ReadTimeout:[0-9]+' "$WORK/config.dec" | tail -1)"
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
# `--grep` flags are OR-combined `raw LIKE '%x%'`; `_` and `%` are LIKE wildcards, harmless here because
# every row is prefix-pinned after decode. `blobs/uploads` fetches the HTTP API rows (the sample and n2);
# `PatchBlobUpload` fetches the error rows (n1) and, unavoidably, heartbeat echoes, which the pin rejects.
fetch log "$LOG_LIMIT" --since "$WINDOW" --grep 'blobs/uploads' --grep 'PatchBlobUpload' --limit "$LOG_LIMIT"
LOG_TRUNC="$FETCH_TRUNC"
decode < "$FETCH_FILE" > "$WORK/log.dec"

# ONE classifier over the decoded rows. Every count below comes from here and nowhere else, so there is
# no second path that counts rows from an unpinned decode. A row counts only if it begins with the
# SOLEUR_ZOT_LOG envelope for the registry host (a SOLEUR_ZOT_DISK heartbeat, a webhook row quoting a
# row, or another host cannot enter any count); client text lives after `,headers:{` and is cut first,
# and `method` sits directly after `clientIP`, a server-controlled position.
#   patch      PATCH upload rows (the sample floor)
#   n1         level:error PatchBlobUpload rows with `i/o timeout` (best-effort: the error line is not cap-exempt)
#   n2         upload rows of ANY method with a 5xx at >= 95% of the deadline (the claim-bearing, exempt signal)
#   other5xx   5xx at any other latency (EOF-shaped, out of scope) ; unparse = 5xx with no Go-duration latency
#   upload_any upload rows of any method (printed so a future shape drift is readable from the verdict line)
CLASSIFIER_PY='
import re, sys
PFX = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "
CUT = 0.95 * float(sys.argv[2]) / 1e9
UP = re.compile(r"^\{time:[^,]+,level:[a-z]+,message:HTTP API,module:http,(?:username:[^,]*,)?component:session,clientIP:[^,]+,method:([A-Z]+),path:/v2/[^,]+/blobs/uploads/[^,]*,statusCode:([0-9]{3}),latency:([^,]+),")
ERR = re.compile(r"^\{time:[^,]+,level:error,")
UNITS = r"(?:ns|us|µs|ms|h|m|s)"
FULL = re.compile(r"(?:[0-9]+(?:\.[0-9]+)?" + UNITS + r")+")
DUR = re.compile(r"([0-9]+(?:\.[0-9]+)?)(" + UNITS + r")")
UNIT = {"ns": 1e-9, "us": 1e-6, "µs": 1e-6, "ms": 1e-3, "s": 1.0, "m": 60.0, "h": 3600.0}
patch = n1 = n2 = other5 = unparse = upload_any = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith(PFX):
        continue
    body = line[len(PFX):]
    m = UP.match(body.split(",headers:{", 1)[0])
    if m:
        upload_any += 1
        method, status, lat = m.groups()
        if method == "PATCH":
            patch += 1
        if status[0] == "5":
            if FULL.fullmatch(lat):
                secs = sum(float(v) * UNIT[u] for v, u in DUR.findall(lat))
                if secs >= CUT:
                    n2 += 1
                else:
                    other5 += 1
            else:
                unparse += 1
        continue
    if ERR.match(body) and "PatchBlobUpload" in body and "i/o timeout" in body:
        n1 += 1
print("patch=%d n1=%d n2=%d other5xx=%d unparse=%d upload_any=%d" % (patch, n1, n2, other5, unparse, upload_any))
'
cls="" ; cls_rc=0
cls="$(python3 -c "$CLASSIFIER_PY" "$WORK/log.dec" "$DEADLINE_NS" 2>/dev/null)" || cls_rc=$?
CLS_RE='^patch=([0-9]+) n1=([0-9]+) n2=([0-9]+) other5xx=([0-9]+) unparse=([0-9]+) upload_any=([0-9]+)$'
if (( cls_rc != 0 )) || [[ ! "$cls" =~ $CLS_RE ]]; then
  verdict "TRANSIENT reason=classifier-failed classifier_rc=${cls_rc}"
  echo "TRANSIENT: the upload-row classifier did not return a well-formed result. A crashed helper is not"
  echo "  a clean run: NOT a pass."
  exit 2
fi
patch_rows="${BASH_REMATCH[1]}"; n1="${BASH_REMATCH[2]}"; n2="${BASH_REMATCH[3]}"
other5xx="${BASH_REMATCH[4]}"; unparse="${BASH_REMATCH[5]}"; upload_any="${BASH_REMATCH[6]}"

# PRESENCE FIRST. A deadline-shaped failure is a finding on a short page, a full page or a page that also
# holds an unparseable latency; the floor and every coverage guard below only qualify an ABSENCE claim.
if (( n1 + n2 > 0 )); then
  verdict "FAIL reason=deadline-submode-present n1_error_rows=${n1} n2_deadline_5xx=${n2} window=${WINDOW}"
  echo "FAIL: ${n2} upload row(s) with a 5xx at deadline-shaped latency and ${n1} error row(s) carrying"
  echo "  'i/o timeout' in ${WINDOW}, on a host whose deadlines DO read ${DEADLINE_NS} ns. The deadline was"
  echo "  raised and uploads are still being cut, so the ceiling is not the (only) constraint — re-open the"
  echo "  diagnosis rather than raising the number again. Read the paired HTTP-API row's Content-Length and"
  echo "  latency for the new wall."
  exit 1
fi

if (( unparse > 0 )); then
  verdict "TRANSIENT reason=latency-unparseable rows=${unparse}"
  echo "TRANSIENT: ${unparse} upload 5xx row(s) carry a latency that is not a Go duration, so whether they are"
  echo "  deadline cuts is unknown. NOT a pass."
  exit 2
fi

if (( LOG_TRUNC == 1 )); then
  verdict "TRANSIENT reason=query-truncated-log rows=${FETCH_N} limit=${LOG_LIMIT} window=${WINDOW}"
  echo "TRANSIENT: the uploads read returned a FULL page. betterstack-query.sh keeps the newest rows, so the"
  echo "  oldest part of the window was lost and an absence claim would cover less than ${WINDOW}. NOT a pass."
  exit 2
fi

# SAMPLE FLOOR over real PATCH upload rows. A window with too few rows cannot support an absence claim.
if (( patch_rows < MIN_SAMPLES )); then
  verdict "TRANSIENT reason=too-few-samples patch_rows=${patch_rows} upload_rows_any=${upload_any} min=${MIN_SAMPLES} window=${WINDOW}"
  echo "TRANSIENT: only ${patch_rows} PATCH upload rows in ${WINDOW}; need >= ${MIN_SAMPLES} before an absence"
  echo "  means anything. Too little upload traffic to conclude, NOT a clean run. (upload_rows_any=${upload_any}:"
  echo "  many upload rows with zero PATCH matches would mean the row shape drifted, not that traffic stopped.)"
  exit 2
fi

# ── Exempt-lane drop guard. The shipper caps ORDINARY rows per tick (reason=rate_cap) and never drops
# the exempt lane (failed-upload HTTP halves) unless something else went wrong. rate_cap is the ONLY
# benign reason; any other reason — or a drop row with no parseable reason — means the row n2 depends on
# could have been lost, so the absence claim is unsupported. An allow-list of one is deliberate: a future
# drop reason must fail closed. Accepted trade-off: one non-rate_cap drop blocks PASS until the window
# rolls past it. Measured 7d: 1913 rows (~10% of the page), all rate_cap.
fetch dropped "$DROP_LIMIT" --since "$WINDOW" --grep 'SOLEUR_ZOT_LOG_DROPPED' --limit "$DROP_LIMIT"
if (( FETCH_TRUNC == 1 )); then
  verdict "TRANSIENT reason=query-truncated-dropped rows=${FETCH_N} limit=${DROP_LIMIT} window=${WINDOW}"
  echo "TRANSIENT: the drop-accounting read returned a FULL page, so the oldest drops are unseen. NOT a pass."
  exit 2
fi
decode < "$FETCH_FILE" > "$WORK/dropped.dec"
DROP_PY='
import re, sys, collections
PFX = "SOLEUR_ZOT_LOG_DROPPED "
bad = collections.Counter()
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith(PFX):
        continue
    m = re.search(r"\breason=([A-Za-z0-9_]+)", line)
    r = m.group(1) if m else "noreason"
    if r != "rate_cap":
        bad[r] += 1
print("bad=" + (",".join("%s:%d" % kv for kv in sorted(bad.items())) if bad else "-"))
'
dshape="" ; drc=0
dshape="$(python3 -c "$DROP_PY" "$WORK/dropped.dec" 2>/dev/null)" || drc=$?
if (( drc != 0 )) || [[ ! "$dshape" =~ ^bad=([A-Za-z0-9_:,-]+)$ ]]; then
  verdict "TRANSIENT reason=classifier-failed classifier_rc=${drc} stage=dropped"
  echo "TRANSIENT: the drop-accounting classifier did not return a well-formed result. NOT a pass."
  exit 2
fi
if [[ "${BASH_REMATCH[1]}" != "-" ]]; then
  verdict "TRANSIENT reason=exempt-lane-dropped reasons=${BASH_REMATCH[1]} window=${WINDOW}"
  echo "TRANSIENT: the log shipper dropped rows for a reason other than rate_cap in ${WINDOW}. rate_cap drops only"
  echo "  ordinary-lane rows; any other reason could have lost the failed-upload row this probe's absence claim"
  echo "  rests on. NOT a pass until the window rolls past it."
  exit 2
fi

# ── Coverage anchor. Replaces the old span-of-rows guard, which could never pass (see the header). At least
# one SOLEUR_ZOT_DISK heartbeat must lie in [window start, window start + ANCHOR_SLACK_H]: `--since` is the
# window itself, so a hit proves the warehouse reaches the window start independent of upload timing, and a
# heartbeat elsewhere in the window (or older than it) cannot satisfy it. Bounded to 20 rows, so it cannot
# truncate. Date arithmetic in python3 (already a prerequisite), not GNU `date -d`.
UNTIL="$(python3 -c '
import sys, datetime
days, slack = int(sys.argv[1]), int(sys.argv[2])
t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days) + datetime.timedelta(hours=slack)
print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))
' "$WIN_DAYS" "$ANCHOR_SLACK_H" 2>/dev/null)" || UNTIL=""
if [[ ! "$UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  verdict "TRANSIENT reason=span-arithmetic-failed"
  echo "TRANSIENT: could not compute the coverage anchor bound. NOT a pass."
  exit 2
fi
fetch anchor 0 --since "$WINDOW" --until "$UNTIL" --grep 'SOLEUR_ZOT_DISK' --limit 20
decode < "$FETCH_FILE" > "$WORK/anchor.dec"
anchor_rows="$(grep -c '^SOLEUR_ZOT_DISK ' < "$WORK/anchor.dec" || true)"
if [[ "${anchor_rows:-0}" -eq 0 ]]; then
  verdict "TRANSIENT reason=retention-shorter-than-window window=${WINDOW} anchor_slack_h=${ANCHOR_SLACK_H}"
  echo "TRANSIENT: no SOLEUR_ZOT_DISK heartbeat within ${ANCHOR_SLACK_H}h of the window start, so the warehouse"
  echo "  cannot be shown to reach back ${WINDOW}. An absence claim over time nobody observed is NOT a pass."
  exit 2
fi

verdict "PASS deadlines_ns=${DEADLINE_NS} patch_rows=${patch_rows} upload_rows_any=${upload_any} other5xx=${other5xx} window=${WINDOW}"
echo "PASS: both zot HTTP deadlines report ${DEADLINE_NS} ns on the running host, and across ${patch_rows} PATCH upload"
echo "  rows in ${WINDOW} there is no upload 5xx at deadline-shaped latency and no 'i/o timeout' error row."
echo "  SCOPE: this grades the DEADLINE sub-mode only. 'unexpected EOF' is a separate shape, was observed during a"
echo "  SUCCESSFUL run, and is out of scope for #7555 (${other5xx} upload 5xx row(s) at other latencies are not graded)."
echo "  WEIGHT: the error row is not exempt from the shipper's caps, so the absence rests on the paired HTTP-API"
echo "  row, guarded by drop accounting; the error-row count is best-effort. patch_rows is a lower bound (ordinary"
echo "  rows are rate-capped), and a clean week of this size is a tripwire, not proof: DELIVERY is the causal"
echo "  evidence. It is also not a claim that any particular release succeeded."
exit 0
