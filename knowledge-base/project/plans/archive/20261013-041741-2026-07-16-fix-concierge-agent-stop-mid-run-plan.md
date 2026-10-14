---
title: "fix: Concierge false mid-run stop (orphan client error + long-turn hard cap)"
type: fix
date: 2026-07-16
branch: feat-one-shot-fix-concierge-agent-stop-mid-run
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
# No `closes:` — residual harness reliability; do not bind closed issue numbers as work targets.
---

# 🐛 fix: Concierge false mid-run stop (orphan client error + long-turn hard cap)

## Enhancement Summary

**Deepened on:** 2026-07-16  
**Sections enhanced:** Root residual analysis, Path A rebind semantics, Phase 2 test enumeration, Hypotheses, Risks (precedent-diff), verify-the-negative  
**Research agents / passes used:** local repo residual trace, learnings apply, verify-the-negative, precedent-diff (watchdog recovery), test-compatibility enum for hard-cap constant, plan-review eng panel (mechanical)

### Key Improvements (deepen pass)

1. **Confirmed live prod already has prior heartbeats** (`build_sha 0853bd51…`) — residual is **orphan Stage-2 error rebind**, not redeploy of #5208/#5214.
2. **Named the cc_router chip trap** as the load-bearing post-error failure: after eviction, `tool_use` for `cc_router` only appends chips and never heals the red banner.
3. **Hard-cap test enumeration is complete** (not sampled): only two production-constant pins assert `DEFAULT_MAX_TURN_DURATION_MS === 10 * 60 * 1000` — `soleur-go-runner-awaiting-user.test.ts:610-611` and `soleur-go-runner-tool-result-idle-reset.test.ts:210-211`. Do **not** change `DEFAULT_IDLE_REAP_MS` pins (also 10 min, different constant).
4. **Path B demoted to true contingency** — pure model silence >90s without any frame is rarer on Concierge when debug/command_stream fire; Path A rebind covers the operator-visible orphan class.
5. **Network-timeout keyword false-fire handled:** application watchdog timeouts are not L3/L7 network outage — Hypotheses section added.

### New Considerations Discovered

- `findRecoverableErrorBubble` must stop when a **newer live text bubble** for the same leader exists after an old error (avoid resurrecting ancient errors after a successful stream_end + new stream_start already created a healthy tip).
- `stream_start` after error currently **appends a new thinking bubble** without healing the error row — Phase 1 should also rebind-or-heal on `stream_start` when recoverable error is the tip (or transition prior error → done when starting a new stream for same leader). Prefer: if recoverable error is tip, **reuse** it as the new stream bubble (`state: thinking`) rather than stacking.
- Rebind must clear `retrying` so message-bubble leaves both error and "No response yet" paths.

## Overview

Soleur Concierge turns (including long one-shot runs from the web UI) still paint a **terminal red banner** —

> Agent stopped responding after: {toolLabel ?? Working}

— while the agent is **still working** (Debug stream / tools continue). This is a **Concierge harness reliability** bug on the already-shipped heartbeat stack. It is **not** nav-rail product scope (position resume is orthogonal and already shipped).

**Premise Validation (Phase 0.6):**

| Cited premise | Status |
|---|---|
| Banner copy path `message-bubble.tsx` when `messageState === "error"` | **Held** — `"Agent stopped responding after: {toolLabel ?? "Working"}"` |
| Client stuck-watchdog → terminal `error` via `applyTimeout` stage 2 | **Held** — `lib/chat-state-machine.ts` `applyTimeout` |
| Server `runner_runaway` user copy is different | **Held** — `"The agent went idle without finishing…"` in `server/cc-workflow-end-messages.ts` |
| Shipped: `soleur-go-runner` re-arms idle `armRunaway` on SDK `tool_progress` | **Held on origin/main and on live prod `build_sha`** |
| Shipped: cc-dispatcher `onToolProgress` forward (5s debounce) | **Held** |
| Shipped: `debug_event` tool_use as single-leader liveness heartbeat + `MAX_LIVENESS_REARMS` | **Held** |
| Prior plan `2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md` | **Held** as prior work; residual is what that plan's follow-ups predicted after server heartbeats landed |
| Nav-rail resume as the fix | **Stale/wrong** — do not re-enter that scope |
| Prod deploy lag blocking heartbeats | **Falsified for the shipped heartbeat code** — `GET https://app.soleur.ai/health` → `version 0.216.3`, `build_sha 0853bd51…` **contains** `tool_progress` re-arm + `onToolProgress` + `MAX_LIVENESS_REARMS` / `debug_event` liveness. Residual is code-path, not "fixes not deployed." |

