---
title: Post-Implementation Review Value Asymmetry for Verbatim Prose-Plan PRs
date: 2026-05-12
category: engineering
tags: [review, workflow, plan-review, cost-efficiency, skill-prose, multi-agent]
module: soleur
component: review-workflow
problem_type: developer_experience
severity: low
---

# Post-Implementation Review Value Asymmetry for Verbatim Prose-Plan PRs

## Problem

PR #3625 ("Named Orchestration Lanes" feature) implemented a 5-agent-reviewed
plan verbatim into 5 SKILL.md prose edits + 1 bash marker-test file (~70 lines
net additions). Post-implementation `/soleur:review` skill prescription is "code
class" (any `.sh` extension triggers full 8-agent review). Spawning 8 review
agents on this PR shape produced near-zero P1/P2/P3 findings — all returned
CONCUR / Ship / Approve with sub-threshold polish suggestions.

The token cost is poorly matched to the marginal review value:

- **Plan-time review** (5 agents): caught operator P1.2 (awk extraction
  brittleness), DHH cut (9→5 phases), CPO/CTO lane-axis collapse — high value
  per agent.
- **Work-time review** (8 agents prescribed): zero net findings on a verbatim
  implementation of the plan-reviewed design.

## Root Cause

The `/soleur:review` change-class decision tree treats *any* source extension as
"code → 8 agents." But "skill-prose-edit" (the plan frontmatter
`classification:` field) is a real change class that the decision tree does not
recognize:

- Source-of-truth is markdown prose, not executable logic.
- The bash test file is marker-existence assertions over markdown headings
  (no behavior to break, no performance to regress, no data integrity at
  stake).
- All design churn was absorbed at plan time; implementation is mechanical
  prose insertion.

Pre-implementation multi-agent review has already done the work that post-
implementation review would do again.

## Solution (Practitioner Heuristic)

When a PR matches ALL of these:

1. Plan was reviewed by ≥3 agents at plan time (verifiable via plan file or
   `## Domain Review` section), AND
2. Implementation is verbatim plan execution (no scope creep), AND
3. Diff is dominated by markdown/skill-prose with optional bash marker tests,
   AND
4. No production code paths (TypeScript runtime, SQL, route handlers) are
   touched.

…then run a **focused 3-agent slice** at work-time instead of the prescribed
8: `pattern-recognition-specialist` (precedent match), `security-sentinel`
(any shell/awk injection in scaffolding), `code-simplicity-reviewer` (YAGNI +
plan-faithfulness CONCUR). Document the deviation explicitly in the
classification announcement so the workflow choice is reviewable.

**This is judgment, not skill-prescription override.** When in doubt, run the
full 8. The deviation is only justified when conditions 1-4 all hold AND the
operator announces the slice with a one-sentence rationale.

## Key Insight

Multi-agent review is most valuable at the design boundary (plan time) where
agents catch invented APIs, scope creep, axis collisions, and tradeoff
miscalls. Multi-agent review at implementation time is most valuable when
implementation introduces logic, state, or contract surface that the plan
abstracted over. For prose plans implemented as prose, the second pass is
mostly confirmation.

The cost ratio is asymmetric: a 5-agent plan review on a 70-line skill-prose
PR catches design errors that no work-time review could; an 8-agent work-time
review on the same PR catches almost nothing because the design is already
correct.

## Session Errors

1. **Bare-repo path confusion at session start** — `git branch` from the
   bare-repo root failed with "this operation must be run in a work tree."
   Recovery: cd to `.worktrees/feat-orchestration-lanes/`. Prevention: in
   bare-repo projects (`core.bare=true`), the harness or the operator's
   first action MUST cd into the active worktree before any git or file
   operation. The work skill's Pre-Flight Check 1 (FAIL on default branch,
   WARN if not in `.worktrees/`) catches this when work is invoked
   directly — but the initial /work invocation in this session bypassed it
   because the first bash call ran before the skill's Phase 0.5.

2. **Plan-file ls at bare-repo path returned ENOENT** — the plan lives in
   the worktree, not the bare root. Recovery: re-checked from worktree.
   Prevention: knowledge-base artifacts on feature branches live in the
   worktree, period; never `ls <bare-root>/knowledge-base/.../<feat-file>`.

3. **`test-all.sh` tail-truncation produced false "36/37" signal** —
   piping the full output through `tail -40` cut off the final summary
   line, making the run look like a one-suite failure. Re-running with
   stdout captured to a file and `tail -3` showed 37/37 exit 0.
   Prevention: when a test runner's tail looks like partial failure, OR
   the suite count doesn't match expectations, capture stdout to file
   first AND inspect both `tail -3` and `echo "exit=$?"` separately
   before drawing conclusions.

4. **`set -uo pipefail` classification predicates silently returned
   empty** — `grep -E ... || true` swallowed legitimate matches and the
   shell-snapshot's `ZSH_VERSION: unbound variable` noise added confusion.
   Recovery: simpler direct grep one-liner. Prevention: for ad-hoc
   classification predicates, run a one-line `grep -E '...' file | head`
   FIRST to confirm the regex matches anything, then build the
   set-strict pipeline. The `|| true` idiom is correct for the pipeline
   (legit-empty case) but masks regex bugs during predicate development.

## Tags

category: engineering / workflow
module: soleur
component: review
