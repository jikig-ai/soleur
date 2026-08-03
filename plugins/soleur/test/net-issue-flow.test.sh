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
# `passes` exists for the anti-vacuity floor at the bottom. Before it, pass()
# only printed, so there was no count to floor against and a deleted case was
# indistinguishable from a case that never existed.
passes=0
pass() { printf '  ok   %s\n' "$1"; passes=$((passes + 1)); }
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
# The PR number is validated, not just the flags: dropping "$PR_NUMBER" from
# the `gh pr view` calls would otherwise resolve whatever PR the cwd points at
# while jq's bare-#N match still used the passed number -- a silent desync.
case "$*" in
  *"pr view 999"*"--json body"*)      cat "$PR_BODY_FILE" ;;
  *"pr view 999"*"--json createdAt"*) printf '%s\n' "${PR_CREATED_AT_FIXTURE}" ;;
  *"pr view"*"--json body"*|*"pr view"*"--json createdAt"*)
    echo "stub gh: pr view without the expected PR number: $*" >&2; exit 64 ;;
  *"issue list"*)                 cat "$ISSUE_LIST_FILE" ;;
  *) echo "stub gh: unhandled argv: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# ---------------------------------------------------------------------------
# Stub git. The exemption derives its qualifying rule-id set from the MERGE-BASE
# copy of the corpus, so `merge-base` and `show` are the seam.
#
# Shape follows .claude/hooks/session-rules-loader.test.sh, NOT the `gh` stub
# above: REAL_GIT is resolved BEFORE the shim goes on PATH, the heredoc is
# UNQUOTED so it interpolates, and every non-targeted subcommand delegates via
# `exec`. The gh stub's quoted-heredoc shape cannot be copied here because the
# gate still needs real git for `rev-parse --show-toplevel`.
#
# Every invocation is recorded so the "must never read the staged index"
# assertion can be made positively: with a bare `:path`, `git show` reads the
# AUTHOR'S OWN staged copy, which returns rc=0 and a full id list — a fail-open
# that is non-empty, so no empty-set warning would ever fire.
# ---------------------------------------------------------------------------
REAL_GIT="$(command -v git)"
cat > "$WORK/bin/git" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${GIT_CALLS:-/dev/null}"
case "\$*" in
  "merge-base"*)
    # EXACT argv, not a prefix. A prefix-matching stub answers identically for
    # any refs, so `merge-base HEAD HEAD` -- which in production resolves to
    # HEAD and lets a PR tag a rule and exempt ITSELF in the same diff -- would
    # be indistinguishable from the correct call. That is the feature's central
    # claim, so the stub has to be able to reject.
    if [[ "\$*" != "merge-base origin/main HEAD" ]]; then
      echo "stub git: unexpected merge-base argv: \$*" >&2
      exit 64
    fi
    if [[ "\${MB_FAIL:-0}" == "1" ]]; then
      echo "stub git: simulated merge-base failure" >&2
      exit 128
    fi
    printf '%s\n' "\${MB_SHA_FIXTURE:-abc1234def5678}"
    ;;
  "show "*":AGENTS.rules.md")
    # Serve the merge-base SHA the honest path resolves. EVERY other ref --
    # a bare ':path' (staged index) or a direct HEAD read -- gets a DISTINCT,
    # fully-tagged corpus, so a gate reading the wrong ref does not merely fail
    # to find a file: it SUCCEEDS with a wider set, flipping a BLOCKED case to
    # exempt. The fail-open becomes a behaviour change, not a missing file.
    case "\$*" in
      "show \${MB_SHA_FIXTURE:-abc1234def5678}:AGENTS.rules.md") cat "\${CORPUS_FILE:-/dev/null}" ;;
      *)                                                        cat "\${INDEX_CORPUS_FILE:-/dev/null}" ;;
    esac
    ;;
  *) exec "$REAL_GIT" "\$@" ;;
esac
STUB
chmod +x "$WORK/bin/git"

export PATH="$WORK/bin:$PATH"
export GH_CALLS="$WORK/gh-calls"
export GIT_CALLS="$WORK/git-calls"
export PR_CREATED_AT_FIXTURE="2026-07-20T10:00:00Z"

# Keep test telemetry out of the operator's real .claude/.rule-incidents.jsonl.
export INCIDENTS_REPO_ROOT="$WORK/incidents-root"
mkdir -p "$INCIDENTS_REPO_ROOT"

# Build an issue-list fixture with N issues that bare-reference PR #999.
mk_issues() {
  local n="$1" out="[" i
  for ((i = 1; i <= n; i++)); do
    [[ $i -gt 1 ]] && out+=","
    out+="{\"number\":$((7000 + i)),\"body\":\"Follow-up from #999 work.\",\"createdAt\":\"2026-07-20T12:00:00Z\"}"
  done
  printf '%s]\n' "$out"
}

