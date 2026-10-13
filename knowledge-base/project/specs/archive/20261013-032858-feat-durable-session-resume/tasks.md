---
title: Tasks — Durable session resume v1
issue: 5240
branch: feat-durable-session-resume
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-14-feat-durable-session-resume-v1-plan.md
---

# Tasks: Durable session resume v1 (#5240)

## Phase 0 — Preconditions ✅ COMPLETE (2026-06-14)
- [x] 0.1 Switch call pinned: `supabase.rpc("set_current_workspace_id", { p_workspace_id: <id> })` — canonical pattern at `app/api/workspace/accept-invite/route.ts:78` (membership-checked, sets BOTH current_workspace_id + current_organization_id, best-effort with `reportSilentFallback`). Also at `active-repo/route.ts:59`.
- [x] 0.2 Resolver path confirmed: `resolveActiveWorkspacePath:339` → `resolveCurrentWorkspaceId:190` reads `user_session_state.current_workspace_id`, `?? userId` solo-fallback at `:217`. (`agent-runner.ts:994` resolves agent cwd through it.)
- [x] 0.3 Resume SELECT confirmed `"id, status, repo_url"` at `ws-handler.ts:1613` (no `workspace_id`); switch point is right after `session.conversationId = msg.conversationId` at `:1634`; terminal catch `:1649-1653` (no `.catch` replay).
- [x] 0.4 cc-dispatcher `persistUserMessage` reads `conversations.workspace_id` (`~2203`) — FR2 branches off it.
- [x] 0.5 **No connection-state input in the reducer** (grep of `chat-state-machine.ts` for connect/socket/disconnect found only a comment). → FR4 ships the accurate single "No response yet" state; state-1/2 split defers to #5282.
- [x] 0.6 Baseline `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (run at GREEN start).

**FR1 GREEN recipe (verified):** at `ws-handler.ts:1613` add `workspace_id` to `.select(...)`; after `:1634` add `const { error: switchErr } = await tenantResumeConv.rpc("set_current_workspace_id", { p_workspace_id: (conv as {workspace_id:string}).workspace_id }); if (switchErr) reportSilentFallback({code:switchErr.code,message:switchErr.message}, { feature:"session-resume", op:"resume-workspace-rebind", message:..., extra:{userId, conversationId: msg.conversationId} });` (mirror accept-invite:78-91). RED test: integration-style (`TENANT_INTEGRATION_TEST=1`, model on `test/server/ws-handler.tenant-isolation.test.ts`) asserting the resumed session resolves to `conversations.workspace_id`, OR a focused unit test spying the tenant client `.rpc` call.

## Phase 1 — FR1 verified rebind (server) [RED→GREEN]
- [x] 1.1 RED: test resume aligns `user_session_state.current_workspace_id` to `conversations.workspace_id` (assert the field/resolved cwd, NOT the in-memory map).
- [x] 1.2 Add `workspace_id` to the resume `.select(...)` at `ws-handler.ts:~1615`.
- [x] 1.3 On resume, write `current_workspace_id = conv.workspace_id` via the existing switch (0.1); guard to only fire on conversationId (re)assignment (R4).
- [x] 1.4 On read failure/null → `reportSilentFallback(op:"resume-workspace-rebind")`; honest client error via the existing catch (no `.catch` replay assumption).

## Phase 2 — FR2/FR3 probe + honest message (server) [DEFERRED → follow-up]
**Descoped from v1 (2026-06-14).** Implementation traced a regression in the
plan's prescribed placement: the `.git`-absent self-heal (`ensureWorkspaceRepoCloned`)
runs *inside* the cold dispatch (`realSdkQueryFactory:1464`), gated on the
~80-line `effectiveInstallationId` entitlement-promotion chain. A pre-dispatch
probe that skips dispatch (the plan's "off the persistUserMessage read"
placement) prevents that self-heal from running for exactly the connected-repo
resume case it targets — turning today's transparent re-clone into a permanent
dead-end, and making AC7/AC8's `[Resume]` ("send a message") un-deliverable.
The honest reclaimed-message is fundamentally a *post-self-heal-failure* concept
and must be emitted after a failed re-clone, not before dispatch. FR1 already
fixes the actual reported incident (resume → wrong/solo workspace → misleading
greeting), so v1 ships FR1+FR4+FR5 and FR2/FR3 + AC6/AC7/AC8 move to a follow-up
that does the post-self-heal architecture correctly.
- [ ] 2.1 (deferred) honest reclaimed-message emitted only after a failed self-heal re-clone.
- [ ] 2.2 (deferred) thread a "self-heal failed" signal out of `realSdkQueryFactory`.
- [ ] 2.3 (deferred) branch around the agent greeting (mutually exclusive, R3); `warnSilentFallback(op:"resume-workspace-gone")`.

## Phase 3 — FR4 retire the "Retrying…" lie (client) [RED→GREEN]
- [x] 3.1 RED: 45s silent stream → accurate status, never "Retrying…".
- [x] 3.2 Replace `RetryingChip` copy + misleading semantic (`message-bubble.tsx:~50`, `chat-state-machine.ts:~1113`) with accurate "No response yet".
- [x] 3.3 If 0.5 found a connection-state input → split states 1/2; else ship accurate single state and defer split to #5282.

## Phase 4 — FR5 + honesty consequences (AC6/AC7/AC8)
- [x] 4.1 FR5: resumed turn with existing bound workspace continues in it — falls out of Phase 1 (FR1 rebinds the resolver to `conversations.workspace_id`; with `.git` present the agent continues in that workspace). Verified by `ws-handler-resume-rebind.test.ts` (the rebind assertion).
- [ ] 4.2 AC6 (deferred with FR2/FR3): turn-completed-while-away renders completed transcript, no spinner/resume-prompt. Part of the honest reclaimed/reconnect UX cluster; moves to the FR2/FR3 follow-up.
- [ ] 4.3 AC7 (deferred with FR2/FR3): failed `[Resume]` self-heal → honest retryable error. Depends on the reclaimed-message + self-heal path → follow-up.
- [ ] 4.4 AC8 (deferred with FR2/FR3): decline/ignore resting state. Depends on the reclaimed-message UX → follow-up.

## Phase 5 — Verification
- [x] 5.1 `tsc --noEmit` clean; vitest touched suites green (deterministic — assert resolver rpc / reducer copy, not LLM prose). FR1 `ws-handler-resume-rebind.test.ts` (2) + FR4 `message-bubble-retry.test.tsx` (4) + neighbor state-machine/streaming suites (73 total).
- [~] 5.2 Browser QA — N/A for v1: the FR2/FR3 reclaimed-message states (3 of 4 wireframes) are deferred; only FR4's "No response yet" chip copy changed (leaf `components/chat/message-bubble.tsx` — does NOT trip the structural-UI visual gate), covered by the component test.
- [x] 5.3 AC-obs: `op: "resume-workspace-rebind"` emitted on both failure paths (`ws-handler.ts:1654,1672`). `resume-workspace-gone`/`resume-action-failed` slugs deferred with FR2/FR3. Sentry discoverability curl is a post-deploy verify (zero events in steady state).
- [ ] 5.4 Pre-ship: `/soleur:preflight`; PR body `Refs #5240` (NOT `Closes` — FR2/FR3 + AC3/AC6/AC7/AC8 deferred, #5240 stays open as their tracker); `user-impact-reviewer` at review (single-user threshold).

## Out of scope (tracked)
- #5273 stream-since-disconnect buffer · #5274 physical durability · #5275 in-flight work (incl. AC9) · #5282 reconnect state-machine hardening (AC10–AC12 + state 1/2 split).

## Deferred from v1 (2026-06-14 descope) — tracked on #5240 (stays open)
- **FR2/FR3 honest reclaimed-message + AC3 + AC6/AC7/AC8.** The plan's pre-dispatch `.git` probe regresses connected-repo resume recovery (skips the in-dispatch `ensureWorkspaceRepoCloned` self-heal). Correct design: emit the honest message only AFTER a failed self-heal re-clone (post-`realSdkQueryFactory` signal), suppressing the agent greeting then. v1 ships FR1 (verified rebind — fixes the reported incident) + FR4 (retire "Retrying…") + FR5.
