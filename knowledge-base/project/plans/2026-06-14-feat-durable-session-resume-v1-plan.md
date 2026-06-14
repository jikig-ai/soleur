---
title: Durable session resume v1 — honest UX + verified workspace rebind
date: 2026-06-14
type: feat
issue: 5240
branch: feat-durable-session-resume
pr: 5256
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-durable-session-resume/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-14-durable-session-resume-brainstorm.md
wireframes: knowledge-base/product/design/chat/reconnect-resume-states.pen
plan_review: applied (DHH + Kieran + Simplicity, 2026-06-14)
---

# Plan: Durable session resume v1 (#5240)

## Overview

Backend agent sessions mishandle disconnect/reconnect: on resume the agent's cwd resolves to the
**wrong (solo) workspace**, the agent reports "no git repository… nothing to resume from" (a
misleading fresh-session greeting), and a fabricated "Retrying…" status masks a stalled turn. The
user's cloned repo + in-flight worktree are **not lost** — they sit intact on a persistent volume —
so v1 is a small, high-trust fix: **align the resolver with the conversation's own workspace,
verify it, and tell the truth when it's genuinely gone.**

v1 = FR1–FR5 (honest reconnect/resume UX + verified deterministic rebind). Deferred: #5273
(stream-since-disconnect buffer), #5274 (physical durability), #5275 (in-flight work durability),
and a new reconnect-state-machine hardening follow-up (AC10–AC12, see Open Questions).

