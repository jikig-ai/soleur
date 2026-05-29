---
title: "Extending a terraform-apply -target= allow-list must sweep ALL guard suites, not just the named filter"
date: 2026-05-29
category: workflow-patterns
tags: [terraform, github-actions, destroy-guard, test-all, orphan-suite, plan-completeness]
issue: 4585
pr: 4591
branch: feat-one-shot-4585-sentry-uptime-autoapply
---

# Learning: extending a `-target=` allow-list must sweep all guard suites + posture-describing docs

## Problem

PR #4585 extended `.github/workflows/apply-sentry-infra.yml`'s auto-apply
`-target=` allow-list from 17 `sentry_cron_monitor.*` resources to also include
4 `sentry_uptime_monitor.*` resources. The plan (deepened, with AC1–AC9)
identified two guard artifacts to sync:

- `tests/scripts/lib/destroy-guard-filter-sentry.jq` (the jq filter — AC5)
- `tests/scripts/test-destroy-guard-counter-sentry.sh` (its counter test — AC6/AC8)

But it **missed a third** artifact that mechanically asserts on the same
allow-list: `tests/scripts/test-destroy-guard-sentry-scope-guard.sh`, a
forward-looking guard whose whole job is to FAIL when the workflow's `-target=`
set contains a resource type the jq filter has not been verified to cover. Its
allow-list was hard-coded `grep -vxF 'sentry_cron_monitor'`. The moment the
uptime targets landed, this guard failed:

```
[FAIL] apply-sentry-infra.yml targets unexpected resource type(s):
  sentry_uptime_monitor
[FAIL] tests/scripts/destroy-guard-sentry-scope-guard (17ms)
```

It was caught **only** by the work-phase-2-exit full-suite gate
(`bash scripts/test-all.sh`), NOT by the touched-file tests — the scope guard
is an orphan suite relative to the files the diff touched.

A second near-miss: that first `test-all.sh` run **exited 0** while printing
`=== 82/83 suites passed ===`. The non-zero suite was masked by the runner's
exit-code aggregation (the known test-all tail-masking shape). It was caught
only because the `N/N suites passed` summary line was read, not the exit code.

## Solution

1. Widened the scope guard's allow-list regex:
   `grep -vxF 'sentry_cron_monitor'` → `grep -vxE 'sentry_cron_monitor|sentry_uptime_monitor'`
   (`-F`→`-E` to use `|`; `-x` retained for full-line anchoring).
2. Corrected the guard's header comment, which had **speculatively** asserted
   `sentry_uptime_monitor` would carry `check_locations{}` array-of-blocks.
   Verified against the pinned provider binary schema (`block_types: []`) that
   uptime monitors are scalar-only, so `nested_deletes: 0` stays correct and no
   jq nested-clause is needed. Added the beta-schema-bump re-validation as the
   documented compensating control for the type-based (not shape-based) guard.
3. Multi-agent review surfaced two more posture-describing docs the plan's
   naming-sweep (AC4, workflow-scoped) had missed: the `AUTO-APPLY NOTE` header
   in `uptime-monitors.tf` and the `## Auto-apply` section of ADR-031 — both
   still asserted uptime monitors are operator-applied. Synced both.
4. Review also caught the plan's AC11 prescribing `GET /organizations/{org}/monitors/`
   (the Sentry **Crons** endpoint) to verify uptime monitors — that endpoint
   does not return uptime monitors, so the probe would false-fail and force a
   dashboard eyeball. Reworded to `terraform state list | grep -c sentry_uptime_monitor == 4`.

## Key Insight

When a change extends a hand-maintained allow-list (terraform `-target=`,
a CSRF route set, an RLS table list, an enum gate), the authoritative work-list
of files to sync is **every file that asserts on or describes that list** —
discovered by grep, not by the plan's enumeration. For a `-target=` allow-list
specifically: the jq filter, its counter test, AND any *scope guard* that
mechanically forbids un-covered types. The plan reliably finds the filter +
counter (they share a name stem); the scope guard is an orphan because it lives
under a different name and only the full-suite exit gate exercises it.

Two cheap gates would have caught this at plan/work time:
- **At plan time:** `git grep -l '<resource-type-prefix>\|--target\|-target=' tests/`
  to enumerate every guard touching the allow-list.
- **At work time:** the Phase 2 `test-all.sh` exit gate is load-bearing for
  exactly this orphan-suite class — and you MUST read its `N/N suites passed`
  line, never trust its exit code (it masks failures).

Separately: an AC that prescribes an API-GET verification is a precondition to
verify, not a fact — confirm the endpoint actually returns the resource type
before the plan commits to it.

## Session Errors

1. **Plan missed the scope-guard orphan suite.** AC5/AC6 synced the jq filter +
   counter test but not `test-destroy-guard-sentry-scope-guard.sh`, which
   hard-codes the allow-list. — Recovery: widened the guard regex + corrected
   its header; added the file to the plan's Files to Edit. — Prevention: at
   plan time, `git grep -l` every guard/test that asserts on the allow-list
   being extended; at work time, the `test-all.sh` exit gate catches the orphan.
2. **`test-all.sh` exited 0 with a `[FAIL]` present** (`82/83 suites passed`). —
   Recovery: read the summary line, investigated the failing suite. — Prevention:
   already-known (test-all tail-masking); assert on `N/N suites passed`, not exit code.
3. **Plan AC11 prescribed the wrong Sentry endpoint** (`/monitors/` is Crons-only,
   excludes uptime monitors). — Recovery: reworded AC11 (plan + tasks) to a
   `terraform state list` probe. — Prevention: verify an AC's API endpoint
   returns the target resource type before committing the plan.
4. **Plan AC4 naming-sweep was workflow-scoped only** — left stale
   manual-apply claims in `uptime-monitors.tf` header + ADR-031. — Recovery:
   synced both inline at review. — Prevention: when flipping apply-posture
   (manual→auto), grep every file describing the posture (`.tf` headers, ADRs).
5. **`File has been modified since read` on tasks.md/plan.md Edits** — caused by
   earlier `sed` checkbox-marking + linter touching files between Read and Edit.
   — Recovery: re-read then edited. — Prevention: re-read before Edit when a
   prior bulk/sed op touched the file this session.
