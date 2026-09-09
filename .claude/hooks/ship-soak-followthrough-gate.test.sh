#!/usr/bin/env bash
# Sibling suite for ship-soak-followthrough-gate.sh.
#
# Written for #7164: this hook was one of two in-scope hooks with NO sibling
# suite, so nothing asserted its characteristic behaviour and a break in its
# wiring would have been silent.
#
# COVERAGE IS PARTIAL AND SAID SO OUT LOUD. The deny path needs a real PR body
# carrying a soak signal plus a resolvable open tracker, which means a
# multi-response `gh` stub. What is covered here:
#   - the trigger predicate (which commands the gate intercepts at all)
#   - every documented FAIL-OPEN branch, driven through a `gh` stub
#   - the #7164 envelope contract
# The deny path itself remains covered by ship/SKILL.md's gate and the agent, as
# the hook header already states. Degrading that to "fail-open, as expected"
# silently would be the failure mode this file exists to avoid.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-soak-followthrough-gate.sh"

PASS=0; FAIL=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

# ADR-129 rule (c): ONE owning trap for every tempfile this suite allocates.
# Per-case sandboxes are children of this root, so a case that dies mid-assertion
# cannot leak — /tmp is a machine-global tmpfs shared with sibling worktrees.
HIC_TMPROOT="$(mktemp -d -t ssfgroot.XXXXXXXX)"
trap 'rm -rf "$HIC_TMPROOT"' EXIT

# A git fixture with an explicit branch: CI-on-main masks branch-dependent
# sibling gates (#5192), so the branch is set rather than inherited.
mk_repo() {
  local d; d="$(mktemp -d -p "$HIC_TMPROOT")"
  : "${d:?fixture dir is empty; git -C <empty> would retarget this write}"
  git -C "$d" init -q -b feat-fixture
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$d"
}

# A `gh` stub keeps the gate off the network. Default: report no PR, which is
# the hook's documented "cannot read PR body" fail-open branch.
mk_gh_stub() {
  local d="$1" mode="${2:-nopr}"
  mkdir -p "$d/stub"
  # The stub VALIDATES argv rather than answering unconditionally. A fake that
  # dispatches on nothing puts the fixture seam ABOVE the code under test: it
  # cannot detect the gate querying the WRONG thing, so a change from `gh pr
  # view` to some other subcommand would keep the suite green. `exit 64` on an
  # unrecognised invocation makes a wrong query a loud failure.
  # (.claude/hooks/stub-argv-fidelity.test.sh enforces this class repo-wide.)
  cat > "$d/stub/gh" <<'STUB'
#!/usr/bin/env bash
ARGS="$*"
case "$1" in
  pr|issue) ;;
  *) echo "gh-stub: unexpected subcommand: $ARGS" >&2; exit 64 ;;
esac
case "$ARGS" in
  *view*) ;;
  *) echo "gh-stub: expected a 'view' read, got: $ARGS" >&2; exit 64 ;;
esac

# `issue view` answers describe an OPEN, entirely UNENROLLED tracker — the state
# that makes the gate deny. Any ref reaching this branch therefore denies, which
# is what lets the closing-target cases below prove the fix by their verdict
# alone: if the filter stopped working, the ref would arrive here and flip the
# expected allow into a deny.
if [[ "$1" == "issue" ]]; then
  # Emit the --jq-PROJECTED scalar, not the raw JSON envelope: the gate reads
  # these through `--jq .state` / `--jq '[.labels[].name]|join(",")'`, so a stub
  # answering `{"state":"OPEN"}` yields a $state that never equals OPEN and the
  # tracker is skipped as closed — turning the deny-path control green-by-accident.
  case "$ARGS" in
    *--json\ state*)  printf '%s\n' 'OPEN' ;;
    *--json\ labels*) printf '%s\n' '' ;;
    *--json\ body*)   printf '%s\n' '' ;;
    *) echo "gh-stub: unexpected issue read: $ARGS" >&2; exit 64 ;;
  esac
  exit 0
fi