# Corpus defaults. Declared up-front (not just exported at call time) so `set -u`
# never bites and every pre-exemption case runs against a REALISTIC corpus rather
# than an empty one -- an empty corpus would make the original 14 cases pass for
# the wrong reason once the exemption exists.
export CORPUS_FILE="$WORK/corpus-default"
export INDEX_CORPUS_FILE="$WORK/corpus-index"
export MB_FAIL=0
export MB_SHA_FIXTURE="abc1234def5678"

run_gate() {
  : > "$GH_CALLS"
  : > "$GIT_CALLS"
  ( export PR_BODY_FILE ISSUE_LIST_FILE CORPUS_FILE INDEX_CORPUS_FILE MB_FAIL MB_SHA_FIXTURE
    "$GATE" 999 ) > "$WORK/out" 2>&1
  CASE_RC=$?
}

# Corpus fixtures. These are parsed by scripts/lint-rule-bodies.py's own
# parse_bodies (the gate shells out to it), so they must be REAL corpora:
# a gated `## SECTION` heading with `- ` body lines at column 0.
#
# The last two entries under Workflow Gates are the load-bearing negatives.
# A shell `grep -F '[mandates-filing]'` -- the gate's original derivation --
# honoured BOTH, because it enforced only the id-prefix conjunct while
# parse_bodies enforces four (section, `- ` at column 0, not pointer-shaped,
# prefix). Measured on the shipped corpus, the grep form derived 4 ids to
# parse_bodies' 2: an indented sub-bullet or a plain prose line carrying the
# marker is invisible to the ADR-092 ack gate, the hash manifest and
# lint-rule-ids.py, but visible to grep -- a silent, permanent, repo-wide
# self-grant needing no ack. Keep both shapes here.
cat > "$WORK/corpus-default" <<'CORPUS'
## Hard Rules

- Investigate any non-zero exit [id: hr-when-a-command-exits-non-zero-or-prints]. Never treat a failed step as success.

## Workflow Gates

- When deferring a capability, default to documenting it in-place [id: wg-when-deferring-a-capability-create-a] [mandates-filing]. File an issue ONLY when the triple test passes.
- `/ship` Phase 5.5 blocks PR-ready without `Tracks #NNNN` companions [id: wg-block-pr-ready-on-undeferred-operator-steps] [mandates-filing] [skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]. **Why:** #4066.
- Defer only after inline triage [id: wg-defer-only-after-inline-triage]. This rule RESTRICTS filing; it must never be exempt.
- An id that exists ONLY in this fixture, never in the shipped corpus [id: wg-fixture-only-mandating-rule] [mandates-filing].
  - INDENTED sub-bullet: not a body line, so the ack gate cannot see it [id: wg-indented-subbullet-must-not-derive] [mandates-filing].

Prose line, no bullet: also invisible to the ack gate [id: wg-prose-line-must-not-derive] [mandates-filing].

## Code Quality

- A cq rule that carries the marker on an ACK-UNGATED prefix [id: cq-tagged-but-ungated-prefix] [mandates-filing]. Must not be derived.

## Appendix

- A well-formed body line with a gated PREFIX, under a heading NOT in SECTIONS [id: wg-ungated-section-must-not-derive] [mandates-filing].
CORPUS

# The staged-index / wrong-ref corpus. Distinct on purpose: it tags the id used
# by the merge-base-unresolvable case, so a fallback to the index -- or a read of
# any ref other than the resolved merge-base -- flips that case from BLOCKED to
# exempt and is caught as a behaviour change rather than a missing file.
cat > "$WORK/corpus-index" <<'CORPUS'
## Workflow Gates

- Anything the author staged [id: wg-block-pr-ready-on-undeferred-operator-steps] [mandates-filing].
- Anything at all [id: wg-self-granted-by-the-index] [mandates-filing].
CORPUS

MANDATED="wg-block-pr-ready-on-undeferred-operator-steps"

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

# ===========================================================================
# Cases 15+ — the mandated-filing exemption.
#
# Two repo gates were in genuine conflict: wg-block-pr-ready-on-undeferred-
# operator-steps REQUIRES a tracking issue for a bare operator action, and this
# gate BLOCKED the PR for filing it. Neither documented exit applied ("fix
# inline" is a SIZE test; "close something" needs a superseded issue), leaving
# only the blanket override — whose help text called itself an
# architectural-pivot deferral. An escape hatch that requires mis-describing the
# escape gets taken reflexively, which is what makes the gate advisory.
#
# The exemption is deliberately NOT self-serve: the claim must name a rule id
# that carries [mandates-filing] in the MERGE-BASE corpus. Everything below
# tests BOTH directions — fixtures on one side only cannot see an exemption
# that is too permissive, which is the failure mode that matters for a gate.
# ===========================================================================


