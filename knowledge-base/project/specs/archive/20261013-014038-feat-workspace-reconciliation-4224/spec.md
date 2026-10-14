---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4224
pr: 4226
branch: feat-workspace-reconciliation-4224
brainstorm: knowledge-base/project/brainstorms/2026-05-21-workspace-reconciliation-brainstorm.md
domain_leaders: [cpo, clo, cto]
---

# Spec: Periodic Workspace Reconciliation with Main

**Issue:** #4224
**Branch:** feat-workspace-reconciliation-4224
**PR:** #4226 (draft)
**Brainstorm:** [2026-05-21-workspace-reconciliation-brainstorm.md](../../brainstorms/2026-05-21-workspace-reconciliation-brainstorm.md)

## Problem Statement

The webapp KB viewer at `app.soleur.ai/dashboard/kb` reads from per-operator server-side workspace clones at `userData.workspace_path/knowledge-base/`. Workspaces only sync on session-boundary (`syncPull`/`syncPush`) and KB-mutation (`syncWorkspace` after delete/rename/upload). No background reconciliation exists, so workspaces drift hours/days behind the operator's connected default branch with no UI signal of staleness. Concrete repro: PR #4215 merged removing a regressed `knowledge-base/design/` folder; the webapp continued rendering the stale folder ~25 min later. The operator may act on stale source-of-truth (trust breach) — e.g., reference a deleted policy file the viewer still shows.

## Goals

