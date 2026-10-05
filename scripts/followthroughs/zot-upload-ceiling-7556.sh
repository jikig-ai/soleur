#!/usr/bin/env bash
# Follow-through verification for #7556 — did the raised zot HTTP deadlines LAND, and did the
# deadline sub-mode STOP?
#
# WHY TWO SIGNALS AND NOT ONE. The change (#7555, ADR-190) is delivered by a `user_data` ForceNew
# replace, so "the config in the repo says 1800s" proves nothing about the running host. And a
# quiet log proves nothing either, because the failure is INTERMITTENT at roughly 1 in 13 per push —
# a quiet stretch is the expected outcome even fully unfixed. So this probe requires BOTH:
#
#   (1) DELIVERY  — zot's own boot `configuration settings` line, on the NEWEST start, reports both
#                   deadlines at the intended nanosecond value, and no OTHER start inside the window
#                   reports anything else (so the whole window ran under the raised deadlines). This is
#                   zot reporting its own parsed config, not the repo describing itself.
#   (2) ABSENCE   — over a window long enough to matter, no deadline-shaped upload failure.
#
# Neither alone is a pass. (2) is a TRIPWIRE, not a proof: at ~18 pushes a week and ~1-in-13 per push
# an unfixed pipeline still looks clean over the window about 24% of the time, so DELIVERY is the
# causal evidence.
#
# ── WHAT THE SAMPLE FLOOR COUNTS (the 2026-10 fix) ────────────────────────────────────────────
# The floor used to be `grep -c PatchBlobUpload`. That string is zot's handler FUNC NAME: it appears
# only on zot ERROR lines (`func:...PatchBlobUpload`) and on the SOLEUR_ZOT_DISK heartbeat's echo of the
# last error, never on a successful upload row. So a week with 44 real PATCH uploads read
# `too-few-samples patch_rows=2` — two heartbeat echoes of one stale EOF error — on every sweep from
# 2026-08-21. The denominator is now the PATCH 2xx `/blobs/uploads` HTTP API row itself, pinned to the
# SOLEUR_ZOT_LOG envelope and read in ONE python3 classifier (see CLASSIFIER_PY).
#
# Defects that sat behind that one, each of which would have kept the probe from ever passing or let it
# pass wrongly:
#   * the retention guard demanded `span(rows) >= 168h` over rows fetched with `--since 7d`; every row
#     satisfies dt >= now-7d, so the span is <= 168h with equality only at the endpoints. It is replaced
#     by a COVERAGE ANCHOR (a registry heartbeat inside [window start, window start + 6h]) plus a
#     TRAILING-EDGE check (a registry heartbeat in the last 12h), so a shipper or warehouse outage at
#     either end cannot be read as a quiet week;
#   * the real `PatchBlobUpload` error line carries `message:unexpected error, removing .uploads/ files`
#     and names the handler only in `func:`, so the shipper's cap-exempt arm keyed on a `PatchBlobUpload*`
#     message prefix does not see it, and an absence claim made only of error rows is blind. The
#     claim-bearing signal (n2) is the paired HTTP API row — a 5xx on /v2/*/blobs/uploads/* at
#     deadline-shaped latency — which IS exempt; n1 (the error row) is best-effort corroboration. A guard
#     over SOLEUR_ZOT_LOG_DROPPED rows protects n2's loss mode;
#   * the shared error-payload check grepped RAW rows for "exception|syntax error|Code: N", so one
#     GitHub-webhook row quoting an issue body wedged the probe for up to 7 days. It is now structural;
#   * a decoded line is NOT necessarily one row from one emitter. The warehouse source is shared with
#     GitHub-webhook receipts that quote attacker-influenceable text (a real one quoting
#     `configuration settings` sits in the warehouse), a message may carry a newline that the splitter
#     reads as a second row, and a client controls the path/username text that sits before the
#     `statusCode`/`latency` fields. So: ONE decoder emits exactly one sanitized line per row; every
#     signal (config, uploads, drops, heartbeats) is pinned to its emitter's envelope at offset 0; a row
#     whose server fields occur more than once is unparseable, never counted; and the drop read
#     (whose empty answer would read as "no drops") must account for every row it fetched.
#
# ── WHAT THIS PROBE MUST NOT DO ────────────────────────────────────────────────────────────
# It must never report PASS for a state it could not establish. Every unestablished state is
# TRANSIENT (exit 2) with a distinct `reason=`, because this exit code auto-closes a tracker and
# "I could not tell" auto-closing a P1 follow-up is the failure this whole class exists to stop.
# `${VAR:?msg}` is BANNED here: under `set -u` it aborts with a bare bash diagnostic and no
# verdict line, which the sweeper records as an unclassified crash rather than a TRANSIENT.
# A helper's failure is validated by shape and never folded into a count; the two `grep -c … || true`
# folds that remain turn "could not count" into 0, and 0 maps to TRANSIENT, never to PASS.
#
# ── SCOPED TO THE DEADLINE SUB-MODE, DELIBERATELY ──────────────────────────────────────────
# zot's `PatchBlobUpload` fails in at least TWO shapes. This probe grades only the deadline shape.
# `unexpected EOF` is a DIFFERENT sub-mode, observed during a run that SUCCEEDED, and is out of scope
# for #7555 (a 5xx at EOF-shaped latency is printed as other5xx and not graded). A PASS here is not
# evidence that EOF is gone. A 2xx at deadline-shaped latency (ADR-190 "Arm C") is not graded either;
# delivery parity of BOTH keys is the guard for that shape.
#
# OUTPUT IS PUBLIC. The sweeper posts stdout on a public issue; rows carry internal IPs, repo names and
# usernames, and the query tool's stderr can name the warehouse host, so this prints counts, reasons and
# enum values only — never a row excerpt and never the query tool's stderr.
#
# EXIT CONTRACT (the sweeper reads these numerically):
#   0  PASS       — both deadlines on the newest start AND on every start in the window, a validated
#                   >= MIN_SAMPLES PATCH 2xx upload rows, no deadline-shaped failure, every read
#                   untruncated, no non-rate_cap shipper drop, and heartbeats at both ends of the window.
#   1  FAIL       — a deadline is absent/wrong on the newest start, OR a deadline-shaped upload failure
#                   exists (decided BEFORE the floor and the truncation arm: a finding on a short or full
#                   page is still a finding). Both are real findings about the running host.
#   2  TRANSIENT  — the state could not be established. Never a pass.
# A bash crash (for example a `set -u` abort) exits 1, which the sweeper reads as FAIL; that is
# pre-existing and unchanged here (an EXIT-trap remap cannot be driven red without a test-only seam).
#
# DUPLICATION: the two-stage row decode exists, in jq form, in several sibling probes
# (zot-log-channel-7440.sh, zot-inventory-assert-marker.sh, zot-disk-sample.sh, ...). This probe's
# decoder is python (it must neutralise embedded line breaks, which `jq -r` re-emits as row breaks), so
# it is a different implementation, not a copy. Extracting one shared decoder and the structural
# payload check into scripts/lib/ is tracked with the shipper follow-up for #7556.
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
# power. Measured: 43 PATCH 2xx rows in a week (18 pushes of 1-6 rows). 12 trips only on a near-silent week.
MIN_SAMPLES="${ZOT_CEILING_MIN_SAMPLES:-12}"
# Page limits. betterstack-query.sh keeps the NEWEST rows when more match, so a full page silently
# loses the OLDEST part of the window: a count == limit is truncation, never "all rows".
LOG_LIMIT=5000
DROP_LIMIT=20000
# Heartbeats land every 5 minutes, so any healthy window start has one within 6 hours, and any healthy
# present has one within 12 hours. Constants, not knobs: probes run under `env -i`.
ANCHOR_SLACK_H=6
TAIL_STALE_H=12
# zot logs its `configuration settings` line once per START, so a long-lived host's line ages out of the
# window; look back further for the newest one.
CFG_LOOKBACK=30d

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

