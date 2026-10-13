---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4224
pr: 4226
plan: knowledge-base/project/plans/2026-05-21-feat-workspace-reconciliation-with-main-plan.md
spec: knowledge-base/project/specs/feat-workspace-reconciliation-4224/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-21-workspace-reconciliation-brainstorm.md
---

# Tasks: Periodic Workspace Reconciliation with Main (#4224)

## Phase 0: Preconditions (inline kickoff, no separate commit)

- [x] 0.1 Reaffirm CPO sign-off (brainstorm Phase 4 covered; verify operator hasn't reset scope).
- [x] 0.2 Confirm `bun test apps/web-platform/test/server/` baseline is green; capture pre-existing red list to avoid attribution mistakes during the Sentry-mirror sweep.

## Phase 1: Webhook Push Dispatch Branch

- [x] 1.1 RED: write `apps/web-platform/test/server/webhook-push-dispatch.test.ts` covering 9 cases (default-branch push, tag, branch deletion, default-branch creation with before=0, non-default ref, ref-vs-default mismatch, missing `repository.default_branch`, no installation.id, unmapped installation_id → 404 + releaseDedupRow + zero inngest.send).
- [x] 1.2 GREEN: edit `apps/web-platform/app/api/webhooks/github/route.ts` — insert `push` dispatch branch AFTER founder lookup (~line 230) + AFTER workflow_run gate (~line 218), BEFORE `actionClass = HEADER_TO_ACTION_CLASS[githubEvent]` (line 256). On `inngest.send` throw: `releaseDedupRow()` + 500. Inline comment cites ADR-034 + CLO Art. 6(1)(b) + plan path.
- [x] 1.3 REFACTOR: extract `isReconcilablePush(body): { ok, … } | { ok: false, reason }` for testability.
- [x] 1.4 Verify all 9 RED cases pass.

## Phase 2: Inngest Function + Write-Scope + Cross-Tenant Concurrent

- [x] 2.1 RED: write `apps/web-platform/test/server/workspace-reconcile-on-push.test.ts` — happy path, ff-only failure, workspace_not_ready skip, unmapped-defense-in-depth, write-scope (single-tenant), cross-tenant concurrent (two installations).
- [x] 2.2 GREEN: create `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — listens on `platform/workspace.reconcile.requested`, CEL concurrency `{ key: "'wsr-' + event.data.installationId", limit: 1 }`, no throttle. Branches on `workspace_status !== "ready"`. Calls existing `syncWorkspace`.
- [x] 2.3 GREEN: add `appendKbSyncRow(userId, row)` helper next to existing `recordKbSyncHistory` in `apps/web-platform/server/session-sync.ts`. Reuses fetch/update/cap-100 logic. Do NOT widen `recordKbSyncHistory` signature.
- [x] 2.4 Verify all RED cases pass.

## Phase 3: Sentry Mirror Sweep (Inline per Workflow-Gate)

- [x] 3.1 RED: update existing tests (or add new) to assert `reportSilentFallback` IS called at the 4 sites — fix any prior test that asserts silent-fallback (no Sentry call). Per Kieran #5.
- [x] 3.2 GREEN: `apps/web-platform/server/kb-route-helpers.ts:282` — `syncWorkspace` failure path → `reportSilentFallback(syncError, { feature: "kb-route-helpers", op: "workspace-sync-" + context.op, extra: { userId: context.userId, workspacePath }, message: "kb/" + context.op + ": workspace sync failed" })`.
- [x] 3.3 GREEN: `apps/web-platform/server/session-sync.ts:380` (syncPull catch) → `reportSilentFallback(err, { feature: "session-sync", op: "syncPull", extra: { userId, workspacePath }, message: "Sync pull failed — continuing with local state" })`.
- [x] 3.4 GREEN: `apps/web-platform/server/session-sync.ts:451` (recordKbSyncHistory inner catch from syncPush) → `reportSilentFallback(err, { feature: "session-sync", op: "recordKbSyncHistory", extra: { userId, workspacePath }, message: "KB sync history recording failed" })`.
- [x] 3.5 GREEN: `apps/web-platform/server/session-sync.ts:457` (syncPush outer catch) → `reportSilentFallback(err, { feature: "session-sync", op: "syncPush", extra: { userId, workspacePath }, message: "Sync push failed — next session will retry" })`.
- [x] 3.6 Verify `grep -cE 'reportSilentFallback\(' apps/web-platform/server/{kb-route-helpers,session-sync}.ts apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` returns ≥ 5.

## Phase 4: UI — `KbSyncStatus` + `POST /api/kb/sync`

- [x] 4.1 RED: `apps/web-platform/test/server/kb-sync-route.test.ts` — auth, 409 on workspace_status≠ready, manual-trigger row append, server-side workspace_path resolution (request body workspace_path ignored).
- [x] 4.2 GREEN: create `apps/web-platform/app/api/kb/sync/route.ts` — POST, auth-gated, rate-limit 6/min/operator (tune at /work if convention differs), resolves workspace_path from `session.user_id` only, calls `syncWorkspace` directly, appends `{ trigger: "manual" }` row.
- [x] 4.3 RED: `apps/web-platform/test/components/kb-sync-status.test.tsx` — synced state, desync state, in-flight overlay, empty-state renders "Workspace ready", 409 toast.
- [x] 4.4 GREEN: create `apps/web-platform/components/kb/kb-sync-status.tsx` — single component with inline 12-line discriminator for legacy `{date,count}` vs new richer shape.
- [x] 4.5 GREEN: mount `<KbSyncStatus lastSync={lastSync} />` in `apps/web-platform/components/kb/kb-content-header.tsx`.
- [x] 4.6 GREEN: thread `lastSync` from layout-state through `kb-desktop-layout.tsx` and `kb-mobile-layout.tsx` to the header.
- [x] 4.7 GREEN: extend `apps/web-platform/hooks/use-kb-layout-state.ts` (or `kb-context.tsx` per /work grep) to fetch latest `kb_sync_history` row alongside the tree; refetch on Sync-now resolve.
- [x] 4.8 Verify all UI RED tests pass.

## Phase 5: Compliance Docs + Post-merge Wiring

- [x] 5.1 Edit `knowledge-base/legal/article-30-register.md` PA-17 row. Add sub-bullets to (b) Purposes AND (g) TOMs. **Wording MUST distinguish "display-only signal ingestion" (existing PA-17 scope) vs "workspace clone reconciliation — filesystem write side-effect" (new sub-bullet)** per Kieran #10. Update `last_updated:` to today.
- [x] 5.2 Edit `docs/legal/data-protection-disclosure.md` §2.3(r). Append one sentence: "Workspace synchronization runs outside the operator's session on receipt of a GitHub `push` webhook." Update `last_updated:` to today.
- [x] 5.3 PR body draft: include `Closes #4224` AND `Ref #4228`.
- [x] 5.4 Confirm `push_received_at` + `sync_completed_at` Unix-ms fields populated in all webhook-push `kb_sync_history` rows for 30-day drift analysis (TR4).

## Phase 6: Post-merge (operator) — Automated via `/soleur:ship` where feasible

- [ ] 6.1 (auto) Push smoke-test commit to operator's connected repo; via `mcp__plugin_supabase_supabase__execute_sql`: `SELECT kb_sync_history->-1 FROM public.users WHERE id = '<id>'` — verify row appears within 30s.
- [ ] 6.2 (auto) Query Sentry residency endpoint for 24h post-deploy window; verify zero `feature:"workspace-reconcile-push"` events at severity `error`.
- [ ] 6.3 (auto via gh CLI) `gh issue close 4224` after 6.1 + 6.2 pass.
- [ ] 6.4 (subjective, deferable) Visual check of `KbSyncStatus` on `app.soleur.ai/dashboard/kb` after a real KB-mutation merge. Automatable partially via Playwright snapshot at `/soleur:ship`; defer to follow-up if not in scope.

## Phase 7: Verification + Wrap-up

- [x] 7.1 Run `bun test apps/web-platform/test/` — all green; verify AC7 conditions.
- [x] 7.2 Run `/soleur:preflight` to check the User-Brand Impact section presence + threshold validity (preflight Check 6).
- [ ] 7.3 Mark PR #4226 ready for review.
- [ ] 7.4 Resolve any plan-review-style PR comments inline.
- [ ] 7.5 `/soleur:ship` to merge + run AC9–AC11.
