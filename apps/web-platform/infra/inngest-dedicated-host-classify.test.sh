#!/usr/bin/env bash
# inngest-dedicated-host-classify.test.sh (#7674) — unit tests for the pure classifier that
# gives SOLEUR_INNGEST_SERVER_PROBE its first consumer.
#
# WHY THIS SUITE EXISTS. The marker had been emitted hourly and read by NOTHING: measured
# 2026-08-25, the dedicated host had been `server_active=inactive` for 5.4 days on a single
# unchanged boot_id, and every one of those rows also carried `cutover_flag=rolled-back` — the
# cause, sitting in the same line as the symptom, for 130 consecutive hours. A dead dedicated
# host was invisible by construction because nothing read the row.
#
# The classifier is extracted (rather than inlined in the workflow) for the reason
# inngest-liveness-classify.sh was: a verdict that cannot be driven RED is not a verdict.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUT="$REPO_ROOT/scripts/inngest-dedicated-host-classify.sh"
WF="$REPO_ROOT/.github/workflows/scheduled-inngest-health.yml"

PASS=0; FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

# SELF-TEST of the assertion helper. A neutered `assert` reports every row below as a PASS and
# the pass COUNT is not a tell, because PASS increments on the same branch either way.
_ST_P=$PASS; _ST_F=$FAIL
assert "self-test: a FALSE condition fails (expected FAIL below)" "false"
if [[ "$FAIL" -ne $((_ST_F + 1)) || "$PASS" -ne "$_ST_P" ]]; then
  echo "  FATAL: assert() does not fail on a false condition — every row in this suite is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (assert self-test OK — deliberate FAIL above is expected and subtracted)"

echo "== SUT presence =="
assert "classifier exists" "[[ -f '$SUT' ]]"
# shellcheck source=/dev/null
. "$SUT"
assert "classify_dedicated_host() is defined after sourcing" "declare -F classify_dedicated_host >/dev/null"

# --- (a) THE DECISION TABLE ------------------------------------------------------------------
EV=0
c_case() { # $1 desc, $2 rowcount-or-sentinel, $3 server_active, $4 http_code, $5 cutover_flag, $6 expected
  local got; got="$(classify_dedicated_host "$2" "$3" "$4" "$5")"
  EV=$((EV + 1))
  assert "classify: $1 -> $6" "[[ '$got' == '$6' ]]"
}

c_case "serving host is healthy"                    "1" "active"   "200" "done"         "healthy"
# The brake case — TODAY's measured state. It must name the flag, not report health, and not
# be confused with an unexplained stop: the remediations are completely different.
c_case "inactive under a standing rollback brake"   "1" "inactive" "000" "rolled-back"  "stopped-by-brake"
c_case "inactive under an in-flight rollback"       "1" "inactive" "000" "rollback"     "stopped-by-brake"
# Unexplained stop: the flag does NOT explain it, so this is a genuine unknown.
c_case "inactive with no brake is not-serving"      "1" "inactive" "000" "done"         "not-serving"
c_case "inactive while armed is not-serving"        "1" "inactive" "000" "armed"        "not-serving"
c_case "failed unit with no brake is not-serving"   "1" "failed"   "000" "unset"        "not-serving"
# A brake flag must NOT launder a host that is actually serving into a non-healthy verdict,
# and must not launder a 500 into health either.
c_case "active but non-200 is not-serving"          "1" "active"   "500" "done"         "not-serving"
# ABSENCE IS NEVER HEALTH. This is the probe_unavailable discipline the sibling classifier
# exists to enforce: a missing signal must not read as a working one.
c_case "no probe row at all is probe-unavailable"   "0" "" "" ""                        "probe-unavailable"
c_case "an unreadable query is probe-unavailable"   "__UNREADABLE__" "" "" ""           "probe-unavailable"
c_case "a non-decimal rowcount is probe-unavailable" "n/a" "active" "200" "done"        "probe-unavailable"
c_case "rows present but fields empty is probe-unavailable" "1" "" "" ""                "probe-unavailable"
assert "classifier scenarios actually dispatched (>=11)" "[[ '$EV' -ge 11 ]]"

# HARNESS CANARY. A c_case that stopped comparing against the real function would report every
# row above as a PASS; prove it can FAIL, then subtract.
_C_P=$PASS; _C_F=$FAIL
c_case "harness canary: a deliberately wrong expectation MUST fail (expected FAIL below)" \
  "1" "active" "200" "done" "not-serving"