WORK="$(mktemp -d)" || { verdict "TRANSIENT reason=no-scratch-dir"; echo "TRANSIENT: mktemp -d failed."; exit 2; }
trap 'rm -rf "$WORK"' EXIT
# A signal must END the run: a handler that only removes the scratch dir lets the script resume with
# $WORK gone and limp to a verdict with a bogus reason.
trap 'exit 130' INT
trap 'exit 143' TERM

# ── ONE DECODER. The warehouse stores rows DOUBLE-ENCODED ({"dt":..,"raw":"{\"message\":..}"}) and the
# producer's sanitize() strips quotes and non-printable bytes, so a naive grep sees neither what zot
# emitted nor what this probe was written against. This decodes `.raw` then `.message` and emits EXACTLY
# ONE line per row: any embedded line break (LF, CR, VT, FF, NEL, U+2028/9) becomes a space, because a
# message that carries one is otherwise read as several rows (a forged `SOLEUR_ZOT_LOG ...` line inside a
# webhook receipt would satisfy the sample floor). `.dts` is the parallel row-time file. A row that does
# not decode to a string message is counted in bad=, never silently skipped. Prints `ok=N bad=M`.
DECODE_PY='
import json, re, sys
src, out, dts = sys.argv[1], sys.argv[2], sys.argv[3]
BRK = re.compile("[\r\n\v\f\x00\x85\u2028\u2029]")
ok = bad = 0
with open(src, encoding="utf-8", errors="replace") as fi, \
     open(out, "w", encoding="utf-8") as fo, open(dts, "w", encoding="utf-8") as fd:
    for line in fi:
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
            inner = json.loads(o["raw"])
            msg = inner["message"]
            dt = o["dt"]
            if not (isinstance(msg, str) and isinstance(dt, str)):
                raise ValueError("shape")
        except (ValueError, KeyError, TypeError):
            bad += 1
            continue
        fo.write(BRK.sub(" ", msg) + "\n")
        fd.write(BRK.sub(" ", dt) + "\n")
        ok += 1
