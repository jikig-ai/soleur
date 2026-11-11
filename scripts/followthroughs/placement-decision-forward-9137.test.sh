#!/usr/bin/env bash
# Fixture suite for placement-decision-forward-9137.sh (#12587 AC12 soak probe).
#
# PROPERTY. The probe exits 0 iff journald rows emitted by the
# `soleur-web-platform` container carry `message_json` placement_decision events
# showing BOTH decision=forward with host_ip != 10.0.1.10 AND decision=execute
# with host_ip = 10.0.1.10. Rows that would satisfy a reverted field read —
# SYSLOG_IDENTIFIER isolation, .message grep — must NOT satisfy either arm:
#   * the app container runs `--log-driver journald` with no `--log-opt tag`, so
#     journald SYSLOG_IDENTIFIER is the rotating container short ID and
#     CONTAINER_NAME carries the app name;
#   * the structured payload lives in message_json (vector-parsed pino);
#     `.message` in these rows is an unrelated deprecation/quotation line;
#   * doppler webhook rows (SYSLOG_IDENTIFIER=doppler, no CONTAINER_NAME) quote
#     issue/PR text verbatim and are the contamination class field isolation
#     exists to reject.
#
# STUB. PLACEMENT_FT_QUERY points at a stub that cats $WORK/rows.jsonl (mode=ok)
# or exits 3 (mode=fail) — no network, no credentials.
#
# Values are synthesized (cq-test-fixtures-synthesized-only); every dt, container
# id, and host field is fabricated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/placement-decision-forward-9137.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$WORK"

command -v jq >/dev/null || { echo "FATAL: jq required for the fixture builders" >&2; exit 1; }

APP="soleur-web-platform"
EXEC_IP="10.0.1.10"
WEB2_IP="10.0.1.11"

# ── fixture builders ────────────────────────────────────────────────────────
# A placement_decision pino object, as it appears under raw.message_json.
mj() { # <decision> <host_ip> [class]
  printf '{"level":30,"event":"placement_decision","op":"inngest-exec-placement","fnId":"soleur-runtime-cron-example","class":"%s","decision":"%s","host_ip":"%s","msg":"placement_decision"}' \
    "${3:-portable}" "$1" "$2"
}

# A wire row: {dt, raw:"<json-string>"}. Decoded raw carries the journald/docker
# fields the probe isolates on. Pass "-" to omit CONTAINER_NAME / SYSLOG_IDENTIFIER
# / message_json entirely.
row() { # <container_name|-> <syslog_id|-> <message> <message_json|->
  local inner
  inner="$(jq -cn --arg cn "$1" --arg sid "$2" --arg msg "$3" --arg mj "$4" '
    (if $cn  == "-" then {} else {CONTAINER_NAME:$cn}    end)
    + (if $sid == "-" then {} else {SYSLOG_IDENTIFIER:$sid} end)
    + {message:$msg}
    + (if $mj  == "-" then {} else {message_json:($mj | try fromjson catch $mj)} end)')"
  jq -cn --arg raw "$inner" '{dt:"2026-11-11 17:15:05.000000", raw:$raw}'
}

# ── stub transport ──────────────────────────────────────────────────────────
STUB="$WORK/betterstack-query-stub.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="$(cat "$D/mode" 2>/dev/null || echo ok)"
case "$mode" in
  ok) cat "$D/rows.jsonl" ;;
  *) echo "stub: query backend unreachable" >&2; exit 3 ;;
esac
EOF
chmod +x "$STUB"
echo ok > "$WORK/mode"
: > "$WORK/rows.jsonl"

NOEXEC_STUB="$WORK/betterstack-query-noexec.sh"
printf '#!/usr/bin/env bash\necho unreachable\n' > "$NOEXEC_STUB" # deliberately no +x

# ── harness ─────────────────────────────────────────────────────────────────
run_probe() { # <query-path>
  env -i PATH="$PATH" PLACEMENT_FT_QUERY="$1" PLACEMENT_FT_WINDOW=24h \
    bash "$PROBE" 2>&1
}

expect() { # <desc> <want-rc> <needle-or-->
  local desc="$1" want="$2" needle="${3:--}" out rc
  out="$(run_probe "$STUB")"; rc=$?
  if [[ "$rc" != "$want" ]]; then
    fail "$desc — rc=$rc (want $want): ${out:0:200}"; return
  fi
  if [[ "$needle" != "-" ]] && ! grep -qF "$needle" <<<"$out"; then
    fail "$desc — missing '$needle' in: ${out:0:200}"; return
  fi
  pass "$desc"
}

echo "placement-decision-forward-9137 fixture suite"

