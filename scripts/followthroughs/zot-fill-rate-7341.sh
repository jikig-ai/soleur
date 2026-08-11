#!/usr/bin/env bash
# Follow-through verification for #7341 — the post-recut FILL RATE.
#
# WHY A FILL RATE AND NOT A DISK READING. The 2026-08-10 registry-luks-recut wiped a 100%-full
# store and rebuilt on a fresh LUKS cpx22. Hours later `pcent` was 6 and `zot_restarts` 0. That
# proves the recut worked; it proves NOTHING about whether the thing that filled the store is
# fixed, because a freshly wiped disk is empty regardless of the defect.
#
# The untreated cause is upstream zot#4235: gc completes repeatedly for `soleur-inngest-bootstrap`
# and never for `soleur-web-platform`, panicking in `pkg/scheduler/scheduler.go`. It is reported
# against 2.1.18 and PR #4236 is unmerged, so it is NOT fixed in the v2.1.20 pin this host now
# runs. A refill is therefore the EXPECTED outcome to measure, not a surprise to react to.
#
# A second candidate surfaced during the recut and is not in the original diagnosis: zot logged
# `unexpected error, removing .uploads/ files ... i/o timeout ... PatchBlobUpload`, i.e. its own
# cleanup of orphaned upload staging failing. The 2026-08-10 inventory left exactly two candidates
# for the 44.22 GB unaccounted (dedupe cache DB vs orphaned `.uploads/`), and that log line is
# direct evidence for the second. This check cannot discriminate them — it measures the SLOPE, and
# the slope is what says whether either is still accumulating.
#
# WHAT THIS ASSERTS. Over the samples in the window: the newest `pcent` is under the alerting
# threshold AND the store is not on a trajectory that reaches it soon. Both, because either alone
# is satisfiable by a broken system — a low reading says nothing about direction, and a flat slope
# at 90% is not health.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       pcent under threshold AND slope not projecting a breach inside the horizon
#   1 = FAIL       breach, or projected breach — the refill is live; #7341 stays open, treat
#                  zot#4235 / the .uploads/ lead as the actual work
#   * = TRANSIENT  Better Stack unreachable, or too little CURRENT-BOOT history to fit a slope
#                  (fewer than 12 samples, or spanning under MIN_SPAN_HOURS). The sweeper leaves
#                  the issue open and re-runs; this is the expected verdict for the first day or
#                  so after a recut, and it must never be read as health.
#
# Required env: BETTERSTACK_QUERY_HOST / _USERNAME / _PASSWORD (read by betterstack-query.sh).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# The indirection is the test seam. `betterstack-query.sh` is reached by absolute path, not via
# PATH, so the stub-a-binary harness the sibling soaks use (zot-soak-6122.test.sh) cannot reach it.
# Production never sets ZOT_FILL_QUERY; the sweeper runs under `env -i` with an explicit allowlist,
# so it cannot be set there even accidentally.
QUERY="${ZOT_FILL_QUERY:-${REPO_ROOT}/scripts/betterstack-query.sh}"

export PCENT_MAX=85       # the alerting threshold the heartbeat itself uses
export HORIZON_DAYS=14    # project the slope this far; a breach inside it is a FAIL
export MIN_SPAN_HOURS=24  # a slope needs a BASELINE, not just a count — see below
WINDOW="${ZOT_FILL_WINDOW:-72h}"

[[ -x "$QUERY" ]] || { echo "TRANSIENT: ${QUERY} is not executable"; exit 2; }

raw="$("$QUERY" --since "$WINDOW" --grep SOLEUR_ZOT_DISK --limit 1000 2>/dev/null)" || {
  echo "TRANSIENT: betterstack-query.sh failed (transport). NOT evidence about the store."; exit 2; }

