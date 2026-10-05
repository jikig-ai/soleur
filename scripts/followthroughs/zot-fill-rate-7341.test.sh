#!/usr/bin/env bash
# Exit-code harness for zot-fill-rate-7341.sh (#7341).
#
# The probe's exit code auto-closes a P1 disk-exhaustion tracker, so every case below is a way the
# verdict can be wrong in the PASS direction. The first live run returned
#   PASS pcent=8 slope=-58.48pp/day proj14d=-811
# across a window straddling the recut — a wipe fitted as a trend. Case 1 is that input.
#
# FIXTURES ARE PRODUCTION-SHAPED, AND THAT IS LOAD-BEARING. An earlier stub emitted `raw` as a bare
# string; a genuine Better Stack row stores it as a JSON-ENCODED OBJECT, `{"message":"SOLEUR_ZOT_
# DISK …"}`. The difference is not cosmetic — it is what the envelope anchor keys on, so the old
# fixture could not express a contaminating row at all, and a parser hardened to the repo's shared
# invariants scored 3/11 against it. The fixture did not merely fail to falsify the weak parse, it
# BLOCKED the hardening: anyone bringing the probe in line with its own shared library saw 8 red
# and reverted. That is one level worse than "a fixture can only falsify assumptions its author
# did not share", which is what this PR's learning doc is about.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field shape mirror a
# measured emission, every number and id is fabricated.
#
# SPEC segments: "<boot_id>,<h_ago_start>,<h_ago_end>,<pcent_start>,<pcent_end>,<count>", ';'-joined.
# EXTRA:  raw JSONL lines appended verbatim — used for non-envelope contamination.
# TAIL:   appended to every message, for zot_last_err spoof attempts.
# GLITCH: one extra newest sample at this pcent, for the single-bad-reading case.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/zot-fill-rate-7341.sh"
fails=0
passes=0
# `cases` is incremented at the CALL SITE — at the top of expect(), and immediately before each
# inline if/else that resolves to exactly one verdict — and NEVER inside pass()/fail(). That
# placement is the whole substance of the conservation check at the bottom of this file. The
# previous shape incremented `checks` inside BOTH verdict helpers, so it moved WITH the verdict:
# stubbing `fail() { :; }` dropped the row and its count together, the cardinality floor stayed
# satisfied at 29, and a probe auto-closing a P1 disk-exhaustion tracker on a wipe-derived slope
# printed `29/29 passed` and exited 0.
#
# Never increment inside `$( )` — a subshell discards it.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub ASSERTS ITS ARGV before answering. Neither stub did this before, so every
# query-construction mutation stayed green: dropping --grep, adding --no-archive (a ~40-minute hot
# keyhole -> span < 24h -> TRANSIENT forever, which is #6288 verbatim), or shrinking --limit. Those
# are TRANSIENT-direction so they never auto-close, but a probe wedged at TRANSIENT is a tracker
# that never closes and an alarm that never fires.
cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
# The stub DISPATCHES on --grep, because the probe now issues a SECOND query: the attribution
# lead in the FAIL arm reads the SOLEUR_ZOT_LOG channel. Answering both from one fixture would put
# the seam above the code under test — the lead could query the wrong channel and stay green.
# GCROWS is emitted verbatim so a case can inject a contaminating row the parser must reject.
if [[ "$argv" == *"--grep SOLEUR_ZOT_LOG"* ]]; then
  [[ "${GC_RC:-0}" == "0" ]] || exit "${GC_RC}"
  [[ "$argv" == *"--since"* ]] || { echo "stub: attribution query missing --since (argv: $argv)" >&2; exit 64; }
  # `|| [[ -n "$l" ]]` is load-bearing: GCROWS has no trailing newline, so a bare `while read`
  # drops its LAST row — which in these fixtures is the unmatched start under test.
  printf '%s' "${GCROWS:-}" | while IFS= read -r l || [[ -n "$l" ]]; do [[ -n "$l" ]] && printf '%s\n' "$l"; done
  exit 0
