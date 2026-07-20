#!/usr/bin/env bash
# Test: plugins/soleur/skills/ship/scripts/net-issue-flow.sh
#
# Mutation-proof discipline (#6727 convention): every assertion below must be
# capable of FAILING. A gate that cannot fail is the defect class this repo
# keeps re-learning. Each case is mutation-tested in
# specs/<branch>/mutation-evidence.md.
#
# Fixture seam is at the I/O boundary ONLY: a stub `gh` on PATH. Nothing above
# the counting logic is stubbed, so the regexes, the jq filter, the date
# comparison and the exit policy are all exercised for real.
#
# Foot-guns deliberately avoided (see work/SKILL.md):
#   - no `producer | grep -q` (SIGPIPE/pipefail early-match false-negative)
#   - stub `gh` validates "$*" so a call-shape regression is caught
#   - every happy-path case carries a positive control (CASE_RC)

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GATE="$REPO_ROOT/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

if [[ ! -x "$GATE" ]]; then
  printf 'FAIL: gate script missing or not executable: %s\n' "$GATE" >&2
  exit 1
fi

WORK="$(mktemp -d -t net-issue-flow.XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Stub gh. Dispatches on argv. Writes every invocation to $WORK/gh-calls so a
# call-shape regression (dropped --limit, reintroduced --search) is assertable.
# ---------------------------------------------------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [[ "${GH_FAIL:-0}" == "1" ]]; then
  echo "stub gh: simulated API failure" >&2
  exit 1
fi
case "$*" in
  *"pr view"*"--json body"*)      cat "$PR_BODY_FILE" ;;
  *"pr view"*"--json createdAt"*) printf '%s\n' "${PR_CREATED_AT_FIXTURE}" ;;
  *"issue list"*)                 cat "$ISSUE_LIST_FILE" ;;
  *) echo "stub gh: unhandled argv: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export GH_CALLS="$WORK/gh-calls"
export PR_CREATED_AT_FIXTURE="2026-07-20T10:00:00Z"

# Build an issue-list fixture with N issues that bare-reference PR #999.
mk_issues() {
  local n="$1" out="[" i
  for ((i = 1; i <= n; i++)); do
    [[ $i -gt 1 ]] && out+=","
    out+="{\"number\":$((7000 + i)),\"body\":\"Follow-up from #999 work.\",\"createdAt\":\"2026-07-20T12:00:00Z\"}"
  done
  printf '%s]\n' "$out"
}

run_gate() {
  : > "$GH_CALLS"
  ( export PR_BODY_FILE ISSUE_LIST_FILE; "$GATE" 999 ) > "$WORK/out" 2>&1
  CASE_RC=$?
}

# ---------------------------------------------------------------------------
# Case 1 (THE mandatory one): NET = +3, no override -> MUST exit 1.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body1"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues3"; export ISSUE_LIST_FILE
printf 'Some PR that closes nothing and files three.\n' > "$PR_BODY_FILE"
mk_issues 3 > "$ISSUE_LIST_FILE"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "net=+3 without override BLOCKS (exit 1)"
else fail "net=+3 without override should exit 1, got $CASE_RC"; fi
if grep -qE 'Net:[[:space:]]*\+3' "$WORK/out"; then pass "net=+3 reports Net: +3"
else fail "expected 'Net: +3' in output; got: $(tr '\n' '|' < "$WORK/out")"; fi

# ---------------------------------------------------------------------------
# Case 2: same NET = +3 WITH the override marker -> MUST exit 0.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body2"; export PR_BODY_FILE
{
  printf 'Architectural pivot; three deferrals are deliberate.\n'
  printf '<!-- gate-override: net-issue-flow -->\n'
  printf -- '- #7001 blocked on upstream schema change\n'
} > "$PR_BODY_FILE"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "net=+3 WITH override PASSES (exit 0)"
else fail "net=+3 with override should exit 0, got $CASE_RC"; fi
if grep -qE 'override' "$WORK/out"; then pass "override path is announced in output"
else fail "expected override to be announced"; fi

# ---------------------------------------------------------------------------
# Case 3: NET = 0 (closes 1, files 1) -> exit 0. Boundary: NET>0 blocks, 0 does not.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body3"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues1"; export ISSUE_LIST_FILE
printf 'Closes #6769\n' > "$PR_BODY_FILE"
mk_issues 1 > "$ISSUE_LIST_FILE"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "net=0 passes (exit 0)"
else fail "net=0 should exit 0, got $CASE_RC"; fi

