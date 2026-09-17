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
#   4 - no dedicated-host rows in the window. SILENCE IS NOT HEALTH: this means the
#       host is not shipping, which is itself a finding, not a clean bill.

set -uo pipefail

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

if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  cat >&2 <<'EOF'
inngest-host-state.sh: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not set.

You are NOT missing access — these live in Doppler and must be INJECTED:

  doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh

If `doppler` is not installed:  scripts/ensure-doppler.sh
EOF
  exit 3
fi

probe_rows="$("$QUERY" --since "$SINCE" --grep SOLEUR_INNGEST_SERVER_PROBE --limit 300 2>/dev/null)" || true

state_out="$(printf '%s\n' "$probe_rows" | python3 -c '
import sys, json, re

rows = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
        r = json.loads(o.get("raw", "{}"))
    except Exception:
        continue
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
    f = dict(re.findall(r"(\w+)=([^\s]+)", m))
    rows.append((o.get("dt", "")[:19], f))

if not rows:
    sys.exit(4)

# A row that anchored but carries no identity did not parse as a probe row. Emitting a
# verdict over it would restate the defect above in a narrower form: absent fields must
# never render as a health claim.
if not rows[-1][1].get("instance_id") or not rows[-1][1].get("server_active"):
    sys.exit(5)

import datetime as _dt

dt, f = rows[-1]
serving = f.get("server_active") == "active" and f.get("http_code") == "200"

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
    dt, ("  [%dm old]" % age_min) if age_min is not None else "", len(rows)))
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
stale = age_min is not None and age_min > 5
print("  VERDICT        %s%s" % (
    ("SERVING" if serving else "NOT SERVING"),
    ("   AS OF %dm AGO — NOT NECESSARILY NOW" % age_min) if stale else ""))
if stale:
    print("  STALE          the probe timer is hourly (OnUnitActiveSec=1h), so this row can")
    print("                 lag reality by up to 60m. A change made since %s is" % dt)
    print("                 INVISIBLE here. Read the error scan for continuously-shipped lines.")
if not serving:
    # A single sample is a coin flip on a crash-looping unit (RestartSec=5 never latches
    # `failed`), so say what this reading does and does not establish.
    print("  NOTE           server_active=activating across two rows an hour apart is the")
    print("                 crash-loop signature, not a slow boot. One sample cannot")
    print("                 distinguish it from a boot in progress.")
' 2>/dev/null)"
state_rc=$?

if [[ "$state_rc" -eq 5 ]]; then
  echo "inngest-host-state.sh: the newest anchored row carries no instance_id/server_active." >&2
  echo "  It did not parse as a probe row, so NO VERDICT is emitted — an unparseable row is" >&2
  echo "  not evidence of ill health any more than of good. Widen --since and re-read." >&2
  exit 5
fi

if [[ "$state_rc" -eq 4 || -z "$state_out" ]]; then
  echo "inngest-host-state.sh: no dedicated-host probe rows in the last ${SINCE}." >&2
  echo "  SILENCE IS NOT HEALTH — it means the host is not shipping to Better Stack" >&2
  echo "  (vector down, host down, or never booted). That is a finding, not a clean read." >&2
  exit 4
fi

printf '%s\n' "$state_out"

[[ "$WANT_ERRORS" -eq 1 ]] || exit 0

err_rows="$("$QUERY" --since "$SINCE" --grep inngest-server --limit 400 2>/dev/null)" || true
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
' 2>/dev/null

exit 0
