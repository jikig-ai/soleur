---
title: "A merged fix is not a deployed fix on Concierge; instrument the blind surface, never ask the operator to run diagnostics"
date: 2026-07-02
category: workflow-patterns
module: agent-sandbox, deploy-pipeline, reproduce-bug
tags: [concierge, agent-sandbox, deploy, observability, blind-surface, plugin-deploy-gap]
related_prs: [5880, 5888]
related_adrs: [ADR-080]
---

# Learning: merged ≠ deployed on Concierge; instrument, don't ask

## Problem

A stale-`.git/config.lock` self-heal fix (PR #5880) merged to `main` + released as a
plugin version, but Concierge kept hitting the identical failure the next day. Two
compounding wrong assumptions cost a full extra cycle:

1. **"Self-heals on next session"** assumed the merged script was *running* on the
   Concierge host. It was not.
2. When the fix still didn't work, I asked the operator to run `ls`/`stat`/`findmnt`
   in the sandbox to diagnose — a direct violation of
   `hr-no-dashboard-eyeball-pull-data-yourself` and the "Soleur users are
   non-technical" principle.

## Root Cause (two layers)

**Delivery gap:** Concierge runs plugin code from `/mnt/data/plugins/soleur`, a
read-only bind-mount **seeded from the web-platform Docker image** and re-seeded on
every deploy (`ci-deploy.sh`). That image is rebuilt+deployed ONLY by
`web-platform-release.yml`, which triggered only on `apps/web-platform/**`. So a
**plugins-only merge rebuilt no image and deployed nothing** — the host kept running
the pre-fix script until a coincidental `apps/` deploy. (Fixed in PR #5888 / ADR-080:
widen BOTH the outer `on.push.paths` AND `reusable-release.yml`'s inner
`check_changed` gate to a runtime-plugin denylist.)

**Diagnosis method gap:** the Concierge agent-sandbox is a **blind execution
surface** — you cannot run interactive diagnostics in it. Asking the operator to run
shell commands is never the answer.

## Key Insight

1. **A fix in `main` is not a fix in production.** Before claiming a fix works,
   verify the DELIVERY PATH end-to-end: does the merge actually rebuild/redeploy the
   artifact the failing surface runs? For Concierge plugin code, "merged" only
   reaches the host on a web-platform image rebuild. Check the last deploy timestamp
   vs. the merge, and confirm the running artifact contains the fix.
2. **On a blind execution surface, the deployed code IS your diagnostic instrument —
   the operator is not.** When you need ground truth from Concierge / agent-sandbox /
   a cron worker, add structured, grep-able diagnostics to the deployed code so the
   next occurrence self-reports into the surface's own debug stream, then read that.
   NEVER ask a (non-technical) operator to run `ls`/`stat`/`git config`/etc.
   Companion to `hr-no-dashboard-eyeball-pull-data-yourself` and
   `hr-no-ssh-fallback-in-runbooks`.
3. **Confident agent reasoning that contradicts empirical signal is a hypothesis, not
   a verdict.** Across this incident, multiple agents (two in-sandbox, one Explore)
   confidently asserted opposite root causes; the code-model reads and the live
   behavior conflicted. When they conflict, get the raw evidence — via
   instrumentation, not the operator.

## Session Errors

- **Claimed the #5880 fix "self-heals on next session" without verifying deployment.**
  Recovery: traced the plugin-delivery path (symlink → mount → image seed) and found
  plugins-only merges never deploy. **Prevention:** verify the delivery/deploy path
  before declaring a blind-surface fix live (Key Insight #1).
- **Asked the operator to run `ls`/`stat`/`findmnt` in the sandbox.** Recovery:
  operator corrected me; pivoted to instrument-the-deployed-code. **Prevention:** the
  reproduce-bug skill Sharp Edge added by this session (Key Insight #2).
- **Delegated-implementation subagent stalled (600s watchdog) during the ~5-min
  `test-all.sh` run.** Recovery: verified the 4 landed commits, removed an orphan
  plan, ran the gate in the orchestrator. **Prevention:** run the slow full-suite exit
  gate in the orchestrator, not inside a delegated implementation subagent whose
  silent long command trips the no-progress watchdog. (recurring)
- **Planning subagent left an orphan duplicate plan file** (`...trigger-gap-plan.md`
  untracked). Recovery: removed it before ship. **Prevention:** one-off; subagent
  artifact hygiene.
- **Ran the new `plugins/soleur/test/*.test.ts` with the web-platform vitest runner**
  ("No test files found") before `bun test`. Recovery: used `bun test
  plugins/soleur/`. **Prevention:** one-off.
