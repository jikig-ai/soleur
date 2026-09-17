#!/usr/bin/env bash
# Unit suite for scripts/inngest-host-state.sh — the dedicated-inngest-host state read.
#
# ── WHAT THIS PINS ──────────────────────────────────────────────────────────────────────────
# web-1 emits SOLEUR_INNGEST_SERVER_PROBE with `host_name=soleur-inngest-prd` — measured
# 2026-09-17: `host=soleur-web-platform host_role=web probe_schema=4`. So a filter on the
# marker, or on host_name, reads the WRONG MACHINE while looking entirely correct. T2 is the
# load-bearing case: given ONLY web-1 rows, the SUT must print nothing and exit 4, never
# summarise a peer as though it were the dedicated host.
#
# The second property is that SILENCE IS NOT HEALTH. An empty window exits 4 with an explicit
# "the host is not shipping" message rather than a clean-looking zero-row success — the shape
# that let a 76-minute outage read as "nothing to report".
#
# ── HARNESS CONTRACT ────────────────────────────────────────────────────────────────────────
# Accumulate-then-exit. The Better Stack query is stubbed via INNGEST_STATE_QUERY, so no case
# touches the network, Doppler, or the warehouse. Counters reconcile at the end.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/inngest-host-state.sh"

passes=0
fails=0
CASES_RUN=0
# APPEND-ONLY FAILURE LEDGER (ADR-193) — see the twin block in scripts/ensure-doppler.test.sh.
# `passes + fails == CASES_RUN` is invariant under redirecting fail()'s increment into
# `passes`, which is the one substitution the reconciliation exists to catch. Measured on
# this file: it reported 10 passed / 0 failed, exit 0, while printing `FAIL:` to stderr.
FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# INSTRUMENT SELF-TEST — positive control that both helpers still RECORD, driven before any
# real case so the unwind is a reset rather than a slice.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
# Redirected: the assertion reads the COUNTERS, not the text, so a literal `FAIL:` on
# every green run is pure noise to a human or agent scanning the transcript.
{ pass "instrument self-test: pass() records"
  fail "instrument self-test: fail() records"
} >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record (passes %s->%s, fails %s->%s, ledger %s->%s)\n' \
    "$_iv_p" "$passes" "$_iv_f" "$fails" "$_iv_n" "${#FAILED[@]}" >&2
  exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
BASH_ABS="$(command -v bash)"

# One warehouse row, as betterstack-query.sh emits it: {"dt":…,"raw":"<json string>"}
row() {
  python3 -c '
import json, sys
dt, host, msg = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({"dt": dt, "raw": json.dumps({"host": host, "host_name": "soleur-inngest-prd", "message": msg})}))
' "$1" "$2" "$3"
}

DEDICATED_MSG='SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active redis_active=active instance_id=hetzner-166317708 boot_id=abc cutover_flag=done probe_schema=8 host_role=dedicated redis_keys=442 redis_expires=431 data_mount_src=/dev/sdb data_mount_devid=scsi-0HC_Volume_106261946 data_bytes=58898716 registry_fns=7 flush_latched=true'
WEB1_MSG='SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive redis_active=active instance_id=hetzner-123931471 probe_schema=4 host_role=web redis_keys=n/a'
DEAD_MSG='SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=activating redis_active=active instance_id=hetzner-166317708 probe_schema=8 host_role=dedicated redis_keys=442 registry_fns=__UNREADABLE__ cutover_flag=done'

make_query() {
  cat > "$SANDBOX/q.sh" <<EOF
#!/usr/bin/env bash
# \$4 is the --grep operand in the SUT's call shape.
for a in "\$@"; do
  [[ "\$prev" == "--grep" ]] && G="\$a"
  prev="\$a"
done
if [[ "\$G" == "SOLEUR_INNGEST_SERVER_PROBE" ]]; then cat "$SANDBOX/probe.jsonl" 2>/dev/null; else cat "$SANDBOX/err.jsonl" 2>/dev/null; fi
exit 0
EOF
  chmod +x "$SANDBOX/q.sh"
  : > "$SANDBOX/probe.jsonl"
  : > "$SANDBOX/err.jsonl"
}

