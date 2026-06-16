---
title: Tasks — KB-sync protected-branch trigger fix
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-16-fix-kb-sync-protected-branch-trigger-plan.md
spec: knowledge-base/project/specs/feat-kb-sync-trigger-fix/spec.md
closes: 5426
created: 2026-06-16
---

# Tasks: KB-sync protected-branch trigger fix

All work in worktree `.worktrees/feat-kb-sync-trigger-fix` on branch `feat-kb-sync-trigger-fix`.
Single atomic PR (#5427). Write failing tests first (RED) per `cq-write-failing-tests-before`.

## Phase 0 — Preconditions (verify, don't assume)
- [ ] 0.1 Confirm `gitWithInstallationAuth` accepts `fetch`/`branch`/`cherry-pick`/`push <refspec>`/`reset --hard` (`server/git-auth.ts:266`) and that `runConnectedRepoGit` forbids reset/branch/push (`session-sync.ts:39-56`).
- [ ] 0.2 Derive the user repo `{owner, repo}` via the `agent-runner.ts:1478-1590` `repo_url`→owner/repo parse + `GITHUB_NAME_RE` guard (ADR-044 canonical workspace read). Reuse that pattern.
- [ ] 0.3 Use `getInstallationOctokit(installationId)` (`github/app-client.ts:88`) + `createPullRequest` (`github-app.ts:1236`); App has `pull_requests:write` (`infra/github-app-manifest.json:26`). Note: `createPullRequest` has no `draft` param → open non-draft.
- [ ] 0.4 Capture real protected-branch + `shallow update not allowed` push stderr shapes (synthesize fixtures from them — `cq-test-fixtures-synthesized-only`).

## Phase 1 — Push-error classification (RED → GREEN)
- [x] 1.1 RED: write `classifyPushError` unit tests — `protected_branch` (GH006 / remote-rejected + protection tails incl. required-review/required-check), `persistent_other` (`shallow update not allowed`), neither for auth/network. (AC1)
- [x] 1.2 GREEN: implement `classifyPushError(err)` in `session-sync.ts`, keyed on `GH006` + `remote rejected`, tolerant of varied tails.

## Phase 2 — Protected-fallback path in `syncPush` (RED → GREEN)
- [x] 2.1 RED: tests for the fallback — pushes `soleur/kb-sync` to the user repo (dynamic owner/repo, base = `resolveDefaultBranch`, never hardcoded `main`); opens a **non-draft** PR base = resolved default. (AC2)
- [x] 2.2 RED: durable-branch accretion — two consecutive fallbacks → one branch built by **tree-overlay** (`checkout -B soleur/kb-sync origin/soleur/kb-sync` → `git checkout <default-HEAD> -- knowledge-base` → commit), never `checkout -B` from default or cherry-pick; PR reused. (AC4)
- [x] 2.3 RED: after success, local default reset to `origin/<default>`, HEAD on `<default>`, reset AFTER side-branch push + PR. (AC3)
- [x] 2.4 RED: failure preserves writes — side-branch push / Octokit failure ⇒ default NOT reset, HEAD restored to default, `protected-fallback-failed` emitted. (AC6)
- [x] 2.5 RED: idempotent re-entry — empty `origin/<default>..HEAD` + no overlay diff ⇒ no commit, reuse PR, not a failure. (AC7)
- [x] 2.6 RED: unprotected path unchanged — push succeeds, no fallback, history recorded. (AC5)
- [x] 2.7 GREEN: implemented `runProtectedFallback` in `syncPush` — resolve default + owner/repo → fetch → tree-overlay onto `soleur/kb-sync` → push refspec (ff, no force; bail on non-ff) → `findOpenPullRequest`-or-`createPullRequest` (non-draft) → **then** `reset --hard origin/<default>` + restore HEAD. All git via `gitWithInstallationAuth`. (Used `findOpenPullRequest` + `createPullRequest` from `github-app.ts` rather than `getInstallationOctokit` — simpler, mirrors `createPullRequest`'s auth surface, no `founderId` audit baggage.)

## Phase 3 — Observability
- [x] 3.1 Emit `kb-sync.push-protected-fallback` (warn; payload: PR url + commit count) and `kb-sync.protected-fallback-failed` (covers push-reject / Octokit / persistent_other). Operator message strings preserved.
- [x] 3.2 Added `sentry_issue_alert.kb_sync_protected_fallback_failed` in `infra/sentry/issue-alerts.tf` (op-scoped IS_IN, freq=17); wired into `apply-sentry-infra.yml` -target list; op-contract test `test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts`.

## Phase 4 — Verify & gate
- [x] 4.1 New file `test/server/session-sync-protected-fallback.test.ts` (matches `test/**/*.test.ts`). (kb-route-helpers untouched — this change is wholly in `session-sync.ts`, not `syncWorkspace`; the existing file still passes the AC8 gate.)
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes. (AC8)
- [x] 4.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/session-sync-protected-fallback.test.ts test/kb-route-helpers.test.ts` passes. (AC8)
- [x] 4.4 Precedent-diff complete: tree-overlay chosen over cherry-pick (novel, conflict-prone) — distinct from `selfHealNonFastForward`'s `git branch <recovery> HEAD` (branches at HEAD, not onto a diverged remote branch). Branch-topology rationale captured in the plan R1 + the fallback doc-comment; standalone ADR deferred as non-blocking.

## Phase 5 — Ship & post-merge
- [ ] 5.1 PR body uses `Ref #5426` (not `Closes`) — closure is post-merge after verification.
- [ ] 5.2 After deploy, confirm `kb-sync.push-protected-fallback` (with PR url) fires and `self-heal-recovered-diverged` stops recurring **for the affected workspace** (scope to workspace; pre-existing strandings may emit until #5428). Then `gh issue close 5426`.
