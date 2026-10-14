---
title: "Tasks — fix(kb): manual sync affordance + reconcile self-heal"
branch: feat-one-shot-kb-sync-affordance-reconcile
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-03-fix-kb-sync-affordance-and-reconcile-self-heal-plan.md
---

# Tasks

Derived from `2026-06-03-fix-kb-sync-affordance-and-reconcile-self-heal-plan.md` (deepened).
Wireframe (committed): `knowledge-base/product/design/kb-viewer/kb-viewer-wireframes.pen`.

## Phase 0 — Root-cause trace (read-only, gates Fix B shape)

- [ ] 0.1 Sentry: search `kb-route-helpers` + `WORKSPACE_RECONCILE_SENTRY_FEATURE` for
  `op:sync` / "workspace sync failed" around 2026-06-02 21:10 UTC for the Owner's
  installation. Capture the git stderr (non_fast_forward vs auth/IO/timeout).
- [ ] 0.2 Inngest run history for `workspace-reconcile-on-push`: did it fire for PR #4846's
  push delivery? Did it reach `reconcile-<ws.id>`? Outcome?
- [ ] 0.3 Decision gate: divergence → self-heal LOAD-BEARING (build 2.3); auth/IO →
  classification-only + tracked follow-up; reconcile-never-fired → THIRD root cause, file +
  re-scope. Append `## Phase 0 Findings` to the plan before proceeding.

## Phase 1 — Fix A: manual sync affordance in the rail (TDD)

- [ ] 1.1 RED: add tests (extend `test/kb-sync-status.test.tsx` or new
  `test/kb-sidebar-shell.test.tsx`, jsdom glob `test/**/*.test.tsx`) — "Sync now" renders in
  (a) populated tree, (b) empty tree, (c) `ok:false` desync row; successful POST invokes
  context `refreshTree`. (AC-A1..A4, A6)
- [ ] 1.2 GREEN: mount `<KbSyncStatus lastSync onSynced={refreshTree} onError={…} />` from
  `useKb()` in `components/kb/kb-sidebar-shell.tsx`, visible in BOTH the `FileTree` and
  `RailEmptyState` branches (rail footer region, matching the committed wireframe).
- [ ] 1.3 Decide + record: does `DesktopPlaceholder` also need the affordance? (rail mount
  likely covers it — 1-line rationale). (AC-A5)
- [ ] 1.4 Verify existing `kb-sync-status.test.tsx` discriminator cases still green.

## Phase 2 — Fix B: classify + self-heal in `syncWorkspace` (TDD; contract before consumer)

- [ ] 2.1 RED+GREEN classify (CONTRACT): add a git-error classifier → `KbSyncErrorClass`
  (`non_fast_forward` vs `sync_failed`). **Verify the exact non-fast-forward stderr against
  the installed git** (run `git pull --ff-only` on a diverged fixture clone; capture
  "Not possible to fast-forward"). Widen `syncWorkspace` return to
  `{ok:true; recovered?:boolean} | {ok:false; error; errorClass:KbSyncErrorClass}`. (AC-B1,B7)
- [ ] 2.2 GREEN consumer: write `syncResult.errorClass` (not hard-coded) at
  `app/api/kb/sync/route.ts:130-145` (remove stale comment) AND
  `server/inngest/functions/workspace-reconcile-on-push.ts:304-316`. (AC-B2)
- [ ] 2.3 Self-heal (only if Phase 0 confirms divergence): on `non_fast_forward` →
  `git fetch origin <default>`; `git rev-list --count @{u}..HEAD` (reuse
  `session-sync.ts:200-208` shape). count==0 → `git reset --hard origin/<default>` →
  `{ok:true, recovered:true}`. count>0 → NO reset → `{ok:false, errorClass:"non_fast_forward"}`
  + fail_loud (never destroy un-pushed agent-session work). Default branch via
  `git symbolic-ref --short refs/remotes/origin/HEAD` (NOT literal `main`). (AC-B3,B5,B6)
- [ ] 2.4 Observability: self-heal SUCCESS → Sentry breadcrumb `op:self-heal-reset` +
  `kb_sync_history` recovered row; FAILURE → `reportSilentFallback` `op:self-heal-failed`
  (fail_loud) + `ok:false`. Omit `workspacePath` (raw userId) from all new Sentry payloads. (AC-B4)
- [ ] 2.5 Caller sweep: update the FOUR `syncWorkspace` callers — `kb/sync/route.ts:116`,
  `workspace-reconcile-on-push.ts:289`, `kb/file/[...path]/route.ts:66`+`:308` — for the
  widened return. `tsc --noEmit` clean. (AC-B8)
- [ ] 2.6 Sibling surface: route `kb/upload/route.ts:234` inline `pull --ff-only` through
  hardened `syncWorkspace` (folds in #2244 → `Closes #2244`) OR scope out with a tracked
  follow-up. (AC-B9)
- [ ] 2.7 Tests (`test/kb-route-helpers.test.ts`, `test/server/kb-sync-route.test.ts`,
  `test/server/inngest/workspace-reconcile-on-push.test.ts`): drive `syncWorkspace` DIRECTLY
  with mocked `gitWithInstallationAuth` (`mockGitWithAuth`). Cases: non-FF+0-commits→reset+
  recovered; non-FF+N-commits→no-reset+ok:false; auth-err→sync_failed+no-reset; clean→no-reset.

## Phase 3 — Restore service + verify (post-merge, automated; NO SSH)

- [ ] 3.1 Trigger re-sync for the Owner's workspace via `/soleur:trigger-cron` (allowlisted
  reconcile event) or `/api/kb/sync` on their behalf. (AC-P1)
- [ ] 3.2 Verify the PIR renders: Playwright MCP on `/dashboard/kb/...` OR `/api/kb/tree`
  read asserting the PIR path present. (AC-P1)
- [ ] 3.3 Post-deploy: confirm a real `non_fast_forward` records the correct `error_class`
  via Sentry/observability (not a dashboard eyeball). (AC-P2)

## Ship gates

- [ ] tsc --noEmit clean (web-platform); vitest run for all edited test files (NOT bun).
- [ ] PR body: `Ref` the incident; `Closes #2244` only if folded (Phase 2.6).
- [ ] CPO sign-off recorded (single-user-incident threshold) before merge.
