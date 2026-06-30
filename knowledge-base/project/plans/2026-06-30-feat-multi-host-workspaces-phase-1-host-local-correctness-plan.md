---
title: "feat: Multi-host /workspaces — Phase 1 (host-local correctness, no new infra)"
date: 2026-06-30
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5274
related: [5240, 5273, 5338, 5356, 5546]
epic: knowledge-base/project/plans/2026-06-29-feat-multi-host-workspaces-layer-plan.md
spec: knowledge-base/project/specs/feat-multi-host-workspaces/spec.md
adr: ADR-068
branch: feat-multi-host-workspaces-phase1
status: draft
---

# ✨ Multi-host `/workspaces` — Phase 1: host-local correctness (NO new infra; still `replicas = 1`)

> **Epic step (1 of 6).** This is the first executable PR of the multi-host
> `/workspaces` epic (#5274). The architecture is **already settled and merged**
> in **ADR-068** (`status: adopting`, PR #5710 — Phase 0). This phase makes **no
> new architectural decision and adds no infrastructure**: it lands the two
> **host-local seams** ADR-068 §4–§5 names as the load-bearing Phase-1 enablers,
> behaviour-identical at `replicas = 1`, so the Phase-3 coordinator can later
> route control by changing *one* function instead of the timer machinery.

## Overview

Phase 1 implements **tasks.md 1.1–1.5** of the epic. Two code seams + an audit +
RED→GREEN tests. No migration, no Terraform, no Redis, no coordinator, **no
`host_id`** (host identity is a Phase-2 lease concept — introducing it here would
be premature). At `replicas = 1` every change below is a behaviour-preserving
no-op on the happy path; its entire value is **establishing the seam** ADR-068
Decision §4 (control routing) and §5 (lease-derived affinity) build on.

The two seams:

1. **TR2 host-local owning-host guard** before the disconnect-grace abort fires
   (`runDisconnectGraceAbort`, ws-handler.ts:228–240). This **closes a real
   single-host race today** — it is not merely a Phase-3 seam. On reconnect the
   new live socket is registered at ws-handler.ts:**2843**, but the grace-timer
   cancel runs **three awaited DB round-trips later** (`:2853` org → `:2859`
   workspace → `:2869` default-workspace → cancel `:2893–2899`). A 30 s grace
   timer that expires inside that await window fires `runDisconnectGraceAbort`
   while `sessions.get(uid)` is **already** the new OPEN socket but the cancel has
   not run — aborting a just-reconnected user's in-flight turn (the #5240 "my work
   vanished" regression) **at `replicas = 1`**. The guard reads that live socket
   and suppresses the abort. It *also* **localises the ownership decision inside
   the abort function**, so Phase 3 routes *that one function* through the
   coordinator/Postgres-lease (a reconnect landing on another host then no longer
   lets this host abort a now-remote-live session). No poll, no cross-host call in
   Phase 1.

2. **`abortSession` returns a found-count** (agent-session-registry.ts:190–213,
   currently `void`) — a **semantic mirror** of `drainAutonomousDisclosureGates`
   (cc-dispatcher.ts:1344–1364, returns `number`). The count is the number of
   *registered* sessions matched and signalled **on this host**; it is the
   affordance ADR-068 §4 names for the Phase-3 coordinator-forward decision
   (local-resolve → found 0 → RPC-forward to the lease-holder). Note it counts
   *registered* entries, not *live* turns — a finishing-but-not-yet-
   `unregisterSession`'d entry still counts (the safe direction: don't forward
   when something was found). Harmless at `replicas = 1`; load-bearing later.

Plus an **audit** (1.3): confirm the legacy `agent-runner.ts:944` AbortController
is routed through `activeSessions` (not an unrouted abort surface), and pin that
fact with a grep + test assertion.

## Research Reconciliation — Spec vs. Codebase

Grounded against current `main` (`fd3db9b34`, 2026-06-30) — the epic's 2026-06-29
citations were re-verified because main moves fast. **All seams confirmed; no
semantic drift.**

| Claim (epic/spec) | Codebase reality (file:line, `main`) | Plan response |
|---|---|---|
| Grace abort has no owning-host guard; the seam is `runDisconnectGraceAbort` (ws-handler.ts:228-240) | **Confirmed + sharper.** `runDisconnectGraceAbort(uid, convId): void` at :228-240 unconditionally aborts. Reconnect registers the new socket at **:2843** but the timer-cancel runs at **:2893-2899** — separated by **three awaited DB calls** (:2853/:2859/:2869). So the cancel does **not** always precede the fire: a 30 s timer expiring in that await window aborts a live just-reconnected session **at replicas=1** (a real race, not a Phase-3-only bug). Cancel is **user-level** (prefix `${userId}:`, all-convs). | Add a **user-level** local-liveness guard at the top of `runDisconnectGraceAbort`. It **closes the race today** (suppresses the abort when a live local socket exists) and is the seam Phase 3 routes through the lease. User-level granularity matches the cancel's per-user "the user is back" semantics. |
| `abortSession` is `void` and cannot distinguish finished-vs-remote | **Confirmed** `void` at :190-213; broadcast loop :206-212 increments **unconditionally** per matched session. The mirror `drainAutonomousDisclosureGates` (cc-dispatcher.ts:**1344-1364**) returns `number` via `let released=0` (:1350) … `if (ok) released+=1` (:1362) … `return released` (:1364) — it increments **conditionally** on resolve-success. | Widen to `: number` using the same accumulator shape (a **semantic** mirror — `abortSession` has no success signal, so it counts every matched session). |
| `agent-runner.ts:944` AbortController might be an unrouted abort surface | **Falsified (good).** :944-950 creates `controller`, wraps it as `AgentSession { abort: controller, … }`, and `registerSession(...)` stores it in `activeSessions`. It is the **sole** abort surface, fully routed through the registry. | Task 1.3 is a **confirmation/audit**, not new wiring — pin it with a grep + a test asserting an `agent-runner`-registered session is reachable by `abortSession`'s broadcast. |
| `userWorkspaces` restart-survival needs new work | **Already shipped + tested** by #5338 (MERGED). `resolveUserWorkspaceBinding` (agent-session-registry.ts:288-327) lazy-rehydrates from `user_session_state.current_workspace_id`. `test/durable-workspace-binding-resolver.test.ts` already covers it: **:43** ("Map miss + DB → rehydrates (writeback) … post-restart sim — load-bearing"), :89 (writeback-consumed-by-next-caller), and `readWorkspaceIdFromDb` directly at :118-137 (present/absent/null/error) — all via a mocked closure. Routing truth = Postgres. | Task 1.2 = **confirmation only** (cite the existing #5338 tests + grep-trace that consumers route through the resolver). **No new resolver, no integration test in Phase 1** — the live-DB schema/RLS round-trip is deferred to Phase 2 (migration 114 adds the first genuinely-new DB surface that justifies an integration harness). Decision: operator + DHH + Simplicity, 2026-06-30. |
| Return-widening (`void → number`) risks breaking consumers (hr-type-widening) | **Swept, `--include=*.ts`.** 6 production call sites (ws-handler:233/362/2101/2423 — all reached via the `agent-runner.ts:201` **re-export** that ws-handler:27-28 imports; agent-runner:713/849) are statement calls. Test consumers: `test/server/abort-turn.test.ts` (×9), `test/agent-runner-disconnect-after-result-race.test.ts:176`, and `vi.spyOn(…, "abortSession")` at `test/agent-runner-stuck-active-reaper.test.ts:268,348` (assert `toHaveBeenCalledWith`, **never the return value**). **No site reads the return** → `void → number` is backward-compatible (TS discards an unused return); the widening propagates automatically through the re-export. | No consumer changes; the full enumerated sweep is recorded in AC6. (Learning `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`.) |
| Phase 1 changes the C4 model | **No.** The seams are already in ADR-068 Decision §4 (found-count) + §5 (host-local cancel) and the model.c4 `coordinator`/`sessionStore`/`gitDataStore` elements are Phase 2+. Phase 1 adds no external actor/system/relationship/container. | **No `.c4` edit** → the `regenerate-c4-model.sh` / `c4-model-freshness` gotcha does **not** fire for this phase. |

## Implementation Phases

> One PR. RED→GREEN per `cq-write-failing-tests-before`. Order matters: the
> contract change (1.4, `abortSession` return type) lands **before** any consumer
> that reads the count — Phase 1 has none, but the audit test (1.3) and the guard
> (1.1) are written against the post-widening signature.

### Phase 1.A — `abortSession` found-count (contract change first)
- [ ] Widen `abortSession(userId, conversationId, reason?, leaderId?)` from `: void`
  to `: number`. Both branches return a count of sessions whose `.abort.abort(...)`
  was invoked:
  - `leaderId` branch (:198-204): `return session ? 1 : 0`.
  - Broadcast branch (:206-212): accumulate `let aborted = 0; … aborted += 1; return aborted;`
    — the same accumulator shape as `drainAutonomousDisclosureGates` (a **semantic**
    mirror: `abortSession` increments per matched session, not on a success signal).
- [ ] Update the docblock (:178-189) to state the return contract precisely:
  *"Returns the number of **registered** sessions matched and signalled on **this
  host** (not necessarily still-live turns — a finishing-but-not-yet-deregistered
  entry still counts; the safe direction). The Phase-3 coordinator reads this to
  decide whether to RPC-forward (ADR-068 §4); the full forward rationale lives in
  ADR-068, not here."*
- [ ] Do **not** touch any call site (all 6 production sites are statement calls; the
  test spies assert call-args, not the return — see Reconciliation / AC6).

### Phase 1.B — TR2 host-local owning-host guard
- [ ] At the top of `runDisconnectGraceAbort(uid, convId)` (ws-handler.ts:228),
  before the abort, add the **local-liveness** guard reading the already-imported
  `sessions` map (session-registry.ts):
  ```ts
  // Host-local owning-host guard (TR2 — epic #5274 Phase 1, ADR-068 §5).
  // A live local OPEN socket for this user means they have reconnected. This
  // CLOSES A REAL replicas=1 RACE: the reconnect registers the new socket at
  // :2843 but the pendingDisconnects-cancel runs ~3 awaited DB calls later
  // (:2853/:2859/:2869 → :2893); a 30s timer expiring in that window would
  // otherwise abort a just-reconnected live turn (#5240). User-level granularity
  // matches the user-level cancel at :2893 (per-user "the user is back"). It also
  // localises the ownership decision inside this function — the one seam Phase 3
  // routes through the coordinator/Postgres-lease. NO host_id / lease / poll here.
  const live = sessions.get(uid);
  if (live && live.ws.readyState === WebSocket.OPEN) {
    log.info({ userId: uid, conversationId: convId },
      "Reconnected on this host before grace fired — skipping grace abort (owning-host guard)");
    return;
  }
  ```
  - **Granularity is user-level**, matching the existing prefix-cancel (:2893-2899
    cancels on `${userId}:`, all conversations). Justification is *consistency with
    the existing cancel's per-user intent* — not "the cancel granularity" as such
    (the cancel cancels timers; the guard gates per-conversation teardown). A
    stale/closing socket (`readyState !== OPEN`) correctly falls through to abort.
  - `WebSocket.OPEN` + `sessions.get` reuse the exact predicate
    `forceDisconnectForTierChange` (:334-342) already uses — no new import
    (`WebSocket` + `sessions` imported at :324).

### Phase 1.C — Audit the legacy abort path (1.3, confirmation)
- [ ] Confirm by **grep anchored on the stable symbol** `registerSession(` (NOT the
  drift-prone line `:944`) that the `agent-runner` AbortController is wrapped as an
  `AgentSession` and stored in `activeSessions`, hence reachable by `abortSession`'s
  broadcast (`sessionKey` :62-70 → prefix match :207-211). Record the grep in the PR.
- [ ] Add a **present-tense** one-line comment at the agent-runner registration:
  *"This controller is the legacy/registry abort surface reached by `abortSession`;
  the cc-soleur-go lineage has its own controller (`cc-dispatcher.ts:2117`, reached
  by `closeCcConversation`)."* No forward-reference to unbuilt Phase-3 machinery.
- [ ] `session-registry.ts` (operator task 1.3 "add to edit set"): a **present-tense**
  note on the `sessions` Map (:1-5) — *"holds the live socket — host-local by
  definition."* No Phase-3 coordinator narrative (that would rot when Phase 3 lands).

### Phase 1.D — RED→GREEN tests (1.5)
- [ ] **Grace-guard unit test** — new `test/ws-handler-disconnect-grace-owning-host-guard.test.ts`
  (node project; `test/**/*.test.ts`), mirroring the harness in the existing
  `test/ws-handler-grace-abort-cc-parity.test.ts` (which already imports and calls
  `runDisconnectGraceAbort` directly, bypassing the timer). `afterEach(() =>
  sessions.delete(uid))` so the seeded Map never leaks into the cc-parity regression
  (which relies on `sessions.get` being undefined). Three cases:
  - **Guard fires — pins the race (AC2):** seed a live OPEN session
    `sessions.set(uid, { ws:{ readyState: WebSocket.OPEN } } as any)` (this IS the
    race-window state: new socket registered, cancel not yet run), call
    `runDisconnectGraceAbort(uid, convId)`; assert `abortSession`,
    `closeCcConversation`, `streamReplayBuffer.clear` are **NOT** called.
  - **No session — guard passes (AC3):** no entry for `uid`; assert the abort **IS** called.
  - **Stale socket — guard passes (AC3):** seed `{ ws:{ readyState: WebSocket.CLOSED } }`;
    assert the abort **IS** called (pins the `readyState === OPEN` check, not `sessions.has`).
- [ ] **`abortSession` found-count + legacy-abort routing** — extend
  `test/server/abort-turn.test.ts` (folds the standalone legacy-abort deliverable in —
  `registerSession` IS the agent-runner path, no separate code path exists):
  - register 2 leaders → broadcast returns 2; 0 → returns 0; single-leader → 1/0 (AC4).
  - register **one `AbortController`-backed session via `registerSession`** (the
    agent-runner shape), `abortSession(uid, conv)` → assert `controller.signal.aborted
    === true` **and** return ≥ 1 (AC5 — legacy abort routed).
  - add a **decoy** session under a *different* `(uid, conv)`; assert it is **neither
    counted nor aborted** (pins the prefix-exclusion — over-count would mean
    "I own conversations I don't" in Phase 3) (AC4).
- [ ] **Task 1.2 restart-survival — confirmation, NOT a new test** (operator decision
  2026-06-30): cite `test/durable-workspace-binding-resolver.test.ts:43` (the existing
  "post-restart sim — load-bearing" rehydrate test) + :118-137 (`readWorkspaceIdFromDb`)
  as the coverage, and `git grep` to confirm the post-restart consumer path routes
  through `resolveUserWorkspaceBinding`. The **live-DB** schema/RLS round-trip is
  **deferred to Phase 2** (migration 114 is the first new DB surface that justifies an
  integration harness — there is no `*.integration.test` precedent in the repo today).

## Files to Edit
- `apps/web-platform/server/ws-handler.ts` — Phase 1.B guard at `runDisconnectGraceAbort` (:228-240). The only behaviour change in the diff.
- `apps/web-platform/server/agent-session-registry.ts` — Phase 1.A `abortSession` `void → number` (:190-213) + docblock.
- `apps/web-platform/server/agent-runner.ts` — Phase 1.C present-tense one-line comment at the AbortController registration (anchor `registerSession(`, ≈:950). No behaviour change.
- `apps/web-platform/server/session-registry.ts` — Phase 1.C present-tense host-local note on the `sessions` Map (:1-5). No behaviour change.
- `apps/web-platform/test/server/abort-turn.test.ts` — extend with found-count, legacy-abort-routed, and decoy-exclusion assertions (AC4/AC5).

## Files to Create
- `apps/web-platform/test/ws-handler-disconnect-grace-owning-host-guard.test.ts` — grace-guard unit test: race-window-fires / no-session-passes / stale-socket-passes (AC2/AC3).

## User-Brand Impact

**If this lands broken, the user experiences:** the guard **fixes** the
#5240-class "my work vanished" regression in the reconnect/grace race (a 30 s timer
firing in the post-reconnect await window), so a *correct* guard is a net safety
gain. The failure modes are: a guard that wrongly early-returns would **fail to
abort** a genuinely-dead session (a leaked in-flight turn / slot, recoverable by the
pg_cron sweep); a guard that wrongly proceeds would **abort a live reconnected
session**, the very regression it exists to prevent. A mis-counted `abortSession`
return is inert in Phase 1 (no consumer reads it) but would mis-inform the Phase-3
coordinator if wrong.

