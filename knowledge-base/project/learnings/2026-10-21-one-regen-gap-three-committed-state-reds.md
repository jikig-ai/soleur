---
module: Plugin
date: 2026-10-21
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "c4-model-freshness red on the pushed branch: model.likec4.json stale vs the new verificationscaffold component"
  - "fixture-relative-assert.test.sh red: baseline lacked the new generator's row"
  - "root README.md still read '103 skills' after plugins/soleur bumped to 104"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [generated-artifacts, regenerate, committed-state-gates, one-shot]
synced_to: [work]
---

# Learning: Three committed-state reds were ONE gap — the "regenerate the derived artifacts" sweep was incomplete

## Problem

PR #10744 (verification-scaffold) added a new skill, a generator script,
templates, a `guards.tsv` manifest and test files. The review panel's
committed-state gates went red on **three independent surfaces**:

1. `docs/architecture/diagrams/model.likec4.json` — stale vs the new
   `verificationscaffold` component (`c4-model-freshness` reds).
2. `plugins/soleur/test/fixture-relative-assert.baseline.txt` — missing the
   new generator's row (`fixture-relative-assert.test.sh` reds).
3. `README.md` — still read "103 skills" while the manifest census counted
   104 (count drift vs the plugins/soleur bump).

The dedup ledger's structural-cause roll-up named it: the three reds are ONE
defect. A PR that adds or renames members which existing derived artifacts
enumerate invalidates the whole derived set, and the "regenerate the derived
artifacts" sweep had run on a subset — the artifacts the plan happened to name
— not on the enumerable set the diff actually touched.

## Solution

One commit (`0400ffe62a`) ran each artifact's own regenerator:
`scripts/regenerate-c4-model.sh` for the likec4 model, the fixture baseline
regen for `fixture-relative-assert.baseline.txt`, and the README count sync.
All three reds closed at once; plan AC1–AC11 ticked after verification.

The sweep procedure that prevents it: before declaring the regen step done,
enumerate every generator/`--check` pair whose inputs the diff can
invalidate — grep the repo for the regenerator scripts (`scripts/regenerate-*`,
`sync-*-counts`, `*baseline*`), then run each one whose domain overlaps the
touched paths. The plan's regen list is a hypothesis about the set; the repo's
generator inventory is the set.

## Key Insight

**A PR that adds a member to an enumerated set owes the FULL derived-artifact
sweep, and N reds on M surfaces is one gap, not M findings.** Two habits
generalize:

- **Dedup committed-state reds by structural cause before dispatching fixes.**
  The review ledger kept three separate-looking reds as one
  `generated-artifact-not-regenerated` key, so one commit closed all three —
  fixing them as three findings would have produced three commits and still
  possibly missed a fourth unexamined artifact.
- **Regenerate by inventory, not by plan.** Whatever regenerated the artifact
  when it was born is the tool to re-run; a hand-edit to a generated file reds
  its own `--check` and rots the provenance the artifact carries.

## Session Errors

1. **The regen sweep ran on the plan's named subset**, not the enumerable
   derived set — three reds shipped to the pushed branch. Recovery:
   `0400ffe62a`. **Prevention:** grep for every regenerator the touched paths
   can invalidate and run each; treat the plan's regen list as a hypothesis.
2. **`decision-challenges.md` non-canonical table** (forwarded, plan phase):
   5-col header + stray rows below the section — `@BADHEADER`/`@STRAY`.
   Recovery: `b33c34d2c4`. **Prevention:** `technical-ruling-gate.sh --branch`
   before returning the plan.
3. **`$WORK` bookkeeping-dir leak + partial fix** — see the sibling learning
   `2026-10-21-mktemp-cleanup-armed-late-leaks-every-early-exit.md`.
   **Prevention:** arm cleanup at mktemp; rm after the last reader.
4. **Sibling session mid-flight writes** — staged only review-owned paths; see
   `2026-10-21-sibling-session-owned-commits-on-my-branch.md`.

## Tags

category: workflow-issues
module: plugins/soleur, docs/architecture, knowledge-base
