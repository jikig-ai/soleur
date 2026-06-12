<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix: forward tool_progress to client on cc surface (terminal error bubble on >90s single tool)"
type: fix
issue: 5214
branch: feat-one-shot-fwd-tool-progress-cc-surface-5214
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-12
---

# fix: forward `tool_progress` to client on cc surface 🐛

> Closes #5214. Deferred follow-up filed unconditionally at the ship of PR #5208 /
> the prior plan `2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md`
> (`## Follow-ups` → "Client 45s watchdog on the cc surface").

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Files to Edit (JSDoc cadence note), Test Strategy (tests #3/#4/#5-#7), Acceptance Criteria (AC5-AC9)
**Research agents used:** verify-the-negative + precedent-diff + test-compatibility (sonnet), architecture-strategist, test-design-reviewer; local: repo-research-analyst, learnings-researcher

### Key Improvements

1. **Test #3 clock-drive fixed (vacuous-GREEN guard):** the cc-dispatcher debounce
   compares `Date.now()`; `vi.advanceTimersByTime` alone leaves it at 0 and collapses all
   emits into one window. Test now drives `vi.setSystemTime()` per heartbeat (precedent
   `tool-progress-forwarding.test.ts:204-209`).
2. **Test #4 positive control added:** assert `armRunaway` actually fired (no
   `runner_runaway` after the idle window), not just that the malformed forward was
   dropped. Documents the intentional re-arm-on-malformed divergence from agent-runner.
3. **Client tests re-labeled as consumer-contract guards, not RED:** the
   `chat-state-machine.ts` consumer is already complete, so #5-#7 are GREEN pre-fix; the
   real-bug RED coverage lives in server tests #1+#2. Test #6 de-duplicated against the
   already-shipped chip-no-spawn assertion at `cc-soleur-go-end-to-end-render.test.tsx:176-187`.
4. **`onToolProgress?` JSDoc cadence contract:** the runner emits at SDK cadence
   (un-debounced); the JSDoc must instruct consumers to debounce (prevents a future
   second consumer from spamming the socket).

### New Considerations Discovered

- The shape-guard/debounce seam (guard in runner, debounce in dispatcher) is a *better*
  factoring than agent-runner's inline both-in-one (transport policy stays out of the
  surface-agnostic runner) — architecture-strategist confirmed no P0/P1, no drop/duplicate
  risk, blast radius = the two intended files (agent-runner does NOT use `DispatchEvents`).
- All 5 plan invariants (raw-name-not-on-wire, consumer-unchanged, WS-variant-exists,
  cc_router-registered, includePartialMessages-set) verified `confirms` against code.
- 9 test files construct `DispatchEvents`-shaped objects; none break on the optional-field
  widening (`tsc --noEmit` clean) — no fixture sweep needed.

## Overview

On the Concierge (cc / `soleur-go`) surface, `apps/web-platform/server/cc-dispatcher.ts`
does **not** forward SDK `tool_progress` WS events to the client. The client-side
stuck-watchdog `STUCK_TIMEOUT_MS` (45s, `apps/web-platform/lib/ws-constants.ts:14`)
is therefore **not heartbeat-fed** during a long single-tool execution — unlike the
legacy `agent-runner` surface, which forwards `tool_progress` at
`agent-runner.ts:1889-1948`.

Consequence on a **>90s single tool** (routine for any `Read` / `Bash` / web-search
on large input):

1. First client timeout at **45s** → the bubble shows the "Retrying…" chip and resets.
2. A second consecutive timeout at **~90s** drives the client bubble to a **terminal
   `error`** state (`chat-state-machine.ts` `applyTimeout` stage 2) and evicts the
   leader from `activeStreams`.
3. The eventual real answer renders as a **new bubble appended below the orphaned
   error bubble** — the user sees "the agent failed" immediately followed by the answer.