# One issue referencing PR #999, with a controllable body/state.
mk_issue() { # $1=number  $2=body  $3=state (omit key entirely if literal ABSENT)
  local num="$1" body="$2" state="$3"
  if [[ "$state" == "ABSENT" ]]; then
    jq -nc --arg b "$body" --argjson n "$num" \
      '{number:$n, body:$b, createdAt:"2026-07-20T12:00:00Z"}'
  else
    jq -nc --arg b "$body" --arg s "$state" --argjson n "$num" \
      '{number:$n, body:$b, state:$s, createdAt:"2026-07-20T12:00:00Z"}'
  fi
}
set_issues() { printf '%s\n' "$1" | jq -s '.' > "$WORK/issues-dyn"; ISSUE_LIST_FILE="$WORK/issues-dyn"; export ISSUE_LIST_FILE; }

# Body of a well-formed mandated filing: the claim on its own line, plus the
# bare `#999` back-reference that puts it in the FILED set at all.
claim_body() { printf 'Follow-up from #999 work.\n\nMandated-By: %s\n' "$1"; }

# PR body with the companion the mandating rule already requires.
PRB_OK="$WORK/prb-ok"
{ printf 'Operator step deferred.\n\n'; printf 'Tracks #7001\n'; } > "$PRB_OK"

# --- Direction 1: a validly-mandated filing IS exempt -----------------------
PR_BODY_FILE="$PRB_OK"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "validly-mandated filing is EXEMPT (exit 0)"
else fail "mandated filing should be exempt; exit $CASE_RC / $(tr '\n' '|' < "$WORK/out")"; fi

# The report must stay honest: the filing is still COUNTED, and the exemption is
# shown on its own line naming the rule. An exemption that silently reduces
# `Filing:` is worse than the blanket override, because the override at least
# leaves a marker in the PR body.
if grep -qE '^  Filing:[[:space:]]+1\b' "$WORK/out"; then pass "Filing: keeps its true count (1), not reduced by the exemption"
else fail "Filing: must remain 1; got: $(tr '\n' '|' < "$WORK/out")"; fi
if grep -qE "^  Exempt:[[:space:]]+1\b.*#7001.*$MANDATED" "$WORK/out"; then pass "Exempt: line names the issue AND the mandating rule"
else fail "Exempt: line must name #7001 and $MANDATED; got: $(tr '\n' '|' < "$WORK/out")"; fi
if grep -qE '^  Net:[[:space:]]+\+0\b' "$WORK/out"; then pass "Net: +0 after exemption (1 filed, 1 exempt, 0 closing)"
else fail "expected 'Net: +0'; got: $(tr '\n' '|' < "$WORK/out")"; fi
if grep -qE "^  Mandating rules:[[:space:]]+3[[:space:]]+\(.*$MANDATED.*merge-base abc1234" "$WORK/out" \
   && ! grep -qE 'Mandating rules:.*(indented-subbullet|prose-line|ungated-prefix)' "$WORK/out"; then
  pass "report prints the derived ids AND the merge-base (not just a count)"
else fail "must print 'Mandating rules: 3 (<ids>, merge-base <sha>)'; got: $(tr '\n' '|' < "$WORK/out")"; fi

# The corpus MUST come from the merge-base, not the worktree. Without a fixture
# id absent from the shipped corpus, a gate that read `AGENTS.rules.md` directly
# would satisfy every other assertion here -- measured: that mutation SURVIVED
# the first battery. This case is the only thing that distinguishes them, and it
# also pins the same-PR self-grant: a PR cannot tag a rule and exempt itself,
# because its own tag is not at the merge-base yet.
PRB_FIXONLY="$WORK/prb-fixonly"; printf 'Deferred.\n\nTracks #7003\n' > "$PRB_FIXONLY"
PR_BODY_FILE="$PRB_FIXONLY"; export PR_BODY_FILE
set_issues "$(mk_issue 7003 "$(printf 'From #999.\n\nMandated-By: wg-fixture-only-mandating-rule\n')" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "corpus is read from the MERGE-BASE, not the worktree"
else fail "merge-base-only rule id was not honoured => gate is reading some other corpus; exit $CASE_RC"; fi
PR_BODY_FILE="$PRB_OK"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)"
run_gate

# CRLF regression pin. GitHub returns CRLF for web-authored bodies; a `[ \t]`-only
# anchor fails closed on a CORRECT claim, silently and permanently.
set_issues "$(mk_issue 7001 "$(printf 'Follow-up from #999.\r\n\r\nMandated-By: %s\r\n' "$MANDATED")" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "CRLF-bodied claim is exempt (\\r tolerated)"
else fail "CRLF body broke the claim match; exit $CASE_RC"; fi

# --- Direction 2: everything else is NOT exempt -----------------------------
# Each of these must BLOCK. Fixtures all on the positive side cannot detect an
# exemption that is too permissive, which is the direction that matters here.
neg() { # $1=label  $2=issue-json  [$3=pr-body-file]
  local label="$1" issue="$2" prb="${3:-$PRB_OK}"
  PR_BODY_FILE="$prb"; export PR_BODY_FILE
  set_issues "$issue"
  run_gate
  if [[ "$CASE_RC" -eq 1 ]]; then pass "NOT exempt: $label"
  else fail "NOT exempt expected (exit 1) for $label; got exit $CASE_RC / $(tr '\n' '|' < "$WORK/out")"; fi
}

