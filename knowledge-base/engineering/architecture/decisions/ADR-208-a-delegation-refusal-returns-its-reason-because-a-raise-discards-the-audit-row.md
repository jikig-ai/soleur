---
title: "ADR-208 — A delegation refusal returns its reason, because a RAISE discards the audit row it was meant to write"
status: accepted
date: 2026-09-07
tags: [byok, byok-delegations, postgres, plpgsql, audit-ledger, accounting, worm, gdpr, art-30]
related_adrs: [ADR-040, ADR-041, ADR-045]
---

# ADR-208 — A delegation refusal returns its reason, because a RAISE discards the audit row

## Status

Accepted 2026-09-07 ([#7829](https://github.com/jikig-ai/soleur/issues/7829)).

- **Ordinal note:** re-derived at authoring time with `max + 1` over
  `origin/main`, not a presence check. `origin/main` topped out at **ADR-206**
  (`ADR-206-attribute-a-prs-filings-by-the-prs-own-body.md`), so this is
  **ADR-208**. ADR-205 is an unfilled hole — the plan for #7829 reserved it when
  ADR-204 was the ceiling, and a sibling that also planned 205 landed as 206
  instead. The hole is deliberately left unfilled: the ship gate defines "next
  free" as `max + 1`, never the lowest unused ordinal, and back-filling would put
  a 2026-09-07 decision below a decision that already cites 206.

## Related

- Amends [ADR-040](./ADR-040-byok-delegations-resolver-and-grace.md) at Decision #1
  (the refusal *signal* moves from an exception to a return value; the single-lock,
  single-transaction guarantee is preserved and strengthened) and at Decision #10
  (the TypeScript error taxonomy is constructed from a typed discriminator instead
  of a `RAISE` message substring).
- Overturns the disposition of the rejected alternative (C) in
  [ADR-041](./ADR-041-byok-cap-enforcement-model.md)'s `Fork decision (CTO,
  2026-07-03 — #5767 vs #5919)`. That rejection was of a return-type change on a
  *different* function, "for a guard the entry gate already provides" — i.e. for
  zero marginal benefit. Here the return value is the entire purpose of the change.
- Corrects a false factual claim in
  [ADR-045](./ADR-045-byok-delegation-consent-gate-and-in-flight-billing-boundary.md)
  §2, which states that on a consent-withdrawal refusal "the turn raises and the
  audit row is written with `founder_id = grantee`". The row was never written.
- Implemented by `apps/web-platform/supabase/migrations/137_byok_cap_breach_audit_row.sql`.

## Context

`public.check_and_record_byok_delegation_use` (migration 084) refuses a delegated
turn on five branches: `revoked_post_grace`, `consent_withdrawn`, `expired`,
`hourly_cap_exceeded`, `daily_cap_exceeded`. Three of them visibly
`INSERT INTO public.audit_byok_use` before raising; the two cap branches raise
without inserting. [#7829](https://github.com/jikig-ai/soleur/issues/7829) was
filed against those two.

**The issue is narrower than the defect.** In plpgsql an unhandled
`RAISE EXCEPTION` aborts the enclosing (sub)transaction and discards every data
modification the function made in it. The 084 body has one `BEGIN`, one `END;`,
**no `EXCEPTION WHEN` handler anywhere**, and PostgREST executes the RPC as one
transaction. So the `INSERT` that runs immediately before each `RAISE` is rolled
back by that `RAISE`. **No refusal branch has ever persisted a row.** The defect
is five branches, not two, and the obvious repair — "add the two missing INSERTs"
— reproduces the shape that does not work and ships green against any lint that
asserts textual ordering.

The repository already states the mechanism for a sibling function.
`048_precheck_jwt_mint_sqlstate.sql`: *"RAISE EXCEPTION rolls back the function's
effects (plpgsql atomic-volatile semantics)."* The same migration family drew the
opposite conclusion here.

**Why it costs the grantor money.** `persistTurnCost` calls this RPC from
`onResult`, after `messages.create` — the provider has already charged the
grantor's key by the time the refusal is decided. Both cap windows are `SUM`s over
exactly the rows that are not written, so the ledger permanently drops every
refused turn's real spend and the cap is enforced against a systematic
under-count. Migration 061 states the house rule this violates: *"accounting is
sacred."*

**Corroboration that nothing tested this.** `grep -rn attribution_shift_reason
apps/web-platform/test/` returns exactly one live-data assertion, and it is on the
**pass** path (`expect(auditRows![0].attribution_shift_reason, "normal
attribution").toBeNull()`). No test anywhere asserted that a refusal row persists.

## Decision

> **A refusal is a returned value, not an exception.**
> `check_and_record_byok_delegation_use` changes from `RETURNS void` to
> `RETURNS TABLE(refusal_reason text)`. All five refusal branches `INSERT` their
> `audit_byok_use` row and `RETURN` the reason; `NULL` means admitted. Only
> validation failures (missing arguments, unresolvable delegation, anonymised
> row, caller-not-grantee) still `RAISE` — no provider call is attributable to a
> delegation that does not resolve, so no row is owed.

### The in-family precedent

This is convergence on an established shape, not a novel design. The sibling cap
RPC in the same family already does it: `121_byok_cap_trip_from_found.sql`
declares `record_byok_use_and_check_cap(...) RETURNS TABLE(cumulative_cents int,
kill_tripped boolean)`, and ADR-041 Layer 1 enforces the founder cap by
*returning* `kill_tripped` for the caller to act on rather than by aborting.

### It preserves ADR-040 D1 and strengthens it

`FOR UPDATE`, both window `SUM`s and the audit `INSERT` remain in **one**
transaction under **one** row lock. Only the refusal signal changes. Because the
refusal row now commits inside the lock, a concurrent caller's `SUM` can see it —
which is precisely the TOCTOU close D1 exists to provide and which the previous
code silently failed to deliver.

### Two consequential riders, decided here

1. **Caller identity is pinned to the grantee.** 084 never validated
   `p_caller_user_id` against `v_row.grantee_user_id`: the consent re-gate reads
   withdrawals by `grantee_user_id` while every `INSERT` writes
   `founder_id = p_caller_user_id`. Once a refusal row actually persists,
   `founder_id` becomes a durable **billing** assertion that enters a named user's
   DSAR export, so an unvalidated caller would let one user's refusal be booked
   against another's identity. 137 raises `byok_delegations:caller_not_grantee`
   (`42501`) on the mismatch.
2. **`record_byok_use_and_check_cap`'s founder `SUM` gains `AND delegation_id IS
   NULL`.** 121's `SUM` groups by `founder_id` with no delegation filter and flips
   `users.runtime_paused_at`. A grantee-attributed cap row would therefore enter
   the *grantee's* own ADR-041 Layer 1 accumulator against their personal
   `runtime_cost_cap_cents`, pausing their own agent runtime for exceeding
   **someone else's** delegation cap. That outcome was unreachable before this
   change precisely because no refusal row persisted — it is *introduced* by this
   change, not inherited. The filter is also correct on its own terms: the
   personal Layer 1 cap governs the user's own key, while delegated turns run on
   the grantor's key under the delegation's own hourly and daily caps.

### The rejected alternatives, on the record

**Autonomous transaction (`dblink` / `pg_background`) — architecturally
disqualifying, on four independent grounds.**

1. **It breaks ADR-040 D1.** The audit write executes on a separate connection,
   outside the `FOR UPDATE` lock, with non-deterministic ordering against a
   concurrent caller's `SUM`. That split-write shape is the thing D1 exists to
   reject.
2. **Unrepairable WORM corruption.** An autonomous write cannot be undone when the
   outer transaction aborts for an unrelated reason (including a `23514` on the
   widened CHECK). `audit_byok_use` is append-only, and mig 066 narrowed the
   Art. 17 carve-out to `founder_id → NULL` **only**, with every other column
   unchanged. There is no repair path for a wrong row.
3. **Undeclared infrastructure.** `grep -rn "CREATE EXTENSION"
   apps/web-platform/supabase/migrations/` returns only `pg_cron`. Adding an
   extension to a managed Supabase project needs its own decision, and a
   connection string inside a `SECURITY DEFINER` body is a new in-database
   credential surface.
4. **It falsifies the encryption-posture conclusions** recorded for this change
   ("no new store, no new cross-component connection"), which hold only under the
   candidates that stay inside the existing transaction and the existing
   application→Supabase connection.

**Caller-side record — rejected.** It loses D1's single-transaction atomicity, and
`persistTurnCost` is fire-and-forget: a process exit between the RPC returning and
the caller writing loses the row. **A lost write on the billing ledger is the
exact class being fixed.**

### Decision — the newly written cap rows stay inside the window that refused them

The cap `SUM`s are **not** filtered on `attribution_shift_reason`. Three reasons:

1. The cost is real and already charged. Excluding it would make the ledger record
   money the cap arithmetic then pretends did not move — the same defect as
   writing no row, wearing an audit row as a costume.
2. Exclusion creates a **cap leak**: `v_hourly_spent` freezes at its last in-cap
   value, and every turn small enough to fit under `cap − frozen` passes forever.
3. The offsetting worry — double-counting — is not what prevents it.
   `UNIQUE(invocation_id)` + `ON CONFLICT DO NOTHING` dedupes only a replay of an
   already-minted payload, because `invocationId` is `randomUUID()` minted *inside*
   `persistTurnCost`. That is recorded here as a known limit, not as a defence.

### Decision — the down migration leaves the CHECK widened

`137.down.sql` restores the 084 function body but **does not narrow**
`audit_byok_use_attribution_shift_reason_check` back to its three original values,
and `NOT VALID` appears nowhere.

`NOT VALID` skips the initial scan but **still enforces on subsequent `UPDATE`s**.
`065_art17_cascade_deadlock_repair.sql` makes `founder_id` `ON DELETE SET NULL`,
so an account delete issues `UPDATE … SET founder_id = NULL`. A row carrying a cap
reason plus a narrowed constraint would abort that cascade and fail
`auth.admin.deleteUser` — the exact incident 065/066 repaired. ADR-040 set the
precedent for the sibling constraint on this same table ("Down migration
intentionally KEEPS this constraint").

Two reversibility facts recorded alongside it, because they are easy to assume
away: `run-migrations.sh` never executes `*.down.sql` (`*.down.sql) continue ;;`,
and it is not content-sha tracked; and rolling the code back does not roll back
its effects — rows written before a rollback stay in both windows for up to 24h.

### Decision 3 — the delegation windows carry corrected unit semantics; the founder-wide windows do not

`audit_byok_use.unit_cost_cents` holds the **whole turn's** cost in cents
(`server/cost-writer.ts`: `Math.round(costDelta * 100)` where `costDelta =
input.totalCostUsd`), passed alongside `totalTokens` as `p_token_count`. The
expression `token_count * unit_cost_cents` is therefore dimensionally
cents-tokens, and at production caps (500-2,000 cents/hour) it trips on the
first delegated turn of any realistic size. Measured on dev: an 8,000-token
turn costing 3 cents evaluated to 24,000 cents against a 250-cent cap.

Migration 137 corrects this in **its own two windows and in `v_this_cost`
only**. It does not touch migrations 061 or 121, whose founder-wide instances
of the same expression remain open and separately tracked.

**Why the correction is in scope for #7829 and not annexed.** The separate
issue owns whether a cap *threshold* is computed correctly, founder-wide.
#7829 owns whether the ledger *names the right person*. The two overlap in this
one expression because the refusal decision selects `founder_id`: an admitted
turn writes the grantor, a refused turn writes the grantee. Under the defective
arithmetic no delegated turn is ever admitted, so the grantor branch is
unreachable and every delegated row in the WORM ledger names the wrong billing
party — entering the grantee's Art. 15 export via `dsar-export-allowlist.ts`
and rendering as an ordinary charge on `/dashboard/audit`, permanently and
uncorrectably. Shipping a return-status conversion whose sole observable effect
is systematically false attribution would defeat the Art. 5(1)(d) accuracy
basis this migration is justified on. Correcting attribution is the
deliverable; correcting the founder-wide threshold is not.

**Consequence, recorded so it is not rediscovered as a contradiction.** With
`record_byok_use_and_check_cap`'s founder SUM filtered on
`attribution_shift_reason IS NULL`, an ADMITTED delegated row is read by two
accumulators under two formulas: the delegation windows sum `unit_cost_cents`;
the founder window sums `token_count * unit_cost_cents`. This is the
founder-wide defect reaching precisely the rows it already reached before
migration 137 — the filter neither widens nor narrows that reach. It resolves
when the founder-wide fix lands and 061/121 converge on `SUM(unit_cost_cents)`.

**Rejected: `AND delegation_id IS NULL` on the founder SUM.** Migration 121's
founder SUM carried no delegation filter, so grantor-attributed admitted rows
have always counted against the grantor's own ADR-041 Layer 1 cap — correctly,
since the grantor's key paid. `delegation_id IS NULL` would have removed them,
an undeclared weakening of Layer 1 outside #7829's scope, and under this
decision it would additionally leave the grantor's real delegated exposure
unmeasured by any accumulator. `attribution_shift_reason IS NULL` excludes
exactly the refusal rows migration 137 creates and nothing else.

## Consequences

- **This is an accounting fix, not an enforcement fix. State it plainly, because
  it is easy to misread: the delegation cap enforced nothing before this change,
  and it still enforces nothing after it.** The RPC is a post-hoc recorder —
  `persistTurnCost` runs after `messages.create`, and it is fire-and-forget, so the
  refusal changes nothing about the turn that provoked it. What changes is that the
  spend is now *recorded*. Making a breach abort the run is a separate decision;
  the return-status mechanism makes a pre-call gate substantially cheaper to build,
  which is the reason to file it rather than fold it in.
- The `audit_byok_use` count for a delegation stops equalling the number of
  admitted calls and becomes a **partition**: `K` admitted rows (NULL reason) plus
  the refusal rows. The 2026-07-03 learning that recorded `audit == K` is amended
  accordingly.
- Attribution is to the **grantee** (`founder_id = p_caller_user_id`,
  `attribution_shift_reason` = the cap reason), per ADR-045's "cost follows the
  party who continued past the boundary". Its visible effects differ per surface
  and are recorded per surface, not once: the Funded pane uses a service client and
  keeps the rows visible to the grantor; `/dashboard/audit` filters on
  `founder_id` and loses them; the Art. 15 export moves them from the grantor's
  bundle to the grantee's. Whole-overshoot attribution is accepted —
  `UNIQUE(invocation_id)` forbids splitting one invocation across two
  `founder_id`s.
- The live RLS policy on `audit_byok_use` is
  `audit_byok_use_workspace_member_select … USING
  (public.is_workspace_member(workspace_id, auth.uid()))`, created by
  `059_workspace_keyed_rls_sweep.sql` after it dropped
  `audit_byok_use_owner_select`. The grantor is **not** blind to these rows, and
  neither is any workspace co-member. Any reasoning that assumed grantor-blindness
  was reasoning about a policy retired at mig 059.
- Art. 30 register PA-23 limbs (c) and (g) are amended: cap-refusal telemetry is
  now written rather than discarded, and it is attributed to the grantee.
- A return-type change cannot use `CREATE OR REPLACE`, so 137 is `DROP` +
  `CREATE`. `run-migrations.sh` applies with `psql --single-transaction`, so the
  window is atomic; PostgREST reloads its schema cache afterwards.
- The leaky abstraction underneath the whole bug is dissolved: coupling a
  TypeScript error hierarchy to a plpgsql `RAISE` *message substring* left the
  refusal with no typed contract, so its only carrier was an exception — and an
  exception is precisely what destroyed the ledger row.
- **Not changed here, deliberately:** the cap arithmetic. The
  `token_count * unit_cost_cents` unit-semantics defect is founder-wide, not
  delegation-scoped, and correcting it inside this change would silently alter what
  every existing cap test means.