PR #5208 fixed the **server-side** premature `runner_runaway` by re-arming the server
idle watchdog on `tool_progress` in `soleur-go-runner.ts:2170`. That is a distinct
timer and the server fix stands alone — but by keeping the stream alive longer, it
**increases the reachability** of this client-side residual (the >90s path now reaches
the client's second-timeout terminal logic more often, no longer masked by a premature
server teardown). See learning
`knowledge-base/project/learnings/best-practices/2026-06-12-idle-watchdog-reset-on-sdk-heartbeat-and-upstream-fix-exposes-downstream-timeout.md`.

### Root-cause precision (verified against code, not the issue prose)

The cc surface delegates to `soleur-go-runner.ts` via a runner whose events reach the
client through `cc-dispatcher.ts`'s `events: DispatchEvents` object. The runner's
`consumeStream` loop at `soleur-go-runner.ts:2170` **already handles** `tool_progress`,
but the branch comment is explicit: *"Deliberately reads NO fields off the message (a
pure re-arm)"* — it re-arms the server watchdog **only** and emits **no DispatchEvent**.
So nothing reaches the client.

This means the fix is **two-layer**, not a single `sendToClient` line:

- **Runner layer** (`soleur-go-runner.ts`): the `DispatchEvents` interface has no
  `onToolProgress` callback, and the `tool_progress` branch never invokes one. The
  runner must EMIT a `tool_progress` event (shape-guarded) in addition to re-arming.
- **Dispatcher layer** (`cc-dispatcher.ts`): the `events` object passed to
  `runner.dispatch` (~line 2448) has no `onToolProgress` wiring. It must forward to the
  client via the existing `tool_progress` WS message variant.

Everything downstream of the dispatcher is **already complete** (no change required):

- The `tool_progress` WS message variant already exists: `lib/types.ts:319`,
  `lib/ws-zod-schemas.ts:280` (`toolProgressSchema`), `lib/ws-known-types.ts:43`.
- `lib/ws-client.ts:688` already passes `tool_progress` through to the reducer.
- `lib/chat-state-machine.ts:490` (`case "tool_progress"`) already (a) resets the
  watchdog via `timerAction: { type: "reset", leaderId }` and (b) clears the `retrying`
  chip — and the Stage-4 (#2886) guard ensures it does NOT spawn a chip.
- `cc_router` is a valid `DomainLeaderId` (`lib/ws-zod-schemas.ts:53`) and the existing
  cc `tool_use` forward already uses `leaderId: CC_ROUTER_LEADER_ID` successfully — so
  the consumer's `activeStreams.get("cc_router")` lookup will resolve (it is NOT the
  "unknown leader inert no-op" branch).

