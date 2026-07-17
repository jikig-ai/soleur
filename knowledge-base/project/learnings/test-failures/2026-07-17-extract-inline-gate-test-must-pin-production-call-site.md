---
module: infra-config-gate
date: 2026-07-17
problem_type: test_coverage_gap
component: ci_gate
symptoms:
  - "A hermetic gate test is 12/12 green while the gate is deletable from the workflow it guards"
  - "Deleting or in-loop-moving the workflow's call to the extracted adjudicator leaves the suite green"
root_cause: unpinned_production_call_site
severity: high
tags: [ci-gate, test-vacuity, placement-not-correctness, extract-to-sourceable, mutation-testing, infra]
synced_to: []
---

# Learning: an extracted CI gate's test must pin its PRODUCTION call-site, not just the extracted logic

## Problem

PR #6613 (#6594 PR-B) extracted an inline CI gate — the "Verify infra-config apply
succeeded" adjudication in `.github/workflows/apply-deploy-pipeline-fix.yml` — into a
sourceable, unit-tested script (`apps/web-platform/infra/infra-config-gate.sh`, driven
by `infra-config-gate.test.sh`). The hermetic test was 12/12 green and mutation-tested
the adjudicator's *logic* thoroughly (3 fixtures + 3 mutations).

The review's test-design agent found the gap: **the test proved the adjudicator's logic
but was blind to the gate's PLACEMENT in the pipeline it guards.** Its only workflow-wiring
assertion checked the *test's own* registration in `infra-validation.yml`. Nothing asserted
that `apply-deploy-pipeline-fix.yml` actually CALLS `adjudicate_infra_config`, or that it
calls it TERMINALLY (outside the poll loop). Two reverts left the suite fully green:

1. Delete the terminal `if ! adjudicate_infra_config …` block → the #6594 content assert is
   **dead in production**, suite green.
2. Move the call INSIDE the `for attempt in 1 2 3` loop → each retry re-fetches (a fresh
   Cloudflare connector selection) = "retry until SOME host matches" = the any-of-3 coin
   flip the gate exists to kill (#6594). The test never exercises the loop → green.

This is the "a gate certifies placement not correctness" class (2026-07-16 learnings)
turned on the gate itself.

## Solution

Add a **wiring-pin** assertion to the test that reads the CONSUMING workflow and requires:
(a) the terminal adjudicator call exists at all, and (b) it is OUTSIDE the poll loop — a
`done` line strictly between the in-loop count-only break (`infra_config_count_invariant`)
and the terminal content assert (`adjudicate_infra_config`).

```bash
adj_line=$(grep -nE '(^|[^_[:alnum:]])adjudicate_infra_config[[:space:]]+/tmp/' "$APPLY_WF" | head -1 | cut -d: -f1)
ci_line=$(grep -nE 'infra_config_count_invariant[[:space:]]+/tmp/' "$APPLY_WF" | head -1 | cut -d: -f1)
between_done=$(awk -v a="$ci_line" -v b="$adj_line" 'NR>a && NR<b && $1=="done"{print NR; exit}' "$APPLY_WF")
[[ "$ci_line" -lt "$adj_line" && -n "$between_done" ]]   # else: not terminal → fail
```

Mutation-proven against sandbox copies of the workflow: deleting the call reds it
("adjudicate absent"), moving it in-loop reds it ("count_invariant absent"). This mirrors
the self-registration discipline the test already applied to its own runner — extend that
same discipline to the production consumer.

## Key Insight

**An extract-inline-logic-to-sourceable-script refactor must pin the production CALL-SITE
(that the consumer calls it, AND where), not just the extracted logic.** A unit test that
sources the `.sh` and drives its functions directly is necessary but not sufficient: the
value of a gate is its placement in the pipeline it guards, and that placement lives in a
DIFFERENT file (the workflow) the unit test never reads. The same rule the repo already
applies to orphan-test registration (`#5417`: assert the test is wired into a runner)
applies to the gate's own call-site.

Companion failure (fixed in PR #6611, same session): a script that reads a RELATIVE env
var (`INFRA_DIR=apps/web-platform/infra`) AND is invoked by a workflow step with
`working-directory: $INFRA_DIR` double-cds and dies "No such file or directory" — CWD is
already that dir. Derive the dir from `BASH_SOURCE` (absolute, CWD-independent), never
honor a relative env override.

Corollary (two more test gaps the review found, both "a mutation battery only covers what
you mutate"): the `missing`-class arm had zero coverage because the fixture builder created
a real file for both comparable AND missing dests; the `status != "ok"` clause was only
reached via entry-deletion (caught by the `-z host_sha` clause), so a present-but-failed
delivery was untested. Enumerate the SUT's branches and ensure each has a fixture that
REACHES it — a green battery is evidence about the mutations you wrote, not about coverage.

## Session Errors

1. **PR-A's post-merge apply failed** on `verify-tunnel-ingress-origin.sh` double-cd of a
   relative `INFRA_DIR`. **Recovery:** PR #6611 (derive from `BASH_SOURCE`). **Prevention:**
   a workflow that sets `working-directory: $X` must not also pass `$X` (relative) as a dir
   the script re-cds; scripts derive their own dir absolutely.
2. **PR-A's `user_data` size test red** — a 17-line rationale comment shipped into cloud-init
   via base64. **Recovery:** moved rationale to `server.tf` (not byte-budgeted) + modest
   re-baseline. **Prevention:** keep-inline files' comments are byte-budgeted; put rationale
   in `.tf` (the #6425 precedent).
3. **`gh pr merge --delete-branch=false` blocked** by the orphan-worktree guardrail.
   **Recovery:** dropped the flag. **Prevention:** don't pass `--delete-branch` when
   worktrees are active; let cleanup-merged reap post-merge.
4. **`worktree-manager.sh remove` printed usage** (no such subcommand). **Recovery:**
   `git worktree remove`. **Prevention:** the script has no `remove` verb; use git directly.
5. **Gate test first run failed** — passed the infra dir as the `apply_script` arg
   (`sed: Is a directory`). **Recovery:** fixed the arg order. **Prevention:** one-off.

## Tags
category: test-failures
module: infra-config-gate