fi
[[ "$argv" == *"--grep SOLEUR_ZOT_DISK"* ]] || { echo "stub: missing --grep SOLEUR_ZOT_DISK (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--since"* ]]                || { echo "stub: missing --since (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--no-archive"* ]]           && { echo "stub: --no-archive gives a ~40min hot keyhole" >&2; exit 64; }
lim="$(sed -E 's/.*--limit ([0-9]+).*/\1/' <<<"$argv")"
[[ "$lim" =~ ^[0-9]+$ && "$lim" -ge 1000 ]] || { echo "stub: --limit $lim too small for 72h at 5-min cadence" >&2; exit 64; }
python3 -c '
import os, json, datetime
# UTC, matching what Better Stack emits. Load-bearing: when this read datetime.now() the stub
# shared the local-time assumption of the parser in the probe, the two errors cancelled, and the
# staleness cases passed while production was two hours off. A fixture mirroring the bug is blind
# to it. (No apostrophes in this block: it is single-quoted, so one would terminate it.)
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
tail = os.environ.get("TAIL", "")
rows = []
def emit(t, p, boot):
    msg = ("SOLEUR_ZOT_DISK pcent=%s fs_size_gb=59 zot_restarts=0 zot_oom_kills=0 "
           "state_status=running boot_id=%s zot_image_digest=deadbeefcafe%s" % (p, boot, tail))
    rows.append({"dt": t.strftime("%Y-%m-%d %H:%M:%S.%f"),
                 "raw": json.dumps({"message": msg}, separators=(",", ":"))})
spec = os.environ.get("SPEC", "")
for seg in spec.split(";"):
    if not seg.strip(): continue
    boot, h0, h1, p0, p1, n = seg.split(",")
    h0, h1, p0, p1, n = float(h0), float(h1), float(p0), float(p1), int(n)
    for i in range(n):
        f = i / (n - 1) if n > 1 else 0.0
        emit(now - datetime.timedelta(hours=h0 + (h1 - h0) * f), int(round(p0 + (p1 - p0) * f)), boot)
g = os.environ.get("GLITCH", "")
if g and spec.strip():
    emit(now, int(g), spec.split(";")[-1].split(",")[0])
rows.sort(key=lambda r: r["dt"])
for r in rows: print(json.dumps(r, separators=(",", ":")))
for extra in os.environ.get("EXTRA", "").split("\n"):
    if extra.strip(): print(extra)
'
STUB
chmod +x "$WORK/stub-query"

run() { # run <spec> [stub_rc] [extra] [tail] [glitch] [gcrows] [gc_rc]
  OUT="$(SPEC="$1" STUB_RC="${2:-0}" EXTRA="${3:-}" TAIL="${4:-}" GLITCH="${5:-}" \
         GCROWS="${6:-}" GC_RC="${7:-0}" \
         ZOT_FILL_QUERY="$WORK/stub-query" bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { local l="$1" wrc="$2" wsub="$3"
  # One assertion is about to be decided. Counted HERE, outside pass()/fail(), so it survives a
  # neutered verdict helper and the conservation check below can see the missing verdict.
  cases=$((cases + 1))
  if [[ "$RC" != "$wrc" ]]; then fail "$l — wanted rc=$wrc, got rc=$RC. Output: $OUT"; return; fi
  if [[ -n "$wsub" && "$OUT" != *"$wsub"* ]]; then fail "$l — rc ok but output lacks '$wsub'. Output: $OUT"; return; fi
  pass "$l (rc=$RC)"
}

GOOD=48f1c2ae-0000-4000-8000-000000000001
OLD=48f1c2ae-0000-4000-8000-0000000000ff

echo "zot-fill-rate-7341 harness"

# ── SCOPING ──────────────────────────────────────────────────────────────────────────────────
# 1. THE ORIGINAL DEFECT. Old boot pinned at 100 for two days, recut, fresh boot at 5.
run "$OLD,72,10,100,100,200;$GOOD,6,0,5,5,72"
expect "recut straddle does not fit the wipe as a trend" 2 "span"
cases=$((cases + 1))
if [[ "$OUT" == *"proj14d=-"* ]]; then
  fail "a wipe-derived negative slope leaked into the verdict: $OUT"
else
  pass "no wipe-derived slope in the verdict"
fi

# 2. Healthy baseline. Required, or every negative case is satisfiable by a probe that never passes.
run "$GOOD,48,0,6,8,144"
expect "flat low single boot passes" 0 "PASS"

# 3. boot_id=unknown is cloud-init's /proc fallback, not an identity. Treating it as one merges
#    every boot and reproduces case 1 exactly — measured at PASS slope=-32.44pp/day.
run "unknown,72,10,100,100,200;unknown,6,0,5,5,72"
expect "boot_id=unknown is refused, not treated as a boot" 2 "boot_id=unknown"

