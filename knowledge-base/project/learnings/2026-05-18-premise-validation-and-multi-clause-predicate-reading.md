---
date: 2026-05-18
session: feat-one-shot-3981-byok-killswitch-atomicity (PR #3987)
tags: [workflow, premise-validation, deepen-plan, sql-predicate, brainstorm, multi-clause-and]
related:
  - "[[2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record]]"
  - "[[2026-05-12-plan-precondition-and-3-value-enum-gate-drift]]"
---

# Premise validation at routing time AND multi-clause SQL predicate reading at deepen time

Two distinct misses landed in the same session, both classified as
**premise-not-verified**. One at routing layer (issue body claimed a workflow
"doesn't yet exist" when it had shipped 2 days earlier), one at deepen-plan
layer (verified one operand of a multi-clause SQL predicate, missed the
other). Captured together because they share the same prevention shape:
*name the assertion concretely, run a 5-second probe, accept the falsification.*

## Pattern 1 — Issue-body "blocked by" / "deferred from" / "does not exist yet" claims need probing BEFORE worktree creation

Issue body at filing time captures a snapshot. Days or weeks later, the named
blocker can ship without the issue body being updated. The cost of
proceeding on a stale premise depends on where the brainstorm catches it:

- **Phase 1.0.5 (Premise Validation)**: cheap — worktree exists but no
  agents spawned; can revert and re-route in <5 min.
- **Phase 0.5 (Domain Leader Assessment)**: medium — multi-leader agent
  spawn already paid; need to re-prompt all leaders.
- **Phase 2 (Approach exploration)**: expensive — most of the brainstorm
  is wasted; revert + re-frame requires user dialogue.

**Mitigation (route added):** brainstorm SKILL.md Phase 1.0.5 already lists
issue-body claim verification, but the prescription kicks in *after* the
worktree is created (Phase 0 branch safety check creates the worktree
unconditionally on main). For issue-body claims of the form "does not yet
exist" / "blocked by #N" / "deferred from #M", probe BEFORE Phase 0 worktree
creation — a single `ls`/`gh`/`grep` against the named artifact resolves the
premise in seconds. **Cost saved this session:** the brainstorm correctly
caught the stale premise at Phase 1.0.5, but had already created a worktree
+ draft PR #3982 (which had to be cleaned up). With a pre-worktree probe,
the entire brainstorm could have been skipped in favor of one-shot from the
first turn.

### Concrete check pattern

When the user's input references issue `#N` AND the body of `#N` contains
literal text matching `(does not yet exist|deferred from|blocked by) #?(\d+)`,
probe each cited blocker:

```bash
gh issue view <blocker_N> --json state,closedByPullRequestsReferences
# OR if the blocker is described as an artifact path:
ls <named-artifact-path> 2>&1 | head -3
```

If `state == "CLOSED"` and the artifact exists, the premise is stale. Re-frame
with the user BEFORE Phase 0 worktree creation. This is the routing-layer
equivalent of `wg-before-asserting-github-issue-status`.

## Pattern 2 — Deepen-plan verification of multi-clause SQL predicates must restate ALL operands

Migration `046_runtime_cost_state.sql:227`:

```sql
IF v_paused_at IS NULL AND v_total > v_cap THEN
  UPDATE public.users SET runtime_paused_at = now() WHERE ...;
  v_tripped := true;
END IF;
```

**Two clauses, both load-bearing.** Once the first cap-crossing call stamps
`runtime_paused_at`, every subsequent FOR-UPDATE-serialized call observes
the non-null timestamp on its own row-lock acquisition and returns
`kill_tripped=false`.

Deepen-plan's verification at line 168 in the original plan body extracted
the SECOND clause (`v_total > v_cap`) and used it as the basis for "calls
1-5 return kill_tripped=false, calls 6-10 return kill_tripped=true." That
classification is correct for a hypothetical predicate of `IF v_total >
v_cap`, but wrong for the ACTUAL predicate. The first clause was implicit
in deepen's reading but never restated in the plan body, so the derivative
"calls 6-10 return true" misclassification went undetected through
plan-review, work setup, and into the test code.

The live-DB run at /work time was the gate that surfaced it (`at
cumulative=700: expected true got false`). Costly path — recoverable, but
required a plan amendment, test edit, and live re-run.

### Concrete check pattern

When a plan section verifies a SQL predicate by citing line numbers
(`migration N:line P uses X`), the verification body MUST literally restate
EVERY operand of the predicate. A predicate of the shape `IF A AND B THEN
... v_flag := true; END IF` requires:

- Restating A: `<condition>` + meaning + when it's NULL/false/true.
- Restating B: `<condition>` + meaning.
- Restating the conjunction: `v_flag` is true iff (A AND B), not (A) OR
  (B) alone.

Same rule for `AND ... AND ...` (n-ary), `OR`, `CASE WHEN`, and any boolean
predicate with ≥2 operands. The cost is 3-5 extra plan lines; the saving
is one live-DB test failure → plan amendment cycle. For per-row-locking
RPCs like this kill-switch, the second-clause-as-once-flag pattern is
*the* atomicity invariant the test is supposed to pin — getting it wrong
in the plan means the test was written to prove a *weaker* property than
the SUT actually provides.

This is the SQL-predicate analog of the existing learning
`2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`, which
prescribes literal enumeration of TypeScript union members. Same rule:
when a gate has N members or operands, restate all N.

## Session Errors

1. **`/soleur:go #3981` mis-classified as a PR review** — `/soleur:review`
   was invoked, `gh pr view 3981` returned "Could not resolve to a
   PullRequest." The user interrupted and clarified "#3869 item 6 and
   #3981" — both are ISSUES. **Recovery:** re-routed via brainstorm. **Prevention:** when the
   review-target detection in `/soleur:review` gets "Could not resolve to a
   PullRequest" from `gh pr view`, fall through to `gh issue view <N>`
   instead of failing. If issue exists, present the operator with: "PR #N
   not found, but issue #N exists — was the intent to brainstorm/one-shot
   the issue?" This catches the common confusion where `#N` references an
   issue but the user typed `/soleur:go #N` expecting auto-routing.

2. **Brainstorm proceeded on stale "does not exist" premise** — `#3869`
   item 6 and `#3981` body both claim the CI workflow "doesn't yet exist."
   It shipped via PR #3893 on 2026-05-16. Worktree + draft PR #3982 were
   created before the premise was checked. **Recovery:** closed PR
   #3982, deleted worktree, updated #3981 body, routed to one-shot.
   **Prevention:** add pre-worktree probe to brainstorm Phase 0 (BEFORE
   worktree creation) — if the user-input issue body contains "(does not
   yet exist|deferred from|blocked by) #?\d+", `gh issue view` each cited
   blocker and `ls` each cited artifact path. If any premise falsifies,
   re-frame with the user before paying worktree-creation cost.

