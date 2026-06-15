---
title: "fix: false-positive 'Agent stopped responding' — leader-liveness watchdog reset"
type: fix
date: 2026-06-15
branch: feat-one-shot-5240-watchdog-liveness-reset
parent_epic: 5240
app: web-platform
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: false-positive "Agent stopped responding after: <label>" while leader is provably alive

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Desired Fix (mechanism + ceiling), Files to Edit, Acceptance Criteria, Test Scenarios,
Alternatives, Sharp Edges, User-Brand Impact, Observability.
**Review agents used:** architecture-strategist, code-simplicity-reviewer, test-design-reviewer,
user-impact-reviewer (all 4 converged on the same load-bearing flaw).

### Key Improvements (v1 → v2)

1. **Bounded re-arm ceiling (`MAX_LIVENESS_REARMS = 3`).** The v1 design could mask a genuinely-hung leader
   FOREVER — a long-lived sibling or a fast debug-emitting leader would perpetually reset a hung leader's
   watchdog (the exact opposite-direction regression the scope guard forbids). All 4 agents flagged this
   P1/HIGH. v2 caps liveness suppression at 3 re-arms (~3.75min), then escalates regardless of any sibling.
2. **Debug heartbeat scoped to `activeStreams.size === 1`** (was `> 0`). At ≥2 leaders a debug `tool_use` is
   unattributable; resetting all leaders there reintroduced the masking hole. Single-leader is unambiguous;
   multi-leader liveness now flows through the bounded cross-leader gate only.
