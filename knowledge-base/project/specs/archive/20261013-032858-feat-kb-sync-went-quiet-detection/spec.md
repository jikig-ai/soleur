---
title: "KB sync went-quiet detection (time-based / push-correlation stale arm)"
feature: feat-kb-sync-went-quiet-detection
issue: 4717
parent_issue: 4706
predecessor_issue: 4712
branch: feat-kb-sync-went-quiet-detection
pr: 4726
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-06-01
revised: 2026-06-01 (plan-review pivot — users-centric, default-branch commit signal)
status: draft
---

# Spec — KB sync went-quiet detection (#4717)

## Problem Statement

KB sync is driven by the GitHub push webhook → `workspace-reconcile-on-push`,
which writes a `kb_sync_history` row only when a default-branch push arrives. The
**went-quiet** class is a `repo_status='ready'` **and** `github_installation_id IS
NOT NULL` user whose pushes have **stopped arriving** (broken webhook delivery,
disconnected app, etc.). It writes **zero** new rows, so its latest row stays
`ok:true` indefinitely and the connection looks healthy — while its KB silently
goes stale. The parent incident (#4706) was exactly this silent-stale mode (a
KB froze ~5 weeks, no error shown).

#4712 shipped two arms — NULL-install (`ready ∧ install IS NULL`) and
failure-based (`ready ∧ installed ∧ latest row ok:false`). Neither sees
went-quiet (healthy latest row, nothing new written). NG3 of #4712 deferred this
arm because the naive time-only heuristic risks firing on idle repos. This spec
adds the arm **with** an independent default-branch-activity signal that
suppresses that false positive.

> **Design note (plan-review correction):** the v1 brainstorm/spec framing was
> workspace-centric (scan `workspaces`, join `workspace_members`, single-workspace
> owners only). Plan-review found `users` already carries `repo_url` +
> `github_installation_id` + `kb_sync_history` on one row (mig 011) and that arm 2
> already scans `users`. v2 mirrors arm 2 (users-centric) — genuine mutual
> exclusivity, no join, no scope cut. See the plan's Plan-Review Resolutions table.

## Goals

- **G1:** Make the `ready ∧ installed ∧ latest-ok:true ∧ no-new-rows` (went-quiet)
  class loud (ops-only) so a silently-frozen KB can't sit unnoticed.
- **G2:** Suppress idle-repo false positives structurally — fire only when the
  **default branch** has had real commit activity since the last successful sync.
- **G3:** Ship as a read-only extension of the existing daily cron — no migration,
  no new function, no UI, no new dependency.

## Non-Goals

- **NG1:** No `repo_status` mutation. Read-only detection only.
- **NG2:** No user-facing surface. Ops-only Sentry (the #4712 item-1 reconnect
  affordance already covers in-product remediation).
- **NG3:** No new Inngest function, no migration, no new UI component, no new npm
  dependency. Extend `cron-workspace-sync-health.ts` in-place; reuse the
  `githubFetch` GitHub-API pattern.
- **NG4:** No per-user GitHub silence-issue (unbounded cardinality; leaks user
  identifiers into issue titles). Ops-only Sentry.
- **NG5:** No per-**workspace** granularity. Detection is per-user (the user's
  connected repo on `users.repo_url`, matching arm 2 and the reconcile's per-owner
  `kb_sync_history` attribution). True per-workspace went-quiet (one user, multiple
  workspaces/repos) needs a `workspace_id` on each `kb_sync_history` row — tracked
  by #4728 as orthogonal future work.

## Functional Requirements

- **FR1:** Add a third `step.run("scan-went-quiet")` to
  `cron-workspace-sync-health.ts`, AFTER the arm-2 step and BEFORE the heartbeat.
  Query `users`: `select id, repo_url, github_installation_id, kb_sync_history`
  where `repo_status='ready'` and `github_installation_id IS NOT NULL` (the same
  WHERE clause as arm 2; a separate query, matching the existing arm-1/arm-2
  structure).