neg "unknown rule id"            "$(mk_issue 7001 "$(claim_body wg-does-not-exist-anywhere)" OPEN)"
neg "real but UNTAGGED rule id"  "$(mk_issue 7001 "$(claim_body wg-defer-only-after-inline-triage)" OPEN)"
neg "tagged rule on an ack-UNGATED prefix (cq-*)" "$(mk_issue 7001 "$(claim_body cq-tagged-but-ungated-prefix)" OPEN)"
neg "prefix-extension of a tagged id"  "$(mk_issue 7001 "$(claim_body "${MANDATED}-v2")" OPEN)"
neg "malformed claim (no id)"    "$(mk_issue 7001 "$(printf 'Follow-up from #999.\n\nMandated-By:\n')" OPEN)"
neg "two Mandated-By lines"      "$(mk_issue 7001 "$(printf 'Follow-up #999.\n\nMandated-By: %s\nMandated-By: wg-bogus\n' "$MANDATED")" OPEN)"
neg "claim inside a fenced block" "$(mk_issue 7001 "$(printf 'Follow-up #999.\n\n```\nMandated-By: %s\n```\n' "$MANDATED")" OPEN)"
neg "claim mentioned mid-prose"  "$(mk_issue 7001 "$(printf 'Follow-up #999. It is Mandated-By: %s per the rule.\n' "$MANDATED")" OPEN)"
neg "CLOSED issue"               "$(mk_issue 7001 "$(claim_body "$MANDATED")" CLOSED)"
neg "absent state field"         "$(mk_issue 7001 "$(claim_body "$MANDATED")" ABSENT)"

# Companion-side negatives (valid claim, PR body is the defect).
PRB_NONE="$WORK/prb-none"; printf 'No companion here.\n' > "$PRB_NONE"
PRB_BARE="$WORK/prb-bare"; printf 'Mentions #7001 with no keyword.\n' > "$PRB_BARE"
PRB_FENCED="$WORK/prb-fenced"; printf 'Quoting the gate:\n\n```\nTracks #7001\n```\n' > "$PRB_FENCED"
PRB_LONGER="$WORK/prb-longer"; printf 'Tracks #70010\n' > "$PRB_LONGER"

neg "no companion in the PR body"        "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" "$PRB_NONE"
neg "bare #N mention is not a companion" "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" "$PRB_BARE"
neg "companion inside a fenced block"    "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" "$PRB_FENCED"
neg "Tracks #70010 does not satisfy #7001" "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" "$PRB_LONGER"

# LEFT boundary. Without `(^|[^A-Za-z])` the match is a bare substring, so
# `BackRefs`/`ReTracks`/`XRefs` all satisfy the companion — a word that merely
# ENDS in Refs/Tracks is not a companion keyword.
PRB_GLUED="$WORK/prb-glued"; printf 'Deferred.\n\nBackRefs #7001\n' > "$PRB_GLUED"
neg "BackRefs #7001 is not a Refs companion (left boundary)" \
    "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" "$PRB_GLUED"
PRB_GLUED2="$WORK/prb-glued2"; printf 'Deferred.\n\nReTracks #7001\n' > "$PRB_GLUED2"
neg "ReTracks #7001 is not a Tracks companion (left boundary)" \
    "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" "$PRB_GLUED2"

# --- FR4: an UNBALANCED fence must fail CLOSED ------------------------------
# The two sibling ship gates end their fence-stripper with
# `END { if (in_fence) exit 2 }`; this gate's had no such arm, so an unbalanced
# fence silently degraded to "strip nothing after the opener". Discriminating
# fixture: the claim sits BEFORE the unclosed fence, so a fail-OPEN stripper
# keeps it (exempt) and a fail-CLOSED one discards everything (blocked).
PRB_UNBAL="$WORK/prb-unbal"; printf 'Deferred.\n\nTracks #7004\n' > "$PRB_UNBAL"
PR_BODY_FILE="$PRB_UNBAL"; export PR_BODY_FILE
set_issues "$(mk_issue 7004 "$(printf 'From #999.\n\nMandated-By: %s\n\n```\nunclosed fence\n' "$MANDATED")" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "unbalanced fence in the ISSUE body fails CLOSED"
else fail "unbalanced fence must fail closed; got exit $CASE_RC"; fi

# Same property on the PR-body side, where the companion lives.
PRB_UNBAL2="$WORK/prb-unbal2"; printf 'Tracks #7005\n\n```\nunclosed\n' > "$PRB_UNBAL2"
PR_BODY_FILE="$PRB_UNBAL2"; export PR_BODY_FILE
set_issues "$(mk_issue 7005 "$(claim_body "$MANDATED")" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "unbalanced fence in the PR body fails CLOSED"
else fail "unbalanced PR-body fence must fail closed; got exit $CASE_RC"; fi