print("ok=%d bad=%d" % (ok, bad))
'

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
# truncated page means: a finding on a full page is still a finding. The query tool's stderr is never
# printed (it can name the warehouse host and this output is public).
FETCH_FILE=""; FETCH_N=0; FETCH_TRUNC=0
fetch() {
  local name="$1" trunc_at="$2"; shift 2
  local raw="$WORK/${name}.raw" err="$WORK/${name}.err" rc=0 shape=""
  "$QUERY" "$@" > "$raw" 2> "$err" || rc=$?
  if (( rc != 0 )); then
    verdict "TRANSIENT reason=query-failed-${name} query_rc=${rc}"
    echo "TRANSIENT: betterstack-query.sh exited ${rc} on the ${name} read."
    [[ "$rc" == "3" ]] && echo "  rc=3 is the credential guard: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY (run under doppler run -p soleur -c prd_terraform --)."
    echo "  Not evidence about the registry host. Re-run locally to read the tool's own stderr."
    exit 2
  fi
  shape="$(python3 -c "$VALIDATE_PY" "$raw" 2>/dev/null)" || shape=""
  if [[ ! "$shape" =~ ^rows=([0-9]+)\ bad=([0-9]+)$ ]] || [[ "${BASH_REMATCH[2]}" != "0" ]]; then
    local bad_rows="-"
    [[ "$shape" =~ ^rows=([0-9]+)\ bad=([0-9]+)$ ]] && bad_rows="${BASH_REMATCH[2]}"
    verdict "TRANSIENT reason=query-error-payload-${name} bad_rows=${bad_rows}"
    echo "TRANSIENT: the ${name} read returned something that is not rows (an ERROR PAYLOAD on a zero exit)."
    echo "  A failed read is not a measurement. NOT a pass. Re-run once; if it repeats, read the response by hand."
    exit 2
  fi
  FETCH_FILE="$raw"
  FETCH_N="${BASH_REMATCH[1]}"
  FETCH_TRUNC=0
  if (( trunc_at != 0 && FETCH_N >= trunc_at )); then FETCH_TRUNC=1; fi
}

# decode NAME   — decodes the last fetched read into $WORK/NAME.dec (one line per row) and NAME.dts.
# Sets DEC_OK / DEC_BAD. A decoder that cannot run at all is TRANSIENT, never an empty result.
DEC_OK=0; DEC_BAD=0
decode() {
  local name="$1" shape=""
  shape="$(python3 -c "$DECODE_PY" "$FETCH_FILE" "$WORK/${name}.dec" "$WORK/${name}.dts" 2>/dev/null)" || shape=""
  if [[ ! "$shape" =~ ^ok=([0-9]+)\ bad=([0-9]+)$ ]]; then
    verdict "TRANSIENT reason=decoder-failed stage=${name}"
    echo "TRANSIENT: the row decoder did not return a well-formed result. NOT a pass."
    exit 2
  fi
  DEC_OK="${BASH_REMATCH[1]}"; DEC_BAD="${BASH_REMATCH[2]}"
}

