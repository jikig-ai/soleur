---
feature: feat-one-shot-block-dispatch-until-repo-status-ready
issue: 5394
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-16-feat-block-dispatch-until-repo-status-ready-plan.md
---

# Tasks — block dispatch until repo_status=ready (#5394)

Phase order is load-bearing: status-reader contract ships before its consumers.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Confirm `current-repo-url.ts` does not yet read `repo_status` (selects only `repo_url`).
- [ ] 0.2 Read the `cc-dispatcher.ts:3328` typed-branch ladder + the generic `else` `session_id` clear at `:3363`.
- [ ] 0.3 Read `byok-lease.ts:192` `MissingByokKeyError` (error-class export pattern).
- [ ] 0.4 Locate both Sentry mirror sites: `soleur-go-runner.ts:2541`, `cc-dispatcher.ts:3284`.
- [ ] 0.5 Confirm vitest include globs (unit `test/**/*.test.ts` node, component `test/**/*.test.tsx` happy-dom) and `./node_modules/.bin/vitest` present.

## Phase 1 — Status reader contract (server)

- [ ] 1.1 Add `getCurrentRepoStatus(userId, workspaceId?)` in `apps/web-platform/server/current-repo-url.ts`: widen the `workspaces` select to `repo_url, repo_status, repo_error`, return `{ repoUrl, repoStatus, repoError }`; coerce null status → `not_connected`; **fail-OPEN** on read error (transient → proceed, never block).
- [ ] 1.2 Add `RepoSetupInProgressError` + `RepoSetupFailedError { sanitizedReason }` and pure `evaluateRepoReadiness(status, repoError)` in `apps/web-platform/server/repo-readiness.ts`. Exact AC copy; reuse `parseErrorPayload` shape from `status/route.ts:102` for the sanitized reason. `ready`/`not_connected` → `{ok:true}`.

## Phase 2 — Layer A gate (dispatch backstop)

- [ ] 2.1 ws-handler primary short-circuit (`ws-handler.ts:2346`, before `dispatchSoleurGoForConversation` at `:2355`, inside `routing.kind !== "legacy"`): resolve status → `evaluateRepoReadiness`; on `!ok` `sendToClient({type:"error", message, errorCode?})` + `break`. No throw, no Sentry.
- [ ] 2.2 Factory backstop (`cc-dispatcher.ts`, after `repoUrl` resolves `:1532`, BEFORE `ensureWorkspaceDirExists`/`ensureWorkspaceRepoCloned`): read status (fold into existing row resolution), throw `RepoSetupInProgressError`/`RepoSetupFailedError` on cloning/error. `ready` falls through unchanged (AC6 invariant).
- [ ] 2.3 Dispatch-catch branches (`cc-dispatcher.ts:3328` ladder, ABOVE the generic `else`): `RepoSetupInProgressError` → cloning message; `RepoSetupFailedError` → error message + `errorCode:"repo_setup_failed"`. Do NOT clear `session_id`.
- [ ] 2.4 Sentry-mirror skip for the two expected classes at BOTH `soleur-go-runner.ts:2541` and `cc-dispatcher.ts:3284`; emit `logger.info` breadcrumb instead.

## Phase 3 — Layer B (chat composer)

- [ ] 3.1 Extend `useActiveRepo` (or `useRepoSetupState` wrapper): interval poll (2 s) WHILE `cloning`, self-stop on ready/error/not_connected, keep mount+focus, coalesce via `inFlight`.
- [ ] 3.2 `chat-input.tsx`: add `repoSetupState` prop; disable composer + `"Setting up your repository…"` placeholder while cloning; inline elapsed-timer indicator (`useElapsed(sinceMs)`), voice from `setting-up-state.tsx`.
- [ ] 3.3 Error reconnect CTA (inline banner) → link `/dashboard/settings`; voice from `failed-state.tsx`, do not reuse full `FailedState`.
- [ ] 3.4 Wire `chat-surface.tsx` to pass `repoSetupState`; auto-transition to enabled on ready poll (AC4).

## Phase 4 — Tests (AC7)

- [ ] 4.1 `test/repo-readiness.test.ts` (node): `evaluateRepoReadiness` per branch (cloning AC1 / error AC2 / ready AC3 / not_connected) + gate calls `sendToClient` and NOT dispatch (mocked), LLM off the assertion path.
- [ ] 4.2 AC6 regression: `ready` → `{ok:true}`, factory reaches mocked `ensureWorkspaceRepoCloned`.
- [ ] 4.3 `test/chat-input-repo-setup.test.tsx` (component): cloning → disabled + placeholder + elapsed (AC4 start); rerender ready → re-enabled (AC4 transition); error → reconnect CTA to `/dashboard/settings` (AC5).
- [ ] 4.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-readiness.test.ts test/chat-input-repo-setup.test.tsx` green; `./node_modules/.bin/tsc --noEmit` clean (AC8).
- [ ] 4.5 AC9 grep: gate routes `repo_error` through the sanitizer, no raw stderr/path leak.

## Ship

- [ ] PR body uses `Closes #5394`.
- [ ] `.pen` wireframe for composer setting-up + error states (wg-ui-feature-requires-pen-wireframe) produced at deepen-plan/work Phase 2.5.
- [ ] CPO sign-off (single-user-incident threshold) recorded before /work.
