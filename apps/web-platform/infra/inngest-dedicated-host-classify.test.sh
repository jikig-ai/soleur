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

# Tempfile ownership (ADR-129): this suite allocates scratch via mktemp, so it must register a
# single owning trap — otherwise nothing removes them if the script dies mid-run. An earlier
# revision used SCRATCH+=() copied from the sibling suite WITHOUT this infrastructure, i.e. it
# recorded paths into an array nothing ever read. lint-trap-tempfile-ownership.py caught it.
SCRATCH=()
scratch_cleanup() { [[ ${#SCRATCH[@]} -gt 0 ]] && rm -rf "${SCRATCH[@]}" 2>/dev/null || true; }
trap scratch_cleanup EXIT

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
# CORRECTED (#7674 review): this asserted on `DEDICATED_VERDICT`, which appears ZERO times in the
# workflow — the arm's variable is `VERDICT`. It could never fail. Assert the real property: the
# arm's $GITHUB_OUTPUT block writes exactly verdict/detail/flag and never failure_mode.
ARM_OUT=$(awk '/^      - name: Dedicated inngest host probe consumer/,/^      - name: Note the known brake/' "$WF" | grep -cE '^ *echo "failure_mode=') || true
assert "#7674 the arm never writes failure_mode (it could then reach the restart dispatch)" \
  "[[ '$ARM_OUT' -eq 0 ]]"
# The restart dispatch must not be wired to the arm's OUTPUT either — the five rows below only
# cover `failure_mode == '<token>'`, but `steps.dedicated.outputs.verdict == '<token>'` is the
# natural way someone would wire this arm in, and it was uncovered.
# The natural way to wire this arm into the restart path is `steps.dedicated.outputs.verdict`,
# which the five failure_mode rows above cannot see. Assert the dispatch condition never mentions
# the arm at all — the strongest available form, and it covers any verdict token.
DISPATCH_LINE=$(grep -nF "if: (steps.effmode.outputs.failure_mode == 'inngest_down'" "$WF" | head -1 | cut -d: -f1) || true
assert "#7674 the restart dispatch condition was located (non-vacuity for the row below)" \
  "[[ -n '$DISPATCH_LINE' ]]"
DISPATCH_TXT=$(sed -n "${DISPATCH_LINE}p" "$WF" 2>/dev/null) || true
assert "#7674 the restart dispatch never reads the dedicated arm (any verdict token)" \
  "! grep -qF 'steps.dedicated' <<<\"\$DISPATCH_TXT\""

# --- (c) ASSEMBLY: the arm is wired, isolates the host, and carries the cause ------------------
assert "the workflow sources the classifier (no inlined second copy)" \
  "grep -qF 'scripts/inngest-dedicated-host-classify.sh' '$WF'"
assert "the workflow reads SOLEUR_INNGEST_SERVER_PROBE (the marker gains a consumer)" \
  "grep -qF 'SOLEUR_INNGEST_SERVER_PROBE' '$WF'"
# HOST ISOLATION. inngest-server-probe.sh is the SHARED renderer for the dedicated host AND
# web-1, and vector.toml states all hosts multiplex into ONE Logs source with host_name the
# sole discriminator. web-1 legitimately reports cutover_flag=unknown; counting its rows as the
# dedicated host's would make this arm report health for the wrong machine.
# Anchored on the FULL conjunction as one string: `grep -qF 'host_name'` passed on the four
# COMMENT occurrences alone, so deleting the only line that isolates would have stayed green.
assert "the arm isolates on BOTH identity fields (anchored on the conjunction, not a bare token)" \
  "grep -qF 'select(.host == env.DEDICATED_HOST and .host_name == env.DEDICATED_HOST_NAME)' '$WF'"
# #6616 is OPEN — "host_name telemetry is lying": a web host has been observed self-labelling
# with the dedicated node's sed-rendered literal. host_name ALONE would let that web host's rows
# be read as this host's state, and the arm auto-CLOSES its issue on a `healthy` verdict — so the
# collision would silently resolve a dedicated-host alarm from the wrong machine's telemetry.
assert '#6616 the arm ALSO isolates on the unforgeable host field (host_name alone can lie)' \
  "grep -qE '^ *DEDICATED_HOST: soleur-inngest\$' '$WF' && grep -qF '.host == env.DEDICATED_HOST' '$WF'"
# `raw` is DOUBLE-ENCODED in ClickHouse: a "host_name":"..." literal matched against the outer
# row matches NOTHING, EVER. The arm must decode before it matches or it reads 0 rows forever
# and reports probe-unavailable permanently.
# `fromjson` also appears in the comments, so the bare form could not fail. Anchor on the -R
# call shape, which a comment does not produce.
assert "the arm decodes with jq -R + double fromjson? (one bad line must not lose the rest)" \
  "grep -qF \"jq -R -r 'fromjson? | .raw? | fromjson?\" '$WF'"
assert "the arm carries cutover_flag into its alert (the cause travels with the alarm)" \
  "grep -qF 'cutover_flag' '$WF'"
assert "the arm has its own issue class, distinct from [ci/inngest-down]" \
  "grep -qF 'ci/inngest-dedicated-host' '$WF'"
assert "the arm does not pollute the [ci/inngest-down] age gate" \
  "! grep -qE 'ci/inngest-dedicated-host.*age|agegate.*dedicated' '$WF'"
# --- (d) THE CONSUMER'S OWN OBSERVABILITY (#7674 review) --------------------------------------
# Every verdict branch keys on an OUTPUT of the probe step. A crashed step writes no outputs, so
# without a branch keyed on its OUTCOME a broken reader is indistinguishable from a healthy host —
# the defect this whole PR exists to fix, one level up.
assert "#7674 a crashed consumer is detected via steps.dedicated.OUTCOME, not its outputs" \
  "grep -qF \"steps.dedicated.outcome != 'success'\" '$WF'"
# Every consumer branch must be reachable on a failing run. A step `if:` with no status function is
# implicitly ANDed with success(), which would skip the branch on 100% of the runs it exists for.
DED_IFS=$(grep -cE "^ *if: always\(\) && steps\.dedicated\." "$WF") || true
assert "#7674 every dedicated-host consumer branch carries always() (>=4, got $DED_IFS)" \
  "[[ '$DED_IFS' -ge 4 ]]"
# operator-digest harvests ONLY action-required. The ci/inngest-* labels are not harvested, so a
# genuine fault without this label is detected and then discarded into a log nobody reads.
assert "#7674 genuine faults carry action-required (operator-digest harvests only that label)" \
  "grep -qF 'label action-required' '$WF'"
assert "#7674 genuine faults are p1-high, not p2-medium" \
  "grep -qF 'label priority/p1-high' '$WF'"
# The KNOWN brake must NOT share the issue channel: ~96 comments/day for ~3 months, and closing the
# issue makes the next tick file a new one. It gets the run log instead.
assert "#7674 the known brake is excluded from the issue channel (run-log only)" \
  "grep -qF \"steps.dedicated.outputs.verdict != 'stopped-by-brake'\" '$WF'"
assert "#7674 the arm emits an ::error:: annotation on a genuine fault (run-log legibility)" \
  "grep -qE '::error::#7674 dedicated inngest host verdict=' '$WF'"
# One malformed warehouse line must not lose every valid row after it.
assert "#7674 the arm decodes with jq -R (a stream-parse abort would read as 'host silent')" \
  "grep -qF 'jq -R -r' '$WF'"

assert "the three BETTERSTACK_QUERY_* secrets are wired into the workflow" \
  "grep -qF 'BETTERSTACK_QUERY_HOST' '$WF' && grep -qF 'BETTERSTACK_QUERY_USERNAME' '$WF' && grep -qF 'BETTERSTACK_QUERY_PASSWORD' '$WF'"

# --- (e) THE ARM, EXECUTED (#7674 review) -----------------------------------------------------
# Everything above this point asserts TEXT. A test-design pass drove 13 mutations against those
# assertions and 11 SURVIVED — including severing the classifier from its only caller
# (`VERDICT="healthy"`), making the whole step dead (`if: false`), and pointing the query at a
# marker that does not exist. All three left the suite fully green, because "the token appears in
# the file" is not "the code does the thing" — and the long rationale comments this PR adds are
# themselves matchable text, so the prose explaining an assertion was satisfying it.
#
# So: extract the arm's `run:` body and RUN it against stubbed rows, asserting the verdict it
# actually writes to $GITHUB_OUTPUT. This is behaviour, not spelling.
ARM_BODY="$(mktemp)"; SCRATCH+=("$ARM_BODY")
awk '/^      - name: Dedicated inngest host probe consumer/,/^      - name: Note the known brake/' "$WF"   | awk '/^        run: \|$/,0' | sed '1d; s/^          //' > "$ARM_BODY"
ARM_N=$(wc -l < "$ARM_BODY" | tr -d '[:space:]')
assert "#7674 the arm's run body extracted non-vacuously (>20 lines, got $ARM_N)" "[[ '$ARM_N' -gt 20 ]]"

run_arm() { # $1 = file of stub rows; echoes the verdict the arm writes to $GITHUB_OUTPUT
  local rows="$1" out ws
  out="$(mktemp)"; ws="$(mktemp -d)"; SCRATCH+=("$out" "$ws")
  mkdir -p "$ws/scripts"
  # Stub ONLY the external reader. The REAL classifier is placed at the path the arm sources, so
  # the `source` line and the classify call are both exercised — severing them must be detectable.
  printf '#!/usr/bin/env bash\ncat %q\n' "$rows" > "$ws/scripts/betterstack-query.sh"
  chmod +x "$ws/scripts/betterstack-query.sh"
  cp "$SUT" "$ws/scripts/inngest-dedicated-host-classify.sh"
  (
    export GITHUB_OUTPUT="$out" GITHUB_WORKSPACE="$ws"
    export BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x
    export DEDICATED_HOST=soleur-inngest DEDICATED_HOST_NAME=soleur-inngest-prd PROBE_WINDOW=3h
    bash "$ARM_BODY"
  ) >/dev/null 2>&1
  grep -oE '^verdict=.*' "$out" 2>/dev/null | head -1 | cut -d= -f2-
}

fx() { local f; f="$(mktemp)"; SCRATCH+=("$f"); printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
AEV=0
arm_case() { # $1 desc, $2 fixture file, $3 expected verdict
  local got; got="$(run_arm "$2")"; AEV=$((AEV + 1))
  assert "#7674 arm EXECUTED: $1 -> $3 (got '${got:-<none>}')" "[[ '$got' == '$3' ]]"
}

R_OK='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active cutover_flag=done\"}"}'
R_BRAKE='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive cutover_flag=rolled-back\"}"}'
R_DEAD='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive cutover_flag=done\"}"}'
R_WEB='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-web-platform\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active cutover_flag=unknown\"}"}'
R_SPOOF='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active cutover_flag=unknown\"}"}'
R_MALFORMED='not json at all'

arm_case "a serving host is healthy"                 "$(fx "$R_OK")"                 "healthy"
arm_case "today's state: stopped by the brake"        "$(fx "$R_BRAKE")"              "stopped-by-brake"
arm_case "inactive with no brake is not-serving"      "$(fx "$R_DEAD")"               "not-serving"
arm_case "NO rows at all is probe-unavailable"        "$(fx "")"                      "probe-unavailable"
# HOST ISOLATION, executed end-to-end: web-1's healthy row must not be read as OUR health, or the
# arm auto-closes the dedicated-host alarm off the wrong machine's telemetry.
arm_case "web-1 rows alone are probe-unavailable"     "$(fx "$R_WEB")"                "probe-unavailable"
arm_case "#6616 a web host SPOOFING our host_name is probe-unavailable" "$(fx "$R_SPOOF")" "probe-unavailable"
# A malformed line must not lose the valid row after it (this is what jq -R buys).
arm_case "a malformed line does not lose the real row" "$(fx "$R_MALFORMED" "$R_BRAKE")" "stopped-by-brake"
assert "#7674 arm-executed scenarios actually dispatched (>=7)" "[[ '$AEV' -ge 7 ]]"
# HARNESS CANARY: prove arm_case can FAIL, then subtract.
_A_P=$PASS; _A_F=$FAIL
arm_case "harness canary: a deliberately wrong expectation MUST fail (expected FAIL below)" "$(fx "$R_OK")" "not-serving"
if [[ "$FAIL" -ne $((_A_F + 1)) || "$PASS" -ne "$_A_P" ]]; then
  echo "  FATAL: arm_case does not compare against the executed arm — every executed row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (arm_case harness canary OK — deliberate FAIL above is expected and subtracted)"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
# WHOLE-SUITE ANTI-DELETION FLOOR. The only merge gate is `FAIL -gt 0`, so a deleted or skipped
# assertion is otherwise indistinguishable from a clean run.
if [[ "$PASS" -lt 48 ]]; then
  echo "  FAIL: suite dispatched $PASS assertions, floor is 48 — an assertion was removed or skipped."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
echo "  PASS: anti-deletion floor ($PASS >= 48 assertions dispatched)"
