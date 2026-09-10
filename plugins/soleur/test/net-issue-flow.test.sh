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
# INJECTION SEAM. AC-G4 runs a real differential against the pre-change gate, so
# the suite must be able to point at another copy. The DEFAULT is asserted below:
# without that assertion a stray `NET_ISSUE_FLOW_GATE` in the environment silently
# redirects every case, which is a fail-open in the harness itself — the suite
# would report on a file nobody chose.
GATE_DEFAULT="$REPO_ROOT/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"
GATE="${NET_ISSUE_FLOW_GATE:-$GATE_DEFAULT}"

# RUNNING THE AC-G4 DIFFERENTIAL: the pre-change gate must be staged somewhere,
# and the gate resolves its incidents lib as `dirname "$BASH_SOURCE"/../../../../..`
# — five levels up — so a copy at any other depth silently emits NO telemetry and
# three ledger assertions fail for a reason that has nothing to do with the
# property under test. Measured: 10 failures instead of 7. The gate honours
# CLAUDE_PROJECT_DIR first, so set it:
#
#   CLAUDE_PROJECT_DIR="$PWD" NET_ISSUE_FLOW_GATE=<pristine-copy> bash <this file>
#
# Without it the differential is not a differential — it is two files disagreeing
# about where the repo is.

fails=0
# `passes` exists for the anti-vacuity floor at the bottom. Before it, pass()
# only printed, so there was no count to floor against and a deleted case was
# indistinguishable from a case that never existed.
passes=0
# `cases` is the INDEPENDENT counter, incremented at every assertion CALL SITE and
# never inside pass()/fail(). That placement is the whole substance of the
# conservation check at the bottom of this file: a counter that moves inside the
# verdict helpers moves WITH the verdict, so stubbing fail() to a no-op drops the
# row and its count together and the identity still holds. `passes` alone cannot
# serve — it DEFLATES when verdicts are discarded, so a floor reading it reports
# "too few assertions" and names the wrong fault.
#
# Never increment inside `$( )` — a subshell discards it.
cases=0
pass() { printf '  ok   %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# ---------------------------------------------------------------------------
# INSTRUMENT SELF-TEST. Drive BOTH verdict helpers once and require each to move
# its OWN counter, before any real assertion runs.
#
# The conservation check at the end of this file is DIRECTION-BLIND, and its
# comment used to claim otherwise ("the arm that catches a NEUTERED verdict
# helper"). It compares passes+fails against cases, so a fail() that increments
# `passes` instead of `fails` satisfies it exactly, keeps `fails` at 0, and the
# suite reports ALL PASS at exit 0. Measured during the #7896 review: with that
# one-token swap AND the declared-filing arm reverted to a dead literal, this
# suite printed TEN `FAIL` lines on screen and still exited 0.
#
# The anti-vacuity floor cannot see it either -- the floor reads `cases`, which
# is untouched.
#
# This control does NOT cover neg(), and an earlier revision of this comment
# claimed it did. Measured: disarming neg() (`-eq 1` -> `-ge 0`) while breaking
# the gate left this suite at ALL PASS / exit 0. The reason is structural --
# neg() decides its OWN verdict and then calls pass(), so the helpers are both
# behaving perfectly and the wrong branch was taken before either ran. A
# verdict-machinery control cannot see an assertion that asserts the wrong
# thing; only a control that proves neg() can still REJECT can. That one is
# immediately below.
#
# Reported with printf + exit 1 DIRECTLY, never through fail(): a check enforced
# through the suspect cannot witness the suspect (ADR-193).
# ---------------------------------------------------------------------------
_p0=$passes; _f0=$fails
pass "instrument self-test: pass() records a pass" >/dev/null
fail "instrument self-test: fail() records a failure (EXPECTED, not a real failure)" >/dev/null
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  printf '\n[FATAL] verdict helpers are neutered: pass() moved passes by %d (want 1), fail() moved fails by %d (want 1).\n' \
    "$((passes - _p0))" "$((fails - _f0))" >&2
  printf '  Every verdict this suite records is therefore unreliable; refusing to report a result.\n' >&2
  exit 1
fi
# Unwind the control so the real accounting is untouched. `cases` was never
# incremented, so the floor and the conservation identity both stay exact.
passes=$_p0; fails=$_f0

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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "net=+3 without override BLOCKS (exit 1)"
else fail "net=+3 without override should exit 1, got $CASE_RC"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "net=+3 WITH override PASSES (exit 0)"
else fail "net=+3 with override should exit 0, got $CASE_RC"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "net=-2 passes (exit 0)"
else fail "net=-2 should exit 0, got $CASE_RC"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "gh failure fails OPEN (exit 0)"
else fail "gh failure should fail open with exit 0, got $CASE_RC"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ -n "$issue_call" ]]; then pass "issue list was invoked"
else fail "issue list was never invoked"; fi
cases=$((cases + 1))
if [[ "$issue_call" == *"--limit 500"* ]]; then pass "FILED query passes --limit 500 (default 30 undercounts)"
else fail "FILED query must pass --limit 500; got: $issue_call"; fi
cases=$((cases + 1))
if [[ "$issue_call" != *"--search"* ]]; then pass "FILED query does NOT use --search (empty under App token)"
else fail "FILED query must not use --search; got: $issue_call"; fi
cases=$((cases + 1))
if [[ "$issue_call" == *"--state all"* ]]; then pass "FILED query uses --state all"
else fail "FILED query must use --state all; got: $issue_call"; fi