run_sut() {
  local out rc=0
  out="$(BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    INNGEST_STATE_QUERY="$SANDBOX/q.sh" "$BASH_ABS" "$SUT" "$@" 2>/dev/null)" || rc=$?
  # VISIBLE SEPARATOR. This was a raw \x01 (SOH) byte embedded literally in the source:
  # it worked, but it is invisible in every diff, review UI and `cat`, and any formatter
  # or editor that normalises control bytes silently collapses the split below into a
  # no-op -- after which `rc` holds the whole output and every `-eq` compare becomes an
  # arithmetic evaluation of prose. A sentinel that survives a round-trip through text
  # tooling costs nothing and cannot fail that way.
  printf '%s\n__RC__=%s\n' "$out" "$rc"
}

echo "T1: a dedicated-host row is summarised and exits 0"
make_query; row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
# `SERVING` IS A SUBSTRING OF `NOT SERVING`. The previous assertion was `grep -q 'SERVING'`,
# which T6's crash-loop fixture satisfies just as well — so T1 and T6 were BOTH green under a
# SUT that never reports a healthy host, and `serving = False` survived the whole suite.
# `SERVING=yes` is the token the SUT now emits precisely so this cannot be matched backwards.
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out" && grep -q 'SERVING=yes' <<<"$out"; then
  pass "dedicated row -> exit 0, summarised, VERDICT SERVING"
else
  fail "expected exit 0 with summary, got rc=$rc out='$out'"
fi

echo "T2: web-1 rows ONLY -> exit 4, empty stdout (the wrong-machine guard)"
make_query; row "2026-09-17 13:00:00" soleur-web-platform "$WEB1_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 4 && -z "$out" ]]; then
  pass "web-1 only -> exit 4 and EMPTY stdout"
else
  fail "expected exit 4 + empty stdout, got rc=$rc out='$out'"
fi

# T3 WAS A TAUTOLOGY. It re-grepped T2's `$out`, which T2 had already asserted was EMPTY, so
# it could not fail unless T2 had already failed — and it still counted toward the floor.
#
# Replaced with the case that isolates ONE conjunct. Every web-1 fixture in this suite fails
# BOTH pin conjuncts at once (host=soleur-web-platform AND host_role=web), so neither is ever
# the sole reason a row is excluded, and each could be deleted with the suite fully green.
# Worse: swapping `r["host"] != "soleur-inngest"` for `r["host_name"] != "soleur-inngest-prd"`
# — verbatim the wrong-machine read this file's header says it exists to prevent — survived
# all ten cases, because row() gives EVERY fixture host_name=soleur-inngest-prd.
#
# This row is host=soleur-web-platform with host_role=dedicated IN THE MESSAGE, so the `host`
# conjunct is the only thing excluding it. Under the host_name swap it is admitted and the
# SUT summarises a peer as the dedicated host.
echo "T3: a web-1 row CLAIMING host_role=dedicated is still excluded (the host conjunct alone)"
make_query
row "2026-09-17 13:00:00" soleur-web-platform \
  'SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active instance_id=hetzner-123931471 probe_schema=8 host_role=dedicated registry_fns=7' \
  > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 4 && -z "$out" ]] ; then
  pass "host-conjunct alone excludes a web-1 row that claims host_role=dedicated"
else
  fail "web-1 row admitted on a host_role claim — the host pin is not load-bearing (rc=$rc out='$out')"
fi

# The mirror image: host=soleur-inngest but host_role=web. Here the host_role conjunct is the
# sole filter, so deleting it admits a row the summary must not describe.
echo "T3b: a dedicated-host row with host_role=web is excluded (the host_role conjunct alone)"
make_query
row "2026-09-17 13:00:00" soleur-inngest \
  'SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active instance_id=hetzner-999 probe_schema=4 host_role=web registry_fns=7' \
  > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 4 && -z "$out" ]]; then
  pass "host_role conjunct alone excludes a host_role=web row"