# 4. A rise confined to the previous boot must not condemn the current one — scoping has to drop
#    stale history in the FAIL direction too.
run "$OLD,72,26,10,80,120;$GOOD,48,0,6,7,144"
expect "a rise on the previous boot does not condemn the current one" 0 "PASS"

# ── CONTAMINATION ────────────────────────────────────────────────────────────────────────────
# 5. THE ENVELOPE ANCHOR. One GitHub comment quoting a marker line — routine triage on a disk
#    incident — flipped a measured FAIL into PASS: the pasted pcent became `cur`, and the pasted
#    row being newest seized which boot got scoped.
CONTAM='{"dt":"2099-01-01 00:00:00.000000","raw":"{\"body\":\"see SOLEUR_ZOT_DISK pcent=6 boot_id=48f1c2ae-0000-4000-8000-00000000beef in the logs\"}"}'
run "$GOOD,48,0,40,78,144" 0 "$CONTAM"
expect "a pasted marker line cannot overturn a real FAIL" 1 "projects"

# 6. ...and contamination alone, with no genuine emission, is a measured absence — never a pass.
run "" 0 "$CONTAM"
expect "only non-envelope rows is TRANSIENT, not PASS" 2 "no_emission_rows"

# 7. TRUSTED REGION. zot_last_err is free text from zot's own logs, emitted last. Combined with the
#    pcent=-1 df-failure sentinel, an unstripped search walks into the tail and reads it.
run "$GOOD,48,0,6,8,144" 0 "" " zot_last_err={message:cleanup pcent=99 boot_id=deadbeef}"
expect "a crafted zot_last_err tail cannot spoof the verdict fields" 0 "PASS"

# ── THE FIT ──────────────────────────────────────────────────────────────────────────────────
# 8. IN-BOOT RECLAIM. gc reclaiming, .uploads/ cleanup succeeding, a zot CONTAINER restart or an
#    operator delete all free the volume WITHOUT rebooting — same boot_id, same step. Fitting
#    across it reported PASS slope=-31.15pp/day on a store refilling at +20pp/day, which is the
#    zot#4235 signature this probe is named for.
run "$GOOD,72,49,95,95,70;$GOOD,48,0,40,60,144"
expect "a reclaim inside one boot does not mask the refill after it" 1 "fit_from_reclaim"

# 9. A reclaim followed by genuinely flat low usage is healthy and must still pass.
run "$GOOD,72,49,95,95,70;$GOOD,48,0,6,7,144"
expect "a reclaim followed by flat low usage passes" 0 "PASS"

# 10. A reclaim too recent to have a baseline is TRANSIENT, not a pass on two hours of data.
run "$GOOD,72,3,95,95,200;$GOOD,2,0,5,5,24"
expect "a reclaim with too little history after it is TRANSIENT" 2 "TRANSIENT"

# 11. SINGLE BAD READING. df resolves /var/lib/zot to the ROOT filesystem when the volume is
#     detached or mid-remount. One such sample appended to 48h at 95 turned FAIL into PASS pcent=8.
run "$GOOD,48,0,95,95,144" 0 "" "" 8
expect "one spurious low reading does not clear a 95%-full store" 1 "at_or_over"

# 12. Already breached and flat — guards the level arm independently of the slope arm.
run "$GOOD,48,0,92,92,144"
expect "at-or-over threshold fails even when flat" 1 "at_or_over"

# 13. Rising toward the threshold.
run "$GOOD,48,0,10,40,144"
expect "rising toward the threshold fails" 1 "projects"

# ── FLOORS AND PLUMBING ──────────────────────────────────────────────────────────────────────
# 14. Span floor. 60 samples across 2h clears any count floor while extrapolating jitter across two
#     weeks — precisely the freshly-recut shape.
run "$GOOD,2,0,5,5,60"
expect "short span with a passing sample count is TRANSIENT" 2 "under_24h"

# 15. Count floor.
run "$GOOD,48,0,5,5,4"
expect "too few samples is TRANSIENT" 2 "too_few_samples"

# 16. Dead heartbeat. 48h of low-flat history ending 40h ago cleared the span floor and fitted
#     +0.00pp/day — loudest-green exactly when the host is gone.
run "$GOOD,88,40,5,5,144"
expect "a heartbeat that stopped 40h ago is TRANSIENT, not PASS" 2 "min_old_over"

# 17. ...and a live heartbeat is not rejected as stale, so 16 is not satisfiable by a reject-all gate.
run "$GOOD,48,0,6,8,144"
expect "a live heartbeat is not rejected as stale" 0 "PASS"

