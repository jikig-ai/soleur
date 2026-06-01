---
feature: feat-kb-sync-went-quiet-detection
issue: 4717
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-01-feat-kb-sync-went-quiet-detection-plan.md
status: ready
---

# Tasks — KB sync went-quiet detection (#4717)

Derived from the finalized (post-plan-review v2) plan. Design is **users-centric**
(mirrors arm 2); GitHub signal is the **default-branch HEAD commit date**.

## 1. GitHub helper (Phase 1)

- [ ] 1.1 Add exported `getDefaultBranchHeadCommitAt(installationId, owner, repo)` to `apps/web-platform/server/github-app.ts`, sibling to `checkRepoAccess`.
  - [ ] 1.1.1 Token via `generateInstallationToken(installationId)`.
  - [ ] 1.1.2 `githubFetch(\`${GITHUB_API}/repos/${owner}/${repo}/commits?per_page=1\`, { headers: { Authorization: \`token ${token}\` } })` (no `sha` → default branch).
  - [ ] 1.1.3 Return `Date.parse(body[0].commit.committer.date)` (epoch ms); `null` when the array is empty (brand-new repo); **throw** on non-200 / network / token failure.

## 2. RED tests (Phase 2)

- [ ] 2.1 In `apps/web-platform/test/server/inngest/cron-workspace-sync-health.test.ts`, extend the existing `users` mock rows to carry `repo_url` + `github_installation_id`.
- [ ] 2.2 `vi.mock("@/server/github-app")` and stub `getDefaultBranchHeadCommitAt` per-scenario (number / null / throws).
- [ ] 2.3 Write the 10 TR5 scenarios (table in the plan) as failing tests; confirm they fail because op `went-quiet` never fires.

## 3. Arm-3 scan step (Phase 3)

- [ ] 3.1 Add `step.run("scan-went-quiet")` AFTER the arm-2 step, BEFORE the heartbeat step in `cron-workspace-sync-health.ts`. Wrap the whole body in try/catch so it never throws.
- [ ] 3.2 Query `users`: `.select("id, repo_url, github_installation_id, kb_sync_history").eq("repo_status","ready").not("github_installation_id","is",null)`. On DB error → `reportSilentFallback(op:"scan-went-quiet")`, return.
- [ ] 3.3 Per user: `latest = kb_sync_history.at(-1)`; require `"ok" in latest && latest.ok === true`; `lastOkSyncAt = Date.parse(latest.at)` (skip on NaN); skip if `now − lastOkSyncAt <= N days`.
- [ ] 3.4 Parse `owner/repo` from `user.repo_url` (mirror `workspace-reconcile-on-push.ts:92` `repoSlug` + split; skip if malformed).
- [ ] 3.5 `try { headCommitAt = await getDefaultBranchHeadCommitAt(...) }` → on throw `reportSilentFallback(op:"went-quiet-probe", extra:{userId})` + continue; `null` → skip.
- [ ] 3.6 Fire when `headCommitAt > lastOkSyncAt + FRESHNESS_SLACK_MS` AND `now − lastOkSyncAt > N days` → `reportSilentFallback(new Error("...went quiet..."), {feature:"workspace-sync-health", op:"went-quiet", extra:{userId}})`. userId only.
- [ ] 3.7 `logger.info({ fn, wentQuiet: count }, ...)`. No `ScanResult`/return widening.

## 4. Constants + env (Phase 4)

- [ ] 4.1 `const FRESHNESS_SLACK_MS = 5 * 60 * 1000;` with the cross-clock comment.
- [ ] 4.2 `const n = Number(process.env.KB_WENT_QUIET_MAX_GAP_DAYS); const KB_WENT_QUIET_MAX_GAP_DAYS = Number.isFinite(n) && n > 0 ? n : 3;`
- [ ] 4.3 Add `# KB_WENT_QUIET_MAX_GAP_DAYS=3` near line 176 of `apps/web-platform/.env.example`.

## 5. GREEN + verify (Phase 5)

- [ ] 5.1 `./node_modules/.bin/vitest run test/server/inngest/cron-workspace-sync-health.test.ts` green.
- [ ] 5.2 `tsc --noEmit` clean in `apps/web-platform`.
- [ ] 5.3 Confirm heartbeat still posts under arm-3 throw (scenario 8/9); arms 1 & 2 unaffected.

## 6. Ship prep

- [ ] 6.1 PR body uses `Closes #4717`; note #4728 remains open (per-workspace future work).
- [ ] 6.2 Run review + QA per lifecycle before marking ready.