else
  fail "host_role=web row admitted — the host_role pin is not load-bearing (rc=$rc out='$out')"
fi

echo "T4: a dedicated row mixed in with web-1 rows is still found"
make_query; { row "2026-09-17 12:59:00" soleur-web-platform "$WEB1_MSG"; row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG"; } > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out"; then
  pass "mixed rows -> picks the dedicated host"
else
  fail "expected the dedicated row, got rc=$rc out='$out'"
fi

echo "T5: an EMPTY window is exit 4, not a clean zero-row success (silence != health)"
make_query
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 4 && -z "$out" ]]; then
  pass "no rows -> exit 4, empty stdout"
else
  fail "expected exit 4 on empty window, got rc=$rc out='$out'"
fi

echo "T6: a crash-looping host is NOT SERVING and says so"
make_query; row "2026-09-17 13:00:00" soleur-inngest "$DEAD_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'NOT SERVING' <<<"$out"; then
  pass "activating/000 -> VERDICT NOT SERVING"
else
  fail "expected NOT SERVING, got rc=$rc out='$out'"
fi

echo "T7: missing credentials exit 3 and query nothing"
make_query; row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG" > "$SANDBOX/probe.jsonl"
rc=0
out="$(env -u BETTERSTACK_QUERY_HOST -u BETTERSTACK_QUERY_USERNAME -u BETTERSTACK_QUERY_PASSWORD \
  INNGEST_STATE_QUERY="$SANDBOX/q.sh" "$BASH_ABS" "$SUT" --no-errors 2>/dev/null)" || rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$rc" -eq 3 && -z "$out" ]]; then
  pass "no creds -> exit 3, empty stdout"
else
  fail "expected exit 3, got rc=$rc out='$out'"
fi

echo "T8: the error scan surfaces a BLOCK refusal from the dedicated host"
make_query
row "2026-09-17 13:00:00" soleur-inngest "$DEAD_MSG" > "$SANDBOX/probe.jsonl"
row "2026-09-17 12:59:00" soleur-inngest "BLOCK: cutover flag='done' but this host carries no done-owner marker at /var/lib/inngest-cutover/done-owner — refusing a prod start on an INHERITED done (#7228)" > "$SANDBOX/err.jsonl"
res="$(run_sut)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'done-owner' <<<"$out"; then
  pass "error scan surfaces the #7228 refusal"
else
  fail "expected the BLOCK line in the scan, got rc=$rc out='$out'"
fi

# The ERROR SCAN has its own host pin, and it was pinned by nothing: T8 only ever sends it a
# row that SHOULD appear, so the scan's `host` filter could be swapped to `host_name` — the
# wrong-machine read this whole file exists to prevent — and the suite stayed green. Measured:
# that mutation SURVIVED while the summary block's identical mutation was killed, because the
# summary block has T3/T3b on the exclusion side and the scan had nothing.
#
# The consequence is not cosmetic: web-1's systemd refusals would print under a heading that
# says "dedicated inngest host", which is the report an operator reads mid-outage.
echo "T8b: a refusal from ANOTHER host is excluded from the scan (the scan's own host pin)"
make_query
row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG" > "$SANDBOX/probe.jsonl"
row "2026-09-17 12:59:00" soleur-web-platform "BLOCK: web-1 refusal that must never appear under the dedicated-host heading" > "$SANDBOX/err.jsonl"
res="$(run_sut)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && ! grep -q 'web-1 refusal' <<<"$out"; then
  pass "foreign-host refusal excluded from the error scan"
else
  fail "a peer host's refusal reached the dedicated-host report — rc=$rc out='$out'"
fi

