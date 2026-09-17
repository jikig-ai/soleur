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
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); echo "  FAIL: $1" >&2; }

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
  printf '%s%s' "$out" "$rc"
}

echo "T1: a dedicated-host row is summarised and exits 0"
make_query; row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out" && grep -q 'SERVING' <<<"$out"; then
  pass "dedicated row -> exit 0, summarised, VERDICT SERVING"
else
  fail "expected exit 0 with summary, got rc=$rc out='$out'"
fi

echo "T2: web-1 rows ONLY -> exit 4, empty stdout (the wrong-machine guard)"
make_query; row "2026-09-17 13:00:00" soleur-web-platform "$WEB1_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 4 && -z "$out" ]]; then
  pass "web-1 only -> exit 4 and EMPTY stdout"
else
  fail "expected exit 4 + empty stdout, got rc=$rc out='$out'"
fi

echo "T3: specifically, no web-1 field reaches stdout"
if grep -q 'hetzner-123931471\|host_role=web' <<<"$out"; then
  fail "web-1 field leaked — the SUT summarised a peer as the dedicated host"
else
  pass "no web-1 field on stdout"
fi
CASES_RUN=$((CASES_RUN + 1))

echo "T4: a dedicated row mixed in with web-1 rows is still found"
make_query; { row "2026-09-17 12:59:00" soleur-web-platform "$WEB1_MSG"; row "2026-09-17 13:00:00" soleur-inngest "$DEDICATED_MSG"; } > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out"; then
  pass "mixed rows -> picks the dedicated host"
else
  fail "expected the dedicated row, got rc=$rc out='$out'"
fi

echo "T5: an EMPTY window is exit 4, not a clean zero-row success (silence != health)"
make_query
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 4 && -z "$out" ]]; then
  pass "no rows -> exit 4, empty stdout"
else
  fail "expected exit 4 on empty window, got rc=$rc out='$out'"
fi

echo "T6: a crash-looping host is NOT SERVING and says so"
make_query; row "2026-09-17 13:00:00" soleur-inngest "$DEAD_MSG" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
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
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 0 ]] && grep -q 'done-owner' <<<"$out"; then
  pass "error scan surfaces the #7228 refusal"
else
  fail "expected the BLOCK line in the scan, got rc=$rc out='$out'"
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
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 0 ]] && grep -q 'hetzner-166317708' <<<"$out" && ! grep -q 'rawBody\|pull_request' <<<"$out"; then
  pass "quoted token ignored; the real probe row is still reported"
else
  fail "webhook payload treated as a probe row — got rc=$rc out='$out'"
fi

echo "T10: an anchored row with no identity fields yields NO verdict (exit 5)"
make_query
row "2026-09-17 13:20:00" soleur-inngest "SOLEUR_INNGEST_SERVER_PROBE host_role=dedicated" > "$SANDBOX/probe.jsonl"
res="$(run_sut --no-errors)"; CASES_RUN=$((CASES_RUN + 1))
out="${res%$'\001'*}"; rc="${res##*$'\001'}"
if [[ "$rc" -eq 5 && -z "$out" ]]; then
  pass "unparseable row -> exit 5, no verdict, empty stdout"
else
  fail "expected exit 5 with no verdict, got rc=$rc out='$out'"
fi

echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails"
if [[ "$CASES_RUN" -lt 10 ]]; then
  echo "FATAL: expected at least 10 cases, saw $CASES_RUN — suite lost coverage" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  echo "FATAL: $((passes + fails)) verdicts for $CASES_RUN cases — a case decided nothing" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
echo "inngest-host-state: all $passes assertions passed"