# --- The self-grant guard ---------------------------------------------------
# With merge-base unresolvable, a bare `git show :AGENTS.rules.md` reads the
# AUTHOR'S STAGED INDEX -- returning rc=0 and a full id list, so the read
# "succeeds" and no empty-set warning fires. That is a fail-open that lets a PR
# grant itself the exemption it is introducing. Two assertions, because the
# behavioural one alone would also pass if the gate read the index and the index
# happened not to match.
PR_BODY_FILE="$PRB_OK"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)"
MB_FAIL=1; export MB_FAIL
run_gate
MB_FAIL=0; export MB_FAIL
if [[ "$CASE_RC" -eq 1 ]]; then pass "unresolvable merge-base => NOT exempt (fails CLOSED)"
else fail "merge-base failure must fail closed; got exit $CASE_RC"; fi
if grep -qE '^show :AGENTS\.rules\.md$' "$GIT_CALLS"; then
  fail "gate read the STAGED INDEX via a bare ':path' -- author-controlled self-grant"
else pass "gate never issues a bare ':path' git show (index is not read)"
fi
if grep -qiE 'mandating rules: 0|corpus' "$WORK/out"; then pass "corpus-read failure is announced in the report"
else fail "corpus read failure must be visible; got: $(tr '\n' '|' < "$WORK/out")"; fi

# --- Rejection causes are named, not collapsed ------------------------------
# Six distinct causes otherwise render identically as "Exempt: 0", which makes
# the gate undebuggable exactly when an agent is blocked and guessing.
set_issues "$(mk_issue 7002 "$(claim_body wg-defer-only-after-inline-triage)" OPEN)"
run_gate
if grep -qE '^  Rejected:.*#7002.*wg-defer-only-after-inline-triage' "$WORK/out"; then
  pass "Rejected: line names the issue and the offending claim"
else fail "expected a Rejected: line naming #7002; got: $(tr '\n' '|' < "$WORK/out")"; fi


# --- The derivation uses the ACK GATE'S OWN PARSER, not a second grep --------
# Four conjuncts (gated section, `- ` at column 0, not pointer-shaped, prefix),
# not one. A shell grep enforced only the prefix, so an indented sub-bullet or a
# prose line carrying the marker was honoured while being invisible to ADR-092,
# the hash manifest and lint-rule-ids.py -- a permanent repo-wide self-grant
# needing no ack. Measured: the grep form derived 4 ids where parse_bodies sees 2.
PRB_SHAPE="$WORK/prb-shape"; printf 'Deferred.\n\nTracks #7010\nTracks #7011\n' > "$PRB_SHAPE"
PR_BODY_FILE="$PRB_SHAPE"; export PR_BODY_FILE
set_issues "$(mk_issue 7010 "$(claim_body wg-indented-subbullet-must-not-derive)" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "INDENTED sub-bullet carrying the marker is NOT derived"
else fail "indented sub-bullet self-granted the exemption; exit $CASE_RC"; fi
set_issues "$(mk_issue 7011 "$(claim_body wg-prose-line-must-not-derive)" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "PROSE line carrying the marker is NOT derived"
else fail "prose line self-granted the exemption; exit $CASE_RC"; fi

# The SECTION conjunct: a perfectly-formed body line with a gated prefix, under a
# heading outside SECTIONS. Without `not in_section` this derives while the ack
# gate still cannot see it -- measured, that mutation SURVIVED the first battery
# because every other fixture line sat under a gated heading.
PRB_SECT="$WORK/prb-sect"; printf 'Deferred.\n\nTracks #7012\n' > "$PRB_SECT"
PR_BODY_FILE="$PRB_SECT"; export PR_BODY_FILE
set_issues "$(mk_issue 7012 "$(claim_body wg-ungated-section-must-not-derive)" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "body line under an UNGATED section is NOT derived"
else fail "ungated-section rule self-granted the exemption; exit $CASE_RC"; fi

# --- Cardinality: EXEMPT must subtract exactly, not zero out ----------------
# Every other exemption fixture is a single issue, under which `NET=0 if EXEMPT>0`
# is indistinguishable from `FILED - EXEMPT - CLOSING`. 1-of-1 is all-of-1.
PRB_MULTI="$WORK/prb-multi"; printf 'Deferred.\n\nTracks #7001\n' > "$PRB_MULTI"
PR_BODY_FILE="$PRB_MULTI"; export PR_BODY_FILE
{
  mk_issue 7001 "$(claim_body "$MANDATED")" OPEN
  mk_issue 7002 "Follow-up from #999, no claim." OPEN
  mk_issue 7003 "Another from #999, no claim." OPEN
  mk_issue 7004 "A third from #999, no claim." OPEN
} | jq -s '.' > "$WORK/issues-multi"
ISSUE_LIST_FILE="$WORK/issues-multi"; export ISSUE_LIST_FILE
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "1 exempt of 4 filed still BLOCKS (exemption subtracts, not zeroes)"
else fail "4 filed / 1 exempt must block; got exit $CASE_RC"; fi
if grep -qE '^  Filing:[[:space:]]+4\b' "$WORK/out" \
   && grep -qE '^  Exempt:[[:space:]]+1\b' "$WORK/out" \
   && grep -qE '^  Net:[[:space:]]+\+3\b' "$WORK/out"; then
  pass "Filing: 4 / Exempt: 1 / Net: +3 (arithmetic, not a boolean)"