echo "T9: a webhook payload that merely QUOTES host_role=dedicated is not a probe row"
# MEASURED 2026-09-17: inngest-server logs every webhook delivery as JSON carrying the full
# `rawBody`. A GitHub pull_request event whose body quoted `host_role=dedicated` — the PR
# describing THIS script — became the "newest probe row"; every field parsed as absent and the
# summary still printed a confident `VERDICT NOT SERVING` about a healthy host. The fix is an
# anchored startswith, and this case is what keeps it.
make_query
{
  row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG"
  row "2026-09-17 13:15:05" soleur-inngest '{"caller":"api","event":{"data":{"githubEvent":"pull_request","rawBody":"the pin is host_role=dedicated and host=soleur-inngest"}}}'
} > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out" && ! grep -q 'rawBody\|pull_request' <<<"$out"; then
  pass "quoted token ignored; the real probe row is still reported"
else
  fail "webhook payload treated as a probe row — got rc=$rc out='$out'"
fi

echo "T10: an anchored row with no identity fields yields NO verdict (exit 5)"
make_query
row "2026-09-17 13:20:00" soleur-inngest "SOLEUR_INNGEST_SERVER_PROBE host_role=dedicated" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 5 && -z "$out" ]]; then
  pass "unparseable row -> exit 5, no verdict, empty stdout"
else
  fail "expected exit 5 with no verdict, got rc=$rc out='$out'"
fi

# ── THE INSTRUMENT-FAULT PARTITION ─────────────────────────────────────────────────────────
# Until these cases existed the stub ALWAYS exited 0, so the suite was structurally incapable
# of observing what the SUT does when the read fails. Measured 2026-09-17: a query exiting
# non-zero, a missing query binary, a non-JSON response, a python crash and an absent python3
# ALL printed "the host is not shipping to Better Stack (vector down, host down, or never
# booted)" and exited 4 — a confident diagnosis of a production host from a fault in the
# reader. T5 ("empty window -> exit 4") would have LOCKED THAT IN, because it asserts the very
# exit code the conflation produced.
echo "T11: a FAILING query is exit 6 (nothing measured), never the exit-4 host verdict"
make_query
cat > "$SANDBOX/q.sh" <<'QEOF'
#!/usr/bin/env bash
echo "curl: (22) The requested URL returned error: 503 Service Unavailable" >&2
exit 22
QEOF
chmod +x "$SANDBOX/q.sh"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 6 && -z "$out" ]]; then
  pass "query rc!=0 -> exit 6, no host verdict on stdout"
else
  fail "a failed read must be exit 6, got rc=$rc out='$out'"
fi

echo "T12: the exit-6 message must NOT claim the host is not shipping"
make_query
cat > "$SANDBOX/q.sh" <<'QEOF'
#!/usr/bin/env bash
echo "betterstack-query.sh: refusing to send credentials to 'evil.example'" >&2
exit 2
QEOF
chmod +x "$SANDBOX/q.sh"
err_txt="$(BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  INNGEST_STATE_QUERY="$SANDBOX/q.sh" "$BASH_ABS" "$SUT" --no-errors 2>&1 >/dev/null || true)"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'THE READ FAILED' <<<"$err_txt" \
   && grep -q 'NOT a statement about' <<<"$err_txt" \
   && ! grep -q 'host is not shipping' <<<"$err_txt"; then
  pass "a read fault names the read path and never the host"
else
  fail "exit-6 diagnostic wrong or still blames the host: '$err_txt'"
fi

echo "T13: the query's own stderr is surfaced, not discarded"
CASES_RUN=$((CASES_RUN + 1))
if grep -q "refusing to send credentials" <<<"$err_txt"; then
  pass "the underlying query error reaches the operator"
else
  fail "the query's stderr was swallowed — the operator cannot tell what failed"
fi