# #7759 — the FIFTH pinned property, previously uncovered. The four above pin
# WHICH issues come back; this pins WHICH FIELDS come with them, and the failure
# mode is the same family: dropping `createdAt` makes every row fail the
# `select((.createdAt // "") >= $since)` recency guard, so FILED=0 and the gate
# PASSES on every PR, silently. `state` is equally load-bearing — the ADR-155
# exemption reads it, and `number`/`body` are the row identity and the citation
# corpus. Asserted per FIELD, not as one string match: a single `--json` blob
# comparison would go red on a harmless reordering and green on a partial list.
# Extract the --json OPERAND and test membership in THAT, never a substring of
# the whole call line. Measured: a bare `*state*` match against the line is
# satisfied by the unrelated `--state all` flag, so dropping `state` from the
# field list left the assertion green — the exact bare-token vacuity this
# repo's cq-assert-anchor-not-bare-token names, in an assertion written to
# close an always-pass path.
_json_fields="$(printf '%s\n' "$issue_call" | sed -n 's/.*--json[[:space:]]\{1,\}\([A-Za-z,]*\).*/\1/p')"
cases=$((cases + 1))
if [[ -n "$_json_fields" ]]; then pass "FILED query passes --json with a field list"
else fail "could not extract a --json field list from: $issue_call"; fi
for _f in number body createdAt state; do
  cases=$((cases + 1))
  if [[ ",$_json_fields," == *",$_f,"* ]]; then
    pass "FILED query requests --json field: $_f"
  else
    fail "FILED query must request --json field '$_f'; got --json '$_json_fields'"
  fi
done
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "marker outside a fence still overrides"
else fail "real override was swallowed by the fence strip; exit $CASE_RC"; fi

# ---------------------------------------------------------------------------
# Case 13 (review finding): the fail-open event_type must be one the aggregator
# actually counts. rule-metrics-aggregate.sh counts only deny/bypass/applied/
# warn -- a 'transient' row increments nothing, so the operator cannot tell
# "never fired" from "fail-opened every time".
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if grep -qE '_emit[[:space:]]+warn' "$GATE" && ! grep -qE '_emit[[:space:]]+transient' "$GATE"; then
  pass "fail-open emits a counted event_type (warn, not transient)"
else
  fail "fail-open must emit 'warn'; 'transient' is counted by nothing"
fi

# Case 14: the emitted rule_id must be exempt in the aggregator, or the first
# real event hard-fails the metrics run (exit 5) via the orphan gate.
#
# Rewritten for #7853. These used to grep for two hand-maintained exemption stanzas
# (`startswith("net-issue-flow")`, `startswith("cost-of-filing-")`). Those stanzas are gone: the
# orphan gate now asks whether an id CLAIMS corpus membership by carrying a section prefix, so these
# ids are exempt structurally rather than by enumeration. Grepping for a deleted stanza would test
# the mechanism instead of the property, and would have to be rewritten again at the next refactor.
#
# The property is tested against the aggregator's OWN regex, extracted from it rather than restated
# here. That keeps this a genuine cross-file parity check: if the aggregator ever widens its
# predicate to capture these ids, this reds, which is exactly the failure the original cases
# existed to prevent.
AGG="$REPO_ROOT/scripts/rule-metrics-aggregate.sh"
cases=$((cases + 1))
PREFIX_RE="$(grep -oE 'test\("\^\(hr\|wg\|cq\|rf\|pdr\|cm\)-"\)' "$AGG" 2>/dev/null | head -1)"
if [[ -n "$PREFIX_RE" ]]; then
  pass "aggregator carries the section-prefix orphan predicate"
else
  fail "aggregator has NO section-prefix predicate -- the structural exemption below is unfounded"
