---
title: "Tasks — TR9 PR-6 strategy-review Inngest migration"
date: 2026-05-25
plan: knowledge-base/project/plans/2026-05-25-feat-tr9-pr6-strategy-review-inngest-migration-plan.md
issue: 4416
umbrella: 3948
lane: single-domain
deepen_pass: applied 2026-05-25
---

# Tasks — TR9 PR-6 (scheduled-strategy-review → Inngest)

**Deepen-pass design change:** v1 design was "spawn `/bin/bash scripts/strategy-review-check.sh`"; corrected to "TS port of the script using `@octokit/core` + `gray-matter`" because `gh` CLI is NOT in the Hetzner Dockerfile. See plan §Enhancement Summary.

## Phase 0 — Preflight

- [x] 0.1 Verify reference file: `ls apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` (PR-5 reference, 1226 lines)
- [x] 0.2 Verify umbrella state: `gh issue view 3948 --json title,state` returns OPEN
- [x] 0.3 Verify child issue: `gh issue view 4416` returns OPEN
- [x] 0.4 Verify migration source files present: `git ls-files | grep -E "scripts/strategy-review-check.sh|.github/workflows/scheduled-strategy-review.yml"` returns BOTH
- [x] 0.5 Confirm `cron_run_ledger` reconciliation: `grep -rn cron_run_ledger apps/web-platform/ supabase/migrations/` returns ZERO
- [x] 0.6 Read existing route.ts registry to determine alphabetical insertion slot (verified: between `cronOauthProbe` line 49 and `githubOnEvent` line 50)
- [x] 0.7 **[deepen-pass]** Confirm `gray-matter` dep is present: `grep -E '"gray-matter"' apps/web-platform/package.json` returns `"gray-matter": "^4.0.3",`
- [x] 0.8 **[deepen-pass]** Confirm `gh` CLI NOT in Dockerfile: `grep -nE 'gh|github-cli' apps/web-platform/Dockerfile` returns ZERO
- [x] 0.9 **[deepen-pass]** Confirm current `-target=` count in apply-sentry-infra.yml: `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns `10` (verified — plan's "11" was stale); will become `11`

## Phase 1 — Author Inngest function (TS port, no bash spawn)

- [x] 1.1 Create `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` per plan §Phase 1 outline (755 lines including comment headers; structure matches outline)
- [x] 1.2 Helpers: `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `setupEphemeralWorkspace` (no plugin symlink; sentinel checks the 3 KB dirs), `teardownEphemeralWorkspace`
- [x] 1.3 **[deepen-pass]** TS port helpers (no PR-5 precedent): `ensureReviewLabel`, `resolveMilestoneNumber`, `listExistingReviewIssueTitles`, `collectStrategyFiles`, `parseISODate`, `runStrategyReview` — port `scripts/strategy-review-check.sh` logic 1:1 via Octokit + node:fs + gray-matter
- [x] 1.4 `postSentryHeartbeat` — single-step end-of-step.run POST (per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`)
- [x] 1.5 `cronStrategyReviewHandler` — 4 step.run blocks: mint-installation-token → setup-workspace → strategy-review-check (TS port + Promise.race against MAX_RUN_DURATION_MS) → sentry-heartbeat + finally:teardown
- [x] 1.6 Validate manual-trigger `event.data.date_override` (regex `^\d{4}-\d{2}-\d{2}$`) before threading into `runStrategyReview` as `todayISO`
- [x] 1.7 Register via `inngest.createFunction` with `id: "cron-strategy-review"`, concurrency keys (`fn`=1, `account`=`"cron-platform"`=1), triggers `[{ cron: "0 8 * * 1" }, { event: "cron/strategy-review.manual-trigger" }]`, retries=1
- [x] 1.8 **[deepen-pass]** Confirm NO `spawn(` calls other than the one in `setupEphemeralWorkspace` (`grep -cE 'spawn\(' cron-strategy-review.ts` returns exactly `1`)

## Phase 2 — Register in route.ts

- [x] 2.1 Edit `apps/web-platform/app/api/inngest/route.ts`: add `import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";` AFTER the `cronOauthProbe` import (alpha order)
- [x] 2.2 Add `cronStrategyReview,` to the `functions: [...]` array on a new line BETWEEN `cronOauthProbe,` and `githubOnEvent,`

## Phase 3 — Add Sentry cron monitor + update auto-apply target list

- [x] 3.1 Edit `apps/web-platform/infra/sentry/cron-monitors.tf`: append `sentry_cron_monitor.scheduled_strategy_review` resource AT FILE END (after `scheduled_gh_pages_cert_state` line 226)
- [x] 3.2 **[deepen-pass — CRITICAL]** Edit `.github/workflows/apply-sentry-infra.yml`: add `-target=sentry_cron_monitor.scheduled_strategy_review \` AFTER the `scheduled_follow_through` line (was 10 entries, now 11)
- [x] 3.3 Verify: `cd apps/web-platform/infra/sentry && terraform init -input=false -backend=false && terraform validate` exits 0 (only pre-existing deprecation warnings)
- [ ] 3.4 **[deepen-pass]** Verify: `actionlint .github/workflows/apply-sentry-infra.yml` (deferred to parent test phase)

## Phase 4 — DELETE GHA workflow

- [x] 4.1 `git rm .github/workflows/scheduled-strategy-review.yml`
- [x] 4.2 Confirm `scripts/strategy-review-check.sh` is UNCHANGED (not deleted — operator-local hand-testing only)

## Phase 5 — Capture learning

- [x] 5.1 Write `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md` documenting BOTH:
  - (a) the bash-spawn-blocked-by-missing-gh pattern (port to Octokit instead of installing gh in Dockerfile for one-off use)
  - (b) the apply-sentry-infra.yml `-target=` allow-list gotcha (it's NOT a wildcard; new resources need same-commit YAML edit)

## Phase 6 — Test

- [ ] 6.1 `cd apps/web-platform && bun test test/server/cron-no-byok-lease-sweep.test.ts` passes; output enumerates `cron-strategy-review.ts`
- [ ] 6.2 `cd apps/web-platform && bun run typecheck` exits 0
- [ ] 6.3 `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform validate` exits 0
- [ ] 6.4 **[deepen-pass]** Bug-for-bug parity hand-check: run `bash scripts/strategy-review-check.sh` against current `knowledge-base/` AND reason through the TS port's runStrategyReview logic — confirm identical issue title format (`Strategy Review: <scope>/<slug>`), identical labels, identical milestone resolution behavior

## Phase 7 — Commit + PR

- [ ] 7.1 Stage all changes in a SINGLE commit:
  - NEW `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`
  - MODIFIED `apps/web-platform/app/api/inngest/route.ts`
  - MODIFIED `apps/web-platform/infra/sentry/cron-monitors.tf`
  - **[deepen-pass]** MODIFIED `.github/workflows/apply-sentry-infra.yml`
  - DELETED `.github/workflows/scheduled-strategy-review.yml`
  - NEW `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md`
- [ ] 7.2 Verify atomic landing: `git show HEAD --name-status` shows all 6 paths in one commit
- [ ] 7.3 Push branch; open PR with body per plan §PR Body Template; ensure `Closes #4416` in body (NOT title; NOT umbrella #3948)
- [ ] 7.4 Run `/soleur:ship` for the pre-merge gate sequence

## Phase 8 — Post-merge

- [ ] 8.1 Verify `apply-sentry-infra.yml` ran successfully on the merge SHA: `gh run list --workflow=apply-sentry-infra.yml --limit=1 --json status,conclusion`
- [ ] 8.2 **[deepen-pass]** Verify the apply log shows `+ create` for `sentry_cron_monitor.scheduled_strategy_review` (confirms the `-target=` edit took effect)
- [ ] 8.3 Fire manual trigger to confirm function registered: `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` (from Hetzner host)
- [ ] 8.4 Confirm Sentry monitor `scheduled-strategy-review` shows fresh `ok` check-in
- [ ] 8.5 Verify umbrella #3948 body updated: `scheduled-strategy-review` line marked done with PR-6 link
- [ ] 8.6 Confirm issue #4416 closed via PR merge auto-close
- [ ] 8.7 **[deepen-pass — follow-up tracking]** File `chore` tracking issue for the sibling `scheduled_bug_fixer` `-target=` omission discovered during PR-6 deepen-pass (PR-5 left a similar gap; not scope-creep for PR-6 but worth tracking)
