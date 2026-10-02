---
module: System
date: 2026-10-02
problem_type: workflow_issue
component: tooling
symptoms:
  - "apply-deploy-pipeline-fix.yml closed every open infra-drift issue with 'Server state was re-aligned with HEAD' although it only plans five -target resources"
  - "#9334 was closed with a pending hcloud_server replacement and re-filed as #9382"
  - "First-draft classifier and its mutation battery passed while several rows measured nothing"
root_cause: missing_workflow_step
resolution_type: tooling_addition
severity: high
tags: [terraform-drift, auto-close, fail-closed, mutation-battery, vacuous-test, review-seats]
---

# Learning: a closer must judge the evidence it can authenticate, not the scope it was built for

## Problem

The `Auto-close any open drift issues for this stack` step in `apply-deploy-pipeline-fix.yml` closed every open `infra-drift` issue after a five-target apply. The issues come from `scheduled-terraform-drift.yml`, which files from an UNTARGETED plan. An issue whose plan carried `hcloud_server ... must be replaced` was closed although the host was never touched (#9259, #9317, #9334 closed the same way; #9382 is the live example).

## Solution

`scripts/infra-drift-autoclose.sh` holds the decision (the workflow step only calls it):

- Judge the NEWEST bot-authored plan-bearing artifact (body, then comments). Author filter keeps a forged human comment from steering the verdict.
- Skip on an `hcloud_server` replace/destroy/create (header regex plus resource-marker regex, HTML-escaped forms folded first).
- Fail closed: truncated or incomplete plan, empty body, failed `gh` read, unparseable envelope, and grep errors all skip. Only a readable, complete, replacement-free plan closes.
- `scripts/infra-drift-autoclose.test.sh` (98 assertions): classifier table, stub-`gh` e2e, workflow wiring check, scale case, `expect_eq` self-test, 14 in-suite script mutants, anti-vacuity floor.

Not changed (recorded in `decision-challenges.md`): other closers of infra-drift issues; a clean later scan writes no artifact so a stale replacement plan stays newest (closing on a clean scan is the better producer-side fix); two plan blocks in one artifact.

## Key Insight

A closer that inherits its trigger from a narrower job than the producer's must re-derive "did my scope cover this?" from the artifact itself. And a mutation battery is only as honest as its row-level checks: two rows were vacuous because one-line functions let a `sed` anchor swallow the whole `classify` call, so the mutant "ran" and the suite stayed green. `row_cases` now rejects any mutant output that is not a valid verdict.

## Session Errors

1. **`cleanup-merged` invoked as a skill name** — Recovery: ran `worktree-manager.sh cleanup-merged`. **Prevention:** one-off; the skill list names it as a script verb, no rule needed.
2. **Merge hook blocked arming auto-merge on #9414 without review evidence** — Recovery: ran `soleur:review`, emitted the trailer, re-armed. **Prevention:** hook worked as designed; run review before arming.
3. **Write to `infra-drift-autoclose.sh` refused (file modified on disk by a review seat)** — Recovery: verified the tree was clean, re-read, rewrote. **Prevention:** report-only seat briefs must say "do not mutate the worktree; mutate a sandbox copy"; re-read before any write after a fan-out.
4. **A pattern seat moved HEAD (restored by the seat)** — Recovery: confirmed HEAD at the expected SHA. **Prevention:** same brief constraint as 3; check `git rev-parse HEAD` after a fan-out before committing.
5. **Battery rows broke after the regex widening** (escaped-only fixtures stopped isolating `normalize`; m6 crashed; m10 marker collided on a substring; m13 target cases unaffected) — Recovery: added `r2-escaped-only`/`r2-double-escaped`, split m6 into reason-exact 6a/6b, renamed tag to `termfn`, dropped m13. **Prevention:** when widening a regex, re-derive which fixtures still isolate each stage before trusting row names.
6. **`fixture-relative-assert` ratchet moved (26, then 3 sites)** — Recovery: `assert_fixture_dir` before every write window rather than regenerating the baseline. **Prevention:** a file-selected suite set cannot see a repo-global ratchet (already in `work/SKILL.md`); run the ratchet suites by name when a new suite writes under `scripts/fixtures/`.
7. **Mutation rows 3/4 vacuous** — Recovery: marker-anchored mutants plus `row_cases` requiring a valid verdict. **Prevention:** every mutation row asserts the mutant differs AND still emits a verdict.
8. **Sentry API 403 on the monitor-mute read for `cron-egress-resolve` / `cron-github-cidr-refresh`** — Recovery: skipped; carried to postmerge items for #9385. **Prevention:** one-off token scope.
9. **Asked the operator technical forks (user: "Those should not be operator...")** — Recovery: decided myself from then on. **Prevention:** already covered by `hr-technical-fork-is-not-an-operator-question`; a brief's "ask me first" does not override it.

## Related

- PR #9416, issue #9382, prior-art closures #9259 / #9317 / #9334.
- Plan: `knowledge-base/project/plans/2026-10-02-fix-drift-autoclose-skip-hcloud-server-replacement-plan.md`.