fi
# Derive the bracketed alternation from the extracted predicate so the shell test uses the same
# prefixes the aggregator does, rather than a second copy that can drift.
PREFIX_ALT="$(printf '%s' "$PREFIX_RE" | sed -E 's/^test\("\^\(//; s/\)-"\)$//')"
for rid in "net-issue-flow" "cost-of-filing-inline-cheaper"; do
  cases=$((cases + 1))
  if [[ -n "$PREFIX_ALT" ]] && [[ "$rid" =~ ^($PREFIX_ALT)- ]]; then
    fail "$rid carries a section prefix -> the aggregator would treat it as an orphan (exit 5)"
  else
    pass "$rid carries no section prefix -> structurally exempt from the orphan gate"
  fi
done

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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "validly-mandated filing is EXEMPT (exit 0)"
else fail "mandated filing should be exempt; exit $CASE_RC / $(tr '\n' '|' < "$WORK/out")"; fi

# The report must stay honest: the filing is still COUNTED, and the exemption is
# shown on its own line naming the rule. An exemption that silently reduces
# `Filing:` is worse than the blanket override, because the override at least
# leaves a marker in the PR body.
cases=$((cases + 1))
if grep -qE '^  Filing:[[:space:]]+1\b' "$WORK/out"; then pass "Filing: keeps its true count (1), not reduced by the exemption"
else fail "Filing: must remain 1; got: $(tr '\n' '|' < "$WORK/out")"; fi
cases=$((cases + 1))
if grep -qE "^  Exempt:[[:space:]]+1\b.*#7001.*$MANDATED" "$WORK/out"; then pass "Exempt: line names the issue AND the mandating rule"
else fail "Exempt: line must name #7001 and $MANDATED; got: $(tr '\n' '|' < "$WORK/out")"; fi
cases=$((cases + 1))
if grep -qE '^  Net:[[:space:]]+\+0\b' "$WORK/out"; then pass "Net: +0 after exemption (1 filed, 1 exempt, 0 closing)"
else fail "expected 'Net: +0'; got: $(tr '\n' '|' < "$WORK/out")"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "corpus is read from the MERGE-BASE, not the worktree"
else fail "merge-base-only rule id was not honoured => gate is reading some other corpus; exit $CASE_RC"; fi
PR_BODY_FILE="$PRB_OK"; export PR_BODY_FILE
set_issues "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)"
run_gate

# CRLF regression pin. GitHub returns CRLF for web-authored bodies; a `[ \t]`-only
# anchor fails closed on a CORRECT claim, silently and permanently.
set_issues "$(mk_issue 7001 "$(printf 'Follow-up from #999.\r\n\r\nMandated-By: %s\r\n' "$MANDATED")" OPEN)"
run_gate
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 0 ]]; then pass "CRLF-bodied claim is exempt (\\r tolerated)"
else fail "CRLF body broke the claim match; exit $CASE_RC"; fi

# --- Direction 2: everything else is NOT exempt -----------------------------
# Each of these must BLOCK. Fixtures all on the positive side cannot detect an
# exemption that is too permissive, which is the direction that matters here.
neg() { # $1=label  $2=issue-json  [$3=pr-body-file]
  local label="$1" issue="$2" prb="${3:-$PRB_OK}"
  PR_BODY_FILE="$prb"; export PR_BODY_FILE
  cases=$((cases + 1))
  set_issues "$issue"
  run_gate
  if [[ "$CASE_RC" -eq 1 ]]; then pass "NOT exempt: $label"
  else fail "NOT exempt expected (exit 1) for $label; got exit $CASE_RC / $(tr '\n' '|' < "$WORK/out")"; fi
}

# ---------------------------------------------------------------------------
# neg() REJECTION CONTROL. neg() owns 16 of this suite assertions and the entire
# "the exemption is too permissive" direction, and it decides its own verdict --
# so a one-token edit to its comparison (`-eq 1` -> `-ge 0`) turns every one of
# those 16 into an unconditional pass while pass(), fail(), the conservation
# check and the floor all stay perfectly healthy. Measured (#7896 review): that
# edit, combined with dropping the companion regex left boundary in the gate so
# `BackRefs`/`ReTracks` grant the exemption, left this suite at
# `ALL PASS (104 assertions)`, exit 0.
#
# The only thing that can witness it is proof that neg() still REJECTS. Drive it
# once with an input that IS exempt -- valid whole-line claim, tagged rule, OPEN,
# and a companion in $PRB_OK -- and require it to have recorded a FAILURE.
#
# Counters are snapshotted and unwound, so this costs the real accounting
# nothing. Reported with printf + exit 1 directly, never through fail(): the
# helper under test must not be the one reporting on it (ADR-193).
# ---------------------------------------------------------------------------
_np=$passes; _nf=$fails; _nc=$cases
neg "control: an EXEMPT issue must be REJECTED by neg()" \
    "$(mk_issue 7001 "$(claim_body "$MANDATED")" OPEN)" >/dev/null
if [[ $((fails - _nf)) -ne 1 ]]; then
  printf '\n[FATAL] neg() no longer rejects: an exempt input recorded %d failure(s), want 1.\n' \
    "$((fails - _nf))" >&2
  printf '  Every "NOT exempt" assertion in this suite is therefore unconditional.\n' >&2
  exit 1
fi
passes=$_np; fails=$_nf; cases=$_nc

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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "unbalanced fence in the ISSUE body fails CLOSED"
else fail "unbalanced fence must fail closed; got exit $CASE_RC"; fi

# Same property on the PR-body side, where the companion lives.
PRB_UNBAL2="$WORK/prb-unbal2"; printf 'Tracks #7005\n\n```\nunclosed\n' > "$PRB_UNBAL2"
PR_BODY_FILE="$PRB_UNBAL2"; export PR_BODY_FILE
set_issues "$(mk_issue 7005 "$(claim_body "$MANDATED")" OPEN)"
run_gate
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "unresolvable merge-base => NOT exempt (fails CLOSED)"
else fail "merge-base failure must fail closed; got exit $CASE_RC"; fi
cases=$((cases + 1))
if grep -qE '^show :AGENTS\.rules\.md$' "$GIT_CALLS"; then
  fail "gate read the STAGED INDEX via a bare ':path' -- author-controlled self-grant"