- G1: Operator's workspace reflects merges to their connected default branch within webhook delivery latency (seconds) without requiring session start or KB mutation.
- G2: KB viewer header surfaces a freshness signal ("Synced N ago" badge) + manual "Sync now" affordance so the operator never has to guess whether the view is current.
- G3: All silent failure paths in `syncWorkspace` callers (existing two + new third) Sentry-mirror per `cq-silent-fallback-must-mirror-to-sentry`.
- G4: Background reconciliation writes per-event audit rows that support a 30-day drift analysis enabling the deferred-cron-backstop (#TBD) exit criterion.
- G5: No cross-tenant credential or data path introduced — `installation_id → user_id → workspace_path` boundary asserted under test.

## Non-Goals

- NG1: Cron backstop (Approach B). Deferred behind 30-day webhook-delivery telemetry; filed as deferred-scope-out issue.
- NG2: Lazy sync on `/api/kb/tree` (Approach C). Rejected — couples sync to read path, degrades p99.
- NG3: Auto-recovery from non-fast-forward state. `git pull --ff-only` failure surfaces an operator-visible "workspace out of sync — reconnect" affordance, never silent reset or rebase.
- NG4: New consent surface ("background sync" toggle). Covered by existing operator-data agreement under Art. 6(1)(b); a toggle would misrepresent the existing PA-2/PA-17 contract framing.
- NG5: New audit table. Reuses `audit_github_token_use` (migration 052, WORM + Art. 17 cascade) with a `sync_source` discriminator.
- NG6: New `kb_sync_history` columns per trigger. Unified JSONB array with a `trigger` field per row.
- NG7: Changes to `syncPull` / `syncPush` semantics in `session-sync.ts`. This PR adds a third trigger that calls the same `syncWorkspace` helper; it does not modify existing trigger behavior.

## Functional Requirements

- FR1: Extend `GITHUB_EVENT_STRATEGIES` in `apps/web-platform/server/inngest/functions/github-event-strategies.ts` with a `push` action class that routes to a workspace-reconcile handler in `github-on-event.ts`.
- FR2: The webhook ingress at `apps/web-platform/app/api/webhooks/github/route.ts` accepts `push` events, runs the existing signature/dedup pipeline, resolves the founder by `installation.id → users.github_installation_id`, and dispatches an Inngest event.
- FR3: The Inngest handler filters on `ref === "refs/heads/<repository.default_branch>"` (read from the webhook payload; do NOT hardcode `main`). Non-default-branch pushes are dropped with a debug log.
- FR4: The handler calls `syncWorkspace(installationId, workspacePath, log, ctx)` with `ctx.sync_source = "webhook_push"`.
- FR5: Append a row to `users.kb_sync_history` JSONB with shape `{ at, trigger: "webhook_push", sha_before, sha_after, ok, error_class }`; cap array at last 100 entries (consistent with existing `recordKbSyncHistory`).
- FR6: KB viewer header renders a "Synced N ago" badge derived from the most-recent `kb_sync_history` row's `at` field, plus a manual "Sync now" button that triggers a one-shot `syncWorkspace` from the existing session-sync helper (no new endpoint required if existing endpoint suffices).
- FR7: When `git pull --ff-only` fails (non-ff state), the UI surfaces a "workspace out of sync — reconnect" affordance derived from a `workspace_desync` event written to `kb_sync_history`.
- FR8: Append a row to `audit_github_token_use` for every webhook-triggered reconciliation with `sync_source = "webhook_push"`, reusing the existing WORM + Art. 17 cascade.

## Technical Requirements

- TR1: Per-`installation_id` in-process mutex coalesces concurrent pulls. If a sync is in flight, await the in-flight promise and short-circuit (pulls are idempotent; latest is latest).
- TR2: Sentry-mirror sweep across ALL THREE `syncWorkspace` callers (session-sync, kb-mutation, new webhook-push), tagging events with `{ installation_id, sync_trigger, branch }`. Apply inline — do NOT scope to only the new caller.
- TR3: `assertWriteScope`-equivalent test asserting that `installation_id → user_id → workspace_path` is install-scoped and fails closed on any ambiguous mapping. This is the load-bearing TOM under GDPR Art. 32.
- TR4: Telemetry rows in `kb_sync_history` MUST include `push_received_at` and `sync_completed_at` Unix timestamps to support the 30-day drift analysis cited as the cron-backstop exit criterion (NG1).
- TR5: Default-branch value is read from `webhook_body.repository.default_branch` at request time. Caching of this value is out of scope.
- TR6: `cron-*.ts` naming convention does NOT apply (no cron added in this PR per NG1).
- TR7: No new database tables. All audit and telemetry flow through existing `kb_sync_history` JSONB and `audit_github_token_use` table.
- TR8: ADR not required. Adding a third sync trigger does not change architecture; the substrate (webhook strategy table, Inngest fan-out, `syncWorkspace`) is in place.

## Compliance Requirements

- CR1: Article 30 register PA-17 cell amendment at PR-merge time: add a sub-bullet noting GitHub `push` webhook events trigger `git pull --ff-only` against the founder's workspace clone (sub-processor recipient unchanged: GitHub Inc.; existing DPA covers).
- CR2: DPD §2.3(r) sentence amendment at PR-merge time: clarify that workspace synchronization runs outside the operator's session on receipt of a GitHub `push` webhook.
- CR3: No new consent surface. No new explicit-consent UI.
- CR4: Lawful basis under Art. 6(1)(b) (necessary to perform the contract of "workspace stays in sync with your repo"). No legitimate-interest balancing test required for Approach A.

## Acceptance Criteria

- [ ] AC1: Pushing a commit to an operator's connected default branch causes their workspace clone to reflect the change within 60 seconds (allowing for webhook delivery latency + Inngest fan-out) without operator-side action.
- [ ] AC2: A `kb_sync_history` JSONB row is appended for every webhook-triggered reconciliation with `trigger: "webhook_push"`, `push_received_at`, `sync_completed_at`, and `ok` populated.
- [ ] AC3: A failed `git pull --ff-only` (force-push / non-ff state) does NOT silently auto-reset. Sentry receives a `captureException` tagged `sync_trigger=webhook_push`; UI surfaces a "workspace out of sync — reconnect" affordance.
- [ ] AC4: Existing two `syncWorkspace` callers (session-sync, kb-mutation) Sentry-mirror their failures after this PR (regression test against pre-PR silent-fallback baseline).
- [ ] AC5: KB viewer header renders "Synced N ago" badge for any operator with a non-empty `kb_sync_history`. Manual "Sync now" button triggers a single `syncWorkspace` call and refreshes the badge on completion.
- [ ] AC6: Concurrent webhook deliveries for the same `installation_id` do not produce `git index.lock` errors. Mutex test asserts that two simultaneous reconcile invocations for the same installation result in exactly one `git pull` invocation.
- [ ] AC7: `assertWriteScope`-equivalent test passes — a webhook payload with `installation.id` not mapping to a user in `users.github_installation_id` produces a 404 (existing behavior) AND does NOT touch any workspace_path.
- [ ] AC8: Article 30 PA-17 cell amendment + DPD §2.3(r) sentence land in the same PR as the code change.
- [ ] AC9: Deferred-scope-out issue filed for cron backstop (Approach B) gated on 30-day webhook-delivery telemetry showing >0.1% drift.

## Out of Scope (Deferred)

- DS1: Cron backstop (Approach B) — file as deferred-scope-out issue; gate on 30-day telemetry from this PR.
- DS2: Debounce window for rapid pushes (merge queue, batched commits) — relying on `--ff-only` idempotency + mutex. Revisit if observed pull-duplication exceeds 5% in telemetry.
- DS3: `webhook_delivery_metrics` separate table — plan-time decision whether `kb_sync_history` is adequate for drift analysis.

## Key References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-21-workspace-reconciliation-brainstorm.md`
- Issue: #4224
- Draft PR: #4226
- AGENTS.md rules: `cq-silent-fallback-must-mirror-to-sentry`, `hr-weigh-every-decision-against-target-user-impact`
- Article 30 register row: PA-17 (GitHub-sourced priority signals)
- Substrate: `apps/web-platform/app/api/webhooks/github/route.ts`, `apps/web-platform/server/inngest/functions/github-on-event.ts`, `apps/web-platform/server/kb-route-helpers.ts:282`, `apps/web-platform/server/session-sync.ts:266,326,389`
- Audit ledger: migration 052 (`audit_github_token_use`)
