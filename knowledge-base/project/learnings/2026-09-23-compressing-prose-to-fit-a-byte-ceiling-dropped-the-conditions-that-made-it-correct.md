---
title: Compressing skill prose to fit a byte ceiling dropped the conditions that made it correct
date: 2026-09-23
category: workflow-issues
tags: [skill-body-budget, compound, brainstorm, prose-review, qa-dry-run, mattpocock-audit]
pr: 8647
refs: [8284, 8648]
---

# Learning: compressing skill prose to fit a byte ceiling dropped the conditions that made it correct

## Problem

PR #8647 (mattpocock/skills audit B4/B10/B12b) added prose to three plugin surfaces. The
plan specified the B10 wording for `compound/SKILL.md` Phase 1.5 step 3.6 verbatim, and
never measured that file against its lifecycle byte ceiling
(`plugins/soleur/test/skill-body-budget.json`: `compound` = 57000, enforced against the merge
base by `scripts/lint-skill-body-budget.py`, ADR-229). The planned text put the file at
58100 bytes, and lefthook `skill-body-budget-lint` refused the first implementation commit.

The work phase compressed the step to 56839 bytes and recorded "every clause and AC anchor is
kept". Two conditions had in fact been dropped:

- the report label `Rule violated: none (null guardrail)` had applied only to findings "not
  already attached to a deviation";
- the `Existing enforcement: unwired: <check> | none` field had carried the name of the check
  to wire in.

The step's scope also still took in "each step-3 deviation". Four of six review seats
independently traced one root cause to four symptoms: a self-contradicting scope sentence, two
proposals for one deviation, a wrong `Rule violated` label, and a false "reuse step 3.6's scan"
claim.

After the review fixes, a constrained QA dry run (a subagent executing the prose against six
scenarios, read-only) found a contradiction all six seats had missed. A step-3.6 finding that
amends an Error-to-Workflow hook proposal fell under two opposite headless rules in
Constitution Promotion: "auto-accept hook proposals with clear mappings" and "never auto-accept
a step-3.6 finding".

## Solution

- Narrowed step 3.6 to Phase 0.5 `recurring` code/config items and left hard-rule deviations
  with step 4. That removed all four symptoms at once, and reverting step 4 to its original
  text freed bytes.
- Put the `Existing enforcement` field back in step 3.6's report clause.
- Stated the headless rule once, in the terms the reader matches on ("never auto-accept a
  step-3.6 finding"), and made an amended Error-to-Workflow proposal count as a step-3.6
  finding so only one rule applies.
- Final size: 56934 / 57000 bytes. The ceiling was not raised.

## Key Insight

A byte ceiling is a precondition to measure at PLAN time, and the wording should be budgeted
as a delta against it (`ceiling - wc -c`). Compression done under a failing hook optimises
for bytes, and a clause that reads like padding ("not already attached to a deviation") is
usually the one carrying a condition. After any compression, diff the compressed text against
the planned text clause by clause, not anchor by anchor: every AC anchor survived here while
two conditions did not.

For prose that routes between sections (a classification one section writes and three others
read), review seats reading hunks miss cross-section contradictions. A dry run that executes
the prose against concrete scenarios finds them, as the qa Notes (#8288) already say.

## Session Errors

1. **Plan subagent read `deepen-plan/SKILL.md` from the bare-repo path instead of the worktree.**
   Recovery: diffed the worktree copy (identical for the range). Prevention: the Skill tool
   announces each skill's base directory under the bare repo root, which steers reads there;
   a subagent brief should name the worktree path for every skill file it reads.
2. **Plan misquoted test-fix-loop's detection order.** Recovery: removed the claim and link.
   Prevention: existing rule (plan-quoted facts are preconditions to verify).
3. **The source plan named `skills/help/SKILL.md` for B12.** Recovery: targeted
   `commands/help.md`, since the skill is a Devin shim. Prevention: existing rule (the plan is
   authoritative for intent, not paths).
4. **An AC grep count for `operator-*` was wrong (3 vs 6).** Recovery: re-measured on
   `origin/main`. Prevention: existing rule (re-derive plan-quoted numbers).
5. **The first commit was blocked: `compound/SKILL.md` was 58100 bytes against a 57000 ceiling
   the plan never measured.** Recovery: compressed the prose. Prevention: new plan sharp edge:
   measure the lifecycle-skill byte ceiling at plan time and budget the prose as a delta.
6. **The compression dropped two load-bearing conditions, and four review seats converged on
   the result.** Recovery: narrowed step 3.6's scope and restored the field. Prevention: the
   same sharp edge, plus diffing the compressed text against the planned text clause by clause.
7. **A Python batch-edit script with a SyntaxError applied nothing.** Recovery: the unchanged
   map output exposed it and the batch was re-run. Prevention: existing `work/SKILL.md` rule
   (a batch that fails to parse looks like one that landed; print the artifact back).
8. **`lint-skill-body-budget.py` run without `--base` returned rc=2 (usage), first read as the
   verdict.** Recovery: re-ran with `--base origin/main`. Prevention: copy a lint's invocation
   from `lefthook.yml` before reading its verdict.
9. **`git rev-parse origin/<branch>` failed after a fetch (no remote-tracking ref).** Recovery:
   `git ls-remote`. Prevention: one-off.
10. **`test-all.sh --capacity` reported CAPACITY_CONTENDED because a sibling full gate was
    running.** Recovery: ran the consumer-derived suites instead. Prevention: one-off
    (environmental).
11. **The QA dry run found a headless auto-accept contradiction that six review seats missed.**
    Recovery: made an amended proposal a step-3.6 finding. Prevention: existing qa Notes
    dry-run rule (#8288). Dogfood note: the byte-ceiling class (5) is **covered**: the lefthook
    pre-commit ran `skill-body-budget-lint` on the failing path, which is what caught it.

## Tags

category: workflow-issues
module: plugins/soleur/skills/compound, plugins/soleur/skills/plan