else fail "expected Filing: 4, Exempt: 1, Net: +3; got: $(tr '\n' '|' < "$WORK/out")"; fi

# Two exempt in one run — pins the pair formatter, never exercised past one entry.
PRB_TWO="$WORK/prb-two"; printf 'Deferred.\n\nTracks #7001\nRefs #7005\n' > "$PRB_TWO"
PR_BODY_FILE="$PRB_TWO"; export PR_BODY_FILE
{
  mk_issue 7001 "$(claim_body "$MANDATED")" OPEN
  mk_issue 7005 "$(claim_body wg-when-deferring-a-capability-create-a)" OPEN
} | jq -s '.' > "$WORK/issues-two"
ISSUE_LIST_FILE="$WORK/issues-two"; export ISSUE_LIST_FILE
run_gate
if grep -qE '^  Exempt:[[:space:]]+2\b.*#7001.*#7005' "$WORK/out"; then
  pass "two exemptions render as a joined pair list"
else fail "expected both #7001 and #7005 on the Exempt: line; got: $(tr '\n' '|' < "$WORK/out")"; fi

# --- A fenced close-keyword must NOT buy NET credit -------------------------
# CLOSING read the RAW body while the marker, claim and companion matches all
# read the stripped one. A quoted commit message or issue body -- routine in this
# repo's PR descriptions -- therefore bought a free unit of NET.
PRB_FENCED_CLOSE="$WORK/prb-fenced-close"
printf 'Quoting an issue body for context:\n\n```\nCloses #4242\n```\n\nNothing actually closed.\n' > "$PRB_FENCED_CLOSE"
PR_BODY_FILE="$PRB_FENCED_CLOSE"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "Follow-up from #999." OPEN)"
run_gate
if grep -qE '^  Closing:[[:space:]]+0\b' "$WORK/out"; then pass "fenced 'Closes #N' does NOT count toward CLOSING"
else fail "fenced close-keyword inflated CLOSING; got: $(tr '\n' '|' < "$WORK/out")"; fi
if [[ "$CASE_RC" -eq 1 ]]; then pass "fenced close-keyword still BLOCKS (no free NET credit)"
else fail "fenced 'Closes' bought a pass; exit $CASE_RC"; fi

# --- Rejection causes are DISTINCT, not one collapsed string ----------------
# Sampling one cause of six cannot detect them all collapsing to "rejected".
PRB_CAUSES="$WORK/prb-causes"; printf 'Deferred.\n\nTracks #7001\nTracks #7002\nTracks #7003\n' > "$PRB_CAUSES"
PR_BODY_FILE="$PRB_CAUSES"; export PR_BODY_FILE
{
  mk_issue 7001 "Follow-up from #999, no claim at all." OPEN
  mk_issue 7002 "$(printf 'From #999.\n\nMandated-By: %s\nMandated-By: wg-bogus\n' "$MANDATED")" OPEN
  mk_issue 7003 "$(claim_body "$MANDATED")" CLOSED
} | jq -s '.' > "$WORK/issues-causes"
ISSUE_LIST_FILE="$WORK/issues-causes"; export ISSUE_LIST_FILE
run_gate
distinct=0
grep -qE '^  Rejected:.*#7001 \(no Mandated-By' "$WORK/out" && distinct=$((distinct + 1))
grep -qE '#7002 \(multiple Mandated-By' "$WORK/out" && distinct=$((distinct + 1))
grep -qE '#7003 \(issue is not OPEN' "$WORK/out" && distinct=$((distinct + 1))
if [[ "$distinct" -eq 3 ]]; then pass "three rejection causes render DISTINCTLY (not one collapsed string)"
else fail "expected 3 distinct causes, matched $distinct; got: $(tr '\n' '|' < "$WORK/out")"; fi

# --- Telemetry: the gate's own rows, read from the incident file ------------
# A source grep for `_emit warn` is satisfied by a body replaced with `:`.
# The attribution rule_id is the feature's stated justification and had no test.
INC="$INCIDENTS_REPO_ROOT/.claude/.rule-incidents.jsonl"
rm -f "$INC"
PR_BODY_FILE="$PRB_OK"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)"
run_gate
attr=0
if [[ -r "$INC" ]]; then
  attr="$(jq -sr --arg r "net-issue-flow-mandated-filing--$MANDATED" \
    '[.[] | select(.rule_id == $r and .event_type == "bypass")] | length' < "$INC" 2>/dev/null || echo 0)"
