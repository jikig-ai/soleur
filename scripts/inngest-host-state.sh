#!/usr/bin/env bash
# On-demand state read for the DEDICATED inngest host — no SSH, no waiting on the
# hourly probe consumer, and no tunnel coin-flip.
#
# ── WHY NOT /hooks/deploy-status ────────────────────────────────────────────────
# The runbook's "Reading host state without SSH" recipe reads `deploy.soleur.ai
# /hooks/deploy-status`. That endpoint CANNOT reach this host. MEASURED 2026-09-17,
# 12 consecutive attempts from a pinned reader:
#
#     resolved pin: hetzner-166317708 (newest dedicated-host probe row)
#     answered by: hetzner-123931471 ×12
#
# Every one was web-1. This is not an unlucky coin-flip to retry past — the `/hooks`
# channel TERMINATES on web-1; the dedicated inngest host runs no listener and has no
# inbound rule (its firewall is deny-all on the public interface, and the tunnel
# ingress is web-1's). So a `deploy-status` read about "the inngest host" is
# structurally answering about a different machine.
#
# That is exactly how a 2026-09-17 incident was misdiagnosed: a deploy-status payload
# showed `inngest_server: inactive` with a two-day-old journal, which was web-1's
# DELIBERATE quiesce, and it was nearly acted on as a statement about a freshly
# replaced host. `restart-inngest-server.yml` reads the same endpoint, which is why
# its verify step failed against a host it never reached.
#
# ── THE CHANNEL THAT DOES REACH IT ──────────────────────────────────────────────
# journald -> vector -> Better Stack. It is continuous (not hourly), and its rows
# carry the host identity IN THE ROW, so pinning is a filter rather than a routing
# hope. This is the channel that actually located the incident's root cause.
#
# ── THE PIN, AND WHY `host_name` ALONE IS NOT IT ────────────────────────────────
# web-1 ALSO emits SOLEUR_INNGEST_SERVER_PROBE with `host_name=soleur-inngest-prd`
# (measured: `host=soleur-web-platform host_role=web probe_schema=4`). A filter on
# the marker or on host_name alone therefore reads the WRONG MACHINE while looking
# correct. The pin is the conjunction: host=soleur-inngest AND host_role=dedicated.
#
# Credentials are INJECTED, never read here:
#   doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh
# `doppler` missing is not a missing capability -> scripts/ensure-doppler.sh
#
# Exit codes:
#   0 - at least one dedicated-host row was found and printed
#   2 - bad usage
#   3 - credentials not injected (nothing was queried)
#   4 - the query RAN, returned rc=0, and the window held no dedicated-host row. SILENCE IS
#       NOT HEALTH: the host is not shipping, which is itself a finding, not a clean bill.
#   5 - the newest anchored row carried no identity/verdict fields, so NO VERDICT was
#       emitted. An unparseable row is not evidence of ill health any more than of good.
#   6 - THE READ FAILED. Nothing about the host was measured. This is NOT a statement about
#       the host and must never be reported as one.
#  78 - refused to run under `set -x` with a live credential in the environment (#7797).
#       Nothing was queried. Listed here because an undocumented code is one a caller
#       branches on wrongly — the same reason 5 and 6 are listed.
#
# WHY 6 EXISTS, AND WHY 4 IS NOT ALLOWED TO ABSORB IT. Until this code was added, every way
# the instrument could fail — the query binary absent, a rejected credential, a ClickHouse
# 5xx, a DNS fault, python3 missing, a traceback — produced an empty `probe_rows` and fell
# into the exit-4 arm, which names three specific HOST causes ("vector down, host down, or
# never booted"). Measured 2026-09-17: five distinct instrument faults each printed that
# sentence verbatim about a healthy host, with the underlying error discarded by
# `2>/dev/null`. That is the exact confident-wrong reading this file's own header says it
# exists to prevent, committed one layer above the row filter it was written for.
#
# The sibling classifier already had the vocabulary: scripts/inngest-dedicated-host-classify.sh
# grades an unreadable query `probe-unavailable` and says "a missing signal must not read as
# a working one"; scripts/cutover-inngest.sh's G3 says "this is NOT a statement about the
# host". This script now follows both rather than re-deriving a narrower verdict.

set -uo pipefail