else pass "gate never issues a bare ':path' git show (index is not read)"
fi
cases=$((cases + 1))
if grep -qiE 'mandating rules: 0|corpus' "$WORK/out"; then pass "corpus-read failure is announced in the report"
else fail "corpus read failure must be visible; got: $(tr '\n' '|' < "$WORK/out")"; fi

# --- Rejection causes are named, not collapsed ------------------------------
# Six distinct causes otherwise render identically as "Exempt: 0", which makes
# the gate undebuggable exactly when an agent is blocked and guessing.
set_issues "$(mk_issue 7002 "$(claim_body wg-defer-only-after-inline-triage)" OPEN)"
run_gate
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "INDENTED sub-bullet carrying the marker is NOT derived"
else fail "indented sub-bullet self-granted the exemption; exit $CASE_RC"; fi
set_issues "$(mk_issue 7011 "$(claim_body wg-prose-line-must-not-derive)" OPEN)"
run_gate
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "1 exempt of 4 filed still BLOCKS (exemption subtracts, not zeroes)"
else fail "4 filed / 1 exempt must block; got exit $CASE_RC"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if grep -qE '^  Closing:[[:space:]]+0\b' "$WORK/out"; then pass "fenced 'Closes #N' does NOT count toward CLOSING"
else fail "fenced close-keyword inflated CLOSING; got: $(tr '\n' '|' < "$WORK/out")"; fi
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$zero" -ge 1 ]]; then pass "read-OK-but-zero-tagged emits a DISTINCT rule_id from unreadable"
else fail "expected a zero-tagged row; got $zero"; fi
cases=$((cases + 1))
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
  cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
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
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "remedy fixture actually blocks (positive control)"
else fail "remedy fixture must block to print the remedy; got exit $CASE_RC"; fi
cases=$((cases + 1))
if grep -qE '^  \(d\) Mandated filing' "$WORK/out"; then pass "BLOCKED output offers the (d) mandated-filing exit"
else fail "blocked output must offer (d); got: $(tr '\n' '|' < "$WORK/out")"; fi
cases=$((cases + 1))
if grep -qE '^        Mandated-By: <rule-id>' "$WORK/out"; then pass "BLOCKED output shows the literal claim form"
else fail "blocked output must show 'Mandated-By: <rule-id>'"; fi
cases=$((cases + 1))
if grep -qE '^      Rules that currently qualify:' "$WORK/out" \
   && grep -qE "^        $MANDATED\$" "$WORK/out"; then
  pass "BLOCKED output enumerates the qualifying rules (no guessing required)"
else fail "blocked output must list the qualifying ids; got: $(tr '\n' '|' < "$WORK/out")"; fi
cases=$((cases + 1))
if grep -qE 'NOT in that list.*unavailable|unavailable to you' "$WORK/out"; then
  pass "BLOCKED output names the untagged-rule dead end"
else fail "blocked output must tell an untagged-rule agent that (d) is unavailable"; fi
cases=$((cases + 1))
if ! grep -qi 'architectural-pivot deferral' "$WORK/out"; then
  pass "BLOCKED output no longer frames the override as architectural-pivot-only"
else fail "blocked output still calls the override an 'architectural-pivot deferral'"; fi
cases=$((cases + 1))
if ! grep -qi 'architectural-pivot deferral' "$GATE"; then
  pass "gate source carries no 'architectural-pivot deferral' framing"
else fail "gate still calls the override an 'architectural-pivot deferral'"; fi

HOOK_GATE="$REPO_ROOT/.claude/hooks/ship-net-issue-flow-gate.sh"
cases=$((cases + 1))
if ! grep -qi 'architectural-pivot deferral' "$HOOK_GATE"; then
  pass "hook remedy text no longer frames the override as architectural-pivot-only"
else fail "hook still calls the override an 'architectural-pivot deferral'"; fi
for needle in "Fix inline" "Close something" "Override" "gate-override: net-issue-flow"; do
  cases=$((cases + 1))
  if grep -qF -- "$needle" "$HOOK_GATE"; then pass "hook remedy needle survives FR8: $needle"
  else fail "FR8 removed a needle the hook suite pins: $needle"; fi
done

printf '\n'

# ===========================================================================
# #7759 — a filing that cites the ISSUE instead of the PR must still be counted
# when the PR's own body DECLARES it.
#
# RED against the pre-change gate. AC-G4 verifies that through the $GATE seam,
# keyed on the named FAIL lines rather than on the suite's exit status — a suite
# exiting 1 for an unrelated reason would otherwise read as a successful RED.
# ===========================================================================

