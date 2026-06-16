---
title: "feat: cc-soleur-go in-flight work checkpoint parity (#5356)"
type: feature
issue: 5356
branch: feat-one-shot-cc-soleur-go-checkpoint-parity
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-15
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: cc-soleur-go in-flight work checkpoint parity (#5356)

## Enhancement Summary

**Deepened on:** 2026-06-15
**Agents:** verify-the-negative + precedent-diff (general-purpose), architecture-strategist, code-simplicity-reviewer
**Verification result:** ZERO contradictions — every load-bearing file:line citation
and every negative/no-op premise (N1–N6) confirmed against the worktree code.

### Key Improvements (applied)

1. **Drop the new `abortConversation` method — reuse + widen the existing
   `closeConversation(conversationId, reason?)`.** Both architecture (P1-1) and
   simplicity reviewers found `abortConversation` as originally specified was a
   near-verbatim duplicate of `closeConversation` (`soleur-go-runner.ts:3115-3120`),
   which is currently DEAD CODE (zero production callers — N2 confirmed). Widening
   the dead method is risk-free and deletes ~25-35 LOC of new surface.
2. **Correct the abort primitive.** There is NO AbortController/`controllerSignal`
   on the cc `ActiveQuery`. The spend-stopping abort is `state.query.close()`,
   reached via the existing `closeQuery(state)` — the same primitive
   `closeConversation`/`reapIdle` already use. Phase 2 reworded accordingly (P1-1).
3. **Thread `reason` through `closeQuery`, not just `onCloseQuery`.** `closeQuery`
   is the single function that fires `onCloseQuery` and is shared by 3 callers; it
   needs an optional `reason` param. This internal seam is NOT fully enumerated by
   `tsc` — hand-check the 3 `closeQuery` call sites (P1-2).
4. **Extract the checkpoint block into `inflight-checkpoint.ts`** and call it from
   BOTH the legacy site (`agent-runner.ts:2368-2406`) and the new cc hook. The
   block encodes the conversation-bound-clone invariant (the plan's #1 silent-failure
   mode) — two verbatim copies would drift. Single enforcement point (simplicity Q3).
5. **Trim cross-consumer-widening ceremony.** `onCloseQuery` has exactly ONE
   consumer (`cc-dispatcher.ts:1909`) and one producer (`closeQuery`). Keep
   `tsc --noEmit` as a normal gate; drop the "exhaustiveness rails" framing.

### New Considerations Discovered

- **Dispatch-time workspace resolution is USER-keyed, not conversation-bound**
  (`cc-dispatcher.ts:1281` `fetchUserWorkspacePath(userId)`). This is exactly the
  active-claim-drift hazard the conversation-bound re-resolve guards against —
  confirms AC3/T4 are load-bearing, not belt-and-suspenders.
- **Registries are mutually exclusive by construction** (per-turn routing at
  `ws-handler.ts:2314`: cc vs legacy `sendUserMessage`; different key shapes). No
  window exists where a conversationId is in both `activeSessions` AND
  `activeQueries` — so dual-signalling the grace timer cannot double-checkpoint.
- **Post-disconnect/pre-grace natural completion is safe** because `closeQuery`
  synchronously `activeQueries.delete`s the entry; a later `closeConversation`
  finds nothing and no-ops. Pinned by a new test (T-race).

> ✨ Follow-up to #5275 (PR #5350). Extends the in-flight work checkpoint
> guarantee to the **cc-soleur-go (Concierge)** path — the dominant production
> agent path — which #5275 explicitly scoped out as an architectural-pivot.

## Overview

PR #5350 (#5275) made the **legacy** agent path (`agent-runner.ts startAgentSession`,
registered in `activeSessions`) durably checkpoint a conversation's uncommitted
working-tree changes to `refs/checkpoints/<conversationId>` when the disconnect
grace timer fires `abortSession`. The **cc-soleur-go** path
(`ws-handler.ts dispatchSoleurGoForConversation` → `cc-dispatcher.ts dispatchSoleurGo`
→ `soleur-go-runner.ts`) does NOT inherit this, because the cc runner tracks
its turns in its own in-memory `activeQueries` Map and is **never registered**
in `activeSessions`. The disconnect grace timer's `abortSession(uid, convId)` is
therefore a silent no-op for cc turns.

