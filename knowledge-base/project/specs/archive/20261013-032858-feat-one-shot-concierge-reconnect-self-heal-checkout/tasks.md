---
feature: feat-one-shot-concierge-reconnect-self-heal-checkout
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-16-fix-concierge-reconnect-self-heal-checkout-plan.md
status: ready
---

# Tasks — Concierge reconnect self-heal + auto-sync resilience

Derived from the finalized (deepened) plan. Test runner: vitest
(`cd apps/web-platform && ./node_modules/.bin/vitest run <path>`); typecheck:
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Do NOT use `bun test` or `npm run -w`.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `evaluateRepoReadiness` gate at `cc-dispatcher.ts:1563-1573` is upstream of
      `ensureWorkspaceRepoCloned` (`:1697`); `effectiveInstallationId` at `:1656`.
- [ ] 0.2 Confirm `provisionWorkspaceWithRepo` (`workspace.ts:166`) wipes via `removeWorkspaceDir` (`:185`).
- [ ] 0.3 Confirm tenant client cannot UPDATE `workspaces` (no RLS UPDATE policy) — read
      `workspace-repo-mirror.ts:35-37`; confirm `cc-dispatcher.ts` is OFF the service-role allowlist.
- [ ] 0.4 `ls apps/web-platform/supabase/migrations/ | tail -3` → next migration is `108_*` (107 is latest).
- [ ] 0.5 Read migration 079 + 083 for the SECURITY DEFINER + 4-role REVOKE/GRANT + `search_path` precedent.
- [ ] 0.6 Verify vitest `include` globs + bunfig block; component tests live under `test/`.

## Phase 1 — Failing tests first (RED)

- [ ] 1.1 `test/server/cc-dispatch-repo-self-heal.test.ts` (new) — scenario (a): decision-level with
      injected seams; branch matrix (error+install+.git-absent→won→clone→ok; failed→error block;
      no-install→block; lock loser→cloning honest-wait, no clone; fresh cloning→honest-wait; ready→ok).
- [ ] 1.2 Add AC1b assertion: after successful self-heal, `gitDirExists(workspacePath)` is true (invariant,
      not a stub-returns-ok proxy).
- [ ] 1.3 Migration/RPC test — `claim_repo_clone_lock` flips `error`→`cloning` and stale-`cloning`→`cloning`,
      returns false for fresh `cloning` + non-member; `set_repo_status` membership-gated.
- [ ] 1.4 Extend `test/components/repo/use-reconnect.test.tsx` + a `project-setup-card` test — scenario (b):
      installed:true + repoUrl in list + status!=ready → setup POST → status poll to terminal; ready→no POST;
      repoUrl not in list→/connect-repo; failure→client Sentry + resolves; bg-clone fail→terminal state.
- [ ] 1.5 `test/server/auto-sync-trigger.test.ts` (new) — scenario (c): RuntimeAuthError/ByokLeaseError →
      bounded retry → success with EXACTLY ONE conversations INSERT; exhausted→reportSilentFallback (op
      auto-sync-trigger), no rethrow, repo_status stays ready.
- [ ] 1.6 Sync-doc drift-guard — `--headless` branch of `plugins/soleur/commands/sync.md` commits-local /
      worktree→PR / handles GH013, never raw-pushes default. (Runner verified at 0.6.)
- [ ] 1.7 Confirm all RED for the right reason (not import errors).

## Phase 2 — FIX 1a: dispatch self-heal (GREEN)

- [ ] 2.1 New migration `108_repo_clone_self_heal_rpc.sql` — `claim_repo_clone_lock(p_workspace_id)` +
      `set_repo_status(p_workspace_id,p_status,p_error)`; SECURITY DEFINER; `search_path` pinned to
      `pg_catalog, pg_temp`; REVOKE from public/anon/authenticated/service_role then GRANT EXECUTE to
      authenticated; membership check; lock predicate `error OR (cloning AND repo_last_synced_at <
      now()-interval '5 minutes')`.