**Residual (named, accepted):** in the narrow race window, if the reconnect's new
session has **not yet re-subscribed** to `convId` (`newSession.conversationId` still
`undefined` at :2843), the user-level guard suppresses all three teardowns for
`convId` — leaving the cc-conversation / replay buffer / slot to the existing
pg_cron sweep rather than the grace path. This matches today's completed-reconnect
behaviour (any reconnect already cancels `convId`'s timer regardless of resume
target), so it is **not a new leak class** — but it is the deliberate trade-off of
user-level granularity, surfaced here rather than waved off.

**If this leaks, the user's data/workflow is exposed via:** N/A for Phase 1 — no
new data surface, no new store, no cross-tenant boundary added. The dev-Supabase
integration test touches only a throwaway dev user's own `user_session_state` row
(dev project, `hr-dev-prd`), anonymised on teardown.

**Brand-survival threshold:** single-user incident.

CPO sign-off carried forward from the 2026-06-29 epic brainstorm
(`USER_BRAND_CRITICAL` triad, `requires_cpo_signoff: true` on the epic plan).
`user-impact-reviewer` runs at this PR's review.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 — typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- **AC2 — guard fires (pins the race):** a unit test seeds the **race-window state**
  (a live OPEN session registered for the user) and proves `runDisconnectGraceAbort`
  early-returns — does **not** call `abortSession`/`closeCcConversation`/
  `streamReplayBuffer.clear` (same event loop, no poll). This is the exact state of
  a reconnect that has run `sessions.set` (:2843) but not yet the cancel (:2893).
