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

- **T1 (trigger reaches cc):** a registered cc `activeQuery` for `convId`, when
  the new `abortConversation(convId, "disconnected")` runner method is called,
  fires the cc close path (`onCloseQuery`) for that conversation. Assert via a
  spy on the dispatcher's wired hook.
- **T2 (checkpoint fires on disconnect):** the cc close path, when the abort
  reason is `disconnected`, calls `checkpointInflightWork(path, convId, userId)`
  exactly once with the conversation-bound workspace path. Spy/mock
  `checkpointInflightWork`.
- **T3 (no checkpoint on non-disconnect terminals):** natural completion
  (`onWorkflowEnded` with `status:"completed"`) and explicit
  `closeConversation` (non-disconnect) do NOT call `checkpointInflightWork`
  (mirrors legacy: only `disconnected` checkpoints).
- **T4 (workspace resolution symmetry):** the checkpoint resolves the clone from
  `conversations.workspace_id` (mock the tenant `.from("conversations").select`),
  NOT from `resolveActiveWorkspacePath`. Assert the path passed equals
  `workspacePathForWorkspaceId(boundWorkspaceId)`.
- **T5 (fire-and-forget / never breaks abort):** when `checkpointInflightWork`
  rejects, the cc abort/close path still completes (existing bash-gate drain
  still runs; no throw escapes). Assert `reportSilentFallback` mirrored.
- **T6 (grace-timer wiring, ws-handler):** the disconnect grace timer
  (`ws-handler.ts:2923`) ALSO signals the cc runner for the bound conversation
  (in addition to `abortSession`). Use the existing ws-handler test harness
  pattern; assert the cc abort method is invoked with `convId`.

All RED before any GREEN. Confirm each fails for the RIGHT reason (missing
trigger / missing hook), not a harness error.

### Phase 2 — cc runner: `abortConversation(conversationId, reason)` (soleur-go-runner.ts)

Add a public runner method that aborts a SINGLE in-flight query by
`conversationId` (the disconnect terminal the cc path lacks today):

- Look up `activeQueries.get(conversationId)`; if absent, no-op (idempotent —
  a tab can close after the turn already ended).
- Abort the query's controller/interrupt the SDK `query()` (mirror what
  `reapIdle`/`closeConversation` already do internally to stop API spend), then
  route through the existing `closeQuery(state)` so `onCloseQuery` fires
  (`soleur-go-runner.ts:1966-1983`) — the same close hook `reapIdle`/
  `closeConversation` use.
- Thread the abort `reason` (`"disconnected"` | other) to `onCloseQuery` so the
  dispatcher hook can decide whether to checkpoint. Widen the `onCloseQuery`
  callback signature from `{conversationId, userId}` to
  `{conversationId, userId, reason?: "disconnected"}` (or a small typed enum).
  Per `hr-type-widening-cross-consumer-grep` + `cq-union-widening-grep-three-patterns`,
  grep all `onCloseQuery` call sites/consumers and update exhaustively; the
  existing `reapIdle`/`closeConversation` callers pass NO reason (→ undefined,
  → no checkpoint), preserving current behavior.
- Export `abortConversation` in the runner's returned object alongside
  `reapIdle`/`closeConversation` (`soleur-go-runner.ts:3220-3231`).

### Phase 3 — cc dispatcher: checkpoint on disconnect close (cc-dispatcher.ts)

In `getSoleurGoRunner`'s `onCloseQuery` hook (`cc-dispatcher.ts:1909-1910`),
extend the existing `cleanupCcBashGatesForConversation(...)` body so that **when
`reason === "disconnected"`** it ALSO checkpoints, mirroring the legacy block
(`agent-runner.ts:2368-2406`) verbatim in shape:

1. `getFreshTenantClient(userId)` → SELECT `workspace_id` from `conversations`
   where `id = conversationId`. On error/null → mirror to Sentry, skip
   checkpoint (do NOT throw — the gate drain must still run).
2. `checkpointWorkspacePath = workspacePathForWorkspaceId(boundWorkspaceId)`.
3. `await checkpointInflightWork(checkpointWorkspacePath, conversationId, userId)`
   (already fire-and-forget + Sentry-mirrored + never-throws — reuse as-is).
4. Wrap the resolution in try/catch with `reportSilentFallback({feature:
   "inflight-checkpoint", op: "checkpoint-on-abort", extra:{…, stage:
   "cc-resolve-workspace-path"}})` so a resolve failure cannot break the
   bash-gate drain (the existing `onCloseQuery` responsibility).
5. Keep the bash-gate cleanup running on EVERY close (reason or not).

Phase-ordering note (`2026-05-10-plan-phase-order-load-bearing…`): the
`onCloseQuery` signature widening (Phase 2) MUST land before the dispatcher
consumes `reason` (Phase 3) — even though the PR merges atomically, `/work`
executes phases in order.

### Phase 4 — ws-handler: signal cc runner from the grace timer (ws-handler.ts)