# --- Seam default -----------------------------------------------------------
# Asserted because the seam is itself a fail-open if it is not: a stray
# NET_ISSUE_FLOW_GATE in the environment would silently redirect every case
# above, and the suite would report on a file nobody chose.
cases=$((cases + 1))
if [[ "$GATE_DEFAULT" == "$REPO_ROOT/plugins/soleur/skills/ship/scripts/net-issue-flow.sh" ]]; then
  pass "GATE default resolves to the shipped gate path"
else
  fail "GATE default resolved to '$GATE_DEFAULT'"
fi

# --- R1: the motivating case ------------------------------------------------
# The issue cites the ORIGINATING ISSUE (#7652), never the PR (999). Before this
# change the gate saw Filing: 0 and PASSED. The PR body declares it.
PR_BODY_FILE="$WORK/body-r1"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r1"; export ISSUE_LIST_FILE
{
  printf 'Some PR that closes nothing and files one.\n'
  printf '\n'
  printf 'Filed: #7708\n'
} > "$PR_BODY_FILE"
printf '%s\n' '[{"number":7708,"body":"Follow-up from #7652 work. Cites the ISSUE, not the PR.","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"}]' > "$ISSUE_LIST_FILE"
run_gate
cases=$((cases + 1))
if grep -qE 'Filing:[[:space:]]*1' "$WORK/out"; then
  pass "R1 declared filing that cites the ISSUE is counted (Filing: 1)"
else
  fail "R1 expected 'Filing: 1'; got: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]]; then pass "R1 net-positive after attribution BLOCKS (exit 1)"
else fail "R1 expected exit 1, got $CASE_RC"; fi

# --- R2: a body-attributed issue is still eligible for the ADR-155 exemption -
# Measured 2026-09-07 (#7896 review), classifying on `.pull_request` because
# issues and PRs share one number space here: 21 of 66 cited numbers are PRs
# and 20 of the 33 whole-line Mandated-By: issues cite at least one. An
# earlier revision of this comment said 0 of 33 -- that used range
# membership, which cannot discriminate. The exemption was under-reached
# rather than inert, so before this
# change none was ever a FILED candidate and the exemption could not fire.
PR_BODY_FILE="$WORK/body-r2"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r2"; export ISSUE_LIST_FILE
{
  printf 'Some PR that closes nothing and files one mandated tracker.\n'
  printf '\n'
  printf 'Filed: #7709\n'
  printf 'Tracks #7709\n'
} > "$PR_BODY_FILE"
printf '%s\n' '[{"number":7709,"body":"Operator step deferred.\nMandated-By: wg-block-pr-ready-on-undeferred-operator-steps\n","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"}]' > "$ISSUE_LIST_FILE"
run_gate
cases=$((cases + 1))
if grep -qE 'Filing:[[:space:]]*1' "$WORK/out"; then
  pass "R2 body-attributed issue keeps its TRUE Filing: count"
else
  fail "R2 expected 'Filing: 1'; got: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
if grep -qiE 'Exempt:[[:space:]]*1' "$WORK/out"; then
  pass "R2 body-attributed issue reaches the ADR-155 exemption (Exempt: 1)"
else
  fail "R2 expected 'Exempt: 1'; got: $(tr '\n' '|' < "$WORK/out")"
fi

# --- R3: the conservation report, and that it is REPORT-ONLY ----------------
# A prose-only mention must be NAMED but must move neither Filing: nor Net:.
PR_BODY_FILE="$WORK/body-r3"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r3"; export ISSUE_LIST_FILE
{
  printf 'Closes #7652\n'
  printf '\n'
  printf 'Filed: #7710\n'
  printf '\n'
  printf 'Incidentally this also relates to #7711 in passing.\n'
} > "$PR_BODY_FILE"
printf '%s\n' '[{"number":7710,"body":"Declared filing citing #7652.","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"},{"number":7711,"body":"Mentioned in prose only; cites #7652.","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"}]' > "$ISSUE_LIST_FILE"
run_gate
cases=$((cases + 1))
if grep -qE 'Filing:[[:space:]]*1' "$WORK/out"; then
  pass "R3 prose-only mention is NOT counted (Filing: 1, not 2)"
else
  fail "R3 expected 'Filing: 1'; got: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
# The prose mention must NOT be reported either. The line it used to appear on
# was computed from the PR body alone -- it never joined the issue array, so it
# had no recency filter, no existence check, and no exclusion of rows the gate
# had ALREADY COUNTED. Measured live on merged PR #7702: five numbers printed as
# "possible unattributed filings", FOUR of them simultaneously in `Filing: 4`,
# plus a prose cross-reference to an unrelated merged PR. The parenthetical
# "not counted" was false for most of the line, and the drift metric built on it
# sat at ceiling. What replaces it is asserted in R8/R9 below.
if ! grep -qiE 'possible unattributed filing' "$WORK/out"; then
  pass "R3 a prose mention is NOT accused on a residual line"
else
  fail "R3 the removed unattributed line is back: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
# `%+d`, so a zero prints as `+0` — an unsigned `0` here would never match and
# the case would red against a correct gate.
if grep -qE 'Net:[[:space:]]*\+0' "$WORK/out"; then
  pass "R3 the reported-only number does not move NET"