- **AC3 — guard passes in both negative cases:** (a) no session for the user → abort
  fires; (b) a session whose `ws.readyState !== OPEN` (CLOSED) → abort **still** fires
  (pins the `readyState === OPEN` check, so a `sessions.has`-only mis-implementation
  is caught).
- **AC4 — found-count + exclusion:** `abortSession` returns the number of registered
  sessions signalled on this host (2 leaders → 2, 0 → 0, single-leader → 1/0); a
  **decoy** session under a different `(uid, conv)` is **neither counted nor aborted**
  (pins prefix-exclusion). Semantic mirror of the `drainAutonomousDisclosureGates`
  accumulator.
- **AC5 — legacy abort routed:** a session registered via `registerSession` with a
  real `AbortController` (the agent-runner shape) is aborted by `abortSession`'s
  broadcast (`controller.signal.aborted === true`, return ≥ 1). The audit grep is
  anchored on the stable symbol `registerSession(`, not a line number.
- **AC6 — no consumer break (type-widening sweep):** `git grep -n "abortSession(" --include=*.ts apps/web-platform`
  enumerates all sites — 6 production statement calls + the test spies
  (`abort-turn.test.ts`, `agent-runner-stuck-active-reaper.test.ts:268/348`,
  `agent-runner-disconnect-after-result-race.test.ts:176`) and the
  `agent-runner.ts:201` re-export — and confirms **none reads the return**; PR body
  records the sweep. (`hr-type-widening-cross-consumer-grep`.)