fi
if [[ "$attr" -ge 1 ]]; then pass "exempt emits per-rule attribution in the STRUCTURED rule_id"
else fail "expected a bypass row under net-issue-flow-mandated-filing--<rule>; got $attr"; fi

# A rejected (non-exempt) run must NOT emit an attribution row — otherwise the
# assertion above passes on every invocation and proves nothing.
rm -f "$INC"
set_issues "$(mk_issue 7001 "$(claim_body wg-does-not-exist-anywhere)" OPEN)"
run_gate
attr_neg=0
if [[ -r "$INC" ]]; then
  attr_neg="$(jq -sr '[.[] | select(.rule_id | startswith("net-issue-flow-mandated-filing--"))] | length' < "$INC" 2>/dev/null || echo 0)"
fi
if [[ "$attr_neg" -eq 0 ]]; then pass "a rejected claim emits NO attribution row (the row is discriminating)"
else fail "non-exempt run emitted $attr_neg attribution row(s)"; fi

# corpus-unreadable and zero-tagged must be DISTINCT ids, not one.
rm -f "$INC"
MB_FAIL=1; export MB_FAIL
run_gate
MB_FAIL=0; export MB_FAIL
unreadable=0
if [[ -r "$INC" ]]; then
  unreadable="$(jq -sr '[.[] | select(.rule_id == "net-issue-flow-mandated-filing-corpus-unreadable")] | length' < "$INC" 2>/dev/null || echo 0)"
fi
if [[ "$unreadable" -ge 1 ]]; then pass "corpus-unreadable emits its own rule_id"
else fail "expected a corpus-unreadable row; got $unreadable"; fi

# A corpus that reads OK but tags NOTHING is a different condition and must say so.
rm -f "$INC"
: > "$WORK/corpus-empty"
printf '## Workflow Gates\n\n- A rule with no marker at all [id: wg-untagged-fixture-rule].\n' > "$WORK/corpus-empty"
CORPUS_FILE="$WORK/corpus-empty"; export CORPUS_FILE
run_gate
zero=0
if [[ -r "$INC" ]]; then
  zero="$(jq -sr '[.[] | select(.rule_id == "net-issue-flow-mandated-filing-zero-tagged")] | length' < "$INC" 2>/dev/null || echo 0)"
fi
if [[ "$zero" -ge 1 ]]; then pass "read-OK-but-zero-tagged emits a DISTINCT rule_id from unreadable"
else fail "expected a zero-tagged row; got $zero"; fi
if grep -qiE 'zero rules tagged' "$WORK/out"; then pass "zero-tagged corpus is announced in the report"
else fail "zero-tagged must be visible; got: $(tr '\n' '|' < "$WORK/out")"; fi
CORPUS_FILE="$WORK/corpus-default"; export CORPUS_FILE

# --- Cross-file parity: the emitted id prefix and the aggregator's reader ----
# Two literal copies of one string in two languages. If the emitter changes,
# summary.gate_exemptions silently becomes [] and the orphan gate cannot see it
# (it exempts everything startswith("net-issue-flow")). The PR's own thesis.
for pair in "net-issue-flow-mandated-filing--:$GATE" \
            "net-issue-flow-mandated-filing--:$AGG" \
            "net-issue-flow-timeout:$REPO_ROOT/.claude/hooks/ship-net-issue-flow-gate.sh" \
            "net-issue-flow-timeout:$AGG"; do
  lit="${pair%%:*}"; f="${pair#*:}"
  if grep -qF -- "$lit" "$f"; then pass "parity: '$lit' present in ${f##*/}"
  else fail "parity broken: '$lit' missing from ${f##*/} — readout would go silently empty"; fi
done

# --- The blanket override is untouched (FR7) --------------------------------
# It must keep working unchanged for the cases the exemption cannot cover --
# most filing sites are SKILL.md phase mandates with no rule id to tag.
PR_BODY_FILE="$WORK/prb-override"; export PR_BODY_FILE
{ printf 'Architectural pivot.\n'; printf '<!-- gate-override: net-issue-flow -->\n'; } > "$PR_BODY_FILE"
set_issues "$(mk_issue 7001 "$(claim_body wg-does-not-exist-anywhere)" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 0 ]]; then pass "blanket override still passes an unexemptable filing"
else fail "blanket override must remain functional; got exit $CASE_RC"; fi