else
  fail "R3 expected 'Net: +0'; got: $(tr '\n' '|' < "$WORK/out")"
fi

# --- R4 (M2): TWO declared filings, so a first-member-only check cannot pass --
# A derivation that stops at the first member is an instance of the very class
# this gate exists to catch. With one declared filing per fixture, truncating
# the set to `.[0:1]` is INVISIBLE — measured: M2 survived the whole battery.
PR_BODY_FILE="$WORK/body-r4"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r4"; export ISSUE_LIST_FILE
{
  printf 'Files two, closes nothing.\n'
  printf '\n'
  printf 'Filed: #7720 #7721\n'
} > "$PR_BODY_FILE"
printf '%s\n' '[{"number":7720,"body":"cites #7652 only","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"},{"number":7721,"body":"cites #7652 only","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"}]' > "$ISSUE_LIST_FILE"
run_gate
cases=$((cases + 1))
if grep -qE 'Filing:[[:space:]]*2' "$WORK/out"; then
  pass "R4 BOTH declared filings are counted (a first-member-only check cannot pass)"
else
  fail "R4 expected 'Filing: 2'; got: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
if grep -qE 'Attributed:.*#7720.*#7721' "$WORK/out"; then
  pass "R4 both numbers appear on the Attributed: line"
else
  fail "R4 expected both #7720 and #7721 on Attributed:; got: $(tr '\n' '|' < "$WORK/out")"
fi

# --- R7: an EMPTY residual must print NO line, not a malformed one ------------
# Regression for the @tsv empty-field collapse. Tab is IFS-whitespace, so an
# empty numbers field shifted every later field left and the gate printed a
# literal `Possible unattributed filings: #-`. Found by dogfooding, not by any
# fixture — every other case here has a non-empty residual.
PR_BODY_FILE="$WORK/body-r7"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r7"; export ISSUE_LIST_FILE
printf 'A PR body that mentions no issue numbers at all.\n' > "$PR_BODY_FILE"
printf '%s\n' '[]' > "$ISSUE_LIST_FILE"
run_gate
cases=$((cases + 1))
if ! grep -qE 'Undelivered declarations|Contradictory:' "$WORK/out"; then
  pass "R7 empty residual prints NO undelivered/contradictory line"
else
  fail "R7 printed a residual line for an empty residual: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
if ! grep -qE '#-' "$WORK/out"; then
  pass "R7 never prints a malformed '#-' number"
else
  fail "R7 emitted a malformed '#-': $(tr '\n' '|' < "$WORK/out")"
fi

# --- R5 (M8): a filed-then-CLOSED issue is STILL a filing ---------------------
# THE ESCAPE ROW. Conjoining `state == "OPEN"` onto the declared disjunct
# satisfies every other row in the matrix while violating the property — which
# is precisely why `--state all` is a pinned query property. Every other fixture
# here is OPEN, so without this case the conjunction is invisible.
PR_BODY_FILE="$WORK/body-r5"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r5"; export ISSUE_LIST_FILE
{
  printf 'Files one, which has since been closed.\n'
  printf '\n'
  printf 'Filed: #7730\n'
} > "$PR_BODY_FILE"
printf '%s\n' '[{"number":7730,"body":"cites #7652 only","createdAt":"2026-07-20T12:00:00Z","state":"CLOSED"}]' > "$ISSUE_LIST_FILE"
run_gate
cases=$((cases + 1))
if grep -qE 'Filing:[[:space:]]*1' "$WORK/out"; then
  pass "R5 a filed-then-CLOSED issue is still counted (--state all is load-bearing)"
else
  fail "R5 expected 'Filing: 1' for a CLOSED filing; got: $(tr '\n' '|' < "$WORK/out")"
fi

# --- R6 (M7): the body-attribution emit uses its OWN rule id ------------------
# POSITIVE ledger assertion by exact .rule_id. An absence-only check is green
# under the mutation that reuses the shared `net-issue-flow` id, because the
# emit is already conditional — measured: M7 survived. Mirrors the existing
# attr/attr_neg pair for the exemption id.
rm -f "$INC"
PR_BODY_FILE="$WORK/body-r1"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues-r1"; export ISSUE_LIST_FILE
run_gate
body_attr=0
if [[ -r "$INC" ]]; then
  body_attr="$(jq -sr '[.[] | select(.rule_id == "net-issue-flow-body-attributed")] | length' < "$INC" 2>/dev/null || echo 0)"
fi
cases=$((cases + 1))
if [[ "$body_attr" -ge 1 ]]; then
  pass "declared-arm firing emits its OWN rule_id (net-issue-flow-body-attributed)"
else
  fail "expected >=1 net-issue-flow-body-attributed row; got $body_attr"
fi

# Negative twin: a run where the declared arm did NOT fire must emit none, or
# the assertion above passes on every invocation and proves nothing.
rm -f "$INC"
PR_BODY_FILE="$WORK/body1"; export PR_BODY_FILE
ISSUE_LIST_FILE="$WORK/issues3"; export ISSUE_LIST_FILE
run_gate
body_attr_neg=0
if [[ -r "$INC" ]]; then
  body_attr_neg="$(jq -sr '[.[] | select(.rule_id == "net-issue-flow-body-attributed")] | length' < "$INC" 2>/dev/null || echo 0)"
