---
title: "Workspace reconcile — error-level Sentry noise on a self-healed dirty-tree ff-only abort"
status: in-progress
closes:
brand_survival_threshold: single-user incident
related_prs: [4878, 4901, 4963, 4965, 4967]
related_learnings:
  - 2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md
  - cron-clone-enospc-kb-reconcile-freeze-postmortem.md
  - plan-workspace-reconcile-push-noise.md
---

# Plan: stop the error-level Sentry page for a self-healed reconcile ff-only abort

## Problem

Production Sentry error `9ccf1d861b3b4c8595772bd116b931e8` (web-platform, prod,
`level=error`, `feature=pino-mirror`), fired by Inngest fn
`workspace-reconcile-on-push`:

```
Error: Command failed: git -c credential.helper= pull --ff-only
error: Your local changes to the following files would be overwritten by merge:
    knowledge-base/engineering/architecture/diagrams/model.likec4.json
Please commit your changes or stash them before you merge. Aborting
fatal: Cannot fast-forward your working tree.
```

The operator got a high-priority alert email for a condition the platform
**already self-heals**.

## Root cause (verified by reading the code path)

1. **The dirty file's source.** The new Layer-2 LikeC4 re-render
   (`c4-writer.ts` `rerenderAndCommit` → `c4-render.ts` `renderC4Model`, shipped
   2026-06-05 in #4963/#4965/#4967) writes the regenerated `model.likec4.json`
   **directly onto the tracked working-tree path** (`renderC4Model` validates to
   a temp file then `rename`s it onto `<diagramsDir>/model.likec4.json`,
   c4-render.ts:144,191). The bytes are then committed via the GitHub Contents
   API and pulled. So:
   - On the **success** path, the working-tree write collides with the
     subsequent `git pull --ff-only` (uncommitted local change vs the incoming
     identical-bytes commit) → dirty-tree abort, every save.
   - On any **failure** in `rerenderAndCommit` *after* the render-write but
     before the final resync (oversized-model early return, commit-json throw,
     resync failure), the uncommitted `model.likec4.json` is **stranded** in the
     working tree and dirties the **next webhook-push reconcile** — exactly the
     reported `op:push` event.

2. **Why it self-heals already.** `classifyGitSyncError` (workspace-sync.ts:41)
   routes `"would be overwritten by merge"` to `non_fast_forward` (added by
   #4901 for the `.claude/settings.json` incident), and
   `selfHealNonFastForward` runs a gated `reset --hard origin/<default>` when the
   clone holds **zero** un-pushed commits — discarding the spurious render-write
   and recovering (`{ok:true, recovered:true}`). The workspace is **not** frozen.

3. **The actual defect — the report fires before the self-heal.**
   `syncWorkspace` (workspace-sync.ts:100-127) emits BOTH
   `log.error({ err: syncError, … })` (line 102) and `reportSilentFallback`
   (line 106) **unconditionally on the first pull failure, before
   `selfHealNonFastForward` runs**. The pino `log.error` carries an `err` key, so
   `logger.ts:71-75` mirrors it to Sentry via
   `Sentry.captureException(err, { tags: { feature: "pino-mirror" } })` at
   `level=error` — the exact event the operator received. A benign,
   self-healable, recovered condition pages the operator on every push.

This is the same "benign + self-healing ⇒ don't create a Sentry issue" class the
prior reconcile-noise work established (`plan-workspace-reconcile-push-noise.md`:
the no-workspace-match skip was moved off Sentry to pino for the same reason).

## Fix (scope: de-noise the self-healable path)

Single file: `apps/web-platform/server/workspace-sync.ts`. Restructure the
`syncWorkspace` catch so the error-level mirror only fires for a **genuinely
un-recoverable** failure:

- **Self-healable class (`non_fast_forward`, incl. dirty-tree):** do NOT emit the
  pre-self-heal `log.error`(+`err`) or `reportSilentFallback`. Record a single
  pino **`log.info`** breadcrumb (Better Stack drain only — `info` is below the
  WARN+ Sentry-mirror threshold and carries no `err` key, so no Sentry capture),
  then delegate to `selfHealNonFastForward`, which already owns escalation:
  - success → `warnSilentFallback(op:self-heal-reset)` (unchanged; warning-level,
    does not trigger the high-priority alert rule; deliberately observable per
    the 2026-06-03 self-heal design).
  - un-pushed-commit abort → `reportSilentFallback(op:self-heal-aborted-dirty)`
    (unchanged — a real, operator-actionable freeze; now the operator sees the
    accurate "un-pushed local commits" cause instead of the raw git stderr).
  - reset/fetch failure → `reportSilentFallback(op:self-heal-failed)` (unchanged).
- **Non-self-healable class (`sync_failed`):** keep the existing
  `log.error`(+`err`) + `reportSilentFallback(op:workspace-sync-${op})`. A
  genuine sync failure still pages.

Net effect: a self-healed reconcile no longer emits an error-level Sentry event;
every genuine failure still pages. No change to `workspace-reconcile-on-push.ts`
(its `op:sync` mirror at line 298 already only fires when `syncResult.ok ===
false`, which a recovered self-heal no longer is).

### Out of scope (deferred follow-up — file a tracked issue)

The deeper source — `renderC4Model` writing the **tracked** working-tree
`model.likec4.json` (collides with `pull --ff-only` on success; strands a dirty
file on failure) — is a hot, freshly-shipped feature (2026-06-05). After this
de-noise fix the source churn is **benign and silent** (self-heals, no error
page), so hardening it (render to a non-tracked path / restore the working-tree
file on every `rerenderAndCommit` exit) is a separable robustness improvement,
not required to resolve this incident. Defer to a GitHub issue created at ship
time; do NOT redesign the render-after-save path in this PR (regression risk on
a feature shipped hours ago).

## Tests (failing-first)

Extend `apps/web-platform/test/kb-route-helpers.test.ts` (`describe("syncWorkspace")`).
The existing self-heal tests (lines 541-716) assert recovery/abort outcomes but
NONE assert the *absence* of the pre-self-heal error mirror — that is the
regression gap.

1. **NEW (fails against current code):** dirty-tree abort that self-heals
   (`DIRTY_TREE_STDERR` pull reject + `rev-list 0`) ⇒
   - `result.ok === true`, `result.recovered === true`
   - `mockReportSilentFallback` **not** called with `op:workspace-sync-*` (in
     fact not called at all on the recovered path)
   - the injected `logger.error` spy **not** called (no pino-mirror error capture)
   - a `logger.info` breadcrumb was emitted
   - `warnSilentFallback(op:self-heal-reset)` still fired (recovery observable)
2. **NEW:** same for the `non_fast_forward` (diverged) recovered path.
3. **Strengthen existing (line 457):** rename its error to an unambiguous
   `sync_failed` signature and re-title to make explicit that the error mirror is
   the **`sync_failed`** path; assert `log.error`(+`err`) + `reportSilentFallback`
   both fire and `result.ok === false`.
4. Unchanged: self-heal-aborted-dirty (649), self-heal-failed (677),
   self-heal-reset observable (701), clean pull (718) all still pass.

`workspace-reconcile-on-push.test.ts` is unaffected (it mocks `syncWorkspace`).

## Verification

- `pnpm --filter web-platform exec tsc --noEmit` clean.
- `pnpm --filter web-platform exec vitest run test/kb-route-helpers.test.ts test/c4-writer-rerender.test.ts test/server/inngest/workspace-reconcile-on-push.test.ts` — all green.
- `cq-ref-removal-sweep`: confirm `warnSilentFallback`/`reportSilentFallback`/
  `logger` imports in workspace-sync.ts still all have live callers after the edit
  (warnSilentFallback still used by self-heal-reset; reportSilentFallback still
  used by sync_failed + self-heal branches).

## Observability (no-SSH)

- **Sentry:** genuine `sync_failed` (`feature:kb-route-helpers
  op:workspace-sync-*`), self-heal aborts (`op:self-heal-aborted-dirty`), and
  self-heal failures (`op:self-heal-failed`) still surface — discoverable without
  SSH. The benign self-healed ff-only abort no longer creates an error issue.
- **Better Stack (pino):** the self-healable-abort breadcrumb
  (`kb/<op>: ff-only pull blocked — attempting gated self-heal`, info) and the
  `op:self-heal-reset` warn remain queryable for audit.

## Operator follow-up

After deploy, resolve/archive the existing Sentry issue
`9ccf1d861b3b4c8595772bd116b931e8` so the historical events clear.