# --- TR7a: the SHIPPED corpus derives exactly the ONE intended id -----------
# Runs against the real worktree AGENTS.rules.md, so it proves the tag actually
# shipped. (The merge-base set is necessarily empty until this PR merges -- an
# assertion against merge-base here would be unsatisfiable by construction.)
#
# DELIBERATE CHANGE (#7174, 2026-08-03): this asserted TWO ids until the
# operator untagged `wg-when-deferring-a-capability-create-a`. The decisive
# reason was that NOTHING WRITES that claim -- every writer emits
# `wg-block-pr-ready-on-undeferred-operator-steps` literally (ship/SKILL.md
# Phase 5.5, work/SKILL.md operator-only deferral row), so citing the other id
# would have been hand-authored free-form text. This assertion is EXACT (not
# a superset check) precisely so that re-tagging a rule cannot happen silently:
# widening it back is a deliberate edit, reviewed alongside the ack row that
# ADR-092 already forces. The multi-id derivation path stays covered by the
# synthetic `corpus-default` fixture above, which still carries several tags.
# Derive via the AUTHORITY's own parser, not a second grep. ADR-155 names
# the shell form by name as "a strict SUPERSET along the line-shape axis"
# (it derived 4 ids where parse_bodies saw 2), and the gate itself consumes
# --emit-mandating-ids. A test that re-implements the predicate can agree
# with the gate today and diverge silently tomorrow.
derived="$(python3 "$REPO_ROOT/scripts/lint-rule-bodies.py" --emit-mandating-ids \
  < "$REPO_ROOT/AGENTS.rules.md" | sort -u | tr '\n' ' ')"
if [[ "$derived" == "wg-block-pr-ready-on-undeferred-operator-steps " ]]; then
  pass "worktree corpus derives exactly the 1 intended id"
else fail "worktree corpus derived: '$derived'"; fi

# --- Help text (FR8) --------------------------------------------------------
# Asserted against the gate's OWN BLOCKED OUTPUT, not against its source. A
# source grep for 'Mandated-By:' also matches the jq predicate and the header
# comments, so it stays green with the entire remedy block deleted -- measured:
# that mutation SURVIVED the first battery.
PR_BODY_FILE="$PRB_NONE"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)"
run_gate
if [[ "$CASE_RC" -eq 1 ]]; then pass "remedy fixture actually blocks (positive control)"
else fail "remedy fixture must block to print the remedy; got exit $CASE_RC"; fi
if grep -qE '^  \(d\) Mandated filing' "$WORK/out"; then pass "BLOCKED output offers the (d) mandated-filing exit"
else fail "blocked output must offer (d); got: $(tr '\n' '|' < "$WORK/out")"; fi
if grep -qE '^        Mandated-By: <rule-id>' "$WORK/out"; then pass "BLOCKED output shows the literal claim form"
else fail "blocked output must show 'Mandated-By: <rule-id>'"; fi
if grep -qE '^      Rules that currently qualify:' "$WORK/out" \
   && grep -qE "^        $MANDATED\$" "$WORK/out"; then
  pass "BLOCKED output enumerates the qualifying rules (no guessing required)"
else fail "blocked output must list the qualifying ids; got: $(tr '\n' '|' < "$WORK/out")"; fi
if grep -qE 'NOT in that list.*unavailable|unavailable to you' "$WORK/out"; then
  pass "BLOCKED output names the untagged-rule dead end"
else fail "blocked output must tell an untagged-rule agent that (d) is unavailable"; fi
if ! grep -qi 'architectural-pivot deferral' "$WORK/out"; then
  pass "BLOCKED output no longer frames the override as architectural-pivot-only"
else fail "blocked output still calls the override an 'architectural-pivot deferral'"; fi
if ! grep -qi 'architectural-pivot deferral' "$GATE"; then
  pass "gate source carries no 'architectural-pivot deferral' framing"
else fail "gate still calls the override an 'architectural-pivot deferral'"; fi

HOOK_GATE="$REPO_ROOT/.claude/hooks/ship-net-issue-flow-gate.sh"
if ! grep -qi 'architectural-pivot deferral' "$HOOK_GATE"; then
  pass "hook remedy text no longer frames the override as architectural-pivot-only"
else fail "hook still calls the override an 'architectural-pivot deferral'"; fi
for needle in "Fix inline" "Close something" "Override" "gate-override: net-issue-flow"; do
  if grep -qF -- "$needle" "$HOOK_GATE"; then pass "hook remedy needle survives FR8: $needle"
  else fail "FR8 removed a needle the hook suite pins: $needle"; fi
done

printf '\n'

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR. Set AT the running count, never below it: a floor with
# slack silently absorbs a deleted case, which is the one thing it exists to
# stop. `-lt` (a floor, not equality) so the suite can grow without churn --
# lower it only deliberately.
#
# Motivating vacuity: before this run the suite had no pass COUNTER at all, so
# deleting a case changed nothing observable. Baseline before the exemption
# work was 23.
# ---------------------------------------------------------------------------
MIN_ASSERTIONS=84
if [[ "$passes" -lt "$MIN_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity floor: %d assertions ran, expected >= %d\n' "$passes" "$MIN_ASSERTIONS"
  fails=$((fails + 1))
fi

if [[ "$fails" -eq 0 ]]; then
  printf 'net-issue-flow.test.sh: ALL PASS (%d assertions)\n' "$passes"
  exit 0
fi
printf 'net-issue-flow.test.sh: %d FAILED (%d passed)\n' "$fails" "$passes"
exit 1