# ── Signal 1: DELIVERY. zot's boot `configuration settings` line. ──────────────────────────
# CONFIG_PY reads the RAW rows (it needs each row's dt). A config row counts only if it begins with the
# SOLEUR_ZOT_LOG envelope for the registry host and has the zerolog shape `{time:..,level:info,
# message:configuration settings,params:{` — the shipped line is sanitized (no quotes), so the timeouts
# read `ReadTimeout:1800000000000`; a `"ReadTimeout":` pattern would never match and the probe would
# return TRANSIENT forever. A webhook row or another host quoting that text cannot be a config row.
# Output: `cfg_rows=N newest=<ok|none|unparseable> read=R write=W older_bad=K`:
#   newest      the newest pinned config row (by dt): carries both timeouts / is absent / lacks one
#   older_bad   other pinned config rows INSIDE the window whose deadlines are not DEADLINE_NS (a zot
#               start in the window that predates the delivery: the window is not a post-fix window)
CONFIG_PY='
import json, re, sys, datetime
src, deadline, win_days = sys.argv[1], sys.argv[2], int(sys.argv[3])
PFX = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "
SHAPE = re.compile(r"^\{time:[^,]+,level:info,message:configuration settings,params:\{")
BRK = re.compile("[\r\n\v\f\x00\x85\u2028\u2029]")
def when(s):
    for f in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.datetime.strptime(s[:26] if "." in s else s[:19], f)
        except ValueError:
            pass
    return None