# 18. Transport failure must never read as health, and must surface the rc.
run "$GOOD,48,0,5,5,144" 7
expect "query transport failure is TRANSIENT" 2 "query_rc=7"

# 19. rc=3 is betterstack-query.sh's credential guard — the likeliest first-run failure, and the
#     one the old `2>/dev/null` destroyed.
run "$GOOD,48,0,5,5,144" 3
expect "the credential-guard rc is named, not collapsed into 'transport'" 2 "credential guard"

# ── ATTRIBUTION LEAD (#7456 item b) ──────────────────────────────────────────────────────────
# The lead answers "why is it filling?" in the same comment the FAIL arm posts. It is
# INFORMATIONAL: it runs after the verdict and must not be able to move the exit code, because a
# stall and a dropped completion row are byte-indistinguishable (see case 24).
ENVP="SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry"
WEB=/var/lib/zot/jikig-ai/soleur-web-platform
BOOTSTRAP=/var/lib/zot/jikig-ai/soleur-inngest-bootstrap
gcrow() { python3 -c 'import json,sys
print(json.dumps({"dt":"2026-08-12 20:54:20.000000",
 "raw":json.dumps({"message":sys.argv[1]},separators=(",",":"))},separators=(",",":")))' "$1"; }
zpay() { printf '{time:2026-08-12T20:54:20.797245158Z,level:info,message:%s,module:gc,caller:zotregistry.dev/zot/v2/pkg/storage/gc/gc.go:109}' "$1"; }

FAILSPEC="$GOOD,48,0,10,40,144"

# 20. The lead CANNOT change the verdict when its own query dies. This is the whole safety
#     argument for putting attribution in a FAIL arm rather than in a probe with its own exit code.
run "$FAILSPEC" 0 "" "" "" "" 3
expect "a dead attribution query leaves the FAIL verdict intact" 1 "attribution_unavailable"

# 21. Paired start/completion is healthy; an unmatched start names its repository. Per-repo is the
#     point: a GLOBAL ratio reads 50% here and looks half-healthy.
GC_OK="$(gcrow "$ENVP $(zpay "executing gc of orphaned blobs for $WEB")")
$(gcrow "$ENVP $(zpay "gc successfully completed for $WEB")")
$(gcrow "$ENVP $(zpay "executing gc of orphaned blobs for $BOOTSTRAP")")"
run "$FAILSPEC" 0 "" "" "" "$GC_OK"
expect "an unmatched gc start names its repository" 1 "soleur-inngest-bootstrap"
cases=$((cases + 1))
if [[ "$OUT" == *"gc_start_events=2 gc_completion_events=1 over 2 repo(s)"* && "$OUT" == *"soleur-inngest-bootstrap 0/1"* ]]
then pass "EVENT counts are 2/1 over 2 repos, and the lagging repo shows done/started"
else fail "expected gc_start_events=2 gc_completion_events=1 with soleur-inngest-bootstrap 0/1. Output: $OUT"
fi

# 22. INJECTION. sanitize() strips only quotes and backslashes, so a header value survives with its
#     commas and colons intact. Anchoring on the parsed message field (level: then message:) is
#     what stops a crafted User-Agent from minting a repository that never completes -> false stall.
GC_INJ="$(gcrow "$ENVP {time:2026-08-12T20:54:20Z,level:info,message:HTTP API,module:http,headers:{User-Agent:[curl,message:executing gc of orphaned blobs for /var/lib/zot/x/phantom]},caller:zotregistry.dev/zot/v2/pkg/api/session.go:92}")"
run "$FAILSPEC" 0 "" "" "" "$GC_INJ"
cases=$((cases + 1))
if [[ "$OUT" != *phantom* ]]
then pass "a header-borne 'executing gc' mints no repository"
else fail "header injection minted a phantom repository. Output: $OUT"
fi

# 23. The drop count travels WITH the unmatched start. Cap-exempt rows have their own 17/tick
#     ceiling, so a dropped completion looks exactly like a stall; printing the confound is the
#     difference between a lead and a wrong answer.
GC_DROP="$GC_OK
$(gcrow "SOLEUR_ZOT_LOG_DROPPED n=3 interval_s=300 boot_id=$GOOD seq=2 cum=5 reason=rate_cap")"
run "$FAILSPEC" 0 "" "" "" "$GC_DROP"
expect "the SUMMED dropped-row count is printed beside the unmatched start" 1 "dropped_rows=3"

# 24. The envelope anchor carries a TRAILING SPACE. Without it host=soleur-registry-2 matches.
GC_HOST2="$(gcrow "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry-2 $(zpay "executing gc of orphaned blobs for /var/lib/zot/x/other")")"
run "$FAILSPEC" 0 "" "" "" "$GC_HOST2"
cases=$((cases + 1))
if [[ "$OUT" == *"rows_envelope=0"* && "$OUT" == *"gc_start_events=0"* ]]
then pass "a neighbouring host's rows are not admitted (trailing-space anchor; rows_envelope=0)"
else fail "host=soleur-registry-2 was admitted. Output: $OUT"
fi

# 25. The lead is FAIL-only: a PASS verdict must not pay for a second query.
run "$GOOD,48,0,6,8,144" 0 "" "" "" "$GC_OK"
cases=$((cases + 1))
if [[ "$RC" == "0" && "$OUT" != *"gc_starts"* ]]
then pass "a PASS verdict does not run the attribution lead"
else fail "the lead ran on PASS (rc=$RC). Output: $OUT"
fi

# 26. NOT AN EXONERATION. starts==dones==0 is also what a dead shipper, a changed host token and a
#     drifted row shape produce. The earlier text asserted "growth is not a gc stall" here — a
#     negative the parse cannot support, asserted hardest exactly when the channel is down.
run "$FAILSPEC" 0 "" "" "" ""
cases=$((cases + 1))
if [[ "$OUT" == *"NOT evidence that gc is healthy"* && "$OUT" != *"growth is not a gc stall"* ]]
then pass "zero parsed gc rows is reported as no-evidence, not as an all-clear"
else fail "an empty parse produced an exoneration. Output: $OUT"
fi

# 27. THE INTERMITTENT SHAPE. Same repo starts 3 gc cycles and completes 1. A set-difference lead
#     reported this HEALTHY (the repo is present in `dones`), which is precisely the zot#4235
#     degradation the lead exists to surface.
GC_LAG="$(gcrow "$ENVP $(zpay "executing gc of orphaned blobs for $WEB")")
$(gcrow "$ENVP $(zpay "executing gc of orphaned blobs for $WEB")")
$(gcrow "$ENVP $(zpay "executing gc of orphaned blobs for $WEB")")
$(gcrow "$ENVP $(zpay "gc successfully completed for $WEB")")"
run "$FAILSPEC" 0 "" "" "" "$GC_LAG"
cases=$((cases + 1))
if [[ "$OUT" == *"soleur-web-platform 1/3"* && "$OUT" != *"not a gc stall"* ]]
then pass "a repo completing 1 of 3 started cycles is reported, not called healthy"
else fail "the intermittent under-completion shape read as healthy. Output: $OUT"
fi

# --- Anti-vacuity floor -----------------------------------------------------------------------
# This harness's own dispatch. A stub that stops emitting, a `run()` that stops invoking the
# probe, an early `return` — any of these leaves the suite asserting nothing about a probe whose
# exit code auto-closes a P1 disk-exhaustion tracker.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never by incrementing `fails`. The previous
# shape did `fails=$((fails + 1))`, and `fails` is exactly what the exit status reads — so
# neutering the verdict machinery silenced the rows AND the floor that exists to notice the
# silence. A floor enforced through the suspect cannot witness the suspect.
#
# Measured from a green run with ZERO slack: 29 assertions (22 expect() rows + 7 inline
# if/else rows). Ratchet upward only.
MIN_CHECKS=29
if (( cases < MIN_CHECKS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CHECKS" >&2
  echo "zot-fill-rate-7341: $passes/$cases passed"
  exit 1
fi

# --- Accounting conservation --------------------------------------------------------------
# The arm that actually catches a neutered verdict helper. The floor above catches "no
# assertions RAN"; it cannot catch "assertions ran and their verdicts were discarded", because
# `cases` keeps its full value when fail() is a no-op. Every assertion records exactly one
# verdict, so passes+fails MUST equal cases. Reported directly for the same reason as the floor.
if (( passes + fails != cases )); then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  if (( passes + fails < cases )); then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a probe failure: add the increment at that call site.\n' >&2
  fi
  echo "zot-fill-rate-7341: $passes/$cases passed"
  exit 1
fi

echo "zot-fill-rate-7341: $passes/$cases passed"
(( fails == 0 )) || exit 1