# (#7797) Refuse to run under shell tracing while a live credential is set: `set -x` would
# trace BETTERSTACK_QUERY_PASSWORD into whatever collects this script's output. Spelled
# exactly as scripts/betterstack-query.sh spells it — `case "$-" in *x*)` tests whether
# tracing is ON rather than enumerating the eight ways to turn it on, two of which carry no
# `-x` token at all. This script is wrapped in `doppler run`, so the credential is live in
# its environment on every real invocation.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${INNGEST_STATE_QUERY:-$SCRIPT_DIR/betterstack-query.sh}"
SINCE="${INNGEST_STATE_SINCE:-90m}"
WANT_ERRORS=1

usage() {
  cat >&2 <<'EOF'
usage: inngest-host-state.sh [--since 90m] [--no-errors]

  --since      lookback window (default 90m; the probe timer is hourly, so a
               shorter window can render a healthy host silent).
  --no-errors  print only the probe state, skip the recent unit-error scan.

Wrap in `doppler run -p soleur -c prd_terraform --` so creds are injected.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --no-errors) WANT_ERRORS=0; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# VALIDATE THE WINDOW BEFORE SPENDING A QUERY ON IT. `--since 90` (unit omitted) and
# `--since ""` both reach ClickHouse as a malformed literal; the query then fails, and before
# the exit-6 split above that failure was reported as "the host is not shipping". A caller's
# typo must never be able to render as a production outage.
if [[ ! "$SINCE" =~ ^[0-9]+[hmd]$ ]]; then
  echo "inngest-host-state.sh: --since must be <N>h, <N>m or <N>d — got '${SINCE}'." >&2
  echo "  Nothing was queried. This is a usage error, not a statement about the host." >&2
  exit 2
fi

if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  cat >&2 <<'EOF'
inngest-host-state.sh: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not set.

You are NOT missing access — these live in Doppler and must be INJECTED:

  doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh

If `doppler` is not installed:  scripts/ensure-doppler.sh
EOF
  exit 3
fi

# THE READ IS MEASURED, NOT ASSUMED. The rc and stderr are both captured: `|| true` plus
# `2>/dev/null` is what let a 503, a rejected credential and a missing binary all render as
# "the host is not shipping". An instrument fault exits 6 below and NEVER reaches the
# host-verdict arm.
QERR="$(mktemp)"
trap 'rm -f "$QERR"' EXIT
probe_rc=0
probe_rows="$("$QUERY" --since "$SINCE" --grep SOLEUR_INNGEST_SERVER_PROBE --limit 300 2>"$QERR")" || probe_rc=$?

if [[ "$probe_rc" -ne 0 ]]; then
  echo "inngest-host-state.sh: THE READ FAILED (${QUERY##*/} exit ${probe_rc}). NOTHING about the host was measured." >&2
  echo "  This is NOT a statement about the dedicated inngest host — it is a statement about" >&2
  echo "  the read path. A rotated Better Stack credential, a ClickHouse fault, a DNS failure" >&2
  echo "  and an absent binary all land here, and none of them is evidence the host is down." >&2
  if [[ -s "$QERR" ]]; then
    echo "  --- ${QUERY##*/} stderr (first 5 lines) ---" >&2
    head -5 "$QERR" >&2
  else
    echo "  (the query produced no stderr; check that ${QUERY} exists and is executable)" >&2
  fi
  exit 6
fi

state_out="$(printf '%s\n' "$probe_rows" | python3 -c '
import sys, json, re

rows = []
# BYTES ARRIVED BUT NOTHING PARSED IS AN INSTRUMENT FAULT, NOT A HOST FINDING. A proxy or CDN
# error page, or a ClickHouse error body returned with a zero exit, gives a SUCCESSFUL query
# whose output is not rows at all. Counting only `rows` cannot tell that from a genuinely
# empty window, so both are counted: `nonempty` lines in, `parsed` of them decoded.
nonempty = 0
parsed = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    nonempty += 1
    try:
        o = json.loads(line)
        r = json.loads(o.get("raw", "{}"))
    except Exception:
        continue
    parsed += 1
    # THE PIN. Both conjuncts: web-1 emits this marker with host_name=soleur-inngest-prd,
    # so host_name alone selects the wrong machine while looking right.
    if r.get("host") != "soleur-inngest":
        continue
    m = r.get("message")
    if not isinstance(m, str):
        continue
    # ANCHOR, NOT A BARE TOKEN (cq-assert-anchor-not-bare-token). A `"host_role=dedicated"
    # in m` test matches ANY line CONTAINING the token, including third-party content the
    # host merely logged. MEASURED 2026-09-17: inngest-server logs each webhook delivery as
    # JSON carrying the full `rawBody`, so a GitHub pull_request event whose body quoted
    # `host_role=dedicated` — the description of the PR adding this script — became the
    # "newest probe row". Every field then parsed as absent and the summary still printed
    # a confident `VERDICT NOT SERVING` about a healthy host.
    if not m.startswith("SOLEUR_INNGEST_SERVER_PROBE"):
        continue
    if "host_role=dedicated" not in m:
        continue
    # FIRST-WINS, NOT LAST-WINS. `dict(re.findall(...))` keeps the LAST occurrence of every
    # key and the scan covers the WHOLE line, so any trailing `k=v` text overrides a field
    # the summary then presents as measured truth. Measured 2026-09-17: a probe line whose
    # tail carried `server_active=active http_code=200` rendered a host that was actually
    # `activating`/`000` as `VERDICT SERVING` — a clean bill of health on the crash-loop
    # state this tool exists to catch. The probe emitter writes each key once, so first-wins
    # is lossless for well-formed rows and immune to an appended tail.
    f = {}
    for _k, _v in re.findall(r"(\w+)=([^\s]+)", m):
        f.setdefault(_k, _v)
    rows.append((o.get("dt", "")[:19], f))