# ---------------------------------------------------------------------------
# Case 4: NET = +1 -> MUST block. Pins the boundary at >0, not >+1.
# This is the case that distinguishes the shipped threshold from the
# originally-briefed 'NET > +1'. If someone loosens the gate, this reddens.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body4"; export PR_BODY_FILE
printf 'No closures here.\n' > "$PR_BODY_FILE"
mk_issues 1 > "$ISSUE_LIST_FILE"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "net=+1 BLOCKS (threshold is >0, not >+1)"
else fail "net=+1 should exit 1, got $CASE_RC"; fi

# ---------------------------------------------------------------------------
# Case 5: NET < 0 (closes 2, files 0) -> exit 0.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body5"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues0"; export ISSUE_LIST_FILE
printf 'Closes #100 and fixes #200.\n' > "$PR_BODY_FILE"
mk_issues 0 > "$ISSUE_LIST_FILE"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "net=-2 passes (exit 0)"
else fail "net=-2 should exit 0, got $CASE_RC"; fi
if grep -qE 'Closing:[[:space:]]*2' "$WORK/out"; then pass "dedup+multi-keyword closing count = 2"
else fail "expected 'Closing: 2'; got: $(tr '\n' '|' < "$WORK/out")"; fi

# ---------------------------------------------------------------------------
# Case 6: env escape hatch.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body6"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues3"; export ISSUE_LIST_FILE
printf 'No closures.\n' > "$PR_BODY_FILE"
run_gate_env() {
  : > "$GH_CALLS"
  ( export PR_BODY_FILE ISSUE_LIST_FILE SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1; "$GATE" 999 ) > "$WORK/out" 2>&1
  CASE_RC=$?
}
run_gate_env
if [[ "$CASE_RC" -eq 0 ]]; then pass "SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1 passes"
else fail "env skip should exit 0, got $CASE_RC"; fi

# ---------------------------------------------------------------------------
# Case 7: gh failure -> FAIL-OPEN (exit 0) but must NOT be silent.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body7"; export PR_BODY_FILE
printf 'No closures.\n' > "$PR_BODY_FILE"
run_gate_fail() {
  : > "$GH_CALLS"
  ( export PR_BODY_FILE ISSUE_LIST_FILE GH_FAIL=1; "$GATE" 999 ) > "$WORK/out" 2>&1
  CASE_RC=$?
}
run_gate_fail
if [[ "$CASE_RC" -eq 0 ]]; then pass "gh failure fails OPEN (exit 0)"
else fail "gh failure should fail open with exit 0, got $CASE_RC"; fi
if grep -qiE 'transient|fail-open|could not' "$WORK/out"; then pass "fail-open is announced, not silent"
else fail "fail-open must announce; got: $(tr '\n' '|' < "$WORK/out")"; fi

# ---------------------------------------------------------------------------
# Case 8: call-shape contract. The four FILED-query defects that would make a
# BLOCKING gate silently always-pass are each pinned here.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body8"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues0"; export ISSUE_LIST_FILE
printf 'Closes #1\n' > "$PR_BODY_FILE"
run_gate
issue_call="$(grep -F 'issue list' "$GH_CALLS" || true)"
if [[ -n "$issue_call" ]]; then pass "issue list was invoked"
else fail "issue list was never invoked"; fi
if [[ "$issue_call" == *"--limit 500"* ]]; then pass "FILED query passes --limit 500 (default 30 undercounts)"
else fail "FILED query must pass --limit 500; got: $issue_call"; fi
if [[ "$issue_call" != *"--search"* ]]; then pass "FILED query does NOT use --search (empty under App token)"
else fail "FILED query must not use --search; got: $issue_call"; fi
if [[ "$issue_call" == *"--state all"* ]]; then pass "FILED query uses --state all"
else fail "FILED query must use --state all; got: $issue_call"; fi
if [[ "$issue_call" != *"deferred-scope-out"* ]]; then pass "FILED query is not label-filtered (label covers ~8%)"
else fail "FILED query must not filter by deferred-scope-out; got: $issue_call"; fi

