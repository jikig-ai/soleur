---
feature: feat-one-shot-4728-kb-sync-workspace-id
issue: 4728
lane: single-domain
plan: knowledge-base/project/plans/2026-06-01-feat-kb-sync-workspace-id-discriminator-plan.md
---

# Tasks — feat(kb-sync): add `workspace_id` discriminator to `kb_sync_history` rows

Derived from the finalized plan. Additive optional JSONB field; no migration.

## 1. Setup / Preconditions

- [ ] 1.1 Re-run the Open Code-Review Overlap check against the final file list
      (`gh issue list --label code-review --state open` → grep edited paths). Expected: none.
- [ ] 1.2 Confirm baselines: `grep -c 'appendKbSyncRow(ownerId' …workspace-reconcile-on-push.ts` = 3;
      `grep -c 'workspace_id' …app/api/kb/sync/route.ts` = 0.

## 2. Core Implementation

- [ ] 2.1 **(Phase 1 — contract first)** Add optional `workspace_id?: string` to `KbSyncRow`
      in `apps/web-platform/server/session-sync.ts` (after `sync_completed_at`, with the
      #4728 comment). → AC1.
- [ ] 2.2 **(Phase 2)** Add `workspace_id: ws.id` to all 3 `appendKbSyncRow(ownerId, {…})`
      object literals in `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
      (skip-not-ready, sync-failed, ok:true). → AC2 (`grep -c 'workspace_id: ws.id'` = 3).
- [ ] 2.3 **(Phase 3 — no-op)** Leave `apps/web-platform/app/api/kb/sync/route.ts` unchanged;
      optionally add a one-line comment that `workspace_id` is intentionally omitted
      (users-centric route, no ws id in scope). Do NOT add a `workspace_members` lookup.
      → AC3 (`grep -c 'workspace_id'` stays 0).

## 3. Testing

- [ ] 3.1 **(Phase 4)** Extend `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts`:
      assert `appendKbSyncRowSpy` called with `expect.objectContaining({ workspace_id: <wsId> })`
      on the ok:true path AND at least one failure path, using the existing fixture's ws id. → AC4.
- [ ] 3.2 Run targeted suite: `cd apps/web-platform && ./node_modules/.bin/vitest run
      test/server/inngest/workspace-reconcile-on-push.test.ts test/server/kb-sync-route.test.ts`
      → AC6. Confirm route test still green (partial matcher unaffected). → AC5.
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → AC5 (all readers compile
      against widened-but-optional type).

## 4. Close-out

- [ ] 4.1 File the deferral tracking issue for the per-workspace went-quiet **reader** (NG1)
      with re-eval criterion "≥1 owner has ≥2 ready+installed workspaces". Milestone per
      `knowledge-base/product/roadmap.md`.
- [ ] 4.2 PR body: `Closes #4728`. (This PR fully resolves #4728; the reader is a new deferral,
      not a re-open.)
