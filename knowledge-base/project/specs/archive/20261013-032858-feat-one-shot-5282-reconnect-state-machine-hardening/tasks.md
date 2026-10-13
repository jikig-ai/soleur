---
feature: reconnect state-machine hardening (#5282)
plan: knowledge-base/project/plans/2026-06-14-feat-reconnect-state-machine-hardening-plan.md
branch: feat-one-shot-5282-reconnect-state-machine-hardening
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — Reconnect State-Machine Hardening (#5282)

Derived from the finalized (post-deepen) plan. TDD throughout (`cq-write-failing-tests-before`).
Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.

## Phase 0 — Preconditions (grep-verify, no code)

- [ ] 0.1 `grep -n "case " apps/web-platform/lib/chat-state-machine.ts` — confirm 16 `applyStreamEvent` arms; this module stays untouched.
- [ ] 0.2 `grep -n "case " apps/web-platform/lib/ws-client.ts` (chatReducer L254-388) — enumerate `ChatAction` arms.
- [ ] 0.3 **Enumerate all 5 `clear_streams` sites** (`grep -n 'clear_streams' apps/web-platform/lib/ws-client.ts` → :552, :589, :781, :859, :1003) and classify each user-new-turn vs socket-churn/abort. Confirm :589 (`connect()`) fires every reconnect ⇒ cannot be the connection-reset hatch.
- [ ] 0.4 Read ws-client.ts:32 (`ConnectionStatus`), :417-487, :714-736 (auth_ok), :1014-1024 (`stream_replay incomplete`), :858-896 (`session_ended`), :1043-1117 (onclose), :1446 (`sendMessage`).
- [ ] 0.5 Read the EXISTING State-1 banner at `chat-surface.tsx:567-580` + `:891` "Reconnecting…" text — this is a rewire target.
- [ ] 0.6 Read `.pen` `content` nodes for State 1/2/3/4 copy.
- [ ] 0.7 `cd apps/web-platform && ./node_modules/.bin/vitest run` baseline green.
- [ ] 0.8 Re-run open code-review overlap query (two-stage `gh --json` then `jq --arg`) against the planned files.

## Phase 1 — Connection-state slice + actions (TDD)

- [ ] 1.1 (FR1) Define `ConnectionPhase = "live" | "reconnecting" | "unrecoverable"`; add `connection: { phase: ConnectionPhase }` to `ChatState` (ws-client.ts:206-226), initial `{ phase: "live" }`. Document the `ConnectionStatus` → phase mapping inline.
- [ ] 1.2 (FR2) RED: write `test/chat-state-machine-connection.test.ts` flap test (live→reconnecting→live→reconnecting ⇒ phase=reconnecting). GREEN: add `{ type: "connection_change"; phase }` to `ChatAction` + `chatReducer` arm (unconditional latest-wins assignment except sticky guard).
- [ ] 1.3 (FR3) RED: write `"AC11: unrecoverable sticky across reconnect; reset only on new turn"` (set unrecoverable → dispatch `clear_streams` → still unrecoverable → dispatch `reset_connection` → live). GREEN: sticky `unrecoverable` guard in `connection_change` arm; NEW `reset_connection` arm resets to `live`. Inline comment names the load-bearing sub-value. **Leave `clear_streams` untouched re: connection.**

## Phase 2 — Hook dispatch wiring (AC3 / AC9)

- [ ] 2.1 (FR4) Dispatch `connection_change`: auth_ok reattach (:714)→`live`; onclose transient (:1105)→`reconnecting`; onclose non-transient (:1088)→`unrecoverable`; `session_ended` after grace (:858, AFTER its `clear_streams`)→`unrecoverable`; `stream_replay incomplete` (:1014)→`unrecoverable`.
- [ ] 2.2 (FR3 wiring) Dispatch `reset_connection` from the shared `sendMessage` (:1446) — covers both legacy + cc-soleur-go paths.
- [ ] 2.3 (FR5) State 4 derived affordance (e.g. `resumedAt` on slice OR transient flag) on clean reattach (no `incomplete`/`session_ended`). If a slice field is added, include in fixture sweep.
- [ ] 2.4 Extend `test/ws-reconnect-cleanup.test.ts` with dispatch-sequence assertions (transient/non-transient close, session_ended-after-grace, stream_replay incomplete, reset_connection-on-send).

## Phase 3 — Render derivation + State-1 rewire (AC6 / AC7 / AC12)

- [ ] 3.1 (FR6) Add `deriveReconnectView({ phase, hasRetryingBubble }): ReconnectView` (3-variant `none|connection_lost|no_activity`) to `chat-state-machine.ts` with `_exhaustive: never` rail over `ConnectionPhase`. Precedence: reconnecting→connection_lost regardless of hasRetryingBubble. RED: truth-table test (connection_lost ⟹ ¬no_activity).
- [ ] 3.2 (FR7) REWIRE `chat-surface.tsx:567-580` to render via `deriveReconnectView(...).kind === "connection_lost"`; add `data-testid="connection-banner"` + `aria-live="polite"`; reconcile `:891` text so State 1 renders ONCE. Reconcile the `:351-355` useEffect if it drove the old banner.
- [ ] 3.3 Add NEW State 3 (unrecoverable: "Resume with full context" CTA + "View conversation") and State 4 (derived "Continuing… · workspace restored" notice) render branches per `.pen`.
- [ ] 3.4 Write `test/components/chat/connection-banner.test.tsx`: exactly-one-banner after flap (AC4), banner ⟹ no retrying-chip (AC12), no 3→4 flip render (AC5).

## Phase 4 — Sweep + exhaustiveness + regression (AC1/AC8/AC10)

- [ ] 4.1 (FR8) Fixture/directive sweep: add `connection` (+ `resumedAt` if added) to every `ChatState` literal in `test/**`; remove stale `@ts-expect-error`. Use `tsc --noEmit` TS2741 as the enumerator (~18 sites).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0; verify removing one `ConnectionPhase` case in `deriveReconnectView` makes tsc fail, then restore (AC8).
- [ ] 4.3 (FR9 / AC10) `./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/chat-reducer.test.ts test/ws-streaming-state.test.ts test/ws-reconnect-cleanup.test.ts` green.
- [ ] 4.4 Run the new connection suites (discoverability_test command) green.
- [ ] 4.5 AC7 verify: `git grep -n 'data-testid="connection-banner"' apps/web-platform/components/chat/` == 1; `git grep -nc 'Connection lost. Reconnecting' apps/web-platform/components/chat/chat-surface.tsx` == 1 (no duplicate).
