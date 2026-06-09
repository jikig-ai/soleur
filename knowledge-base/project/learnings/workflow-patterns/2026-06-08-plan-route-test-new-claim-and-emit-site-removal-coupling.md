---
title: "A plan's \"this route test is NEW\" claim and \"remove this read\" both need a wider grep than the plan ran"
date: 2026-06-08
category: workflow-patterns
tags: [planning, test-discovery, observability-coupling, resolver-convergence, sentry-alerts]
issue: 5005
pr: feat-one-shot-5005-workspace-path-readers
---

## Problem

`/one-shot #5005` converged five read paths off the legacy `users.workspace_path`/
`workspace_status` columns onto the workspace-id resolver. The plan's research
(a test-excluded `git grep`) produced two assertions that were both wrong, and
both surfaced only at the **full-suite exit gate** (`vitest run` → 2 failed
files / 7 failed tests) — after the per-file TDD loops had all gone green:

1. **"`kb-sync-route.test.ts` is correctly NEW."** A canonical route test
   already existed at `apps/web-platform/test/server/kb-sync-route.test.ts` —
   one directory deeper than the plan's grep looked. I had already authored a
   *duplicate* `test/kb-sync-route.test.ts` against the GREEN design before the
   exit gate revealed the original (which still mocked the old tenant-client
   path and broke on my change).

2. **kb/sync's tenant-mint removal silently darkened a production Sentry alert.**
   Dropping `getFreshTenantClient` from kb/sync deleted the last
   `kb-sync.tenant-mint` emit site — the surviving slug that kept the
   `kb_tenant_mint_silent_fallback` issue-alert armed (the #4953/#4956 lineage
   had already migrated the other KB routes off it). A cross-artifact contract
   test (`test/sentry-kb-tenant-mint-alert-op-contract.test.ts`) asserts the
   slug lives in both the route and `infra/sentry/issue-alerts.tf`, so it failed
   — but the *real* consequence was an alert that would never fire again.

## Solution

1. Rewrote the canonical `test/server/kb-sync-route.test.ts` for the resolver
   path (preserving its error_class / recovered / body-ignore coverage) and
   deleted the duplicate `test/kb-sync-route.test.ts`.
2. Re-pointed (not retired) the alert to the route's surviving silent-failure
   surface — `op=kb-sync.unexpected`, resource renamed `kb_sync_silent_failure`
   — and renamed/retargeted its contract test, after surfacing the fork to the
   operator (re-point vs retire). Re-pointing keeps a notification armed on the
   converged route's real failure surface, which is what the #4913 PIR proved
   necessary.

## Key Insight

A plan's `git grep` is a **hypothesis about the work-list, not the work-list**
(this repo's `cq`/`hr` corpus already says this for source files — it applies to
TESTS and to OBSERVABILITY COUPLING too):

- **Before trusting "this route/component test is NEW,"** re-grep EVERY test
  directory for an existing suite that imports the route under test —
  `git grep -l "app/api/<route>/route" -- 'apps/web-platform/test/**'` —
  including nested `test/server/`, `test/helpers/`. A route test living one dir
  deeper than the plan's glob reads as "absent" and you author a duplicate.
- **Before deleting a read/emit site** (a tenant-mint, a `reportSilentFallback`
  op slug, a log line a monitor greps), grep for what FILTERS on it:
  `git grep -rn "<op-slug>" -- 'apps/web-platform/infra/sentry/' 'apps/web-platform/test/*op-contract*'`.
  Removing the last emit site of an `op IS_IN`/`filter_match="all"` alert darks
  the alert — a silent observability regression a green typecheck never shows.

The full-suite exit gate (`hr`/`wg` "run `test-all.sh` / full `vitest` before
Phase 3") is what caught both — confirming its value as the orphan-suite
backstop, but the cheaper catch is the wider grep at plan/work-start.

## Session Errors

1. **Planning subagent transient rate-limit after 42 tool uses** (before its
   Session Summary). Recovery: partial-artifact recovery — plan + deepen-plan
   output were on disk; loaded and continued. Prevention: already covered by
   one-shot's partial-artifact recovery path; no new rule.
2. **Plan grep missed `test/server/kb-sync-route.test.ts` + the Sentry op-slug
   coupling.** Recovery: full-suite exit gate caught both; rewrote canonical
   test, deleted duplicate, re-pointed alert. Prevention: the Key Insight above,
   routed to the plan skill's research step.
3. **tsc flagged a zero-arg-inferred test mock** (`vi.fn(() => false)` then
   `.mockImplementation((p) => …)`). Recovery: typed the hoisted mock param
   `(_p?: unknown)`. Prevention: one-off; the `tsc --noEmit` work-phase gate
   caught it as designed.
4. **`git add -A … <stale-old-filename>` aborted the whole add**, so a commit
   captured only the rename/delete and not the content edits. Recovery:
   re-staged specific files + `git commit --amend`. Prevention: one-off; after a
   rename, stage by current path, and verify `git show --stat HEAD` after
   committing.
