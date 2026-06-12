# Tasks — Fix: C4 Code-tab Save does not persist (model.c4 reverts after Save)

Plan: `knowledge-base/project/plans/2026-06-12-fix-c4-code-save-not-persisting-plan.md`
Lane: cross-domain
Mandatory fix: **F-A1 (optimistic editor apply) + F-B (honest error, no silent revert)**. F-A2 and F-C are deferred.

## Phase 0 — Confirm failure mode (sizes the F-C deferral; does NOT gate the fix)

- [ ] 0.1 Reproduce against the dev-cohort workspace clone. Capture:
  - `git log origin/<branch>` shows the `.c4` commit landed on origin.
  - `git -C <clone> rev-list --count @{u}..HEAD` and `git -C <clone> status` show why `git pull --ff-only` did not advance the working tree.
  - the `SyncWorkspaceResult` the C4 save returned (`ok:true` no-op vs `SYNC_FAILED`).
- [ ] 0.2 Record the dominant hypothesis (H1 diverged-clone abort / H2 propagation lag / H3 concurrency / H4 wrong upstream) in the PR body. This drives the F-C tracking-issue scope, not the F-A1/F-B implementation.
- [ ] 0.3 Open Code-Review overlap check: `gh issue list --label code-review --state open --json number,title,body --limit 200`, grep bodies for `c4-shared.tsx`, `c4-writer.ts`, `app/api/kb/c4/`. Record fold-in / acknowledge / defer (or `None`).

## Phase 1 — RED (failing tests first)

- [ ] 1.1 `apps/web-platform/test/c4-code-panel.test.tsx`: add a failing test — after a PUT 200, the editor reflects the saved source WITHOUT depending on the on-disk clone having advanced (mock `reload()` to return the OLD source; assert the editor shows the NEW saved text).
- [ ] 1.2 `apps/web-platform/test/c4-code-panel.test.tsx`: add/confirm a test — on a PUT 500 `SYNC_FAILED`, the editor shows the error inline AND retains the user's edited draft (no revert, no `reload()` on failure). (Verify-the-negative confirmed this is already the behavior at `c4-shared.tsx:416/:497-499` — the test pins it against regression from 1.1.)
- [ ] 1.3 (Only if the writer must echo content) `apps/web-platform/test/c4-writer-rerender.test.ts`: assert `writeC4Diagram` returns the written `content` needed for optimistic apply.

## Phase 2 — GREEN (minimal implementation)

- [ ] 2.1 `apps/web-platform/components/kb/c4-shared.tsx`: on a successful PUT (200), keep the client's `draft` (optimistic apply) instead of resetting it from the `reload()`-fetched `data.sources` (F-A1). Confirm the diagram-staleness path still falls through to the existing Layer-1 banner when the clone lags.
- [ ] 2.2 `apps/web-platform/components/kb/c4-shared.tsx`: confirm/preserve the non-2xx error-inline-no-reload behavior at `:416/:497-499` (F-B regression guard).
- [ ] 2.3 (Only if needed for 2.1) `apps/web-platform/server/c4-writer.ts` + `apps/web-platform/app/api/kb/c4/[...path]/route.ts`: return the written `content` to the client. First verify whether the existing `commitSha`/already-sent body suffices before editing the route.
- [ ] 2.4 (Observability) `apps/web-platform/server/c4-writer.ts`: tie a greppable per-save event to the diverged-clone abort (`SYNC_FAILED` / `self-heal-aborted-dirty`) so the failure mode is dashboard-discoverable.

## Phase 3 — Guards & regression

- [ ] 3.1 Assert NO ungated `reset --hard` was added to any save/sync path; the `@{u}..HEAD == 0` gated self-heal is untouched (un-pushed agent-session work preserved).
- [ ] 3.2 `apps/web-platform/test/c4-workspace.test.tsx`: regression on the full workspace save flow (source commits, diagram re-renders on a clean clone).
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-panel.test.tsx test/c4-writer-rerender.test.ts test/c4-workspace.test.tsx` green.

## Phase 4 — Deferrals

- [ ] 4.1 File the **F-C tracking issue**: workspace-wide shared-clone divergence-recovery gap (best-effort `session-sync` push leaves the clone un-fast-forwardable, degrading EVERY sync consumer) + the H3 `rev-list→reset` TOCTOU (route working-tree git ops through `withWorkspacePermissionLock`). Reference `kb-sync-stale-no-manual-recovery-postmortem.md` and a roadmap milestone. Re-eval: any `self-heal-aborted-dirty` recurrence or a second clone-stuck report.

## Phase 5 — Post-merge (operator)

- [ ] 5.1 Live dogfood on the dev-cohort deployment: C4 KB page → Code tab → edit a label in `model.c4` → Save → confirm the edit persists in the editor AND (after re-render) the diagram updates; if `SYNC_FAILED`, confirm the honest error renders. (Automation not feasible — requires the live operator clone's diverged state, which a synthetic CI clone cannot reproduce.)