# One "<epoch> <pcent>" per sample, SCOPED TO THE CURRENT BOOT.
#
# The boot_id scoping is the whole correctness of this check, and it was added after the first
# live run returned `PASS slope=-58.48pp/day proj14d=-811`. That reading is not a fill rate: the
# 72h window straddled the 2026-08-10 recut, so the regression fitted a line through the OLD
# volume at pcent=100 and the NEW one at pcent=6 and reported the WIPE as a trend. A wipe is a
# step discontinuity, not a slope, and fitting across it produces an arbitrarily large negative
# number that sails through every threshold below. The failure direction is the dangerous one:
# it PASSES.
#
# So: take the newest sample's boot_id and keep only rows that share it. Any host replacement,
# reboot, or second recut restarts the measurement rather than corrupting it.
samples="$(printf '%s\n' "$raw" | python3 -c '
import sys, json, re, datetime
rows=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: row=json.loads(line)
    except Exception: continue
    dt=row.get("dt",""); raw=str(row.get("raw",""))
    m=re.search(r"pcent=(\d+)", raw)
    # `(\S+)`, not a hex-and-dash class. A character class that does not cover the whole token
    # still MATCHES — it just captures the longest acceptable PREFIX. Two distinct boot_ids then
    # collapse to their common prefix and compare EQUAL, silently disabling the scoping this
    # entire check rests on, with no error anywhere. Caught by the harness at first run.
    b=re.search(r"boot_id=(\S+)", raw)
    if not (dt and m and b): continue
    try:
        ts=datetime.datetime.fromisoformat(dt.split(".")[0]).timestamp()
    except Exception: continue
    rows.append((int(ts), int(m.group(1)), b.group(1)))
if not rows:
    sys.exit(0)
rows.sort()
current=rows[-1][2]
print("\n".join(f"{t} {p}" for t,p,b in rows if b == current))
')"

n="$(printf '%s\n' "$samples" | grep -c '[0-9]' || true)"
# A SLOPE needs a spread of samples, not just two adjacent ones. Below this the answer is
# "could not measure", which must never read as "fine" on a gate that decides an incident.
if [[ "${n:-0}" -lt 12 ]]; then
  echo "TRANSIENT: only ${n:-0} SOLEUR_ZOT_DISK samples for the current boot in ${WINDOW}; cannot compute a fill rate."
  exit 2
fi

read -r verdict detail <<<"$(printf '%s\n' "$samples" | python3 -c '
import sys, os
pmax=float(os.environ["PCENT_MAX"]); horizon=float(os.environ["HORIZON_DAYS"])
min_span=float(os.environ["MIN_SPAN_HOURS"])/24.0
pts=[tuple(map(int,l.split())) for l in sys.stdin if l.strip()]
pts.sort()
t0=pts[0][0]
xs=[(t-t0)/86400.0 for t,_ in pts]; ys=[float(p) for _,p in pts]
span=xs[-1]
cur=ys[-1]

# COUNT is not BASELINE. The heartbeat emits every 5 minutes, so 12 samples can span one hour —
# enough rows to satisfy any count floor while extrapolating an hour of jitter across two weeks.
# A freshly recut host has exactly that shape, and it is the shape this check will meet first.
if span < min_span:
    print(f"TRANSIENT span={span*24:.1f}h_under_{min_span*24:.0f}h_pcent={cur:.0f}")
    raise SystemExit(0)

mx=sum(xs)/len(xs); my=sum(ys)/len(ys)
den=sum((x-mx)**2 for x in xs)
slope=(sum((x-mx)*(y-my) for x,y in zip(xs,ys))/den) if den else 0.0
proj=cur+slope*horizon
if cur >= pmax:
    print(f"FAIL pcent={cur:.0f}_at_or_over_{pmax:.0f}_slope={slope:+.2f}pp/day")
elif slope > 0 and proj >= pmax:
    days=(pmax-cur)/slope
    print(f"FAIL pcent={cur:.0f}_slope={slope:+.2f}pp/day_projects_{pmax:.0f}_in_{days:.1f}d")
else:
    print(f"PASS pcent={cur:.0f}_slope={slope:+.2f}pp/day_proj{horizon:.0f}d={proj:.0f}_span={span*24:.0f}h")
')"

echo "zot-fill-rate[#7341]: ${verdict} ${detail} samples=${n} window=${WINDOW}"
case "$verdict" in
  PASS) exit 0 ;;
  FAIL) echo "The store is refilling toward the threshold. zot#4235 is unfixed in v2.1.20; also weigh the orphaned .uploads/ lead (i/o timeout during PatchBlobUpload cleanup, observed 2026-08-10)."; exit 1 ;;
  TRANSIENT) echo "TRANSIENT: ${detail} — too little post-recut history to fit a slope. NOT a pass."; exit 2 ;;
  *)    echo "TRANSIENT: could not classify"; exit 2 ;;
esac
