# Session State — feat-kb-sync-trigger-fix (#5426)

**Updated:** 2026-06-16. **Branch:** `feat-kb-sync-trigger-fix`. **Worktree:** `.worktrees/feat-kb-sync-trigger-fix/`. **PR:** #5427 (draft). **Issue:** #5426.

## Pipeline so far
`/soleur:go #5426` → brainstorm → plan → deepen-plan → work (Phase 1 done).
- Brainstorm: `knowledge-base/project/brainstorms/2026-06-16-kb-sync-trigger-fix-brainstorm.md`
- Plan (reviewed + deepened): `knowledge-base/project/plans/2026-06-16-fix-kb-sync-protected-branch-trigger-plan.md`
- Tasks: `knowledge-base/project/specs/feat-kb-sync-trigger-fix/tasks.md`
- Deferred: #5428 (recovery-branch sweep), #5429 (in-product status surface UI).

## Done (committed `887f6b210`)
**Phase 1** — `classifyPushError` in `apps/web-platform/server/session-sync.ts` (exported, after `FORBIDDEN_GIT_FLAGS`): returns `protected_branch | persistent_other | other`. 7 RED→GREEN tests in `apps/web-platform/test/server/session-sync-protected-fallback.test.ts`. `tsc --noEmit` clean.

## Resume — Phase 2 (the git-mechanics fallback in `syncPush`)
Implement the protected-fallback path in `syncPush` (`session-sync.ts:551`, the `catch` at ~`:623`). On `classifyPushError(err) === "protected_branch"`:
1. Resolve `defaultBranch` (mirror `resolveDefaultBranch` — `git symbolic-ref --short refs/remotes/origin/HEAD`, via `gitWithInstallationAuth`) and the user `{owner, repo}` from the workspace `repo_url` (ADR-044 canonical read; parse per `agent-runner.ts:1525-1538` — `new URL(repoUrl).pathname.split("/")` + `GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/`; strip a trailing `.git` from `repo`).
2. **All branch/fetch/checkout/reset/push via `gitWithInstallationAuth`** — `runConnectedRepoGit` forbids them (allowlist = status/add/commit/remote/rev-list only, `session-sync.ts:39-45`).
3. Accrete via **tree-overlay** (NOT cherry-pick): capture default HEAD; checkout/create local `soleur/kb-sync` tracking `origin/soleur/kb-sync` (or branch from `origin/<default>` if absent); `git checkout <default-HEAD> -- knowledge-base/`; commit. Latest-KB-wins, conflict-free, preserves the side branch's prior commits.
4. Push `HEAD:refs/heads/soleur/kb-sync` (ff, no `--force`). On non-ff (co-member race) → do NOT reset default; bail best-effort.
5. Create-or-update PR in the user's repo: `getInstallationOctokit(installationId)` → `GET /repos/{owner}/{repo}/pulls` (`head:"soleur/kb-sync"`, `base:<default>`, `state:"open"`) → if none, `createPullRequest(installationId, owner, repo, "soleur/kb-sync", <default>, title, body)` (`github-app.ts:1236`, **non-draft** — no `draft` param exists; never auto-merge); else no-op.
6. **Only after the side-branch push + PR succeed**: `reset --hard origin/<default>` + restore HEAD to `<default>` (so failure preserves the commit on default for next-session retry — AC6).
7. Observability: `warnSilentFallback`/`reportSilentFallback` ops `kb-sync.push-protected-fallback` (payload: PR url + commit count) and `kb-sync.protected-fallback-failed`. Phase 3.2: add `sentry_issue_alert` for the failed op in `apps/web-platform/infra/sentry/*.tf`.

RED tests (extend the existing test file) for AC2/AC3/AC4(tree-overlay accretion, content-equality + prior commits)/AC5(unprotected unchanged)/AC6(failure preserves writes)/AC7(idempotent empty re-entry). Mock surface: `git-auth` (`gitWithInstallationAuth`), `github-app` (`createPullRequest`), `github/app-client` (`getInstallationOctokit`), the workspace `repo_url` read, plus the existing `child_process`/`fs`/`observability` mocks (see `test/server/session-sync-sentry-mirror.test.ts` for the hoisted-spy pattern).

## Exit gate (Phase 4)
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + `./node_modules/.bin/vitest run` (full suite, from the WORKTREE path — CWD drifts to bare-repo otherwise). Then `/soleur:review` → `/soleur:qa` (diff touches `server/`, not dashboard UI → qa optional) → `/soleur:compound` → `/soleur:ship`. PR body uses `Ref #5426` (not `Closes`); close post-merge after the Sentry verification (Phase 5.2).
