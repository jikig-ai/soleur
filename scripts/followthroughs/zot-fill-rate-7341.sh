#!/usr/bin/env bash
# Follow-through verification for #7341 — the post-recut FILL RATE.
#
# WHY A FILL RATE AND NOT A DISK READING. The 2026-08-10 registry-luks-recut wiped a 100%-full
# store and rebuilt on a fresh LUKS cpx22. Hours later `pcent` was 6 and `zot_restarts` 0. That
# proves the recut worked; it proves NOTHING about whether the thing that filled the store is
# fixed, because a freshly wiped disk is empty regardless of the defect.
#
# The untreated cause is upstream zot#4235: gc completes repeatedly for `soleur-inngest-bootstrap`
# and never for `soleur-web-platform`, panicking in `pkg/scheduler/scheduler.go`. PR #4236 is
# unmerged, so it is NOT fixed in the v2.1.20 pin this host runs. A refill is therefore the
# EXPECTED outcome to measure. A second candidate — orphaned `.uploads/` staging, seen as
# `i/o timeout ... PatchBlobUpload` during the recut — is not discriminable from here; attribution
# is blocked by #7440 (the registry ships no zot logs; this heartbeat is its only instrument).
#
# ── EVERY PARSE STEP BELOW IS A GUARD. DO NOT REGEX THE WHOLE ROW. ───────────────────────────
#
# This probe reads a multiplexed log stream and its exit code AUTO-CLOSES a P1 incident tracker.
# Three of the guards come from `scripts/lib/zot-telemetry-parse.sh`, which exists so the #6288
# soak, the #6291 restart-loop alarm and this probe cannot drift apart on them; its header calls
# duplicating them "a maintenance hazard", and the first version of this file was that hazard
# realised — it hand-rolled `re.search(r"pcent=(\d+)")` over the raw row and had all three holes.
# Each was demonstrated flipping a verdict, not argued:
#
#   1. ENVELOPE ANCHOR. `--grep SOLEUR_ZOT_DISK` compiles to an unanchored
#      `raw LIKE '%SOLEUR_ZOT_DISK%'` over a source EVERY host multiplexes into. A genuine
#      emission's stored `raw` STARTS `{"message":"SOLEUR_ZOT_DISK `. Without the anchor, ONE
#      GitHub comment quoting a marker line — routine triage on a disk-fill incident — turned a
#      measured `FAIL pcent=78 projects 85 in 0.4d` into `PASS pcent=6`. The commenter picks the
#      verdict. The same hole is why `private-nic-converged-6415.sh:50` calls its anchor
#      "load-bearing, and NOT optional". The journald egress-failure line
#      `[zot] SOLEUR_ZOT_DISK egress ... FAILED: $LINE` also carries a full copy of `pcent=` and
#      `boot_id=`, and lands exactly when direct egress is broken.
#   2. TRUSTED REGION. `zot_last_err=` is emitted LAST and is free text from zot's own logs. Cut
#      from its first occurrence so a crafted error message cannot spoof a verdict field. The
#      sentinel case makes this live rather than paranoid: cloud-init sets `PCENT=-1` when `df`
#      fails, `pcent=(\d+)` does not match `-1`, so an unstripped search WALKS ON into the tail.
#   3. `boot_id=unknown`. cloud-init falls back to that literal when /proc is unreadable. Treating
#      it as an identity collapses every boot that ever failed the read into one pseudo-boot, and
#      a recut straddle then fits the wipe as a trend again — reproducing this file's own headline
#      defect verbatim (`PASS slope=-32.44pp/day`).
#
# Two further guards are specific to what this probe measures and have no library equivalent:
#
#   4. STEP DISCONTINUITY WITHIN A BOOT. boot_id is the KERNEL boot id, but every remediation on
#      the table for #7341 — a gc run reclaiming, the `.uploads/` cleanup succeeding, a zot
#      CONTAINER restart, an operator delete — frees the volume WITHOUT rebooting. Same boot_id,
#      same wipe, same bogus fit. Measured: a store cleaned at 95% and then refilling at +20pp/day
#      over the following 24h — precisely the zot#4235 signature — reported
#      `PASS slope=-31.15pp/day`. Scoping to boot_id does not cover this; only fitting the
#      TRAILING SEGMENT after the largest drop does.
#   5. `cur` IS A MEDIAN, NOT THE LAST SAMPLE. `df` resolves `/var/lib/zot` to the ROOT filesystem
#      if the volume is detached or mid-remount, reporting its low usage. One such reading
#      appended to 48h pinned at 95% turned `FAIL pcent=95` into `PASS pcent=8`.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       pcent under threshold AND the trailing segment not projecting a breach
#   1 = FAIL       breach, or projected breach — the refill is live; #7341 stays open
#   * = TRANSIENT  the store's state could not be established. Each cause prints a DISTINCT
#                  message: "cannot measure" must never read as "fine", and an operator reading
#                  only the sweeper's issue comment has no other instrument.
#
# Required env: BETTERSTACK_QUERY_HOST / _USERNAME / _PASSWORD (read by betterstack-query.sh).
#
# shellcheck disable=SC2016  # the python3 -c bodies are single-quoted ON PURPOSE — bash must not
#                              expand them; the constants they need arrive via the environment.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# The indirection is the test seam. `betterstack-query.sh` is reached by absolute path, not via
# PATH, so the stub-a-binary harness the sibling soaks use cannot reach it. Production never sets
# ZOT_FILL_QUERY: the sweeper runs `env -i` with a CLOSED allowlist and this name is absent from
# the workflow's `env:`. That second clause is the actual defence — `env -i` forwards any name the
# directive's `secrets=` lists, so this stays safe only while the workflow env stays explicit.
QUERY="${ZOT_FILL_QUERY:-${REPO_ROOT}/scripts/betterstack-query.sh}"
PARSE_LIB="${REPO_ROOT}/scripts/lib/zot-telemetry-parse.sh"

