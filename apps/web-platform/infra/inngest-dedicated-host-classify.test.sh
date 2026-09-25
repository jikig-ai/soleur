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
# call shape, which a comment does not produce. #8846: the shape now opens with the shared
# probe-row def (scripts/lib/inngest-probe-row.sh), prefixed to the same program.
# shellcheck disable=SC2016,SC2034  # a literal shape, read inside the assert eval string below
JQ_SHAPE='jq -R -r "$INNGEST_PROBE_ROW_JQ"'"'"' fromjson? | .raw? | fromjson?'
assert "the arm decodes with jq -R + the shared def + double fromjson? (one bad line must not lose the rest)" \
  "grep -qF -- \"\$JQ_SHAPE\" '$WF'"
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
# The range's LAST line is the next step's `- name: Note the known brake (…)` header. Kept in the
# body it is a shell syntax error, so every execution exited 2 after writing its outputs — harmless
# while nothing read the exit code, fatal now that #8846 asserts on it. The second awk stops at it.
awk '/^      - name: Dedicated inngest host probe consumer/,/^      - name: Note the known brake/' "$WF" \
  | awk '/^        run: \|$/{g=1; next} g && /^      - name: /{exit} g' | sed 's/^          //' > "$ARM_BODY"
ARM_N=$(wc -l < "$ARM_BODY" | tr -d '[:space:]')
assert "#7674 the arm's run body extracted non-vacuously (>20 lines, got $ARM_N)" "[[ '$ARM_N' -gt 20 ]]"

PROBE_ROW_LIB_SRC="$REPO_ROOT/scripts/lib/inngest-probe-row.sh"
# run_arm reports through GLOBALS, not stdout, so one execution yields the verdict, the step's exit
# code, its detail= and the stub reader's argv together (#8846: a selector that cannot run must
# fail the STEP, and that is only observable as an exit code plus a verdict= that is absent).
ARM_RC=0; ARM_VERDICT=""; ARM_DETAIL=""; ARM_OUT=""; ARM_ARGV=""
run_arm() { # $1 = file of stub rows; $2 = lib|nolib (copy the shared probe-row lib?); $3 = optional PATH prefix dir
  local rows="$1" lib="${2:-lib}" pathpre="${3:-}" out ws argv
  out="$(mktemp)"; ws="$(mktemp -d)"; argv="$(mktemp)"; SCRATCH+=("$out" "$ws" "$argv")
  mkdir -p "$ws/scripts/lib"
  # Stub ONLY the external reader (it records its argv, so the query's --limit is observable). The
  # REAL classifier and the REAL probe-row lib are placed at the paths the arm sources, so the
  # `source` lines, the shared def and the classify call are all exercised — severing any of them
  # must be detectable.
  printf '#!/usr/bin/env bash\necho "$*" >> %q\ncat %q\n' "$argv" "$rows" > "$ws/scripts/betterstack-query.sh"
  chmod +x "$ws/scripts/betterstack-query.sh"
  cp "$SUT" "$ws/scripts/inngest-dedicated-host-classify.sh"
  [[ "$lib" == nolib ]] || cp "$PROBE_ROW_LIB_SRC" "$ws/scripts/lib/inngest-probe-row.sh"
  ARM_RC=0
  (
    # The override must not leak in from a caller's environment: with it set, the nolib case
    # would load the lib from elsewhere and never reach the selector-unavailable arm.
    unset INNGEST_PROBE_ROW_LIB
    export GITHUB_OUTPUT="$out" GITHUB_WORKSPACE="$ws"
    export BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x
    export DEDICATED_HOST=soleur-inngest DEDICATED_HOST_NAME=soleur-inngest-prd PROBE_WINDOW=3h
    if [[ -n "$pathpre" ]]; then export PATH="$pathpre:$PATH"; fi
    # Executed the way Actions runs a `run:` block with no `shell:` key (errexit already on).
    bash --noprofile --norc -eo pipefail "$ARM_BODY"
  ) >/dev/null 2>&1 || ARM_RC=$?
  ARM_OUT="$out"; ARM_ARGV="$argv"
  ARM_VERDICT="$(grep -oE '^verdict=.*' "$out" 2>/dev/null | head -1 | cut -d= -f2-)" || true
  ARM_DETAIL="$(grep -oE '^detail=.*' "$out" 2>/dev/null | head -1 | cut -d= -f2-)" || true
}