# 1. MUST-PASS (anti-vacuity floor): both arms present, interleaved with an
#    unrelated container's qualifying-looking rows that must not count.
{
  row "$APP" "e7b1da5ba07c" "deprecation noise" "$(mj execute "$EXEC_IP" portable)"
  row "unrelated-container" "c0102501a54c" "noise" "$(mj forward "$WEB2_IP" host-affine)"
  row "$APP" "3bdb782cb4ab" "deprecation noise" "$(mj forward "$WEB2_IP" host-affine)"
  row "$APP" "e7b1da5ba07c" "noise" "$(mj execute "$EXEC_IP" host-affine)"
} > "$WORK/rows.jsonl"
expect "both arms + unrelated container" 0 "split verified"

# 2. execute arm only → still soaking.
{
  row "$APP" "e7b1da5ba07c" "noise" "$(mj execute "$EXEC_IP" portable)"
} > "$WORK/rows.jsonl"
expect "execute-only" 1 "still soaking"

# 3. forward arm only → still soaking.
{
  row "$APP" "3bdb782cb4ab" "noise" "$(mj forward "$WEB2_IP" host-affine)"
} > "$WORK/rows.jsonl"
expect "forward-only" 1 "still soaking"

# 4. forward that landed ON the exec host does not satisfy the off-exec arm.
{
  row "$APP" "e7b1da5ba07c" "noise" "$(mj forward "$EXEC_IP" host-affine)"
  row "$APP" "e7b1da5ba07c" "noise" "$(mj execute "$EXEC_IP" portable)"
} > "$WORK/rows.jsonl"
expect "forward-on-exec + execute-on-exec" 1 "still soaking"

# 5. doppler webhook contaminant: no CONTAINER_NAME, qualifying structure in
#    both message_json AND message text — must satisfy neither arm.
{
  row "-" "doppler" 'issue body quotes {"event":"placement_decision","decision":"forward","host_ip":"10.0.1.11"}' "$(mj forward "$WEB2_IP" host-affine)"
  row "-" "doppler" 'issue body quotes {"event":"placement_decision","decision":"execute","host_ip":"10.0.1.10"}' "$(mj execute "$EXEC_IP" portable)"
} > "$WORK/rows.jsonl"
expect "doppler contaminant" 1 "still soaking"

# 6. bare-SYSLOG_IDENTIFIER host row: the name sits in SYSLOG_IDENTIFIER (the
#    field a reverted probe would match) but not in CONTAINER_NAME; qualifying
#    payload in message_json and qualifying text in message.
{
  row "-" "$APP" 'note mentions placement_decision {"decision":"forward","host_ip":"10.0.1.11"}' "$(mj forward "$WEB2_IP" host-affine)"
  row "-" "$APP" 'note mentions placement_decision {"decision":"execute","host_ip":"10.0.1.10"}' "$(mj execute "$EXEC_IP" portable)"
} > "$WORK/rows.jsonl"
expect "syslog-id-only contaminant" 1 "still soaking"

# 7. Evidence only inside .message text (a quoted PR-body blob), message_json
#    absent or a bare string — the field a reverted extraction would read.
{
  row "$APP" "e7b1da5ba07c" 'PR quote: {"event":"placement_decision","decision":"forward","host_ip":"10.0.1.11"}' "-"
  row "$APP" "3bdb782cb4ab" 'PR quote: {"event":"placement_decision","decision":"execute","host_ip":"10.0.1.10"}' '"placement_decision string not object"'
} > "$WORK/rows.jsonl"
expect "message-text-only evidence" 1 "still soaking"

# 8. Qualifying rows under a DIFFERENT container name must not count.
{
  row "other-app" "5e113a04025b" "noise" "$(mj forward "$WEB2_IP" host-affine)"
  row "other-app" "5e113a04025b" "noise" "$(mj execute "$EXEC_IP" portable)"
} > "$WORK/rows.jsonl"
expect "wrong-container rows" 1 "still soaking"

# 9. Empty window → still soaking (never vacuous PASS).
: > "$WORK/rows.jsonl"
expect "empty row set" 1 "still soaking"

# 10. Query-layer failure → TRANSIENT (exit 2), do not grade the product.
echo fail > "$WORK/mode"
expect "stub backend down" 2 "TRANSIENT"
echo ok > "$WORK/mode"

# 11. Non-executable transport → TRANSIENT (exit 2).
out="$(run_probe "$NOEXEC_STUB")"; rc=$?
if [[ "$rc" == 2 ]] && grep -qF "TRANSIENT" <<<"$out"; then
  pass "non-executable query stub"
else
  fail "non-executable query stub — rc=$rc: ${out:0:200}"
fi

# Anti-vacuity floor: the suite must have run at least one positive assertion
# (case 1) — a suite that only ever saw exit 1 could be green while the probe
# rejects every row.
if (( passes < 1 )); then
  fail "anti-vacuity: no positive assertion ran"
fi

if (( fails > 0 )); then
  printf 'FAILURES: %d\n' "$fails" >&2
  exit 1
fi
printf 'All fixtures passed. (%d assertions)\n' "$passes"