- **AC7 — additive-only (no abort newly caused):** the guard only ever *suppresses*
  an abort when a live local OPEN socket exists; it never *causes* an abort that did
  not fire before. The sole behaviour delta vs. today is that a turn which today
  could be wrongly killed in the reconnect/grace race is now preserved. The
  `abortSession` change adds a return value read by nobody in Phase 1. `Ref #5274`
  (NOT `Closes`) — the epic stays open.

### Task 1.2 — confirmation (no new test; live-DB deferred to Phase 2)
- **AC8 — restart-survival is already covered:** the PR cites
  `test/durable-workspace-binding-resolver.test.ts:43` (post-restart rehydrate sim) +
  :118-137 (`readWorkspaceIdFromDb`) and a `git grep` showing the post-restart consumer
  routes through `resolveUserWorkspaceBinding`. The live-DB schema/RLS integration test
  is **deferred to Phase 2** (recorded in that phase's tasks; operator decision
  2026-06-30) — not built here, and **not** replaced by a query-shape proxy.

### Post-merge (operator)
- None. Phase 1 introduces no infrastructure; the merge ships the code. (The epic's
  IaC apply path begins at Phase 2.)

## Open Code-Review Overlap

3 open `code-review` issues name the touched files; **none overlaps the Phase-1 edit
regions** (`runDisconnectGraceAbort` body, `abortSession` signature, the AbortController
registration). Dispositions:
- **#3374** (emit `slot_reclaimed` WS frame for ledger-divergence recovery — ws-handler.ts) — **Acknowledge.** Different concern (slot-reclaim signalling); Phase 1 does not touch it. Remains open.
- **#2191** (`clearSessionTimers` helper + refresh-timer jitter — ws-handler.ts) — **Acknowledge.** Phase 1 adds a guard inside `runDisconnectGraceAbort`; it does not refactor the timer helpers. The guard is compatible with a later `clearSessionTimers` extraction. Remains open.
- **#3242** (`tool_use` WS event lacks raw name — agent-runner.ts) — **Acknowledge.** Unrelated event-shape concern; Phase 1's only `agent-runner` edit is a doc comment. Remains open.

