# Tasks: feat-one-shot-11594-11599-auth-mode-followups

Plan: `knowledge-base/project/plans/2026-10-31-feat-auth-mode-followups-recovery-copy-and-delegated-api-key-plan.md`. Rulings: `decision-challenges.md` in this directory. Two commits: commit 1 = #11594 (lease), commit 2 = #11599.

## Phase 0 Setup

- 0.1 Fetch `origin/main`; run `bash scripts/check-adr-ordinals.sh`; install dependencies in `apps/web-platform` if absent.
- 0.2 Re-run the open code-review overlap query for the planned files.
- 0.3 Confirm `/dashboard/chat/new` renders; confirm `getFreshTenantClient` dedups the in-flight mint per user; confirm `bind_agent_engine_run` is the only place `auth_mode` is stamped.
- 0.4 Baseline the Test-impact sweep (plan section) and record pre-existing failures.

## Phase 1 RED tests (write first, watch them fail)

- 1.1 Commit 1: lease cases as `describe` blocks in `test/byok-lease-credential-type.test.ts` and `test/byok-lease-auth-mode-binding.test.ts` (AC1-AC4, AC15); rewrite the "AC4 gate order" table and the AC16 "no binding read" test; resolver mismatch case in `test/engine-binding-auth-mode.test.ts`.
- 1.2 Commit 2: `test/auth-mode-unresolved-frame.test.ts`, `test/auth-mode-unresolved-client.test.tsx`, `test/server/ws-handler-lease-refusal.test.ts`; new cases in `agent-auth-user-message.test.ts`, the three wire suites, `test/server/auto-sync-trigger.test.ts`, `agent-engine-settings.test.tsx`; characterization tests for the delegate dead ends (AC16).

## Phase 2 Lease (commit 1)

- 2.1 `server/auth-mode-error.ts`: transient set, reason union with `workspace_mismatch`, `classifyAuthModeReason`.
- 2.2 `server/byok-lease.ts`: cause union and constructor, `failAuthModeClosed`, `mapByokLeaseCauseToErrorCode`, `crossOwnerChoseApiKey` and restructure, tripwire before `decryptRow(oauthRow)`, `delegationWorkspaceId`, breadcrumb, JSDoc.
- 2.3 `server/byok-resolver.ts` passes `delegationWorkspaceId`; `server/engine-binding-auth-mode.ts` accepts the expected workspace.
- 2.4 `server/auto-sync-trigger.ts` and `server/inngest/functions/agent-on-spawn-requested.ts` follow the new causes.
- 2.5 ADR-048 addendum (#11594 part) and appended CLO audit addendum.

## Phase 3 Server wiring (commit 2)

- 3.1 `server/agent-auth-user-message.ts`: `isLeaseRefusalReported`, frame builder, generalised helpers, INFO logging.
- 3.2 Skip the call-site mirror at the five points (`agent-runner.ts` x2, `ws-handler.ts`, `soleur-go-runner.ts`, `cc-dispatcher.ts` incl. both existing `isOauthUnusableLeaseError` sites) and add the cc-dispatcher frame branch.

## Phase 4 Client (commit 2)

- 4.1 `lib/types.ts` and `lib/ws-zod-schemas.ts` in one change.
- 4.2 `lib/ws-client.ts` branch (mark unanswered, no teardown) and scoped clear on send; `components/chat/chat-surface.tsx` title and no Reconnect.

## Phase 5 Settings (commit 2)

- 5.1 `components/settings/agent-engine-settings.tsx`: non-owner helper and disclosure; compare with draft PR #9051.

## Phase 6 Recovery sentence (commit 2)

- 6.1 One constant on the five `oauth_token` cells; update the pinned copy test.

## Phase 7 Docs and issues

- 7.1 ADR-048 #11599 addendum, supersession markers, `related:`; one trailing newline.
- 7.2 Read-only check of DPD item (w) and AUP 5.6 for a non-owner grantor; record in the decision file; flag a gap to the CLO.
- 7.3 File the one follow-up issue (delegate dead-end copy), `Ref #11599`.

## Phase 8 Verification

- 8.1 `npx tsc --noEmit`; the Test-impact sweep; `python3 scripts/lint-anthropic-content-position.py`; `bash scripts/check-adr-ordinals.sh`; `bash scripts/markdown-lint.sh --repo-sweep`.
- 8.2 PR body: `Closes #11594`, `Closes #11599` only if every acceptance criterion holds; `## Changelog` section.
