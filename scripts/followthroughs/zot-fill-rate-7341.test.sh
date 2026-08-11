#!/usr/bin/env bash
# Exit-code harness for zot-fill-rate-7341.sh (#7341).
#
# WHY THIS EXISTS, SPECIFICALLY. The first live run of the probe returned
#   PASS pcent=8 slope=-58.48pp/day proj14d=-811
# against a 72h window that straddled the 2026-08-10 recut. That is not a fill rate: the
# regression fitted one line through the OLD 100%-full volume and the NEW empty one, turning a
# WIPE into a trend. It PASSED — the dangerous direction — and no threshold in the script could
# have caught it, because the number was arithmetically correct and semantically meaningless.
#
# So case 1 below is the regression test for exactly that input shape, and it is the reason the
# file exists. The rest of the cases exist so case 1 cannot be satisfied by a probe that has simply
# stopped returning PASS at all: a check that never passes is not a check.
#
# FIXTURES ARE SYNTHESIZED (cq-test-fixtures-synthesized-only). The marker FIELD SHAPE mirrors a
# measured SOLEUR_ZOT_DISK line, but every value here is fabricated — the boot_ids are obvious
# placeholders and no production reading is transcribed.
#
# THE SEAM is ZOT_FILL_QUERY, which the probe honours in place of the absolute path to
# betterstack-query.sh. The PATH-stub trick the sibling soaks use cannot reach an absolute path.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/zot-fill-rate-7341.sh"
fails=0
checks=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub emits JSONL exactly as betterstack-query.sh does: one object per line, `dt` plus a
# `raw` blob containing the marker. SPEC is a semicolon-separated list of
# "<boot_id>,<hours_ago_start>,<hours_ago_end>,<pcent_start>,<pcent_end>,<count>" segments.
cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
python3 -c '
import os, json, datetime
now = datetime.datetime.now()
rows = []
for seg in os.environ["SPEC"].split(";"):
    if not seg.strip(): continue
    boot, h0, h1, p0, p1, n = seg.split(",")
    h0, h1, p0, p1, n = float(h0), float(h1), float(p0), float(p1), int(n)
    for i in range(n):
        f = i / (n - 1) if n > 1 else 0.0
        t = now - datetime.timedelta(hours=h0 + (h1 - h0) * f)
        p = round(p0 + (p1 - p0) * f)
        raw = ("SOLEUR_ZOT_DISK pcent=%d fs_size_gb=59 zot_restarts=0 zot_oom_kills=0 "
               "state_status=running boot_id=%s zot_image_digest=deadbeefcafe" % (p, boot))
        rows.append({"dt": t.strftime("%Y-%m-%d %H:%M:%S.%f"), "raw": raw})
rows.sort(key=lambda r: r["dt"])
for r in rows: print(json.dumps(r))
'
STUB
chmod +x "$WORK/stub-query"

# run <spec> <stub_rc> -> sets OUT / RC
run() {
  OUT="$(SPEC="$1" STUB_RC="${2:-0}" ZOT_FILL_QUERY="$WORK/stub-query" bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { # expect <label> <want_rc> <want_substr>
  local label="$1" want_rc="$2" want_sub="$3"
  if [[ "$RC" != "$want_rc" ]]; then
    fail "$label — wanted rc=$want_rc, got rc=$RC. Output: $OUT"; return
  fi
  if [[ -n "$want_sub" && "$OUT" != *"$want_sub"* ]]; then
    fail "$label — rc correct but output lacks '$want_sub'. Output: $OUT"; return
  fi
  pass "$label (rc=$RC)"
}

echo "zot-fill-rate-7341 harness"

# 1. THE REGRESSION. Old boot pinned at 100% for two days, then a recut and a fresh boot at 5%.
#    Unscoped, the fit is hugely negative and reports PASS. Scoped to the current boot, the new
#    boot has only 6h of history, so the only honest answer is TRANSIENT.
run "bootOLD-aaaa,72,10,100,100,200;bootNEW-bbbb,6,0,5,5,72"
expect "recut straddle does NOT pass on a wipe-as-trend fit" 2 "span"
if [[ "$OUT" == *"-5"*"pp/day"* || "$OUT" == *"proj14d=-"* ]]; then
  fail "recut straddle — a wipe-derived negative slope leaked into the verdict: $OUT"
else
  pass "recut straddle — no wipe-derived slope in the verdict"
fi

# 2. Healthy: one boot, 48h, flat and low. The probe MUST be able to pass, or case 1 is vacuous.
run "bootNEW-bbbb,48,0,6,8,144"
expect "flat low single boot passes" 0 "PASS"

# 3. Refilling: one boot, 48h, 10 -> 40. Slope ~15pp/day projects past 85 well inside 14 days.
run "bootNEW-bbbb,48,0,10,40,144"
expect "rising toward the threshold fails" 1 "projects"

# 4. Already breached, and FLAT — so only the level test can catch it. Guards the `cur >= pmax`
#    arm independently of the slope arm.
run "bootNEW-bbbb,48,0,92,92,144"
expect "at-or-over threshold fails even when flat" 1 "at_or_over"

# 5. Short span, plenty of samples. The count floor alone would admit this; the span floor is what
#    rejects it. 60 samples across 2h is precisely the freshly-recut shape.
run "bootNEW-bbbb,2,0,5,5,60"
expect "short span with a passing sample count is TRANSIENT" 2 "under_24h"

# 6. Too few samples outright.
run "bootNEW-bbbb,48,0,5,5,4"
expect "too few samples is TRANSIENT" 2 "cannot compute"

# 7. Transport failure must never read as health.
run "bootNEW-bbbb,48,0,5,5,144" 7
expect "query transport failure is TRANSIENT" 2 "transport"

# 8. A rise confined to the OLD boot must not be inherited by the new one. The inverse of case 1:
#    scoping has to drop stale history in the FAIL direction too, not just the PASS direction.
run "bootOLD-aaaa,72,26,10,80,120;bootNEW-bbbb,48,0,6,7,144"
expect "a rise on the previous boot does not condemn the current one" 0 "PASS"

# Anti-vacuity floor: if a refactor drops cases, the count fails even when every remaining case
# passes.
MIN_CHECKS=9
if (( checks < MIN_CHECKS )); then
  echo "FAIL: only $checks assertions ran, expected >= $MIN_CHECKS" >&2
  fails=$((fails + 1))
fi

echo "zot-fill-rate-7341: $((checks - fails))/$checks passed"
(( fails == 0 )) || exit 1