# ── ROW ORDERING ───────────────────────────────────────────────────────────────────────────
# Every prior fixture had at most ONE row passing the pin, so `rows[-1]` ("the newest") and
# `rows[0]` ("the oldest") were indistinguishable and the index could be truncated freely.
# betterstack-query.sh emits ORDER BY dt ASC, so the LAST row is the newest.
echo "T14: with two dedicated rows, the NEWEST is summarised"
make_query
{ row "2026-09-17 12:00:00" soleur-inngest "${DEDICATED_MSG/instance_id=hetzner-166317708/instance_id=hetzner-OLDEST}"
  row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG"; } > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out" && ! grep -q 'hetzner-OLDEST' <<<"$out"; then
  pass "two rows -> the newest (rows[-1]) is the one summarised"
else
  fail "row ordering not pinned — got rc=$rc out='$out'"
fi

# ── #8015: LISTENING IS NOT SERVING ────────────────────────────────────────────────────────
# A diagnostic boot satisfies server_active=active AND http_code=200 and owns no work.
# scripts/followthroughs/inngest-host-not-serving-7674.sh added registry_fns as a third
# conjunct for exactly this reason; re-deriving the verdict here without it granted SERVING
# to the state #7674 exists to detect. Every prior fixture had both conjuncts agreeing, so
# `and` -> `or`, dropping http_code, and `serving = False` all survived.
echo "T15: a diagnostic boot (active/200 but registry_fns=0) is NOT SERVING"
make_query
row "2026-09-17 13:00:00" soleur-inngest \
  "${DEDICATED_MSG/registry_fns=7/registry_fns=0}" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'SERVING=no' <<<"$out" && grep -q 'owns no work' <<<"$out"; then
  pass "active+200 with registry_fns=0 -> NOT SERVING, named as the diagnostic-boot shape"
else
  fail "a listening-but-idle host read as SERVING (#8015) — rc=$rc out='$out'"
fi

# ── TRAILING k=v CANNOT OVERRIDE A MEASURED FIELD ──────────────────────────────────────────
# `dict(re.findall(...))` keeps the LAST occurrence and scans the whole line, so appended text
# rewrote the fields the summary presents as measured truth. Measured: a host reading
# activating/000 rendered as VERDICT SERVING.
echo "T16: a trailing k=v tail cannot flip the verdict (first-wins parsing)"
make_query
row "2026-09-17 13:00:00" soleur-inngest \
  'SOLEUR_INNGEST_SERVER_PROBE host_role=dedicated probe_schema=8 instance_id=hetzner-166317708 server_active=activating http_code=000 registry_fns=0 detail=upstream server_active=active http_code=200 registry_fns=9' \
  > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'SERVING=no' <<<"$out"; then
  pass "trailing k=v ignored; the measured activating/000 verdict stands"
else
  fail "a trailing tail overrode a measured field — rc=$rc out='$out'"
fi

# ── A USAGE TYPO IS NOT A PRODUCTION OUTAGE ────────────────────────────────────────────────
echo "T17: --since without a unit is a usage error (2), not a host finding"
make_query; row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors --since 90)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 2 && -z "$out" ]]; then
  pass "--since 90 (no unit) -> exit 2, nothing queried"
else
  fail "a --since typo must not reach the warehouse or produce a verdict — rc=$rc out='$out'"
fi