# `pr view` is read as `--json body --jq .body`, so the stub must emit the
# PROJECTED body, exactly as the issue branch above does. Emitting the `{"body":...}`
# envelope instead put the JSON wrapper into the corpus and collapsed the body onto
# ONE line, which silently changed what any line-scoped analysis could see.
case "${MODE:-nopr}" in
  nopr)   exit 1 ;;                                            # no PR readable
  nosoak) printf '%s\n' 'ordinary PR body with no soak signal' ;;
  # Soak signal + the SAME issue named as both the closing target and a `Ref`.
  # This is PR #7426's shape: the plan discussed `Ref #7409` inside a rejected
  # counterfactual while the PR closes #7409.
  # NOTE: this body previously read "Post-deploy soak: none." — a NEGATED soak.
  # Once the gate learned to drop negations that case would have passed because
  # there was NO SIGNAL AT ALL, making this #7426 closing-target regression test
  # vacuous. It carries a real soak declaration so the CLOSES filter stays under test.
  soakcloses) printf '%s\n' 'Closes #7409

Post-deploy soak holds at 0 for 7 days. Ref #7409 would apply only under the split we rejected.' ;;
  # Control: a genuine third-party tracker alongside the closing target. The
  # closing target drops out; #9999 must NOT, or the fix has disabled the gate
  # rather than narrowed it.
  soakother) printf '%s\n' 'Closes #7409

Post-deploy soak holds. Ref #9999 tracks the soak.' ;;
  # Only NEGATED soak vocabulary -- a plan declaring that NO soak exists -- beside a
  # genuine third-party ref. The gate must NOT fire: there is no soak to enrol.
  # PR #7987's real shape: the refs sit on their OWN lines (a `Ref #N` line carries
  # no soak vocabulary), and the only soak match in the whole corpus is the plan
  # template row that says the section does not apply.
  soaknegated) printf '%s\n' 'Closes #7409

Ref #9999

| 2.9.1 Soak follow-through | **Skip.** No acceptance criterion is time-gated; nothing here closes on a soak. |
No soak-gated status flip.' ;;
  # ACCEPTED RESIDUAL, pinned so it is a decision rather than a surprise: a negation
  # that shares ONE LINE with a tracker reference is KEPT and therefore DENIES. That
  # is the safe direction (the gate asks for enrollment on a ref the author put
  # there) and it is the price of using the tracker as the discriminator instead of
  # a punctuation window -- which was a live bypass on five house-style spellings.
  # THE BYPASS SHAPE. Soleur house style for a soak-gated closure is
  # `Ref #N` / NOT `Closes`, and the clause-boundary window that preceded the
  # tracker discriminator DROPPED this line -- a live merge-gate bypass. Verbatim
  # from knowledge-base/project/plans/2026-06-30-fix-agent-readiness-*.md.
  soakhousestyle) printf '%s\n' 'Closes #7409

- PR body: `Ref #9999`, never `Closes` (closure gated on the 7-day soak).' ;;
  soaknegsameline) printf '%s\n' 'Closes #7409

No soak-gated status flip. Ref #9999 tracks the residue.' ;;
  # The negation must be SCOPED: here `NOT` negates `Closes`, not the soak, and the
  # sentence IS a real soak declaration. Must still DENY.
  # Body cites a plan on disk; the soak declaration and the refs live in the PLAN.
  soakplan) printf '%s\n' 'Closes #7409

See knowledge-base/project/plans/fixture-soak-plan.md for the detail.' ;;
  # FAR SIDE. Every fixture above asserts the strip removes ENOUGH; these assert it
  # does not remove TOO MUCH. Without them, widening the negation window
  # ({0,60}->{0,600}), loosening the second rule ('not applicable'->'not'), or
  # making either fence strip greedier all left the suite byte-identical green
  # while silently disabling the gate on a real declaration.
  soakwindow) printf '%s\n' 'Closes #7409

No acceptance criterion is time-gated here and the release plan is otherwise unremarkable, but the post-deploy soak holds at 0 for 7 days. Ref #9999 tracks it.' ;;
  soakafter) printf '%s\n' 'Closes #7409

The post-deploy soak is not yet enrolled. Ref #9999 tracks it.' ;;
  # An UNBALANCED fence in the PR body. The body strip is fail-closed
  # (END{if(in_fence) exit 2} -> write the body unstripped), so the live Ref past
  # the unclosed fence must still be seen. Deleting that END clause flipped this
  # to allow while the suite stayed green.
  soakbodyfence) printf '%s\n' 'Closes #7409

Post-deploy soak holds at 0 for 7 days.