# ---------------------------------------------------------------------------
# Case 9: createdAt filter is applied client-side on the FULL ISO timestamp.
# An issue created BEFORE the PR must not count.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body9"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues9"; export ISSUE_LIST_FILE
printf 'No closures.\n' > "$PR_BODY_FILE"
cat > "$ISSUE_LIST_FILE" <<'PRE'
[{"number":6000,"body":"Pre-existing context for #999.","createdAt":"2026-07-01T09:00:00Z"}]
PRE
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "issue created BEFORE the PR is excluded (net=0)"
else fail "pre-PR issue must not count; got exit $CASE_RC / $(tr '\n' '|' < "$WORK/out")"; fi

# ---------------------------------------------------------------------------
# Case 10: bare-#N matching must not match a longer number (#9990 != #999).
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body10"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues10"; export ISSUE_LIST_FILE
printf 'No closures.\n' > "$PR_BODY_FILE"
cat > "$ISSUE_LIST_FILE" <<'SUB'
[{"number":6100,"body":"Unrelated work on #9990 only.","createdAt":"2026-07-20T12:00:00Z"}]
SUB
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "#9990 does not substring-match #999 (net=0)"
else fail "numeric boundary broken: #9990 matched #999; exit $CASE_RC"; fi

# ---------------------------------------------------------------------------
# Case 11 (review finding): the override marker must NOT match inside a fenced
# code block. The BLOCKED message prints the literal marker, so pasting gate
# output into the PR description as context would otherwise self-override.
# ---------------------------------------------------------------------------
PR_BODY_FILE="$WORK/body11"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues3"; export ISSUE_LIST_FILE
mk_issues 3 > "$ISSUE_LIST_FILE"
{
  printf 'Here is what the gate printed when it blocked me:\n\n'
  printf '```text\n'
  printf '  (c) Override — add to the PR body:\n'
  printf '        <!-- gate-override: net-issue-flow -->\n'
  printf '```\n\n'
  printf 'Still working on it.\n'
} > "$PR_BODY_FILE"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "marker inside a fenced block does NOT override"
else fail "fenced-block marker self-overrode; exit $CASE_RC"; fi

# Case 12: the marker OUTSIDE a fence still overrides even when a fence exists
# elsewhere in the body (proves the strip is scoped, not a blanket disable).
PR_BODY_FILE="$WORK/body12"; export PR_BODY_FILE
{
  printf '```text\nsome unrelated quoted output\n```\n\n'
  printf '<!-- gate-override: net-issue-flow -->\n'
  printf -- '- #7001 genuinely deferred\n'
} > "$PR_BODY_FILE"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "marker outside a fence still overrides"
else fail "real override was swallowed by the fence strip; exit $CASE_RC"; fi

# ---------------------------------------------------------------------------
# Case 13 (review finding): the fail-open event_type must be one the aggregator
# actually counts. rule-metrics-aggregate.sh counts only deny/bypass/applied/
# warn -- a 'transient' row increments nothing, so the operator cannot tell
# "never fired" from "fail-opened every time".
# ---------------------------------------------------------------------------
if grep -qE '_emit[[:space:]]+warn' "$GATE" && ! grep -qE '_emit[[:space:]]+transient' "$GATE"; then
  pass "fail-open emits a counted event_type (warn, not transient)"
else
  fail "fail-open must emit 'warn'; 'transient' is counted by nothing"
fi

# Case 14: the emitted rule_id must be exempt in the aggregator, or the first
# real event hard-fails the metrics run (exit 5) via the orphan gate.
AGG="$REPO_ROOT/scripts/rule-metrics-aggregate.sh"
if [[ -r "$AGG" ]] && grep -qF 'startswith("net-issue-flow")' "$AGG"; then
  pass "net-issue-flow rule_id is exempted in rule-metrics-aggregate.sh"
else
  fail "net-issue-flow rule_id would be an orphan -> aggregator exit 5"
fi
if [[ -r "$AGG" ]] && grep -qF 'startswith("cost-of-filing-")' "$AGG"; then
  pass "cost-of-filing-* rule_ids are exempted in rule-metrics-aggregate.sh"
else
  fail "cost-of-filing-* would be orphans -> aggregator exit 5"
fi

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf 'net-issue-flow.test.sh: ALL PASS\n'
  exit 0
fi
printf 'net-issue-flow.test.sh: %d FAILED\n' "$fails"
exit 1