export PCENT_MAX=85       # the alerting threshold the heartbeat itself uses
export HORIZON_DAYS=14    # project the trailing slope this far; a breach inside it is a FAIL
export MIN_SPAN_HOURS=24  # a slope needs a BASELINE, not just a count
export MAX_AGE_MIN=30     # the newest sample must be RECENT — six missed 5-minute beats
export DROP_PP=15         # a fall of this many points between adjacent samples is a WIPE, not a trend
WINDOW="${ZOT_FILL_WINDOW:-72h}"

[[ -x "$QUERY" ]] || { echo "TRANSIENT: ${QUERY} is not executable"; exit 2; }
[[ -r "$PARSE_LIB" ]] || { echo "TRANSIENT: ${PARSE_LIB} is not readable — refusing to hand-roll the trusted-region parse"; exit 2; }
command -v python3 >/dev/null || { echo "TRANSIENT: python3 is not on PATH"; exit 2; }
# NOT sourced, and the reason is mechanical rather than a preference. `zot_trusted_region` is
# `sort | sed 's/ zot_last_err=.*//'`, which cuts to END OF LINE — on a JSONEachRow row that also
# removes the closing `"}`, so the row no longer decodes and every sample silently vanishes
# (measured: n=0 from 144 rows). The library's consumers grep whole lines; this probe must decode
# them, so the same three invariants are applied post-decode below, each labelled with the library
# function it mirrors. Duplicating a security invariant is the hazard the library's own header
# warns about, so this divergence is filed for reconciliation rather than left implicit — a
# JSON-aware variant belongs in the library. The readability check above stays: if the library is
# missing, the invariants it documents are probably being reasoned about wrongly here too.

# Keep stderr AND the exit code. `2>/dev/null` here destroyed the most likely first-run failure:
# an unprovisioned secret resolves to "", the sweeper still forwards it (it tests for SET, not
# non-empty), betterstack-query.sh exits 3 with an actionable "creds not injected" message — and
# the operator's issue comment said only "failed (transport)".
qerr="$(mktemp)"; WORK_BOOT="$(mktemp)"; trap 'rm -f "$qerr" "$WORK_BOOT"' EXIT
# Capture rc on its OWN line. Inside `if ! cmd; then`, `$?` is the negated test result, not the
# command's exit status, so `qrc` read 0 for every failure and the rc=3 credential branch below
# was unreachable. The harness caught it; a live run would have printed "exited 0".
raw="$("$QUERY" --since "$WINDOW" --grep SOLEUR_ZOT_DISK --limit 5000 2>"$qerr")"; qrc=$?
if (( qrc != 0 )); then
  echo "zot-fill-rate[#7341]: TRANSIENT query_rc=${qrc}"
  echo "TRANSIENT: betterstack-query.sh exited ${qrc}: $(head -c 600 "$qerr")"
  [[ "$qrc" == "3" ]] && echo "  rc=3 is the credential guard — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY."
  echo "  NOT evidence about the store."
  exit 2
fi

