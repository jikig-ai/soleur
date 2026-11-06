---
title: "The tasks-file grouping table contradicted the plan's own census, workers followed the wrong row, and the P1 shipped until the review panel caught it four times"
date: 2026-11-03
category: workflow-patterns
tags: [one-shot, tasks-file, census, grouping-table, p1, #11899, PR-#11957]
---

# Learning: the per-file work-list is a second source of truth, and its "already present" bucket silently overrode the measured census

## Problem

PR #11957 (issue #11899, one-shot pipeline) converged fourteen convention
suites in `apps/web-platform/test/infra/` plus `scripts/guard-vacuity-floor.test.sh`
on the registry-clientip `hdr()` idiom. The issue named narrow subsets (5
`fail>0`, 4 step-pin, 2 `SELF`); a measured census table in the plan
(`knowledge-base/project/plans/2026-11-03-chore-convention-suite-cleanup-plan.md`
§Convention-family census) showed the defect family-wide — 12 missing the
pre-battery `fail>0` gate, 8 missing step-shape pins — and a CTO ruling
correctly widened scope to the census. That ruling was right. The failure was
downstream of it.

The plan's Phase-2 grouping (and the tasks.md that mirrored it) bucketed
`egress-gw-alert.test.sh` into "Group B — seam + `fail>0` only, **step pins
already present**" while the census table three pages earlier in the same plan
recorded egress-gw's step-pins column as `MISSING`. The grouping was derived by
hand, not generated from the census, and nobody grep-verified the "already
present" claim. Five work-phase workers followed the grouping row; the
five-seat fan-out edited fifteen files and egress-gw shipped with no
step-shape pins. The 9-seat review panel caught it as a convergent P1 — four
independent seats flagged the same missing file. The instrument worked; the
work-list had already lost what the census measured.

## Solution

Fix-round (commits through `9b1c0c9108`) restored egress-gw to the step-pin
group and, per the CTO dissent amend (D1/D2 in `decision-challenges.md`),
converged all five awk slice dialects family-wide onto the registry-clientip
`hdr()` idiom: `JOB_BLOCK`/`STEP_BLOCK` derived from the pinned run line,
`STEP_BAD` name+run and `JOB_BAD` key-allowlists, `if:`/`continue-on-error:`
banned at step, top-of-job, and whole-job positions, file-wide `^defaults:`
ban, and six shape mutation rows per suite. The slice is now derived from the
pinned run line, never a hardcoded job name — the same correction the CTO
applied to the plan's own `validate:`/`deploy-script-tests-fixed:` mislabel.

## Key Insight

A plan can contain the correct measured truth and still ship the defect if the
derived work-list is built by paraphrase rather than by projection. The census
table and the grouping table were two sources of truth for the same fact; the
second one silently won because it was the one workers were fanned out on.
"Already present" and "already verbatim" are *claims about the world* — the
cheapest possible class to grep-verify — yet they were carried as prose
through plan → tasks → five worker prompts without a single check. Derive
per-file work-lists mechanically from the one measured table, and treat every
"already X" in a grouping table as a grep obligation at work-start. Also
notable: the issue's named subsets understated the measured census — the
issue body is a hypothesis, and the family-wide ruling was the right call; the
error was not scope but provenance.

## Session Errors

1. **Plan mislabel: enclosing job named `validate:`, actual job is
   `deploy-script-tests-fixed:`** (`infra-validation.yml:847`; `validate:` at
   :473 is a different job). Seven mislabels corrected by the technical-ruling
   gate before implementation. **Prevention:** verify workflow job names
   against the file before plan/ruling phases close — the ruling that caught
   this now requires the slice be derived from the pinned run line, never a
   hardcoded job name.
2. **Census donor mislabel: plan cited egress-gw as the `CENSUS_*` donor;
   actual donor is faithful-canary-sandbox** (`CENSUS_NAMES`/`CENSUS_N`/
   `CENSUS_MISSING` at :350-357; egress-gw carries no census block). Same
   class, same gate, same correction. **Prevention:** same as (1) — name
   citations in a plan are preconditions to re-verify, not evidence.
3. **tasks.md classification bug (the costly one).** The per-file grouping
   bucketed egress-gw into "step pins already present," contradicting the
   plan's own census row (`MISSING`). Workers followed the wrong row and the
   P1 shipped; the review panel caught it four seats deep. An "already
   present" claim in a grouping table was never grep-verified.
   **Prevention:** derive per-file work-lists from ONE source of truth;
   grep-verify any "already present"/"already verbatim" claim in a plan or
   tasks file before fan-out. See Workflow-Feedback Proposals.
4. **Pre-existing defect fixed this PR: bare `$$` in
   `registry-zot-credential-shape-alert.test.sh` (~:472) pid-expanded inside an
   unquoted `<<PY` heredoc** — fixed to `\x24\x24` (`fa2bafaca2`).
   **Prevention:** the landmine sweep is already documented; add `\$\$` to the
   convention checklist (now in tasks 4.5).
5. **Commit tooling rejected a command that changed `CLAUDE_PLUGIN_ROOT`
   before staging.** Recovery: separate `git add` then `git commit`.
   **Prevention:** one-off, no recurrence vector.
6. **`git -C`/hooks required literal paths (no variable expansion) in this
   worktree.** Minor friction. **Prevention:** one-off.
7. **Session-start tmp-sweep lock contention + worktree capacity contention.**
   Informational, no defect. **Prevention:** none needed.
8. **Pre-existing LOW noted by the fix-round seat: `inngest-cutover` carries
   no `mutate_floor_red` row** — its stricter `MUT_ROWS_RUN ==
   MUT_ROWS_EXPECTED` exact-count ledger (:338, :566-567) covers row drift by
   exit-2 FATAL instead. Documented as accepted residual; deliberately NOT
   filed as an issue. **Prevention:** none — the exact-count ledger is the
   stronger invariant for this suite.

## Triage

| # | Class | Disposition |
|---|---|---|
| 1–3 | Recurring — plan/tasks assert facts about files without re-verifying; the "already present" bucket overrides a measured table | **Workflow-rule proposal** (below) |
| 4 | Recurring — documented landmine class (`$$` in unquoted heredoc) | Already covered by the landmine-sweep hard rule; reinforced by adding `\$\$` to the convention checklist |
| 5–7 | One-off tooling/environment friction | No action |
| 8 | Pre-existing LOW, accepted residual | Documented; no issue filed |

## Workflow-Feedback Proposals

**Proposed rule (tier: advisory):** *Grep-verify "already present" claims in
work-lists.* When a plan or tasks file contains a per-file grouping table, any
cell or bucket asserting a capability is "already present" / "already
verbatim" / "has" must be re-verified with a concrete grep at work-start,
before fan-out, and the grouping should be generated from the measured census
table rather than paraphrased. Cost: one grep per claim; the alternative is a
P1 that only the review panel catches. This would have caught errors 1–3:
`validate:` vs `deploy-script-tests-fixed:` is a `grep -n "^  [a-z-]*:"`
check; the egress-gw bucket is a one-line read of the census row it
contradicted. Suggested home: the work skill's fan-out preamble or the
plan→tasks handoff gate, as an advisory checklist line, not a blocking gate —
the claim set is small and heterogeneous enough that enumeration stays manual.

## Tags

category: workflow-patterns
module: apps/web-platform/test/infra (convention-alert suites), scripts/guard-vacuity-floor.test.sh, .github/workflows/infra-validation.yml
related: 2026-07-08-git-config-atomic-writer-and-plan-vs-tasks-drift.md, 2026-10-15-a-guard-vocabulary-widened-and-its-census-did-not-and-prose-was-scoped-narrower-than-its-claims.md
issue: '#11899'
pr: '#11957'