# ── THE EXIT-5 GUARD COVERS EVERY FIELD THE VERDICT READS ──────────────────────────────────
# Widening the guard back to {instance_id, server_active} survived the whole suite, because no
# fixture had a row that carries those two and is MISSING a field the verdict is made of. A row
# missing http_code used to print `http_code=?` beside a confident NOT SERVING — a verdict
# decided by an absence.
# ── THE EXIT-5 GUARD COVERS EVERY FIELD THE VERDICT READS ──────────────────────────────────
# Parameterised over ALL FOUR guard fields, not just the two this PR widened the guard with.
# The first version of this block added a case per NEWLY-ADDED field (http_code, registry_fns)
# and left the two that were already there unpinned — measured: dropping `instance_id` or
# `server_active` from the guard SURVIVED the whole suite at 23/23. That is the fixture-shape
# defect this PR exists to fix, committed inside the fix for it: a suite that covers the delta
# rather than the property. One loop is both fuller coverage and fewer lines than the cases it
# replaces.
#
# The row carries every field EXCEPT the one under test, so each iteration makes that field the
# SOLE reason the guard fires — the same isolate-one-conjunct discipline as T3/T3b.
echo "T18: a row missing ANY field the verdict reads yields NO verdict (exit 5)"
_t18_all='instance_id=hetzner-166317708 server_active=active http_code=200 registry_fns=7'
for _omit in instance_id server_active http_code registry_fns; do
  make_query
  _msg='SOLEUR_INNGEST_SERVER_PROBE host_role=dedicated probe_schema=8'
  for _kv in $_t18_all; do
    [[ "${_kv%%=*}" == "$_omit" ]] && continue
    _msg="$_msg $_kv"
  done
  row "2026-09-17 13:00:00" soleur-inngest "$_msg" > "$SANDBOX/probe.jsonl"
  res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
  rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
  if [[ "$rc" -eq 5 && -z "$out" ]]; then
    pass "guard fires on absent ${_omit} -> exit 5, no verdict"
  else
    fail "a verdict was rendered with ${_omit} absent — rc=$rc out='$out'"
  fi
done

# ── AN UNKNOWN AGE IS NOT A FRESH ONE ──────────────────────────────────────────────────────
# Every fixture used the space-separated dt that parses, so `age_min = None` was unreachable
# and reverting `stale` to `age_min is not None and age_min > 5` survived. With an ISO dt the
# parse fails, and before the fix the bare verdict printed with NO qualifier at all — the
# absence of the `[Nm old]` bracket reads as tidiness, not as a missing measurement.
echo "T19: an unparseable dt is reported as an UNKNOWN age and treated as stale"
make_query
row "2026-09-17T13:00:00.000Z" soleur-inngest "$DEDICATED_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 0 ]] && grep -q 'AGE UNKNOWN' <<<"$out" && grep -q 'STALE' <<<"$out"; then
  pass "unparseable dt -> AGE UNKNOWN + stale qualifier, never a bare verdict"
else
  fail "an unknown age rendered as a fresh reading — rc=$rc out='$out'"
fi

# ── A SUCCESSFUL QUERY CAN STILL RETURN NON-ROWS ───────────────────────────────────────────
# The rc split above catches a query that FAILS. A proxy or CDN error page, or a ClickHouse
# error body, arrives with a ZERO exit and non-row bytes — measured: an HTML 502 body still
# exited 4 and blamed the host after the rc split landed, because "no rows parsed" and "the
# window was empty" were still the same state.
echo "T20: a zero-exit query returning non-row bytes is a read failure, not a host finding"
make_query
cat > "$SANDBOX/q.sh" <<'QEOF'
#!/usr/bin/env bash
echo "<html><head><title>502 Bad Gateway</title></head></html>"
exit 0
QEOF
chmod +x "$SANDBOX/q.sh"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
rc="$(sed -n 's/^__RC__=//p' <<<"$res")"; out="$(sed '/^__RC__=/d' <<<"$res")"
if [[ "$rc" -eq 6 && -z "$out" ]]; then
  pass "non-row payload -> exit 6, no host verdict"
else
  fail "an unparseable payload rendered as a host finding — rc=$rc out='$out'"
fi
# The over-fix control for this is T5, not a case of its own: a genuinely empty window must
# still exit 4. Dropping the `nonempty > 0 and` conjunct is killed by T5 alone (measured), so
# a dedicated case here is byte-identical setup with a strictly weaker assertion.

echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

# printf + exit DIRECTLY, never through pass()/fail(). `[FATAL]` is the sentinel the
# guard-vacuity-floor meta-suite matches on — a bare `FATAL:` is not in its vocabulary.
_min_cases=25
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s — the suite lost coverage\n' \
    "$CASES_RUN" "$_min_cases" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' \
    "$((passes + fails))" "$CASES_RUN" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s ledger entries vs fails=%s — the verdict machinery was tampered with\n' \
    "${#FAILED[@]}" "$fails" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
echo "inngest-host-state: all $passes assertions passed"
