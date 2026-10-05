---
title: BYOK cap enforcement model for autonomous-AI leader loops
status: accepted
date: 2026-05-25
related: [4379, 4124, 4378]
related_adrs: [ADR-042, ADR-030]
related_plans:
  - knowledge-base/project/plans/2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md
related_specs:
  - knowledge-base/project/specs/feat-4379-anthropic-leader-loop/spec.md
brand_survival_threshold: single-user incident
---

# ADR-041: BYOK cap enforcement model for autonomous-AI leader loops

## Status

**Accepted** (2026-05-25, PR #4379).

Lands in the same PR as ADR-042 and migration 069. ADR-042 documents the loop topology that this ADR's cap-enforcement model plugs into; the two ADRs are deliberately split for **cleaner reversibility** — a future cap-policy change (e.g., raising the per-spawn ceiling, swapping pre-call → post-call gating, or adding a new failure mode) is isolated to ADR-041 without re-opening the loop-topology decision in ADR-042.

## Context

PR-B introduces the first autonomous-AI runtime in `apps/web-platform/server/`. The operator (`ops@jikigai.com`) funds every Anthropic API call via BYOK. Three cost-control surfaces already exist or are introduced by PR-B:

1. **BYOK per-founder rolling cap** (existing infra, mig 053 + `record_byok_use_and_check_cap` at `mig 061:81-148`). Enforced via SQL RPC with `FOR UPDATE` lock on `public.users`.
   - **Reconciliation note (feat-l5-runaway-guard / #5767, P2-9):** the *shipped* RPC enforces a single **rolling 1-hour cumulative-spend cap per founder** — it `SUM`s `audit_byok_use` over `now() - interval '1 hour'` and compares against `users.runtime_cost_cap_cents`. The earlier prose in this ADR ("daily soft $20 / hard $50 / monthly hard $500") described an aspirational tiered model that was **never implemented in the RPC**; the daily/monthly tiers are deferred (rolling-24h founder budget is tracked as a follow-up, #5903). Treat the rolling-1-hour `runtime_cost_cap_cents` cap as the authoritative Layer-1 mechanism.
2. **Per-spawn cost ceiling** (PR-B-new, $2.60 USD — raised from $2.00 by #5849). Bounds worst-case operator-side spend on a single Today-card click. Independent of (1).
3. **Max-turns ceiling** (PR-B-new, flat 8 turns × 4096 max_tokens). Physical upper bound on loop runtime.

The PR-B brainstorm Key Decisions table locks: per-spawn ceiling is the **primary gate** (locked at $2.00; raised to $2.60 by #5849); max-turns is the **secondary backstop**; BYOK daily/monthly is the existing layer. This ADR pins the **enforcement model** — i.e., when, how, and where the checks fire — so all three layers compose correctly and fail-closed.

**Brand-survival threshold: single-user incident.** A runaway leader-loop draining the operator's BYOK balance during dogfood is brand-survival-relevant. The operator IS the brand at this stage.

### Why this needs an ADR (separate from ADR-042)

Cap-policy is high-churn. The per-spawn ceiling, the kill-tripped semantics, and the failure_reason taxonomy are likely to evolve as PR-B's per-class behavior matures in dogfood. Pinning the *current* model in ADR-041 — separate from ADR-042's loop topology — means:

- Future "raise the cap to $5" PRs amend ADR-041 only.
- Future "switch to post-call gating" PRs (e.g., if a new accounting story makes pre-call infeasible) amend ADR-041 only.
- ADR-042's invariants (per-turn `step.run`, lease scope, tool allowlist, prompt versioning) stay frozen across cap-policy churn.

## Decision

**Three-layer fail-closed model: pre-call BYOK cap gate (layer 1) + pre-call per-spawn cost ceiling (layer 2) + post-call max-turns backstop (layer 3). Every layer raises `failure_reason` and short-circuits the loop without issuing the next Anthropic call.**

### Layer 1 — Pre-call BYOK cap gate

Each per-turn `step.run("turn-${n}-cap-check", …)` invokes `recordByokUseAndCheckCap` (TS wrapper at `apps/web-platform/server/byok-cap-rpc.ts`, greenfield in PR-B) which forwards to the existing 6-arg SQL RPC at `mig 061:81-148`. The wrapper signature:

```ts
export async function recordByokUseAndCheckCap(args: {
  invocationId: string;
  founderId: string;
  workspaceId: string;            // === founderId per N2 invariant
  agentRole: "agent.spawn.requested";
  tokenCount: number;             // 0 on pre-call cap-check
  unitCostCents: number;          // 0 on pre-call cap-check
}): Promise<{ cumulativeCents: number; killTripped: boolean }>;
```

The RPC returns `killTripped: true` **exactly once** — on the call that atomically flips `runtime_paused_at NULL→now()` on a cap crossing (`v_tripped := FOUND`, migration `121_byok_cap_trip_from_found.sql` / #5919). It deliberately does NOT re-trip an already-paused caller (that would double-trip under concurrency — the atomicity Invariant C). The paused-founder re-block is therefore owned entirely by Layer 0's entry gate below, NOT by this RPC. On trip:

- The loop short-circuits with `failure_reason = "byok_cap_exceeded"`.
- The Anthropic call is NEVER issued.
- `users.runtime_paused_at` is flipped by the RPC on first breach (idempotent — only NULL→now()).

**Fail-closed semantics**: any RPC error THROWS in the wrapper rather than returning `killTripped: false`. A transient DB error must NOT allow an uncapped Anthropic call. This is the explicit contract of the wrapper unit test:

```ts
it("throws on RPC error rather than returning killTripped=false", async () => {
  // ...arrange Supabase RPC to return { error: ... }
  await expect(recordByokUseAndCheckCap(args)).rejects.toThrow();
});
```

**Pre-call, NOT post-call**: the cap check fires BEFORE the Anthropic call, with `tokenCount: 0` (the call hasn't happened yet). The PURPOSE is to gate the next call — not to record the just-completed call's cost. Cost recording happens separately in `persistTurnCost` AFTER the call returns. The two paths converge: `record_byok_use_and_check_cap` reads cumulative spend from `audit_byok_use` rows; `persistTurnCost` writes new `audit_byok_use` rows post-call. The next turn's pre-call check therefore sees the prior turn's cost (because `persistTurnCost` is awaited per ADR-042 I5).

### Layer 2 — Pre-call per-spawn cost ceiling

After the cap check passes, `step.run("turn-${n}-precheck-cost-ceiling", …)` reads the **cumulative cost of THIS spawn** by joining `audit_byok_use` rows on the time window `[action_sends.created_at, now()]` with `agent_role = "agent.spawn.requested:${actionClass}"` and `founder_id = $founderId`. If `SUM(unit_cost_cents) >= PER_SPAWN_COST_CEILING_CENTS` (260 = $2.60 since #5849), the loop short-circuits with `failure_reason = "cost_ceiling_exceeded"`.

`PER_SPAWN_COST_CEILING_CENTS` is a **single-source-of-truth constant** (per learning `2026-05-06-cap-coupling-between-adjacent-prs.md`) declared once in `apps/web-platform/server/inngest/leader-prompts/index.ts`. Drift-guard test forbids hand-rolled literals (`expect(src).not.toMatch(/\b2\.00\b|\b200\b/)` scoped to leader-prompts/ paths and the Inngest function file).

**The partial artifact is preserved on cost-ceiling trip**: if turns 1-2 emitted artifacts before turn-3's pre-check tripped, `reversal_handles` is non-NULL and the Today card renders an Undo button (per the plan's AC11 state-matrix row "`failure_reason IS NOT NULL` AND `reversal_handles IS NOT NULL`"). The operator can undo the partial output without manually scraping GitHub.

### Layer 3 — Post-call max-turns backstop

Inside the loop body, if turn `n === maxTurns` (8) and the model did NOT emit `stop_reason === "end_turn"`, the loop short-circuits with `failure_reason = "leader_max_turns_exceeded"`. This is the secondary backstop — by physical token-budget arithmetic, 8 turns × 4096 max_tokens × Sonnet pricing ≈ $0.33 worst-case at the corrected $2/$10 rates (#7774; was ≈$0.50 when this row assumed $3/$15), ~8x under the $2.60 layer-2 ceiling. Layer 3 fires when Layer 2 does NOT (e.g., on Haiku-routed classes where cost stays below ceiling but the model never converges).

### Composition

The three layers compose deterministically. For a given turn `n`:

```text
turn-${n}-cap-check         → Layer 1 → fail → "byok_cap_exceeded"
                                                      ↓ stops here
turn-${n}-precheck-cost-ceiling → Layer 2 → fail → "cost_ceiling_exceeded"
                                                            ↓ stops here
turn-${n}-claude            → Anthropic call → persistTurnCost
turn-${n}-tool-${i}         → ...
(loop exit or next turn)
At max-turns: → Layer 3 → "leader_max_turns_exceeded"
```

**Order matters.** Layer 1 fires first (BYOK is the operator-wallet gate). Layer 2 fires second (per-spawn ceiling is the per-spawn shape). Layer 3 fires last (physical loop bound). If Layer 1 fires, Layer 2 is skipped; if Layer 2 fires, the call is skipped.

### Cancellation interaction

`step.run("turn-${n}-cancel-check", …)` is independent of the cap/ceiling layers — it fires between Layer 2 and the Anthropic call. Cancellation (`cancellation_requested_at IS NOT NULL`) short-circuits with `failure_reason = "cancelled_by_operator"`. The in-flight turn ALWAYS completes before cancellation is honored (mid-turn cancellation not supported); the next turn's cancel-check fires the short-circuit. The plan's AC10 operator copy explicitly surfaces the in-flight turn cost on the "Stopped" card so the operator isn't surprised by a non-zero cost.

### Layer 0 — Spawn-entry pause gate + working-pause contract (PR-A, feat-l5-runaway-guard #5767)

The original three-layer model shipped a **cosmetic pause**: `runtime_paused_at` had zero readers/clearers repo-wide, and the RPC set `killTripped` only on the NULL→set *transition*. So an already-paused founder's next spawn re-ran the cap-check, found `runtime_paused_at` already stamped, took neither branch, returned `killTripped=false`, and **kept spending**. Nothing cleared the flag, so "resume" had no code. PR-A closes this with a **single-guard fail-closed working-pause contract**:

1. **Spawn-entry pause gate (the sole paused-case guard).** Before the turn loop — and therefore before any Anthropic call or `audit_byok_use` row — the handler reads `users.runtime_paused_at`. If set, it halts immediately via `persistFailure(reason: "run_paused")` and never enters the loop. It **fails CLOSED**: a `users`-read error also halts via `run_paused` (an unverifiable pause state must not admit a possibly-paused founder). This matches the fail-closed posture of the two adjacent steps (Layer-1 cap-check throws on RPC error; Layer-2 cost-ceiling fail-closes on cumulative-read error), so fail-open here would be the one inconsistent soft spot buying zero availability.
2. **No RPC backstop (fork resolution — see below).** An earlier draft rewrote `record_byok_use_and_check_cap` to return `kill_tripped=true` while paused. That conflates two distinct signals — "I just crossed the cap this call" (exactly-once) vs "this founder is blocked" (paused-or-tripped) — and re-broke the concurrency atomicity Invariant C that #5919 fixed with `v_tripped := FOUND`. The backstop was **abandoned**; the entry gate above (fail-closed) is the working-pause guard. Even without a backstop, Layer 2's per-spawn ceiling bounds any residual leak to ≤ `PER_SPAWN_COST_CEILING_CENTS`.
3. **Set-never-clear contract.** The cap RPC and the entry gate only *read* or *set* the pause; they NEVER clear it. The **only** clearer is the operator-resume route (`POST /api/dashboard/runtime/resume`, sets `runtime_paused_at = NULL` scoped to the caller's own id). Terminal-halt model: clearing the pause lets the founder start a **fresh** run — no checkpoint/re-bill machinery.
4. **`cap_check_unavailable` (distinct reason, P2-H).** A transient cap-check DB error is no longer misreported as `byok_cap_exceeded`; it raises `cap_check_unavailable` so the operator alert reads "we couldn't verify your budget", not a false "you exceeded your cap". Fail-closed (no Anthropic call) is preserved.

**Fork decision (CTO, 2026-07-03 — #5767 vs #5919).** During PR #5881's ship, sibling #5919 merged an exactly-once (`v_tripped := FOUND`) rewrite of the same RPC to fix the atomicity double-trip that this feature's dev-applied draft had caused. The two are contradictory on one `kill_tripped` boolean. The CTO ruled: **drop the RPC-backstop migration; make the entry gate fail-closed** (this section). Rejected alternatives: (A) drop backstop + keep entry gate fail-open — leaves one inconsistent soft spot vs the adjacent fail-closed steps, for zero availability gain; (C) add a separate `already_paused` return column — a DROP+CREATE return-type change on #5919's just-hardened live function for a guard the entry gate already provides. The availability trade (a `users`-read blip halts that founder's spawns) is accepted per the zero-downtime gate (#5923): the failure is transient and self-heals on retry, identical to the two adjacent fail-closed steps.

### Notification layer (PR-A, feat-l5-runaway-guard #5767)

Cap/loop halts were previously silent (Sentry-only). PR-A wires `notifyOfflineUser` into `persistFailure` at the **single** deadletter site, fired BEFORE the `action_sends` UPDATE (mirroring the Sentry-mirror-first ordering), inside its own memoized `step.run("notify-cost-breaker")` so Inngest replays/retries send it **exactly once** (a raw side-effect re-executes on every replay → duplicate founder pages), for the enumerated subset `{cost_ceiling_exceeded, byok_cap_exceeded, leader_max_turns_exceeded, cap_check_unavailable}` and **never** for `cancelled_by_operator` (operator-initiated) nor **`run_paused`**. `run_paused` is deliberately excluded: the `byok_cap_exceeded` breach already paged the founder when it set the pause, and the Today card renders the paused halt + Resume on every subsequent blocked spawn, so re-paging each blocked spawn would be a notification storm from the guard itself. The `cost_breaker_tripped` payload carries dollar aggregates (`cumulativeCents`/`ceilingCents`), `which_window` (`"spawn" | "cap-1h"`), and the reason — no prompt/response content, no PII beyond the founder's own account id (TR5). Copy is honest by construction: it never implies the run completed, denominates in dollars, and quotes an amount only when one exists (`cap_check_unavailable` reads "stopped as a precaution", never "paused" or "exceeded"). A notification-send failure is mirrored to Sentry (`op=notify-cost-breaker`, per `cq-silent-fallback-must-mirror-to-sentry`) and swallowed, so it can never mask the terminal state write.

## Consequences

### Positive

- **Composable, predictable failure modes**: three layers, three failure_reasons, no overlap.
- **Operator wallet-safe**: BYOK daily/monthly cap is the outermost gate; runaway can't drain it past hard cap.
- **Per-spawn-safe**: the $2.60 ceiling bounds worst-case single-click spend, even on a misbehaving Haiku-routed class that doesn't converge.
- **Audit-correct**: every Anthropic call is preceded by a fail-closed pre-call gate; every Anthropic call result is followed by an awaited `persistTurnCost` (ADR-042 I5).
- **Reversibility**: ADR-041 is the cap-policy ADR. Future "raise to $5" or "switch to post-call" amendments touch this file only.

### Negative / accepted trade-offs

- **Three caps overlap**. Per code-simplicity review (2026-05-25), the three layers are arguably redundant: BYOK daily cap alone bounds operator spend. We retain all three because:
  - Layer 1 (BYOK daily/monthly): cap is operator's daily/monthly TOTAL across all uses — not per-spawn.
  - Layer 2 (per-spawn $2.60): per-spawn shape gives the operator a single-click guarantee — "no single click will cost more than $2.60." That guarantee is denominated in REAL dollars, which is what makes Layer 2 irreducible to Layer 3 (see the 2026-09-03 amendment).
  - Layer 3 (max-turns): physical loop bound; covers the case where layer-2 cost arithmetic is below ceiling but the model never converges (Haiku classes especially).
  - Removing Layer 2 was explicitly rejected in the brainstorm Key Decisions table.
- **One extra `step.run` per turn for the cap-check**. Adds ~30ms per turn. Acceptable: per-turn budget is ~60s; cap-check is ~0.05% of the budget.
- **`persistTurnCost` must be awaited inside the lease scope** (ADR-042 I5). This was a Kieran review finding (B2); the awaited shape closes the cost-vs-Realtime ordering race.
- **No soft-warning mode** (e.g., "you're at 80% of cap"). Cap-hit is fail-closed; the operator must raise the cap via Settings → BYOK → Raise Cap and re-click Spawn. Soft-warning UX is a follow-up (Non-Goal in PR-B plan).

### Sentinel tests

| Sentinel | Path | Asserts |
|---|---|---|
| BYOK cap RPC wrapper | `test/server/byok-cap-rpc.test.ts` | Layer 1 — fail-closed throw on RPC error; N2 invariant; service-role only |
| Per-spawn cost ceiling | `test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` | Layer 2 — turn-3 trip with partial artifacts preserved |
| Max-turns backstop | same file | Layer 3 — 8-turn convergence-failure path |
| SSOT constant drift-guard | `test/server/inngest/leader-prompts/prompt-version-stability.test.ts` | `PER_SPAWN_COST_CEILING_CENTS` equals 260 ($2.60). NOTE: a value PIN, not a literal drift-guard — earlier text here cited a `constants-ssot.test.ts` that has never existed, and nothing forbids hand-rolled `260`/`$2.60` literals |
| Failure-reason exhaustiveness | `test/components/dashboard/failure-reason-copy.test.ts` | every taxonomy value has copy + Retry-eligibility flag |
| BYOK audit writer sweep | `test/server/byok-audit-writer-sweep.test.ts` (existing) | New lease site at `agent-on-spawn-requested.ts` carries a real `persistTurnCost` call (no `out-of-scope` marker) |

## Alternatives Considered

1. **Post-call cap check** — rejected; fails-open on transient errors. Pre-call is fail-closed.
2. **Soft warning at 80% cap** — rejected for v1; the operator dogfood threshold is "no surprises", and a soft warn that then auto-continues introduces an ambiguous "I clicked through that" failure mode. Filed as PR-B Non-Goal #15 if dogfood signal warrants.
3. **Drop Layer 2 (per-spawn ceiling)** — rejected; brainstorm-locked. Layer 1's daily cap alone is too coarse for the operator's per-spawn UX promise.
4. **Drop Layer 3 (max-turns)** — rejected; physical bound is necessary for Haiku classes where token cost arithmetic under-counts model convergence failures.
5. **Fold cap-enforcement into ADR-042** — rejected; cap-policy churn would force re-opening loop-topology decisions every cap-policy change.
6. **Resume-from-checkpoint apparatus (PR-A)** — rejected; the terminal-halt model (operator clears the pause + starts a fresh run) is simpler and safer than a checkpoint/re-bill state machine that would fight ADR-042's attempt-reset determinism. Accepted trade-off: a fresh run re-does work and re-spends BYOK, but the operator is explicitly in control at resume.
7. **Notify at the cap RPC layer (PR-A)** — rejected; the RPC is a pure wrapper and already funnels through `persistFailure`. Notifying there would double-notify and violate the single-responsibility of the RPC. Notification lives at the one `persistFailure` deadletter site.
8. **Fail-OPEN the spawn-entry pause read (PR-A, superseded)** — initially chosen (the Layer-1 cap-check was assumed to backstop), then **reversed by the CTO fork ruling** once #5919's exactly-once RPC removed that backstop. The gate now fails CLOSED — see Layer 0 above. Rejected alternatives to fail-closed (keep-fail-open, add-`already_paused`-column) are recorded in the Layer-0 fork-decision note.

## References

- Plan: `knowledge-base/project/plans/2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md`
- ADR-042: loop-topology dependency.
- BYOK cap RPC: `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`
- BYOK lease: `apps/web-platform/server/byok-lease.ts:338`
- Cost writer: `apps/web-platform/server/cost-writer.ts:72-160`
- BYOK lint: `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`
- Critical learnings:
  - `2026-05-06-cap-coupling-between-adjacent-prs.md` (Layer 2 SSOT constant)
  - `2026-05-12-stub-handlers-as-silent-undercount-vectors.md` (cache token persistence)
  - `2026-05-24-token-cache-margin-vs-consumer-budget-envelope.md` (BYOK lease envelope inequality referenced from ADR-042 I2)

## Amendment — 2026-09-03 (#7774): Layer 2 is real-dollar, and the ledger has an undated regime boundary

Anthropic cancelled the Sonnet 5 increase scheduled for 2026-09-01, so `MODEL_PRICING[SONNET_MODEL]`
was corrected from $3/$15 to $2/$10 per MTok. That raised the question of whether
`PER_SPAWN_COST_CEILING_CENTS` must move with it.

**Ruling: it does not. 260 stands.**

`PER_SPAWN_COST_CEILING_CENTS` is a ceiling on **real cents of the founder's own Anthropic spend**,
not a work budget denominated in cents. Three things establish that, none of them the constant's name:

1. This ADR's own Consequences section justifies Layer 2's existence — against a code-simplicity
   argument to delete it — as "a single-click guarantee", i.e. a dollar promise.
2. The number is rendered back to the founder as money. `costBreakerCopy`
   (`server/notifications.ts`) emits "You spent $X of your $2.60 per-run spending limit — your own
   Anthropic credits." Under the old row that sentence was materially false: the founder's Anthropic
   account was debited ~$1.73 at the trip point.
3. Work is bounded by **Layer 3**, not Layer 2 — `LEADER_MAX_TURNS × LEADER_MAX_TOKENS`, ≈$0.33
   worst-case, ~8x below the ceiling. Layer 2 has never been the binding constraint on well-behaved
   work.

The symmetric-looking alternative — scale 260 → 173 to preserve the work-per-spawn budget — was
rejected. #5849's 200 → 260 bump moved from one *true* state to another: the tokenizer made
equivalent work genuinely cost ~30% more real dollars, and the dollar promise was consciously re-set.
This correction fixes a state that was **never** true — a $1.73 ceiling wearing a $2.60 label.
Scaling to 173 would preserve the defect's effect, ratify a number nobody chose, and hard-code a
retired price ratio into a user-visible dollar figure. A genuinely tighter per-click promise is a
separate decision that amends this ADR on its own merits.

**Accepted trade-off:** real worst-case per-click exposure rises from ~$1.73 to $2.60 (+50%). That is
the figure #5849 chose and this ADR sanctions, outer-bounded by Layer 1's rolling-hour cap.

**Layer 1 is repaired, not loosened.** `runtime_cost_cap_cents` is a budget the user typed in their
own dollars. Tripping at ~$33 real when the user set $50 was silent under-delivery, and
unreconcilable — Soleur said $50 while Anthropic's invoice said $33, with no surface exposing the gap.

### The WORM boundary is undated in the data

`audit_byok_use` carries no model or rate column, and migration 037 makes rows permanent, so a row
written at $3/$15 is indistinguishable from one written at $2/$10. **The only partition key is
`created_at` against 2026-09-03.**

A rate column was considered and rejected: it is a DDL change on a WORM table serving two live cap
layers, it would be NULL for exactly the rows needing disambiguation, and it widens WAL on a
per-turn write path for no retrospective value. The rate change is global-in-time, so the date is a
complete partition key and a column would add nothing.

Both cap layers self-heal across the boundary (Layer 1's window is one rolling hour, Layer 2's is a
single spawn, and straddling rows are the over-attributed ones, so a trip can only be early).
**Reporting does not.** Every lifetime aggregate spanning the boundary — `workspace_cost_aggregate`,
the Today cost route, the audit page — permanently blends a 50%-over-attributed Sonnet segment with
a correct one, with error bounded by a third of pre-boundary Sonnet cents. Those totals must not be
presented as reconcilable against the founder's Anthropic invoice.

### Correction in the same PR: Layer 2 was not actually per-spawn

Reviewing the ruling above surfaced that the enforcement query never matched the semantics this
ADR describes. `turn-${n}-precheck-cost-ceiling` summed `audit_byok_use` on
`founder_id` + `agent_role` with **no time bound**, and `agent_role` is
`agent.spawn.requested:${actionClass}` — an action CLASS, constant across every spawn a founder
ever makes of that class. So the "per-spawn" ceiling was a LIFETIME per-(founder, class)
accumulator: once a founder's total for one class crossed 260¢, every later spawn of that class
failed at turn 1 with `cost_ceiling_exceeded`, permanently. `audit_byok_use` is WORM, so the
balance could not be trimmed or reset.

The step name, the constant name, the failure message (`per-spawn cost ceiling reached at turn N`)
and the notification's `whichWindow: "spawn"` all already claimed per-spawn scope. Only the query
did not — the single-click guarantee this ADR justifies Layer 2 by was never the thing enforced.

Fixed by anchoring the sum at the spawn's originating `action_sends.created_at`, mirroring the
windowed sibling in `app/api/dashboard/today/[id]/cost/route.ts` (which keeps the
`(founder_id, agent_role, created_at)` index usable). The anchor is read from the database inside
a `step.run`, never from `new Date()`: an Inngest replay re-executes the function body, so a
wall-clock anchor would re-derive a different window on each retry and make the ceiling
non-deterministic. The read fails closed — a missing anchor would silently widen the window back
to all of history, which is the defect being closed.

No backfill or remediation is required, and that is a property of the fix rather than a judgement:
windowing at the action send excludes every historical row **by construction**, so a founder
previously locked out on a class starts their next spawn at zero. This was initially proposed as a
deferred scope-out on the theory that WORM rows needed a remediation path; the CONCUR gate
dissented, correctly — the premise dissolves once the window lands.

Residual, unchanged and out of scope: the ceiling read fails closed on a transient Postgres error,
so a database blip fails the spawn rather than admitting it.