In the disconnect grace-timer callback (`ws-handler.ts:2923-2931`), after the
existing `abortSession(uid, convId)`, ALSO call the cc runner's new
`abortConversation(convId, "disconnected")` (via `getSoleurGoRunner()` or the
already-imported dispatch surface). Both calls are safe no-ops for the path that
does not own the conversation (legacy `abortSession` no-ops for a cc-only
conversation and vice-versa), so dual-signalling is correct and idempotent — it
does NOT double-checkpoint because only ONE path holds the live in-flight state.

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

- [ ] **AC1 (issue re-eval criterion met):**
  `git grep -n checkpointInflightWork apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/soleur-go-runner.ts`
  returns ≥1 hit (the cc-path checkpoint is wired) — the exact grep from the
  issue's "Re-eval by (event-grep)".
- [ ] **AC2 (write-side only — no restore regression):** `restoreInflightCheckpoint`
  call site (`ws-handler.ts:1994`) is unchanged; `git diff` touches no read-side
  restore logic. The cc checkpoint produces a ref the existing gated restore
  consumes unchanged.
- [ ] **AC3 (conversation-bound clone):** the cc checkpoint resolves its clone
  from `conversations.workspace_id` via `workspacePathForWorkspaceId`, NOT
  `resolveActiveWorkspacePath` — verified by T4 and by grep of the new block.
- [ ] **AC4 (disconnect-only):** T3 proves natural completion + explicit
  `closeConversation` do NOT checkpoint; only `reason === "disconnected"` does.
- [ ] **AC5 (never breaks the close path):** T5 proves a checkpoint/resolve
  failure mirrors to Sentry and the bash-gate drain still completes; no throw
  escapes `onCloseQuery`.
- [ ] **AC6 (dual-path terminal wired):** T6 proves the disconnect grace timer
  signals BOTH `abortSession` (legacy) and `abortConversation` (cc).
- [ ] **AC7 (exhaustive widening):** `tsc --noEmit` clean after the `onCloseQuery`
  signature change; every existing caller (`reapIdle`, `closeConversation`)
  passes no `reason` and is unaffected.
- [ ] **AC8 (full suite green):** `./node_modules/.bin/vitest run` (apps/web-platform)
  passes, including `cc-dispatcher-bash-gate.test.ts` and `inflight-checkpoint.test.ts`.
- [ ] **AC9 (observability slug parity):** the new emit uses
  `op: "checkpoint-on-abort"` (grep the new block) — same slug the legacy +
  restore sites use; no new orphan slug.
- [ ] **AC10 (PR body):** `Closes #5356`. (#5356 is resolved AT MERGE — the fix
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
| **(b) cc-side disconnect terminal + checkpoint hook** | **Selected** | One signal edge (grace timer → `abortConversation`) + reuse of the existing close hook + verbatim reuse of the legacy checkpoint block. Touches 3 files; legacy contract unchanged. |
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
runner abort-by-conversation → dispatcher checkpoint hook). Primary risk is the
mirroring-a-sibling-predicate class: the cc checkpoint mirrors the legacy
`isDisconnected` block — load-bearing sub-value is (a) cross-path durability the
legacy block does not provide for cc traffic, NOT redundant defense
(`2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate…`). Type-widening
of `onCloseQuery` is the one cross-consumer surface — exhaustiveness enforced by
`tsc` (AC7), not a hand count.

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

- `apps/web-platform/server/soleur-go-runner.ts` — add `abortConversation(conversationId, reason)` public method; widen `onCloseQuery` callback signature to carry `reason`; export the new method. (~line 1109-1115 hook, ~1966-1983 closeQuery, ~3220-3231 return object)
- `apps/web-platform/server/cc-dispatcher.ts` — extend the `onCloseQuery` hook in `getSoleurGoRunner` (~line 1909-1910) to checkpoint when `reason === "disconnected"`, mirroring `agent-runner.ts:2368-2406`. Import `checkpointInflightWork`, `workspacePathForWorkspaceId`, `getFreshTenantClient` as needed.
- `apps/web-platform/server/ws-handler.ts` — in the disconnect grace-timer callback (~line 2923-2931), also call the cc runner's `abortConversation(convId, "disconnected")` after `abortSession`.

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
  checkpoint off is the one it BUILDS (grace timer → `abortConversation` →
  close hook). Do not assume a pre-existing idle/shutdown terminal exists.
- **Clone-resolution asymmetry is the #1 silent-failure mode** (learning
  `2026-06-15-git-checkpoint-clean-tree-not-sufficient…` gap #3): resolve the
  checkpoint clone from `conversations.workspace_id` (what restore reads), never
  from the mutable active-claim resolver. A mismatch writes the ref where restore
  never looks → silent no-checkpoint + stranded ref. Enforced by AC3/T4.
- **Do NOT double-checkpoint.** The grace timer signals both `abortSession`
  (legacy) and `abortConversation` (cc); only ONE holds live in-flight state for
  a given conversation, so only one checkpoint fires. If a future change lets
  both paths own the same conversation, this invariant breaks — assert it in T6.
- **`onCloseQuery` widening is cross-consumer.** `reapIdle` and
  `closeConversation` both call `closeQuery → onCloseQuery`; they must pass NO
  `reason` (→ no checkpoint) to preserve current behavior. `tsc` enumerates the
  rails (AC7) — do not hand-count.
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
