---
feature: feat-one-shot-block-dispatch-until-repo-status-ready
issue: 5394
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-16-feat-block-dispatch-until-repo-status-ready-plan.md
wireframe: knowledge-base/product/design/concierge/chat-composer-repo-setup-states.pen
---

# Tasks — block dispatch until repo_status=ready (#5394)

Design (post deepen-plan review): SINGLE factory gate, ONE error class, ONE catch branch.
Scope = Concierge / `/soleur:go` surface; legacy `startAgentSession` path = follow-up (AC10).
Phase order is load-bearing: status-reader contract ships before its consumers.

## Phase 0 — Preconditions (verify, no code)

- [x] 0.1 `grep -n "repo_status\|repo_error" server/current-repo-url.ts` → selects only repo_url today.
- [x] 0.2 `sed -n '3328,3371p' server/cc-dispatcher.ts` → typed ladder + generic-else session_id clear at :3363.
- [x] 0.3 Read byok-lease.ts:192-201 (MissingByokKeyError pattern).
- [x] 0.4 Confirm Sentry mirror sites: soleur-go-runner.ts:2541, cc-dispatcher.ts:3284.
- [x] 0.5 `grep -n repo_error server/workspace-repo-mirror.ts` → repo_error NOT mirrored (reason from users).
- [x] 0.6 `grep -n "parseErrorPayload\|WSErrorCode" app/api/repo/status/route.ts lib/types.ts` → parseErrorPayload module-private (extract); WSErrorCode lacks repo_setup_failed (widen).
- [x] 0.7 Vitest globs (unit test/**/*.test.ts node, component test/**/*.test.tsx happy-dom); `command -v ./node_modules/.bin/vitest`.
- [x] 0.8 `gh label list --limit 200 | grep -E "^(domain/engineering|chore)\b"` for the follow-up issue labels.

## Phase 1 — Status reader contract (server)

- [x] 1.1 Extract `parseErrorPayload` from app/api/repo/status/route.ts:102 into a shared exported module (co-locate with sanitizeGitStderr in server/git-auth.ts); update status/route.ts to import it.
- [x] 1.2 Add `getCurrentRepoStatus(userId)` in server/current-repo-url.ts: repo_status from workspaces (widen existing .select), error reason from users.repo_error; coerce null status → not_connected (fail-OPEN, never block a ready founder).
- [x] 1.3 server/repo-readiness.ts: `class RepoNotReadyError extends Error { code: "cloning"|"error"; errorCode?: "repo_setup_failed" }` (this.name set); exported copy constants REPO_CLONING_MSG + repoErrorMsg(reason); pure `evaluateRepoReadiness(status, repoError)`. ready/not_connected → {ok:true}; error reason via extracted parseErrorPayload.

## Phase 2 — Layer A gate (single, in the factory)

- [x] 2.1 cc-dispatcher.ts realSdkQueryFactory: fold repo_status into the existing getCurrentRepoUrl resolution in the Promise.all (:1515-1533, ZERO extra round-trips); after :1532, BEFORE ensureWorkspaceDirExists/ensureWorkspaceRepoCloned: `if (!r.ok) throw new RepoNotReadyError(...)`. (AC6 invariant: before ensureWorkspaceRepoCloned, fires only on cloning/error.)
- [x] 2.2 cc-dispatcher.ts:3328 ladder: ONE `else if (err instanceof RepoNotReadyError)` ABOVE the generic else → sendToClient({type:"error", message, errorCode?}). Does NOT clear session_id.
- [x] 2.3 Sentry-mirror skip `if (!(err instanceof RepoNotReadyError))` at BOTH soleur-go-runner.ts:2541 and cc-dispatcher.ts:3284; emit logger.info breadcrumb instead.
- [x] 2.4 Widen WSErrorCode (lib/types.ts:140) with "repo_setup_failed"; sweep consumers (git grep errorCode lib/ws-client.ts components/) per cq-union-widening-grep-three-patterns.

## Phase 3 — Layer B (chat composer)

- [x] 3.1 Extend useActiveRepo IN PLACE (already returns repoStatus): add setInterval (2s) in the existing useEffect guarded by repoStatus === "cloning", self-stop on leaving cloning, clear on unmount, keep inFlight coalescing. NO new wrapper hook.
- [x] 3.2 chat-input.tsx: add `repoSetupState?: "cloning"|"error"|null` prop; disabled when cloning; placeholder "Setting up your repository…"; inline spinner + "Setting up your repository…" + static "This usually takes less than a minute." (NO mm:ss timer — cut as gold-plating).
- [x] 3.3 chat-input.tsx error state: inline `<Link href="/dashboard/settings">Reconnect in Settings → Repository</Link>` (NO new banner component).
- [x] 3.4 chat-surface.tsx: read repoStatus from useActiveRepo, pass repoSetupState to <ChatInput>; auto-transition to enabled on ready poll (AC4).

## Phase 4 — Tests (AC7)

- [x] 4.1 test/repo-readiness.test.ts (node): evaluateRepoReadiness per branch (cloning AC1 vs imported const / error AC2 + errorCode / ready AC3 / not_connected); fail-open null→{ok:true}; sanitization (AC9: raw stderr+/abs/path → no leak).
- [x] 4.2 test/cc-dispatcher-repo-gate.test.ts (node): factory cloning/error THROWS before ensureWorkspaceRepoCloned (spy not-reached, no spawn — AC1); catch branch does NOT call clearCcSessionId; error payload has errorCode, cloning does not.
- [x] 4.3 Same file: Sentry-mirror spy — RepoNotReadyError → 0 mirror calls (both sites), unrelated error → 1 (positive control).
- [x] 4.4 Same file: AC6 — ready reaches mocked ensureWorkspaceRepoCloned.
- [x] 4.5 test/use-active-repo-poll.test.ts (node, fake timers): interval fires while cloning, self-stops on ready, clears on unmount, inFlight coalesces (AC4 controller).
- [x] 4.6 test/chat-input-repo-setup.test.tsx (component): cloning → disabled + placeholder + static indicator; rerender null → re-enabled; error → reconnect CTA Link to /dashboard/settings (AC5).
- [x] 4.7 `cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-readiness.test.ts test/cc-dispatcher-repo-gate.test.ts test/use-active-repo-poll.test.ts test/chat-input-repo-setup.test.tsx` green; `./node_modules/.bin/tsc --noEmit` clean (AC8).

## Ship

- [x] File AC10 follow-up issue: gate legacy startAgentSession path (agent-runner.ts:1097), re-eval note, labels domain/engineering + chore.
- [x] PR body: `Closes #5394`, `Ref #<follow-up>`, reference the committed .pen.
- [x] CPO sign-off (single-user-incident threshold) recorded before /work.