```
unclosed fence
Ref #9999 tracks the soak.' ;;
  soaknegscoped) printf '%s\n' 'Closes #7409

- [ ] AC9: PR body uses **`Ref #9999`** (NOT `Closes`) -- closure is gated on the post-deploy soak below.' ;;
  *)      echo "gh-stub: unknown MODE=${MODE:-}" >&2; exit 64 ;;
esac
STUB
  chmod +x "$d/stub/gh"
  echo "$d/stub"
}

decision_of() { # <command-string> <repo> <gh-mode>
  local cmd="$1" repo="$2" mode="${3:-nopr}" stub out
  stub="$(mk_gh_stub "$repo" "$mode")"
  out="$(cd "$repo" && jq -nc --arg c "$cmd" --arg d "$repo" \
          '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' \
        | PATH="$stub:$PATH" MODE="$mode" INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" 2>/dev/null)"
  [[ -z "${out//[[:space:]]/}" ]] && { echo "<none>"; return; }
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}
check() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "PASS: $label → $got"
  else FAIL=$((FAIL+1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"; fi
}

REPO="$(mk_repo)"

# --- trigger predicate: what the gate intercepts at all ---------------------
check "unrelated command allows"           "<none>" "$(decision_of 'ls -la' "$REPO")"
check "git commit allows (not a merge)"    "<none>" "$(decision_of 'git commit -m x' "$REPO")"
check "gh pr merge WITHOUT --auto allows"  "<none>" "$(decision_of 'gh pr merge 1 --squash' "$REPO")"

# --- documented fail-open branches -----------------------------------------
check "gh pr ready, no PR readable → fail-open" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" nopr)"
check "gh pr merge --auto, no PR readable → fail-open" "<none>" \
  "$(decision_of 'gh pr merge 1 --squash --auto' "$REPO" nopr)"
check "PR body carries no soak signal → fail-open" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" nosoak)"

# --- closing target is never an enrollable soak tracker (PR #7426) ----------
# The carve-out is reasoned at issue level but was implemented at mention level,
# so one `Ref #N` re-added the PR's own `Closes` target and restored the #7278
# deadlock. These two cases pin the ISSUE-level reading. They are a matched
# pair on purpose: the first alone would also pass if the filter dropped every
# ref, which would silently disable the gate.
check "closing target named by BOTH Closes and Ref → allows" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" soakcloses)"
check "third-party unenrolled tracker still DENIES (fix narrows, not disables)" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakother)"

# --- negated soak vocabulary is not a soak declaration ----------------------
# The gate matched a bare `soak` anywhere in the corpus, so a plan row saying the
# section does NOT apply fired it: "| 2.9.1 Soak follow-through | **Skip.** No
# acceptance criterion is time-gated; nothing here closes on a soak. |" was the
# ONLY match in the entire corpus of PR #7987, and it demanded enrollment for two
# trackers that close on no timer at all. The hook's CLOSES-extraction comment (anchor: `**Why:** PR #7426`) already recorded the
# cause -- "the regex is negation-blind" (PR #7426) -- while fixing only the
# closing-target half beside it.
#
# These two are a MATCHED PAIR and must stay one: the first alone also passes if
# the drop pass eats everything, which would disable the gate rather than narrow it.
check "negated soak vocabulary only -> allows (negation-blindness, #7426)" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" soaknegated)"
check "ACCEPTED RESIDUAL: a negation sharing a line with a tracker still DENIES (safe direction)" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soaknegsameline)"
check "house-style 'Ref #N, never Closes (closure gated on the soak)' still DENIES" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakhousestyle)"
check "negation scoped to its own clause: 'NOT Closes' still DENIES" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soaknegscoped)"

check "a long negation-free clause before a real soak still DENIES (window length)" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakwindow)"
check "a negation AFTER 'soak' does not silence the declaration" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakafter)"
check "an unbalanced fence in the BODY is fail-closed, so the live Ref is still seen" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakbodyfence)"

# --- the PLAN half gets the same fenced-block strip as the PR body -----------
# The body is stripped so a quoted example cannot read as a live declaration;
# the plan was then appended RAW, so the protection stopped halfway through one
# corpus. Plans are where worked examples and sample PR bodies actually live.
# Matched pair: fenced ref must be invisible, unfenced ref must still deny.
# Byte-exact copy of test-helpers.sh's assert_fixture_dir. Inlined rather than
# sourced, matching the six sibling hook suites that do the same
# (cla-signed-author-gate, context-reviewed-gate, pre-merge-rebase{,-headless,-parity},
# ship-unpushed-commits-gate): `.claude/hooks/` suites do not pull in
# plugins/soleur/test/test-helpers.sh. It is the ONLY guard the P1b scanner
# recognises, and only as an executed statement -- see
# fixture-relative-assert.baseline.txt, "WHAT A GUARD HAS TO PROVE". Keep byte-exact:
# fixture-dir-operand-assert.test.sh drift-checks every copy in the repo.
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