3. **Re-arm `timerAction` contract pinned** to `{ type: "reset", leaderId }` (was "implementer's call") —
   never `undefined` (would never re-arm → permanent suppression), never `reset_all` (would reset the
   sibling's timer too).
4. **`reset_all` iterates the live timer Map**, not `chatState.activeStreams` (symmetry with
   `clearAllTimeouts`; removes a cross-state-slice read). `applyTimeout`'s return union is NOT widened.
5. **Single-leader heartbeat also clears `retrying`** (mirror `tool_progress`) so the stale "No response
   yet" chip doesn't persist on a working turn.
6. **Test coverage tightened:** added AC3b (bounded-ceiling un-masking), AC3c (re-arm-then-all-silent),
   AC7 size>1 + `reasoning` ceiling negatives, AC8b terminal-bubble no-resurrection; pinned AC2 assertions.

### New Considerations Discovered

- A sibling leader being active is NOT proof the in-flight leader is alive — A and its workspace can hang
  independently of B. The bound is what makes "B is active" a safe *grace*, not a *blank check*.
- #5290's merged stream-replay buffer could (in a future path) feed buffered `debug_event`s through the
  reducer post-disconnect; the plan now pins the "debug is live-only" invariant inline.

## Overview

The Concierge chat shows a red **"Agent stopped responding after: {toolLabel}"** error banner on an
in-flight message bubble **even though the agent is demonstrably still working** — the connection badge
reads "Connected" (green), the Debug stream is still emitting tool events, and newer tool chips are still
streaming below the errored bubble.

This is a **residual / regression symptom under parent epic #5240**, NOT covered by the merged v1 (PR #5256)
or the reconnect-hardening follow-ups (#5290 stream-replay, #5299 connection-vs-activity precedence). #5299
gave **connection** state precedence over the activity watchdog (`reconnecting` → "Connection lost…" wins),
but when the connection is `live` the per-message activity watchdog still runs and escalates to `error`.
This plan closes the **"live socket + active work but watchdog still escalates"** path.

**Scope guard:** This is a **UI/state-machine false-positive fix only**. The backend workspace-rebind /
genuine stuck-loop (the deferred #5240 FR-half from the 4826 session) is **out of scope**. The fix must NOT
mask a genuinely-hung turn forever — a turn with zero liveness evidence from any source must still surface
the error eventually (the two-stage 45s watchdog is preserved; we only add liveness inputs that reset it).

This is a NEW focused sub-issue under #5240. Do **not** reopen merged scope.

## Root Cause (verified against branch base @ e62b19bda)

The error banner is the `messageState === "error"` branch in
`apps/web-platform/components/chat/message-bubble.tsx:369-391`
("Agent stopped responding after: {toolLabel ?? 'Working'}").

It is produced by the per-message two-stage stuck-watchdog `applyTimeout` in
`apps/web-platform/lib/chat-state-machine.ts:1083-1126`:
- **Stage 1** (first 45s of silence on a `thinking`/`tool_use` bubble) → set `retrying: true`, keep the
  bubble active, **reset** the watchdog (`timerAction: { type: "reset" }`).
- **Stage 2** (second consecutive 45s timeout, bubble already `retrying`) → transition to `state: "error"`,
  delete the leader from `activeStreams`, **clear** the watchdog.

`STUCK_TIMEOUT_MS = 45_000` (`apps/web-platform/lib/ws-constants.ts:14`).

The timer is **per-leaderId** (`timeoutTimersRef: Map<string, Timeout>` in
`apps/web-platform/lib/ws-client.ts:564`), scheduled/reset by `resetLeaderTimeout` (`ws-client.ts:588-596`)
and driven by `timerAction` intents the reducer emits, applied in the `useEffect` at `ws-client.ts:612-619`
(`reset` → `resetLeaderTimeout`, `clear` → `clearLeaderTimeout`, `clear_all` → `clearAllTimeouts`).

**The watchdog resets ONLY on MAIN-STREAM reducer events keyed to that same leaderId** — `tool_use`
(`:492`), `tool_progress` (`:528`/`:536`), `stream` (`:575`/`:595`), `stream_start` (`:417`),
`command_stream` (`:987`/`:1009`). Two structural gaps make the false positive inevitable:

1. **The Debug stream is a separate channel that resets nothing.** The `debug_event` reducer case
   (`chat-state-machine.ts:1032-1055`) **deliberately emits no `timerAction`**, and `debug_event` carries
   **no `leaderId`** at all (`types.ts:341-346` — "Flat (no leaderId): the panel is a single ordered log").
   So live debug-stream activity — which the operator can SEE proving the agent is alive — never resets the
   watchdog for the in-flight bubble. (Screenshot 1: single bubble errors while the Debug stream still flows.)

2. **Per-message keying means each bubble escalates independently, and an errored bubble is unrecoverable.**
   Once a bubble reaches `error`, `applyTimeout`'s guard (`:1099`) only acts on `thinking`/`tool_use`
   bubbles, the leader is removed from `activeStreams` (`:1110`), and its timer is cleared. Subsequent
   leader activity (newer tool chips / debug events, possibly under a different leaderId) does **not** clear
   a prior bubble's error. (Screenshot 2: bubble A "Working…" and bubble B "Reading …" both stuck in
   `error` while newer chips + a live 141-event Debug stream flow below them.)

**Net:** the watchdog's input set ("same-bubble main-stream `tool_use`") is narrower than its claim ("the
agent stopped responding"). The fix widens the **liveness input set** to any evidence the *leader* is alive,
WITHOUT widening what the error ultimately means (genuinely silent turns still surface).

## Research Reconciliation — Spec vs. Codebase

| Premise (from task framing) | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| Error banner at `message-bubble.tsx:369-390` | Confirmed `:369-391` (`messageState === "error"` branch) | No change to this branch's copy/markup; it stays the honest terminal state. |
| `applyTimeout` ~`:1074-1129` | Confirmed `:1083-1126` | Primary fix surface (the "second consecutive timeout → error" arm). |
| Watchdog resets only on main-stream `tool_use` ~`:488` | Confirmed `:488-492`; also `tool_progress`/`stream`/`stream_start`/`command_stream` | All reset paths are **per-leaderId**; none are global. |
| `deriveReconnectView` ~`:1129-1190`, connection precedence (#5299) | Confirmed `:1174-1195`; `phase: "live"` returns `no_activity` when `hasRetryingBubble` | The selector already reads `phase`. The fix uses `phase === "live"` as the "socket alive" half of the liveness signal. |
| Option (a): feed debug-stream into reducer to reset watchdog | `debug_event` has **no leaderId** | Option (a) can ONLY be a **global** reset (reset every active leader's timer), never per-leader. This is the load-bearing constraint that selects the design (below). |
| Existing single-bubble invariant tests at `chat-state-machine.test.ts:47` + `message-bubble-retry.test.tsx:88` | Confirmed. The state-machine tests assert per-leader reset on `tool_use`/`stream`; the render tests assert that GIVEN `state="error"` the banner renders. | Neither exercises the **debug-liveness** path nor the **cross-leader** path. New RED tests add exactly those orderings. |
| `clear_all` global timer action already exists | Confirmed reducer emits `clear_all` (`:664`,`:699`) and `ws-client.ts:617` handles it via `clearAllTimeouts` | A sibling **`reset_all`** global action fits the existing architecture cleanly — `activeStreams.keys()` already enumerated at `ws-client.ts:479-482`. |

## User-Brand Impact

**If this lands broken, the user experiences:** a red "Agent stopped responding" banner on a turn that is
visibly still working (Debug stream flowing, new chips appearing) — the single most trust-destroying signal
a non-technical operator can see. They will assume the product is broken and the agent crashed, when in
fact it is mid-task. Worse: a *regression* in the opposite direction (suppressing the error forever) would
hide a genuinely hung turn behind a perpetual spinner.

**The opposite-direction regression is explicitly closed (deepen-plan):** the fix must NOT hide a genuinely
hung turn. The `MAX_LIVENESS_REARMS` bounded ceiling guarantees a hung leader escalates within ~3.75min even
when a sibling stays busy or a fast leader spams the debug stream (AC3b). The honest Stage-1 "No response
yet" chip is preserved (and now clears on genuine liveness, AC1), so the user always has SOME during-silence
signal. No flicker/ping-pong (the gate prevents the false `error` from rendering rather than un-erroring
after the fact).

**If this leaks, the user's data/workflow is exposed via:** N/A — no data surface; this is a pure
client-side render/state-machine change. No new persistence, no new network surface, no PII.

**Brand-survival threshold:** `single-user incident` — a single operator seeing a false "stopped responding"
on a working turn is a brand-trust failure. Per `hr-weigh-every-decision-against-target-user-impact`, this
threshold drives the `requires_cpo_signoff: true` frontmatter and the `user-impact-reviewer` at review time.

## Desired Fix (minimal, chosen design)

**Chosen approach: a global LEADER-LIVENESS reset, gated on `connection.phase === "live"`, fed by both
main-stream cross-leader activity AND the debug stream — combined with a Stage-2 liveness re-check so a
bubble cannot escalate to `error` while ANY leader is provably active.**

Rationale for picking this over the alternatives (see "Alternative Approaches Considered"): the task's
option (a) [feed debug events into the reset] and option (b) [clear lingering error on later activity] are
**both** required for the two screenshots, and they share one root mechanism — *the watchdog's per-leader
keying is too narrow*. A single global-liveness primitive satisfies both with one new code path and no
widening of the error's true meaning.

> **[Updated 2026-06-15 — deepen-plan]** The 4-agent review (architecture-strategist, code-simplicity,
> test-design, user-impact) converged on ONE load-bearing flaw in the v1 design: an *unbounded* liveness
> re-arm could **mask a genuinely-hung leader forever** (the opposite-direction regression the scope guard
> forbids). A long-lived sibling leader (10-min build) or a fast leader spamming debug `tool_use` would
> perpetually reset a hung leader's watchdog, so the real hang never surfaces. The mechanism below is the
> revised design: liveness re-arm is **BOUNDED** (a new ceiling, per `2026-05-05-defense-relaxation-must-
> name-new-ceiling.md`), the debug heartbeat is **scoped to the unambiguous single-leader case**, and the
> re-arm `timerAction` contract is **pinned** (no "implementer's call").

### Mechanism (revised — all pure reducer + the existing timer `useEffect`)

The fix has TWO behavioral inputs (debug heartbeat for the single-leader screenshot-1 case; cross-leader
gate for the multi-leader screenshot-2 case) plus ONE shared **bounded re-arm ceiling** that guarantees the
genuine-hang exit survives even under a perpetually-busy sibling.

0. **New per-message `livenessRearms?: number` counter (the ceiling).** Add an optional field to
   `ChatMessageBase` (`chat-state-machine.ts:31-54`, alongside `retrying`). It counts how many times this
   bubble's Stage-2 escalation has been *suppressed* by liveness evidence. Introduce
   `MAX_LIVENESS_REARMS = 3` (a new named constant in `chat-state-machine.ts` or `ws-constants.ts`). Once a
   bubble has been re-armed `MAX_LIVENESS_REARMS` times, the next Stage-2 timeout escalates to `error`
   **regardless** of sibling/debug liveness. At 45s/window this bounds a genuinely-hung leader's
   false-suppression to ≈`(2 + MAX_LIVENESS_REARMS) × 45s ≈ 3.75 min` even while a sibling stays busy —
   the named ceiling that makes "another leader is alive" a *bounded* grace, not a blank check (it is NOT
   proof that THIS leader is alive; A and its workspace can hang independently of B).

1. **Debug-stream heartbeat — scoped to the single active leader (option a).** In the `debug_event`
   reducer case (`chat-state-machine.ts:1032-1055`), emit `timerAction: { type: "reset_all" }` **only when
   `activeStreams.size === 1`** AND `event.kind === "tool_use"`. Rationale (architecture P1): when exactly
   one leader is active, an unattributed debug `tool_use` is unambiguously *that* leader's heartbeat → reset
   is sound. When `size > 1`, debug events cannot be attributed and resetting all leaders is the over-broad
   masking the scope guard forbids — the *cross-leader gate* (piece 2, bounded) is the correct handler
   there, so the debug case stays out of it. This covers screenshot-1 (single bubble, debug-only liveness)
   without reintroducing the multi-leader masking hole.
   - **`reset_all` (not a single-leader `reset`):** debug events carry no `leaderId`
     (`types.ts:341-346`), so even in the `size === 1` case the reducer cannot name the leader to emit a
     `{ type: "reset", leaderId }`. `reset_all` is the minimal primitive for an unattributed heartbeat. With
     the `size === 1` gate it resets exactly one timer.
   - **Also clear `retrying` on the heartbeat** (mirror the existing `tool_progress` behavior at `:518-529`):
     a live heartbeat means the Stage-1 "No response yet" chip is now stale and must clear back to the
     normal tool chip (user-impact FINDING 3), and the bubble's `livenessRearms` resets to 0 (genuine
     liveness, not a grace-suppression). Without this the user would see a permanent "No response yet" on a
     working turn.
   - **Inert when no active stream / `size !== 1`:** avoids resurrecting a `stream_end`ed leader's timer.
   - **Connection gate:** `debug_event` only arrives over a live socket today. **Pin this invariant
     inline** — #5290 (merged) added stream-replay buffering under #5240; a future replay path that fed
     buffered `debug_event`s through the reducer post-disconnect would falsely reset on a dead socket. Add a
     one-line comment asserting debug events are live-only, OR (defensive) read `connection.phase` is not
     available in the pure reducer, so document the invariant rather than gate on it.

2. **Cross-leader liveness BOUNDED-blocks Stage-2 escalation (option b).** Change `applyTimeout`'s Stage-2
   arm (`:1104-1116`): before escalating, check whether **any OTHER leader** (`!== leaderId`) remains in
   `activeStreams` with a bubble in `thinking`/`tool_use`/`streaming` state, AND this bubble's
   `livenessRearms < MAX_LIVENESS_REARMS`. If BOTH hold → **suppress** the escalation: increment
   `livenessRearms`, keep `retrying: true`, and emit **exactly `{ type: "reset", leaderId }`** (NEVER
   `reset_all`, NEVER `undefined` — pinned contract; architecture P1). Otherwise (no sibling active, OR the
   re-arm budget is exhausted) → escalate to `error` and delete the leader from `activeStreams` (unchanged
   terminal path). The `!== leaderId` exclusion is mandatory: the in-flight leader is still in
   `activeStreams` at scan time, so without the exclusion it would always see "itself" and never escalate.
   - **Why `{ type: "reset", leaderId }` and not `undefined`:** the per-leader timer self-deletes when it
     fires (`ws-client.ts:593`). If the re-arm emits no reset intent, the leader is never re-armed and
     never escalates again — a *permanent* false-suppression (architecture P1). The explicit `reset`
     re-arms THIS leader's own timer; `reset_all` is wrong here (it would reset the alive sibling's timer
     as a side effect of THIS leader's timeout — out-of-scope, muddies attribution).
   - `applyTimeout` is pure and already receives `activeStreams` — the cross-leader scan needs no new input.

3. **`reset_all` timer action wiring** (the hook side). Add `| { type: "reset_all" }` to the
   `applyStreamEvent` `timerAction` return union ONLY (`chat-state-machine.ts:302-305`). **Do NOT widen
   `applyTimeout`'s return union** (`:1090-1092`) — it returns only `reset`/`clear`; `reset_all` is a
   *stream-event* intent (debug heartbeat), never a *timeout* intent (architecture P2). Handle `reset_all`
   in `ws-client.ts:612-619` by iterating **`timeoutTimersRef.current.keys()`** (the live timer Map) and
   calling `resetLeaderTimeout(id)` for each — NOT `chatState.activeStreams.keys()`. This mirrors
   `clearAllTimeouts` (`:576-581`) exactly, is self-contained (no cross-state-slice read, no dependency-array
   question), and resets precisely the set of currently-armed timers (architecture P2). Add a
   `resetAllTimeouts` helper or inline the loop.

**What is deliberately NOT changed (preserve the genuine-hang path):**
- The 45s `STUCK_TIMEOUT_MS` and the two-stage Stage-1→Stage-2 lifecycle are unchanged.
- A turn where the **only** active leader goes silent with **zero** debug/cross-leader activity STILL
  escalates to `error` after two windows. AND — the new ceiling — even a multi-leader session where one
  leader hangs but siblings stay busy STILL escalates the hung leader after `MAX_LIVENESS_REARMS`
  suppressions. This is the load-bearing ceiling (`2026-05-05-defense-relaxation-must-name-new-ceiling.md`):
  we add liveness *inputs* and a *bounded* grace, we do not remove the *exit*.
- We do NOT add a path that un-escalates an ALREADY-`error` bubble (that would require resurrecting a
  cleared timer + flipping a terminal state, and risks ping-ponging). The Stage-2 gate prevents the false
  `error` from ever being reached on a live leader, which is strictly better than clearing it afterward.

### Name the ceiling (which signals count as "leader alive", and for how long)

Per `2026-06-03-cloud-task-heartbeat-grace-discriminate-null-origins.md` and
`2026-03-29-workflow-gate-multi-signal-detection.md`, enumerate the liveness signal set AND the bound:

| Signal | Resets which timer | Counted as liveness? | Bound | Why |
| --- | --- | --- | --- | --- |
| `tool_use` / `tool_progress` / `stream` / `stream_start` / `command_stream` for leader X | X (existing) | yes (unchanged) | unbounded (true per-leader proof) | Strongest, leader-attributed; proves X itself is alive. |
| `debug_event` `kind: "tool_use"` while `activeStreams.size === 1` | the sole active leader (`reset_all`) | **yes (new)** | unbounded (unambiguous → true proof of THAT leader) | One active leader ⇒ debug heartbeat is unambiguously its own; also clears `retrying` + resets `livenessRearms`. |
| `debug_event` `kind: "tool_use"` while `activeStreams.size > 1` | **none** | **no** | n/a | Unattributable across ≥2 leaders; the bounded cross-leader gate handles this case instead (no `reset_all`). |
| `debug_event` `kind: "reasoning"` / `"result"` (any size) | none | **no** | n/a | Weaker / can fire post-turn; excluded to keep the ceiling tight. |
| Stage-2 timeout for leader X when ANOTHER leader is active AND `livenessRearms < MAX` | X re-armed (`reset`), NOT errored, `livenessRearms++` | **yes (new, BOUNDED)** | `MAX_LIVENESS_REARMS = 3` suppressions | A sibling is NOT proof X is alive; grant a *bounded* grace then escalate X regardless. |
| Stage-2 timeout for X when no sibling active, OR `livenessRearms >= MAX` | X → `error` | n/a | n/a | **Genuine-hang exit preserved** even under a perpetually-busy sibling. |

## User-Brand Impact sign-off

Threshold `single-user incident` → `requires_cpo_signoff: true`. CPO sign-off required at plan time before
`/work` begins (covered by Phase 2.5 Domain Review CPO if Product is flagged, or confirm CPO has reviewed
this plan). `user-impact-reviewer` will be invoked at review time per the review-skill conditional block.

## Files to Edit

- `apps/web-platform/lib/chat-state-machine.ts`
  - **Add `livenessRearms?: number`** to `ChatMessageBase` (`:31-54`, beside `retrying`) — the bounded
    re-arm counter. Document it like `retrying` (optional so existing fixtures type-check unchanged).
  - **Add `export const MAX_LIVENESS_REARMS = 3;`** (here or in `ws-constants.ts` beside `STUCK_TIMEOUT_MS`).
  - Extend the `applyStreamEvent` `timerAction` return union (`:302-305`) with `| { type: "reset_all" }`.
    **Do NOT widen `applyTimeout`'s return union (`:1090-1092`)** — it stays `reset`/`clear`; `reset_all` is
    a stream-event intent only (architecture P2).
  - `debug_event` case (`:1032-1055`): emit `{ type: "reset_all" }` **only when `event.kind === "tool_use"`
    AND `activeStreams.size === 1`**; in that arm also clear `retrying` and reset `livenessRearms` to 0 on
    the sole active bubble (mirror `tool_progress` at `:518-529`). Keep the appended debug message. Rewrite
    the orthogonal-panel comment (`:1036-1039`) to record (a) debug is now a single-leader heartbeat input
    AND (b) why it's safe — the `size === 1` gate (no resurrection of a `stream_end`ed leader) and the
    `applyTimeout` transitional-state guard at `:1099` (a re-armed dangling timer no-ops on a non-transitional
    bubble). A comment that just says "debug resets the watchdog" without the safety rationale is the same
    maintainer trap inverted.
  - `applyTimeout` Stage-2 arm (`:1104-1116`): add the cross-leader-active check (any OTHER leader,
    `!== leaderId`, in `activeStreams` with a transitional/streaming bubble) AND the `livenessRearms < MAX`
    budget check. If both hold → increment `livenessRearms`, keep `retrying: true`, return
    `{ type: "reset", leaderId }`. Else → escalate to `error` + delete from `activeStreams` (unchanged).
- `apps/web-platform/lib/ws-client.ts`
  - `useEffect` timer dispatcher (`:612-619`): handle `ta.type === "reset_all"` → iterate
    **`timeoutTimersRef.current.keys()`** (the live timer Map, NOT `chatState.activeStreams`) and
    `resetLeaderTimeout(id)` for each. Add a `resetAllTimeouts` helper mirroring `clearAllTimeouts`
    (`:576-581`) exactly — self-contained, no cross-state-slice read (architecture P2).
- `apps/web-platform/test/chat-state-machine.test.ts` — RED tests (see Test Scenarios), state-machine level.
- `apps/web-platform/test/message-bubble-retry.test.tsx` — RED test (see Test Scenarios), render level
  (assert the live-leader path produces NO "Agent stopped responding" banner).

**Note on `reset_all` type widening (`hr-type-widening-cross-consumer-grep`,
`cq-union-widening-grep-three-patterns`):** only `applyStreamEvent`'s return union gains `reset_all`
(`applyTimeout`'s does NOT — `reset_all` is a stream-event intent, never a timeout intent). The `timerAction`
union is consumed at the `ws-client.ts:612-619` if-ladder — NOT an exhaustive switch, so `tsc` will NOT
catch a missed branch there. Grep `git grep -n "pendingTimerAction\|timerAction\|\.type === \"clear" apps/web-platform/`
to enumerate every consumer before freezing, add the `reset_all` branch to the if-ladder, and run
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` to catch any exhaustive-switch consumers.

## Files to Create

None. (New tests are added to the two existing files above, which match vitest's `test/**/*.test.ts` /
`test/**/*.test.tsx` include globs at `apps/web-platform/vitest.config.ts:44,60`.)

## Open Code-Review Overlap

4 open `code-review` issues mention the edited files, none overlapping the watchdog/timer logic:
- `#2220` refactor: inject idFactory into `applyStreamEvent` to restore reducer purity — **Acknowledge**
  (reducer-purity concern, orthogonal to liveness timing; this fix adds a pure `timerAction` only).
- `#2224` refactor: chat code-quality polish (JSX/factory/`StreamEvent` export) — **Acknowledge** (cosmetic;
  no interaction with watchdog).
- `#3374` review: emit `slot_reclaimed` WS frame — **Acknowledge** (`ws-client.ts` but a different
  ledger-divergence concern).
- `#3280` review: refactor history-fetch into reducer-driven state machine — **Acknowledge** (`ws-client.ts`
  but unrelated to the timer `useEffect`).
None are folded in: this fix is intentionally minimal and these are independent refactor cycles.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (RED→GREEN, single-bubble debug-liveness):** New test in `chat-state-machine.test.ts`: with
      exactly ONE active leader's bubble at Stage 1 (`retrying: true`, state `tool_use`,
      `activeStreams.size === 1`), applying `debug_event { kind: "tool_use" }` emits
      `timerAction.type === "reset_all"` AND clears `retrying` AND resets `livenessRearms` to 0 on that
      bubble. Test FAILS on base (today `debug_event` emits no `timerAction`).
- [ ] **AC2 (RED→GREEN, multi-bubble cross-leader, pinned):** New test: leader A bubble at Stage 1
      (`retrying`, `livenessRearms` unset/0), leader B still in `activeStreams` (state `tool_use`).
      `applyTimeout(prev, streams, "A")` returns `messages[Aidx].state === "tool_use"` (NOT `error`),
      `activeStreams.has("A") === true`, `messages[Aidx].retrying === true`, `messages[Aidx].livenessRearms === 1`,
      and `timerAction` is **exactly** `{ type: "reset", leaderId: "A" }` (pin the value — not `reset` OR
      `reset_all`; test-design Rec 2). FAILS on base (today A escalates regardless of B).
- [ ] **AC3 (genuine-hang ceiling, single leader — standalone):** Dedicated test (do NOT fold into `:73`/`:86`):
      leader A is the **only** active leader (`activeStreams.size === 1`), `retrying: true`, no debug event.
      `applyTimeout(prev, streams, "A")` STILL transitions A to `error` + removes A from `activeStreams`.
      Bracket it with the AC2 seed (same bubble + a second active leader) so the pair proves the gate is the
      discriminator, not the leader count alone (test-design Rec 1).
- [ ] **AC3b (genuine-hang ceiling, BOUNDED re-arm — the un-masking guard):** New sequence test (user-impact
      FINDING 1/2): leader A `retrying`, leader B active. Call `applyTimeout(…, "A")`
      `MAX_LIVENESS_REARMS + 1` times **with B kept active throughout** (B never leaves `activeStreams`).
      Assert A re-arms for the first `MAX_LIVENESS_REARMS` calls (`livenessRearms` increments 1→2→3, state
      stays `tool_use`) and on the `(MAX+1)`-th call A escalates to `error` **regardless of B still being
      active**. This is the load-bearing proof that a perpetually-busy sibling cannot mask a hung leader
      forever.
- [ ] **AC3c (re-arm then later all-silent escalates):** Sequence test (test-design Gap 3): A `retrying`,
      B active → `applyTimeout(…, "A")` re-arms A (no error). Then B goes silent (remove B from
      `activeStreams`) → next `applyTimeout(…, "A")` with A now last DOES escalate to `error`. Proves the
      gate is transient, not permanent suppression.
- [ ] **AC4 (render-level, no false banner + chip clears):** Test in `message-bubble-retry.test.tsx`: a
      Stage-1 `retrying` bubble renders the honest "No response yet" chip, NEVER "Agent stopped responding".
      Keep the existing `:59`/`:80` terminal-error render tests green. (Single render assertion — do not
      re-drive the full reducer through render; the state-machine ACs already prove the state never reaches
      `error` on a live leader. code-simplicity trim.)
- [ ] **AC5 (`reset_all` wired in hook, timer-Map iteration):** `ws-client.ts` `useEffect` handles
      `reset_all` by iterating `timeoutTimersRef.current.keys()` (NOT `chatState.activeStreams`) and resetting
      each. Verify `git grep -n "reset_all\|resetAllTimeouts" apps/web-platform/lib/ws-client.ts` returns the
      branch + helper, sitting beside the existing `clearAllTimeouts` handling (`:617`).
- [ ] **AC6 (type-widening sweep):** `git grep -n "pendingTimerAction\|timerAction" apps/web-platform/` lists
      every consumer; the `ws-client.ts:612-619` if-ladder handles `reset_all`. `applyTimeout`'s return union
      is NOT widened (only `applyStreamEvent`'s is). `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      is clean.
- [ ] **AC7 (ceiling negatives — debug-event tight):** Tests: (a) `debug_event { kind: "tool_use" }` with
      `activeStreams.size === 0` emits NO `timerAction` (inert); (b) with `activeStreams.size > 1` (two
      leaders) emits NO `reset_all` (unattributable → cross-leader gate handles it instead); (c)
      `debug_event { kind: "reasoning" }` and `{ kind: "result" }` each emit NO `reset_all`. `debug_event`
      still appends a `ChatDebugEventMessage`, still carries no `leaderId`, still never persisted (standing
      CI grep gate unaffected).
- [ ] **AC8b (no resurrection of terminal bubble):** Test (test-design Gap 2 / ping-pong vector): the sole
      active leader's bubble is already `error`/`done` but still (transiently) in `activeStreams`. A
      `debug_event { kind: "tool_use" }` `reset_all` re-arms its timer, but the next `applyTimeout` no-ops
      (the `:1099` transitional-state guard rejects non-`thinking`/`tool_use` bubbles) — assert no state
      change / no resurrection.
- [ ] **AC8 (full suite green):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/message-bubble-retry.test.tsx test/cc-soleur-go-tool-progress-no-terminal-error.test.ts`
      passes (the existing `cc-soleur-go-tool-progress-no-terminal-error` regression test must stay green —
      it asserts the unchanged single-leader heartbeat path).
- [ ] **AC9 (PR body links parent):** PR body uses `Ref #5240` (NOT `Closes #5240` — #5240 is the open
      parent epic and must stay open) and `Closes #<new-sub-issue>` for the focused sub-issue filed under it.

### Post-merge (operator)

- [ ] **AC10:** None required. Pure client-side state-machine change shipped via the standard
      `web-platform-release.yml` pipeline (path-filtered on `apps/web-platform/**`); the merge IS the
      deploy. No migration, no infra, no secret, no operator step. (Automation-feasibility gate: nothing to
      automate post-merge.)

## Test Scenarios

Mirror the pure-reducer harness in
`apps/web-platform/test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` (a `ReducerState` + `applyEvent`
+ `applyTimeoutTo` helper set) — no JSX needed for the state-machine ACs.

1. **Single-bubble debug-liveness (AC1):** seed `[thinkingMessage("cpo") state tool_use, retrying:true]`,
   streams `[["cpo",0]]` (size 1). Apply `debug_event {kind:"tool_use", body:"…"}`. Assert `timerAction`
   is `{type:"reset_all"}`, `messages[0].retrying` is cleared, `messages[0].livenessRearms === 0`.
2. **Multi-bubble cross-leader, pinned (AC2):** seed `cpo` (idx 0, `tool_use`, `retrying:true`) + `cto`
   (idx 1, `tool_use`), streams `[["cpo",0],["cto",1]]`. `applyTimeout(prev, streams, "cpo")`: assert
   `messages[0].state === "tool_use"`, `activeStreams.has("cpo") === true`, `messages[0].retrying === true`,
   `messages[0].livenessRearms === 1`, `timerAction` is **exactly** `{type:"reset", leaderId:"cpo"}`.
3. **Genuine hang, last leader (AC3 — standalone, bracketed):** seed only `cpo` (`tool_use`, `retrying:true`),
   streams `[["cpo",0]]`. `applyTimeout(prev, streams, "cpo")`: assert `state === "error"`,
   `activeStreams.has("cpo") === false`. Co-locate with the AC2 two-leader seed so the pair proves the gate
   is the discriminator (not leader count).
4. **Bounded re-arm un-masks a hung leader (AC3b):** seed `cpo` (`tool_use`, `retrying:true`) + `cto`
   (active), streams both. Loop `applyTimeout(…, "cpo")` `MAX_LIVENESS_REARMS + 1` times, `cto` ALWAYS
   active. Assert calls 1..MAX re-arm (`livenessRearms` 1→2→3, `state` stays `tool_use`), call MAX+1
   escalates `cpo` to `error` despite `cto` still active.
5. **Re-arm then later all-silent escalates (AC3c):** `cpo` re-armed (call once, `cto` active) → remove
   `cto` from streams → `applyTimeout(…, "cpo")` now escalates `cpo` to `error` (`cpo` is last).
6. **Debug ceiling — inert / size>1 / wrong kind (AC7):** (a) streams empty + `debug_event{kind:"tool_use"}`
   → `timerAction` undefined; (b) two active leaders + `debug_event{kind:"tool_use"}` → NO `reset_all`;
   (c) one active leader + `debug_event{kind:"reasoning"}` and `{kind:"result"}` → NO `reset_all` each.
7. **No resurrection of terminal bubble (AC8b):** sole active leader's bubble is `error`/`done` but still in
   `activeStreams`; `debug_event{kind:"tool_use"}` emits `reset_all`, but a follow-up `applyTimeout` no-ops
   (`:1099` transitional-state guard) — assert no state change.
8. **Render: live-leader bubble shows honest chip, not banner (AC4):** render `MessageBubble` for the
   `retrying` Stage-1 bubble → assert `getByTestId("retrying-chip")` present with "No response yet",
   `queryByText(/Agent stopped responding/)` absent. (Existing `:59`/`:80` terminal-error render tests stay.)

## Domain Review

**Domains relevant:** Product (UI-surface: chat message bubble render path)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none (no new UI surface — this modifies the existing `message-bubble.tsx` error/chip
render path's UPSTREAM state machine; it does not create a new page, component, or interactive flow. The
mechanical UI-surface override does NOT fire: `## Files to Create` is empty and `## Files to Edit` adds no
new `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` file — `message-bubble.tsx` is edited
zero times by this plan; only its inputs change.)
**Pencil available:** N/A (no new UI surface)

#### Findings

The user-visible change is purely behavioral: a working turn no longer shows a false error. No new copy, no
new layout, no new interactive control. The honest "No response yet" Stage-1 chip and the legitimate terminal
`error` banner are both unchanged in markup. CPO sign-off is required by the `single-user incident` threshold
(frontmatter `requires_cpo_signoff: true`), satisfied by plan-time review; `user-impact-reviewer` runs at PR
time.

## Infrastructure (IaC)

None. Pure client-side TypeScript change under `apps/web-platform/lib/` + `apps/web-platform/test/`. No new
server, service, cron, secret, vendor, DNS, or persistent process. (Phase 2.8 trigger scan: no remote-shell
access, no secret writes, no systemd unit, no vendor dashboard step, no new Terraform root.)

## Observability

This plan edits code under `apps/web-platform/lib/` (a code-class path), so the Observability schema is
required. The fix is a client-side render/state-machine correction with no new server error path:

```yaml
liveness_signal:
  what: "No new server-side liveness signal. The change is the FIX to a client-side false liveness verdict."
  cadence: "n/a (client render-time, per WS frame)"
  alert_target: "n/a"
  configured_in: "apps/web-platform/lib/chat-state-machine.ts (pure reducer; no telemetry emit)"
error_reporting:
  destination: "n/a — no new error path. The existing client reportSilentFallback/warnSilentFallback mirror (mocked in message-bubble-retry.test.tsx) is unchanged."
  fail_loud: "n/a"
failure_modes:
  - mode: "Fix too aggressive — suppresses a genuine hang forever"
    detection: "AC3 unit test (last-active-leader still escalates to error); plus the unchanged 45s two-stage watchdog exit"
    alert_route: "test-suite (CI) — no runtime alert; the genuine-hang error banner itself is the user-visible signal"
  - mode: "Bounded re-arm masks a hung leader (a busy sibling perpetually suppresses escalation)"
    detection: "AC3b (loop MAX+1 times with sibling active → still escalates) — the MAX_LIVENESS_REARMS ceiling caps suppression at ~3.75min"
    alert_route: "test-suite (CI); the genuine-hang error banner is the user-visible signal once the ceiling is hit"
  - mode: "reset_all branch missed in a timerAction consumer (silent no-op)"
    detection: "AC6 type-widening grep + tsc --noEmit; AC5 grep for the wired branch"
    alert_route: "CI typecheck + grep ACs"
logs:
  where: "No new logs. Debug-stream events remain render-only + ephemeral (never persisted to messages/logs/Sentry — standing CI grep gate, AC7)."
  retention: "n/a"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/message-bubble-retry.test.tsx"
  expected_output: "all tests pass; AC1/AC2 (false-positive paths) green, AC3/AC3b/AC3c (genuine-hang + bounded-ceiling exits) green"
```

## Hypotheses

Not a network-connectivity issue (the symptom is the OPPOSITE — connection is `live`/Connected; the bug is a
client state-machine false positive while the socket is healthy). The Phase 1.4 network-outage checklist does
not apply.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **(a only) Feed every `debug_event` into a per-leader reset** | `debug_event` has NO `leaderId` — a per-leader reset is impossible. Must be global (`reset_all`). And (a) alone does not fix screenshot 2's cross-leader case where the in-flight leader's OWN bubble already escalated while a DIFFERENT leader streams. |
| **(b only) Clear lingering `error` on later activity** | Requires resurrecting a cleared timer and flipping a terminal `error`→`tool_use` state, risking ping-pong and a flickering banner. The cross-leader Stage-2 gate prevents the false `error` from ever rendering, which is strictly cleaner than un-erroring after the fact. |
| **Extend `STUCK_TIMEOUT_MS` (e.g., 45s → 120s)** | Pure latency band-aid; a long debug-only span still escalates falsely, and it slows the genuine-hang signal. Does not address the structural input-set gap. Also a defense-relaxation that would need its own ceiling analysis. |
| **Reset all timers whenever ANY main-stream event arrives (drop per-leader keying entirely)** | Over-broad; would mask a genuinely-hung leader B whenever a fast leader A keeps emitting. The chosen design is the targeted version: cross-leader suppression is BOUNDED (`MAX_LIVENESS_REARMS`) so a busy sibling cannot mask a hung leader forever. |
| **`reset_all` from debug while `activeStreams.size > 0` (v1 plan)** | **Rejected at deepen-plan (architecture P1 + user-impact FINDING 2):** with ≥2 active leaders, an unattributed debug `tool_use` from a fast leader A would reset a hung leader B's timer forever — reintroducing the masking the row above rejects. Narrowed to `size === 1` (unambiguous heartbeat); multi-leader liveness goes through the bounded cross-leader gate instead. |
| **Unbounded cross-leader gate (v1 plan)** | **Rejected at deepen-plan (user-impact FINDING 1):** a long-lived sibling (10-min build) would keep a hung leader's bubble spinning with no error for the sibling's whole lifetime — "another leader active" is NOT proof THIS leader is alive. Replaced with the bounded `MAX_LIVENESS_REARMS` grace. |
| **Suppress the error banner entirely when `phase === "live"`** | Would permanently hide genuine single-leader hangs on a live socket — exactly the regression the scope guard forbids. |

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6.** This section is filled (threshold `single-user incident`).
- **The `timerAction` union is consumed by an if-ladder in `ws-client.ts:612-619`, NOT an exhaustive
  switch** — `tsc` will NOT flag a missing `reset_all` branch there. The type-widening sweep (AC6) is the
  guard; do not rely on the compiler for that consumer. Only `applyStreamEvent`'s union gains `reset_all`;
  `applyTimeout`'s does not.
- **The cross-leader Stage-2 scan MUST exclude the in-flight `leaderId` itself** (`!== leaderId`). The
  in-flight leader is still in `activeStreams` at scan time, so without the exclusion it always sees
  "itself" as active and never escalates — a permanent suppression. AC3 brackets this.
- **`reset_all` must iterate the live timer Map (`timeoutTimersRef.current`), NOT `chatState.activeStreams`.**
  Mirroring `clearAllTimeouts` keeps the reset self-contained (no cross-state-slice read, no dependency-array
  question) and resets exactly the currently-armed timers (architecture P2).
- **Debug heartbeat resets only when `activeStreams.size === 1`.** At `size > 1` a debug `tool_use` is
  unattributable; resetting all leaders there would let a fast leader mask a hung sibling (the v1 hole). The
  bounded cross-leader gate is the multi-leader handler.
- **The single-leader debug heartbeat MUST also clear `retrying` + reset `livenessRearms`** (mirror
  `tool_progress`), or the user sees a permanent stale "No response yet" chip on a working turn
  (user-impact FINDING 3).
- **The `debug_event` reducer comment currently asserts the OPPOSITE of the new behavior** ("a
  tool_use/reasoning/result event must not reset the stuck-state watchdog"). Rewrite it to record (a) debug
  is now a single-leader heartbeat AND (b) why it's safe (the `size === 1` gate + the `:1099`
  transitional-state guard) — a comment that just says "debug resets the watchdog" is the same maintainer
  trap inverted.
- **Test runner is vitest, not `bun test`** (`apps/web-platform/bunfig.toml` sets `[test] pathIgnorePatterns
  = ["**"]`). Use `./node_modules/.bin/vitest run <path>`. Typecheck is `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit`, NOT `npm run -w` (no root `workspaces` field).
- **New tests MUST live under `test/`** (`test/**/*.test.ts` / `test/**/*.test.tsx`) — a co-located
  `lib/**/*.test.ts` is collected by the unit project (`lib/**/*.test.ts` is in the include glob) but a
  `components/**/*.test.tsx` is NOT. Keep the render test in `test/message-bubble-retry.test.tsx`.
- **The cross-leader Stage-2 gate is BOUNDED, not a permanent suppression.** Each suppression increments
  `livenessRearms`; after `MAX_LIVENESS_REARMS` the bubble escalates regardless of any active sibling
  (AC3b). "Another leader active" grants a bounded grace (~3.75min), NOT proof that THIS leader is alive —
  a busy sibling must never mask a hung leader forever (user-impact FINDING 1/2). The re-arm emits exactly
  `{ type: "reset", leaderId }` (never `undefined` — the timer self-deleted on fire and would never re-arm;
  never `reset_all` — that would reset the sibling's timer too).

## Deferred / Out of Scope (tracking)

- **Backend workspace-rebind / genuine stuck-loop** (the deferred #5240 FR-half, 4826 session): explicitly
  out of scope per the scope guard. Already tracked under the open parent epic #5240 — no new deferral issue
  needed (the parent epic IS the tracker).

## References

- `apps/web-platform/lib/chat-state-machine.ts:1083-1126` (`applyTimeout`), `:1032-1055` (`debug_event`),
  `:302-305` (`timerAction` union), `:1174-1195` (`deriveReconnectView`), `:317-335` (`StreamEvent`).
- `apps/web-platform/lib/ws-client.ts:563-596` (timer Map + reset/clear helpers), `:612-619` (timerAction
  `useEffect`), `:479-482` (`activeStreams.keys()` enumeration), `:576-581` (`clearAllTimeouts` precedent).
- `apps/web-platform/components/chat/message-bubble.tsx:356-392` (state→render switch, error branch).
- `apps/web-platform/lib/types.ts:341-346` (`debug_event` shape — no leaderId), `:247` (`MessageState`).
- `apps/web-platform/components/chat/chat-surface.tsx:233-260` (`hasRetryingBubble` + `deriveReconnectView`).
- `apps/web-platform/test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` (pure-reducer harness to mirror).
- `apps/web-platform/vitest.config.ts:44,60` (include globs); `apps/web-platform/bunfig.toml:6-11`.
- Learnings: `2026-06-03-cloud-task-heartbeat-grace-discriminate-null-origins.md` (name the ceiling),
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md` (preserve the genuine-hang exit),
  `2026-05-13-plan-verify-reducer-case-arms-with-grep-not-read-first-n.md` (enumerate reducer arms by grep),
  `2026-04-23-command-center-bubble-lifecycle-invariants.md` (state-transition-at-reducer-exit invariant),
  `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md` (tsc as the exhaustiveness oracle).