cc-soleur-go is the dominant (effectively only) production path (#3270), so this
leaves the larger share of traffic without the PRESERVE guarantee #5275 builds.

### The decisive de-scoping discovery (write-side only)

Research established that **the restore (read) side is already path-agnostic**.
`restoreInflightCheckpoint(workspacePath, conversationId, …)` is wired on the
resume path at `ws-handler.ts:1994` and is keyed purely by `conversationId`
(via `checkpointRefName(conversationId)` — `inflight-checkpoint.ts:53,292`). It
runs for **every** resumed conversation regardless of which runtime produced the
turn. The moment a cc turn writes `refs/checkpoints/<conversationId>`, the
existing gated-restore picks it up with zero read-side changes.

**Therefore #5356 is a WRITE-SIDE-ONLY fix:** wire `checkpointInflightWork` onto
a cc-path disconnect terminal. All save plumbing (`inflight-checkpoint.ts`),
the conversation-bound workspace resolution (`workspacePathForWorkspaceId`),
and the entire restore path are reused unchanged.

### Approach decision: (a) register-in-activeSessions vs (b) cc-side terminal

The issue offers two approaches. This plan selects **(b) — build a minimal
cc-side disconnect terminal** and REJECTS (a), with the rationale recorded in
"Alternative Approaches Considered". In short: (a) forces the cc path back into
the `AgentSession` shape (`reviewGateResolvers` Map + `controllerSignal`) that
`cc-dispatcher.ts:920-927` deliberately bypassed, and re-routes every cc turn
through legacy grace-abort + supersede semantics it was designed to avoid — a
high-blast-radius regression surface for a checkpoint write. (b) adds one signal
edge from the existing grace timer into the cc runner and hangs the checkpoint
off the cc close path, touching three files with no change to the legacy contract.

## Research Reconciliation — Spec vs. Codebase

The issue body's framing is mostly accurate but contains one material
over-statement about the cc path's terminal lifecycle that reshapes the plan.

| Spec / issue claim | Codebase reality (file:line) | Plan response |
| --- | --- | --- |
| cc turns are "not aborted on disconnect at all"; grace timer's `abortSession` is a no-op for cc | CONFIRMED. `ws-handler.ts:2923-2934` grace timer calls `abortSession(uid, convId)`; that reaches only `activeSessions` (`agent-session-registry.ts:190`). cc queries live in the runner-internal `activeQueries` Map. | Build the missing edge: signal the cc runner from the grace timer (Phase 4). |
| cc durability boundary is "idle reap / `server_shutdown`, not grace-abort" | PARTIALLY FICTIONAL. `reapIdle()` is exported (`soleur-go-runner.ts:3226`) but **never scheduled in production** — no `setInterval` / caller exists (the only `setInterval` in cc-dispatcher, line 890, reaps the *pending-prompt* registry, not queries). `closeConversation()` likewise has **no production caller**. SIGTERM's `abortAllSessions()` (`index.ts:235`) drains only `activeSessions`, NOT `activeQueries`. | The plan does NOT hang the checkpoint off idle-reap or `server_shutdown` (both are dead/no-op for cc). It builds the **disconnect** terminal the issue's preferred boundary assumed already existed. Recorded as Sharp Edge. |
| The fix requires "net-new lifecycle wiring across cc-dispatcher.ts + soleur-go-runner.ts" | CONFIRMED, plus a third file: the **trigger** lives in `ws-handler.ts` (the grace timer), which the issue body omits. | `## Files to Edit` includes all three: `ws-handler.ts` (trigger), `soleur-go-runner.ts` (abort-by-conversation method), `cc-dispatcher.ts` (checkpoint hook). |
| A naive drop into `onWorkflowEnded` "would still miss the disconnect case (it does not fire onWorkflowEnded)" | CONFIRMED. The disconnect terminal must fire `onCloseQuery` (or a dedicated abort path), which is the close-side hook (`soleur-go-runner.ts:1109-1115`) firing on `reapIdle`/`closeConversation` → `closeQuery`, NOT `onWorkflowEnded`. | The checkpoint hangs off the cc *close* boundary, reached by the new abort-by-conversation method, not `onWorkflowEnded`. |
| Re-eval grep `checkpointInflightWork` in cc-dispatcher/soleur-go-runner returns ≥1 hit ⇒ done | CONFIRMED 0 hits today; only `agent-runner.ts` imports it (`agent-runner.ts:193`). | This PR makes that grep return ≥1 (the AC), satisfying the issue's stated re-eval criterion. |

## User-Brand Impact

**If this lands broken, the user experiences:** a cc-soleur-go user whose tab
closes mid-turn (laptop sleeps, network drops, tab crash) silently loses all
uncommitted edits the agent produced that turn — and a later resume can clobber
them by re-cloning / advancing the shared workspace. This is exactly the data-loss
class #5275 was built to prevent, still live for the dominant traffic path.

**If this leaks, the user's workflow is exposed via:** a checkpoint ref written
onto the WRONG clone (active-claim drift between grace-start and checkpoint), or
a checkpoint restored over a live sibling tab's tree — surfacing as one user's
in-flight work materializing into another conversation's workspace. The #5275
safety primitives (conversation-bound `workspace_id` resolution + sibling-slot
probe on restore) bound this; this PR MUST reuse them, not re-derive them.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. Invoke CPO domain
> leader if not already covered by Phase 2.5 carry-forward, or confirm CPO has
> reviewed. `user-impact-reviewer` will be invoked at review-time (review/SKILL.md
> conditional-agent block).

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

Read-only greps that gate the design. Capture each result in `tasks.md`:

1. **Confirm write-side gap is the only gap.**
   `git grep -n checkpointInflightWork apps/web-platform/server/` → expect hits
   ONLY in `agent-runner.ts` and `inflight-checkpoint.ts` (0 in cc files).
2. **Confirm restore is path-agnostic.** Read `ws-handler.ts:1994` +
   `inflight-checkpoint.ts:286-320` — verify `restoreInflightCheckpoint` keys
   solely on `conversationId` and is reached for any resumed conversation
   (not gated on a legacy-path flag). If it IS gated, this plan grows a
   read-side phase — re-scope before proceeding.
3. **Confirm cc has no live idle reaper / closeConversation caller.**
   `git grep -n "reapIdle\|closeConversation" apps/web-platform/server/ | grep -v test`
   → expect only comments + the runner def/export (no `setInterval`/caller).
   This is the load-bearing premise for Phase 2.
4. **Trace the value-of-interest from the entry point** (learning
   `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`):
   confirm `userId` + `conversationId` are in scope at the grace-timer site
   (`ws-handler.ts:2920-2934` — both already captured as `uid`/`convId`) AND
   that `workspace_id` is resolvable from `conversations.workspace_id` at the
   cc checkpoint site (symmetric with `agent-runner.ts:2378-2393`). Do NOT use
   the mutable `resolveActiveWorkspacePath` for the checkpoint clone — use
   `workspacePathForWorkspaceId(conversations.workspace_id)`, the same source
   the restore reads (learning `2026-06-15-git-checkpoint-clean-tree-not-sufficient…`,
   gap #3 "checkpoint/restore clone asymmetry").
5. **Confirm test runner + glob:** `vitest`, `test/**/*.test.ts`
   (`apps/web-platform/vitest.config.ts:44`). New test file lands under
   `apps/web-platform/test/`.

### Phase 1 — Failing tests first (RED) — `cq-write-failing-tests-before`

New file `apps/web-platform/test/cc-soleur-go-checkpoint-on-disconnect.test.ts`
(vitest, node project — matches `test/**/*.test.ts`). Drive through the cc runner
+ dispatcher seam with the SDK removed from the assertion path (learning
`2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` — use direct
runner method invocation + an injected `queryFactory`/spy, NOT a `query({prompt})`):

**[Updated 2026-06-15 — T1 folded into T2 (its assertion was existing-behavior
once `abortConversation` is dropped); T3 collapsed to one parametrized case;
added T-race.]**

- **T2 (checkpoint fires on disconnect):** `closeConversation(convId, "disconnected")`
  with a live `activeQueries` entry routes through `closeQuery` → `onCloseQuery`
  with `reason:"disconnected"`, and the dispatcher hook calls
  `checkpointInflightWorkForConversation` → `checkpointInflightWork(path, convId,
  userId)` exactly once with the conversation-bound path. Spy/mock the checkpoint
  helper. (Subsumes the old T1 "close path fires" assertion via the reason-propagation
  check.)
- **T3 (no checkpoint on non-disconnect terminals):** ONE parametrized case —
  `closeConversation(convId)` with NO reason AND natural completion
  (`onWorkflowEnded status:"completed"` → `closeQuery` with no reason) both leave
  `reason` undefined → do NOT call the checkpoint helper (mirrors legacy).
- **T4 (workspace resolution symmetry):** the helper resolves the clone from
  `conversations.workspace_id` (mock the tenant `.from("conversations").select`),
  NOT from `fetchUserWorkspacePath`/`resolveActiveWorkspacePath`. Assert the path
  equals `workspacePathForWorkspaceId(boundWorkspaceId)`. (Load-bearing: cc
  dispatch-time resolution is USER-keyed at `cc-dispatcher.ts:1281` and can drift.)
- **T5 (fire-and-forget / never breaks the drain):** when `checkpointInflightWork`
  (or the workspace resolve) rejects, the cc close path still completes (bash-gate
  drain still runs; no throw escapes `onCloseQuery`). Assert `reportSilentFallback`
  mirrored.
- **T6 (grace-timer wiring, ws-handler):** the disconnect grace timer
  (`ws-handler.ts:2923`) calls BOTH `abortSession` (legacy) and
  `getSoleurGoRunner().closeConversation(convId, "disconnected")` (cc). Use the
  existing ws-handler test harness; assert both invoked with `convId`.
- **T-race (P2-1 — completed-before-grace):** a conversation whose `activeQueries`
  entry was already removed (natural completion via `closeQuery`'s synchronous
  `activeQueries.delete`) does NOT checkpoint when `closeConversation(convId,
  "disconnected")` is subsequently called (the lookup returns undefined → no-op).
  Pins the race resolution against a future refactor that delays the Map delete.

All RED before any GREEN. Confirm each fails for the RIGHT reason (missing
trigger / missing hook), not a harness error.

### Phase 2 — cc runner: thread an abort `reason` through the existing close path (soleur-go-runner.ts)

**[Updated 2026-06-15 — reuse the existing dead-code `closeConversation`; do NOT
add a new `abortConversation` method.]** The runner already has the disconnect
terminal it needs — `closeConversation(conversationId)` (`:3115-3120`) already
looks up `activeQueries.get(conversationId)`, no-ops if absent (idempotent), sets
`state.closed = true`, and calls `closeQuery(state)`; `closeQuery` (`:1942-1984`)
calls `state.query.close()` (`:1953`) — the SDK subprocess-terminating primitive
that STOPS API spend (the same call `reapIdle` uses; there is NO AbortController
on the cc `ActiveQuery`). It is currently **dead code** (zero production callers —
N2). The only missing piece is carrying a `reason` to the close hook.

Minimal change set (all three are small, internal-seam edits):

1. **Widen `closeConversation(conversationId: string, reason?: "disconnected")`**
   (`:3115`). No behavior change to existing (zero) callers.
2. **Widen `closeQuery(state, reason?)`** (`:1942`) — the SINGLE function that
   fires `onCloseQuery` (`:1969-1974`). Pass `reason` through to the
   `onCloseQuery({ conversationId, userId, reason })` call (`:1971`). `closeQuery`
   has THREE callers (`emitWorkflowEnded` `:1939`, `reapIdle` `:3108`,
   `closeConversation` `:3119`); the first two pass NO reason (→ undefined → no
   checkpoint). **This is an INTERNAL seam — `tsc` does NOT enumerate `closeQuery`'s
   callers as exhaustively as the exported `onCloseQuery` type; hand-check all
   three call sites (P1-2).**
3. **Widen the `onCloseQuery` callback type** (`:1115`) from
   `{conversationId, userId}` to `{conversationId, userId, reason?: "disconnected"}`.
   `onCloseQuery` has exactly ONE production consumer (`cc-dispatcher.ts:1909`) and
   one producer (`closeQuery`) — `tsc --noEmit` is a sufficient gate for THIS
   surface (the `reason?` is additive/optional, so no caller breaks). Do not invoke
   heavyweight cross-consumer-widening ceremony for a single-callsite union.

`closeConversation` stays exported (`:3220-3231`) — no new export needed.

### Phase 3 — shared checkpoint helper + cc dispatcher hook (inflight-checkpoint.ts, cc-dispatcher.ts, agent-runner.ts)

**[Updated 2026-06-15 — EXTRACT the checkpoint block; do not copy-paste it.]**
The legacy block (`agent-runner.ts:2368-2406`) encodes the conversation-bound-clone
invariant the plan's Sharp Edges calls the #1 silent-failure mode. Two verbatim
copies would drift, so extract it to ONE place and call it from both paths.

**3a — Extract `checkpointInflightWorkForConversation` into `inflight-checkpoint.ts`**
(co-located with `checkpointInflightWork`). Inputs: a tenant-client factory (or
the `userId` it mints from via `getFreshTenantClient`), `conversationId`, `userId`.
Body = the verbatim legacy block:
1. `getFreshTenantClient(userId)` → SELECT `workspace_id` from `conversations`
   where `id = conversationId`. On error/null → `reportSilentFallback({feature:
   "inflight-checkpoint", op: "checkpoint-on-abort", extra:{userId, conversationId,
   stage: "resolve-workspace-path"}})`, return (no throw).
2. `workspacePathForWorkspaceId(boundWorkspaceId)`.
3. `await checkpointInflightWork(path, conversationId, userId)` (fire-and-forget,
   never throws — reuse as-is).
4. Whole resolve wrapped in try/catch → `reportSilentFallback`. Never throws to
   the caller (both the legacy abort branch AND the cc bash-gate drain must survive).

**3b — Refactor the legacy site** (`agent-runner.ts:2368-2406`) to call the new
helper inside the existing `if (isDisconnected)` guard (same PR — it's already a
3-file PR; leaving the duplicate defeats the extraction).

**3c — Wire the cc dispatcher hook** (`cc-dispatcher.ts:1909-1910`). The
`onCloseQuery` hook already calls `cleanupCcBashGatesForConversation(...)` on
EVERY close. Add: **when `reason === "disconnected"`**, ALSO
`await checkpointInflightWorkForConversation(userId, conversationId)`. Keep the
bash-gate cleanup running unconditionally. Use Sentry `stage: "cc-resolve-workspace-path"`
(deliberate cc/legacy distinction — the shared `op: "checkpoint-on-abort"` keeps
both on one monitor; the `cc-` prefix is intentional, not a typo — P2-3); thread
it via an optional `stage` arg to the helper, or accept the helper hard-codes
`"resolve-workspace-path"` and the cc/legacy distinction lives in the helper's
own caller-tagged `feature`/extra. Decide at `/work`; either keeps one emit site.

Phase-ordering note (`2026-05-10-plan-phase-order-load-bearing…`): Phase 2's
`closeQuery`/`onCloseQuery` `reason` plumbing MUST land before Phase 3c consumes
`reason` — `/work` executes phases in order even though the PR merges atomically.

### Phase 4 — ws-handler: signal cc runner from the grace timer (ws-handler.ts)

In the disconnect grace-timer callback (`ws-handler.ts:2923-2931`), after the
existing `abortSession(uid, convId)`, ALSO call
`getSoleurGoRunner().closeConversation(convId, "disconnected")`. Both calls are
safe no-ops for the path that does not own the conversation (legacy
`abortSession` no-ops for a cc-only conversation; `closeConversation` no-ops when
`activeQueries` has no entry — e.g. a legacy conversation). Dual-signalling is
correct and idempotent — it does NOT double-checkpoint because the two registries
are mutually exclusive by construction (per-turn routing at `ws-handler.ts:2314`
sends a conversation to cc XOR legacy `sendUserMessage`, with different key
shapes), so a conversationId is never live in both `activeSessions` AND
`activeQueries` simultaneously.

Add a one-line comment citing #5356 + the dual-path-terminal learning
(`2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`):
any turn-boundary lifecycle hook needs wiring on BOTH the `sendUserMessage`
(legacy) AND `dispatchSoleurGoForConversation` (cc) lineages.

### Phase 5 — Observability + GREEN + full-suite exit gate

- Verify the new checkpoint emit-site uses the same Sentry op slug family the
  restore/legacy sites use (`op: "checkpoint-on-abort"`) so the existing
  dashboards/monitors keyed on it light up for the cc path automatically
  (learning `2026-06-08-plan-route-test-new-claim-and-emit-site-removal-coupling.md`
  — do not invent a new slug that darks the existing monitor).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-soleur-go-checkpoint-on-disconnect.test.ts`
  → GREEN.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean (catches
  every `onCloseQuery` widening rail; do NOT pre-count sites — let `tsc`
  enumerate, per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`).
- Full suite: `cd apps/web-platform && ./node_modules/.bin/vitest run` — the
  existing `cc-dispatcher-bash-gate.test.ts` T13/T13b (onCloseQuery drain) and
  `inflight-checkpoint.test.ts` are the orphan-adjacent suites most likely to
  break on the signature widening; confirm green.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (issue re-eval criterion met):**
  `git grep -n checkpointInflightWork apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/soleur-go-runner.ts`
  returns ≥1 hit (the cc-path checkpoint is wired) — the exact grep from the
  issue's "Re-eval by (event-grep)". NOTE: the extraction (Phase 3a) means
  cc-dispatcher calls `checkpointInflightWorkForConversation` — which substring-matches
  `checkpointInflightWork`, so the issue's literal grep still returns ≥1. (If a
  future reviewer wants the bare `checkpointInflightWork(` call, that lives in the
  shared helper in `inflight-checkpoint.ts`; the cc path reaches it transitively.)
