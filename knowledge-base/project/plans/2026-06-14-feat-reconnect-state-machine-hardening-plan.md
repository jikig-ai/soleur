---
title: "feat: reconnect state-machine hardening (connection-state input, flap idempotency, grace-boundary single-state, connection-vs-activity precedence)"
issue: 5282
branch: feat-one-shot-5282-reconnect-state-machine-hardening
date: 2026-06-14
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Reconnect State-Machine Hardening (#5282)

✨ **Type:** enhancement (client-side chat state machine + render)
🎯 **Threshold:** single-user incident (a chat that lies about connection state, or stacks contradictory banners during a network flap, is the brand-survival surface)

## Enhancement Summary

**Deepened on:** 2026-06-14
**Review agents:** architecture-strategist, code-simplicity-reviewer, verify-the-negative/reducer-realism (sonnet)
**Gates passed:** Phase 4.6 (User-Brand Impact), 4.7 (Observability 5-field), 4.8 (no PAT-shape), 4.9 (UI-wireframe `.pen` committed).

### Key corrections applied (P0/P1 from deepen-review)
1. **P0 — sticky-terminal escape hatch.** Original plan made `clear_streams` reset the connection slice; it fires on EVERY reconnect (`connect()` ws-client.ts:589) + from abort handlers (:859), which would defeat AC11's no-3→4-flip entirely. Replaced with a dedicated `reset_connection` action dispatched only from the user-new-turn `sendMessage` path. All 5 `clear_streams` sites enumerated + classified at Phase 0.
2. **P0 — duplicate banner.** A State-1 "Connection lost. Reconnecting…" banner ALREADY exists at `chat-surface.tsx:567-580`. Reframed State 1 as a REWIRE of that banner through the precedence selector (not a greenfield `connection-banner.tsx`), with explicit reconciliation of the `:891` text to prevent two banners.
3. **Simplicity — enum minimized.** Collapsed the parallel 4-value `ConnectionPhase` (which duplicated the existing `ConnectionStatus`) to a 3-value `live|reconnecting|unrecoverable`; State 4 is now a DERIVED render affordance, not a `terminal_resumable` phase with a fragile two-step dispatch. `ReconnectView` shrunk 5→3 variants.
4. **P1 — function names + citation.** Corrected `sendUserMessage`/`dispatchSoleurGoForConversation` → the real unified `sendMessage` (ws-client.ts:1446); fixed the dual-path learning path to `integration-issues/2026-06-14-...`.
5. **P1 — streamState co-transition.** Documented (R6) that abort handlers already reset `streamState` via `clear_streams` before `connection` goes terminal, avoiding a Send-disabled-under-unrecoverable contradictory state.

### New considerations discovered
- ~18 `ChatState` literal sites in `test/**` need the new slice (tsc TS2741 is the enumerator).
- `applyStreamEvent` is timer/IO-free but calls `crypto.randomUUID()` — "pure" reworded to "untouched / no new coupling".

## Overview

Deferred from #5240 v1 during plan-review (DHH + Simplicity consensus, 2026-06-14). v1 (PR #5256, merged) retired the "Retrying…" lie and shipped the single honest "No response yet" watchdog chip (the `retrying` flag). #5273 stream-since-disconnect (PR #5290, merged) added the server-side replay buffer + `resume_stream`/`stream_replay` wire protocol. Both prerequisites are now satisfied; this is the bundled follow-up that builds the **connection-state model** v1 deliberately omitted.

Today the chat reducer (`apps/web-platform/lib/chat-state-machine.ts` + `chatReducer` in `apps/web-platform/lib/ws-client.ts`) carries ambient slices for `activeStreams`, `workflow`, `spawnIndex`, and `streamState` — but **nothing terminal-state-aware represents "is the session recoverable?"**. The WS connection lifecycle lives in `ws-client.ts` local state (`status: ConnectionStatus = "connecting"|"connected"|"reconnecting"|"disconnected"`, L32) which flips back to `connected` on reattach. A State-1 "Connection lost. Reconnecting…" banner **already exists** at `chat-surface.tsx:567-580`, driven directly by `status === "reconnecting"` (with a "Retry now" button at :575). The State-2 "No response yet" `RetryingChip` renders per-message at `message-bubble.tsx:45-64`.

**The real defects this plan fixes** (confirmed by code review against `origin/main`, not the original "the code can't distinguish them" framing which was inaccurate):
1. **AC12 — States 1 & 2 are wired independently** (banner off `status`, chip off per-message `retrying`), so both can render at once. There is no single precedence decision anywhere.
2. **AC11 — `status` cannot express a sticky-terminal state.** On reattach `status` flips `reconnecting → connected`, so a late reattach frame after a grace-expired abort would flip the UI from "unrecoverable" (State 3) to "resumed" (State 4). The existing `ConnectionStatus` has no "unrecoverable-after-grace" concept — that is a UI-honesty distinction the socket layer genuinely lacks.
3. **States 3 (unrecoverable / workspace reset) and 4 (successful-resume notice) are NOT rendered at all** today (grep of `chat-surface.tsx` for unrecoverable/reclaim/resume-CTA returns zero) — genuinely net-new render branches per the `.pen`.

This plan adds a **minimal connection slice to `chatReducer`** — one new sticky-terminal value plus a small precedence selector — fed by a new `connection_change` `ChatAction` dispatched from the hook's socket lifecycle handlers (auth_ok/onclose) and the abort signals, and implements the three deferred acceptance criteria:

- **AC10 — Flap idempotency (latest-wins):** rapid disconnect→reconnect→disconnect renders exactly one connection-state banner reflecting the *latest* transition; no stacked/duplicated banners.
- **AC11 — Grace-boundary single terminal state:** within the `DISCONNECT_GRACE_MS` window, an abort-vs-reattach outcome renders exactly one terminal state. After an abort (grace expired → `session_ended`/`stream_replay status:"incomplete"`), the UI MUST NOT flip from State 3 (unrecoverable) to State 4 (successful resume) — no 3→4 flip.
- **AC12 — Connection precedence over activity:** when connection state is "lost/reconnecting", it takes precedence over the activity watchdog; **State 1 and State 2 never render simultaneously**.

The design decision that anchors the whole plan: **the connection-state input is a `chatReducer` `ChatAction` (`connection_change`), NOT a new `StreamEvent`/`WSMessage` variant.** `StreamEvent` is the server→client wire union consumed by the *pure* `applyStreamEvent`; connection lifecycle is a client-local observation (socket onclose has no `WSMessage`). Adding it as a `ChatAction` keeps `applyStreamEvent` untouched (it is timer/IO-free — it returns `timerAction` *descriptors*, never fires timers; it does call `crypto.randomUUID()` for message IDs, so "pure" here means "no connection-state coupling, no new side effects", not strict referential transparency), and co-locates the new slice with the existing client-owned ambient slices (`streamState`, `workflow`). This avoids widening the wire protocol or the `StreamEvent` exhaustiveness rail.

**Scope-minimality decision (post-review):** rather than a parallel 4-value `ConnectionPhase` enum duplicating `ConnectionStatus`, the slice adds the *minimum* the existing `status` lacks — a single sticky-terminal value. The connection slice is `{ phase: "live" | "reconnecting" | "unrecoverable" }`: `reconnecting` drives the existing State-1 banner (rewired through the precedence selector), `unrecoverable` is the new sticky State-3 value, `live` is the default. **State 4 (the brief "Continuing…/workspace restored" notice) is DERIVED, not a phase** — it is a transient render affordance shown when a `resume_stream` reattach completed without `incomplete`/`session_ended`; it has no invariant that must survive in reducer state, so modeling it as a phase (with a fragile `terminal_resumable → live` two-step dispatch) is rejected as over-engineering.

## Research Reconciliation — Spec vs. Codebase

The issue body and feature description are accurate. No spec.md exists for this branch (the spec dir `knowledge-base/project/specs/feat-one-shot-5282-reconnect-state-machine-hardening/` is empty); the GitHub issue #5282 is the canonical input. Reconciliation of the cited premises against `origin/main`:

| Claim (issue / feature desc) | Codebase reality (verified) | Plan response |
|---|---|---|
| "#5240 v1 has merged" | #5240 is an **issue** (OPEN umbrella). v1 shipped as **PR #5256** — `10b8c308a feat(session-resume): verified workspace rebind + honest status (FR1/FR4, #5240) (#5256)`. Merged. | Premise holds. Prereq satisfied. |
| "#5273 (stream-since-disconnect) has merged" | #5273 issue **CLOSED**; shipped as **PR #5290** — `5c908a8a6 feat(session-resume): stream-since-disconnect replay buffer (#5273) (#5290)`. Merged. | Premise holds. The `resume_stream`/`stream_replay status:"incomplete"` protocol is live in `ws-client.ts:1014-1024` + `ws-handler.ts`. AC11 binds to it. |
| "watchdog currently tracks only a single `retrying` activity flag (chat-state-machine.ts)" | Confirmed. `retrying?: boolean` on `ChatMessageBase` (`chat-state-machine.ts:50`), set/cleared by `applyTimeout` (`:1080-1123`) + `tool_progress` arm (`:515-527`). No connection-state slice anywhere in the reducer. | Premise holds. This plan adds the missing connection slice. |
| "Wireframes at …reconnect-resume-states.pen (4 states)" | Exists, 44,665 bytes / 1,133 lines, valid Pencil JSON. Frames: State 1 "Connection lost (reconnecting)", State 2 "No activity for 45s (stuck watchdog)", State 3 "Unrecoverable / workspace reset (KEY)", State 4 "Successful resume". | Premise holds. UX gate (Phase 2.5) satisfied by the existing `.pen`; this plan references it, does not regenerate it. |

**Premise Validation note:** All four cited references checked. #5282 OPEN, #5256 (v1) merged, #5290 (#5273) merged, `chat-state-machine.ts` + `.pen` present. No stale premises. The cited mechanism (connection-state input to the reducer) is novel — grep of `knowledge-base/engineering/architecture/decisions/` found no ADR rejecting a client-side reducer connection slice; the nearest ADR-059 (referenced in `ws-handler.ts:2766`) governs the grace-expiry replay-buffer clear, which this plan consumes, not contradicts.

## User-Brand Impact

**If this lands broken, the user experiences:** during a brief network flap, the chat stacks two contradictory banners ("Connection lost" + "No response yet" at once), or — worse for AC11 — after their workspace was unrecoverably reset (State 3) the UI flips to a green "Successfully resumed" (State 4) and the user trusts a session that is actually gone, losing the work they were watching stream.

**If this leaks, the user's data is exposed via:** N/A — this is a pure client-side UI state machine. It reads no PII, writes no storage, touches no schema/auth/API route. No new data exposure vector.

**Brand-survival threshold:** single-user incident. A single user seeing the chat lie about whether their session survived a reconnect is a trust-destroying event for an agent product whose entire value is "the agent is working for you." This is the same honesty surface #5240 v1 was filed to protect; #5282 hardens its edges.

CPO sign-off required at plan time before `/work` begins (carried forward from #5240's brainstorm framing — same brand-honesty surface). `user-impact-reviewer` will be invoked at review-time per the review SKILL conditional-agent block.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Connection slice exists.** `ChatState` (in `ws-client.ts`, currently 5 named fields + 1 optional at L206-226) carries a new `connection: { phase: ConnectionPhase }` slice (see FR1). `tsc --noEmit` passes; every `ChatState` literal in `test/**` is updated — ~18 sites construct one (`grep -rn "streamState:" apps/web-platform/test/` ≈ 18), but use `tsc --noEmit` TS2741 as the canonical enumerator, not the grep count (per `2026-05-07-tdd-ts-expect-error-sweep-and-reducer-fixture-sweep.md`). Verify: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [x] **AC2 — `connection_change` action.** A new `ChatAction` variant `{ type: "connection_change"; phase: ConnectionPhase }` is handled by `chatReducer`; `applyStreamEvent` (`chat-state-machine.ts`) is NOT modified. Verify: `git grep -n '"connection_change"' apps/web-platform/lib/ws-client.ts` returns ≥1; `git diff origin/main -- apps/web-platform/lib/chat-state-machine.ts` shows no `connection` field added to `StreamEventResult`/`applyStreamEvent`.
- [x] **AC3 — Hook dispatches connection_change.** The hook dispatches `connection_change` from the socket lifecycle handlers and abort signals: auth_ok reattach success (`:714-736`) → `live`; onclose transient (`:1105-1110`) → `reconnecting`; onclose non-transient (`:1088`) → `unrecoverable`; `session_ended` after grace (`:858-896`) → `unrecoverable`; `stream_replay status:"incomplete"` (`:1014-1024`) → `unrecoverable`. Verify: `git grep -n 'connection_change' apps/web-platform/lib/ws-client.ts` shows dispatches at these sites.
- [x] **AC4 (flap idempotency / latest-wins).** Reducer test: dispatching `connection_change` live→reconnecting→live→reconnecting leaves `state.connection.phase === "reconnecting"` (latest wins) and the render derives exactly ONE banner. Component test asserts exactly one `data-testid="connection-banner"` in the DOM after a flap sequence — AND that the pre-existing inline `chat-surface.tsx:567` banner has been rewired through the selector (no second, ungated banner). Verify: new tests in `test/chat-state-machine-connection.test.ts` + `test/components/chat/connection-banner.test.tsx` pass.
- [x] **AC5 (grace-boundary single terminal state, no 3→4 flip).** Reducer/component test: once `connection.phase === "unrecoverable"` (set by an abort signal), a *subsequent* `connection_change` to `live`/`reconnecting` is a **no-op** (sticky guard, FR3). The ONLY reset is the new narrow `reset_connection` action dispatched on explicit user new-turn (`sendMessage`, `ws-client.ts:1446`) — NOT `clear_streams` (which fires on every reconnect; see FR3). Verify: test `"AC11: unrecoverable is sticky across reconnect; reset only on new turn"` — set unrecoverable, dispatch `connect()`-equivalent `clear_streams`, assert STILL unrecoverable; dispatch `reset_connection`, assert `live`. Component test asserts render shows State 3 (resume CTA), never State 4, after abort→reattach.
- [x] **AC6 (connection precedence; states 1 & 2 mutually exclusive).** Pure selector `deriveReconnectView({ phase, hasRetryingBubble })` returns a 3-variant view `none | connection_lost | no_activity`; when `phase === "reconnecting"` it returns `connection_lost` (State 1) regardless of `hasRetryingBubble`. Component test asserts: `screen.queryByTestId("connection-banner")` present ⟹ `screen.queryByTestId("retrying-chip")` absent. Verify: test `"AC12: connection precedence over activity"` passes. (State 3 `unrecoverable` and the derived State-4 notice are SEPARATE render branches, not part of this 3-variant precedence union — they don't participate in the State-1-vs-State-2 conflict.)
- [x] **AC7 (wireframe state-1-vs-state-2 split + State 3/4 rendered).** State 1 = the EXISTING `chat-surface.tsx:567-580` banner, REWIRED to render via `deriveReconnectView` (gains `data-testid="connection-banner"`; the hardcoded `status === "reconnecting"` condition at :567 and the `:891` "Reconnecting…" text are replaced/reconciled so State 1 renders exactly once). State 2 = existing `RetryingChip` unchanged. State 3 (unrecoverable, resume-CTA "Resume with full context") + State 4 (derived "Continuing…/workspace restored" notice) are NEW render branches per `.pen`. Verify: `git grep -n 'data-testid="connection-banner"' apps/web-platform/components/chat/` returns exactly 1; `git grep -nc 'Connection lost. Reconnecting' apps/web-platform/components/chat/chat-surface.tsx` returns 1 (not 2 — no duplicate). Copy matches `.pen` `content` nodes verbatim.
- [x] **AC8 (exhaustiveness rails widened).** The new `ConnectionPhase` enum and the `deriveReconnectView` return union each have a `const _exhaustive: never` rail. `chatReducer`'s `ChatAction` switch ALREADY has a `never` rail (`ws-client.ts:379-385`) — do not add a duplicate; the new `connection_change`/`reset_connection` arms land inside it. Verify: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0; temporarily removing one `ConnectionPhase` case in `deriveReconnectView` makes tsc fail (then restore).
- [x] **AC9 (dual-path lifecycle coverage).** Per learning `knowledge-base/project/learnings/integration-issues/2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`: the `connection_change` dispatches live in the socket handlers (auth_ok/onclose) + abort-signal handlers, which are path-independent. Both the legacy and cc-soleur-go initial-message paths funnel through the single `sendMessage` callback (`ws-client.ts:1446`); the `reset_connection` dispatch (FR3) MUST be wired into that single `sendMessage` so it fires for BOTH paths. Verify: `git grep -n 'connection_change\|reset_connection' apps/web-platform/lib/ws-client.ts` shows connection_change only in socket/abort handlers, and reset_connection only in `sendMessage` — neither gated behind a per-path branch.
- [x] **AC10 (no behavior regression).** Existing reducer + ws tests stay green: `test/chat-state-machine.test.ts`, `test/chat-reducer.test.ts`, `test/ws-streaming-state.test.ts`, `test/ws-reconnect-cleanup.test.ts`. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/chat-reducer.test.ts test/ws-streaming-state.test.ts test/ws-reconnect-cleanup.test.ts` exits 0.

### Post-merge (operator)

- [x] **AC11 — Dark-launch verification.** None required beyond CI; pure client-side change ships behind the existing chat surface. No migration, no infra, no feature flag. (See `## Infrastructure (IaC)` — N/A.)

## Implementation Phases

> TDD throughout (`cq-write-failing-tests-before`): write the failing reducer test for each AC, then implement. Typecheck = `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Tests = `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.

### Phase 0 — Preconditions (grep-verify before coding)

1. `grep -n "case " apps/web-platform/lib/chat-state-machine.ts` — re-confirm the 16 `applyStreamEvent` arms (NOT adding a case here; the module stays untouched). Per `2026-05-13-plan-verify-reducer-case-arms-with-grep`.
2. `grep -n "case " apps/web-platform/lib/ws-client.ts` within `chatReducer` (lines 254-388) — enumerate the existing `ChatAction` arms; the new `connection_change`/`reset_connection` arms land alongside `clear_streams`/`enter_stopping`.
3. **Enumerate ALL 5 `clear_streams` dispatch sites** (`grep -n 'clear_streams' apps/web-platform/lib/ws-client.ts` → :552 teardown, :589 `connect()` every-reconnect, :781 error, :859 session_ended, :1003 revoked) and classify each: does it represent a *user-initiated new turn* (→ should reset connection) or *socket churn / terminal abort* (→ must NOT reset connection)? This is the load-bearing AC11 step — `clear_streams` at :589 fires on every reconnect, so it CANNOT be the connection-reset hatch.
4. Read `ws-client.ts:32` (`ConnectionStatus`), `:417-487` (lifecycle refs), `:714-736` (auth_ok), `:1014-1024` (`stream_replay incomplete`), `:858-896` (`session_ended`), `:1043-1117` (onclose), `:1446` (`sendMessage` — the single unified send path for BOTH legacy and cc-soleur-go). Confirm the transition sites.
5. **Read the EXISTING State-1 banner** at `chat-surface.tsx:567-580` (`status === "reconnecting"` → "Connection lost. Reconnecting…" + "Retry now") and the `:891` "Reconnecting…" text. This is a REWIRE target, not a greenfield component.
6. Read `.pen` `content` nodes for State 1/2/3/4 copy (`grep -oE '"content"[[:space:]]*:[[:space:]]*"[^"]+"' …reconnect-resume-states.pen`) — confirmed copy: State 1 "Connection lost. Reconnecting…" / "Your place is held. Nothing was lost."; State 2 "No response for 45 seconds." / "Keep waiting" / "Stop the turn"; State 3 "Resume with full context"; State 4 "— Continuing from … · workspace restored —".
7. `cd apps/web-platform && ./node_modules/.bin/vitest run` baseline — green before changes.

### Phase 1 — Connection-state slice + actions (TDD)

- **FR1 — `ConnectionPhase` enum + `ChatState.connection` slice (minimal).** Define `ConnectionPhase = "live" | "reconnecting" | "unrecoverable"` (3 values — the minimum the existing `ConnectionStatus` lacks; State 4 is DERIVED, not a phase). Add `connection: { phase: ConnectionPhase }` to `ChatState` (`ws-client.ts:206-226`), initial `{ phase: "live" }`. **Classify every enum value's behavior in every consumer** (per `2026-05-12-plan-precondition-and-3-value-enum-gate-drift`). Document the explicit mapping from `ConnectionStatus` transitions → `connection_change` phase so the two enums don't silently drift.
  - Files: `apps/web-platform/lib/ws-client.ts`.
- **FR2 — `connection_change` action + latest-wins arm (AC4).** Add `{ type: "connection_change"; phase: ConnectionPhase }` to `ChatAction`; `chatReducer` arm sets `state.connection.phase = action.phase` UNCONDITIONALLY (latest-wins idempotency = no banner stacking; the slice holds exactly one phase) EXCEPT the sticky guard (FR3).
  - Files: `apps/web-platform/lib/ws-client.ts` (ChatAction union ~L231-252, `chatReducer` ~L254).
  - Test (RED→GREEN): `test/chat-state-machine-connection.test.ts` — `connection_change` ×4 alternating leaves `phase` = last value.
- **FR3 — Sticky `unrecoverable` + narrow `reset_connection` (AC5 / AC11 no 3→4 flip).** Once `phase === "unrecoverable"`, a subsequent `connection_change` to `live`/`reconnecting` is a **no-op**. The ONLY escape is a NEW dedicated action `{ type: "reset_connection" }` that resets `connection` to `{ phase: "live" }`, dispatched ONLY from `sendMessage` (`ws-client.ts:1446`, the explicit user-new-turn entry shared by both paths). **`clear_streams` MUST NOT reset `connection`** — it fires on every reconnect via `connect()` (`:589`) and from the abort handlers themselves (`:859`), so coupling the reset to it would defeat the sticky guard entirely (the grace-window late-reattach frame would flip State 3 → State 4). **Document the load-bearing sub-value** inline (per `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate`): the sticky guard exists precisely because socket `status` flips back to `connected` on reattach and cannot express terminal-after-grace.
  - Files: `apps/web-platform/lib/ws-client.ts` (`chatReducer` `connection_change` arm with sticky guard; new `reset_connection` arm; `sendMessage` dispatches `reset_connection`). Leave the 4 abort/churn `clear_streams` sites untouched re: connection.
  - Test: `"AC11: unrecoverable sticky across reconnect; reset only on new turn"` — set unrecoverable, dispatch `clear_streams`, assert STILL unrecoverable; dispatch `reset_connection`, assert `live`.

### Phase 2 — Hook dispatch wiring (AC3 / AC9)

- **FR4 — Dispatch `connection_change` from socket lifecycle + abort handlers.** In `ws-client.ts`:
  - `auth_ok` reattach success (`:714-736`): dispatch `live` (the sticky guard makes this a no-op if already `unrecoverable` — that is the AC11 abort-then-reattach case).
  - `onclose` transient (`:1105-1110`): dispatch `reconnecting` (State 1).
  - `onclose` non-transient (`:1088`, `NON_TRANSIENT_CLOSE_CODES`): dispatch `unrecoverable` (State 3).
  - `session_ended` after grace (`:858-896`) + `stream_replay status:"incomplete"` (`:1014-1024`): dispatch `unrecoverable` (grace expired, replay gone → honest unrecoverable, never a stale-resume lie). These are the AC11 abort signals. **Dispatch `connection_change` AFTER the existing `clear_streams` in the `session_ended` handler** (clear_streams runs first at :859 and must not touch connection per FR3).
  - **AC9 dual-path:** these dispatches live in the shared socket handlers (path-independent); the `reset_connection` (FR3) lives in the shared `sendMessage`. Both paths covered without per-path branching.
  - Files: `apps/web-platform/lib/ws-client.ts`.
  - Test: `test/ws-reconnect-cleanup.test.ts` (extend) — dispatch sequences for transient-close, non-transient-close, `session_ended`-after-grace, `stream_replay incomplete`.
- **FR5 — State 4 (successful-resume notice) is DERIVED, not a phase.** When a `resume_stream` reattach completes without `incomplete`/`session_ended`, set a short-lived render affordance (a `resumedAt` timestamp on the connection slice, or a transient flag the component dismisses on a timer) so the State-4 "— Continuing… · workspace restored —" notice shows briefly. This avoids the rejected `terminal_resumable → live` two-step dispatch (which had no reliable "live frames now flow" edge — replay frames are dedup-gated at `:705-711` and a resume may replay zero frames). State 4 is reachable ONLY from `reconnecting`-then-resume, NEVER from `unrecoverable` (sticky guard enforces this). If a `resumedAt` field is added to the slice, include it in the AC1 fixture sweep.
  - Files: `apps/web-platform/lib/ws-client.ts` (auth_ok reattach branch), `apps/web-platform/components/chat/chat-surface.tsx` (derive + render the notice).

### Phase 3 — Render derivation + State-1 rewire (AC6 / AC7 / AC12)

- **FR6 — `deriveReconnectView` pure selector (AC12 precedence).** A pure function `deriveReconnectView({ phase, hasRetryingBubble }): ReconnectView` where `ReconnectView` is a **3-variant** union `{ kind: "none" } | { kind: "connection_lost" } | { kind: "no_activity" }`. **Precedence rule:** if `phase === "reconnecting"` → `connection_lost` (State 1), regardless of `hasRetryingBubble`; else if `hasRetryingBubble` → `no_activity` (State 2); else `none`. State 1 and State 2 derive from the SAME selector → cannot co-occur (AC12). `const _exhaustive: never` rail over `ConnectionPhase`. (State 3 `unrecoverable` and the derived State-4 notice are SEPARATE render branches in `chat-surface.tsx`, not in this precedence union — they don't conflict with the chip.)
  - Files: `apps/web-platform/lib/chat-state-machine.ts` (pure, unit-testable in the node project).
  - Test: `test/chat-state-machine-connection.test.ts` — truth table over all `ConnectionPhase × hasRetryingBubble`; assert connection_lost ⟹ ¬no_activity.
- **FR7 — Rewire the EXISTING State-1 banner; add State 3/4 branches.** REWIRE `chat-surface.tsx:567-580`: replace the inline `status === "reconnecting"` condition with `deriveReconnectView(...).kind === "connection_lost"`, add `data-testid="connection-banner"` and `aria-live="polite"`, keep the existing `.pen`-matching copy ("Connection lost. Reconnecting…" + "Retry now"). Reconcile the `:891` "Reconnecting…" text so State 1 renders exactly ONCE (no duplicate banner — the P0 risk). State 2 = existing `RetryingChip` unchanged. ADD State 3 (unrecoverable: "Resume with full context" CTA, "View conversation") and State 4 (derived "Continuing… · workspace restored" notice) render branches per `.pen` frames 3/4. **Do NOT create a separate `connection-banner.tsx` greenfield component** — extract the existing JSX if a component boundary aids testability, but the copy already lives in the file and already matches the `.pen`.
  - Files: `apps/web-platform/components/chat/chat-surface.tsx` (rewire :567 banner, reconcile :891, add State 3/4 branches).
  - Test: `test/components/chat/connection-banner.test.tsx` — exactly one banner after flap (AC4); banner ⟹ no retrying-chip (AC12); no 3→4 flip render (AC5).

### Phase 4 — Sweep + exhaustiveness + regression (AC1/AC8/AC10)

- **FR8 — Fixture + directive sweep.** `grep -rn "ChatState\b" apps/web-platform/test/` and update every `ChatState` literal/fixture with the new `connection` field; remove now-stale `@ts-expect-error` directives (per `2026-05-07-tdd-ts-expect-error-sweep`). `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` must be the canonical enumerator of broken sites (TS2741), not a grep count.
- **FR9 — Full reducer + ws suite green.** Run the AC10 suite + the new connection suites. Confirm no regression in `streamState`, `workflow`, `spawnIndex` slices.

## Domain Review

**Domains relevant:** Product (UI honesty surface), Engineering (CTO — state-machine architecture)

### Engineering (CTO)

**Status:** reviewed (carried forward from #5240 brainstorm framing — same reconnect/honesty surface; CTO architectural framing already established v1's "no fabricated state" principle)
**Assessment:** The connection-state-as-`ChatAction` (not `StreamEvent`) decision keeps `applyStreamEvent` untouched and avoids wire-protocol widening — architecturally sound (confirmed by architecture-strategist deepen-review). Two P0 corrections were applied post-review: (1) the sticky-`unrecoverable` escape hatch is a dedicated `reset_connection` from `sendMessage`, NOT `clear_streams` (which fires every reconnect and would defeat AC11); (2) State 1 is a REWIRE of the existing `chat-surface.tsx:567` banner, not a greenfield component (avoids the duplicate-banner failure AC10 targets). Simplicity-review collapsed the enum to 3 values and made State 4 a derived render affordance (not a phase). Dual-path (legacy + cc-soleur-go) coverage is satisfied because both connection-lifecycle dispatches (shared socket handlers) and the `reset_connection` (shared `sendMessage` :1446) are path-independent — AC9 verifies explicitly per the 2026-06-14 dual-path learning.

### Product/UX Gate

**Tier:** blocking (chat interface — UI surface; mechanical override fires on `components/chat/*.tsx` files)
**Decision:** auto-accepted (pipeline) — wireframe already exists
**Agents invoked:** none (wireframe pre-exists; pipeline path)
**Skipped specialists:** none — `ux-design-lead` is N/A as a *producer* because `knowledge-base/product/design/chat/reconnect-resume-states.pen` already exists (44,665 bytes, 4 states) and is the spec for this work. The verifier invariant (`.pen` exists on disk, non-empty, referenced in FRs) is satisfied: FR7 + AC7 bind State-1/2/3/4 copy to the `.pen` frames.
**Pencil available:** N/A (no new wireframe needed; existing `.pen` is the producer artifact)

#### Findings

The `.pen` is the authoritative source for State 1/2/3/4 copy and visual treatment. FR7/AC7 require the State-1 banner copy to match the `.pen` State-1 frame verbatim. No new design artifact required; this is implementation of an already-designed flow.

## Infrastructure (IaC)

N/A — pure client-side TypeScript change. No server, service, cron, secret, DNS, cert, or firewall rule introduced. Files touched are all under `apps/web-platform/lib/` and `apps/web-platform/components/`. Phase 2.8 IaC gate: no trigger phrases present. Skipped.

## Observability

```yaml
liveness_signal:
  what: "N/A — client-side UI state machine; no server liveness surface introduced. Connection-state transitions are observable in the user's own browser DevTools console (existing ws-client log lines) and in Sentry breadcrumbs from the existing ws-client error path."
  cadence: "per socket lifecycle event (onopen/onclose/auth_ok)"
  alert_target: "none (no new server signal)"
  configured_in: "apps/web-platform/lib/ws-client.ts (existing log.info/log.warn calls on connection transitions)"
error_reporting:
  destination: "Sentry (existing ws-client client-side error boundary + lastError state); no new error path — the new reducer arm is a pure state assignment that cannot throw."
  fail_loud: "true — a malformed connection_change (impossible: typed enum) would surface as a tsc error at build, not a runtime silent failure."
failure_modes:
  - mode: "Sticky-`unrecoverable` guard pruned, OR `clear_streams` wired to reset connection (3→4 flip regression returns)"
    detection: "regression test test/chat-state-machine-connection.test.ts 'AC11: unrecoverable sticky across reconnect; reset only on new turn'"
    alert_route: "CI vitest failure on PR"
  - mode: "Duplicate State-1 banner (rewired :567 banner + a second ungated render) stacks during flap (AC10 regression)"
    detection: "component test connection-banner.test.tsx 'exactly one banner after flap' + AC7 grep -c 'Connection lost. Reconnecting' == 1"
    alert_route: "CI vitest failure on PR"
  - mode: "State 1 + State 2 render simultaneously (AC12 regression)"
    detection: "deriveReconnectView 3-variant truth-table test + component mutual-exclusion assertion"
    alert_route: "CI vitest failure on PR"
logs:
  where: "browser console via existing ws-client structured logs; no server log surface added"
  retention: "client-session only (ephemeral); Sentry breadcrumbs per existing client config"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine-connection.test.ts test/components/chat/connection-banner.test.tsx"
  expected_output: "all tests pass (0 failures); the three regression-mode tests above are the discoverability surface for the AC10/AC11/AC12 invariants"
```

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` against the planned files (`apps/web-platform/lib/ws-client.ts`, `apps/web-platform/lib/chat-state-machine.ts`, `apps/web-platform/components/chat/chat-surface.tsx`). No open scope-out names these files. (Re-run the two-stage `gh --json` then `jq --arg` query at /work Phase 0 to re-confirm against current backlog.)

## Files to Edit

- `apps/web-platform/lib/ws-client.ts` — `ConnectionPhase` 3-value enum, `ChatState.connection` slice + initial state (+ optional `resumedAt` if State 4 uses a timestamp, FR5), `ChatAction` `connection_change` + `reset_connection` variants, `chatReducer` arms (latest-wins + sticky-`unrecoverable` guard; `reset_connection` resets to `live`), `reset_connection` dispatch in `sendMessage` (`:1446`), `connection_change` dispatch wiring in auth_ok (`:714`), onclose transient/non-transient (`:1088`/`:1105`), `session_ended` (`:858`), `stream_replay incomplete` (`:1014`). **`clear_streams` is NOT modified to touch connection** (FR3 — it fires every reconnect at `:589`).
- `apps/web-platform/lib/chat-state-machine.ts` — `deriveReconnectView` pure selector + 3-variant `ReconnectView` union + `_exhaustive` rail over `ConnectionPhase` (`applyStreamEvent` UNCHANGED). Update the `retrying` JSDoc at L40-50 to reference that connection-state now lives in the reducer slice (resolves the "flag name retained pending #5282" note).
- `apps/web-platform/components/chat/chat-surface.tsx` — **REWIRE the existing State-1 banner at `:567-580`** (replace `status === "reconnecting"` with `deriveReconnectView(...).kind === "connection_lost"`, add `data-testid="connection-banner"` + `aria-live="polite"`, keep existing copy), reconcile the `:891` "Reconnecting…" text so State 1 renders ONCE, add NEW State 3 (resume-CTA) + State 4 (derived "Continuing…" notice) branches per `.pen`. Also reconcile the `status === "reconnecting"` `useEffect` at `:351-355` if it drove the old banner.
- `apps/web-platform/test/chat-reducer.test.ts` — fixture sweep for new `connection` slice.
- `apps/web-platform/test/ws-reconnect-cleanup.test.ts` — extend with `connection_change`/`reset_connection` dispatch-sequence assertions.
- Any other `test/**` file with a `ChatState` literal (~18 sites by `grep -rn "streamState:" apps/web-platform/test/`; enumerated authoritatively via `tsc --noEmit` TS2741).

## Files to Create

- `apps/web-platform/test/chat-state-machine-connection.test.ts` — unit (node project, `test/**/*.test.ts` glob): latest-wins flap, sticky-`unrecoverable` + `reset_connection`-only escape, `deriveReconnectView` 3-variant truth table.
- `apps/web-platform/test/components/chat/connection-banner.test.tsx` — component (happy-dom project, `test/**/*.test.tsx` glob): exactly-one-banner after flap (no duplicate of the rewired :567 banner), State1⟹¬State2 mutual exclusion, no 3→4 flip render. (Path under `test/` — vitest `component` project collects `test/**/*.test.tsx`; a co-located `components/**/*.test.tsx` would be SKIPPED.)
- (NO new `connection-banner.tsx` component — State 1 is a rewire of the existing `chat-surface.tsx:567` banner, not a greenfield component. If a component boundary aids testability, extract the EXISTING JSX as-is.)

## Test Scenarios

| AC | Test | Type | File |
|---|---|---|---|
| AC4 | flap live→reconnecting→live→reconnecting ⇒ phase=reconnecting, exactly one banner (no duplicate) | unit + component | chat-state-machine-connection / connection-banner |
| AC5/AC11 | `unrecoverable` sticky across `clear_streams` (reconnect); reset only via `reset_connection`; abort→reattach renders State 3 not State 4 | unit + component | both |
| AC6/AC12 | `deriveReconnectView` 3-variant truth table; connection_lost ⟹ ¬no_activity | unit + component | both |
| AC7 | rewired State-1 banner renders once with `.pen` copy; State-2 RetryingChip unchanged; State 3/4 branches present | component | connection-banner |
| AC9 | connection_change only in socket/abort handlers; reset_connection only in shared `sendMessage` (path-independent) | unit | ws-reconnect-cleanup |
| AC10 | existing reducer/ws suites stay green | unit | (existing) |

## Risks & Mitigations

- **R1 (P0) — `clear_streams` as escape hatch defeats AC11.** `clear_streams` fires on EVERY reconnect (`connect()` at `:589`) and from the abort handlers themselves (`session_ended` :859). If it reset `connection`, the sticky guard would be cleared on the next reconnect and a late reattach frame would flip State 3 → State 4. Mitigation: a DEDICATED `reset_connection` action dispatched ONLY from `sendMessage` (user new turn); `clear_streams` left untouched re: connection. The 5 `clear_streams` sites are classified at Phase 0 step 3.
- **R2 (P0) — Duplicate State-1 banner.** A State-1 "Connection lost. Reconnecting…" banner ALREADY exists at `chat-surface.tsx:567-580` (+ `:891` text). Adding a parallel component without reconciling produces two banners — the exact "stacked banner" failure AC10 targets. Mitigation: FR7 REWIRES the existing banner through the selector and reconciles `:891`; AC7 verifies `grep -c 'Connection lost. Reconnecting'` returns 1.
- **R3 — Sticky guard pruned as "redundant".** Mitigation: inline comment naming the load-bearing sub-value (socket `status` flips back to `connected` on reattach; the guard is what makes terminal-after-grace expressible) + AC11 regression test (per `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate`).
- **R4 — Enum widening drift.** New `ConnectionPhase` member added later without updating `deriveReconnectView`. Mitigation: `const _exhaustive: never` rail over `ConnectionPhase`; `cq-union-widening-grep-three-patterns` at /work.
- **R5 — Fixture sweep miss.** Mitigation: trust `tsc --noEmit` TS2741 as the enumerator, not a grep count (per `2026-05-07-tdd-ts-expect-error-sweep`).
- **R6 — `streamState` left stale at terminal.** Entering `unrecoverable` mid-`streaming` could leave `streamState === "streaming"` (Send button disabled under an unrecoverable banner — a new contradictory-state class). Mitigation: the abort handlers (`session_ended`/non-transient close) already dispatch `clear_streams` which resets `streamState` to `"idle"` atomically (`:307-314`); FR4 dispatches `connection_change(unrecoverable)` AFTER that `clear_streams`, so streamState is already idle when connection goes terminal. Verify the ordering in the `session_ended` handler at /work.
- **R7 — `ConnectionStatus` vs `ConnectionPhase` drift.** The hook keeps its 4-value socket `ConnectionStatus`; the new 3-value `ConnectionPhase` adds the `unrecoverable` value the socket status lacks. Mitigation: FR1 documents the explicit `ConnectionStatus` transition → `connection_change` phase mapping inline; keep the slice enum separate (the socket status has no "unrecoverable" concept — a UI-honesty distinction, not a socket fact).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled: threshold = single-user incident.)
- **A State-1 banner ALREADY EXISTS at `chat-surface.tsx:567-580`.** This work REWIRES it; it does NOT create a new `connection-banner.tsx`. Creating a parallel component duplicates the banner.
- **`clear_streams` MUST NOT be the connection-reset hatch** — it fires on every reconnect (`:589`). Use the dedicated `reset_connection` from `sendMessage` only.
- `applyStreamEvent` stays untouched — connection state is a `ChatAction`, NOT a `StreamEvent`/`WSMessage` variant. Do not add a `connection` field to `StreamEventResult`. ("Pure" = no connection coupling / no new side effects; it does call `crypto.randomUUID()` for IDs, so it is not strictly referentially transparent — the constraint is "don't touch it".)
- Component test MUST live at `test/components/chat/*.test.tsx` (collected by vitest `component` project glob `test/**/*.test.tsx`). A co-located `components/chat/*.test.tsx` is silently skipped.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT `npm run -w` (no root `workspaces` field). Test runner is vitest — NOT bun (`bunfig.toml` `pathIgnorePatterns=["**"]`).
- State copy must match the `.pen` `content` nodes verbatim (confirmed at Phase 0 step 6); do not paraphrase from memory.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Add `connection_state` as a new `WSMessage`/`StreamEvent` variant | The socket onclose has no `WSMessage` — connection lifecycle is a client-local observation, not a server frame. Would couple the wire union to client socket state and force a fabricated frame. Rejected. |
| Make `clear_streams` the sticky-terminal escape hatch | `clear_streams` fires on every reconnect (`connect()` :589) and from abort handlers (:859), so it would clear the sticky guard exactly when AC11 needs it held. Rejected in favor of a dedicated `reset_connection` from `sendMessage`. |
| Parallel 4-value `ConnectionPhase` enum + `terminal_resumable` phase for State 4 | Duplicates the existing `ConnectionStatus`; `terminal_resumable` needs a fragile `→ live` two-step dispatch with no reliable "live frames flow" edge (replay frames are dedup-gated; a resume may replay zero frames). Collapsed to a 3-value enum + DERIVED State-4 notice. Rejected as over-engineering (simplicity review). |
| New greenfield `connection-banner.tsx` component | State-1 banner + copy already exist at `chat-surface.tsx:567`; greenfield duplicates it. Rewire instead. Rejected. |
| Drive State 1/2 from `ConnectionStatus` directly in the component (no reducer slice) | Cannot express sticky-terminal (AC11) — `status` flips back to `connected` on reattach and would flip State 3 → State 4. Rejected. |
| Reuse the per-message `retrying` flag for connection state | That conflation is exactly what #5282 fixes. Rejected. |

## Deferral Tracking

None deferred. All three deferred ACs (AC10/AC11/AC12 from #5240 v1) + the wireframe state split are implemented in this plan. No new out-of-scope items requiring tracking issues.
