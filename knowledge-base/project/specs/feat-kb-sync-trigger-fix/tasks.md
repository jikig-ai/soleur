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
- [ ] 0.2 Confirm how to derive the user repo `{owner, repo}`: clone `origin` remote URL vs `workspaces.repo_url` (ADR-044). Pick the source the fallback will use.
- [ ] 0.3 Confirm the Octokit-from-installation-token path (`resolveOctokit` / installation token) and that the App has `pull_requests:write` (`infra/github-app-manifest.json:26`).
- [ ] 0.4 Capture real protected-branch + `shallow update not allowed` push stderr shapes (synthesize fixtures from them — `cq-test-fixtures-synthesized-only`).

## Phase 1 — Push-error classification (RED → GREEN)
- [ ] 1.1 RED: write `classifyPushError` unit tests — `protected_branch` (GH006 / remote-rejected + protection tails incl. required-review/required-check), `persistent_other` (`shallow update not allowed`), neither for auth/network. (AC1)
- [ ] 1.2 GREEN: implement `classifyPushError(err)` in `session-sync.ts`, keyed on `GH006` + `remote rejected`, tolerant of varied tails.

## Phase 2 — Protected-fallback path in `syncPush` (RED → GREEN)
- [ ] 2.1 RED: tests for the fallback — pushes `soleur/kb-sync` to the user repo (dynamic owner/repo, base = `resolveDefaultBranch`, never hardcoded `main`); opens a **draft** PR base = resolved default. (AC2)
- [ ] 2.2 RED: durable-branch accretion — two consecutive fallbacks → one branch, **both** commits (content-equality), one PR; built by cherry-pick onto `origin/soleur/kb-sync`, never `checkout -B`. (AC4)
- [ ] 2.3 RED: after success, local default `== origin/<default>`, HEAD on `<default>`. (AC3)
- [ ] 2.4 RED: failure preserves writes — side-branch push / Octokit failure ⇒ default NOT reset, writes survive, `protected-fallback-failed` emitted. (AC6)
- [ ] 2.5 RED: idempotent re-entry — empty `origin/<default>..HEAD` ⇒ no-op reuse of PR, not reported as failure. (AC7)
- [ ] 2.6 RED: unprotected path unchanged — push succeeds, no fallback, history recorded. (AC5)
- [ ] 2.7 GREEN: implement the fallback in `syncPush` catch — resolve default + owner/repo → fetch → accrete (cherry-pick) onto `soleur/kb-sync` → push refspec (ff, no force; bail on non-ff) → create-or-update draft PR → **then** `reset --hard origin/<default>` + restore HEAD. All git via `gitWithInstallationAuth`. Order so default resets ONLY after side-branch push succeeds.

## Phase 3 — Observability
- [ ] 3.1 Emit `kb-sync.push-protected-fallback` (warn; payload: PR url + commit count) and `kb-sync.protected-fallback-failed` (covers push-reject / Octokit / persistent_other). Preserve operator message strings.
- [ ] 3.2 Add the `sentry_issue_alert` for `kb-sync.protected-fallback-failed` in `infra/sentry/*.tf`.

## Phase 4 — Verify & gate
- [ ] 4.1 New file `test/server/session-sync-protected-fallback.test.ts` (matches `test/**/*.test.ts`); extend `test/kb-route-helpers.test.ts`.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes. (AC8)
- [ ] 4.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/session-sync-protected-fallback.test.ts test/kb-route-helpers.test.ts` passes. (AC8)
- [ ] 4.4 (deepen-plan/work) precedent-diff the cherry-pick vs `merge --ff` shape against `selfHealNonFastForward` branch-aside (`workspace-sync.ts:288`); consider a short ADR for the branch-topology decision (R6).

## Phase 5 — Ship & post-merge
- [ ] 5.1 PR body uses `Ref #5426` (not `Closes`) — closure is post-merge after verification.
- [ ] 5.2 After deploy, confirm `kb-sync.push-protected-fallback` (with PR url) fires and `self-heal-recovered-diverged` stops recurring **for the affected workspace** (scope to workspace; pre-existing strandings may emit until #5428). Then `gh issue close 5426`.
