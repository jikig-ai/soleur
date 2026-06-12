# Tasks — Fix: C4 Code-tab Save does not persist (model.c4 reverts after Save)

Plan: `knowledge-base/project/plans/2026-06-12-fix-c4-code-save-not-persisting-plan.md`
Lane: cross-domain
Mandatory fix: **F-A1 (optimistic editor apply) + F-B (honest error, no silent revert)**. F-A2 and F-C are deferred.

## Phase 0 — Confirm failure mode (sizes the F-C deferral; does NOT gate the fix)

- [x] 0.1 Live-clone repro deferred to the post-merge dogfood (5.1) — a synthetic CI clone cannot reproduce a perpetually-diverged prod clone. Code-trace confirms the mechanism: GET `/project` reads `data.sources` from the on-disk clone; the `[data, activeFile]` effect (`c4-shared.tsx:396-398`) re-seeds `draft` from it, so a stale clone reverts the editor. F-A1/F-B are correct for all hypotheses regardless.
- [x] 0.2 Dominant hypothesis recorded in PR body: **H1 (diverged clone → self-heal aborts on un-pushed commits)** as PRIME for the deterministic "every save reverts" symptom; **H2 (Contents-API→fetch replica lag)** for the intermittent case. Both cured identically by F-A1 (the editor stops depending on the clone advancing). Drives the F-C tracking-issue scope.
- [x] 0.3 Open Code-Review overlap check run: `gh issue list --label code-review --state open` grep for `c4-shared.tsx` / `c4-writer.ts` / `app/api/kb/c4/` → **None**.

## Phase 1 — RED (failing tests first)

- [x] 1.1 `c4-code-panel.test.tsx` F-A1 test added — after a 200, a stale reload() (new object, OLD source) must not revert the editor. RED confirmed: received `user = element`, expected `user = element TEST`.
- [x] 1.2 `c4-code-panel.test.tsx` F-B test added — on a 500 `SYNC_FAILED` the editor shows the error AND retains the edited draft, and `onSaved` (the reload trigger) is never called. Passed at RED (already-shipped behavior); pins it against the F-A1 change.
- [x] 1.3 N/A — F-A1 reuses the client's own `draft` (no server echo needed). Writer/route untouched.

## Phase 2 — GREEN (minimal implementation)

- [x] 2.1 `c4-shared.tsx`: added `savedContentRef` (per-file optimistic content); the `[data, activeFile]` effect now keeps the saved text when the reloaded source is stale, clearing the marker once the clone catches up. Diagram staleness still falls through to the Layer-1 banner.
- [x] 2.2 `c4-shared.tsx`: non-2xx still `throw`s before `onSaved` (`:416`) → error inline, no reload (F-B preserved). Pinned by the 1.2 test.
- [x] 2.3 N/A — verified `commitSha` + the client's already-sent `draft` suffice; no route/writer change.
- [x] 2.4 N/A — already satisfied: `c4-writer.ts:138` logs `event:c4_write` per-save; `c4-writer.ts:318` + `workspace-sync.ts:204` (`op:self-heal-aborted-dirty`) already mirror the diverged-clone abort to Sentry via `reportSilentFallback`.

## Phase 3 — Guards & regression

- [x] 3.1 No `reset --hard` added — `workspace-sync.ts` untouched; the gated `@{u}..HEAD` self-heal is preserved (un-pushed session work safe).
- [x] 3.2 `c4-workspace.test.tsx` regression green (clean-clone save flow unchanged).
- [x] 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (EXIT=0).
- [x] 3.4 `vitest run` of the three C4 suites green (28/28); full web-platform suite green (9613 passed, 0 failures).

## Phase 4 — Deferrals

- [ ] 4.1 File the **F-C tracking issue**: workspace-wide shared-clone divergence-recovery gap (best-effort `session-sync` push leaves the clone un-fast-forwardable, degrading EVERY sync consumer) + the H3 `rev-list→reset` TOCTOU (route working-tree git ops through `withWorkspacePermissionLock`). Reference `kb-sync-stale-no-manual-recovery-postmortem.md` and a roadmap milestone. Re-eval: any `self-heal-aborted-dirty` recurrence or a second clone-stuck report.

## Phase 5 — Post-merge (operator)

- [ ] 5.1 Live dogfood on the dev-cohort deployment: C4 KB page → Code tab → edit a label in `model.c4` → Save → confirm the edit persists in the editor AND (after re-render) the diagram updates; if `SYNC_FAILED`, confirm the honest error renders. (Automation not feasible — requires the live operator clone's diverged state, which a synthetic CI clone cannot reproduce.)