3. **Deepen-plan verification missed first clause of `IF v_paused_at IS
   NULL AND v_total > v_cap`** — extracted the `> v_cap` clause but not
   the `v_paused_at IS NULL` co-condition. Plan documented "calls 6-10
   return kill_tripped=true" (wrong); actual is "exactly 1 call wins the
   flip." **Recovery:** live-DB run at /work time surfaced the gap; plan
   + test both corrected to pin the stronger atomicity invariant.
   **Prevention:** deepen-plan SKILL.md gains a sub-rule: "When verifying
   a multi-clause SQL predicate (`IF A AND B`, `CASE WHEN A AND B`, `OR
   ... AND ...`), the plan body MUST literally restate EVERY operand
   alongside the line citation. A predicate paraphrase that names only
   the most-discussed clause is a Phase 4.6 plan halt."

4. **Bash CWD drift across calls** — `git status` from worktree returned
   "fatal: this operation must be run in a work tree" because the persistent
   bash CWD had drifted back to the bare-repo root. **Recovery:** chained
   `cd <abs-path> && <cmd>` in single Bash calls. **Prevention:** rule
   already documented in `work/SKILL.md` Phase 2 step 5; just required
   adherence.

## Tags

category: workflow
module: brainstorm,deepen-plan,go-routing
