# Tasks — git-surface / config.lock hardening (#6191 Closes, #5934 Ref)

Plan: `knowledge-base/project/plans/2026-07-08-chore-git-surface-config-lock-hardening-plan.md`
Lane: cross-domain (no spec.md — TR fail-closed default)

## Phase 0 — Preconditions
- [ ] 0.1 Re-grep exact anchors: `grep -nE 'execFileSync\("git", \["config", "user\.(name|email)"' apps/web-platform/server/workspace.ts` and `grep -n 'git config --global --get user.email' .claude/hooks/prod-write-defer-gate.sh`.
- [ ] 0.2 Confirm ADR-099 §Known latent surfaces still names both sites; ADR-081 still carries the 2026-07-05 single-path CORRECTION + the "coordinated with #6191" note.
- [ ] 0.3 Read the atomic-rename precedents: `apps/web-platform/server/workspace-permission-lock.ts:11–26` and `worktree-manager.sh atomic_git_config` (cp-p→`git config --file`→`mv -f`).

## Phase 1 — lock-free TS `atomicGitConfig` (RED → GREEN)
- [ ] 1.1 RED: create `apps/web-platform/test/git-config-atomic.test.ts` (vitest node project, `test/**/*.test.ts`); fixtures modeled on `test/worktree-config-seed.test.ts`. Cases: clean-write; other-keys-survive (cp-first invariant); pre-existing `config.lock` non-blocking + not-deleted; non-regular target refused (no throw).
- [ ] 1.2 GREEN: create `apps/web-platform/server/git-config-atomic.ts` exporting `atomicGitConfig(cwd, args, opts?)` — resolve `.git/config`, `cp -p` → same-dir temp, `git config --file <tmp> <args>`, defensive non-regular-target check → `reportSilentFallback(...)` CAPTURED Sentry event + error log (NOT a bare breadcrumb, per `cq-silent-fallback-must-mirror-to-sentry`), `renameSync(tmp, config)`. Best-effort, never throws; log via `createChildLogger("git-config-atomic")`. NO stdout `SOLEUR_*` sentinels. Module doc-comment: concurrency safety = synchronous + single-worker-per-container (NOT "lock-free"); no Mutex (multi-process/async out of scope — mirror `workspace-permission-lock.ts:1–10`).
  - Test also asserts the masked-target branch invokes `reportSilentFallback` (spy/mock).

## Phase 2 — Route host-side writes through the helper
- [ ] 2.1 Replace the two raw `execFileSync("git",["config","user.name"/"user.email",…])` at workspace.ts:236/246 with `atomicGitConfig(workspacePath, …)`; keep the outer try/catch→log.warn.
- [ ] 2.2 Route `seedWorktreeConfig`'s two writes in `worktree-config-seed.ts` through `atomicGitConfig` (the `--get` read stays raw). Lock-free helper makes the 2-caller surface safe.
- [ ] 2.3 Run `test/workspace.test.ts` + `test/worktree-config-seed.test.ts`; adjust only if a specific outcome assertion breaks (none expected — they assert config outcomes, not write argv).

## Phase 3 — Gate authority inversion (Taste: default accept-the-caveat)
- [ ] 3.1 Default: fix `.claude/hooks/prod-write-defer-gate.sh` L105–107 comment — document the non-bare `--global`=bot inversion, that the path is audit-log-only + double-unset-guarded, cite ADR-099 §latent. No resolver logic change; suite stays green.
- [ ] 3.2 (Active-fix arm, only if operator/review elects it) bot-shape discriminator applied to BOTH `--local` and `--global`; extend `prod-write-defer-gate.test.sh` with `TEST-FIXTURE-NOT-REAL` cases (bot-shaped → `unknown@local`; non-bot local → resolved; env-precedence unchanged).

## Phase 4 — Documentation
- [ ] 4.1 ADR-099 (via `/soleur:architecture`): mark both §latent items RESOLVED by #6191 (note "resolved 2026-07-08, #6191").
- [ ] 4.2 ADR-081: consolidate the single-path mask-scope conclusion into one authoritative statement (currently split between ruled-out candidate (a) + 2026-07-05 correction). Status unchanged (`adopting`).
- [ ] 4.3 `gh issue comment 5934` — record re-eval outcome (single-path CONFIRMED; #5912 fallback de-risked to insurance; durable sandbox-masking fix remains OPEN; non-recurrence tracked, due 2026-07-14). DO NOT close.

## Phase 5 — Verify (all no-SSH)
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-config-atomic.test.ts test/workspace.test.ts test/worktree-config-seed.test.ts test/git-lock-marker-telemetry.test.ts`
- [ ] 5.3 `bash .claude/hooks/prod-write-defer-gate.test.sh`
- [ ] 5.4 `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` (parity reference — must stay green)
- [ ] 5.5 PR body: `Closes #6191`, `Ref #5934`. Pre-merge/Post-merge AC split honored.

## Ship notes
- `Closes #6191` (both latent items resolved). `Ref #5934` (durable fix not in this repo; soak due 2026-07-14).
- Post-merge (automated via ship): `gh issue view 6191` == CLOSED; `gh issue view 5934` == OPEN.
- `decision-challenges.md` (D1 gate resolve-vs-caveat) → ship renders into PR body + files action-required issue.