- [ ] 2.2 New `server/repo-readiness-self-heal.ts` — `resolveRepoReadinessWithSelfHeal(args, seams)` with
      injected `{ evaluateRepoReadiness, claimCloneLock, setRepoStatus, ensureWorkspaceRepoCloned,
      gitDirExists }`. Keep `repo-readiness.ts` I/O-free.
- [ ] 2.3 Rewire `cc-dispatcher.ts`: keep zero-await `evaluateRepoReadiness` fast-path at `:1563`
      (ready/not_connected); fall error/cloning through to `resolveRepoReadinessWithSelfHeal` AFTER
      `effectiveInstallationId` + `ensureWorkspaceDirExists`. Throw `RepoNotReadyError` only on `{ok:false}`.
      Reuse `effectiveInstallationId` (not raw `installationId`).
- [ ] 2.4 Self-heal failure → `reportSilentFallback` (feature cc-dispatcher, op repo-readiness-self-heal).

## Phase 3 — FIX 1b: reconnect re-triggers setup (GREEN)

- [ ] 3.1 `components/repo/use-reconnect.ts` — on detect-installation success + repoUrl-in-list +
      status!=ready → `POST /api/repo/setup {repoUrl}`; reachability guard; client Sentry on failure
      (`lib/client-observability`, op reconnect-resetup); never .catch(noop).
- [ ] 3.2 `components/settings/project-setup-card.tsx` — surface reconnect re-setup in the `error` branch
      (not ReconnectNotice, which is ready-only); add bounded `GET /api/repo/status` poll to terminal
      (mirror connect-repo/page.tsx).

## Phase 4 — FIX 2: headless sync push resilience (GREEN)

- [ ] 4.1 `plugins/soleur/commands/sync.md` — add `--headless` contract: commit-local / worktree→PR /
      GH013-graceful / auto-skip interactive AskUserQuestion gates.
- [ ] 4.2 Degraded read-back: headless sync writes a degraded marker (`conversations.status`); trigger reads
      it back and emits `reportSilentFallback` (op auto-sync-degraded) — OR drop the op if descoped.

## Phase 5 — FIX 3: auto-sync trigger lease resilience (GREEN)

- [ ] 5.1 New `server/auto-sync-trigger.ts` — `triggerHeadlessSync` with injectable `startAgentSession`
      seam; conversation INSERT ONCE outside retry; retry wraps only `startAgentSession`; bounded backoff
      (3× ~1s/3s/9s) on RuntimeAuthError/ByokLeaseError; exhausted → reportSilentFallback (op
      auto-sync-trigger), no rethrow, repo_status untouched.
- [ ] 5.2 `app/api/repo/setup/route.ts` — replace inline auto-sync with `triggerHeadlessSync` call.
- [ ] 5.3 Confirm `getUserApiKey` (agent-runner.ts:216) backstop + `userHasEffectiveByokKey` presence-gate
      both unchanged.

## Phase 6 — Verify

- [ ] 6.1 Three RED suites + AC1b + AC1c → GREEN.
- [ ] 6.2 `./node_modules/.bin/tsc --noEmit` clean.
- [ ] 6.3 Adjacent suites green: repo-readiness, ensure-workspace-repo, cc-reprovision, use-reconnect,
      byok-lease, sentry-chat-alert-op-contract (self-heal op NOT appended to chat-save rule).
- [ ] 6.4 No edits to `agent-runner.ts` readiness gating (sibling-worktree boundary — AC7).
- [ ] 6.5 No version-file bump.

## Phase 7 — Infra (post-merge / IaC)

- [ ] 7.1 NEW `sentry_issue_alert` for feature=cc-dispatcher op IS_IN {repo-readiness-self-heal} in
      `infra/sentry/issue-alerts.tf` (unused frequency; NOT appended to chat-save rule). Apply via
      `apply-sentry-infra.yml` `-target=`.
- [ ] 7.2 Migration applies via `web-platform-release.yml#migrate` on merge (not manual).
- [ ] 7.3 `/soleur:gdpr-gate` against the migration diff before merge (expected: no Critical).