# Exit 7 (surfaced as the exit-6 read-failure class by the caller): the query answered, but
# none of what it answered with was a row.
if nonempty > 0 and parsed == 0:
    sys.stderr.write(
        "the query returned %d non-empty line(s) and NONE decoded as a warehouse row\n"
        % nonempty)
    sys.exit(7)

if not rows:
    sys.exit(4)

# A row that anchored but carries no identity did not parse as a probe row. Emitting a
# verdict over it would restate the defect above in a narrower form: absent fields must
# never render as a health claim.
# THE GUARD MUST COVER EVERY FIELD THE VERDICT IS MADE OF, not just the two that were in
# mind when it was written. `http_code` and `registry_fns` are both conjuncts of `serving`
# below; with only instance_id/server_active guarded, a row missing `http_code` printed
# `http_code=?` next to a confident `NOT SERVING` — a verdict decided by an absence, which
# is the same defect one field over.
_newest = rows[-1][1]
if not all(_newest.get(k) for k in ("instance_id", "server_active", "http_code", "registry_fns")):
    sys.exit(5)

import datetime as _dt

dt, f = rows[-1]
# THE THIRD CONJUNCT (#8015). `server_active=active` plus `http_code=200` says the unit runs
# and the listener answers — it says NOTHING about whether the host owns any work. A
# diagnostic boot (`INNGEST_DIAGNOSTIC_BOOT=1`, documented in the runbook section this PR adds)
# satisfies both and serves nothing. scripts/followthroughs/inngest-host-not-serving-7674.sh
# added `registry_fns` for exactly this reason and records it inline; re-deriving the verdict
# here without it granted SERVING to the state #7674 exists to detect.
_regfns = f.get("registry_fns", "")
serving = (
    f.get("server_active") == "active"
    and f.get("http_code") == "200"
    and _regfns.isdigit()
    and int(_regfns) > 0
)

