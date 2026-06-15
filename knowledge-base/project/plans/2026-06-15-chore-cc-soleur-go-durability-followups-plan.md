---
title: "cc-soleur-go durability follow-ups (idle-reaper scheduling + SIGTERM cc-drain)"
type: chore
issue: 5371
branch: feat-one-shot-5371-cc-durability
lane: cross-domain
date: 2026-06-15
---

# ♻️ chore: cc-soleur-go durability follow-ups (idle-reaper scheduling + SIGTERM cc-drain)

Closes #5371. Ref #5356 (parent review, CLOSED), PR #5362 (MERGED — made the cc disconnect terminal real).

## Overview

Two pre-existing latent cc-soleur-go durability gaps surfaced while building the cc disconnect-checkpoint parity (#5356 / PR #5362). Neither was introduced by #5362 — #5362 only made the cc disconnect terminal real, which exposed these adjacent gaps. Both are pure-backend wiring changes against the already-provisioned `apps/web-platform` runtime: no new infrastructure, no new vendor, no schema, no UI surface.

**Gap 1 — cc idle-reaper not scheduled in production.** `reapIdle()` (`apps/web-platform/server/soleur-go-runner.ts:3097`) is exported on the `SoleurGoRunner` interface and unit-tested (`apps/web-platform/test/soleur-go-runner-lifecycle.test.ts:95`) but **never called at runtime** — no `setInterval`/scheduler wires it. Idle cc queries persist in the in-memory `activeQueries` map until container restart. This is a memory/stale-state leak AND a second disconnect-class durability gap: a tab abandoned **without** a socket close (laptop-sleep, network drop, force-kill) never fires the ws-handler grace timer, so the only thing that would ever close that `Query` is the (currently unscheduled) idle reaper.

**Gap 2 — SIGTERM does not drain cc `activeQueries`.** The SIGTERM handler (`apps/web-platform/server/index.ts:216`) calls `abortAllSessions()` (`agent-session-registry.ts:359`) which drains only the legacy `activeSessions` map; the cc runner's `activeQueries` are not touched on deploy-time shutdown. **Design constraint from the issue:** the legacy path *intentionally* does not checkpoint on `server_shutdown` (the abort reason `server_shutdown` is classified non-`disconnected`, so the checkpoint branch at `agent-runner.ts:2358` is skipped — legacy conversations "own their terminal state"). cc parity therefore = **match legacy = abort without checkpoint**. The value of this change is bounded: stop API credit consumption + flip conversation status cleanly on shutdown, NOT preserve uncommitted work (that is the `disconnected` grace-abort terminal's job, already shipped in #5362).

The implementation mirrors two existing precedents 1:1:
- **Gap 1** mirrors `startStuckActiveReaper()` (`agent-runner.ts:773`) — a `setInterval` returning `NodeJS.Timeout`, started at `index.ts:120`, cleared at `index.ts:231`.
- **Gap 2** mirrors the legacy `abortAllSessions()` drain slot at `index.ts:235`, adding a sibling cc-drain that aborts-without-checkpoint.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| `reapIdle()` exported but never called | Confirmed: defined `soleur-go-runner.ts:3097`, on interface `:1129`, returned `:3240`; re-eval grep `setInterval.*reapIdle\|reapIdle\(\)` returns zero scheduler hits | Wire a scheduler (Gap 1) |
| `abortAllSessions()` drains only `activeSessions` | Confirmed: `agent-session-registry.ts:358-362` iterates `activeSessions` only; passes `SessionAbortError("server_shutdown")` → non-`disconnected` → no checkpoint | Add sibling cc-drain (Gap 2) |
| Runner reachable from SIGTERM/scheduler layer | Runner is a **lazy singleton** in cc-dispatcher.ts (`_runner`, created on first `getSoleurGoRunner(sendToClient)`). Only `hasActiveCcQuery` (`:1909`) and `closeCcConversation` (`:1924`) touch `_runner` without forcing creation, both with `if (!_runner) return` guards. **No exported "reap all" / "drain all" accessor exists.** | Add two new `_runner`-guarded exported accessors in cc-dispatcher.ts (`reapIdleCcQueries`, `drainCcQueriesForShutdown`) — do NOT force runner creation from index.ts |
| `closeConversation(id, "disconnected")` triggers checkpoint | Confirmed: `:3133` → `closeQuery(state, reason)` → `handleCcCloseQuery` (`cc-dispatcher.ts:1194`) checkpoints only on `reason === "disconnected"` | Gap 2 drain must NOT pass `"disconnected"` (match legacy no-checkpoint) — see Sharp Edge below |

## User-Brand Impact

**If this lands broken, the user experiences:** an idle cc-soleur-go conversation tab that, after a clean deploy, shows a permanently-spinning "working…" state because its in-flight `Query` was neither reaped nor drained and the container restart silently dropped it (no status flip to `failed`). Or, if the reaper cadence is mis-tuned, an *active-but-quiet* conversation (e.g. a long Bash review-gate awaiting human input) is reaped mid-flight and the user's eventual click is dropped.

**If this leaks, the user's workflow is exposed via:** N/A — this change moves no user data across a boundary. It only closes in-memory `Query` handles and flips the user's own conversation status rows on the existing authenticated path.

**Brand-survival threshold:** none — no data-movement surface; the change matches the legacy lifecycle that already ships. (Sensitive-path note: this PR touches `apps/web-platform/server/` but no auth/schema/migration/API-route file; threshold `none` reason: server-internal lifecycle wiring with no persistence-contract or data-egress change.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — idle reaper scheduled (behavioral).** A unit test, advancing `vi.useFakeTimers()` past `CC_IDLE_REAPER_INTERVAL_MS`, asserts the scheduler started by `startCcIdleReaper()` invokes `reapIdle()` (observed via the reaped-count side effect or an `onCloseQuery` spy). The re-eval grep `git grep -nE 'startCcIdleReaper' apps/web-platform/server/index.ts` also returns ≥1 (proves it is actually wired at boot, not just defined).
- [ ] **AC2 — reaper timer unref'd AND cleared on SIGTERM.** The scheduler calls `timer.unref()` before returning (mirroring `agent-runner.ts:848`, which the legacy reaper DOES do — see Sharp Edge). `git grep -n 'clearInterval(ccIdleReaperTimer)' apps/web-platform/server/index.ts` returns exactly 1, immediately after the existing `clearInterval(stuckActiveReaperTimer)` inside the SIGTERM handler.
- [ ] **AC3 — SIGTERM drains cc queries.** `git grep -n 'drainCcQueriesForShutdown' apps/web-platform/server/index.ts` returns ≥1, called immediately after `abortAllSessions()` (before `streamReplayBuffer.clearAll()`) inside the SIGTERM handler.
- [ ] **AC4 — drain does NOT checkpoint (legacy parity).** A unit test injects a real runner with a spy `onCloseQuery` dep (the runner accepts `onCloseQuery` — see `cc-dispatcher.ts:1962`), runs the drain over ≥1 active query, and asserts every `onCloseQuery` call carries `reason === undefined` (NOT `"disconnected"`). This is the checkable contract (a `"disconnected"` reason is the only thing that triggers checkpoint via `handleCcCloseQuery`). Do NOT spy on `checkpointInflightWorkForConversation` directly — it is a same-module `void`-call inside `handleCcCloseQuery` and is not reliably interceptable by `vi.spyOn`.
- [ ] **AC5 — lazy-singleton safe.** Both new accessors no-op when `_runner` is null (deploy with no cc traffic since boot): `reapIdleCcQueries()` returns 0, `drainCcQueriesForShutdown()` returns 0, neither throws. Unit test calls each before any `getSoleurGoRunner()`. **Invariant:** the scheduler calls only the null-guarded `reapIdleCcQueries()`, never `_runner.reapIdle()` directly.
- [ ] **AC6 — drain is idempotent against already-closed entries.** A unit test runs `closeConversation(id, "disconnected")` (grace-abort path sets `state.closed = true`) and THEN `drainCcQueriesForShutdown()`, asserting the drain does NOT re-fire `onCloseQuery` for that conversation (exactly one `onCloseQuery` call total). The drain must skip entries where `state.closed === true`. See Sharp Edge (closeQuery non-idempotency).
- [ ] **AC7 — drain closes awaitingUser queries (unlike the reaper).** A unit test with an `awaitingUser: true` query present asserts the **reaper** skips it (existing `reapIdle` guard, `soleur-go-runner.ts:3110`) but the **drain** closes it. The drain must NOT copy the reaper's `awaitingUser` skip — a deploy must tear down a query parked on a human-review gate.
- [ ] **AC8 — reaper failure path mirrored to Sentry.** The scheduler callback wraps its `reapIdleCcQueries()` call in `try/catch → reportSilentFallback` (per `cq-silent-fallback-must-mirror-to-sentry`) with `feature: "cc-idle-reaper"`. (Belt-and-suspenders: `reapIdle` is synchronous in-memory Map iteration and does no I/O, so this catch is a defensive guard, not an expected-to-fire path — see `## Observability`.)
- [ ] **AC9 — typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes, and `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-lifecycle.test.ts` passes (tests are added to the existing lifecycle file; no new file — see Phase 3).

### Post-merge (operator)

- _None._ Container restart on merge to `apps/web-platform/**` is the deploy mechanism (`web-platform-release.yml` path-filtered `on.push`); the SIGTERM handler runs automatically on the next deploy. No manual step.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

- Confirm `reapIdle()` still has zero schedulers: `git grep -nE 'setInterval.*reapIdle|reapIdle\(\)' apps/web-platform/server/`.
- Read the `startStuckActiveReaper` body in `apps/web-platform/server/agent-runner.ts` (around `:773-849`) — adopt its `setInterval(…, INTERVAL_MS)` + **`timer.unref()` before return** shape. NOTE: the legacy reaper IS unref'd (`agent-runner.ts:848`); the cc reaper must match (the explicit `clearInterval` on SIGTERM is belt-and-suspenders on top of `unref()`, not a replacement for it).
- Read `apps/web-platform/server/index.ts` start region (the `startStuckActiveReaper()` call site) and the `process.on("SIGTERM", …)` handler body — confirm symbol anchors (the SIGTERM handler holds `clearInterval(stuckActiveReaperTimer)` → `abortAllSessions()` → `streamReplayBuffer.clearAll()`). **Do not rely on absolute line numbers; anchor edits to these symbols** (the handler region shifts as the file evolves).
- Read `apps/web-platform/server/soleur-go-runner.ts` interface (`:1125-1170`), return object (`:3236-3244`), and the `closeQuery` body (`:1949-1995`). **Key finding (verified):** `closeQuery` has NO `if (state.closed) return` early return — the `state.closed = true` guard lives in its three CALLERS (`emitWorkflowEnded`, `reapIdle`, `closeConversation`), not the body. The drain must therefore set/check `state.closed` itself to stay idempotent (see Phase 2.1 + Sharp Edge).

### Phase 1 — Gap 1: schedule the cc idle reaper

1. **`apps/web-platform/server/cc-dispatcher.ts`** — add an exported `reapIdleCcQueries(): number` accessor mirroring `closeCcConversation`'s `if (!_runner) return 0;` guard, delegating to `_runner.reapIdle()`. Add an exported `startCcIdleReaper(): NodeJS.Timeout` that runs `setInterval(() => { try { reapIdleCcQueries(); } catch (err) { reportSilentFallback(err, { feature: "cc-idle-reaper", op: "reap" }); } }, CC_IDLE_REAPER_INTERVAL_MS)` and calls `timer.unref()` before returning. Define a **local** `const CC_IDLE_REAPER_INTERVAL_MS = 300_000` (NOT exported, NOT a knob) with a one-line comment: `// ≤ DEFAULT_IDLE_REAP_MS (10min, soleur-go-runner.ts:524); an idle query is reaped within ~1 interval of crossing the window`. (Do not import `STUCK_ACTIVE_CHECK_INTERVAL_MS` — it is module-private to agent-runner.ts; coupling two unrelated reapers is worse than a local literal.)
2. **`apps/web-platform/server/index.ts`** — add `const ccIdleReaperTimer = startCcIdleReaper()` immediately after the existing `const stuckActiveReaperTimer = startStuckActiveReaper()`.
3. **`apps/web-platform/server/index.ts`** — inside the SIGTERM handler, add `clearInterval(ccIdleReaperTimer)` immediately after the existing `clearInterval(stuckActiveReaperTimer)` (before `abortAllSessions()`).

### Phase 2 — Gap 2: drain cc queries on SIGTERM (no checkpoint)

Sub-steps are ordered contract-first (interface method before its dispatcher caller before the index.ts wiring):

1. **`apps/web-platform/server/soleur-go-runner.ts`** — add `closeAllForShutdown(): number` to the `SoleurGoRunner` interface (`:1125`), to the returned object (`:3240`), and implement it near `closeConversation` (`:3126`). It iterates `activeQueries`, and for each entry where `state.closed !== true` sets `state.closed = true` and calls `closeQuery(state)` **with no reason** (no checkpoint — legacy parity), returning the count closed. It does **NOT** skip `awaitingUser` (unlike `reapIdle`) — a deploy must tear down review-gate-parked queries too. Encapsulating the iteration in the runner is required because `activeQueries` is closure-private (`:1704`); exposing a raw id-iterator + looping `closeConversation` from the dispatcher would leak that internal and still need the same closed-guard, so the single method is the smaller surface.
2. **`apps/web-platform/server/cc-dispatcher.ts`** — add an exported `drainCcQueriesForShutdown(): number` accessor with the `if (!_runner) return 0;` guard, delegating to `_runner.closeAllForShutdown()`.
3. **`apps/web-platform/server/index.ts`** — inside the SIGTERM handler, call `drainCcQueriesForShutdown()` immediately after `abortAllSessions()` (before `streamReplayBuffer.clearAll()`). Final SIGTERM order: `clearInterval(stuckActiveReaperTimer)` → `clearInterval(ccIdleReaperTimer)` → `abortAllSessions()` → `drainCcQueriesForShutdown()` → `streamReplayBuffer.clearAll()` → connection close. The drain is synchronous in-memory (the only async tail is the `void cleanupCcBashGatesForConversation` inside `handleCcCloseQuery`, which is best-effort in-memory registry cleanup, NOT awaited DB I/O — so `process.exit(0)` does not truncate persisted state; next-boot `cleanupOrphanedConversations` (`index.ts:106`) is the status-row backstop).

### Phase 3 — Tests (RED → GREEN)

Extend `apps/web-platform/test/soleur-go-runner-lifecycle.test.ts` (already uses `vi.useFakeTimers()` + has a `reapIdle()` test at `:95`; same file = same fixtures, no new file needed). Each test cleans up with `afterEach(() => { vi.useRealTimers(); clearInterval(timer); })` to avoid the leaked-setInterval test hazard (`2026-03-20-bun-segfault-leaked-setinterval-timers.md`):

- **T1 (AC4):** drain over ≥1 active query with an injected spy `onCloseQuery` dep → every call carries `reason === undefined` (no checkpoint).
- **T2 (AC5):** `reapIdleCcQueries()` / `drainCcQueriesForShutdown()` return 0 / no-op when called before any `getSoleurGoRunner()` (null `_runner`) — use the `__setCcRunnerForTests`/reset hook if needed to ensure null state.
- **T3 (AC6):** `closeConversation(id, "disconnected")` then `drainCcQueriesForShutdown()` → `onCloseQuery` fires exactly once for that conversation (drain skips the already-closed entry).
- **T4 (AC7):** an `awaitingUser: true` query is skipped by `reapIdle()` but closed by the drain.
- **T5 (AC1):** advance fake timers past `CC_IDLE_REAPER_INTERVAL_MS` after `startCcIdleReaper()` → the reaped-count side effect / `onCloseQuery` spy shows `reapIdle()` ran.
- **No new test framework** — vitest is already the runner; no new dependency.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — add `closeAllForShutdown(): number` to interface (`:1125`) + return object (`:3240`) + impl (near `:3126`). **(Contract change — edit FIRST per Phase 2.1.)**
- `apps/web-platform/server/cc-dispatcher.ts` — add `reapIdleCcQueries`, `startCcIdleReaper`, `drainCcQueriesForShutdown`, and the local `CC_IDLE_REAPER_INTERVAL_MS`.
- `apps/web-platform/server/index.ts` — start cc reaper (after `startStuckActiveReaper()` call); clear it + drain cc queries inside the SIGTERM handler (after the matching legacy steps). Anchor by symbol, not line number.
- `apps/web-platform/test/soleur-go-runner-lifecycle.test.ts` — T1–T5.

## Files to Create

- None. Tests extend the existing lifecycle test file.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each planned file path (`jq --arg`) against issue bodies. Four open issues name a planned file incidentally; none overlaps the reaper/drain lifecycle edits:

- **#3243** (arch: decompose cc-dispatcher.ts into focused modules) — **Acknowledge.** Broad refactor of the whole file; these 3 small guarded accessors are additive and module-boundary-neutral. The decomposition can absorb them later. Different concern, own cycle.
- **#3242** (review: tool_use WS event lacks raw name field) — **Acknowledge.** Concerns the WS `tool_use` event payload shape, a different code region of cc-dispatcher.ts; no interaction with reaper/drain.
- **#3740** (review: author sentry-post-merge-smoke.yml workflow) — **Acknowledge.** Names `index.ts` only as deploy-smoke context; it is a CI-workflow concern, not the SIGTERM handler. No overlap.
- **#2349** (qa skill: port-probe + multi-worktree ESM loader cache) — **Acknowledge.** qa-skill / worktree-tooling concern that mentions `index.ts` incidentally; no SIGTERM-handler edit.

None folded in: each is a distinct concern with its own cycle, and folding would expand this chore well beyond the 2-gap scope. (This issue #5371 itself carries `deferred-scope-out` + `type/chore`, not `code-review`.)

## Observability

This change adds no expected-to-fire failure path: `reapIdle()` and `closeAllForShutdown()` are synchronous in-memory `Map` iteration (no RPC, no `await`, no I/O), so unlike `startStuckActiveReaper` (whose Sentry-mirrored catch exists because it does a Supabase RPC every tick) there is no async error class to alert on. The observability surface is therefore deliberately minimal — one defensive `reportSilentFallback` wrapper, no new alert rule.

```yaml
liveness_signal:
  what: "cc idle-reaper tick — log.info({ reaped }) when reaped > 0 (existing pino pipeline)"
  cadence: "every CC_IDLE_REAPER_INTERVAL_MS (300s)"
  alert_target: "none — a self-healing reaper does not warrant an alert rule"
  configured_in: "apps/web-platform/server/cc-dispatcher.ts (startCcIdleReaper)"
error_reporting:
  destination: "reportSilentFallback → Sentry (feature: 'cc-idle-reaper', op: 'reap') — defensive belt only"
  fail_loud: "yes — the scheduler callback's try/catch mirrors any throw to Sentry per cq-silent-fallback-must-mirror-to-sentry, even though reapIdle does no I/O"
failure_modes:
  - mode: "drain leaves a query un-closed (interface bug)"
    detection: "next-boot cleanupOrphanedConversations (index.ts:106) flips stale active→failed"
    alert_route: "existing cleanupOrphanedConversations path"
logs:
  where: "pino structured logs (container stdout → existing pipeline); Sentry only on the defensive catch"
  retention: "per existing Sentry/log retention — unchanged"
discoverability_test:
  command: "Sentry issue search feature:cc-idle-reaper (no SSH)"
  expected_output: "zero cc-idle-reaper events under steady state (the catch is defensive, not expected to fire)"
```

**Op-contract note:** the `feature: "cc-idle-reaper"` slug is new and distinct from `concurrency-stuck-active-reaper`; no new Sentry alert rule is added, so there is no `filter_match` over-match risk to verify. If a future signal shows the reaper genuinely fails, add an alert rule then — not speculatively.

## Infrastructure (IaC)

None. This is a pure code change against the already-provisioned `apps/web-platform` runtime. No new server, service, secret, vendor, cron, DNS, or firewall rule. The deploy mechanism (container restart on merge via `web-platform-release.yml`) already exists. Skipped per Phase 2.8 (plan only edits files under `apps/web-platform/server/` and `apps/web-platform/test/`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — backend runtime/lifecycle change with no UI surface (no file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`), no marketing/legal/finance/sales/support/product surface. Engineering-only tooling change. The mechanical UI-surface override did not fire (no UI-surface path in Files to Edit/Create).

## Risks & Mitigations

- **Reaping an active-but-quiet conversation.** `reapIdle()` already guards `awaitingUser` (`soleur-go-runner.ts:3110`) so a paused human-review gate is skipped; the 5-min `REVIEW_GATE_TIMEOUT_MS` is the absolute backstop. Cadence must stay ≤ the 10-min `DEFAULT_IDLE_REAP_MS` window, never tighter than it. Mitigation: reuse the proven 300s cadence; do not introduce a new aggressive interval.
- **Drain checkpointing by accident.** If the drain accidentally passes `reason: "disconnected"`, every in-flight cc turn would checkpoint at deploy time — diverging from legacy and adding deploy latency + Supabase write load. Mitigation: AC4 spy-asserts zero checkpoint calls; Sharp Edge below.
- **Lazy-singleton creation from shutdown.** Calling `getSoleurGoRunner(sendToClient)` from index.ts would *create* a runner at shutdown (wrong, and requires a sendToClient closure). Mitigation: new accessors use the `if (!_runner) return` guard exactly like `closeCcConversation`; never call `getSoleurGoRunner` from the scheduler or SIGTERM path.
- **Leaked setInterval in tests.** Per `2026-03-20-bun-segfault-leaked-setinterval-timers.md`, an uncleaned `setInterval` in a test segfaults/hangs the runner. Mitigation: `afterEach(() => { vi.useRealTimers(); clearInterval(timer) })`.

## Sharp Edges

- **The drain MUST NOT pass `reason: "disconnected"`.** `closeAllForShutdown` must call `closeQuery(state)` with no reason. `handleCcCloseQuery` (`cc-dispatcher.ts:1194`) gates the checkpoint on `reason === "disconnected"`; passing it on a shutdown drain would diverge from legacy parity (the entire point of Gap 2 is *match legacy = no checkpoint*). AC4 spy-asserts `reason === undefined`.
- **`closeQuery` is NOT idempotent (verified).** Its body (`soleur-go-runner.ts:1949`) has no `if (state.closed) return` — the guard lives only in its three callers (`emitWorkflowEnded`, `reapIdle`, `closeConversation`). So `closeAllForShutdown` MUST check `state.closed !== true` before closing and set `state.closed = true` itself; otherwise a conversation mid-grace-abort (`closeConversation(id,"disconnected")` already ran, `activeQueries.delete` not yet completed) or mid-reaper-tick gets a second `onCloseQuery` + `query.close()`. The `clearInterval` ordering on SIGTERM is necessary-but-insufficient: an already-entered async reaper tick survives `clearInterval` and can mutate the map during the drain — the `state.closed` skip is the actual race fix, not the ordering. AC6 tests this.
- **`.unref()` the reaper timer (verified).** The legacy `startStuckActiveReaper` calls `timer.unref()` (`agent-runner.ts:848`); `index.ts` comments confirm `.unref()` already prevents shutdown blocking. The cc reaper must match — do NOT ship an un-unref'd timer relying on `clearInterval` alone.
- **The drain closes `awaitingUser` queries; the reaper skips them.** `reapIdle` deliberately `continue`s on `state.awaitingUser` (`:3110`) so a human-review gate is never reaped mid-read. `closeAllForShutdown` must NOT copy that skip — a deploy tears down every query, including review-gate-parked ones. AC7 tests both behaviors.
- **Do not force runner creation at the SIGTERM/scheduler layer.** Only `_runner`-direct guarded accessors may be used; `getSoleurGoRunner` instantiates and requires a `sendToClient` closure. The scheduler calls the guarded `reapIdleCcQueries()`, never `_runner.reapIdle()` directly.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold `none` with sensitive-path reason.)

## Test Scenarios

| # | AC | Scenario | Expected |
| --- | --- | --- | --- |
| 1 | AC4 | Drain with 2 active + 1 idle query, `_runner` set, spy `onCloseQuery` dep | All 3 closed; every `onCloseQuery` call has `reason === undefined` |
| 2 | AC5 | `reapIdleCcQueries()` / `drainCcQueriesForShutdown()` called before any dispatch (`_runner` null) | Returns 0 / no-op, no throw |
| 3 | AC6 | `closeConversation(id,"disconnected")` then `drainCcQueriesForShutdown()` | `onCloseQuery` fires exactly once for that conversation (drain skips closed entry) |
| 4 | AC7 | `awaitingUser:true` query present | Reaper skips it; drain closes it |
| 5 | AC1 | Fake-timer advance past `CC_IDLE_REAPER_INTERVAL_MS` after `startCcIdleReaper()` | `reapIdle()` ran (reaped-count / spy side effect); timer is unref'd |
| 6 | AC9 | typecheck + `vitest run test/soleur-go-runner-lifecycle.test.ts` | green |