mk_plan() { # <repo> <ref-line-placement: fenced|unfenced>
  local d="$1" where="$2" f
  # Guard the redirect operand at the ENCLOSING FUNCTION HEAD, which is where the
  # P1a guard window starts. Without it `} > "$f"` below is an unprovable operand:
  # an empty $1 makes the path relative and the heredoc lands in the CALLER's
  # working tree. This is the fixture-relative-assert ratchet's own finding on this
  # very edit -- guarded rather than passed through its `--write-baseline` remedy,
  # which would have recorded a real site as accepted.
  : "${1:?mk_plan needs a repo dir; an empty operand would write into the caller cwd}"
  assert_fixture_dir "$1"
  f="$1/knowledge-base/project/plans/fixture-soak-plan.md"
  assert_fixture_dir "$f"
  mkdir -p "$1/knowledge-base/project/plans"
  {
    echo "# fixture plan"
    echo
    echo "Post-deploy soak holds at 0 for 7 days before the tracker closes."
    echo
    if [[ "$where" == fenced ]]; then
      echo '```'
      echo "AC9: PR body uses Ref #9999 (NOT Closes) — quoted illustration only."
      echo '```'
    else
      echo "Ref #9999 tracks the soak."
    fi
  } > "$f"
}

mk_plan "$REPO" fenced
check "ref inside a FENCED block in the plan is not a tracker → allows" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" soakplan)"
mk_plan "$REPO" unfenced
check "same ref UNFENCED in the plan still DENIES (strip narrows, not disables)" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakplan)"
rm -f "$REPO/knowledge-base/project/plans/fixture-soak-plan.md"

# --- #7164 envelope contract ------------------------------------------------
# An ARRAY tool_input.command rendered across lines, matched the trigger regex
# nowhere, and slipped the gate. This hook is not the designated ask responder,
# so it stays silent on stdout — but it must record the fault rather than
# exiting 0 as if it had seen an ordinary non-merge command.
arr="$(jq -nc --arg d "$REPO" '{tool_name:"Bash", tool_input:{command:["gh","pr","ready"]}, cwd:$d}')"
out="$(cd "$REPO" && printf '%s' "$arr" | INCIDENTS_REPO_ROOT="$REPO" bash "$HOOK" 2>/dev/null)"
check "ARRAY command: no decision emitted (non-responder)" "" "${out//[[:space:]]/}"

if [[ -f "$REPO/.claude/.rule-incidents.jsonl" ]] \
   && grep -q 'hook-input-' "$REPO/.claude/.rule-incidents.jsonl" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS: ARRAY command records a hook-input fault (no silent disarm)"
else
  FAIL=$((FAIL+1)); echo "FAIL: ARRAY command disarmed the gate with no record"
fi

rm -rf "$REPO"

# --- instrument self-test + assertion floor ------------------------------------
# Both emit with printf + exit 1 DIRECTLY. Routing either through check() would
# let the single edit that disarms check() disarm its own backstop.
#
# Measured before this existed: `check() { : }` reported "1 passed, 0 failed",
# exit 0 — thirteen of fourteen assertions gone, CI green. And a check() that
# always counts a PASS produced a BYTE-IDENTICAL headline.
_c_pass=$PASS _c_fail=$FAIL
check "instrument self-test: check() records a PASS" "x" "x"
check "instrument self-test: check() records a FAIL (expected, unwound below)" "x" "y"
if [[ "$PASS" -ne $((_c_pass + 1)) || "$FAIL" -ne $((_c_fail + 1)) ]]; then
  printf 'FATAL: check() did not move both counters (pass %s->%s, fail %s->%s)\n' \
    "$_c_pass" "$PASS" "$_c_fail" "$FAIL" >&2
  exit 1
fi
PASS=$_c_pass FAIL=$_c_fail   # unwind the self-test

MIN_ASSERTIONS=19
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: only %s assertions passed, floor is %s — the suite is vacuous\n' \
    "$PASS" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo
echo "=== ship-soak-followthrough-gate: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