**Research decision:** Strong local patterns + prior plan/learnings; **no external research**. Stack is TypeScript/Next already covered by built-in agents (community discovery skipped). Functional overlap: internal harness state-machine fix (no community skill install).

## Problem Statement / Motivation

### Operator symptom (correctly classified)

Mid-one-shot Concierge conversation dies with the red client banner while Debug still shows tool activity (`grep`/`find`/`ls`/`mkdir`). Trust-destroying: looks like the product gave up while the agent is alive.

### What is already fixed (do NOT re-implement)

| Layer | Mechanism | Anchors |
|------|-----------|---------|
| Server idle 90s | `armRunaway` re-armed on SDK `tool_progress` | `server/soleur-go-runner.ts` `msg.type === "tool_progress"` → `armRunaway(state)` |
| Client feed | cc `onToolProgress` → WS `tool_progress` (5s debounce) | `server/cc-dispatcher.ts` `onToolProgress` + `TOOL_PROGRESS_DEBOUNCE_MS = 5_000` |
| Client reset | `tool_progress` / `tool_use` / `stream` → `timerAction: reset` | `lib/chat-state-machine.ts` |
| Debug liveness | `debug_event` kind `tool_use` when `activeStreams.size === 1` → `reset_all` | same file, `#5240` |
| Cross-leader grace | Stage-2 suppress while sibling active, budget `MAX_LIVENESS_REARMS = 3` | `applyTimeout` |
| Absolute ceiling | `DEFAULT_MAX_TURN_DURATION_MS = 10 * 60 * 1000` **not** re-armed on heartbeats | `armTurnHardCap` / ADR-022 amendment 2026-06-12 |

Learnings that already encode this stack:

- `knowledge-base/project/learnings/best-practices/2026-06-12-idle-watchdog-reset-on-sdk-heartbeat-and-upstream-fix-exposes-downstream-timeout.md`
- `knowledge-base/project/learnings/bug-fixes/2026-06-15-watchdog-liveness-input-set-must-match-its-claim.md`
- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`

### Dominant residual (code evidence)

**Once Stage-2 paints `error`, the leader leaves `activeStreams` and subsequent live activity cannot clear the red banner.**

1. `applyTimeout` stage 2 sets `state: "error"`, **deletes** the leader from `activeStreams`, `timerAction: clear` (`chat-state-machine.ts` `applyTimeout` second-timeout branch).

2. For Concierge leader `cc_router`, later `tool_use` when `!activeStreams.has("cc_router")` takes the **chip-only** branch (Stage 4 `#2886`): appends `tool_use_chip`, **no** `timerAction`, **does not** rebind or heal the error bubble.

3. `tool_progress` with unknown leader (`idx === undefined`) is an **inert no-op** — cannot recover.

4. `debug_event` heartbeat is gated on `activeStreams.size === 1` and comments explicitly say it **must not resurrect** a terminal bubble.

5. `command_stream` without an active stream **creates a new** `streaming` bubble below the orphan error — agent continues under a new row while the red banner stays.

Net UX: **orphan red banner + live tools/debug** — exactly the operator report. Banner copy is client `error` state (`message-bubble.tsx`), **not** server `runner_runaway` copy.

### Secondary residuals (still real)

| Residual | Mechanism | When it bites |
|----------|-----------|---------------|
| **A. False Stage-2 escalate before recovery** | Two consecutive 45s windows without attributed heartbeat while bubble stays transitional | Model "think" gaps with no `tool_progress` / no `tool_use` / no `command_stream`; multi-leader `debug_event` inert (`size !== 1`); shape-guard drops on malformed `tool_progress` (server still re-arms idle, client may not get WS) |
| **B. 10-min absolute hard cap** | `armTurnHardCap` from `firstToolUseAt`, **not** extended by activity | Legitimate multi-step Concierge/one-shot >10 min → `runner_runaway` `reason: "max_turn_duration"` (different user copy, still kills the turn) |
| **C. Genuine hang** | No heartbeats for idle window | Must still fail closed |

### Deploy note

Live `app.soleur.ai/health` already runs a SHA that includes the #5208/#5214-class heartbeats. Do **not** plan "redeploy the old heartbeats" as the fix. After **this** fix ships, confirm cutover via the same health endpoint (Web Platform Release has historically hit `image_pull_failed` — treat deploy confirmation as an AC, not a premise that "main is live").