fi
cases=$((cases + 1))
if [[ "$body_attr_neg" -eq 0 ]]; then
  pass "no body-attributed row when every filing cites the PR directly"
else
  fail "expected 0 net-issue-flow-body-attributed rows on the cites-PR path; got $body_attr_neg"
fi

printf '\n'

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# R8-R14: the #7896 review round. Every case here is a shape that was measured
# WRONG against the shipped gate before the fix, so each one can be driven RED by
# reverting its own fix -- none is a restatement of a case above.
#
# Fixture DIRECTION is deliberate: R10 and R11 sit on the "the matcher is too
# AGGRESSIVE" side, which the original R1-R7 set had no member of at all. A suite
# whose fixtures all assert must-match cannot see a widening.
# ---------------------------------------------------------------------------
_r() { # $1=body  $2=issues
  PR_BODY_FILE="$WORK/r89"; export PR_BODY_FILE
  ISSUE_LIST_FILE="$WORK/r89i"; export ISSUE_LIST_FILE
  printf '%b' "$1" > "$PR_BODY_FILE"; printf '%s\n' "$2" > "$ISSUE_LIST_FILE"
  run_gate
}
_PLAIN='[{"number":7001,"body":"Follow-up filed during this work; cites no PR.","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"}]'
_MAND='[{"number":7001,"body":"Operator step deferred.\nMandated-By: wg-block-pr-ready-on-undeferred-operator-steps\n","createdAt":"2026-07-20T12:00:00Z","state":"OPEN"}]'

# R8 -- an unbalanced fence must ABORT, not silently delete the declared arm.
# Before: one unclosed ``` yielded `Filing: 0 / Net: +0 / PASS` with no residual
# line and no telemetry, because sf returns "" and $declared is the only arm that
# can see a filing citing the originating issue.
_r 'Work.\n\n```bash\ncode\n\nFiled: #7001\n' "$_PLAIN"
cases=$((cases + 1))
if [[ "$CASE_RC" -eq 1 ]] && grep -qE 'unbalanced code fence' "$WORK/out"; then
  pass "R8 an unbalanced PR-body fence aborts instead of emptying the declared arm"
else
  fail "R8 expected an unbalanced-fence abort; rc=$CASE_RC out=$(tr '\n' '|' < "$WORK/out")"
fi

# R9 -- Filed: + Closes on the SAME number must not cancel to a credit.
# Before: `Closing: 1 / Filing: 0 / Net: -1 / PASS` -- one line bought two units.
_r 'Work.\n\nFiled: #7001\nCloses #7001\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Filing:[[:space:]]+1\b' "$WORK/out" && grep -qE '^  Net:[[:space:]]+\+0\b' "$WORK/out"; then
  pass "R9 a number on both Filed: and Closes stays in BOTH terms (Net +0, not -1)"
else
  fail "R9 expected Filing: 1 / Net: +0; got: $(tr '\n' '|' < "$WORK/out")"
fi
cases=$((cases + 1))
if grep -qE '^  Contradictory:.*#7001' "$WORK/out"; then
  pass "R9 the contradiction is surfaced, not silently netted"
else
  fail "R9 expected a Contradictory: line; got: $(tr '\n' '|' < "$WORK/out")"
fi

# R10 (DIRECTION: too aggressive) -- a prose `Refs:` line must NOT declare.
# Measured on a real line on main: `Refs: #6588, #6897, #6604, #6570. Prior
# decision: #6918` admitted FIVE issues as this PR filings under the old
# `(Filed|Tracks|Refs):?` alternation, including the one labelled Prior decision.
_r 'Work.\n\nRefs: #7001 (prior decision), #7002\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Filing:[[:space:]]+0\b' "$WORK/out"; then
  pass "R10 a prose Refs: line declares nothing (P4: no sibling over-attribution)"
else
  fail "R10 a Refs: line still declares; got: $(tr '\n' '|' < "$WORK/out")"
fi

# R11 (DIRECTION: too aggressive) -- the keyword must be line-initial, so an
# ordinary sentence containing it cannot declare.
_r 'Work.\n\nWe filed: #7001 during an unrelated sweep last week.\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Filing:[[:space:]]+0\b' "$WORK/out"; then
  pass "R11 mid-sentence 'filed:' declares nothing"
else
  fail "R11 mid-sentence prose declared; got: $(tr '\n' '|' < "$WORK/out")"
fi

# R12 -- the producer shapes an author actually writes. Before: all three were
# silently advisory while ship/SKILL.md carry-forward grep reported them present.
for _shape in '- Filed: #7001' '**Filed:** #7001' 'FILED: #7001'; do
  _r "Work.\n\n${_shape}\n" "$_PLAIN"
  cases=$((cases + 1))
  if grep -qE '^  Filing:[[:space:]]+1\b' "$WORK/out"; then
    pass "R12 producer shape counts: ${_shape}"
  else
    fail "R12 producer shape dropped: ${_shape}; got: $(tr '\n' '|' < "$WORK/out")"
  fi
