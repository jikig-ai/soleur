---
title: "Tasks — fix cron workspace off /tmp tmpfs"
plan: knowledge-base/project/plans/2026-06-01-fix-cron-workspace-off-tmpfs-plan.md
branch: feat-one-shot-cron-workspace-off-tmpfs-4684
lane: cross-domain
issues: [4684, 4689]
---

# Tasks — relocate cron ephemeral workspaces off the 256 MB /tmp tmpfs

## Phase 1 — Substrate base-dir resolution + free-space guard

- 1.1 Add `export function resolveCronWorkspaceRoot()` to
  `_cron-claude-eval-substrate.ts` (env `CRON_WORKSPACE_ROOT`, `.trim() ||`
  fallback to `tmpdir()`).
- 1.2 Change the `mkdtemp` parent (lines 109-110) to
  `join(resolveCronWorkspaceRoot(), \`soleur-${cronName}-\`)`; keep prefix.
- 1.3 Import `statfs` from `node:fs/promises` and `warnSilentFallback` from
  `@/server/observability` (verified export at `observability.ts:227`).
- 1.4 Add the non-fatal pre-clone free-space guard (after mkdtemp, before
  clone): `op: "cron-workspace-low-disk"` WARN under floor; `bavail*bsize`;
  `DEFAULT_CRON_WORKSPACE_MIN_FREE_MB = 256`; `CRON_WORKSPACE_MIN_FREE_MB`
  override; wrap statfs in try/catch → `op: "cron-workspace-statfs-failed"`.
  No `throw` anywhere in the guard.
- 1.5 Confirm teardown (`rm -rf ephemeralRoot`) is unchanged; confirm ADR-033
  I1-I6, redaction, clone-failure reporting unchanged.

## Phase 2 — Surface exitCode in scheduled-output-missing

- 2.1 Add `exitCode?: number | null` to `resolveOutputAwareOk` args
  (`_cron-shared.ts`).
- 2.2 Add `exitCode` to the `scheduled-output-missing` Sentry `extra` object
  (~`_cron-shared.ts:261-269`).
- 2.3 Thread `exitCode` from the 4 call sites that already pass `stderrTail`
  (`cron-content-generator`, `cron-roadmap-review`, `cron-competitive-analysis`,
  + the `stderrTail`-passing follow-through path). Re-grep to confirm scope; the
  4 sites that don't pass `stderrTail` need no change (optional arg).

## Phase 3 — Wire CRON_WORKSPACE_ROOT in ci-deploy.sh

- 3.1 Add `-e CRON_WORKSPACE_ROOT=/workspaces \` after the
  `-e INNGEST_BASE_URL` line in the CANARY docker run block (~line 456).
- 3.2 Add the same line in the PROD docker run block (~line 620).
- 3.3 Confirm the `--tmpfs /tmp:…size=256m` lines are byte-for-byte unchanged.

## Phase 4 — Tests

- 4.1 Extend `test/server/inngest/cron-claude-eval-substrate.test.ts` with a
  `resolveCronWorkspaceRoot` describe: env-set → value; env-unset → `tmpdir()`;
  whitespace → `tmpdir()`. afterEach restores env. No live tokens.
- 4.2 Add `assert_cron_workspace_root` to `ci-deploy.test.sh` mirroring
  `assert_tmpfs_flag` (every docker run line has
  `-e CRON_WORKSPACE_ROOT=/workspaces`); register the call near line 1182.
- 4.3 Run `./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts`
  and `bash apps/web-platform/infra/ci-deploy.test.sh` — both green.

## Phase 5 — Runbook correction

- 5.1 Append container-tmpfs + `_metrics`-emptiness clarification to the
  existing `## Known coverage gap` section in
  `knowledge-base/engineering/ops/runbooks/betterstack-log-query.md`.

## Phase 6 — Deferred-item tracking + ship

- 6.1 File a follow-up issue for stdout-tail capture (max-turns notice
  diagnosability) — label `type/bug` + `domain/engineering`.
- 6.2 Confirm the "route app pino stdout into Vector" follow-up issue exists;
  file if not.
- 6.3 PR body: `Closes #4684`, `Closes #4689`.
- 6.4 Post-merge verification folded into `/soleur:ship` (no SSH): trigger one
  cron + confirm no new `WEB-PLATFORM-17` ENOSPC events.