- **FR2:** For each user, derive `lastOkSyncAt` from the **latest** row only:
  `latest = kb_sync_history.at(-1)`; require `"ok" in latest && latest.ok === true`
  (excludes legacy `{date,count}` and arm-2's `ok:false`). `lastOkSyncAt =
  Date.parse(latest.at)`. Skip if `now − lastOkSyncAt <= KB_WENT_QUIET_MAX_GAP_DAYS`.
- **FR3:** Add an exported `github-app.ts` helper
  `getDefaultBranchHeadCommitAt(installationId, owner, repo)` (mirroring
  `checkRepoAccess`): token via `generateInstallationToken`; `githubFetch(GET
  /repos/{owner}/{repo}/commits?per_page=1)` (defaults to the default branch);
  return `[0].commit.committer.date` as epoch ms, `null` for an empty repo, and
  **throw** on token/network/non-200.
- **FR4:** Parse `owner/repo` from `user.repo_url` (mirror
  `workspace-reconcile-on-push.ts` `repoSlug` + split) — NOT the `_cron-shared`
  `REPO_OWNER/REPO_NAME` constants (Soleur's own repo).
- **FR5:** Fire went-quiet when **both** hold:
  `headCommitAt > lastOkSyncAt + FRESHNESS_SLACK_MS` **AND**
  `now − lastOkSyncAt > KB_WENT_QUIET_MAX_GAP_DAYS`.
- **FR6:** For each finding, `reportSilentFallback(err, { feature:
  "workspace-sync-health", op: "went-quiet", extra: { userId } })` — read-only,
  hashed-userId only (no repo name/path/owner handle).
- **FR7:** No user-facing output. No `ScanResult`/return widening (report in-place
  like arm 2). The arm-3 step body is fully try/caught so it never throws — the
  heartbeat always posts.

## Technical Requirements

- **TR1:** `KB_WENT_QUIET_MAX_GAP_DAYS` defaults to **3**, env-overridable, guarded
  `Number.isFinite(n) && n > 0 ? n : 3` (a blank/`0` env var must not yield a
  0-day firehose). `FRESHNESS_SLACK_MS = 5 * 60 * 1000` (cross-clock guard between
  GitHub `committer.date` and our `lastOkSyncAt`).
- **TR2:** Scan source is `users` (carries `repo_url`/`github_installation_id`/
  `repo_status`/`kb_sync_history` on one row per mig 011; not dropped by 079 UP).
  Mutual exclusivity with arm 2 is by construction: same row, `at(-1).ok` opposite
  polarity.
- **TR3:** All IO (Supabase scan, token mint, GitHub fetch) inside `step.run`
  (ADR-033 I1). Per `cq-silent-fallback-must-mirror-to-sentry`, every silent branch
  (DB error op `scan-went-quiet`, per-user probe error op `went-quiet-probe`)
  mirrors to Sentry. Register no new function. Heartbeat `ok` stays `scan.ok`
  (arm-1 result; arm-3 DB error does not flip it — matching arm 2).
- **TR4:** No `@octokit/core` or any new npm dependency — reuse `githubFetch`.
- **TR5:** Tests (RED→GREEN, modeled on `cron-workspace-sync-health.test.ts`):
  fires once for stale+pushed; no-fire for idle (`headCommitAt <= lastOk`), fresh
  (`gap <= N`), latest `ok:false` (arm 2), NULL-install, empty-repo
  (`getDefaultBranchHeadCommitAt` → null), empty/legacy history, and the `gap == N`
  boundary; probe error reports `went-quiet-probe` and continues; DB error reports
  `scan-went-quiet`; any arm-3 throw still lets the heartbeat post. `vitest run`
  green + `tsc --noEmit` clean in `apps/web-platform`.
- **TR6:** owner/repo parsing reuses the in-tree `repoSlug` shape; no ad-hoc
  parsing.

## Acceptance Criteria

- [ ] `cron-workspace-sync-health` reports each went-quiet ready+installed user via
  `reportSilentFallback` (op `went-quiet`, hashed-userId); emits nothing for
  idle/fresh/failure-arm/NULL-install/empty-repo/legacy cases.
- [ ] Default-branch HEAD commit read via `getDefaultBranchHeadCommitAt`; owner/repo
  from `user.repo_url`; both AND-conditions enforced; threshold guarded `> 0`.
- [ ] Failure-isolated: DB error (op `scan-went-quiet`), per-user probe error (op
  `went-quiet-probe`), and any arm-3 throw all leave the heartbeat posting and arms
  1 & 2 unaffected. Read-only — no `repo_status` mutation, no migration, no new
  function, no new dependency.
- [ ] Tests green per TR5. `# KB_WENT_QUIET_MAX_GAP_DAYS=3` in `.env.example`.

## Domain Review (carry-forward)

- **CTO:** Extend the cron in-place; default-branch HEAD-commit correlation via a
  `github-app.ts` helper; scan `users` (mirrors arm 2 → genuine mutual exclusion);
  ops-only Sentry; N=3 env-overridable; arm-3 step never throws.
- **CPO (carry-forward #4712):** Ops-only; reconnect affordance already shipped.
  Inherits `single-user incident`.
- **CLO (carry-forward #4712):** No statutory clock; default-branch commit date is
  already-authorized metadata; hashed-userId Sentry logging.

Plan: `knowledge-base/project/plans/2026-06-01-feat-kb-sync-went-quiet-detection-plan.md`
Brainstorm: `knowledge-base/project/brainstorms/2026-06-01-kb-sync-went-quiet-detection-brainstorm.md`