done

# R13 -- `Filed: #N` must reach the ADR-155 exemption. Before this was the ONE
# shape that admitted a mandated filing to FILED and then denied it the
# exemption, rejecting with "PR body has no Tracks/Refs #N companion" over a body
# that declared #N verbatim -- and the printed remediation looped.
_r 'Work.\n\nFiled: #7001\n' "$_MAND"
cases=$((cases + 1))
if grep -qE '^  Exempt:[[:space:]]+1\b' "$WORK/out" && [[ "$CASE_RC" -eq 0 ]]; then
  pass "R13 a mandated filing declared ONLY on the Filed: line is exempt"
else
  fail "R13 expected Exempt: 1 / exit 0; rc=$CASE_RC out=$(tr '\n' '|' < "$WORK/out")"
fi

# R14 -- a declaration the gate cannot honour must be NAMED. Before, a declared
# number with no matching row was dropped from FILED and suppressed from the
# residual too, so it appeared nowhere: the silent case the arm exists to end.
_r 'Work.\n\nFiled: #4242\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Undelivered declarations:.*#4242' "$WORK/out"; then
  pass "R14 a declaration with no matching issue is reported, not silently dropped"
else
  fail "R14 expected an Undelivered declarations line; got: $(tr '\n' '|' < "$WORK/out")"
fi

# R15 -- CLOSING is the cheapest way to neutralise a count, so its keyword match
# must not fire inside a longer word and must not credit a self-reference. Both
# were pre-existing fail-opens that got materially cheaper the moment the
# declared arm made FILED actually count on the shapes that matter.
_r 'Work.\n\nFiled: #7001\nThis is unclosed #4242.\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Closing:[[:space:]]+0\b' "$WORK/out"; then
  pass "R15 unclosed #N is not a close keyword"
else
  fail "R15 unclosed credited a close; got: $(tr '\n' '|' < "$WORK/out")"
fi
_r 'Work.\n\nFiled: #7001\nCloses #999\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Closing:[[:space:]]+0\b' "$WORK/out"; then
  pass "R15 a close naming the PR own number is not a credit"
else
  fail "R15 a self-referential close was credited; got: $(tr '\n' '|' < "$WORK/out")"
fi
# Direction control: a REAL close keyword must still count, or the two negatives
# above are satisfied by a match that broke entirely.
_r 'Work.\n\nCloses #7001\n' "$_PLAIN"
cases=$((cases + 1))
if grep -qE '^  Closing:[[:space:]]+1\b' "$WORK/out"; then
  pass "R15 control: a real close keyword still counts"
else
  fail "R15 the close match broke entirely; got: $(tr '\n' '|' < "$WORK/out")"
fi


# ACCOUNTING CONSERVATION. Deliberately placed BEFORE the floor: this is the arm
# that catches a NEUTERED verdict helper, and the floor cannot. `cases` keeps its
# full value when fail() is a no-op, so the floor stays green while the verdicts
# it was floored on have silently evaporated. Every counted case records exactly
# one verdict, so passes+fails MUST equal cases.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never through fail(): fail()
# increments the counter the exit status reads, so a check enforced through the
# suspect cannot witness the suspect.
# ---------------------------------------------------------------------------
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' \
    "$((passes + fails))" "$cases" >&2
  if [[ $((passes + fails)) -lt "$cases" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  printf 'net-issue-flow.test.sh: %d FAILED (%d passed, %d cases)\n' "$fails" "$passes" "$cases"
  exit 1
fi

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR. Set AT the running count, never below it: a floor with
# slack silently absorbs a deleted case, which is the one thing it exists to
# stop. `-lt` (a floor, not equality) so the suite can grow without churn --
# lower it only deliberately.
#
# Motivating vacuity: before this run the suite had no pass COUNTER at all, so
# deleting a case changed nothing observable. Baseline before the exemption
# work was 23.
#
# It reads `cases`, NOT `passes`. `passes` deflates whenever a verdict is
# discarded, so a floor on it fires with "too few assertions" on a run whose real
# fault is a neutered fail() -- naming the wrong fault. `cases` moves only with
# the call sites, which is exactly what a floor is about.
#
# Reported directly (`printf >&2` + `exit 1`) for the same reason as the
# conservation check above: routing it through fail() puts the floor inside the
# thing it is meant to police.
# ---------------------------------------------------------------------------
MIN_ASSERTIONS=117
if [[ "$cases" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_ASSERTIONS" >&2
  printf 'net-issue-flow.test.sh: %d FAILED (%d passed, %d cases)\n' "$fails" "$passes" "$cases"
  exit 1
fi

if [[ "$fails" -eq 0 ]]; then
  printf 'net-issue-flow.test.sh: ALL PASS (%d assertions)\n' "$cases"
  exit 0
fi
printf 'net-issue-flow.test.sh: %d FAILED (%d passed)\n' "$fails" "$passes"
exit 1