rows = []
for line in open(src, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
        msg = BRK.sub(" ", json.loads(o["raw"])["message"])
        dt = when(o["dt"])
    except (ValueError, KeyError, TypeError):
        continue
    if dt is None or not isinstance(msg, str) or not msg.startswith(PFX):
        continue
    body = msg[len(PFX):]
    if not SHAPE.match(body):
        continue
    r = re.search(r"ReadTimeout:([0-9]+)", body)
    w = re.search(r"WriteTimeout:([0-9]+)", body)
    rows.append((dt, r.group(1) if r else None, w.group(1) if w else None))
rows.sort(key=lambda t: t[0])
if not rows:
    print("cfg_rows=0 newest=none read=- write=- older_bad=0")
    sys.exit(0)
newest = rows[-1]
state = "ok" if (newest[1] and newest[2]) else "unparseable"
start = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - datetime.timedelta(days=win_days)
older_bad = sum(1 for dt, r, w in rows[:-1] if dt >= start and (r != deadline or w != deadline))
print("cfg_rows=%d newest=%s read=%s write=%s older_bad=%d" % (len(rows), state, newest[1] or "-", newest[2] or "-", older_bad))
'
fetch config 0 --since "$CFG_LOOKBACK" --grep 'configuration settings' --limit 2000
cshape="" ; crc=0
cshape="$(python3 -c "$CONFIG_PY" "$FETCH_FILE" "$DEADLINE_NS" "$WIN_DAYS" 2>/dev/null)" || crc=$?
CFG_RE='^cfg_rows=([0-9]+) newest=(ok|none|unparseable) read=([0-9-]+) write=([0-9-]+) older_bad=([0-9]+)$'
if (( crc != 0 )) || [[ ! "$cshape" =~ $CFG_RE ]]; then
  verdict "TRANSIENT reason=classifier-failed classifier_rc=${crc} stage=config"
  echo "TRANSIENT: the config-row classifier did not return a well-formed result. NOT a pass."
  exit 2
fi
cfg_rows="${BASH_REMATCH[1]}"; cfg_newest="${BASH_REMATCH[2]}"; read_ns="${BASH_REMATCH[3]}"
write_ns="${BASH_REMATCH[4]}"; older_bad="${BASH_REMATCH[5]}"

if [[ "$cfg_newest" == "none" ]]; then
  verdict "TRANSIENT reason=no-config-line lookback=${CFG_LOOKBACK}"
  echo "TRANSIENT: no registry 'configuration settings' line in ${CFG_LOOKBACK}. Either the #7440 log channel is not"
  echo "  delivering (check the SOLEUR_ZOT_DISK heartbeats with zot-log-channel-7440.sh), or the host has not"
  echo "  started since the channel began (dispatch registry-host-replace). An empty channel is not evidence"
  echo "  the deadlines landed."
  exit 2
fi
if [[ "$cfg_newest" == "unparseable" ]]; then
  verdict "TRANSIENT reason=deadlines-unparseable read=${read_ns} write=${write_ns}"
  echo "TRANSIENT: the newest registry 'configuration settings' line lacks a ReadTimeout or WriteTimeout. The line's"
  echo "  shape may have changed across a zot bump — re-read it (betterstack-query.sh --grep 'configuration settings')"
  echo "  before trusting any verdict here. NOT a pass and NOT a failure."
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
if (( older_bad > 0 )); then
  verdict "TRANSIENT reason=window-spans-pre-delivery-start older_starts=${older_bad} window=${WINDOW}"
  echo "TRANSIENT: ${older_bad} zot start(s) inside the ${WINDOW} window reported deadlines other than ${DEADLINE_NS} ns, so"
  echo "  the window includes time before the change landed and cannot be graded as a post-fix soak."
  echo "  This clears on its own once the window rolls past that start. NOT a pass."
  exit 2
fi

# ── Signal 2: ABSENCE of the deadline sub-mode. ────────────────────────────────────────────
# `--grep` flags are OR-combined `raw LIKE '%x%'`; `_` and `%` are LIKE wildcards, harmless here because
# every row is prefix-pinned after decode. `blobs/uploads` fetches the HTTP API rows (the sample and n2);
# `PatchBlobUpload` fetches the error rows (n1) and, unavoidably, heartbeat echoes, which the pin rejects.
fetch log "$LOG_LIMIT" --since "$WINDOW" --grep 'blobs/uploads' --grep 'PatchBlobUpload' --limit "$LOG_LIMIT"
LOG_TRUNC="$FETCH_TRUNC"
decode log

# ONE classifier over the decoded rows. Every count below comes from here and nowhere else. A row counts
# only if it begins with the SOLEUR_ZOT_LOG envelope for the registry host (a SOLEUR_ZOT_DISK heartbeat, a
# webhook row quoting a row, or another host cannot enter any count). Client text lives after
# `,headers:{` (cut first) and in `path:`/`username:` (which sit BEFORE statusCode/latency), so a row in
# which any server field (clientIP, method, statusCode, latency) occurs other than exactly once is
# UNPARSEABLE — never counted, never graded — and so is an HTTP-API upload row that does not match the
# shape at all (a truncated row cannot be graded either way). Exact-duplicate rows (the shipper replays
# after an undelivered POST) count once.
#   patch      PATCH upload rows with a 2xx status (the sample floor: real pushes, not 401s or cuts)
#   long_ok    of those, rows at >= 60 s (uploads surviving past the OLD ceiling; printed, never graded)
#   n1         level:error PatchBlobUpload rows with `i/o timeout` (best-effort: the line is not cap-exempt)
#   n2         upload rows of ANY method with a 5xx at >= 95% of the deadline (the claim-bearing signal)
#   other5xx   5xx at any other latency (EOF-shaped, out of scope)
#   unparse    forged/duplicated-field, unmatched, or non-Go-duration-5xx upload rows
#   upload_any upload rows of any method (printed so a future shape drift is readable from the verdict)
CLASSIFIER_PY='
import re, sys
PFX = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "
CUT = 0.95 * float(sys.argv[2]) / 1e9
HTTP = re.compile(r"^\{time:[^,]+,level:[a-z]+,message:HTTP API,")
UP = re.compile(r"^\{time:[^,]+,level:[a-z]+,message:HTTP API,module:http,(?:username:[^,]*,)?component:session,clientIP:[^,]+,method:([A-Z]+),path:/v2/[^,]+/blobs/uploads/[^,]*,statusCode:([0-9]{3}),latency:([^,]+),")
ERR = re.compile(r"^\{time:[^,]+,level:error,")
UNITS = r"(?:ns|us|ms|h|m|s)"
FULL = re.compile(r"(?:[0-9]+(?:\.[0-9]+)?" + UNITS + r")+")
DUR = re.compile(r"([0-9]+(?:\.[0-9]+)?)(" + UNITS + r")")
UNIT = {"ns": 1e-9, "us": 1e-6, "ms": 1e-3, "s": 1.0, "m": 60.0, "h": 3600.0}
ONCE = (",clientIP:", ",method:", ",statusCode:", ",latency:")
patch = long_ok = n1 = n2 = other5 = unparse = upload_any = 0
seen = set()
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.startswith(PFX):
        continue
    body = line[len(PFX):]
    if body in seen:
        continue
    seen.add(body)
    head = body.split(",headers:{", 1)[0]
    if HTTP.match(head) and "blobs/uploads" in head:
        m = UP.match(head)
        if not m or any(head.count(t) != 1 for t in ONCE):
            unparse += 1
            continue
        upload_any += 1
        method, status, lat = m.groups()
        secs = None
        if FULL.fullmatch(lat):
            secs = sum(float(v) * UNIT[u] for v, u in DUR.findall(lat))
        if method == "PATCH" and status[0] == "2":
            patch += 1
            if secs is not None and secs >= 60:
                long_ok += 1
        if status[0] == "5":
            if secs is None:
                unparse += 1
            elif secs >= CUT:
                n2 += 1
            else:
                other5 += 1
        continue
    if ERR.match(body) and "PatchBlobUpload" in body and "i/o timeout" in body:
        n1 += 1
print("patch=%d long_ok=%d n1=%d n2=%d other5xx=%d unparse=%d upload_any=%d" % (patch, long_ok, n1, n2, other5, unparse, upload_any))
'
cls="" ; cls_rc=0
cls="$(python3 -c "$CLASSIFIER_PY" "$WORK/log.dec" "$DEADLINE_NS" 2>/dev/null)" || cls_rc=$?
CLS_RE='^patch=([0-9]+) long_ok=([0-9]+) n1=([0-9]+) n2=([0-9]+) other5xx=([0-9]+) unparse=([0-9]+) upload_any=([0-9]+)$'
if (( cls_rc != 0 )) || [[ ! "$cls" =~ $CLS_RE ]]; then
  verdict "TRANSIENT reason=classifier-failed classifier_rc=${cls_rc} stage=log"
  echo "TRANSIENT: the upload-row classifier did not return a well-formed result. A crashed helper is not"
  echo "  a clean run: NOT a pass."
  exit 2
fi
patch_rows="${BASH_REMATCH[1]}"; long_ok="${BASH_REMATCH[2]}"; n1="${BASH_REMATCH[3]}"; n2="${BASH_REMATCH[4]}"
other5xx="${BASH_REMATCH[5]}"; unparse="${BASH_REMATCH[6]}"; upload_any="${BASH_REMATCH[7]}"

# PRESENCE FIRST. A deadline-shaped failure is a finding on a short page, a full page or a page that also
# holds an unparseable row; the floor and every coverage guard below only qualify an ABSENCE claim.
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
  verdict "TRANSIENT reason=upload-rows-unparseable rows=${unparse}"
  echo "TRANSIENT: ${unparse} upload HTTP-API row(s) could not be graded (a 5xx latency that is not a Go duration, a"
  echo "  row whose server fields repeat, or a row that does not match the zot shape, such as a truncated one), so"
  echo "  whether they are deadline cuts is unknown. A zot log-format change shows up here first. NOT a pass."
  exit 2
fi

if (( LOG_TRUNC == 1 )); then
  verdict "TRANSIENT reason=query-truncated-log rows=${FETCH_N} limit=${LOG_LIMIT} window=${WINDOW}"
  echo "TRANSIENT: the uploads read returned a FULL page. betterstack-query.sh keeps the newest rows, so the"
  echo "  oldest part of the window was lost and an absence claim would cover less than ${WINDOW}. NOT a pass."
  echo "  This cannot clear by waiting: it needs LOG_LIMIT raised in this probe."
  exit 2
fi

# SAMPLE FLOOR over real PATCH 2xx upload rows. A window with too few rows cannot support an absence claim.
if (( patch_rows < MIN_SAMPLES )); then
  verdict "TRANSIENT reason=too-few-samples patch_rows=${patch_rows} upload_rows_any=${upload_any} min=${MIN_SAMPLES} window=${WINDOW}"
  echo "TRANSIENT: only ${patch_rows} PATCH 2xx upload rows in ${WINDOW}; need >= ${MIN_SAMPLES} before an absence"
  echo "  claim is more than a row count. Too little upload traffic to conclude, NOT a clean run. (upload_rows_any=${upload_any}:"
  echo "  many upload rows with zero PATCH matches would mean the row shape drifted, not that traffic stopped.)"
  exit 2
fi

# ── Exempt-lane drop guard. The shipper caps ORDINARY rows per tick (reason=rate_cap) and drops exempt
# rows (the failed-upload HTTP halves) only above a per-tick sub-quota or on a redaction failure. rate_cap
# is the ONLY benign reason; any other reason — or a drop row with no parseable reason — means the row
# n2 depends on could have been lost, so the absence claim is unsupported. An allow-list of one is
# deliberate: a future drop reason must fail closed. Accepted trade-off: one non-rate_cap drop blocks PASS
# until the window rolls past it (measured 7d: 1913 rows, all rate_cap). THIS read's empty answer reads
# as "no drops", so it alone must account for every row it fetched: a row that does not decode, or a
# non-empty page that decodes to nothing, is TRANSIENT, never a clean guard.
fetch dropped "$DROP_LIMIT" --since "$WINDOW" --grep 'SOLEUR_ZOT_LOG_DROPPED' --limit "$DROP_LIMIT"
if (( FETCH_TRUNC == 1 )); then
  verdict "TRANSIENT reason=query-truncated-dropped rows=${FETCH_N} limit=${DROP_LIMIT} window=${WINDOW}"
  echo "TRANSIENT: the drop-accounting read returned a FULL page, so the oldest drops are unseen. NOT a pass."
  echo "  This cannot clear by waiting: it needs DROP_LIMIT raised in this probe."
  exit 2
fi
decode dropped
if (( DEC_BAD > 0 || DEC_OK != FETCH_N )); then
  verdict "TRANSIENT reason=dropped-undecodable fetched=${FETCH_N} decoded=${DEC_OK} undecodable=${DEC_BAD}"
  echo "TRANSIENT: the drop-accounting read returned rows that do not decode to a message, so a drop could be"
  echo "  hiding in them. The row shape may have changed. NOT a pass."
  exit 2
fi
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
  echo "  rests on. NOT a pass until the window rolls past it (the drop rows carry their own timestamps)."
  exit 2
fi

# ── Coverage at BOTH ends of the window. A registry heartbeat (SOLEUR_ZOT_DISK, 5-minute cadence, host
# pinned before its free-text tail) must lie in [window start, window start + ANCHOR_SLACK_H] — `--since` is
# the window itself, so a hit proves the warehouse reaches the window start — and the newest heartbeat must
# be at most TAIL_STALE_H old, so a shipper or warehouse outage at the trailing edge (rows that were never
# delivered) cannot read as a quiet week. This replaces the old span-of-rows guard, which could never pass.
# Date arithmetic in python3 (already a prerequisite), not GNU `date -d`.
UNTIL="$(python3 -c '
import sys, datetime
days, slack = int(sys.argv[1]), int(sys.argv[2])
t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days) + datetime.timedelta(hours=slack)
print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))
' "$WIN_DAYS" "$ANCHOR_SLACK_H" 2>/dev/null)" || UNTIL=""
if [[ ! "$UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  verdict "TRANSIENT reason=anchor-bound-failed"
  echo "TRANSIENT: could not compute the coverage anchor bound. NOT a pass."
  exit 2
fi
HEARTBEAT_PY='
import re, sys, datetime
dec, dts = sys.argv[1], sys.argv[2]
PFX = "SOLEUR_ZOT_DISK "
n = 0
newest = None
for msg, dt in zip(open(dec, encoding="utf-8", errors="replace"), open(dts, encoding="utf-8", errors="replace")):
    msg = msg.rstrip("\n")
    if not msg.startswith(PFX):
        continue
    if not re.search(r"(?:^| )host=soleur-registry(?: |$)", msg.split(" zot_last_err=", 1)[0]):
        continue
    n += 1
    try:
        t = datetime.datetime.strptime(dt.strip()[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        continue
    if newest is None or t > newest:
        newest = t
age = "-"
if newest is not None:
    age = "%.1f" % ((datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - newest).total_seconds() / 3600.0)
print("n=%d newest_age_h=%s" % (n, age))
'
heartbeats() { # heartbeats NAME -> sets HB_N, HB_AGE
  local name="$1" shape="" rc=0
  shape="$(python3 -c "$HEARTBEAT_PY" "$WORK/${name}.dec" "$WORK/${name}.dts" 2>/dev/null)" || rc=$?
  if (( rc != 0 )) || [[ ! "$shape" =~ ^n=([0-9]+)\ newest_age_h=(-|-?[0-9]+\.[0-9])$ ]]; then
    verdict "TRANSIENT reason=classifier-failed classifier_rc=${rc} stage=${name}"
    echo "TRANSIENT: the heartbeat classifier did not return a well-formed result. NOT a pass."
    exit 2
  fi
  HB_N="${BASH_REMATCH[1]}"; HB_AGE="${BASH_REMATCH[2]}"
}
HB_N=0; HB_AGE="-"
fetch anchor 0 --since "$WINDOW" --until "$UNTIL" --grep 'SOLEUR_ZOT_DISK' --limit 20
decode anchor
heartbeats anchor
anchor_rows="$HB_N"
if (( anchor_rows == 0 )); then
  verdict "TRANSIENT reason=retention-shorter-than-window anchor_rows=0 window=${WINDOW} anchor_slack_h=${ANCHOR_SLACK_H}"
  echo "TRANSIENT: no registry heartbeat within ${ANCHOR_SLACK_H}h of the window start. Either warehouse retention does"
  echo "  not reach back ${WINDOW}, or the heartbeat reporter was down at the window start. Either way an absence claim"
  echo "  over time nobody observed is NOT a pass."
  exit 2
fi
fetch tail 0 --since 1d --grep 'SOLEUR_ZOT_DISK' --limit 20
decode tail
heartbeats tail
tail_rows="$HB_N"; tail_age="$HB_AGE"
if (( tail_rows == 0 )) || [[ "$tail_age" == "-" ]] || ! python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$tail_age" "$TAIL_STALE_H" 2>/dev/null; then
  verdict "TRANSIENT reason=heartbeat-stale newest_age_h=${tail_age} limit_h=${TAIL_STALE_H}"
  echo "TRANSIENT: no registry heartbeat in the last ${TAIL_STALE_H}h, so the newest part of the window is unobserved"
  echo "  (the registry host, the heartbeat reporter or the warehouse is not delivering). NOT a pass."
  exit 2
fi

verdict "PASS deadlines_ns=${DEADLINE_NS} config_starts=${cfg_rows} patch_rows=${patch_rows} long_ok=${long_ok} upload_rows_any=${upload_any} other5xx=${other5xx} n1=${n1} n2=${n2} anchor_rows=${anchor_rows} newest_heartbeat_age_h=${tail_age} window=${WINDOW}"
echo "PASS: both zot HTTP deadlines report ${DEADLINE_NS} ns on the newest start and on every start in ${WINDOW}, and across"
echo "  ${patch_rows} PATCH 2xx upload rows there is no upload 5xx at deadline-shaped latency and no 'i/o timeout' error row."
echo "  SCOPE: this grades the DEADLINE sub-mode only. 'unexpected EOF' is a separate shape, was observed during a"
echo "  SUCCESSFUL run, and is out of scope for #7555 (${other5xx} upload 5xx row(s) at other latencies are not graded)."
echo "  WEIGHT: the error row is not exempt from the shipper's caps, so the absence rests on the paired HTTP-API"
echo "  row, guarded by drop accounting; the error-row count is best-effort. patch_rows is a lower bound (ordinary"
echo "  rows are rate-capped; ${long_ok} of them ran 60 s or longer), and a clean week of this size is a tripwire, not"
echo "  proof: DELIVERY is the causal evidence. It is also not a claim that any particular release succeeded."
exit 0
