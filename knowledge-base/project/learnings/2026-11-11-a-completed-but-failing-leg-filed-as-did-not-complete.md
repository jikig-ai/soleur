---
title: "A completed-but-failing direct-invocation leg files as 'did not complete' unless the leg emits the runner's verdict token"
date: 2026-11-11
category: workflow-issues
module: .github/workflows/main-health-monitor.yml leg capture -> issue filer
tags: [ci-leg, verdict-token, cap-fail, direct-invocation, censored-leg, leg-report, test-all]
issues: ["#12626"]
pr: "#12654"
synced_to: [wfs, plan-sharp-edges, ci-workflow-authoring]
---

# Learning: a completed-but-failing direct-invocation leg files as "did not complete" unless the leg emits the runner's verdict token

## Problem

PR #12654 added `test-webplat-mutations` monitor legs that invoke each battery script DIRECTLY — `bash apps/web-platform/test/<battery>.test.sh` — instead of going through `scripts/test-all.sh`. It has to: the batteries are registered under `VITEST_SHARD`-gated `skip_suite` declines, so `test-all.sh` declines the registrations the moment any shard env is set. A leg that ran to completion and legitimately FAILED produced a teed capture containing none of the runner's verdict tokens, and the main-health-monitor issue filer (`main-health-monitor.yml`, the `cap_fail` gate around the leg-report parse) classified the leg under its else arm: "Run did not complete — a suite was terminated". Censored-leg semantics applied to a verdict-bearing capture — a failing run filed as a crash/timeout would send triage down the wrong path (revert-vs-investigate guidance, signal-shape reasoning) on an ordinary red suite. Caught as a P2 in the sequential-fallback review round, before merge.

## Solution

Emit the runner's own verdict token into the teed capture on non-zero exit, immediately before `exit "$rc"`:

```bash
# main-health-monitor.yml, mut leg step tail:
if (( rc != 0 )); then
  echo "RED apps/web-platform/test/${{ matrix.battery }}.test.sh" | tee -a "$RUNNER_TEMP/leg-report/capture.txt"
fi
exit "$rc"
```

The emit sits BEHIND the `rc != 0` check and at the step's tail for a reason: a censored leg (killed by the step/job `timeout-minutes`) never reaches the line, so "no token in the capture" keeps meaning "did not complete". Pin it: assertion S8 in `plugins/soleur/test/main-health-monitor-workflow.test.sh` greps the leg body for the `RED apps/web-platform/test/${{ matrix.battery }}.test.sh` emit.

## Key Insight

When a workflow leg bypasses the runner, the capture it tees must still speak the runner's verdict vocabulary to every downstream classifier. The main-health-monitor filer's `cap_fail` gate recognizes exactly: `^RED `, `^UNACCOUNTED `, a `=== N suites: ... [1-9][0-9]* failed ...` breakdown, or the `[FAIL]`+short-terminal pairing. A script invoked directly emits none of those, so the classifier's failure arm is unreachable no matter how red the suite went.

The generalizable class: ANY direct-invocation leg added to a workflow whose downstream classifier keys on runner tokens needs a verdict shim, and the shim must be CONDITIONAL on failure at the step tail — an unconditional emit would turn a censored leg into a false "tests failing" filing and erase the complete-vs-timeout split the filer relies on. Audit recipe: list the classifier's token set, then for each leg ask "which line in this leg's capture produces that token on a completed failure?" — if the answer is none, the leg needs the shim.

Companion playbook for the rest of what adding this leg touched: `2026-11-11-adding-a-ci-leg-means-mirroring-every-test-webplat-naming-surface.md`.

## Session Errors

1. **`lint-guard-contract.py` rejected the plan's Guard Contract** — the mutation matrix was written as prose (0 table rows). Recovery: converted it to a 4-row table; re-run green. **Prevention:** write the guard matrix as a table on the first pass; the lint counts rows, not paragraphs.
2. **A `git commit` was blocked by the main-branch guard on ambient cwd.** Recovery: ran git inside the worktree path. **Prevention:** anchor git invocations to the worktree root, not the ambient shell cwd.
3. **A background `find` over the repo root was killed as too slow.** Recovery: none needed; no side effects. **Prevention:** scope repo-wide `find`s to the subtrees that can contain the answer.
4. **The plan claimed `--rows` exists as a row-splitting lever on `approval-guard1-mutation`; the battery argv is `[--only|--list|--check-anchors]`** — a CTO ruling caught it and the plan was amended. Recovery: CTO factual correction, plan/tasks amended, `--rows` deferred as a named follow-up lever. **Prevention:** read the tool's actual argv (or `--help` handling) before a plan proposes a flag as an implementation lever — this is `hr-verify-repo-capability-claim-before-assert`, and the technical-ruling gate is the backstop that caught it here. See routed bullet in `plugins/soleur/skills/plan/references/plan-sharp-edges.md`.
5. **The monitor mut leg's failing-vs-incomplete misclassification was missed at implementation time** (the P2 this learning documents). Recovery: review-round fix — conditional `RED ` emit + S8 pin. **Prevention:** when adding a leg that bypasses the test runner, check the downstream classifier's token set against the leg's capture per terminal state; see routed bullet in `plugins/soleur/skills/review/references/wfs.md`.
6. **P3 wording corrections in the review round:** session-state recorded a "job-level 45m" ceiling phrasing that could read as a step ceiling, and the `ci.yml` leg-shape comment claimed "each leg invokes test-all.sh" plus a stale "single legs" census. Recovery: corrected both in the fix-round commit. **Prevention:** when a diff changes WHO invokes the runner, grep the workflow's own comments for "invokes"/leg-shape claims in the same commit — a comment the diff falsifies is a stale claim the next reader trusts.

## Tags
category: workflow-issues
module: .github/workflows/main-health-monitor.yml leg capture -> issue filer