The **load-bearing precondition** holds: the cc path sets `includePartialMessages: true`
via the shared `buildAgentQueryOptions` (`agent-runner-query-options.ts:160`, consumed by
`realSdkQueryFactory` at `cc-dispatcher.ts:1214`), so `tool_progress` messages already
arrive in the runner loop. No SDK option change is needed.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "add a `tool_progress` WS forward in cc-dispatcher.ts (~line 2107) alongside existing stream/tool_use forwards" | cc-dispatcher does NOT iterate SDK messages itself; it wires `DispatchEvents` callbacks (`events.onText`/`onToolUse`/… at ~2448). The runner (`soleur-go-runner.ts`) owns the SDK loop and swallows `tool_progress` (pure re-arm, no event). | Two-layer fix: add `onToolProgress?` to `DispatchEvents` + emit from the runner's `tool_progress` branch (2170); wire `events.onToolProgress` in cc-dispatcher to `sendToClient`. The "~line 2107" anchor is approximate; the real wire-site is the `events` object at ~2448. |
| "verify chat-state-machine.ts consumer (~line 490) resets STUCK_TIMEOUT_MS on tool_progress" | Verified: `chat-state-machine.ts:490` resets the watchdog AND clears the `retrying` chip; the Stage-4 #2886 guard prevents chip spawn. | **No change** to chat-state-machine. RED tests assert the existing consumer fires once cc-forwarded events arrive. |
| "wire ws-constants.ts / WS message-type as needed" | The `tool_progress` WS variant + zod schema + ws-client passthrough all already exist (used by agent-runner). `ws-constants.ts` holds only `STUCK_TIMEOUT_MS = 45_000` (no change needed). | **No new WS message type**, **no ws-constants edit**. Reuse the existing `tool_progress` variant. |
| "mirroring agent-runner" | agent-runner inlines a 5s debounce (`TOOL_PROGRESS_DEBOUNCE_MS = 5_000`, `toolProgressLastSentAt` Map at `agent-runner.ts:1864-1933`) + runtime shape-guard + `buildToolLabel` routing. | Mirror the debounce + shape-guard. Extract a shared `buildToolProgressWSMessage` into `tool-labels.ts` (parity with the #3235 `buildToolUseWSMessage` sharing pattern), so a future schema change is one edit. |

## User-Brand Impact

**If this lands broken, the user experiences:** on the Concierge chat surface, a >90s
single tool (routine `Read`/`Bash`/web-search) paints a terminal "the agent failed"
error bubble, immediately followed by the real answer rendered as a separate orphaned
bubble below it — the product's core conversation surface looks broken on routine traffic.

**If this leaks, the user's data is exposed via:** N/A for data leakage — but note the
**information-disclosure invariant**: the raw SDK `tool_name` must NEVER reach the wire
(see #2138 / PR #2115). The forward MUST route `tool_name` through `buildToolLabel`
(human label only), exactly as the `tool_use` forward does. A regression here would leak
internal tool implementation names to the client.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. The threshold and framing are
> carried forward verbatim from the prior plan's `## Follow-ups` severity correction
> (user-impact-reviewer, PR #5208 review). `user-impact-reviewer` will be invoked at
> review-time per `plugins/soleur/skills/review/SKILL.md`.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts`
  - Add `onToolProgress?: (block: { toolUseId: string; toolName: string; elapsedSeconds: number }) => void;`
    to the `DispatchEvents` interface (~798-866), with a JSDoc block mirroring the
    `onToolResult?` / `onTextTurnEnd?` doc convention (when it fires, why optional,
    fire-and-forget, the information-disclosure note that raw `tool_name` is routed
    through `buildToolLabel` at the dispatcher boundary). **The JSDoc MUST state that the
    callback fires at SDK cadence (un-debounced) — every `tool_progress` message the SDK
    yields — and that consumers MUST debounce before hitting the socket** (deepen-plan
    architecture + verify-negative finding: the runner emits raw cadence; cc-dispatcher
    owns the 5s debounce, so a future second consumer that forgets to debounce would spam).
  - In the `tool_progress` branch of `consumeStream` (line 2170): AFTER the existing
    `if (!state.closed && !state.awaitingUser) armRunaway(state);`, extract
    `tool_use_id` / `tool_name` / `elapsed_time_seconds` with the **same runtime
    shape-guard** as `agent-runner.ts:1901-1927` (string `toolUseId` non-empty, string
    `toolName`, number `elapsedSeconds`; on mismatch `reportSilentFallback({ feature:
    "soleur-go-runner", op: "tool-progress-shape" })` and skip the emit — NOT the
    re-arm). Invoke `state.events.onToolProgress?.({ toolUseId, toolName, elapsedSeconds })`
    inside a `try/catch` → `reportSilentFallback({ feature: "soleur-go-runner", op:
    "onToolProgress" })`, matching the `onTextTurnEnd` invocation pattern (lines 2133-2141).
    **Update the existing branch comment** ("reads NO fields") to reflect that it now
    forwards a heartbeat event.

- `apps/web-platform/server/tool-labels.ts`
  - Add `export function buildToolProgressWSMessage(args: { toolName: string;
    elapsedSeconds: number; toolUseId: string; workspacePath: string | undefined;
    leaderId: DomainLeaderId }): WSMessage` returning
    `{ type: "tool_progress", leaderId, toolUseId, toolName: buildToolLabel(toolName,
    undefined, workspacePath), elapsedSeconds }`. JSDoc cites #3235 sharing + the #2138
    raw-name invariant, exactly like `buildToolUseWSMessage` (269-280). `tool_input` is
    not part of `SDKToolProgressMessage`, so `buildToolLabel(name, undefined, …)` falls
    to `FALLBACK_LABELS` — fine for a heartbeat label (mirrors `agent-runner.ts:1944`).

- `apps/web-platform/server/cc-dispatcher.ts`
  - Import `buildToolProgressWSMessage` from `./tool-labels` (the file already imports
    `buildToolUseWSMessage` at line 144).
  - In `dispatchSoleurGo`, declare a per-dispatch debounce alongside the `events` object
    (~before line 2448): `const TOOL_PROGRESS_DEBOUNCE_MS = 5_000;` and
    `const toolProgressLastSentAt = new Map<string, number>();` (mirrors
    `agent-runner.ts:1864-1865`; per-dispatch scope matches the per-call cleanup model —
    no module-level cache, so no eviction concern per learning
    `2026-05-11-debounce-cache-needs-eviction-and-symmetric-state-reset.md`).
  - Add an `onToolProgress` property to the `events: DispatchEvents` object that:
    debounces per `toolUseId` (first heartbeat always forwards; subsequent wait the 5s
    window), then `sendToClient(userId, buildToolProgressWSMessage({ toolName,
    elapsedSeconds, toolUseId, workspacePath, leaderId: CC_ROUTER_LEADER_ID }))`.
  - **Debug-stream parity check (NOT a forward):** the `onText` / `onToolUse` callbacks
    also `emitDebugEvent`. `tool_progress` is a heartbeat with no displayable payload and
    the debug panel has no `tool_progress` `kind` (`debugEventSchema.kind` is
    `["tool_use","reasoning","result"]`, `ws-zod-schemas.ts`); do NOT emit a debug event
    for `tool_progress` (parity with `agent-runner`, which does not). Note this in a
    one-line comment so a future reader does not "fix" the omission.

## Files to Create

- `apps/web-platform/test/cc-dispatcher-tool-progress-forwarding.test.ts` — RED tests
  for the runner-emit + cc-dispatcher-forward path (server side).
- `apps/web-platform/test/cc-soleur-go-tool-progress-no-terminal-error.test.tsx` — RED
  tests for the client reducer behavior under a >90s single tool (chat-state-machine via
  the cc surface), asserting no terminal-error flip and no Retrying chip.

> Both paths must satisfy the vitest `include` globs: `test/**/*.test.ts` (node) and
> `test/**/*.test.tsx` (happy-dom) — `apps/web-platform/vitest.config.ts:44,60`. Do NOT
> co-locate under `components/**` (silently never run).

## Test Strategy (RED → GREEN)

Runner is **vitest** via `./node_modules/.bin/vitest run <path>` (NOT `npm -w`).
Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Fixtures
`makeToolProgress(toolUseId, elapsedSeconds)` (`test/helpers/soleur-go-fixtures.ts:159`),
`makeRecordingEvents()`, and `createMockQueryScripted()` already exist. The
agent-runner precedent suite is `test/tool-progress-forwarding.test.ts` — mirror its
assertion shape. The closest runner-idle-reset precedent is
`test/soleur-go-runner-tool-result-idle-reset.test.ts`.

### Server-side RED tests (`cc-dispatcher-tool-progress-forwarding.test.ts`)

1. **Runner emits `onToolProgress`:** drive `createSoleurGoRunner` with
   `makeRecordingEvents()`, `mock.emit(makeToolProgress("tu-1", 5))`, flush; assert the
   recording captured `{ toolUseId: "tu-1", elapsedSeconds: 5, toolName: <raw "Read"> }`.
   (RED: no `onToolProgress` exists yet.)
2. **Dispatcher forwards a `tool_progress` WS message:** via the cc-dispatcher harness
   (`test/helpers/cc-dispatcher-harness.ts`) + a `mockSendToClient`, emit a
   `tool_progress` and assert `mockSendToClient` received
   `{ type: "tool_progress", leaderId: "cc_router", toolUseId: "tu-1", toolName:
   <human label, NOT "Read">, elapsedSeconds: 5 }`. Assert `toolName !== "Read"`
   (the #2138 raw-name invariant — vacuous-RED guard: pick a fixture whose human label
   differs from the raw name).
3. **Debounce ≤1/5s per `toolUseId`:** `vi.useFakeTimers()`; emit `tool_progress` at
   t=0, t=2s, t=6s for the same `tu-1`; assert exactly 2 forwards (t=0 and t=6s).
   Distinct `toolUseId`s each forward independently. **CLOCK-DRIVE (vacuous-GREEN guard,
   deepen-plan test-design finding):** the debounce compares `Date.now()`, so
   `vi.advanceTimersByTime` ALONE leaves `Date.now()` at 0 and all three emits collapse
   into one window (wrong-reason result). Drive the clock with `vi.setSystemTime()` as
   each heartbeat is consumed, mirroring the agent-runner precedent
   `test/tool-progress-forwarding.test.ts:204-209`.
4. **Shape-guard:** emit a malformed `tool_progress` (missing `tool_use_id`) **as the
   sole `tool_progress` in the test** (no prior well-formed emit, so the "no forward"
   assertion is attributable solely to the shape-guard, NOT a debounce window — per
   learning `2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`); assert
   NO forward and `reportSilentFallback` `op: "tool-progress-shape"`. **POSITIVE CONTROL
   (deepen-plan finding):** assert the server watchdog re-arm (`armRunaway`) STILL fired —
   advance past the idle window and confirm NO `runner_runaway` is emitted, mirroring the
   re-arm assertion in `test/soleur-go-runner-tool-result-idle-reset.test.ts:132-140`. The
   malformed-drop assertion alone does not prove the re-arm survived. (This is the
   intentional divergence from agent-runner, which `continue`s past BOTH emit and re-arm on
   a shape fail; the soleur-go runner re-arms on malformed-but-present `tool_progress`
   because the message itself proves the tool is alive — strictly safer.)

### Client-side consumer-contract guard tests (`cc-soleur-go-tool-progress-no-terminal-error.test.tsx`)

> **Not RED for the forwarding defect (deepen-plan test-design finding).** The
> `chat-state-machine.ts` consumer is already complete (line 490 + `applyTimeout`
> 1068-1113), so these tests run against an UNCHANGED reducer and are GREEN both before
> and after the fix. Their value is **regression-locking the consumer contract the new
> forward feeds** — so a future refactor of `chat-state-machine.ts` cannot silently break
> the heartbeat path. The RED coverage of the actual bug (cc-dispatcher not forwarding)
> lives in **server tests #1 (runner emit) + #2 (dispatcher WS shape)**. Do not inflate
> the RED count: server #1-#4 are RED; client #5-#7 are characterization guards.

Drive the `applyStreamEvent` reducer + `applyTimeout` directly (the
`cc-soleur-go-end-to-end-render.test.tsx` `replay()` pattern; assertions on `data-*` /
reducer state, never layout).

5. **>90s single tool does NOT flip to terminal error WHEN `tool_progress` arrives:**
   replay stream-start (leader `cc_router`) → `tool_use` → `applyTimeout` (first, 45s →
   `retrying: true`) → `applyStreamEvent({ type: "tool_progress", leaderId: "cc_router" })`
   → assert `retrying` cleared and watchdog reset → `applyTimeout` again must NOT reach
   stage-2 terminal because the heartbeat reset the consecutive-timeout counter; assert
   `messages[idx].state !== "error"` and `activeStreams.has("cc_router") === true`.
6. **Retrying chip cleared on a progressing tool:** after a first timeout sets
   `retrying: true`, a `tool_progress` event clears it (`retrying` undefined). NOTE the
   "no `tool_use_chip` spawn on `tool_progress`" half is ALREADY covered by
   `cc-soleur-go-end-to-end-render.test.tsx:176-187` — do NOT duplicate that assertion;
   this test's distinct contribution is the `retrying`-clear transition (first-timeout →
   heartbeat → retrying undefined), which the existing test does not exercise.
7. **Control / regression-preserving (NOT a fix-of-the-fix):** a tool that emits NO
   `tool_progress` and times out twice STILL flips to terminal `error` and evicts the
   leader — proves the fix does not relax genuine-failure detection. (Defense-pair per
   learning `2026-05-06-sdk-forward-progress-tool-use-result-resets-per-block-idle.md`.)

### GREEN sweep

- After widening `DispatchEvents`, run `cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit`. The new callback is **optional** (`?`), so existing inline `DispatchEvents`
  constructors in tests do NOT need updating — but run tsc to confirm (per learning
  `2026-05-07-tdd-ts-expect-error-sweep-and-reducer-fixture-sweep.md`).
- `git grep -n "onToolProgress" apps/web-platform/` to confirm exactly the runner
  (definition + invocation) and the cc-dispatcher (wiring) reference it. agent-runner is
  NOT extended (it uses its own inline forward; `DispatchEvents` is a soleur-go concept).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `DispatchEvents` in `soleur-go-runner.ts` has an optional
  `onToolProgress?` callback with a JSDoc block; `git grep -n "onToolProgress?" apps/web-platform/server/soleur-go-runner.ts`
  returns the declaration.
- [x] **AC2** The `tool_progress` branch at `soleur-go-runner.ts:~2170` invokes
  `state.events.onToolProgress?.(...)` inside a `try/catch` AND still calls `armRunaway`;
  the runner-emit RED test (server test #1) passes.
- [x] **AC3** `buildToolProgressWSMessage` exists in `tool-labels.ts` and routes
  `toolName` through `buildToolLabel`; a unit assertion confirms the returned `toolName`
  is the human label, NOT the raw input (`toolName !== "Read"`).
- [x] **AC4** cc-dispatcher's `events` object wires `onToolProgress` →
  `sendToClient(... type: "tool_progress", leaderId: CC_ROUTER_LEADER_ID ...)`; server
  test #2 asserts the forwarded WS shape.
- [x] **AC5** Debounce holds: server test #3 asserts ≤1 forward per 5s per `toolUseId`
  (2 forwards across t=0/t=2s/t=6s), driving the clock via `vi.setSystemTime()` per
  heartbeat (NOT `advanceTimersByTime` alone — the debounce reads `Date.now()`).
- [x] **AC6** Shape-guard holds: server test #4 asserts a malformed `tool_progress`
  produces no forward + a `reportSilentFallback` `op: "tool-progress-shape"`, AND the
  positive control confirms the watchdog re-arm fired (no `runner_runaway` after the idle
  window).
- [x] **AC7** Client guard test #5 passes: a >90s single tool that emits `tool_progress`
  does NOT flip the `cc_router` bubble to `state: "error"` and does NOT evict it from
  `activeStreams`. (Consumer-contract guard — GREEN pre-fix; locks the reducer the forward
  feeds.)
- [x] **AC8** Client guard test #6 passes: the "Retrying…" chip's `retrying` flag is
  cleared by a `tool_progress` event (the chip-no-spawn half is already covered by
  `cc-soleur-go-end-to-end-render.test.tsx:176-187`; not duplicated).
- [x] **AC9** Control guard test #7 passes: a tool emitting NO `tool_progress` STILL flips
  to terminal error after two timeouts (genuine-failure detection preserved — defense-pair).
- [x] **AC10** `chat-state-machine.ts` and `ws-constants.ts` are UNCHANGED
  (`git diff --stat` shows neither file) — the consumer + constant already support this.
- [x] **AC11** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [x] **AC12** `./node_modules/.bin/vitest run test/cc-dispatcher-tool-progress-forwarding.test.ts
  test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` is green; the existing
  `test/tool-progress-forwarding.test.ts` (agent-runner) and `test/chat-state-machine.test.ts`
  remain green (no regression).
- [x] **AC13** PR body uses `Closes #5214`.

### Post-merge (operator)

- None. Pure client-WS-forwarding code change against an already-provisioned surface;
  the `web-platform-release.yml` pipeline restarts the container on merge to
  `apps/web-platform/**`. No migration, secret, infra, or dashboard step.

## Domain Review

**Domains relevant:** Product (UX gate)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — N/A (no UI-surface file created/edited)
**Pencil available:** N/A (no UI surface)

#### Findings

This is a back-end WS-forwarding fix on the chat surface. It creates/edits **no**
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` file — the mechanical
UI-surface override does not fire. The user-visible effect (no spurious terminal-error
bubble) is a *correctness restoration* of existing rendered behavior, not a new
interactive surface or copy change. The `chat-state-machine.ts` reducer that owns the
bubble lifecycle is unchanged. No wireframe is required.

## Infrastructure (IaC)

None. The plan edits only files under `apps/web-platform/server/` and
`apps/web-platform/`-adjacent test dirs against an already-provisioned surface. No
server, service, cron, secret, DNS, vendor account, or persistent runtime process is
introduced. Phase 2.8 detection scan run: no manual-provisioning, systemd, secret-write,
terraform, cron, or vendor-dashboard pattern appears in the implementation steps. Skip.
(The ack comment at the top of this file is for the negative-detection list in this
section — the gate matched a literal token used only to assert its absence.)

## Observability

```yaml
liveness_signal:
  what: cc tool_progress forward count is observable via the existing WS frame stream; a regression (forward stops) re-manifests as the terminal-error bubble it fixes — and the reverse direction (shape-guard trips) emits a Sentry breadcrumb (below).
  cadence: per long-running tool (<=1 forward / 5s / toolUseId)
  alert_target: Sentry (existing project) — no new alert needed; the shape-guard breadcrumb is the new signal.
  configured_in: apps/web-platform/server/soleur-go-runner.ts (reportSilentFallback op tool-progress-shape) + cc-dispatcher onToolProgress wiring
error_reporting:
  destination: Sentry via reportSilentFallback (existing helper, already imported in both files)
  fail_loud: true — a malformed SDKToolProgressMessage mirrors to Sentry (op tool-progress-shape) before being dropped; an onToolProgress callback throw mirrors (op onToolProgress) without blocking the stream.
failure_modes:
  - mode: SDK reshapes SDKToolProgressMessage (missing tool_use_id/tool_name/elapsed) -> forward silently dropped
    detection: reportSilentFallback op "tool-progress-shape" in Sentry
    alert_route: Sentry issue (existing inbound)
  - mode: onToolProgress callback throws in cc-dispatcher (e.g., sendToClient closure error)
    detection: reportSilentFallback op "onToolProgress" in Sentry
    alert_route: Sentry issue (existing inbound)
  - mode: includePartialMessages flips to false upstream -> tool_progress stops arriving (regression of precondition)
    detection: the terminal-error bubble re-appears on >90s tools (user-reported); grep-discoverable comment cites agent-runner-query-options.ts:160 as the load-bearing line
    alert_route: user report / QA on cc surface
logs:
  where: pino structured logs (existing) on the reportSilentFallback paths; no new log surface
  retention: existing platform retention
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher-tool-progress-forwarding.test.ts
  expected_output: forward + debounce + shape-guard assertions green (proves the emit path and the Sentry-mirror path are both reachable without remote shell access)
```

## Open Code-Review Overlap

4 open `code-review` issues touch the edited files; **none** overlap the tool_progress
concern — all acknowledged (no fold-in):

- **#2220** (inject idFactory into applyStreamEvent — reducer purity) — different
  concern; this plan does not touch `chat-state-machine.ts`. **Acknowledge.**
- **#2224** (chat code-quality polish — JSX indentation, bubble factory) — different
  concern; no chat-component edits. **Acknowledge.**
- **#3242** (tool_use WS event lacks raw name field for agent consumers, Ref #3235) —
  adjacent (`tool-labels.ts`), but it argues the OPPOSITE direction (expose raw name for
  agents); this fix preserves the #2138 human-label-only invariant on the new
  `tool_progress` forward. Not folded — distinct design question. **Acknowledge.**
- **#3243** (decompose cc-dispatcher.ts into modules, Ref #3235) — architectural
  refactor of the whole file; out of scope for a targeted forward fix. **Defer** (no
  re-eval note needed; this fix does not affect the decomposition).

## Hypotheses

N/A — root cause is verified directly against code (zero `tool_progress` mentions in
`cc-dispatcher.ts`; the runner branch comment confirms the pure-re-arm-no-emit
behavior). Not a network/connectivity issue.

## Risks & Mitigations

- **Cadence invariant (inherited from PR #5208 plan):** the fix is correct only if the
  SDK `tool_progress` emit interval `< STUCK_TIMEOUT_MS (45s)`. The <=5s debounce floor
  (and the runner's own re-arm cadence) makes this hold with large margin. Named here so
  a future SDK throttle is grep-discoverable.
- **`includePartialMessages` precondition:** silently regresses if
  `agent-runner-query-options.ts:160` flips to `false` (`tool_progress` would stop
  arriving for BOTH surfaces). The runner branch already carries a comment citing that
  line; the new emit code reuses the same branch, so the precondition note is co-located.
- **Raw-name leak (#2138 / PR #2115):** mitigated by routing `tool_name` through
  `buildToolLabel` in the shared `buildToolProgressWSMessage` — AC3 + server-test #2
  assert the wire carries the human label, not the raw SDK name.
- **DoS / absolute-ceiling (defense-relaxation, learning
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md`):** this plan does NOT relax
  any server ceiling — the server `turnHardCap` (10-min, anchored on `firstToolUseAt`,
  PR #3225) is untouched, and the client reducer's terminal-error path still fires when
  `tool_progress` is ABSENT (AC9). The fix feeds an *existing* client watchdog; it adds
  no new unbounded timer. The client `STUCK_TIMEOUT_MS` reset on `tool_progress` already
  shipped for the agent-runner surface (#2861) and is itself bounded by the
  second-consecutive-timeout terminal logic when heartbeats stop.
- **Precedent-diff (deepen-plan Phase 4.4):** the pattern precedent is
  `agent-runner.ts:1889-1948` (`tool_progress` forward) — diff the new runner-emit +
  cc-dispatcher-forward against it for shape-guard / debounce / label parity.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — this section carries a concrete artifact, vector, and the
  `single-user incident` threshold (inherited verbatim from the PR #5208 follow-up).
- The new test files MUST live at `apps/web-platform/test/*.test.ts` /
  `test/*.test.tsx` — vitest collects `test/**/*.test.{ts,tsx}`, NOT co-located
  `components/**` or `server/**` (`vitest.config.ts:44,60`).
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT
  `npm run -w` (no root `workspaces` field).
- The issue's "~line 2107" cc-dispatcher anchor is approximate and points into a
  helper region, NOT the forward site. The real wire-site is the `events: DispatchEvents`
  object at ~line 2448 (where `onText`/`onToolUse` are wired). Do not patch line 2107.
- The fix is **two-layer** (runner emit + dispatcher forward). A single `sendToClient`
  line in cc-dispatcher would have nothing to call — the runner swallows `tool_progress`
  today (`soleur-go-runner.ts:2170` pure re-arm). Both layers are required.
- `chat-state-machine.ts` is **already complete** — adding a duplicate `tool_progress`
  reset there would be wrong (double-reset / chip regression). The only client-side
  change is the two new RED test files; AC10 enforces the reducer stays untouched.