# AGE IS NOT DECORATION. `inngest-server-probe.timer` is OnUnitActiveSec=1h, so the
# newest row can be an hour old and the verdict below is a statement about THEN, not
# now. Measured 2026-09-17: a read taken at 13:02 returned the 12:49 row and would
# have reported NOT SERVING for a host recovered at 12:53. Printing a bare verdict
# over a stale row is the same confident-wrong reading this script exists to prevent.
age_min = None
try:
    obs = _dt.datetime.strptime(dt, "%Y-%m-%d %H:%M:%S").replace(tzinfo=_dt.timezone.utc)
    age_min = int((_dt.datetime.now(_dt.timezone.utc) - obs).total_seconds() // 60)
except Exception:
    pass

print("dedicated inngest host — newest probe row")
print("  observed_at    %s%s   (rows in window: %d)" % (
    dt,
    ("  [%dm old]" % age_min) if age_min is not None else "  [AGE UNKNOWN — dt unparseable]",
    len(rows)))
print("  instance_id    %s" % f.get("instance_id", "?"))
print("  boot_id        %s" % f.get("boot_id", "?"))
print("  probe_schema   %s" % f.get("probe_schema", "?"))
print("  server_active  %s        http_code=%s" % (f.get("server_active", "?"), f.get("http_code", "?")))
print("  registry_fns   %s" % f.get("registry_fns", "?"))
print("  redis_active   %s        redis_keys=%s expires=%s" % (
    f.get("redis_active", "?"), f.get("redis_keys", "?"), f.get("redis_expires", "?")))
print("  data_mount     %s  devid=%s  bytes=%s" % (
    f.get("data_mount_src", "?"), f.get("data_mount_devid", "?"), f.get("data_bytes", "?")))
print("  cutover_flag   %s        flush_latched=%s" % (
    f.get("cutover_flag", "?"), f.get("flush_latched", "?")))
# AN UNKNOWN AGE IS NOT A FRESH ONE. `age_min is None` (an unparseable or absent `dt`) used
# to evaluate `stale = False`, byte-identical to a row three minutes old: no `[Nm old]`
# bracket, no qualifier, a bare verdict. The absence of the bracket reads as tidiness. A
# negative age (a non-UTC `dt` column) failed open the same way. Both now count as stale,
# which is the only direction that cannot mislead.
stale = age_min is None or age_min < 0 or age_min > 5
if stale:
    _age_note = ("   AS OF %dm AGO — NOT NECESSARILY NOW" % age_min) if age_min is not None \
        else "   AS OF AN UNKNOWN TIME — the dt on this row did not parse"
else:
    _age_note = ""
# SERVING= IS THE MACHINE-READABLE TOKEN. The human words stay, but `SERVING` is a
# SUBSTRING of `NOT SERVING`, so any consumer (or test) doing `grep -q SERVING` reads a
# crash-looping host as healthy — the T1 case in this suite did exactly that. `SERVING=yes|no`
# cannot be matched the wrong way round.
print("  VERDICT        %s   SERVING=%s%s" % (
    ("SERVING" if serving else "NOT SERVING"),
    ("yes" if serving else "no"),
    _age_note))
if stale:
    print("  STALE          the probe timer is hourly (OnUnitActiveSec=1h), so this row can")
    print("                 lag reality by up to 60m. A change made since %s is" % dt)
    print("                 INVISIBLE here. Read the error scan for continuously-shipped lines.")
# THE NOTE ASSERTS A FIELD VALUE, SO IT IS GATED ON THAT VALUE. It used to print on ANY
# non-serving verdict, so a row reading `server_active=active` (not serving because
# registry_fns=0, or because http_code was absent) was handed a crash-loop hypothesis that
# contradicted the line four rows above it — an unmeasured causal claim in the advisory
# voice of the tool itself.
if not serving and f.get("server_active") == "activating":
    # A single sample is a coin flip on a crash-looping unit (RestartSec=5 never latches
    # `failed`), so say what this reading does and does not establish.
    print("  NOTE           server_active=activating across two rows an hour apart is the")
    print("                 crash-loop signature, not a slow boot. One sample cannot")
    print("                 distinguish it from a boot in progress.")
# A LISTENING HOST THAT OWNS NO WORK IS ITS OWN STATE (#8015), not a generic failure.
if not serving and f.get("server_active") == "active" and f.get("http_code") == "200":
    print("  NOTE           the unit runs and the listener answers, but registry_fns=%s — it"
          % f.get("registry_fns", "?"))
    print("                 owns no work. That is the diagnostic-boot / unregistered signature")
    print("                 (INNGEST_DIAGNOSTIC_BOOT=1 serves nothing), not a dead process.")
' 2>"$QERR")"
state_rc=$?

# A TRACEBACK IS AN INSTRUMENT FAULT, NOT A HOST FINDING. python3 absent (127), a schema
# change that raises, an encoding fault — each exits non-zero with a code that is neither 4
# nor 5, and each used to fall through the `-z "$state_out"` arm into the host verdict.
if [[ "$state_rc" -ne 0 && "$state_rc" -ne 4 && "$state_rc" -ne 5 ]]; then
  echo "inngest-host-state.sh: THE READ FAILED (row interpreter exit ${state_rc}). NOTHING about the host was measured." >&2
  echo "  The rows were fetched but could not be interpreted, so no verdict is possible." >&2
  if [[ -s "$QERR" ]]; then
    echo "  --- interpreter stderr (first 5 lines) ---" >&2
    head -5 "$QERR" >&2
  fi
  exit 6
fi

if [[ "$state_rc" -eq 5 ]]; then
  echo "inngest-host-state.sh: the newest anchored row carries no instance_id/server_active." >&2
  echo "  It did not parse as a probe row, so NO VERDICT is emitted — an unparseable row is" >&2
  echo "  not evidence of ill health any more than of good. Widen --since and re-read." >&2
  exit 5
fi

# EXIT 4 IS NOW REACHED ONLY FROM rc=4 — "the query ran and the window held no dedicated
# row". The `-z "$state_out"` limb used to be an OR here, which is what made every silent
# instrument fault indistinguishable from a silent host. An empty rc=0 output is not a host
# finding either; it is an interpreter that produced nothing, so it exits 6.
if [[ "$state_rc" -eq 0 && -z "$state_out" ]]; then
  echo "inngest-host-state.sh: THE READ FAILED — the interpreter exited 0 but produced no summary." >&2
  echo "  NOTHING about the host was measured. This is not a statement about the host." >&2
  exit 6
fi

if [[ "$state_rc" -eq 4 ]]; then
  echo "inngest-host-state.sh: the query RAN and returned no dedicated-host probe rows in the last ${SINCE}." >&2
  echo "  SILENCE IS NOT HEALTH — it means the host is not shipping to Better Stack" >&2
  echo "  (vector down, host down, or never booted). That is a finding, not a clean read." >&2
  echo "  (The read path itself is healthy: had it failed, this would be exit 6, not exit 4.)" >&2
  exit 4
fi

printf '%s\n' "$state_out"

[[ "$WANT_ERRORS" -eq 1 ]] || exit 0

# AN ABSENT SECTION IS NOT AN EMPTY ONE. Before this, a failed error-scan query printed
# nothing and exited 0 — byte-identical to "the scan ran and found no refusals". That is the
# worse direction here, because the STALE banner above explicitly sends the operator to this
# section as the only continuously-shipped evidence, and on the #7228 path the line it would
# have carried is the BLOCK refusal this whole PR exists to surface.
err_rc=0
err_rows="$("$QUERY" --since "$SINCE" --grep inngest-server --limit 400 2>"$QERR")" || err_rc=$?
if [[ "$err_rc" -ne 0 ]]; then
  echo >&2
  echo "  error scan DID NOT RUN (${QUERY##*/} exit ${err_rc}) — the absence of a refusals" >&2
  echo "  section below is NOT evidence that there were none. The state summary above stands;" >&2
  echo "  this second read failed independently of it." >&2
  if [[ -s "$QERR" ]]; then head -3 "$QERR" >&2; fi
  exit 0
fi

scan_rc=0
printf '%s\n' "$err_rows" | python3 -c '
import sys, json

hits = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
        r = json.loads(o.get("raw", "{}"))
    except Exception:
        continue
    if r.get("host") != "soleur-inngest":
        continue
    m = r.get("message")
    if not isinstance(m, str):
        continue
    if "DOPPLER_" in m or "SOLEUR_INNGEST_SERVER_PROBE" in m:
        continue
    # STRUCTURED APP LOGS ARE NOT FAILURES. inngest-server emits its own JSON lines
    # ({"caller":"api","event":{...}}) for every webhook delivery, and a bare substring
    # scan matches them on words buried in an arbitrary payload. Measured 2026-09-17:
    # eight routine `pull_request` deliveries were reported as "recent refusals".
    # Unit-level refusals are PLAIN TEXT from systemd/ExecStartPre, never JSON.
    if m.lstrip().startswith("{"):
        continue
    # Anchored markers, not loose substrings: `refus` alone also matches prose in a
    # success line that merely mentions what it did not refuse.
    if not any(k in m for k in (
        "BLOCK:", "ERROR: refusing", "Failed to start", "Failed with result",
        "FATAL", "refusing a prod start", "-REFUSED",
    )):
        continue
    hits.append((o.get("dt", "")[:19], m[:200]))

# AFFIRMATIVE ZERO. An absent section cannot be read as "none found" — say it.
if not hits:
    print()
    print("recent refusals / failures: NONE in the window (the scan ran and matched nothing).")

if hits:
    print()
    print("recent refusals / failures (newest last):")
    seen = set()
    for dt, m in hits[-8:]:
        key = m[:90]
        if key in seen:
            continue
        seen.add(key)
        print("  %s  %s" % (dt, m))
' 2>"$QERR" || scan_rc=$?

# The interpreter's rc is ASSERTED, not merely captured. A captured-but-unread verdict is the
# same silent-failure shape as the `|| true` this file just removed one layer up.
if [[ "$scan_rc" -ne 0 ]]; then
  echo >&2
  echo "  error scan FAILED to interpret its rows (exit ${scan_rc}) — the absence of a" >&2
  echo "  refusals section above is NOT evidence that there were none." >&2
  if [[ -s "$QERR" ]]; then head -3 "$QERR" >&2; fi
fi

exit 0
