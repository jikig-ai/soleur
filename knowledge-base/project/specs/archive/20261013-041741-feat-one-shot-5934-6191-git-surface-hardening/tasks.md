# Tasks — git-surface / config.lock hardening (#6191 Closes, #5934 Ref)

Plan: `knowledge-base/project/plans/2026-07-08-chore-git-surface-config-lock-hardening-plan.md`
Lane: cross-domain (no spec.md — TR fail-closed default)

## Phase 0 — Preconditions
- [x] 0.1 Re-grep exact anchors: workspace.ts 236/246 confirmed; gate L112 confirmed.
- [x] 0.2 Confirm ADR-099 §Known latent surfaces still names both sites; ADR-081 carries the 2026-07-05 single-path CORRECTION + #6191 note.
- [x] 0.3 Read the atomic-rename precedents: `workspace-permission-lock.ts` + `worktree-manager.sh atomic_git_config`.

## Phase 1 — lock-free TS `atomicGitConfig` (RED → GREEN)
- [x] 1.1 RED: `apps/web-platform/test/git-config-atomic.test.ts` (4 cases: clean-write; other-keys-survive; pre-existing lock non-blocking + not-deleted; non-regular-target refused-no-throw + reportSilentFallback spy). Verified RED (missing module).
- [x] 1.2 GREEN: `apps/web-platform/server/git-config-atomic.ts` — `atomicGitConfig(cwd, args, opts?)` cp-p→temp→`git config --file`→`renameSync`; masked-target → CAPTURED `reportSilentFallback` + error log; best-effort never-throws; `createChildLogger`; no `SOLEUR_*` sentinels; concurrency doc-comment (synchronous + single-worker, NOT "lock-free"). 4/4 GREEN.

## Phase 2 — Route host-side writes through the helper
- [x] 2.1 workspace.ts:236/246 → `atomicGitConfig(workspacePath, …)`, outer try/catch→log.warn kept. AC2: 0 raw writes, 2 helper calls.
- [~] 2.2 **SKIPPED per deepened plan** (Enhancement Summary #4 + Phase 2 Scope decision): routing `seedWorktreeConfig` was dropped as manufactured scope by simplicity- + architecture-review — not an ADR-099-named site, already atomic host-side. tasks.md pre-dated that decision; plan is authoritative.
- [x] 2.3 `test/workspace.test.ts` + `test/worktree-config-seed.test.ts` green; no outcome assertion broke. (+ orphan suite `workspace-error-handling.test.ts` 6/6 green.)

## Phase 3 — Gate authority inversion (Taste: default accept-the-caveat)
- [x] 3.1 Default: fixed `prod-write-defer-gate.sh` resolver comment — documents the non-bare `--global`=bot inversion (audit-log-only, double-unset-guarded, ADR-099 §latent). No logic change; suite 62/62 green. AC4 caveat sentence + ADR-099 x2 asserted.
- [~] 3.2 Active-fix arm NOT elected (default accept-the-caveat per D1). No test change.

## Phase 4 — Documentation
- [x] 4.1 ADR-099 §latent: both items marked RESOLVED (2026-07-08, #6191).
- [x] 4.2 ADR-081: single-path finding consolidated into one authoritative statement deferring to the live-findmnt CORRECTION; status unchanged (`adopting`).
- [x] 4.3 `gh issue comment 5934` posted (single-path CONFIRMED; #5912 fallback de-risked; durable fix stays OPEN; follow-through due 2026-07-14). NOT closed.

## Phase 5 — Verify (all no-SSH)
- [x] 5.1 `tsc --noEmit` clean (rc=0).
- [x] 5.2 `vitest run` git-config-atomic + workspace + worktree-config-seed + git-lock-marker-telemetry: 36/36 green.
- [x] 5.3 `bash .claude/hooks/prod-write-defer-gate.test.sh`: 62/62 green.
- [x] 5.4 `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh`: green (2 skipped).
- [ ] 5.5 PR body (`Closes #6191`, `Ref #5934`) — handled by ship.

## Ship notes
- `Closes #6191` (both latent items resolved). `Ref #5934` (durable fix not in this repo; soak due 2026-07-14).
- Post-merge (automated via ship): `gh issue view 6191` == CLOSED; `gh issue view 5934` == OPEN.
- `decision-challenges.md` (D1 gate resolve-vs-caveat) → ship renders into PR body + files action-required issue.