- [x] **AC2 (write-side only — no restore regression):** `restoreInflightCheckpoint`
  call site (`ws-handler.ts:1994`) is unchanged; `git diff` touches no read-side
  restore logic. The cc checkpoint produces a ref the existing gated restore
  consumes unchanged.
- [x] **AC3 (conversation-bound clone):** the cc checkpoint resolves its clone
  from `conversations.workspace_id` via `workspacePathForWorkspaceId`, NOT
  `resolveActiveWorkspacePath` — verified by T4 and by grep of the new block.
- [x] **AC4 (disconnect-only):** T3 proves natural completion + explicit
  `closeConversation` do NOT checkpoint; only `reason === "disconnected"` does.
- [x] **AC5 (never breaks the close path):** T5 proves a checkpoint/resolve
  failure mirrors to Sentry and the bash-gate drain still completes; no throw
  escapes `onCloseQuery`.
- [x] **AC6 (dual-path terminal wired):** T6 proves the disconnect grace timer
  signals BOTH `abortSession` (legacy) and
  `getSoleurGoRunner().closeConversation(convId, "disconnected")` (cc).
- [x] **AC7 (widening clean):** `tsc --noEmit` clean after the `closeConversation`/
  `closeQuery`/`onCloseQuery` `reason?` additions. The `onCloseQuery` type has one
  consumer (`cc-dispatcher.ts:1909`); `closeQuery`'s 3 internal callers are
  hand-verified (P1-2 — `tsc` does not exhaustively enumerate an internal helper's
  call sites). `emitWorkflowEnded` + `reapIdle` pass no `reason` (→ no checkpoint).