fx() { local f; f="$(mktemp)"; SCRATCH+=("$f"); printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
AEV=0
arm_case() { # $1 desc, $2 fixture file, $3 expected verdict
  local got; run_arm "$2"; got="$ARM_VERDICT"; AEV=$((AEV + 1))
  assert "#7674 arm EXECUTED: $1 -> $3 (got '${got:-<none>}')" "[[ '$got' == '$3' ]]"
}

R_OK='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"SYSLOG_IDENTIFIER\":\"inngest-server-probe\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active cutover_flag=done\"}"}'
R_BRAKE='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"SYSLOG_IDENTIFIER\":\"inngest-server-probe\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive cutover_flag=rolled-back\"}"}'
R_DEAD='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"SYSLOG_IDENTIFIER\":\"inngest-server-probe\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive cutover_flag=done\"}"}'
R_WEB='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-web-platform\",\"SYSLOG_IDENTIFIER\":\"inngest-server-probe\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active cutover_flag=unknown\"}"}'
R_SPOOF='{"dt":"2026-08-25 12:00:00.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-inngest-prd\",\"SYSLOG_IDENTIFIER\":\"inngest-server-probe\",\"message\":\"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active cutover_flag=unknown\"}"}'
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

# --- #8846: SELECT BY EMITTER, NOT BY SUBSTRING -----------------------------------------------
# The inngest server's own event log ships under SYSLOG_IDENTIFIER=doppler on the SAME host, and
# it quotes the marker whenever a GitHub issue/PR/comment about the probe is webhooked in. The arm
# kept any host-matching row whose message CONTAINED the marker, then read the newest (`tail -1`),
# so a quoting event-log row won and a healthy host graded probe-unavailable (P1 pairs hourly).
# Fixtures are SYNTHESIZED to the live row shape (host, host_name, SYSLOG_IDENTIFIER, a
# `{"caller":"api","event":{"data":…}}` message), never pasted (cq-test-fixtures-synthesized-only),
# and placed LAST so they are the newest rows, as they were live.
row_json() { # $1 host, $2 host_name, $3 SYSLOG_IDENTIFIER, $4 message
  jq -cn --arg h "$1" --arg hn "$2" --arg id "$3" --arg m "$4" \
    '{dt: "2026-08-25 12:05:00.000000", raw: ({host: $h, host_name: $hn, SYSLOG_IDENTIFIER: $id, message: $m} | tojson)}'
}
evlog_row() { # $1 = the text an issue body quotes; builds shape (a): a doppler event-log row
  local msg
  msg="$(jq -cn --arg b "$1" '{caller: "api", event: {name: "github/issues.closed", data: {action: "closed", issue: {number: 8833}, body: $b}}}')"
  row_json soleur-inngest soleur-inngest-prd doppler "$msg"
}
# (a) quoting prose with NO server_active=/http_code= token: the incident as it happened live.
R_EVLOG_BARE="$(evlog_row $'verdict: `probe-unavailable`\n\nno SOLEUR_INNGEST_SERVER_PROBE row from soleur-inngest-prd within 3h, or the read failed.')"
# (a) quoting a probe line. Each parsed token is followed by a SPACE, so today's `[^ ]+` extraction
# reads exactly these values and the RED is certain (a trailing `"}` would be read into the flag).
R_EVLOG_TOKENS="$(evlog_row 'the last reading was SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive cutover_flag=done boot_id=0 (quoted from the run log)')"
# A row whose raw decodes to a NON-object. `.host` on a number is a jq ERROR, and a jq error now
# fails the step (crash_reason=jq_rc) — so the type-safe emitter predicate must run first. It is
# placed LAST: jq -R's exit status reflects only the FINAL input (measured, jq 1.8), so the same
# row placed first errors on stderr yet exits 0, and would not catch a reordered predicate.
R_NONOBJ='{"dt":"2026-08-25 12:06:00.000000","raw":"42"}'

arm_case "#8846 R_OK then a marker-quoting event-log row (no tokens) is healthy" "$(fx "$R_OK" "$R_EVLOG_BARE")" "healthy"
assert "#8846 …and the step exits 0 (got $ARM_RC)" "[[ '$ARM_RC' -eq 0 ]]"
arm_case "#8846 R_OK then an event-log row QUOTING not-serving tokens is healthy" "$(fx "$R_OK" "$R_EVLOG_TOKENS")" "healthy"
# CONTROL: an event-log row alone is no probe row at all — probe-unavailable before and after.
arm_case "#8846 control: an event-log row alone is probe-unavailable" "$(fx "$R_EVLOG_BARE")" "probe-unavailable"
# shellcheck disable=SC2034  # read inside the assert eval string below
CTRL_DETAIL="$ARM_DETAIL"
assert "#8846 the unavailable detail carries returned=<rows read>/500 (got '${CTRL_DETAIL:0:40}…')" \
  "grep -qF 'returned=1/500' <<<\"\$CTRL_DETAIL\""
arm_case "#8846 web-1 row, R_OK, then an event-log row is healthy" "$(fx "$R_WEB" "$R_OK" "$R_EVLOG_BARE")" "healthy"
# MUST-PASS: the plain healthy path. An uninitialised JQ_RC under `set -u` would kill the step
# HERE — on every healthy tick — and re-create the consumer-broken issue loop (deepen obs F4).
run_arm "$(fx "$R_OK")"
assert "#8846 must-PASS: R_OK alone is healthy (got '${ARM_VERDICT:-<none>}')" "[[ '$ARM_VERDICT' == 'healthy' ]]"
assert "#8846 must-PASS: R_OK alone exits 0 (got $ARM_RC)" "[[ '$ARM_RC' -eq 0 ]]"
# shellcheck disable=SC2034  # read inside the assert eval string below
ARGV_TXT="$(cat "$ARM_ARGV" 2>/dev/null)"
assert "#8846 the reader is asked for --limit 500 (got '${ARGV_TXT}')" \
  "grep -qE -- '(^| )--limit 500( |\$)' <<<\"\$ARGV_TXT\""
# MUST-PASS guard: a non-object decoded row must not crash the step (predicate order).
run_arm "$(fx "$R_OK" "$R_NONOBJ")"
assert "#8846 must-PASS: R_OK then a non-object decoded row is still healthy (got '${ARM_VERDICT:-<none>}')" "[[ '$ARM_VERDICT' == 'healthy' ]]"
assert "#8846 must-PASS: …and exits 0 (got $ARM_RC)" "[[ '$ARM_RC' -eq 0 ]]"
# SELECTOR UNAVAILABLE: the lib is absent from the workspace. The arm must fail the STEP (which
# routes to the consumer-broken issue) and name why — never grade the host at all.
run_arm "$(fx "$R_OK")" nolib
assert "#8846 lib missing: the step exits non-zero (got $ARM_RC)" "[[ '$ARM_RC' -ne 0 ]]"
assert "#8846 lib missing: crash_reason=selector_unavailable is written to GITHUB_OUTPUT" \
  "grep -qE '^crash_reason=selector_unavailable( |\$)' '$ARM_OUT'"
assert "#8846 lib missing: NO verdict= is written (got '${ARM_VERDICT:-<none>}')" "! grep -qE '^verdict=' '$ARM_OUT'"
# JQ FAILURE: a jq that exits non-zero must fail the step with its code, not read as "no rows".
JQ_SHIM="$(mktemp -d)"; SCRATCH+=("$JQ_SHIM")
printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 3\n' > "$JQ_SHIM/jq"; chmod +x "$JQ_SHIM/jq"
run_arm "$(fx "$R_OK")" lib "$JQ_SHIM"
assert "#8846 jq exit 3: the step exits non-zero (got $ARM_RC)" "[[ '$ARM_RC' -ne 0 ]]"
assert "#8846 jq exit 3: crash_reason=jq_rc=3 is written to GITHUB_OUTPUT" "grep -qxF 'crash_reason=jq_rc=3' '$ARM_OUT'"
assert "#8846 jq exit 3: NO verdict= is written (got '${ARM_VERDICT:-<none>}')" "! grep -qE '^verdict=' '$ARM_OUT'"
assert "#7674 arm-executed scenarios actually dispatched (>=11)" "[[ '$AEV' -ge 11 ]]"
# HARNESS CANARY: prove arm_case can FAIL, then subtract.
_A_P=$PASS; _A_F=$FAIL
arm_case "harness canary: a deliberately wrong expectation MUST fail (expected FAIL below)" "$(fx "$R_OK")" "not-serving"
if [[ "$FAIL" -ne $((_A_F + 1)) || "$PASS" -ne "$_A_P" ]]; then
  echo "  FATAL: arm_case does not compare against the executed arm — every executed row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (arm_case harness canary OK — deliberate FAIL above is expected and subtracted)"

# --- (f) #6921/#8077 QUIESCED: classifier mode set <-> probe-step case arms (cross-file) --------
# op=quiesce-web leaves the web unit inactive|failed + disabled; inngest-inventory.sh prints the
# QUIESCED sentinel and classify_liveness_mode maps it to inngest_quiesced. A mode the classifier
# can print but the probe `case` has no arm for falls to `*) → probe_unavailable` (#6374 trap):
# for a quiesced unit that files a soft alert every 15 minutes forever post-cutover. Every grep
# below runs over COMMENT-STRIPPED text, so a commented-out arm/branch cannot satisfy a row.
CLASSIFIER="$REPO_ROOT/scripts/inngest-liveness-classify.sh"
WF_NC="$(mktemp)"; SCRATCH+=("$WF_NC")
grep -v '^[[:space:]]*#' "$WF" > "$WF_NC"
PROBE_NC="$(mktemp)"; SCRATCH+=("$PROBE_NC")
awk '/^      - id: probe$/{f=1; print; next} f && /^      - /{exit} f' "$WF_NC" > "$PROBE_NC"
PROBE_N=$(wc -l < "$PROBE_NC" | tr -d '[:space:]')
assert "#8077 the probe step extracted non-vacuously (>60 non-comment lines, got $PROBE_N)" "[[ '$PROBE_N' -gt 60 ]]"
CASE_NC="$(mktemp)"; SCRATCH+=("$CASE_NC")
awk '/^ *case "\$MODE" in$/{f=1; next} f && /^ *esac$/{exit} f' "$PROBE_NC" > "$CASE_NC"
CASE_N=$(wc -l < "$CASE_NC" | tr -d '[:space:]')
assert "#8077 the probe step's case \"\$MODE\" block extracted non-vacuously (>8 lines, got $CASE_N)" "[[ '$CASE_N' -gt 8 ]]"

# (ii) The restart dispatch `if:` is an allowlist of exactly two restart-family modes: it must
# never name the quiesced mode, and a second `||` member is the natural way one gets wired in.
# (The row in (b) only proves the line exists; this negative row is the sole producer.)
DISP_IF_NC=$(awk '/^      - name: Auto-dispatch inngest restart/{f=1; next} f && /^ *if: /{print; exit} f && /^      - /{exit}' "$WF_NC")
assert "#8077 the Auto-dispatch inngest restart step's if: was located (non-vacuity)" \
  "[[ -n \"\$DISP_IF_NC\" ]] && grep -qF \"failure_mode == 'inngest_down'\" <<<\"\$DISP_IF_NC\""
assert "#8077 the restart dispatch if: never names a quiesced mode" \
  "! grep -qF 'quiesced' <<<\"\$DISP_IF_NC\""
assert "#8077 the restart dispatch if: never names the disabled-unattributed mode" \
  "! grep -qF 'unattributed' <<<\"\$DISP_IF_NC\""
DISP_OR_N=$(grep -oF '||' <<<"$DISP_IF_NC" | wc -l | tr -d '[:space:]')
assert "#8077 the restart dispatch if: carries exactly one || (got $DISP_OR_N)" "[[ '$DISP_OR_N' -eq 1 ]]"

# (v) Every mode classify_liveness_mode can print — derived from the classifier, never listed
# here — has a probe `case` arm. `healthy` is excluded: it is handled by the `if` branch before
# the case (asserted to exist below). The derived-set floor runs BEFORE the loop, so a broken
# derivation (zero modes) cannot pass by iterating nothing.
MODES=$(grep -v '^[[:space:]]*#' "$CLASSIFIER" | grep -oE 'echo "[a-z_]+"' | sed -E 's/^echo "([a-z_]+)"$/\1/' | sort -u | grep -vx 'healthy') || true
MODE_N=$(printf '%s\n' "$MODES" | grep -c .) || true
assert "#8077 classifier modes derived excluding healthy (>=7, got $MODE_N: $(tr '\n' ' ' <<<"$MODES"))" "[[ '$MODE_N' -ge 7 ]]"
for m in $MODES; do
  assert "#8077 the probe case has an arm for classifier mode '$m' (else *) → probe_unavailable)" \
    "grep -qE '^ *${m}\\)' '$CASE_NC'"
done
DEFAULT_ARM=$(awk '/^ *\*\)/{f=1} f{print} f && /;;/{exit}' "$CASE_NC")
assert "#6374 the probe case's *) default arm still exists and maps to probe_unavailable" \
  "grep -qF 'last_mode=\"probe_unavailable\"' <<<\"\$DEFAULT_ARM\""
assert "#8077 the healthy mode is handled by the if [[ \"\$MODE\" == \"healthy\" ]] branch" \
  "grep -qF 'if [[ \"\$MODE\" == \"healthy\" ]]; then' '$PROBE_NC'"

# Declaration row (Guard 1 #6): web_quiesced_since is read by the post-loop record_failure guard and
# by the output block, so it must be declared on the SAME line as fail_mode="" — OUTSIDE
# `if [[ -z "$fail_mode" ]]`. Declared inside that block, the secret_unset path never assigns it and
# the output block's read under `set -u` kills the step before it writes failure_mode. (The executed
# rows in (g) are what catch the mutation; this row names the invariant.)
DECL_LN=$(grep -nF 'fail_mode=""; fail_detail=""' "$PROBE_NC" | head -1 | cut -d: -f1) || true
assert "#8077 the fail_mode=\"\" declaration line was located (non-vacuity)" "[[ -n '$DECL_LN' ]]"
DECL_TXT=$(sed -n "${DECL_LN:-0}p" "$PROBE_NC" 2>/dev/null) || true
assert "#8077 web_quiesced_since=\"\" is declared on the fail_mode=\"\" line" \
  "grep -qF 'web_quiesced_since=\"\"' <<<\"\$DECL_TXT\""
FIRST_WQ_LN=$(grep -nE 'web_quiesced_since=' "$PROBE_NC" | head -1 | cut -d: -f1) || true
assert "#8077 no web_quiesced_since= assignment precedes that declaration (first at ${FIRST_WQ_LN:-none}, decl ${DECL_LN:-none})" \
  "[[ -n '$FIRST_WQ_LN' && '$FIRST_WQ_LN' == '$DECL_LN' ]]"

# (vi) The disabled-unattributed alarm has its own file-issue arm — it must never fall to the
# file-issue step's `*)` default, which maps to the `down` class (a false [ci/inngest-down] P1 that
# also claims a restart this workflow never dispatches for that mode).
# shellcheck disable=SC2034  # read inside the assert eval string below
FILE_CASE_NC=$(awk '/^      - name: File or comment tracking issue \(failure\)/{f=1; next} f && /^ *case "\$FAIL_MODE" in$/{g=1; next} g && /^ *esac$/{exit} g' "$WF_NC")
assert "#8077 the file-issue step's case \"\$FAIL_MODE\" block was located (non-vacuity)" \
  "grep -qE '^ *\\*\\) +ISSUE_CLASS=\"down\"' <<<\"\$FILE_CASE_NC\""
assert "#8077 the file-issue step routes inngest_disabled_unattributed to its own class (not *) → down)" \
  "grep -qE '^ *inngest_disabled_unattributed\\) +ISSUE_CLASS=\"disabled-unattributed\"' <<<\"\$FILE_CASE_NC\""
assert "#8077 the disabled-unattributed issue title carries [ci/inngest-disabled-unattributed] and remedy op=rollback" \
  "grep -qF 'ISSUE_TITLE=\"[ci/inngest-disabled-unattributed]' '$WF_NC' && awk '/ISSUE_CLASS\" == \"disabled-unattributed\"/{f=1} f&&/op=rollback/{print; exit}' '$WF_NC' | grep -q ."
# (vii) The Sentry check-in is `ok` only when the no-live-scheduler alarm did not fire.
# shellcheck disable=SC2034  # read inside the assert eval string below
CHECKIN_NC=$(grep -E '^ *status: \$\{\{ \(steps\.effmode\.outcome' "$WF_NC" | head -1)
assert "#8077 the Sentry check-in status expression was located (non-vacuity)" "[[ -n \"\$CHECKIN_NC\" ]]"
assert "#8077 the Sentry check-in ok requires steps.nolive.outputs.alarm != 'true'" \
  "grep -qF \"steps.effmode.outcome == 'success' && steps.nolive.outputs.alarm != 'true' && (\" <<<\"\$CHECKIN_NC\""

# --- (g) THE PROBE STEP AND THE NOLIVE STEP, EXECUTED (#8077 review) ---------------------------
# The rows in (f) assert TEXT, and the panel drove four workflow mutations through them that all
# stayed green: W1 the quiesced arm's body replaced by `last_mode="inngest_down"`, W2 the arm
# calling record_failure, W3 the web_quiesced_since declaration moved into a comment, W4 the
# post-loop guard reverted to `[[ "$healthy" == "no" ]] && record_failure`. So the real `run:`
# blocks are extracted by their step anchors and EXECUTED the way Actions runs them
# (`bash --noprofile --norc -eo pipefail`), against a stub curl serving scripted (code, body)
# sequences, the REAL classifier at the path the step sources, and a fake $GITHUB_OUTPUT.
extract_run() { # $1 = awk regex of the step's first line; prints the de-indented run: body
  awk -v start="$1" '$0 ~ start {f=1; next} f && /^      - /{exit} f' "$WF" \
    | awk '/^        run: \|$/{g=1; next} g' | sed 's/^          //'
}
PROBE_BODY="$(mktemp)"; SCRATCH+=("$PROBE_BODY")
extract_run '^      - id: probe$' > "$PROBE_BODY"
PROBE_BODY_N=$(wc -l < "$PROBE_BODY" | tr -d '[:space:]')
assert "#8077 the probe step's run body extracted non-vacuously (>100 lines, got $PROBE_BODY_N)" "[[ '$PROBE_BODY_N' -gt 100 ]]"
# The step writes its body to a fixed /tmp path; redirect it into scratch (and prove it was there).
PROBE_WS="$(mktemp -d)"; SCRATCH+=("$PROBE_WS")
HB_N=$(grep -cF '/tmp/health-body' "$PROBE_BODY") || true
assert "#8077 the probe body names its /tmp/health-body scratch (>=2 uses, got $HB_N)" "[[ '$HB_N' -ge 2 ]]"
sed -i "s#/tmp/health-body#$PROBE_WS/health-body#g" "$PROBE_BODY"
mkdir -p "$PROBE_WS/scripts" "$PROBE_WS/bin"
cp "$REPO_ROOT/scripts/inngest-liveness-classify.sh" "$PROBE_WS/scripts/"
cat > "$PROBE_WS/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Serve the Nth scripted response (or the last one) — $SEQ_DIR/<n>.code + <n>.body.
n=$(( $(cat "$SEQ_DIR/calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$SEQ_DIR/calls"
k=$n; while [[ ! -f "$SEQ_DIR/$k.code" && $k -gt 1 ]]; do k=$((k - 1)); done
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] && cat "$SEQ_DIR/$k.body" > "$out"
cat "$SEQ_DIR/$k.code"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$PROBE_WS/bin/sleep"
printf '#!/usr/bin/env bash\ncat >/dev/null; echo "SHA2-256(stdin)= 00"\n' > "$PROBE_WS/bin/openssl"
chmod +x "$PROBE_WS/bin/curl" "$PROBE_WS/bin/sleep" "$PROBE_WS/bin/openssl"

PROBE_RC=0; PROBE_OUT=""; PROBE_CALLS=0
run_probe() { # $1 = "secrets"|"nosecrets"; then pairs: <code> <body> ... served in order
  local mode="$1"; shift
  local seq out i=0; seq="$(mktemp -d)"; out="$(mktemp)"; SCRATCH+=("$seq" "$out")
  while [[ $# -ge 2 ]]; do i=$((i + 1)); printf '%s' "$1" > "$seq/$i.code"; printf '%s' "$2" > "$seq/$i.body"; shift 2; done
  PROBE_RC=0
  (
    export GITHUB_OUTPUT="$out" GITHUB_WORKSPACE="$PROBE_WS" SEQ_DIR="$seq" PATH="$PROBE_WS/bin:$PATH"
    if [[ "$mode" == secrets ]]; then export WEBHOOK_SECRET=x CF_ACCESS_CLIENT_ID=x CF_ACCESS_CLIENT_SECRET=x
    else unset WEBHOOK_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; fi
    bash --noprofile --norc -eo pipefail "$PROBE_BODY"
  ) >/dev/null 2>&1 || PROBE_RC=$?
  PROBE_OUT="$out"; PROBE_CALLS=$(cat "$seq/calls" 2>/dev/null || echo 0)
}
# Prints the LAST value written for key $1, or the literal <absent> when the key was never written.
out_val() {
  if grep -qE "^$1=" "$PROBE_OUT" 2>/dev/null; then grep -E "^$1=" "$PROBE_OUT" | tail -1 | cut -d= -f2-; else printf '<absent>'; fi
}

B_Q='inngest-inventory: QUIESCED host_id=soleur-web-1 unit=inactive enabled=disabled quiesced_since=1789000000 capture=present rebooted_since_quiesce=false — deliberate stop+disable (op=quiesce-web); no restart'
B_Q_NOSINCE='inngest-inventory: QUIESCED host_id=soleur-web-1 unit=inactive enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart'
B_F='inngest-inventory: FATAL host_id=soleur-web-1 /v0/gql functions query failed or non-array (errors=["connection refused"]); is inngest-server.service up?'
B_U='inngest-inventory: DISABLED_UNATTRIBUTED host_id=soleur-web-1 unit=inactive enabled=disabled — scheduler disabled with no valid quiesce marker; not a deliberate quiesce; dispatch op=rollback'
B_OK='{"functions":["cron-a"],"event_names":[],"armed_reminders":[],"durability_state":"durable","host_id":"soleur-web-1"}'

run_probe secrets 503 "$B_Q"
assert "#8077 probe EXECUTED: QUIESCED body → rc 0 (got $PROBE_RC)" "[[ '$PROBE_RC' -eq 0 ]]"
assert "#8077 probe EXECUTED: QUIESCED body → failure_mode='' (got '$(out_val failure_mode)')" "[[ \"\$(out_val failure_mode)\" == '' ]]"
assert "#8077 probe EXECUTED: QUIESCED body → web_quiesced_since=1789000000 (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == '1789000000' ]]"
assert "#8077 probe EXECUTED: QUIESCED breaks the retry loop (1 curl, got $PROBE_CALLS)" "[[ '$PROBE_CALLS' -eq 1 ]]"

run_probe secrets 503 "$B_Q_NOSINCE"
assert "#8077 probe EXECUTED: QUIESCED line without a parseable since → web_quiesced_since=unknown (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == 'unknown' ]]"
assert "#8077 probe EXECUTED: …and still failure_mode='' (got '$(out_val failure_mode)')" "[[ \"\$(out_val failure_mode)\" == '' ]]"

run_probe secrets 503 "${B_Q}"$'\n'"${B_Q/1789000000/1799999999}"
assert "#8077 probe EXECUTED: since is read from the FIRST QUIESCED line (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == '1789000000' ]]"

run_probe secrets 500 "$B_F"
assert "#8077 probe EXECUTED: FATAL body → failure_mode=inngest_down (got '$(out_val failure_mode)', rc $PROBE_RC)" "[[ \"\$(out_val failure_mode)\" == 'inngest_down' && '$PROBE_RC' -eq 0 ]]"
assert "#8077 probe EXECUTED: FATAL body → web_quiesced_since='' (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == '' ]]"
assert "#8077 probe EXECUTED: FATAL retried 3 times (got $PROBE_CALLS)" "[[ '$PROBE_CALLS' -eq 3 ]]"

run_probe secrets 503 "$B_U"
assert "#8077 probe EXECUTED: DISABLED_UNATTRIBUTED → failure_mode=inngest_disabled_unattributed (got '$(out_val failure_mode)')" "[[ \"\$(out_val failure_mode)\" == 'inngest_disabled_unattributed' ]]"
assert "#8077 probe EXECUTED: DISABLED_UNATTRIBUTED → web_quiesced_since='' (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == '' ]]"

run_probe nosecrets 200 "$B_OK"
assert "#8077 probe EXECUTED: secrets unset → rc 0 (got $PROBE_RC)" "[[ '$PROBE_RC' -eq 0 ]]"
assert "#8077 probe EXECUTED: secrets unset → failure_mode=secret_unset, no curl (got '$(out_val failure_mode)', calls $PROBE_CALLS)" "[[ \"\$(out_val failure_mode)\" == 'secret_unset' && '$PROBE_CALLS' -eq 0 ]]"
assert "#8077 probe EXECUTED: secrets unset → web_quiesced_since written empty (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == '' ]]"

run_probe secrets 500 "$B_F" 503 "$B_Q"
assert "#8077 probe EXECUTED: FATAL then QUIESCED → failure_mode='' (got '$(out_val failure_mode)')" "[[ \"\$(out_val failure_mode)\" == '' ]]"
assert "#8077 probe EXECUTED: FATAL then QUIESCED → web_quiesced_since=1789000000 (got '$(out_val web_quiesced_since)')" "[[ \"\$(out_val web_quiesced_since)\" == '1789000000' ]]"

run_probe secrets 200 "$B_OK"
assert "#8077 probe EXECUTED: healthy body → failure_mode='' and web_quiesced_since='' (got '$(out_val failure_mode)'/'$(out_val web_quiesced_since)')" \
  "[[ \"\$(out_val failure_mode)\" == '' && \"\$(out_val web_quiesced_since)\" == '' && '$PROBE_CALLS' -eq 1 ]]"
# PROBE HARNESS CANARY: a wrong expectation must fail, then subtract.
_P_P=$PASS; _P_F=$FAIL
run_probe secrets 500 "$B_F"
assert "probe harness canary: FATAL must NOT read as failure_mode='' (expected FAIL below)" "[[ \"\$(out_val failure_mode)\" == '' ]]"
if [[ "$FAIL" -ne $((_P_F + 1)) || "$PASS" -ne "$_P_P" ]]; then
  echo "  FATAL: run_probe/out_val do not observe the executed step — every executed probe row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (probe harness canary OK — deliberate FAIL above is expected and subtracted)"

# The nolive step: alarm iff web quiesced AND the dedicated host is not healthy AND the quiesce is
# older than the grace (or its epoch is unknown). It must ALWAYS write alarm=true|false.
NOLIVE_BODY="$(mktemp)"; SCRATCH+=("$NOLIVE_BODY")
extract_run '^        id: nolive$' > "$NOLIVE_BODY"
NOLIVE_N=$(wc -l < "$NOLIVE_BODY" | tr -d '[:space:]')
assert "#8077 the nolive step's run body extracted non-vacuously (>10 lines, got $NOLIVE_N)" "[[ '$NOLIVE_N' -gt 10 ]]"
GRACE=$(awk '/^        id: nolive$/{f=1; next} f && /^      - /{exit} f && /^ +INNGEST_QUIESCE_GRACE_MIN: /{print $2; exit}' "$WF" | tr -d "'\"")
assert "#8077 the nolive step's env pins INNGEST_QUIESCE_GRACE_MIN: 60 (got '${GRACE:-<none>}')" "[[ '$GRACE' == '60' ]]"
NOW_S=$(date -u +%s)
nolive_case() { # $1 desc, $2 WEB_QUIESCED_SINCE, $3 DEDICATED_VERDICT, $4 expected alarm
  local out got; out="$(mktemp)"; SCRATCH+=("$out")
  ( export GITHUB_OUTPUT="$out" WEB_QUIESCED_SINCE="$2" DEDICATED_VERDICT="$3" INNGEST_QUIESCE_GRACE_MIN="$GRACE"
    bash --noprofile --norc -eo pipefail "$NOLIVE_BODY" ) >/dev/null 2>&1
  got="$(grep -E '^alarm=' "$out" 2>/dev/null | tail -1 | cut -d= -f2-)"
  assert "#8077 nolive EXECUTED: $1 → alarm=$4 (got '${got:-<absent>}')" "[[ '$got' == '$4' ]]"
}
OLD=$((NOW_S - 2 * 3600)); FRESH=$((NOW_S - 10 * 60))
nolive_case "quiesced 2h ago + dedicated stopped-by-brake"   "$OLD"   "stopped-by-brake"  true
nolive_case "quiesced 2h ago + dedicated probe-unavailable"  "$OLD"   "probe-unavailable" true
nolive_case "quiesced 2h ago + dedicated verdict empty"      "$OLD"   ""                  true
nolive_case "quiesced 2h ago + dedicated not-serving"        "$OLD"   "not-serving"       true
nolive_case "quiesced 10m ago (within grace) + brake"        "$FRESH" "stopped-by-brake"  false
nolive_case "quiesced 2h ago + dedicated healthy"            "$OLD"   "healthy"           false
nolive_case "quiesce epoch unknown + brake"                  "unknown" "stopped-by-brake" true
nolive_case "web not quiesced (since '') + brake"            ""       "stopped-by-brake"  false
# #8846: an EMPTY verdict is a consumer that failed, not a host that is down — the detail (which
# becomes the no-live-scheduler issue body) must say NOT MEASURED, while the alarm still fires.
NL_OUT="$(mktemp)"; SCRATCH+=("$NL_OUT")
( export GITHUB_OUTPUT="$NL_OUT" WEB_QUIESCED_SINCE="$OLD" DEDICATED_VERDICT="" INNGEST_QUIESCE_GRACE_MIN="$GRACE"
  bash --noprofile --norc -eo pipefail "$NOLIVE_BODY" ) >/dev/null 2>&1
# shellcheck disable=SC2034  # read inside the assert eval string below
NL_DETAIL="$(grep -E '^detail=' "$NL_OUT" 2>/dev/null | tail -1 | cut -d= -f2-)"
assert "#8846 nolive EXECUTED: empty verdict -> detail says 'dedicated host NOT MEASURED' (got '${NL_DETAIL:0:60}…')" \
  "grep -qF 'dedicated host NOT MEASURED — the dedicated-host consumer failed' <<<\"\$NL_DETAIL\""
_N_P=$PASS; _N_F=$FAIL
nolive_case "harness canary: a wrong expectation MUST fail (expected FAIL below)" "$OLD" "healthy" true
if [[ "$FAIL" -ne $((_N_F + 1)) || "$PASS" -ne "$_N_P" ]]; then
  echo "  FATAL: nolive_case does not observe the executed step — every nolive row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (nolive harness canary OK — deliberate FAIL above is expected and subtracted)"
assert "#8077 the no-live-scheduler issue step keys on steps.nolive.outputs.alarm == 'true' and labels action-required" \
  "awk '/^      - name: File or comment no-live-scheduler issue/{f=1} f&&/^      - name: /&&!/no-live-scheduler issue/{exit} f' '$WF_NC' | grep -qF \"if: always() && steps.nolive.outputs.alarm == 'true'\" && grep -qF '[ci/inngest-no-live-scheduler]' '$WF_NC'"
assert "#8077 a close step closes [ci/inngest-no-live-scheduler] on alarm == 'false'" \
  "grep -qF \"steps.nolive.outputs.alarm == 'false'\" '$WF_NC'"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
# WHOLE-SUITE EXACT FLOOR. The only merge gate is `FAIL -gt 0`, so a deleted or skipped assertion
# is otherwise indistinguishable from a clean run; an exact count also catches a row that silently
# stopped dispatching (the canaries above subtract their deliberate FAILs before this point).
# Written as `<` OR `>` (not `!=`) with a plain assignment directly above the `if`:
# scripts/guard-vacuity-floor.test.sh recognises a floor only by an ordered comparison and binds
# the threshold only from contiguous simple assignments, and this suite is on its PROMOTED_FILES pin.
# 104 -> 122 (#8846, +18): the watchdog (a) cases — no-token quote healthy + exit 0 (2), token
# quote healthy (1), control probe-unavailable + returned=1/500 detail (2), web-1/R_OK/(a) healthy
# (1); R_OK must-PASS verdict + exit 0 (2); --limit 500 argv (1); non-object row guard verdict +
# exit 0 (2); lib missing exit/crash_reason/no-verdict (3); jq exit 3 exit/crash_reason/no-verdict
# (3); nolive empty-verdict NOT MEASURED wording (1). The jq-shape row was re-anchored in place
# (count unchanged).
EXPECTED_ASSERTIONS=122
if (( PASS + FAIL < EXPECTED_ASSERTIONS )) || (( PASS + FAIL > EXPECTED_ASSERTIONS )); then
  printf '  FAIL: suite dispatched %s assertions, expected exactly %s — an assertion was added, removed or skipped.\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
printf '  PASS: exact assertion floor (%s dispatched)\n' "$EXPECTED_ASSERTIONS"