rows_total="$(printf '%s\n' "$raw" | grep -c '[^[:space:]]' || true)"
envelope="$(printf '%s\n' "$raw" | { grep -F '"raw":"{\"message\":\"SOLEUR_ZOT_DISK ' || true; })"   # guard 1
rows_env="$(printf '%s\n' "$envelope" | grep -c '[^[:space:]]' || true)"

if [[ "${rows_env:-0}" -eq 0 ]]; then
  echo "zot-fill-rate[#7341]: TRANSIENT no_emission_rows rows_returned=${rows_total} window=${WINDOW}"
  echo "TRANSIENT: the query answered but ZERO rows matched the emission envelope. A MEASURED"
  echo "  absence, not a query failure: the heartbeat is not landing, so the registry is currently"
  echo "  UNOBSERVABLE (it is the only instrument — #7440). A dead heartbeat is not a low disk."
  echo "  Discriminator for producer-silent vs fresh-host vs creds: scripts/zot-restart-loop-alarm.sh"
  exit 2
fi

samples="$(printf '%s\n' "$envelope" | BOOT_OUT="$WORK_BOOT" python3 -c '
import sys, json, re, datetime, os
rows=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: row=json.loads(line)
    except Exception: continue
    dt=row.get("dt","")
    inner=row.get("raw","")
    if isinstance(inner,str) and inner.lstrip().startswith("{"):
        try: inner=json.loads(inner)
        except Exception: pass
    msg=inner.get("message","") if isinstance(inner,dict) else str(inner)
    # MIRRORS zot_trusted_region: cut the free-text zot_last_err tail BEFORE any key=value parse,
    # so a crafted zot log line cannot spoof pcent= or boot_id=. Applied to the decoded message
    # rather than the raw line, which is the only difference from the library.
    msg=msg.split(" zot_last_err=")[0]
    b=re.search(r"boot_id=([0-9a-fA-F-]+)", msg)
    # MIRRORS zot_newest_boot: "unknown" is cloud-init /proc fallback, not an identity.
    if not b or b.group(1)=="unknown": continue
    # Does NOT match the pcent=-1 df-failure sentinel; with the tail already cut there is nothing
    # further along to fall through to.
    m=re.search(r"pcent=(\d+)", msg)
    if not (dt and m): continue
    # Better Stack emits dt NAIVE IN UTC. .timestamp() on a naive datetime assumes LOCAL, which on
    # a UTC+2 host read every sample two hours old and made the staleness gate call a live
    # heartbeat 124 minutes stale. Differences are immune to a constant offset, so span and slope
    # were never affected -- only the wall-clock comparison. Pin it, do not inherit the host.
    try:
        ts=(datetime.datetime.fromisoformat(dt.split(".")[0])
            .replace(tzinfo=datetime.timezone.utc).timestamp())
    except Exception: continue
    rows.append((int(ts), int(m.group(1)), b.group(1)))
if not rows:
    raise SystemExit(0)
rows.sort()
# MIRRORS zot_scope_to_boot: newest real boot wins; a host replace reuses the hostname, so boot_id
# is what separates old-host from new-host events.
current=rows[-1][2]
open(os.environ["BOOT_OUT"],"w").write(current)
print("\n".join(f"{t} {p}" for t,p,b in rows if b==current))
')"

n="$(printf '%s\n' "$samples" | grep -c '[0-9]' || true)"
boot="$(cat "$WORK_BOOT" 2>/dev/null || true)"
rows_scoped="$n"
if [[ -z "$boot" ]]; then
  echo "zot-fill-rate[#7341]: TRANSIENT no_real_boot_id rows_env=${rows_env} window=${WINDOW}"
  echo "TRANSIENT: no emission carries a usable boot_id — every row has boot_id=unknown (cloud-init's"
  echo "  /proc fallback), so samples cannot be scoped to a boot. Unscoped, a recut reads as a trend,"
  echo "  the exact defect this probe exists to prevent. Refusing rather than guessing."
  exit 2
fi
if [[ "${n:-0}" -lt 12 ]]; then
  echo "zot-fill-rate[#7341]: TRANSIENT too_few_samples n=${n:-0} rows_env=${rows_env} rows_scoped=${rows_scoped} boot=${boot:0:8} window=${WINDOW}"
  if [[ "${rows_scoped:-0}" -ge 12 ]]; then
    echo "TRANSIENT: ${rows_scoped} rows for this boot but only ${n:-0} parsed — the marker shape may"
    echo "  have changed, or every row carries the pcent=-1 df-failure sentinel. A PARSE problem, not a quiet store."
  else
    echo "TRANSIENT: only ${n:-0} samples for the current boot; too few to fit a fill rate. Expected"
    echo "  shortly after a recut or reboot."
  fi
  exit 2
fi

read -r verdict detail <<<"$(printf '%s\n' "$samples" | python3 -c '
import sys, os, time
pmax=float(os.environ["PCENT_MAX"]); horizon=float(os.environ["HORIZON_DAYS"])
min_span=float(os.environ["MIN_SPAN_HOURS"])/24.0
max_age=float(os.environ["MAX_AGE_MIN"])*60.0
drop=float(os.environ["DROP_PP"])
pts=sorted(tuple(map(int,l.split())) for l in sys.stdin if l.strip())

# STALENESS first: everything below reads the newest sample as the current state, which holds only
# if it IS current. A dead host keeps 48h of low-flat history in the window and used to PASS.
age=time.time()-pts[-1][0]
if age > max_age:
    print(f"TRANSIENT newest_sample_{age/60:.0f}min_old_over_{max_age/60:.0f}min_pcent={pts[-1][1]}")
    raise SystemExit(0)

# GUARD 4 -- SEGMENT ON THE LAST WIPE. A reclaim inside one boot is a step, not a trend, and
# fitting across it yields a large negative slope that sails through every threshold below.
# A drop counts as a reclaim only if enough samples FOLLOW it to confirm the new level held.
# Without that, a single df-resolved-to-root outlier reads as a reclaim, the fit restarts on two
# samples, and a 95%-full store returns TRANSIENT instead of FAIL. Sustained drop -> segment;
# lone outlier -> leave it to the median in guard 5.
cut=0
for i in range(1,len(pts)):
    if pts[i-1][1]-pts[i][1] >= drop and len(pts)-i >= 12:
        cut=i
seg=pts[cut:]
segmented = cut > 0
if len(seg) < 12:
    print(f"TRANSIENT reclaim_at_sample_{cut}_left_{len(seg)}_samples_under_12")
    raise SystemExit(0)

t0=seg[0][0]
xs=[(t-t0)/86400.0 for t,_ in seg]; ys=[float(p) for _,p in seg]
span=xs[-1]
if span < min_span:
    tag = "since_reclaim" if segmented else "of_history"
    print(f"TRANSIENT span={span*24:.1f}h_{tag}_under_{min_span*24:.0f}h_pcent={ys[-1]:.0f}")
    raise SystemExit(0)

# GUARD 5 -- cur is the MEDIAN of the trailing hour (12 five-minute beats), so one df-resolved-to-
# root reading cannot flip the verdict. The max over that window is reported too: if they diverge
# the reading is unstable and the operator should see both.
tail=sorted(ys[-12:])
cur=tail[len(tail)//2]
mx_tail=max(ys[-12:])

mx=sum(xs)/len(xs); my=sum(ys)/len(ys)
den=sum((x-mx)**2 for x in xs)
slope=(sum((x-mx)*(y-my) for x,y in zip(xs,ys))/den) if den else 0.0
proj=cur+slope*horizon
ends=f"first={ys[0]:.0f}_last={ys[-1]:.0f}_median12={cur:.0f}_max12={mx_tail:.0f}_span={span*24:.0f}h"
if segmented: ends += f"_fit_from_reclaim@{cut}"
if cur >= pmax:
    print(f"FAIL pcent={cur:.0f}_at_or_over_{pmax:.0f}_slope={slope:+.2f}pp/day_{ends}")
elif slope > 0 and proj >= pmax:
    days=(pmax-cur)/slope
    print(f"FAIL pcent={cur:.0f}_slope={slope:+.2f}pp/day_projects_{pmax:.0f}_in_{days:.1f}d_{ends}")
else:
    print(f"PASS pcent={cur:.0f}_slope={slope:+.2f}pp/day_proj{horizon:.0f}d={proj:.0f}_{ends}")
')"

# ── ATTRIBUTION LEAD (#7456 item b) ──────────────────────────────────────────────────────────
# WHY IT LIVES HERE AND NOT IN ITS OWN PROBE. This answers "why is the store filling?" — the
# question #7341 criterion 2 asks and the recut reset before it was answered. It was originally
# planned as a standalone scripts/zot-gc-attribution.sh with its own exit-1 stall verdict; review
# established that script could never RUN (sweep-followthroughs.sh canonicalizes every directive's
# script= under scripts/followthroughs/ and rejects anything outside), and that a stall VERDICT is
# not defensible on this channel at all — see the three false-positive paths below. Printed from
# the FAIL arm it fires exactly when the detector fires, needs no vehicle, and carries no
# authority it cannot support.
#
# IT IS A LEAD, NOT A VERDICT, AND THAT IS THE SAFETY ARGUMENT. Three independent mechanisms make
# an unmatched start indistinguishable from a stall:
#   1. Shipper-side loss. The four gc classes are cap-exempt against their OWN 17-per-tick ceiling
#      and drop past it; a redact failure, a sanitize-to-empty, a POST "stop at the hole" or a
#      cursor invalidation each removes a completion while its start survives. So the drop count
#      is printed BESIDE the unmatched set rather than left for the reader to go find.
#   2. --limit truncation. betterstack-query.sh is ORDER BY dt DESC LIMIT n inside, ASC outside,
#      so truncation drops the window's OLDEST rows first: starts vanish, completions remain.
#   3. Window edges. gc is hourly; a start near the trailing edge has not had time to complete.
# Reporting counts and letting the operator judge is honest under all three. Exiting 1 on them
# would not be, and this probe's exit code is already spoken for by the fill-rate slope.
#
# ANCHORING. sanitize() in cloud-init-registry.yml strips ONLY quotes and backslashes, so commas,
# colons and braces survive: the payload is comma-separated key:value with unescaped colons INSIDE
# values (caller:.../gc.go:109). It is not JSON and must not be split on ':'. The repo is read from
# the parsed message FIELD, anchored through {time:...,level:<word>,message:, never from the whole
# line — a header value can otherwise carry ",message:executing gc ... for /var/lib/zot/x/phantom"
# and mint a repository that never completes. The envelope anchor keeps its TRAILING SPACE, or
# host=soleur-registry-2 matches (zot-log-channel-7440.sh:166 carries the same delimiter).
ZOT_ATTR_HOST="${ZOT_ATTR_HOST:-soleur-registry}"
attribution_lead() {
  local aerr aperr araw arc prc
  aerr="$(mktemp)" || { echo "  attribution_unavailable: mktemp failed (no query was attempted)"; return 0; }
  aperr="$(mktemp)" || { rm -f "$aerr"; echo "  attribution_unavailable: mktemp failed (no query was attempted)"; return 0; }
  araw="$("$QUERY" --since "$WINDOW" --grep SOLEUR_ZOT_LOG --limit 5000 2>"$aerr")"; arc=$?
  if (( arc != 0 )); then
    echo "  attribution_unavailable: the gc-channel query exited ${arc}: $(head -c 300 "$aerr" | tr '\n\r\t' '   ')"
    rm -f "$aerr" "$aperr"
    return 0
  fi
  rm -f "$aerr"
  # Python stderr is CAPTURED, not discarded. `2>/dev/null` here would be the same defect this
  # change removes from zot-log-channel-7440.sh's run_query twelve lines of diff away, and the one
  # this file's own header at the query call already documents as a measured incident.
  printf '%s\n' "$araw" | ZOT_ATTR_HOST="$ZOT_ATTR_HOST" python3 -c '
import sys, json, os, re
ENV = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=" + os.environ["ZOT_ATTR_HOST"] + " "  # trailing space: load-bearing
# FIELD-SCANNING, NOT POSITIONAL. An earlier form required `level:` to be field 2
# (`^\{[^,]*,level:[a-z]+,message:`). That matches the row measured 2026-08-12, whose first field
# is `time:`, but it is pinned to one field ORDER — a gc call site emitting message earlier or
# later silently NOMATCHes, and the terminal state below would then read as "gc is fine". Scan
# comma-delimited fields for the message field instead, and terminate the repo on a comma OR
# end-of-string: sanitize() truncates at 800 chars with NO marker, so the trailing comma a
# positional anchor depends on is not guaranteed to survive.
START_LIT = "executing gc of orphaned blobs for "
DONE_LIT  = "gc successfully completed for "
def msg_field(payload):
    for f in payload.lstrip("{").rstrip("}").split(","):
        if f.startswith("message:"):
            return f[len("message:"):]
    return None
from collections import Counter
starts, dones = Counter(), Counter()
n_patch = 0
drop_sum = 0; drop_markers = 0; drop_unknown = 0
rows_in = rows_decoded = rows_envelope = 0
DROP_N = re.compile(r"^SOLEUR_ZOT_LOG_DROPPED n=([0-9]+|unknown)\b")
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    rows_in += 1
    try:
        outer = json.loads(line)
        raw = outer.get("raw", "")
        inner = raw if isinstance(raw, dict) else json.loads(raw)
        msg = inner.get("message", "")
    except Exception:
        continue
    if not isinstance(msg, str): continue
    rows_decoded += 1
    d = DROP_N.match(msg)
    if d:
        drop_markers += 1
        # The MARKER count is not the ROW count. n= is the number of rows that tick discarded, and
        # on the cursor_invalidated path the producer emits the literal `unknown` because the lost
        # span is genuinely unbounded. Counting markers rendered n=417 as "1" -- two orders of
        # magnitude wrong in exactly the case the confound exists to surface.
        if d.group(1) == "unknown": drop_unknown += 1
        else: drop_sum += int(d.group(1))
        continue
    if not msg.startswith(ENV): continue
    rows_envelope += 1
    mf = msg_field(msg[len(ENV):])
    if mf is None: continue
    if mf.startswith(START_LIT): starts[mf[len(START_LIT):]] += 1; continue
    if mf.startswith(DONE_LIT):  dones[mf[len(DONE_LIT):]] += 1;  continue
    if mf.startswith("PatchBlobUpload"): n_patch += 1
lagging = sorted(r for r in starts if dones[r] < starts[r])
drop_txt = str(drop_sum) + ("+unbounded" if drop_unknown else "")
print("  gc_start_events=%d gc_completion_events=%d over %d repo(s); patch_blob_upload=%d dropped_rows=%s (markers=%d)"
      % (sum(starts.values()), sum(dones.values()), len(set(starts) | set(dones)), n_patch, drop_txt, drop_markers))
print("  rows_in=%d rows_decoded=%d rows_envelope=%d%s"
      % (rows_in, rows_decoded, rows_envelope, "  LIMIT REACHED (window truncated)" if rows_in >= 5000 else ""))
if lagging:
    shown = ["%s %d/%d" % (re.sub(r"[^A-Za-z0-9._-]", "?", r.rsplit("/", 1)[-1])[:48], dones[r], starts[r]) for r in lagging[:5]]
    more = "" if len(lagging) <= 5 else " (+%d more)" % (len(lagging) - 5)
    print("  repos completing FEWER gc cycles than they started (done/started): %s%s"
          % (", ".join(shown), more))
    print("  A LEAD, NOT A VERDICT: dropped_rows above can remove a completion while its start")
    print("  survives, and the trailing window edge cuts gc cycles that had not finished yet.")
    print("  zot#4235 is the standing suspect (gc completing for one repo and never another);")
    print("  .uploads/ staging is the other.")
elif sum(starts.values()) == 0:
    # NOT an exoneration. starts==dones==0 is also what a dead shipper, an unparseable row shape
    # and a hostname change all produce, so the earlier "growth is not a gc stall" line asserted a
    # negative the parse cannot support -- and asserted it hardest when the channel was down.
    print("  NO gc start rows were parsed in this window. This is NOT evidence that gc is healthy:")
    print("  a silent shipper, a changed host token or a drifted row shape all land here. Check the")
    print("  channel first: bash scripts/followthroughs/zot-log-channel-7440.sh")
else:
    print("  every repo completed at least as many gc cycles as it started; not a gc stall.")
' 2>"$aperr"; prc=$?
  if (( prc != 0 )); then
    echo "  attribution_unavailable: the gc rows could not be parsed (python exited ${prc}): $(head -c 300 "$aperr" | tr '\n\r\t' '   ')"
  fi
  rm -f "$aperr"
  return 0
}

# boot= on EVERY verdict: the correctness argument of this check is boot scoping, so the artifact
# an operator reads must say which boot was measured, or a stale-vs-recut ambiguity is not
# checkable from the issue comment alone.
echo "zot-fill-rate[#7341]: ${verdict} ${detail} samples=${n} boot=${boot:0:8} window=${WINDOW}"
case "$verdict" in
  PASS) exit 0 ;;
  FAIL) echo "The store is refilling toward the threshold. zot#4235 is unfixed in v2.1.20; also weigh the orphaned .uploads/ lead (i/o timeout during PatchBlobUpload cleanup, observed 2026-08-10)."
        attribution_lead || true
        exit 1 ;;
  TRANSIENT) echo "TRANSIENT: the store's state could not be established. NOT a pass."; exit 2 ;;
  *)    echo "TRANSIENT: could not classify — the verdict stage produced no parseable output, most likely a python failure whose traceback is above."; exit 2 ;;
esac