- [x] **AC8 (full suite green):** `./node_modules/.bin/vitest run` (apps/web-platform)
  passes, including `cc-dispatcher-bash-gate.test.ts` and `inflight-checkpoint.test.ts`.
- [x] **AC9 (observability slug parity):** the new emit uses
  `op: "checkpoint-on-abort"` (grep the new block) — same slug the legacy +
  restore sites use; no new orphan slug.
- [x] **AC10 (PR body):** `Closes #5356`. (#5356 is resolved AT MERGE — the fix
  is pure application code with no post-merge operator step, so `Closes` is
  correct here, unlike ops-remediation PRs.)

### Post-merge (operator)

- [ ] **AC11 (deploy is the remediation):** merge to `main` touching
  `apps/web-platform/**` auto-restarts the container via `web-platform-release.yml`
  — no separate operator step. (Automation: covered by existing pipeline.)

## Observability

```yaml
liveness_signal:
  what: existing pino "inflight-checkpoint wrote checkpoint ref" log now also emitted on cc disconnect
  cadence: per cc disconnect grace-abort with a dirty tree
  alert_target: none (informational); failures route via error_reporting
  configured_in: apps/web-platform/server/inflight-checkpoint.ts (log.info, op checkpoint-on-abort)
error_reporting:
  destination: Sentry via reportSilentFallback (feature inflight-checkpoint, op checkpoint-on-abort)
  fail_loud: true (mirrored, never swallowed) — but never re-thrown onto the close path
failure_modes:
  - mode: conversation.workspace_id unresolvable at cc checkpoint time
    detection: Sentry reportSilentFallback extra.stage=cc-resolve-workspace-path
    alert_route: existing inflight-checkpoint Sentry issue group
  - mode: checkpointInflightWork git plumbing failure (status/write-tree/update-ref)
    detection: Sentry reportSilentFallback op=checkpoint-on-abort (inflight-checkpoint.ts:244)
    alert_route: same group — cc and legacy share the slug, so existing monitor covers both
  - mode: active-claim drift writes ref to wrong clone
    detection: prevented by conversation-bound resolution (AC3); divergence surfaces as a restore no-checkpoint no-op log
    alert_route: pino restore-path log; no false success
logs:
  where: pino (stdout to Better Stack), op checkpoint-on-abort / cc-resolve-workspace-path
  retention: per existing Better Stack pipeline
discoverability_test:
  command: "grep -c checkpoint-on-abort <Better Stack query for cc conversation disconnect> (no ssh)"
  expected_output: "at least 1 entry after a cc tab-close mid-turn with dirty tree"
```

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
| --- | --- | --- |
| **(a) Register cc turns in `activeSessions`** so they inherit grace-abort + checkpoint | **Rejected** | The cc bypass of `activeSessions` is intentional (`cc-dispatcher.ts:920-927`): `activeSessions` assumes an `AgentSession` with a `reviewGateResolvers` Map + `controllerSignal`; cc tracks `activeQueries` itself and synthesizes per-`query()` bash-gate sessions separately. Registering cc turns would re-route them through legacy supersede/SIGTERM/grace semantics they were built to avoid — a high-blast-radius regression surface (every cc turn's lifecycle) for a checkpoint write. |
| **(b) cc-side disconnect terminal + checkpoint hook** | **Selected** | One signal edge (grace timer → existing `closeConversation(reason)`) + reuse of the existing close hook + a shared extracted checkpoint helper. Touches 5 files (incl. legacy refactor to the shared helper); legacy disconnect behavior unchanged. |
| **Hang checkpoint off `reapIdle` / `server_shutdown`** | **Rejected** | Both are dead/no-op for cc today (`reapIdle` unscheduled; SIGTERM drains only `activeSessions`). Would require ALSO building a live reaper / SIGTERM cc-drain — scope creep beyond the disconnect guarantee #5275 defines. Tracked as a separate concern (see Deferred). |
| **Schedule the idle reaper as the trigger** | **Deferred** | Scheduling `reapIdle` is a distinct durability/cost concern (idle cc queries leak in `activeQueries` until container restart). It is orthogonal to disconnect checkpoint parity and carries its own cost/UX tradeoffs. Filed as deferral (below). |

## Deferred (tracking issues)

- **cc idle-reaper not scheduled in production.** `reapIdle()` is exported but
  never called; idle cc queries persist in `activeQueries` until container
  restart (memory + stale-state concern, AND a second disconnect-class durability
  gap if a tab is abandoned without a socket close). Out of scope for #5356
  (disconnect = socket close, which #5356 covers). **Re-eval:** when a memory/
  cost signal on stranded `activeQueries` appears, OR when #5240's reconnect
  design lands. File a GitHub issue with this rationale + milestone from
  `knowledge-base/product/roadmap.md` during `/work`.
- **SIGTERM does not drain cc `activeQueries`.** `abortAllSessions()` (`index.ts:235`)
  drains only `activeSessions`; an in-flight cc turn at deploy time is not
  checkpointed on `server_shutdown`. Distinct from disconnect (#5356). Note: the
  legacy path intentionally does NOT checkpoint on `server_shutdown` either
  (`agent-runner.ts:2350` — it "owns its terminal state"), so cc parity here is
  "match legacy = no checkpoint", making this lower priority. File for tracking.

## Domain Review

**Domains relevant:** Engineering (CTO) — server lifecycle wiring; no Product/UX,
Legal, Finance, Marketing, Sales, Operations, Support implications.

### Engineering (CTO)

**Status:** reviewed (carry-forward — pipeline plan; CTO assessment folded into
Research Reconciliation + Sharp Edges)
**Assessment:** Net-new cross-subsystem lifecycle wiring (ws-handler trigger →
existing `closeConversation` reused with a `reason` → shared checkpoint helper).
Primary risk is the mirroring-a-sibling-predicate class — resolved by EXTRACTING
the checkpoint block to one helper called by both legacy + cc, so the
conversation-bound-clone invariant has a single enforcement point (not two
verbatim copies that drift). The `reason` threads through `closeQuery`, a shared
internal helper — `tsc` covers the exported `onCloseQuery` type but the 3
`closeQuery` callers are hand-checked (P1-2). architecture-strategist verdict:
approve-with-edits (all P1 edits applied here); double-checkpoint premise verified
sound (registries mutually exclusive).

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI surface. `## Files to Edit`/`Create` contain zero
`components/**`, `app/**/page.tsx`, `app/**/layout.tsx` paths; mechanical
UI-surface override does not fire. Pure server lifecycle change.

## Infrastructure (IaC)

None — pure application code against the already-provisioned `apps/web-platform`
runtime. No new server, secret, vendor, cron, or persistent process. The
`refs/checkpoints/*` namespace and Sentry/Better Stack pipelines already exist
(#5275). Phase 2.8 detection scan found no real provisioning step (the plan
introduces zero `.tf` resources, zero secret writes, zero systemd units, zero
vendor-dashboard steps); the IaC routing gate is acknowledged and opted out via
the `iac-routing-ack` marker at the top of this plan.

## GDPR / Compliance

The checkpoint persists a user's uncommitted working-tree changes to a git ref
inside their own workspace clone — same data class, same lawful basis, same
retention surface as #5275's legacy checkpoint (already covered). No NEW
processing activity, no new external-API data movement, no new distribution
surface. `single-user incident` threshold triggers `gdpr-gate` consideration,
but the data flow is byte-for-byte the legacy path's flow extended to a second
trigger site — no new regulated surface. `/work` should run `gdpr-gate` against
the diff per Phase 2.7 and expect "no new regulated surface; inherits #5275 posture".

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — widen `closeConversation(conversationId, reason?)` (~3115), `closeQuery(state, reason?)` (~1942, thread `reason` to the `onCloseQuery` call ~1971), and the `onCloseQuery` callback type (~1115) to carry `reason?: "disconnected"`. No new method, no new export. Hand-check `closeQuery`'s 3 internal callers.
- `apps/web-platform/server/inflight-checkpoint.ts` — **[Updated]** add `checkpointInflightWorkForConversation(userId, conversationId[, stage])` extracting the conversation-bound resolve + checkpoint + Sentry-mirror block; never throws. Co-located with `checkpointInflightWork`.
- `apps/web-platform/server/agent-runner.ts` — **[Updated]** refactor the legacy `if (isDisconnected)` block (~2368-2406) to call the new shared helper (kill the duplicate in the same PR).
- `apps/web-platform/server/cc-dispatcher.ts` — extend the `onCloseQuery` hook in `getSoleurGoRunner` (~1909-1910) to `await checkpointInflightWorkForConversation(userId, conversationId)` when `reason === "disconnected"`; keep the bash-gate drain unconditional. Import the helper.
- `apps/web-platform/server/ws-handler.ts` — in the disconnect grace-timer callback (~2923-2931), also call `getSoleurGoRunner().closeConversation(convId, "disconnected")` after `abortSession`.

## Files to Create

- `apps/web-platform/test/cc-soleur-go-checkpoint-on-disconnect.test.ts` — vitest (node project, `test/**/*.test.ts`), T1–T6 from Phase 1.

## Open Code-Review Overlap

None. (Ran `gh issue list --label code-review --state open` against the three
edited paths during planning; no open scope-out touches
`soleur-go-runner.ts`, `cc-dispatcher.ts onCloseQuery`, or the ws-handler grace
timer. Re-confirm at `/work` Phase 0 per skill Step 1.7.5.)

## Sharp Edges

- **The cc durability boundary the issue names ("idle reap / server_shutdown")
  is partly fictional.** `reapIdle` is unscheduled and SIGTERM does not drain
  `activeQueries` — so the ONLY real cc terminal this PR can hang a disconnect
  checkpoint off is the one it BUILDS (grace timer → `closeConversation(reason)` →
  close hook). Do not assume a pre-existing idle/shutdown terminal exists.
- **`closeConversation` is dead code today (zero production callers)** — which is
  WHY widening it (vs. adding a new method) is risk-free, and ALSO why the grace
  timer is now its first production caller. The documented invariant: any future
  caller passing NO `reason` preserves current behavior (undefined → no checkpoint).
- **The abort primitive is `state.query.close()` (via `closeQuery`), NOT an
  AbortController.** The cc `ActiveQuery` has no `controllerSignal`. Do not hunt
  for one; `closeConversation` → `closeQuery` → `query.close()` already stops API
  spend (same as `reapIdle`).
- **Grace-abort covers only the session-bound conversation** (`ws-handler.ts:2920`
  captures one `current.conversationId`). Concurrent non-bound cc conversations
  rely on idle-reap (unscheduled) — the SAME gap legacy `abortSession` has, so
  this is parity, not a new regression. Tracked with the idle-reaper deferral.
- **Clone-resolution asymmetry is the #1 silent-failure mode** (learning
  `2026-06-15-git-checkpoint-clean-tree-not-sufficient…` gap #3): resolve the
  checkpoint clone from `conversations.workspace_id` (what restore reads), never
  from the mutable active-claim resolver. A mismatch writes the ref where restore
  never looks → silent no-checkpoint + stranded ref. Enforced by AC3/T4.
- **Do NOT double-checkpoint.** The grace timer signals both `abortSession`
  (legacy) and `closeConversation(reason)` (cc); the registries are mutually
  exclusive (per-turn routing at `ws-handler.ts:2314`), so only ONE holds live
  state and only one checkpoint fires. If a future change lets both paths own the
  same conversation, this invariant breaks.
- **`reason` threads through `closeQuery`, a SHARED internal helper.** `closeQuery`
  is called by `emitWorkflowEnded`, `reapIdle`, AND `closeConversation`; only the
  last (from the grace timer) carries `"disconnected"`. `tsc` covers the exported
  `onCloseQuery` type but NOT `closeQuery`'s internal callers — hand-check all
  three (P1-2).
- **A plan whose `## User-Brand Impact` section is empty, contains placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section
  is filled (threshold: single-user incident).
- **Restore is already wired — resist adding read-side code.** Any diff touching
  `restoreInflightCheckpoint` or `ws-handler.ts:1955-2010` is out of scope (AC2);
  the cc fix is write-side only.

## Test Scenarios

Covered by T1–T6 (Phase 1). Test runner: vitest, `apps/web-platform/test/**/*.test.ts`,
invoked `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. LLM removed
from the assertion path (direct runner-method invocation + injected factory/spies).