Sentry self-pull for `runner_runaway` / `tool-progress-shape` at plan time returned project-not-found for the attempted path; plan observability uses structured logs + health + existing `reportSilentFallback` ops (`tool-progress-shape`, `onToolProgress`) rather than dashboard eyeballing (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Research Reconciliation — Spec vs. Codebase

No branch `spec.md` (direct one-shot plan). Operator residual list vs codebase:

| Operator / context claim | Reality | Plan response |
|---|---|---|
| "Fix timeout so long work can run" | Heartbeats for mid-tool already shipped; residual is **orphan terminal error + hard cap** | Prefer recovery + hard-cap policy; do not re-land `tool_progress` re-arm |
| Banner = client stuck-watchdog | Confirmed (`applyTimeout` → `error` → message-bubble) | Primary fix in client state machine |
| Server still may kill long turns | Confirmed 10-min hard cap untouched by activity | Phase 2 hard-cap policy with a **named higher absolute ceiling** |
| Nav-rail | Orthogonal | Non-goal |

## 🎯 Goal

1. Continuous tool/debug activity on Concierge **never leaves a terminal "Agent stopped responding after: …" banner** while the turn is still live.
2. Genuine silence still fails closed (no infinite freeze).
3. Multi-step turns longer than 10 minutes of **agent compute** are not killed solely by the absolute hard cap without a named higher ceiling + idle defense intact.
4. Tests pin false-escalate recovery and hang preservation.
5. Post-deploy: confirm live `build_sha` includes this change (or document deploy block with health evidence).

## Proposed Solution

### Path A (primary — minimal, dominant residual) — **Orphan-error recovery / rebind**

When attributed liveness arrives for a leader that is **not** in `activeStreams`, but the most recent **text** bubble for that leader is `state === "error"` and the turn is still open (no terminal `workflow_ended` / connection unrecoverable required at reducer layer — use "most recent assistant text bubble for leader is error" as the rebind target):

**Rebind that bubble** instead of chip-only / new-bubble / no-op:

| Event | Recovery action |
|-------|-----------------|
| `tool_use` (incl. `cc_router` / `system`) | Re-insert leader → `activeStreams` at bubble index; set `state: "tool_use"`, update `toolLabel` / `toolsUsed`; clear `retrying` / `livenessRearms`; `timerAction: reset` |
| `tool_progress` | Same rebind; set `state: "tool_use"` (or keep tool_use); clear retrying; `timerAction: reset` — still **no chip spawn** |
| `command_stream` | Prefer rebind existing error text bubble + apply command blocks + `state: "streaming"` rather than always appending a new bubble |
| `stream` | Prefer rebind of leader's latest error text bubble when present (avoid dual bubbles); set `state: "streaming"`, REPLACE content as today |
| `stream_start` | Prefer rebind tip error → `state: "thinking"` + re-insert `activeStreams` (avoid stacking a second thinking row above a permanent red banner) |
| `debug_event` kind `tool_use` | If `activeStreams.size === 0` and exactly one leader has a recoverable error text bubble, rebind + `reset` that leader (not `reset_all` with empty timer map). If multi-orphan ambiguous, stay inert |

Extract a pure helper (same file):

```ts
// apps/web-platform/lib/chat-state-machine.ts
function findRecoverableErrorBubble(
  messages: ChatMessage[],
  leaderId: DomainLeaderId,
): number | undefined
// Walk from end: first type==="text" && leaderId match && state==="error"
```

**Do not** recover if a newer non-error text bubble for that leader already exists after the error (turn already continued elsewhere — then only ensure no *second* orphan; prefer healing only the latest error if it is still the tip for that leader).

**Fail-closed:** if **no** liveness events arrive for `2 × STUCK_TIMEOUT_MS` after a recovered bubble returns to transitional, Stage-2 may escalate again. Recovery is not a permanent amnesty.

### Path B (secondary — reduce false Stage-2 rate) — optional thin gate

Keep Stage-1 (`retrying` / "No response yet") as today. For Stage-2 only: if the reducer has a session-level `lastLivenessAt` updated by `tool_use` | `tool_progress` | `command_stream` | single-leader `debug_event` tool_use, and `now - lastLivenessAt < STUCK_TIMEOUT_MS`, **suppress Stage-2** (re-arm timer, increment a bounded `livenessRearms`-like budget or reuse `MAX_LIVENESS_REARMS`) instead of escalating.

Implement Path B **only if** Path A tests show recovery alone still leaves a flash of red that fails AC, **or** if unit scenarios prove Stage-2 races rebind (timer fires in the same tick as heartbeat). Default implement Path A first; Path B is a small additive field on `ChatState` / pure reducer if needed — **not** a constant raise of `STUCK_TIMEOUT_MS`.

### Path C (server — long multi-step turns) — hard-cap policy, not idle re-do

**Problem:** `DEFAULT_MAX_TURN_DURATION_MS = 10 min` is a non-activity-extending ceiling. One-shot from Concierge routinely exceeds 10 minutes of agent compute with continuous tools → `reason: "max_turn_duration"`.

**Policy (name both ceilings — `2026-05-05-defense-relaxation-must-name-new-ceiling`):**

1. Keep **`idle_window` 90s** re-armed on `tool_progress` / blocks / results (unchanged).
2. Keep a **chatty-stall absolute** that heartbeats alone cannot infinitely extend.
3. Change the absolute turn budget to an **activity-aware hard cap**:
   - On each **new work unit** only (`recordAssistantBlock` and `tool_use_result` / `handleUserMessage` tool result — **not** every `tool_progress` heartbeat), extend the remaining hard-cap timer so elapsed agent-compute may continue.
   - Cap total agent-compute at a **named** `DEFAULT_MAX_TURN_DURATION_MS` raised to **45 minutes** (or keep 10 min *base* + activity extension up to `DEFAULT_MAX_TURN_ABSOLUTE_MS = 45 * 60 * 1000` — pick one implementation; recommend **single constant raise to 45 min** *if and only if* activity-extension is rejected as complex, with ADR text that 45 min is the new absolute chatty-stall ceiling).
   - **Preferred minimal server change:** raise `DEFAULT_MAX_TURN_DURATION_MS` to `45 * 60 * 1000` and amend ADR-022 to record the new absolute. Idle 90s stays. Do **not** re-arm hard cap on `tool_progress` (preserves "heartbeat may not defeat absolute ceiling" proof for mid-tool loops). Multi-step skills get headroom; a single hung silent tool still dies at 90s idle; a chatty infinite tool_progress loop still dies at 45 min absolute.

**Rationale for prefer raise-absolute over re-arm-on-heartbeat:** re-arming hard cap on `tool_progress` would dissolve the chatty-stall defense completely (learning #1 in 2026-06-12 idle-watchdog learning). Raising the absolute is an explicit product budget for multi-step Concierge work.

### Explicit non-goals

- Nav-rail position resume / settings last-tab resume
- Re-implementing server `tool_progress` → `armRunaway` or cc `onToolProgress` forward (already shipped)
- Raising `STUCK_TIMEOUT_MS` / `DEFAULT_WALL_CLOCK_TRIGGER_MS` without mechanism
- Changing banner copy for genuine hangs
- Support-persona chat harness (separate surface) unless it shares the same reducer path (it does for client — recovery helps all leaders; no support-specific work)

## Implementation Phases

### Phase 0 — Preflight (read-only + RED scaffolding)

- Confirm current prod `build_sha` via `curl -sS https://app.soleur.ai/health`
- Grep anchors still present (no accidental reverts):
  - `soleur-go-runner.ts`: `msg.type === "tool_progress"` + `armRunaway`
  - `cc-dispatcher.ts`: `onToolProgress`
  - `chat-state-machine.ts`: `MAX_LIVENESS_REARMS`, `case "debug_event"`
- Write **failing** unit tests first (`cq-write-failing-tests-before`):
  1. Stage-2 error + eviction → `tool_use` for `cc_router` **rebinds** (no orphan error; activeStreams has leader; state tool_use)
  2. Stage-2 error → `tool_progress` rebinds + resets timer intent
  3. Stage-2 error → silence (no events) stays error (fail-closed)
  4. `command_stream` after error rebinds rather than leaving error + second bubble tip when rebindable
  5. Server: `DEFAULT_MAX_TURN_DURATION_MS === 45 * 60 * 1000` (or chosen constant) + existing idle/hang tests still pass

### Phase 1 — Client recovery helper + wire events (Path A)

**Files:** `lib/chat-state-machine.ts`, tests under `test/chat-state-machine.test.ts` and/or `test/cc-soleur-go-tool-progress-no-terminal-error.test.ts`

1. Add `findRecoverableErrorBubble`.
2. Wire recovery into `tool_use`, `tool_progress`, `command_stream`, `stream`, and `stream_start` (prefer rebind over new bubble when recoverable error tip exists).
3. Optional `debug_event` zero-activeStreams single-orphan rebind (only if unambiguous).
4. Preserve chip path when **no** recoverable error bubble (cold tool_use before stream_start remains chip behavior for cc_router).
5. GREEN the Phase 0 tests; run  
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/cc-soleur-go-tool-progress-no-terminal-error.test.ts test/ws-streaming-state.test.ts`

### Research Insights — Path A rebind

**Best practices (state machines):** Terminal UI states that can race live backends need either (a) never escalate while any live evidence exists, or (b) **recover** when evidence resumes. This plan chooses (b) as primary because Stage-2 already escalates under gaps; (a) alone does not clear an already-painted error.

**Precedent-diff (same codebase):**

| Concern | Precedent | This plan |
|---------|-----------|-----------|
| Clear `retrying` on heartbeat | `tool_progress` when `current.retrying` | Recovery must clear `retrying` + `livenessRearms` |
| Do not spawn chip on heartbeat | `tool_progress` comment Stage 4 | Rebind must not append `tool_use_chip` |
| No resurrect on debug alone | `debug_event` "do not resurrect" comment | **Deliberate exception** only when tip is error + attributed/unambiguous liveness — document in code comment citing this plan |
| Cross-leader mask bound | `MAX_LIVENESS_REARMS` | Recovery does not grant infinite Stage-2 amnesty after rebind |

**Edge cases:**

- History prepend (`filter_prepend`) shifts indices — rebind stores **fresh index** from scan, never a cached index.
- Multiple error bubbles for same leader (pathological) — helper returns the **latest** only; older errors stay (rare; acceptable).
- Server `workflow_ended` / `error` WS after client rebind — existing terminal paths still win; recovery does not fight server-terminal events.

### Phase 2 — Server hard-cap budget for multi-step turns (Path C)

**Files:** `server/soleur-go-runner.ts`, tests `test/soleur-go-runner-awaiting-user.test.ts` / `test/soleur-go-runner-tool-result-idle-reset.test.ts`, ADR-022 amendment

1. Raise `DEFAULT_MAX_TURN_DURATION_MS` to **45 minutes**.
2. Update **every** production-constant pin for this symbol (full enum from `rg DEFAULT_MAX_TURN_DURATION_MS apps/web-platform`):
   - `test/soleur-go-runner-awaiting-user.test.ts` — `expect(DEFAULT_MAX_TURN_DURATION_MS).toBe(10 * 60 * 1000)` → `45 * 60 * 1000` (and title/comment "10 min" → "45 min")
   - `test/soleur-go-runner-tool-result-idle-reset.test.ts` — same B-pin + comments that name the 10-min ceiling for **this** constant
   - **Do not** change `DEFAULT_IDLE_REAP_MS` pins in `soleur-go-runner-lifecycle.test.ts` (also 10 min, different defense)
3. Amend `ADR-022-sdk-as-router.md` Decision 2 / 2026-06-12 amendment: absolute ceiling value + statement that `tool_progress` still never touches `turnHardCap`.
4. Confirm AC3-class test: heartbeats alone still do not re-arm hard cap; hard cap still fires with `reason: "max_turn_duration"` (tests that inject short `maxTurnDurationMs` remain valid — they override deps).

### Phase 3 — Observability + deploy confirmation

1. On recovery rebind, optional structured client breadcrumb is **not** required if pure reducer; prefer **server-side** existing runaway diagnostics only.
2. If adding a client log, use existing Sentry breadcrumb patterns without PII.
3. Post-merge AC: `curl -sS https://app.soleur.ai/health | jq -r .build_sha` is ancestor-or-equal of the merge commit (or document `image_pull_failed` / stale SHA with the JSON evidence).
4. Dogfood: long Concierge turn with continuous tools must not show terminal banner mid-run (Playwright or operator dogfood; close open dogfood follow-through #2869 if still applicable after verify — **do not** put #2869 in plan `closes:` frontmatter as the work target).

### Phase 4 — Path B only if needed

If Phase 1 GREEN but product still sees red flash from Stage-2 before next tool event >90s of pure model silence with no debug: add `lastLivenessAt` session gate for Stage-2 suppress with `MAX_LIVENESS_REARMS` ceiling. Skip if Path A + continuous tool traffic already meets ACs.

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/lib/chat-state-machine.ts` | `findRecoverableErrorBubble` + rebind on liveness events (`tool_use`, `tool_progress`, `command_stream`, `stream`, `stream_start`, optional `debug_event`); optional Path B field |
| `apps/web-platform/test/chat-state-machine.test.ts` | Recovery + fail-closed cases |
| `apps/web-platform/test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` | cc_router residual contract (error → progress heals) |
| `apps/web-platform/test/ws-streaming-state.test.ts` | Only if applyTimeout / activeStreams contracts drift |
| `apps/web-platform/server/soleur-go-runner.ts` | `DEFAULT_MAX_TURN_DURATION_MS` → 45 min |
| `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` | Constant pin 10→45 min + titles/comments |
| `apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts` | Constant pin 10→45 min + B-pin comments |
| `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` | Amend absolute ceiling value |

## Files to Create

None (tests extend existing files).

## Open Code-Review Overlap

Open code-review issues touching planned files:

- **#3280** (`ws-client` history-fetch → reducer-driven SM) — **Acknowledge**: this plan prefers pure changes in `chat-state-machine.ts`; only touch `ws-client.ts` if Path B needs a clock injection. Do not fold history-fetch refactor.
- **#3374** (`slot_reclaimed` WS frame) — **Acknowledge**: orthogonal reconnect/ledger surface; out of scope.

No fold-in required.

## Alternative Approaches Considered

| Approach | Why rejected / deferred |
|----------|-------------------------|
| Re-ship tool_progress server re-arm / cc forward | Already on main + prod SHA |
| Raise `STUCK_TIMEOUT_MS` only | Magic number; doesn't fix orphan error after escalate |
| Delete client stuck-watchdog | Removes genuine hang fail-closed |
| Re-arm `turnHardCap` on every `tool_progress` | Dissolves chatty-stall absolute (learning 2026-06-12) |
| Nav-rail work | Wrong scope |
| Soft non-terminal "stale" UI instead of error | Larger UX redesign; recovery rebind is smaller |

## User-Brand Impact

- **If this lands broken, the user experiences:** Concierge conversation shows a permanent red **"Agent stopped responding after: …"** mid-answer while tools continue, or a hang with no fail-closed exit if recovery is over-broad.
- **If this leaks, the user's data / workflow is exposed via:** N/A for recovery (no new data path). Hard-cap raise only extends agent compute time already authorized for the session — no new egress or secret surface.
- **Brand-survival threshold:** `single-user incident` — core chat trust surface.

> CPO sign-off required at plan time before `/work` (pipeline: Domain Review CPO advisory below; operator may re-affirm). `user-impact-reviewer` at review-time.

## Observability

```yaml
liveness_signal:
  what: "Existing Concierge WS stream + client bubble state; prod health build_sha; runner structured logs for runner_runaway reason=idle_window|max_turn_duration"
  cadence: "per turn / per deploy"
  alert_target: "Sentry web-platform (existing reportSilentFallback ops tool-progress-shape, onToolProgress); operator via health JSON"
  configured_in: "apps/web-platform/server/soleur-go-runner.ts (runaway logs); apps/web-platform/server/cc-dispatcher.ts (onToolProgress); GET /health"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN; runner log.warn runner_runaway fired"
  fail_loud: "User sees workflow_ended / runner_runaway copy OR genuine hang error banner; recovery path should NOT leave permanent red banner while tools advance"

failure_modes:
  - mode: "False Stage-2 escalate leaves orphan error while tools continue"
    detection: "Unit tests for rebind; dogfood long turn; absence of dual error+live chip pattern"
    alert_route: "PR review + post-deploy health/dogfood"
  - mode: "Recovery never escalates genuine hang"
    detection: "Unit test: error bubble + no events remains error; Stage-2 after rebind silence escalates again"
    alert_route: "CI vitest"
  - mode: "max_turn_duration kills legitimate long one-shot under 45m"
    detection: "log.warn runner_runaway reason=max_turn_duration with elapsedMs; Sentry/query logs post-deploy"
    alert_route: "Structured log search (self-pull), not dashboard eyeball"
  - mode: "Web Platform Release image_pull_failed — fix not live"
    detection: "curl -sS https://app.soleur.ai/health | jq .build_sha not containing merge"
    alert_route: "Ship post-merge verification"

logs:
  where: "web-platform container / structured pino logs; Sentry events for shape-guard"
  retention: "Sentry project retention; container log retention per host config"

discoverability_test:
  command: "curl -sS --max-time 10 https://app.soleur.ai/health | jq '{status,version,build_sha}'"
  expected_output: "status ok; build_sha equals or is descendant of the merge commit that contains the recovery helper"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** Given a `cc_router` text bubble in `error` (evicted from `activeStreams`), when a `tool_use` for `cc_router` arrives, then the bubble returns to `tool_use` (or transitional), leader is in `activeStreams`, and **no** permanent orphan error remains as the tip for that leader.
- [ ] **AC2:** Given the same error bubble, when `tool_progress` arrives, then timer reset intent is emitted and state is non-error transitional.
- [ ] **AC3:** Given error bubble and **no** further events, then bubble stays `error` (fail-closed).
- [ ] **AC4:** Genuine double timeout without heartbeats still reaches `error` from a live transitional bubble (existing Stage-2 tests remain green).
- [ ] **AC5:** `DEFAULT_MAX_TURN_DURATION_MS === 45 * 60 * 1000`; existing tests that pin 10 min updated; `tool_progress` still does **not** re-arm `turnHardCap` (existing AC3-class test).
- [ ] **AC6:** Vitest suites listed in Phase 1 pass via `cd apps/web-platform && ./node_modules/.bin/vitest run <paths>` (not `npm run -w`).
- [ ] **AC7:** ADR-022 amended with the new absolute ceiling sentence.
- [ ] **AC8:** No nav-rail / settings-resume files in the diff.

### Post-merge (operator-automatable)

- [ ] **AC9:** `curl -sS https://app.soleur.ai/health | jq -r .build_sha` matches deployed fix (or ship notes deploy block with health JSON). Automation: `curl` + `jq` in `/soleur:ship` post-merge verification — **not** dashboard-only.
- [ ] **AC10:** Long Concierge turn with continuous tool activity does not paint terminal "Agent stopped responding after: …" while tools advance (Playwright Concierge dogfood if harness exists; else scripted WS fixture integration test if present).

## Test Scenarios

1. **Given** `cc_router` bubble `error` and empty `activeStreams`, **when** `tool_use` label "Running command…", **then** rebind + `timerAction.reset` + state `tool_use`.
2. **Given** error bubble, **when** `tool_progress`, **then** non-error + reset (no chip).
3. **Given** error bubble, **when** nothing for >90s wall in unit terms (two applyTimeouts not applicable once evicted — assert sticky error), **then** remains error.
4. **Given** transitional bubble + two timeouts without heartbeats, **then** still error (regression).
5. **Given** heartbeats every 7s for > prior idle window, **then** no idle `runner_runaway` (existing).
6. **Given** turn longer than 10 min but under 45 min of agent compute with activity, **then** no `max_turn_duration` (new / updated timer test with injected clock).
7. **Given** silent hung tool >90s, **then** `idle_window` still fires (existing AC2b).

## Domain Review

**Domains relevant:** Engineering, Product, Support

### Engineering (CTO)

**Status:** reviewed  
**Assessment:** Dominant residual is client orphan-terminal after Stage-2 eviction interacting with cc_router chip-only `tool_use`. Server heartbeats are already load-bearing and live on prod SHA — do not re-implement. Hard-cap raise to 45m is a product budget change; keep idle 90s and never re-arm hard cap on `tool_progress`. Recovery helper must be pure and exhaustively tested for fail-closed. Path B lastLiveness is optional complexity — prefer Path A only unless races demand it.

### Support (CCO)

**Status:** reviewed  
**Assessment:** Symptom is a high-trust support ticket class ("agent died but debug still moves"). Fix reduces false tickets; genuine hang banner remains for real freezes. Post-deploy dogfood AC matters more than copy changes.

### Product/UX Gate

**Tier:** advisory (behavior of existing error banner; no new component files under `components/**`)  
**Decision:** auto-accepted (pipeline)  
**Agents invoked:** none (no new UI surface; recovery clears existing error state)  
**Skipped specialists:** none  
**Pencil available:** N/A (no UI surface)

#### Findings

No new screens. CPO sign-off framing: single-user incident on chat trust; recovery must not hide real hangs. Brand copy for genuine hang unchanged.

## Architecture Decision (ADR/C4)

### ADR

- **Amend** `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` — absolute turn ceiling value (10 min → 45 min) and reaffirm: `tool_progress` re-arms idle only, never hard cap. Client recovery is an implementation detail of the existing stuck-watchdog (no new ADR required if hard-cap amend is the only architectural number change).

### C4 views

Checked `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` for actors/systems relevant to Concierge WS chat: existing Web Platform container + user browser already model the chat surface; no new external actor, vendor, or container; access relationship unchanged (same authenticated Concierge stream). **No C4 edit** — cite: no new external human actor, no new vendor edge, no container/data-store change, no tenancy boundary move.

### Sequencing

ADR amend lands in the same PR as the constant change.

## Hypotheses

Application-layer false stop (not network outage). Keyword `timeout` in the feature description matches the plan network-outage checklist **string** but the verified mechanism is client `applyTimeout` / server `armRunaway` / `armTurnHardCap` — not SSH, firewall, or HTTP 502/503/504.

| ID | Hypothesis | Status |
|----|------------|--------|
| H1 | Orphan client Stage-2 `error` + cc_router chip-only `tool_use` is the dominant UX residual | **Supported** by code path read |
| H2 | Missing `tool_progress` server re-arm on prod | **Falsified** — prod SHA includes re-arm |
| H3 | 10-min hard cap kills long one-shot with continuous tools | **Supported** by constant + ADR (distinct copy) |
| H4 | Network blip causes banner while tools continue | **Unlikely** — tools continuing proves WS/server alive; connection banner is separate (`#5282`) |
| H5 | L3 firewall / L7 proxy | **N/A** for this residual class |

## Verify-the-negative (deepen)

| Claim | Grep / read | Verdict |
|-------|-------------|---------|
| Recovery MUST NOT leave permanent error while tools advance | Planned AC1/AC2 + rebind on tool_use | Confirm at implement |
| `tool_progress` MUST NOT re-arm hard cap | `soleur-go-runner.ts` tool_progress branch only `armRunaway` | **Confirms** today; Phase 2 must keep |
| Recovery MUST NOT infinite-mask hang | AC3 sticky error without events | Confirm at implement |
| Nav-rail out of scope | Files list has no nav components | **Confirms** |
| Heartbeats already on prod | `git show 0853bd51:…/soleur-go-runner.ts` has tool_progress branch | **Confirms** |

## Technical Considerations

- **NFR:** reliability / fail-closed hang detection; user-perceived availability of long Concierge turns.
- **Performance:** recovery is O(n) scan from end of messages — bounded by conversation length; acceptable.
- **Security:** no new tool permissions; no auth change.
- **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` after reducer changes.
- **Union exhaustiveness:** no new WS variants required for Path A.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Recovery masks genuine hang forever | Fail-closed AC3; Stage-2 can re-fire after rebind silence; no permanent amnesty |
| Rebind wrong bubble after multi-turn history | Only recover latest text bubble for leader with `state===error` at tip semantics |
| 45 min absolute burns tokens on runaway chatty agent | Idle 90s still kills silence; 45m is chatty-loop ceiling; cost ceiling (`cost_ceiling`) remains separate |
| Deploy doesn't cut over | AC9 health SHA check |
| Path B adds clock/state complexity | Default skip Path B |

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6 — filled above.
- Do not re-arm hard cap on `tool_progress` (chatty-stall dissolution).
- `cc_router` chip path is load-bearing for pre-stream tools — only divert when recoverable error exists.
- Test runner is vitest under `apps/web-platform`; discovery globs are `test/**/*.test.ts(x)`.
- Typecheck is in-package `tsc`, not `npm run -w`.

## Success Metrics

- Zero user-visible orphan red banners during continuous-tool Concierge turns in dogfood.
- Genuine hang still surfaces error within ~90s client / 90s server idle.
- One-shot turns 10–45 min agent compute complete without `max_turn_duration`.

## Dependencies & Risks

- Depends on shipped heartbeats remaining present (Phase 0 grep).
- Web Platform Release health for cutover.
- Open dogfood #2869 may be closed after AC10 — not a plan `closes:` target.

## References & Research

- Prior plan: `knowledge-base/project/plans/2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md`
- Learnings: `2026-06-12-idle-watchdog-reset-on-sdk-heartbeat…`, `2026-06-15-watchdog-liveness-input-set-must-match-its-claim`, `2026-05-05-defense-relaxation-must-name-new-ceiling`
- Code: `apps/web-platform/lib/chat-state-machine.ts` (`applyTimeout`, `tool_use` chip branch, `tool_progress`, `debug_event`, `command_stream`)
- Code: `apps/web-platform/components/chat/message-bubble.tsx` error copy
- Code: `apps/web-platform/server/soleur-go-runner.ts` `DEFAULT_MAX_TURN_DURATION_MS`, `armRunaway`, `armTurnHardCap`
- Code: `apps/web-platform/server/cc-dispatcher.ts` `onToolProgress`
- Code: `apps/web-platform/server/cc-workflow-end-messages.ts` `runner_runaway` copy
- Prod: `GET https://app.soleur.ai/health` (plan-time `build_sha` `0853bd51…` already includes prior heartbeats)
- Closed follow-ups already shipped: #5214 (cc tool_progress forward), #5240 (debug/liveness) — **not** reopen as work targets

## MVP pseudo-code

### findRecoverableErrorBubble + tool_use rebind

```ts
// apps/web-platform/lib/chat-state-machine.ts
function findRecoverableErrorBubble(
  messages: ChatMessage[],
  leaderId: DomainLeaderId,
): number | undefined {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.type === "text" && m.leaderId === leaderId && m.state === "error") {
      return i;
    }
    // Stop if a newer live text bubble for this leader already exists
    if (
      m.type === "text" &&
      m.leaderId === leaderId &&
      (m.state === "thinking" || m.state === "tool_use" || m.state === "streaming" || m.state === "done")
    ) {
      return undefined;
    }
  }
  return undefined;
}

// inside case "tool_use" when !activeStreams.has(cc_router):
const recoverIdx = findRecoverableErrorBubble(prev, event.leaderId);
if (recoverIdx !== undefined) {
  const updated = [...prev];
  const { retrying: _r, livenessRearms: _l, ...rest } = updated[recoverIdx];
  updated[recoverIdx] = {
    ...rest,
    state: "tool_use",
    toolLabel: event.label,
    toolsUsed: [...(rest.toolsUsed ?? []), event.label],
    livenessRearms: 0,
  };
  const nextStreams = new Map(activeStreams);
  nextStreams.set(event.leaderId, recoverIdx);
  return {
    messages: updated,
    activeStreams: nextStreams,
    workflow: priorWorkflow,
    spawnIndex: priorSpawnIndex,
    timerAction: { type: "reset", leaderId: event.leaderId },
  };
}
// else existing chip path…
```