## Domain Review

**Domains relevant:** Engineering. (Product NONE, Legal/GDPR considered-and-skipped, Operations none.)

### Engineering (CTO)
**Status:** reviewed (epic carry-forward + this plan's current-`main` grounding)
**Assessment:** The two seams are exactly the minimal, additive, behaviour-preserving
changes ADR-068 §4–§5 require to make Phase 3 a one-function routing change. The
guard's user-level granularity (matching the existing cancel) and the deliberate
*absence* of `host_id`/lease/poll in Phase 1 are the load-bearing scoping calls —
introducing host identity here would be premature (Simplicity risk). The
`void → number` widening is provably consumer-safe (statement-call sweep).

### Product/UX Gate
**Tier:** none
**Decision:** n/a — no UI surface. No files under `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx`; backend server/registry/test only. The user-visible contract
(no wrongly-killed turn, no leaked session) is captured in User-Brand Impact + ACs.
**Pencil available:** N/A (no UI surface)

### Legal (CLO) / GDPR Gate (Phase 2.7)
**Status:** considered — **skipped** (no regulated-data surface added). Phase 1 adds
no migration, no schema, no new processing activity, and (after review) no live-DB
test. `resolveUserWorkspaceBinding` already exists (#5338). The epic's full GDPR gate
fires at **Phase 2** (migration 114 — the first concrete regulated-data surface), per
the epic carry-forward.

### Operations (COO)
**Status:** none — no new host, monitor, or recurring cost in Phase 1.

## Architecture Decision (ADR/C4)

**No new architectural decision in Phase 1.** ADR-068 (`adopting`, merged PR #5710)
already records both seams: Decision §4 (the `abortSession` found-count as the
coordinator-forward affordance) and §5 (lease-derived affinity keeping the grace
cancel host-local). This phase **implements within that frame**; it neither creates
nor amends an ADR.

### C4 views — checked, no impact
Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Phase 1 adds:
- **No external human actor** (no new correspondent/reviewer/recipient).
- **No external system / vendor** (no new webhook, outbound API, or third-party store).
- **No container / data-store** (the Phase-2+ `gitDataStore`, Phase-4a `sessionStore`,
  and Phase-3 `coordinator`/`scheduler` are already modelled in ADR-068's Phase-0 C4
  and ship in their own phases — Phase 1 instantiates none).
- **No actor↔surface access-relationship change** (the guard + return-count are
  internal to the existing `api`/`claude` containers).

→ **No `.c4` edit**, therefore `scripts/regenerate-c4-model.sh` /
`c4-model-freshness.test.sh` are **not** invoked for this phase (the gotcha only
fires on an actual `.c4` source change).

## Observability

Phase 1's entire production-observable footprint is **one new pino `info` log line**
(the guard's early-return). No new Sentry op slug, monitor, or metric — the epic's
`control_plane_route` / `worktree_lease` slugs land with the Phase-3 coordinator that
emits them; adding them now would be dark (never-fired) instrumentation. All error
paths reuse existing telemetry.

```yaml
liveness_signal:
  what: existing /health session-count (session-registry sessions.size); unchanged
  cadence: existing
  alert_target: existing Sentry / Better Stack (unchanged)
  configured_in: apps/web-platform/server/session-registry.ts (sessions.size) — read by existing /health
error_reporting:
  destination: Sentry (server) via existing paths — reportSilentFallback on the disconnect/bind seam (ws-handler.ts:2886) + resolveUserWorkspaceBinding.db-read/.unresolvable slugs (#5338, :299-323)
  fail_loud: true (unchanged)
failure_modes:
  - {mode: guard suppresses a real abort (leaked session), detection: "owning-host guard" info log with no live socket, alert_route: pg_cron slot sweep reclaims; pino log grep-discoverable — no new alert at replicas=1}
  - {mode: guard wrongly aborts a live turn, detection: existing abort/turn-status telemetry, alert_route: existing Sentry}
logs:
  where: pino → existing server log pipeline; new guard info line on early-return
  retention: per existing retention (EU)
discoverability_test:
  command: "./node_modules/.bin/vitest run test/ws-handler-disconnect-grace-owning-host-guard.test.ts && grep -n 'owning-host guard' apps/web-platform/server/ws-handler.ts (no ssh)"
  expected_output: "guard test passes; guard + info log present at the runDisconnectGraceAbort seam"
```

## Risks & Mitigations
- **Guard changes behaviour at replicas=1** → Yes, **deliberately and beneficially**:
  it suppresses the abort in the reconnect/grace race window (new socket at :2843,
  cancel at :2893, ~3 awaited DB calls between). It never *causes* an abort that did
  not fire before (a non-live user still aborts; a CLOSED socket still aborts). The
  delta is asserted by AC2 (suppress-on-live) + AC3 (abort-on-absent/closed) + AC7.
  The earlier "race-free / behaviour-identical" framing was **wrong** (Kieran +
  spec-flow P1) and is corrected throughout.
- **Guard granularity** → user-level (not `convId`-level), justified by *consistency
  with the existing user-level cancel's intent* (any reconnect = "the user is back").
  The accepted residual (a race-window reconnect that has not re-subscribed to
  `convId` defers that conversation's teardown to the pg_cron sweep) is named in
  User-Brand Impact — not a new leak class.
- **`void → number` breaks a consumer** → all 8 call sites are statement calls (swept,
  AC6); TS discards an unused return. No consumer change.
- **Dark/premature infra** → deliberately **no** `host_id`, lease, coordinator, Redis,
  or new Sentry slug in Phase 1 (those are Phase 2/3/4a). Keeps the diff minimal and
  the Simplicity reviewer satisfied.
- **Re-testing already-covered code** → the restart-survival logic is already proven
  by #5338's `durable-workspace-binding-resolver.test.ts`; Phase 1 cites it rather
  than standing up a new `*.integration.test` category. The live-DB schema/RLS test
  lands in Phase 2 (migration 114) where it has a genuinely new surface to cover and
  the harness (dev-only, `anonymise_user` teardown, no setup workspace-create — the
  mig-053 trigger auto-creates) is justified.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, only `TBD`/placeholder, or
  omits the threshold fails `deepen-plan` Phase 4.6. (This plan's is filled;
  threshold = single-user incident.)
- **No `.c4` edit in Phase 1** — do NOT run `regenerate-c4-model.sh`; there is
  nothing to regenerate. The freshness gotcha is real but only for phases that
  actually touch `.c4`.
- **Test runner is vitest, not bun** (`apps/web-platform/bunfig.toml` blocks bun test;
  #1469). Run new tests with `./node_modules/.bin/vitest run <path>`. New `.test.ts`
  must live under `test/**` (node project glob `test/**/*.test.ts`); a `.test.tsx`
  would route to happy-dom — not what we want here.
- **Guard-test isolation:** the new guard test seeds the real module-level `sessions`
  map; it MUST `sessions.delete(uid)` in `afterEach` so a future file-merge or
  `--no-isolate` switch can't silently break the cc-parity test (which relies on
  `sessions.get` being undefined). (Kieran P2-6.)
- **Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`**, NOT
  `npm run -w … typecheck` (root has no `workspaces` field).
- **Carry-forward to Phase 2** (when the live-DB integration test lands): must NOT
  create the workspace in setup and must teardown via `anonymise_user` — the mig-053+
  trigger auto-creates the solo workspace + owner membership + WORM audit row on
  `createUser` (`2026-06-02-dev-supabase-trigger-auto-creates-solo-workspace-and-worm-teardown.md`).
  Phase 2 also introduces the repo's first `*.integration.test` — set its vitest glob
  / env-gating then, not now.
- PR body uses **`Ref #5274`**, never `Closes` — the epic stays open until Phase 3
  (GA) / Phase 4 completes it.

## Open Questions
1. ~~Dev-Supabase integration harness weight~~ **RESOLVED (operator + plan-review,
   2026-06-30):** the restart-survival logic is already covered by #5338's
   `durable-workspace-binding-resolver.test.ts`; Phase 1 **confirms + cites** it (task
   1.2 / AC8) and **defers** the live-DB schema/RLS integration test to **Phase 2**
   (migration 114 — the first new DB surface that justifies the repo's first
   `*.integration.test` harness). The query-shape-proxy fallback was rejected (it
   re-tests the builder, a proxy — Kieran P2-5). Add the live-DB test to Phase 2's tasks.
2. **None remaining for Phase 1.** (Epic-level OQ1/OQ2 — Garage SPOF, checkpoint
   cadence — are Phase 4 concerns, untouched here.)
