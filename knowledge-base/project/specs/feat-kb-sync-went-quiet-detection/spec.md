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
status: draft
---

# Spec — KB sync went-quiet detection (#4717)

## Problem Statement

KB sync is driven entirely by the GitHub push webhook → `workspace-reconcile-on-push`,
which writes a `kb_sync_history` row only when a push arrives **and** a workspace
matches. The **went-quiet** class is a `repo_status='ready'` **and**
`github_installation_id IS NOT NULL` workspace whose pushes have **stopped
arriving** (broken webhook delivery, disconnected app, etc.). It writes **zero**
new rows, so its latest row stays `ok:true` indefinitely and it looks healthy —
while its KB silently goes stale. The parent incident (#4706) was exactly this
silent-stale failure mode (a user's KB froze ~5 weeks, no error shown).

#4712 shipped two detection arms — NULL-install (`ready ∧ install IS NULL`) and
failure-based (`ready ∧ installed ∧ latest row ok:false`). Neither can see
went-quiet, because went-quiet has a healthy latest row and writes nothing new.
NG3 of #4712 deferred this arm because the naive time-only heuristic risks
firing on idle repos. This spec adds the arm **with** an independent push signal
that suppresses that false positive.

## Goals

- **G1:** Make the `ready ∧ installed ∧ latest-ok:true ∧ no-new-rows` (went-quiet)
  class loud (ops-only) so a silently-frozen KB can't sit unnoticed.
- **G2:** Suppress idle-repo false positives structurally — fire only when the
  repo has had real GitHub push activity since the last successful sync.
- **G3:** Ship as a read-only extension of the existing daily cron — no migration,
  no new Inngest function, no user-facing surface.

## Non-Goals

- **NG1:** No `repo_status` mutation (flipping to `error` degrades the tree —
  strictly worse). Read-only detection only.
- **NG2:** No user-facing surface. Ops-only Sentry, consistent with the
  failure-based arm. (The user-facing reconnect affordance already shipped as
  #4712 item 1.)
- **NG3:** No new Inngest function, no migration, no new UI component. Extend
  `cron-workspace-sync-health.ts` in-place.
- **NG4:** No per-workspace GitHub silence-issue (unbounded cardinality; leaks
  customer workspace identifiers into issue titles).
- **NG5:** No multi-workspace-per-owner support in MVP. Owners with ≥2
  ready+installed workspaces are skipped-and-counted (the `kb_sync_history` row
  has no `workspace_id` discriminator; `sha_after` is unreliable). The correct
  fix is a schema change — deferred to a follow-up issue.

## Functional Requirements

- **FR1:** Extend `cron-workspace-sync-health.ts` with a third `step.run` scan:
  resolve every `repo_status='ready' ∧ github_installation_id IS NOT NULL`
  workspace, join to its owner (`workspace_members` role `owner` → `users.id`),
  and read the owner's `kb_sync_history`.
- **FR2:** Evaluate **only owners with exactly one** ready+installed workspace.
  Skip multi-workspace owners and include a `skippedMultiWorkspace` count in the
  function's return / heartbeat for visibility.
- **FR3:** For each evaluated workspace, derive `lastOkSyncAt` = the timestamp of
  the latest `kb_sync_history` row with `ok === true`. A workspace with no
  `ok:true` row ever is out of scope here (covered by the NULL-install / startup
  paths) — do not fire.
- **FR4:** Mint a GitHub installation token **per distinct
  `github_installation_id`** (dedupe), then call
  `GET /repos/{owner}/{repo}` and read `pushed_at`, where `{owner}/{repo}` is
  **parsed from the workspace's own `repo_url`** (NOT the `_cron-shared`
  `REPO_OWNER`/`REPO_NAME` constants, which point at Soleur's own repo).
- **FR5:** Flag went-quiet when **both** hold:
  `pushed_at > lastOkSyncAt + FRESHNESS_SLACK` **AND**
  `now − lastOkSyncAt > KB_WENT_QUIET_MAX_GAP_DAYS`.
- **FR6:** For each finding, `reportSilentFallback(err, { feature:
  "workspace-sync-health", op: "went-quiet", extra: { workspaceId } })` —
  read-only, workspace UUID only (no repo name/path/owner handle).
- **FR7:** No user-facing output.

## Technical Requirements

- **TR1:** `KB_WENT_QUIET_MAX_GAP_DAYS` defaults to **3** and is env-overridable
  (precedent: `WORKSPACE_RECONCILE_IGNORE_REPOS`). `FRESHNESS_SLACK` is a small
  constant (≥ a few minutes) absorbing reconcile latency.
- **TR2:** All IO (Supabase scan, token mint, `GET /repos`) inside `step.run`
  (ADR-033 I1). Gate the GitHub calls in their **own** `step.run` so a token /
  API failure reports via `reportSilentFallback` and returns empty findings
  **without** poisoning the two existing arms.
- **TR3:** Extend the function's `ScanResult` with a `wentQuiet` findings array
  (ADR-033 I5 deterministic return). Heartbeat `ok` reflects **scan-ran**, not
  findings-present (matches existing arms). Emit no Inngest events (I6).
- **TR4:** Per `cq-silent-fallback-must-mirror-to-sentry`, every silent branch
  (DB scan error, token-mint error, per-repo `GET /repos` error) mirrors to
  Sentry. Register no new function — the cron is already registered in
  `app/api/inngest/route.ts`.
- **TR5:** Tests (RED→GREEN, modeled on `cron-workspace-sync-health.test.ts`):
  - went-quiet fires exactly once for a single-workspace owner where
    `pushed_at > lastOkSyncAt + slack` and `now − lastOkSyncAt > N`;
  - does NOT fire when `pushed_at <= lastOkSyncAt` (idle repo / no push since
    sync) even if `now − lastOkSyncAt > N`;
  - does NOT fire when `now − lastOkSyncAt <= N` even if `pushed_at` is newer;
  - does NOT fire for latest `ok:false` (owned by arm 2) or NULL-install (arm 1);
  - multi-workspace owner is skipped and counted, never fires;
  - GitHub `GET /repos` / token-mint error path reports once and yields no
    went-quiet findings, leaving arms 1 & 2 unaffected.
  - `vitest run` green + `tsc --noEmit` clean in `apps/web-platform`.
- **TR6:** owner/repo parsing reuses the repo-URL normalization already in-tree
  (`@/lib/repo-url`) rather than ad-hoc string slicing.

## Acceptance Criteria

- [ ] `cron-workspace-sync-health` reports each went-quiet single-workspace-owner
  workspace via `reportSilentFallback` (op `went-quiet`, UUID-only); emits
  nothing for idle / fresh / failure-arm / NULL-install / multi-workspace cases.
- [ ] `pushed_at` read from each workspace's own `repo_url`; token minted
  per-installation; both AND-conditions enforced; threshold env-overridable.
- [ ] GitHub-call failures isolated in their own `step.run`; arms 1 & 2 unaffected
  on GitHub-side failure. Read-only — no `repo_status` mutation, no migration, no
  new Inngest function.
- [ ] Tests green per TR5. Follow-up issue filed for `workspace_id`-on-row schema
  change (NG5).

## Domain Review (carry-forward)

- **CTO:** Extend the cron in-place; `GET /repos.pushed_at` parsed from
  `repo_url`; per-installation token mint; single-workspace-owner MVP scope to
  eliminate the no-`workspace_id` mis-attribution class; ops-only Sentry; N=3
  env-overridable. No ADR, no capability gaps, ~hours of work.
- **CPO (carry-forward #4712):** Ops-only; reconnect affordance already shipped.
  Inherits `single-user incident`.
- **CLO (carry-forward #4712):** No statutory clock; `pushed_at` is
  already-authorized repo metadata; UUID-only Sentry logging.

Brainstorm: `knowledge-base/project/brainstorms/2026-06-01-kb-sync-went-quiet-detection-brainstorm.md`