> **v1 descope (2026-06-14, implementation correction).** As SHIPPED, v1 is **FR1 + FR4 + FR5
> only**. **FR2/FR3 (the honest reclaimed-message) and the dependent AC3/AC6/AC7/AC8 were reverted
> and deferred (tracked on #5240).** Reason: the plan's pre-dispatch `.git` probe (Phase 2 below)
> skips dispatch when `.git` is absent, but the recovering self-heal re-clone
> (`ensureWorkspaceRepoCloned`) runs *inside* the cold dispatch (`realSdkQueryFactory`) — so the
> probe would dead-end connected-repo resume recovery. The honest reclaimed-message must be emitted
> *after* a failed self-heal re-clone, not before dispatch; that is the follow-up's correct design.
> Consequently **only the `resume-workspace-rebind` op slug ships** — the `resume-workspace-gone`
> and `resume-action-failed` slugs in the Observability block and the AC-obs grep below are
> DEFERRED (do not assert them against the shipped diff). FR1 alone fixes the reported incident
> (resume → wrong/solo workspace → misleading greeting); the genuinely-`.git`-gone path is
> unchanged-or-improved by FR1 (the self-heal still re-clones the now-correct workspace). See
> `tasks.md` §"Deferred from v1" for the authoritative record.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Failure is physical workspace durability (ephemeral fs) | `/workspaces` is a persistent Hetzner volume (`server.tf:847-861`), single instance — repo survives restarts | Reframe to binding-resolution drift; durability deferred (#5274) |
| The in-memory `userWorkspaces` map is the binding (per issue body) | The map is "for SIGTERM precision, not auth" (issue body) — **the agent cwd resolver never reads it** | FR1 does NOT touch the map |
| Resume resolves a different workspace_id (cause unknown) | The agent cwd is resolved by `resolveActiveWorkspacePath` (`agent-runner.ts:994`) → `resolveCurrentWorkspaceId` which reads **`user_session_state.current_workspace_id`** and falls back to `userId`/solo (`workspace-resolver.ts:190,217`). On resume nobody re-aligns `current_workspace_id` with the conversation, so the resolver returns the stale value → solo | **FR1 writes `user_session_state.current_workspace_id = conversations.workspace_id` on resume** (Open Q2 resolved) |
| Binding store is per-user `user_session_state` (one reading) vs per-conversation (another) | BOTH exist and were **out of sync on resume**: `conversations.workspace_id` (NOT NULL, mig `059:62`) is the per-conversation truth; `user_session_state.current_workspace_id` is what the resolver reads | Authoritative *intent* = `conversations.workspace_id`; FR1 syncs the resolver's field to it (Open Q1 resolved) |
| — | No schema change needed; the switch mechanism `set_current_workspace_id` already exists (`workspace-resolver.ts:295`, used by the active-repo route) | **No migration in v1**; reuse the existing switch |

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- Pin the exact `current_workspace_id` switch call: `git grep -rn "set_current_workspace_id\|setCurrentWorkspaceId\|\.rpc(\"set_current" apps/web-platform/server apps/web-platform/app` — locate the active-repo route's corrective write (referenced at `workspace-resolver.ts:295`) and reuse its exact shape.
- Confirm resolver path: `resolveActiveWorkspacePath` (`workspace-resolver.ts:339`) → `resolveCurrentWorkspaceId` (`:190`, reads `user_session_state.current_workspace_id`, `?? userId` at `:217`).
- Confirm resume SELECT at `ws-handler.ts:~1615` lacks `workspace_id`; confirm terminal catch at `~1649-1653` (no outer `.catch` replay).
- Confirm cc-dispatcher already reads `conversations.workspace_id` in `persistUserMessage` (`~2203-2218`) with `reportSilentFallback`+throw — FR2 branches off this, not a new read.
- Check whether the chat reducer has a **connection-state** input (socket open/closed) distinct from the activity watchdog — decides whether FR4 can split state 1 vs state 2 or only "retire the lie" (see Phase 3).
- Baseline: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Phase 1 — FR1: verified deterministic rebind (server)
RED: test that resuming a conversation makes the agent cwd resolve to `conversations.workspace_id`, not solo.
- `ws-handler.ts:~1615` — add `workspace_id` to the resume `.select(...)`.
- On resume, before dispatch, write `user_session_state.current_workspace_id = conv.workspace_id` via the existing `set_current_workspace_id` switch (Phase 0 pins the call). This is the field `resolveCurrentWorkspaceId` reads — it is the load-bearing fix. (Do **not** rely on `setUserWorkspace`/the in-memory map; the resolver ignores it.)
- If the conversation `workspace_id` read fails / is unexpectedly null → `reportSilentFallback(err, { feature: "session-resume", op: "resume-workspace-rebind", extra: { conversationId } })`. **Recovery is the existing terminal catch at `ws-handler.ts:1649` (honest client error), NOT a `.catch` replay** — the resume_session case has no outer replay handler (corrected per plan-review P0-3). Drop any "caller's `.catch` fires" framing.

### Phase 2 — FR2 + FR3: pre-greeting probe + honest message (server)
RED: when the resolved workspace path has no `.git`, an honest "workspace reclaimed — resume with context?" message is emitted, NOT a fresh-session greeting.
- Reuse the already-resolved `conversationWorkspaceId` from the existing `cc-dispatcher.ts` `persistUserMessage` read (`~2203`) — do not re-resolve. Add only the `.git` probe (`existsSync(join(workspacePath, ".git"))`, shape from `ensure-workspace-repo.ts:78`) at the **pre-greeting/dispatch branch** (Phase 0 cites the exact line; it is NOT the RLS-INSERT read at ~2203).
- If `.git` absent → emit the deterministic honest message (wireframe **state 3**) and branch around the agent greeting (mutually exclusive — probe-then-branch, per R3). Mirror as expected operational warning: `warnSilentFallback(... op: "resume-workspace-gone")`.

### Phase 3 — FR4: retire the "Retrying…" lie (client)
RED: a 45s silent stream yields an accurate status, never "Retrying…".
- The `retrying` boolean is load-bearing across ≥5 sites (`chat-state-machine.ts:495-515,1096-1113`; `chat-surface.tsx:~667`; `message-bubble.tsx` `RetryingChip`). v1 retires the **lie**, minimally:
  - Replace the user-facing "Retrying…" copy (`message-bubble.tsx:~50`) AND the misleading semantic with an accurate "No response yet" state.
  - **If Phase 0 finds a connection-state input** in the reducer → split into wireframe states 1 (connection-lost) vs 2 (no-activity-45s). **If not** → ship the accurate single state ("No response for 45s") and defer the 1-vs-2 split to the reconnect-state-machine follow-up (with AC10–AC12). Do not half-build a connection-state machine for copy.

### Phase 4 — FR5 + trimmed honesty consequences (AC6, AC8)
- FR5: a resumed turn with an existing bound workspace continues in it (falls out of Phase 1; `ws-handler.ts:1634-1643` already clears session for first-turn re-resolve).
- AC6 turn-completed-while-away: guard so a conversation whose turn completed during the gap renders the completed transcript (existing completed-conversation UI / wireframe state 4 — no new wireframe), never an indefinite spinner or a resume prompt for done work.
- AC8 decline/ignore resting state: State-3 card persists over the read-only transcript; sending a new message implies Resume (or is blocked with the same affordance) — no dead end. [Resume] maps to the **existing** `ensureWorkspaceRepoCloned` `.git`-absent self-heal (re-clone, `ensure-workspace-repo.ts:78+`) + SDK transcript resume (`agent-runner.ts:1874-1885, 2334` `resumeSessionId`) — **verified present (R5)**, no new resume engine.
- AC7 resume-action failure: if `[Resume]` (the self-heal turn) fails, surface an honest retryable error (mirror `op: "resume-action-failed"`), never a silent loop or fresh greeting.

**Cut from v1 (per plan-review consensus):** AC9 (message-during-gap = in-flight durability) → folded into **#5275**. AC10/AC11/AC12 (flap idempotency, grace-boundary single-state, connection-vs-activity precedence) → new reconnect-state-machine hardening ticket (require a connection-state input the reducer lacks today; net-new architecture, not a binding fix).

### Phase 5 — Verification
- `tsc --noEmit`; vitest for touched suites (deterministic — assert on server message / state value, never via LLM prose).
- Browser QA of the wireframed states via `/soleur:qa`.
- Observability discoverability test (below).

## Files to Edit
- `apps/web-platform/server/ws-handler.ts` (FR1: resume SELECT `workspace_id` + `set_current_workspace_id` switch + `reportSilentFallback`; ~1615/~1632; honest recovery via existing catch ~1649)
- `apps/web-platform/server/cc-dispatcher.ts` (FR2/FR3: `.git` probe off the existing `conversationWorkspaceId` read + honest message at the pre-greeting branch)
- `apps/web-platform/lib/chat-state-machine.ts` (FR4: retire the `retrying` lie; ~1113 / watchdog ~495-515)
- `apps/web-platform/components/chat/message-bubble.tsx` (FR4: `RetryingChip` copy/semantic; ~50)
- `apps/web-platform/test/...` (RED tests; path must match `vitest.config.ts` `include:` globs — `test/**/*.test.ts(x)`)

## Files to Create
- RED test files under `apps/web-platform/test/` for resume-rebind + honest-message + state machine.

## Open Code-Review Overlap
4 open code-review issues touch these files; all distinct concerns — **Acknowledge** (own cycles): #3374 (slot_reclaimed frame) + #2191 (clearSessionTimers refactor) on `ws-handler.ts`; #3243 (cc-dispatcher decomposition) + #3242 (tool_use raw-name) on `cc-dispatcher.ts`. None overlap the resume/binding/status changes.

## User-Brand Impact
*(carried forward from brainstorm — `single-user incident`)*
- **If this lands broken, the user experiences:** a resumed conversation that lies — "nothing to resume" on intact work, or a fake "Retrying…" over a dead turn.
- **If this fails silently, the user's workflow is exposed via:** silent wrong-workspace resolution masquerading as success, destroying the "remembers" brand promise while their in-flight work sits unreferenced.
- **Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at PR review.

## Domain Review
**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — carried forward from brainstorm.

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-review correction). Authoritative resolver field = `user_session_state.current_workspace_id`; per-conversation truth = `conversations.workspace_id`; v1 syncs them on resume. No new store, no ADR needed beyond this note.

### Legal (CLO)
**Status:** reviewed (carry-forward). Not a blocker. v1 reads existing `workspace_id` and writes an existing `current_workspace_id` field — no new data category/recipient/region, no schema change. TTL hygiene applies only to deferred buffer (#5273).

### Product/UX Gate
**Tier:** blocking (edits `chat-state-machine.ts` + `message-bubble.tsx`).
**Decision:** reviewed.
**Agents invoked:** spec-flow-analyzer (this plan), cpo (brainstorm carry-forward), ux-design-lead (brainstorm Phase 3.55 — `.pen` committed).
**Skipped specialists:** none.
**Pencil available:** yes (`reconnect-resume-states.pen`, 4 states; v1 reuses all 4, no new states).

#### Findings
spec-flow surfaced AC6–AC12; plan-review trimmed AC9→#5275 and AC10–AC12→follow-up. v1 keeps AC3/AC4/AC6/AC7/AC8 (the honesty surface). The two "new states" reuse existing wireframes (turn-completed = state 4; decline-resting = state 3). N5 (multi-tab) deferred.

## GDPR / Compliance Gate
Trigger (b) fired (single-user-incident), but v1 touches **no** canonical regulated-data surface (no schema, migration, `.sql`, auth flow, or new PII-handling API route — it reads/writes existing workspace-binding fields). CLO brainstorm assessment carries forward as the substantive analysis. Disposition: **evaluated, no Critical findings, no `compliance-posture.md` write.**

## Observability
```yaml
liveness_signal:
  what: resume-workspace-rebind success (user_session_state.current_workspace_id aligned to conversations.workspace_id on resume)
  cadence: per resume_session (request-driven)
  alert_target: Sentry issue alert on op="resume-workspace-rebind" error events
  configured_in: apps/web-platform/infra/sentry/*.tf (issue alert rule)
error_reporting:
  destination: Sentry via reportSilentFallback (server/observability.ts:183)
  fail_loud: true (FR1 surfaces honest client error via existing catch; no silent solo-fallback)
failure_modes:
  - mode: conversation.workspace_id read fails / null
    detection: reportSilentFallback op="resume-workspace-rebind"
    alert_route: Sentry issue alert
  - mode: bound workspace .git absent (workspace reclaimed)
    detection: warnSilentFallback op="resume-workspace-gone" (expected; debounced)
    alert_route: Sentry warn + honest user message (wireframe state 3)
  - mode: resume action ([Resume] self-heal turn) fails
    detection: reportSilentFallback op="resume-action-failed"
    alert_route: Sentry issue alert
logs:
  where: pino structured logs in ws-handler.ts / cc-dispatcher.ts (op-tagged)
  retention: existing platform log retention (unchanged)
discoverability_test:
  command: 'curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://<org>.sentry.io/api/0/organizations/<slug>/issues/?query=op:resume-workspace-rebind" | jq ".[].title"  # NO ssh; org/slug + token per existing infra/sentry/*.tf + Doppler SENTRY_AUTH_TOKEN'
  expected_output: zero events in steady state; non-zero only on real rebind failures
```

## Acceptance Criteria

### Pre-merge (PR)
- AC1: Reconnect within grace → the resumed turn's agent cwd resolves to `conversations.workspace_id` (no solo drift). Verified by asserting `user_session_state.current_workspace_id` is aligned, NOT by the in-memory map. (FR1) — AC2 (post-restart, workspace exists) and AC5 (no "No workspace binding" throw) are test-case variants of AC1.
- AC3: "continue where you left off" on a conversation with prior turns → never a fresh-session greeting; correct continuation or honest "workspace reclaimed — resume with context?". (FR3)
- AC4: The "Retrying…" fabrication is gone; status copy is accurate (state 2, plus state 1 only if a connection-state input exists). (FR4)
- AC6: A turn that completed during the disconnect renders the completed transcript on reconnect — no indefinite spinner, no resume prompt for done work.
- AC7: A failed `[Resume]` self-heal surfaces an honest retryable error (mirror `op:resume-action-failed`); never a silent loop or fresh greeting. *(Cut if deepen-plan finds the self-heal/transcript path doesn't deliver Resume — then state 3 is honest-copy-only.)*
- AC8: After declining/ignoring `[Resume]`, the user has a defined resting state (read-only transcript + persistent affordance + explicit composer behavior) — no dead end.
- AC-obs: `tsc --noEmit` clean; the op slugs are emitted on their failure paths (`grep -rEn 'op: "(resume-workspace-rebind|resume-workspace-gone|resume-action-failed)"' apps/web-platform/server apps/web-platform/lib`).

### Deferred (tracked, not in this PR)
- AC9 → #5275 (in-flight work durability). AC10/AC11/AC12 → new reconnect-state-machine hardening ticket (filed at plan exit).

## Test Scenarios
- Unit (vitest): resume aligns `current_workspace_id` to `conversations.workspace_id`; missing `.git` → honest message (not greeting); AC6 completed-turn render; AC8 resting state.
- Browser QA: the 4 wireframed states render with accurate copy.
- Deterministic only — assert on server message / reducer state, never on agent prose (`2026-04-19` learning).

## Risks & Mitigations
- **R1 — Resolver field, not the map:** FR1 MUST write `user_session_state.current_workspace_id` (read by `resolveCurrentWorkspaceId:217`); `setUserWorkspace` writes a map the cwd resolver ignores. Mitigation: Phase 1 RED test asserts resolved cwd / the field, not the map (plan-review P0-1).
- **R2 — No `.catch` replay on resume_session:** recovery is the existing terminal catch at `ws-handler.ts:1649` (honest client error + Sentry), not a replay path. Mitigation: FR1 does not assume replay (plan-review P0-3).
- **R3 — Probe vs greeting must be mutually exclusive:** Phase 2 guards dispatch behind the `.git` probe so the user never gets both the honest message and a greeting.
- **R4 — `current_workspace_id` switch concurrency:** a resume write must not race a concurrent `set_current_workspace_id` switch (noted at `agent-runner.ts:1342`, `conversations-tools.ts:164`). Mitigation: reuse the existing switch's ordering/locking; inline a comment that resume only writes on conversationId (re)assignment.
- **R5 — `[Resume]` depends on existing self-heal: VERIFIED present.** `ensureWorkspaceRepoCloned` re-clones a `.git`-absent connected workspace (`ensure-workspace-repo.ts:78+`); `session_id` is persisted + resumed via `resumeSessionId` (`agent-runner.ts:1874-1885, 2334`). [Resume] = trigger a normal turn → self-heal re-clone + transcript resume. No new resume engine; AC7 stays.

## Sharp Edges
- `## User-Brand Impact` is filled (deepen-plan Phase 4.6 gate).
- Deterministic tests only — never assert honesty via an LLM prompt.
- Typecheck via `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces`; `npm run -w` fails).
- FR1 targets `user_session_state.current_workspace_id`, NOT the `userWorkspaces` map — the map is SIGTERM-precision only and the cwd resolver never reads it.