if [[ "$FAIL" -ne $((_C_F + 1)) || "$PASS" -ne "$_C_P" ]]; then
  echo "  FATAL: c_case does not compare against classify_dedicated_host — every row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (c_case harness canary OK — deliberate FAIL above is expected and subtracted)"

# --- (b) THE NO-RESTART CONTRACT, STRUCTURALLY ------------------------------------------------
# The workflow auto-dispatches restart-inngest-server.yml, which is LB-routed to the WEB host.
# A dedicated-host verdict reaching that dispatch would fight the standing brake every 15
# minutes with a restart aimed at the wrong host that cannot fix the condition.
#
# This is asserted the strongest available way: the dispatch condition is an allowlist of two
# liveness modes, and NO dedicated-host verdict token appears anywhere in it. That is stronger
# than "the arm sets no failure_mode", because it holds even if a future edit wires one.
DISPATCH_IF=$(grep -n "if: (steps.effmode.outputs.failure_mode == 'inngest_down'" "$WF" | head -1) || true
assert "the restart dispatch condition still exists (non-vacuity for the rows below)" \
  "[[ -n '$DISPATCH_IF' ]]"
# `healthy` is deliberately NOT in this list: it is not a dedicated-host-specific token and it
# is a SUBSTRING of the legitimate liveness mode `inngest_unhealthy`, so asserting on it would
# match the real dispatch condition and fail for a reason that has nothing to do with this arm.
# That is the bare-token trap (cq-assert-anchor-not-bare-token) — the tokens below are all
# hyphenated verdicts that no liveness mode can contain.
for v in stopped-by-brake not-serving probe-unavailable dedicated_host DEDICATED; do
  assert "restart dispatch cannot see the '$v' verdict" \
    "! grep -qE \"^ *if: .*failure_mode == '[^']*${v}\" '$WF'"
done
# And the arm must not write the variable the dispatch reads.
assert "the dedicated-host arm never sets failure_mode (cannot reach the restart path)" \
  "! grep -qE 'DEDICATED_VERDICT.*failure_mode|failure_mode.*DEDICATED_VERDICT' '$WF'"

# --- (c) ASSEMBLY: the arm is wired, isolates the host, and carries the cause ------------------
assert "the workflow sources the classifier (no inlined second copy)" \
  "grep -qF 'scripts/inngest-dedicated-host-classify.sh' '$WF'"
assert "the workflow reads SOLEUR_INNGEST_SERVER_PROBE (the marker gains a consumer)" \
  "grep -qF 'SOLEUR_INNGEST_SERVER_PROBE' '$WF'"
# HOST ISOLATION. inngest-server-probe.sh is the SHARED renderer for the dedicated host AND
# web-1, and vector.toml states all hosts multiplex into ONE Logs source with host_name the
# sole discriminator. web-1 legitimately reports cutover_flag=unknown; counting its rows as the
# dedicated host's would make this arm report health for the wrong machine.
assert "the arm isolates on the host field, never a bare payload substring" \
  "grep -qF 'host_name' '$WF'"
# `raw` is DOUBLE-ENCODED in ClickHouse: a "host_name":"..." literal matched against the outer
# row matches NOTHING, EVER. The arm must decode before it matches or it reads 0 rows forever
# and reports probe-unavailable permanently.
assert "the arm decodes .raw before matching (raw is double-encoded)" \
  "grep -qE 'fromjson|\\.raw' '$WF'"
assert "the arm carries cutover_flag into its alert (the cause travels with the alarm)" \
  "grep -qF 'cutover_flag' '$WF'"
assert "the arm has its own issue class, distinct from [ci/inngest-down]" \
  "grep -qF 'ci/inngest-dedicated-host' '$WF'"
assert "the arm does not pollute the [ci/inngest-down] age gate" \
  "! grep -qE 'ci/inngest-dedicated-host.*age|agegate.*dedicated' '$WF'"
assert "the three BETTERSTACK_QUERY_* secrets are wired into the workflow" \
  "grep -qF 'BETTERSTACK_QUERY_HOST' '$WF' && grep -qF 'BETTERSTACK_QUERY_USERNAME' '$WF' && grep -qF 'BETTERSTACK_QUERY_PASSWORD' '$WF'"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
# WHOLE-SUITE ANTI-DELETION FLOOR. The only merge gate is `FAIL -gt 0`, so a deleted or skipped
# assertion is otherwise indistinguishable from a clean run.
if [[ "$PASS" -lt 27 ]]; then
  echo "  FAIL: suite dispatched $PASS assertions, floor is 27 — an assertion was removed or skipped."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
echo "  PASS: anti-deletion floor ($PASS >= 27 assertions dispatched)"
