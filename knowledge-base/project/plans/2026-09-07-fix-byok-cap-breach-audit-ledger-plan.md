---
title: "fix: BYOK cap-breach refusals must write the audit_byok_use row before raising"
date: 2026-09-07
slug: fix-byok-cap-breach-audit-ledger
branch: feat-one-shot-7829-byok-cap-audit-ledger
issue: 7829
closes: 7829
lane: cross-domain
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`public.check_and_record_byok_delegation_use` refuses a delegated turn on five
branches. Three append the `audit_byok_use` row before raising; the two cap
branches raise without appending.

The function is a **post-hoc recorder-plus-enforcer, not a pre-flight gate**.
`persistTurnCost` calls it from the dispatcher's `onResult` handler with the
turn's *actual* token counts, so the provider has already charged the grantor's
key by the time a cap branch raises. A cap-breached turn therefore moves real
money and leaves no ledger entry at all.

This plan ships a new forward migration pair (`136`) that makes both cap
branches record the use before refusing, consistent with their three siblings
and with the "accounting is sacred" rule migration 061 states.

## BLOCKING PREMISE — the three "sibling" branches may not persist rows either

**Read this before anything else in the plan. It can invalidate the fix's shape.**

The brief, the issue, ADR-045 and this plan's first draft all rest on: *"three
branches already INSERT-then-RAISE correctly; make the two cap branches match."*
**That premise is probably false, and the whole plan changes if it is.**

In plpgsql, an unhandled `RAISE EXCEPTION` aborts the current (sub)transaction and
discards every data modification the function made. `check_and_record_byok_delegation_use`
has **one** `BEGIN`, **one** `END;`, **no `EXCEPTION WHEN` handler anywhere**, and
six unhandled `RAISE EXCEPTION`s. PostgREST runs the RPC as one transaction. So on
the `revoked_post_grace`, `consent_withdrawn` and `expired` paths, the INSERT that
executes immediately before the RAISE **is rolled back by that RAISE**. Those rows
almost certainly never reach the table.

Nothing in the repo contradicts this, and one thing corroborates it: the only
`attribution_shift_reason` assertion in the live suite
(`test/server/byok-delegations.tenant-isolation.test.ts`) is
`expect(auditRows![0].attribution_shift_reason, "normal attribution").toBeNull()`
— the **pass** path. **No test anywhere asserts that a refusal row persists.** The
`audit == K (admitted only)` invariant in the atomicity suite is equally consistent
with "refusal rows are discarded".

If confirmed:

- The defect is **larger than #7829 describes**: all five refusal branches fail to
  ledger, not two. The two cap branches are merely the ones that don't even
  *attempt* it.
- **The obvious fix is inert.** Adding `INSERT` before `RAISE` in the cap branches
  reproduces the siblings' shape — which is the shape that doesn't work. It would
  ship green against a regex lint asserting textual ordering while writing nothing.
  That is precisely the "I fixed the guard twice and my test could not see either
  fix" class this repo has been bitten by.
- ADR-045 documents an in-flight billing boundary (*"the audit row is written with
  `founder_id = grantee`"*) that **the code cannot produce**. The ADR amendment
  becomes a correction, not just an extension.

**The real architectural question then becomes: how does a function record a
refusal durably while still refusing?** The candidates, to be settled at
deepen-plan with a live probe behind them:

1. **Return a refusal outcome instead of raising.** The INSERT commits; the caller
   maps the returned reason. Attractive because `cost-writer.ts` never rethrows —
   it only reads the error to build a Sentry event — so the consumer blast radius
   is small. Cost: the return type changes from `void`, which needs `DROP` +
   `CREATE` (not `CREATE OR REPLACE`), on a live billing RPC. ADR-041's Layer-0
   fork note already flags a return-type change on this RPC family as a real cost.
2. **Autonomous transaction** (`dblink` / `pg_background`) for the audit write, so
   it survives the abort. Verify the extension is even available on Supabase before
   proposing it.
3. **Caller-side record**: the RPC returns the refusal, `persistTurnCost` writes the
   ledger row. Loses the single-transaction atomicity ADR-040 Decision #1 was
   explicitly built for (the TOCTOU window), so likely rejected — but it must be
   named and rejected on the record, not skipped.

**Phase 0 must settle this empirically before any SQL is written.** If the sibling
rows *do* persist, something non-obvious makes them so, and 136 must use that same
mechanism rather than assuming. If they do not, this plan is re-scoped from "make
two branches match three" to "make all five actually record", and the Load-Bearing
Decision below still stands but attaches to a different mechanism.

**Corroboration from inside the repo.** `048_precheck_jwt_mint_sqlstate.sql` states
the semantics explicitly for a sibling function: *"RAISE EXCEPTION rolls back the
function's effects (plpgsql atomic-volatile semantics) so the counter does NOT
drift."* The same file family draws the opposite conclusion here. The house rule
"accounting is sacred" was **stated but never in force** on any refusal branch.

## Other blocking findings from `data-integrity-guardian`

These arrived after the first draft and several exceed #7829's framing. Each needs
a disposition — fix inline, or defer with a tracking issue — before this plan is
implementable. Recorded here rather than silently absorbed.

- **B3 — the cap arithmetic is wrong by ~10⁴, and this is the most serious finding.**
  `cost-writer.ts` writes `p_unit_cost_cents: Math.round(costDelta * 100)` — the
  **whole turn's** cost, not a per-token rate (confirmed by
  `knowledge-base/project/plans/2026-05-12-fix-api-usage-tracking-undercount-plan.md`,
  and ADR-041 reads the column the same way, summing it bare). But this RPC computes
  `v_this_cost int := p_token_count * p_unit_cost_cents` and both windows are
  `SUM(au.token_count * au.unit_cost_cents)`. A 20k-token, 50¢ turn evaluates to
  1,000,000 cents — exactly the cap CHECK ceiling in `064_byok_delegations.sql`.
  **Under this reading essentially every delegated turn breaches the hourly cap on
  turn one.** That changes what the attribution decision *is*: not "attribute the
  overshoot" but "reassign the entire delegated spend from grantor to grantee from
  turn one, permanently". 136 must settle the unit semantics in the same PR — fix
  the writer or fix the SUMs — and cannot land an attribution change on top of it.
- **B4 — integer overflow in that same expression, evaluated in `DECLARE` before any
  branch runs.** `int * int` overflows at ~2.1e9; 500k tokens × 5,000¢ raises
  `22003`, which is not `P0001`, so `cost-writer.ts` falls to the else-arm
  (`op=merged-rpc-failure`) — no row, no cap check. `059_workspace_keyed_rls_sweep.sql`
  already casts `::bigint` for the same product; the cap RPCs never got it. Cast in 136.
- **B5 — my proposed `NOT VALID` remedy is wrong and would re-break the Art. 17
  cascade.** `NOT VALID` skips the initial scan but still enforces on subsequent
  **UPDATEs**. `065_art17_cascade_deadlock_repair.sql` made `founder_id`
  `ON DELETE SET NULL`, so an account delete issues `UPDATE … SET founder_id = NULL`
  over the user's audit rows; if one carries a cap reason and a narrowed constraint
  is in force, the cascade aborts and `auth.admin.deleteUser` fails — the exact
  incident 065/066 repaired. **Correct remedy: do not narrow the CHECK on rollback
  at all.** ADR-040 set this precedent for the sibling constraint in the same table
  ("Down migration intentionally KEEPS this constraint").
- **B6 — the grantor has no working spend surface at all, today.**
  `apps/web-platform/server/byok-delegation-ui-resolver.ts` selects `cost_cents`
  from `audit_byok_use` in both `resolveGrantorDelegations` and
  `resolveGranteeDelegation`. **No such column exists** (only `unit_cost_cents`), so
  PostgREST returns 42703; the destructure discards `error`, so `todaySpentCents` /
  `mtdSpentCents` / `capRemainingCents` render 0/0/full-cap for every grantor and
  grantee, always. Two unmirrored silent fallbacks on a billing surface
  (`cq-silent-fallback-must-mirror-to-sentry`). Combined with grantee attribution
  removing over-cap rows from the one RLS surface keyed on the grantor's id, this is
  disqualifying at single-user-incident. Fix in the same PR or the attribution shift
  ships with nowhere for the charged party to look.
- **A5 — `p_caller_user_id` is never validated against `v_row.grantee_user_id`.** The
  consent re-gate reads withdrawals by `v_row.grantee_user_id` but inserts
  `p_caller_user_id` as `founder_id` — two sources for "who is the grantee" in
  adjacent lines. Once `founder_id` is a *billing* assertion rather than a forensic
  note, add the guard.
- **A6 — the window SUM has been unindexed since `132_drop_unused_indexes.sql`**,
  which dropped `audit_byok_use_delegation_ts_idx` — the partial index 064 created
  for exactly this SUM. Both windows now seq-scan a growing WORM table twice per
  delegated turn while holding `FOR UPDATE`. 136 adds rows on paths that previously
  added none. Re-create it or record why the scan is acceptable.
- **A8 — column comment drift.** `066`'s `COMMENT ON COLUMN … founder_id` reads
  "Owner of the BYOK invocation", which is wrong wherever
  `attribution_shift_reason IS NOT NULL`. Update it.
- **A9 — `/soleur:gdpr-gate` is a required gate on this diff** per
  `hr-gdpr-gate-on-regulated-data-surfaces`, since `audit_byok_use` telemetry is
  enumerated in the Art. 30 register. Run it at implementation time.

**Scope boundary — binding.** `apps/web-platform/infra/sentry/issue-alerts.tf`
is off limits. The comment block above `resource "sentry_alert"
"byok_cap_exceeded"` is the authority for that boundary and already records why
— it records that #7829 stays open against the enforcement gap, and that flipping
the fallthrough there would page on every breach without fixing the missing ledger
row. Do not flip `fallthrough_type`, do not touch the rule, and do not restate
that comment anywhere else in this feature's artifacts.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Reality on this branch | Plan response |
|---|---|---|
| Three sibling branches INSERT then RAISE; two cap branches SELECT then RAISE, no INSERT | **Confirmed.** In `084_byok_delegation_withdrawals.sql`, the blocks headed `-- Grace check (clock_timestamp() not now())`, the per-turn consent re-gate, and `-- Expired check.` each `INSERT INTO public.audit_byok_use … ON CONFLICT (invocation_id) DO NOTHING` then RAISE. The blocks headed `-- Hourly cap SUM (rolling 1h).` and `-- Daily cap SUM (rolling 24h).` compute the SUM and RAISE with no INSERT. | Fix both cap branches. |
| "`v_hourly_spent` never advances … self-sustaining until the window rolls" | **Directionally right, imprecise.** The window does not freeze absolutely — a *smaller* later turn can still fall under the cap, pass, and write a normal row. The exact defect is sharper: **every refused turn's real spend is dropped from the ledger permanently, so the delegation cap is enforced against a systematic under-count.** | State the precise version in the plan and PR body; do not ship the imprecise claim. |
| The provider has already been charged | **Confirmed, and it is the crux.** `persistTurnCost` (`apps/web-platform/server/cost-writer.ts`) calls `.rpc("check_and_record_byok_delegation_use", …)` with `p_token_count: totalTokens` from the completed turn. | Reason from "the money is real" throughout; never treat the refused cost as hypothetical. |
| — (not in the brief) | **The refusal does not stop anything.** The `.rpc(...).then(...)` call is fire-and-forget: not awaited, never rethrown. Every cap error is routed to `reportSilentFallback` and swallowed. So today the delegation cap's *only* effect is a Sentry event. | Record as a named Non-Goal. Making the cap actually abort a run is a separate decision on a separate surface; this plan restores the ledger, which is the precondition for any enforcement. |
| — (not in the brief) | **`cost-writer.ts` carries a comment that documents the bug as intended behaviour**: `cap-exceeded raises WITHOUT a row.` Leaving it would make it a false comment the moment 136 lands. | In `Files to Edit`. |
| — (not in the brief) | **A live test asserts an invariant this fix inverts.** `test/server/byok-delegation.atomicity.tenant-isolation.test.ts` asserts `audit count == K (admitted only)` and `audit count == K (no double-spend)`, and a committed learning explains that `K` (not `N`) is correct *precisely because* the cap branches do not INSERT. After 136 the invariant becomes `N`. | Update the test and amend the learning. Both in `Files to Edit`. |
| Latest migration is 135 | **Confirmed** — `135_statutory_repin_send.sql`. | New pair is `136_*`. |

## Research Insights

### Premise Validation (Phase 0.6)

- **#7829** — `gh issue view 7829` returns `state: OPEN`, `closedByPullRequestsReferences: []`. Labels `priority/p2-medium`, `type/chore`, `domain/engineering`. Premise holds; the issue is live and unclosed.
- **Commit `0341b8a8f`** — present in history; the narrowing it recorded is in `apps/web-platform/infra/sentry/issue-alerts.tf` and was read in full before writing this plan.
- **Cited migration paths** — `084_byok_delegation_withdrawals.sql`, `084_…down.sql`, `061_byok_audit_workspace_id_rpcs.sql`, `037_audit_byok_use.sql`, `064_byok_delegations.sql`, `066_audit_byok_use_art17_carveout.sql`, `121_byok_cap_trip_from_found.sql` all exist and were read.
- **"accounting is sacred"** — verified as a literal string in `046_runtime_cost_state.sql`, `061_byok_audit_workspace_id_rpcs.sql` and `121_byok_cap_trip_from_found.sql`, in each case attached to the comment `Append the audit row first`. The brief attributes it to 061; that is correct, and 046 is the original.
- **Mechanism vs. the ADR corpus** — the governing ADRs are **ADR-040** (delegations resolver + WORM ledger + atomic cap RPC), **ADR-041** (cap enforcement model), **ADR-045** (consent gate + in-flight billing boundary). The proposed mechanism is *not* in any rejected-alternatives table; ADR-045 states the principle it follows. See `## Architecture Decision (ADR/C4)`.

### Property List (Phase 0.6b)

1. A cap-breached delegated turn leaves a durable ledger row recording the spend that actually occurred.
2. The delegation's rolling hourly and daily windows arithmetically include that spend, so the cap is enforced against real money rather than an under-count.
3. The row is distinguishable from a passing turn, so a reconciliation flow can tell over-cap spend from in-cap spend.
4. Cost attribution on a cap breach follows the repo's existing, ADR-sanctioned rule rather than a new one.
5. Rollback remains possible.

### Cut List (Phase 0.6b)

| Mechanism the brief floats | Property it would buy | Already covered by |
|---|---|---|
| Exclude the new cap rows from the window SUM | (2), on a "don't double-count" theory | **Cut — it *defeats* property 2.** See `## The Load-Bearing Decision`. Double-counting is already prevented structurally by `UNIQUE(invocation_id)` (mig 064) plus `ON CONFLICT (invocation_id) DO NOTHING`. |
| A new `refusal_reason` column distinct from `attribution_shift_reason` | (3) | **Cut.** `attribution_shift_reason` already carries exactly this meaning — ADR-040 defines it as marking "rows where the cost was billed to the grantor's key but the attribution shifted to the caller for audit purposes". A cap row is that shape. A new column is DDL on a WORM table serving two live cap layers for no property the existing column does not already buy. |
| Change the Sentry alert routing | operator visibility | **Cut — out of scope by standing instruction** in `issue-alerts.tf`. |
| Add a new marker to `byok-rpc-markers.json` | drift detection on the new INSERT | **Not cut, but deferred to a decision in Phase 3** — the three existing markers already fail the source lint and the live probe if 136 regresses the function. A fourth marker is additive value, not a gap. |

### Institutional learnings that constrain this work

- `knowledge-base/project/learnings/best-practices/2026-07-03-live-cap-rpc-test-aged-seed-daily-isolation-and-audit-equals-K.md` — **the single most load-bearing learning.** Three constraints: (a) the daily branch is unreachable from live calls alone because the hourly SUM is checked first and a table CHECK forces `hourly_cap ≤ daily_cap`; you must pre-seed `audit_byok_use` rows at `ts = now() − 2h` (inside 24h, outside 1h) to isolate it. `ts` is client-insertable because the WORM triggers are `BEFORE UPDATE/DELETE` only. (b) The double-spend invariant is `audit == K`, **and this fix inverts it to `N`** — the learning must be amended, not just the test. (c) Strict-`>` boundary proof requires a call at exactly `cap` asserted to PASS, with `cap % cost === 0`.
- `.../2026-07-02-byok-cap-double-trip-was-dev-rpc-drift-not-contention.md` — a migration applied directly to dev and absent from the repo once rewrote this RPC family's body. Before writing 136, read the **live** body via `pg_get_functiondef` and diff it against 084's source; do not assume the repo is the live truth.
- `.../best-practices/2026-06-19-sql-function-body-parser-must-anchor-to-create-not-bare-function.md` — any parser over this migration must anchor on `CREATE OR REPLACE FUNCTION public.<fn>(`, because `REVOKE`/`GRANT`/`COMMENT` lines also match a bare `FUNCTION public.<fn>`. 136 re-issues those lines, so this stays live.
- `.../integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md` — the runner pipes each file to `psql --single-transaction`; no `CONCURRENTLY`, no non-transactional DDL. 136 adds no index, so this is a constraint to respect rather than a task.
- `.../2026-05-30-rpc-precondition-gate-drifts-live-db-integration-fixtures.md` — changing an RPC's side effects drifts the **live-DB** fixtures, not only the offline lint. Sweep every test that calls this RPC.

### Conventions verified

- **Migration headers** must carry the issue ref, a `LAWFUL_BASIS:` line and a `RETENTION:` line (precedent: `084`, `037`). Body wrapped `BEGIN;` … `COMMIT;`, closing with the tracking-row footer comment.
- **Apply path**: `apps/web-platform/scripts/run-migrations.sh` pipes the migration body plus the `_schema_migrations` INSERT to `psql --single-transaction --set ON_ERROR_STOP=1`, invoked from the `#migrate` job of `web-platform-release.yml`. Body and tracking row are atomic.
- **CHECK widening precedent** is the `DROP CONSTRAINT IF EXISTS` → `ADD CONSTRAINT` pair in `084`.
- **Test runner**: vitest. `unit` project collects `test/**/*.test.ts`. Single file: `cd apps/web-platform && ./node_modules/.bin/vitest run <path> --project unit`. Never `npm run -w` (no root `workspaces` field).
- **`.tenant-isolation.test.ts` suffix is load-bearing** for the `tenant-integration.yml` path filter; live suites are gated by `TENANT_INTEGRATION_TEST=1`.

## The Load-Bearing Decision

> **Do the newly-written cap rows count toward the very SUM that refused them?**
> **Yes. They are not filtered out. This is the decision the plan turns on.**

### Why

1. **The cost is real, already spent, and already the grantor's.** `persistTurnCost`
   runs after `messages.create`. Excluding the row would mean the ledger holds a
   record of money that the cap arithmetic then pretends did not move — which is
   the *same* defect as writing no row at all, wearing an audit row as a costume.
2. **Exclusion creates a cap leak.** If cap rows were filtered out of the SUM,
   `v_hourly_spent` would freeze at its last in-cap value. Every subsequent turn
   small enough to fit under `cap − frozen_spend` would PASS, indefinitely, while
   the delegation is already over budget. That is strictly worse than today's bug.
3. **Double-counting is bounded — but NOT by the mechanism the first draft
   claimed.** *Corrected after review:* `UNIQUE(invocation_id)` +
   `ON CONFLICT DO NOTHING` does **not** give one-call-one-row. `invocationId` is
   minted by `randomUUID()` *inside* `persistTurnCost`, so two invocations for the
   same provider call mint two different uuids and the conflict never fires. The
   constraint dedupes only a retry of an already-minted RPC payload — and
   `cost-writer.ts`'s comment claiming Inngest-retry idempotency is wrong for the
   same reason. If one-call-one-row is load-bearing for billing attribution, the
   key must be **derived** (conversation + turn index), not random. Treat that as
   an open item this plan must resolve, not a settled support.
4. **A permanent wedge is bounded, with a caveat.** Both windows are rolling and
   filter on `au.ts`, so rows age out — contrast ADR-041's 2026-09-03 amendment,
   where a genuinely unbounded *lifetime* accumulator did wedge a founder out of a
   whole action class. *Corrected after review:* because the run does not abort
   (the caller is fire-and-forget), each refused turn extends the over-cap state by
   a fresh hour from its own `ts`. The window is rolling, but its numerator is fed
   by the very condition it refuses. Bounded, not benign.
5. The refusal is not, today, an enforcement action that could be "unfairly"
   reinforced — it is a Sentry event on a swallowed error. Inclusion makes the
   ledger honest; it does not tighten a brake that is not connected.

**The conclusion survives review; two of its three original supports did not.**
`data-integrity-guardian` attacked this decision directly and returned "correct,
keep it — exclusion is never right here", while invalidating the idempotency and
wedge arguments above. They are corrected in place rather than quietly dropped.

### The test that fails if this is wrong

`test/server/byok-delegation.atomicity.tenant-isolation.test.ts` already asserts
that the table's summed spend for the delegation equals `CAP_CENTS` after the
concurrency battery. Under this decision that assertion must become
`N × COST_CENTS` — every one of the `N` serialized calls contributed. **If the
cap rows were excluded from the SUM, or not written, the sum stays at
`CAP_CENTS` and the assertion fails.** That single assertion discriminates
include-vs-exclude, and it is why the change to this file is a deliverable and
not a chore. See `## Test Scenarios` T5.

## Supporting Decisions

### Attribution — `founder_id` is the grantee (`p_caller_user_id`)

Matches all three sibling refusal branches. ADR-045 states the principle
verbatim: *"cost follows the party who continued past the boundary"*, and
ADR-040 defines `attribution_shift_reason` as marking rows "where the cost was
billed to the grantor's key but the attribution shifted to the caller for audit
purposes". A delegation cap is the grantor's bound on the grant, and spend past it
is spend past the boundary.

**Corrected after review:** the first draft justified this as "what makes the cap
financially protective". That is false as written — the caller is fire-and-forget,
so the refusal stops nothing and 136 buys **attribution, not protection**. The
plan claims only attribution. The accepted-trade-off below was also understated by
an order of magnitude for the same reason: because the run continues and each
swallowed refusal feeds another real-cost row into the window numerator, it is not
one 50c turn that lands on the grantee — it is **every turn from the crossing to
the end of the run, plus every turn for the following rolling hour**, on a grant
the grantee is still fully authorised to use. Either rewrite the consequence or
make the refusal actually abort the run; do not ship the understated version.

**This is an extension of ADR-045's reasoning, not a mechanical application of
it — and the plan says so rather than smuggling it.** The CLO review raised the
disanalogy directly: in the three sibling branches the grantee's *authority* had
lapsed (revoked, expired, consent withdrawn), so the grantee used a key they were
no longer permitted to use. On a cap breach the delegation is still valid, the
grantee was authorised, the cap is a limit the **counterparty** configured
(side letter §3.3 allocates cap configuration to the Grantor), and the breach is
only detectable after the spend. Reading `cap_exceeded` as pre-sanctioned by
ADR-045 would be wrong. The extension is defensible — a bounded grant's bound is
part of the grant — but it is a decision this PR makes, which is exactly why the
ADR-045 amendment below is a deliverable and not a footnote.

**Accepted trade-offs, stated rather than hidden:**

- **Whole-overshoot attribution.** A 50c turn crossing a 99c/100c boundary
  debits the grantee the whole 50c, not the 49c over. Splitting one invocation
  across two `founder_id`s is forbidden by `UNIQUE(invocation_id)` and would be
  a much larger design.
- **RLS visibility inverts.** `audit_byok_use` is `SELECT USING (auth.uid() =
  founder_id)`, so grantee-attribution means the *grantor* cannot see the
  over-cap rows their key paid for. This is pre-existing behaviour for the three
  siblings, but it deserves an explicit answer here because #7829 is framed
  around grantor money. Flagged for `data-integrity-guardian` and the CPO
  sign-off.
- **Founder-cap contamination.** `record_byok_use_and_check_cap` (mig 121) SUMs
  by `founder_id`, so grantee-attributed rows push the *grantee's* own
  `runtime_cost_cap_cents` kill-switch toward tripping on spend from someone
  else's key. Again pre-existing for the siblings; named so review can rule on it.

**Rejected alternative:** `founder_id = grantor` with a new `refusal_reason`
column. Rejected — it is DDL on a WORM table serving two live cap layers, and it
buys no property the existing column does not. Setting `founder_id = grantor`
with a *non-NULL* `attribution_shift_reason` would also be self-contradictory:
the column would claim a shift that did not happen.

### Enum — the CHECK is widened, additively

`audit_byok_use_attribution_shift_reason_check` currently admits
`('revoked_post_grace','expired','consent_withdrawn')`. 136 widens it to also
admit `'hourly_cap_exceeded'` and `'daily_cap_exceeded'`, using the same
`DROP CONSTRAINT IF EXISTS` → `ADD CONSTRAINT` shape 084 uses.

**Underscores, deliberately.** The reason values match the RAISE suffixes
(`byok_delegations:hourly_cap_exceeded`). They are *not* the Sentry `op` slugs,
which are hyphenated (`hourly-cap-exceeded`) in `cost-writer.ts` and in the
Terraform filter. Mig 064 already establishes that sibling reasons use
underscores and only `cross-tenant` is hyphenated. Do not "harmonise" these.

### Rollback — `136.down.sql` narrows with `NOT VALID`

`084_byok_delegation_withdrawals.down.sql` narrows the enum unconditionally and
its header instructs an operator to "null those rows first". **That remedy is
impossible**: `audit_byok_use` is WORM (`audit_byok_use_no_update` from mig 037),
and mig 066 narrowed the carve-out to the single Art. 17 shape of
`founder_id → NULL` with every other column unchanged. A
`SET attribution_shift_reason = NULL` UPDATE is rejected by the trigger, so 084's
down migration is unrunnable once one `consent_withdrawn` row exists.

**Correction after review — `NOT VALID` is the wrong instrument.** The first draft
proposed re-adding the narrowed constraint with `NOT VALID`. That is wrong:
`NOT VALID` skips the initial table scan but still enforces on subsequent
**UPDATEs**, and `065_art17_cascade_deadlock_repair.sql` made `founder_id`
`ON DELETE SET NULL`, so an account delete issues `UPDATE … SET founder_id = NULL`
across the user's audit rows. A cap-reason row plus a narrowed constraint aborts
that cascade and fails `auth.admin.deleteUser` — reintroducing the exact incident
065/066 were written to repair.

**Correct remedy: `136.down.sql` does not narrow the CHECK at all.** A widened
enum is harmless once the code writing the new values is gone. ADR-040 already set
this precedent for the sibling constraint on the same table ("Down migration
intentionally KEEPS this constraint").

Also note the WORM claim needs its stronger phrasing: narrowing is not strictly
*impossible* — `059_workspace_keyed_rls_sweep.sql` shows the
`DISABLE TRIGGER audit_byok_use_no_update` escape hatch — but mig 037's header
calls a trigger drop "itself a forensic signal", so the honest statement is that
**084's documented remedy requires disarming the WORM guarantee on a billing
ledger**, which is an Art. 30 evidentiary-integrity problem, not an operator step.

`084.down.sql` is **already broken in production today** — any withdrawal that has
ever fired makes its step 3 unrunnable, independent of 136. Fix it in this PR
rather than only documenting it: `.down.sql` files are skipped by
`run-migrations.sh` (`*.down.sql) continue ;;`) and are not content-sha tracked,
so editing 084's down file is safe and creates no ledger drift. Phase 5 becomes a
fix, not a scope call.

## User-Brand Impact

**If this lands broken, the user experiences:** a delegated teammate's runs are
either refused when they should be admitted (a too-tight window if rows
double-count) or admitted indefinitely past the grantor's stated cap (a cap leak
if rows are excluded from the SUM). In the second case the grantor is billed by
Anthropic for spend their configured cap said would not happen, with no Soleur
record reconciling it.

**If this leaks, the user's money is exposed via:** the grantor's own Anthropic
API key being charged past the ceiling they set on the grant, with the overage
absent from `audit_byok_use` and therefore absent from the usage dashboard, the
`workspace_cost_aggregate` rollup, and the DSAR export. The failure is silent by
construction — the caller swallows the RPC error.

**Brand-survival threshold: single-user incident.** This matches ADR-040's stated
threshold for the delegations surface ("an unauthorized invoice") and ADR-045's.
One grantor billed past their own cap with no ledger is the incident.

`requires_cpo_signoff: true` is set in frontmatter. `user-impact-reviewer` is to
be invoked at review time.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/136_byok_cap_breach_audit_row.sql` | Widen the CHECK enum; `CREATE OR REPLACE` the RPC so both cap branches INSERT before RAISE. Re-issue `REVOKE`/`GRANT` verbatim. |
| `apps/web-platform/supabase/migrations/136_byok_cap_breach_audit_row.down.sql` | Restore the 084 RPC body; narrow the enum with `NOT VALID`. |
| `apps/web-platform/test/supabase-migrations/136-byok-cap-breach-audit-row.test.ts` | Offline migration-shape lint, following the `084`/`121` conventions. |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/server/cost-writer.ts` | The delegated-path comment states `cap-exceeded raises WITHOUT a row.` — false the moment 136 lands. Rewrite to describe the post-136 behaviour. **No code change** in this file; the error branches are unchanged. |
| `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts` | Invert the `audit == K` invariant to `N` (both assertion sites and the header comment that explains why `K`), and change the summed-spend assertion from `CAP_CENTS` to `N × COST_CENTS`. Add the cap-row-attribution and daily-branch cases. |
| `knowledge-base/project/learnings/best-practices/2026-07-03-live-cap-rpc-test-aged-seed-daily-isolation-and-audit-equals-K.md` | Amend Key Insight #2: after 136 the delegation RPC inserts on every branch, so the invariant is `N`. Leaving it unamended ships knowingly-false institutional knowledge. |
| `knowledge-base/engineering/architecture/decisions/ADR-045-byok-delegation-consent-gate-and-in-flight-billing-boundary.md` | Amendment extending the in-flight billing boundary to the cap branches. See `## Architecture Decision (ADR/C4)`. |
| `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json` | *Conditional* (Phase 3 decision) — add an INSERT-shaped marker for `check_and_record_byok_delegation_use` so the drift probe detects a regression that keeps the RAISE but drops the INSERT. |
| `knowledge-base/legal/article-30-register.md` | **CLO BLOCKING-1.** PA-23 nowhere records that `audit_byok_use.founder_id` can name a party other than the one whose key was charged. Amend limb (c) to state the attribution shift and enumerate all five reasons; add a (g) sub-item recording that cap refusal is now ledgered — limb (g)(5) currently asserts cap enforcement as a TOM with no record of it ever firing. |
| `docs/legal/data-protection-disclosure.md` | **CLO BLOCKING-3.** §2.3(w) states the shift as withdrawal-only: *"withdrawal … stops any in-flight run's billing within one turn (the run's remaining cost is debited to the Grantee, not the Grantor)"*. It already understates today (three triggers); 136 makes five. Generalise to state the shift as a property of the cap RPC with its full trigger set. |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | The DPD mirror, byte-identical at §2.3(w). Paired edit — the drift ratchet applies. |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | Re-pin the DPD SHA after the paired edit. |
| `apps/web-platform/server/byok-delegation-ui-resolver.ts` | **B6 — fix inline.** Both `resolveGrantorDelegations` and `resolveGranteeDelegation` select a non-existent `cost_cents` column (only `unit_cost_cents` exists) and discard the PostgREST `error`, so every spend figure renders 0. Fix the column name and mirror the error (`cq-silent-fallback-must-mirror-to-sentry`). |
| `apps/web-platform/supabase/migrations/084_byok_delegation_withdrawals.down.sql` | **A4 — fix inline.** Its step-3 narrow is already unrunnable in production. `.down.sql` files are skipped by the runner and not content-sha tracked, so editing is safe. |
| `knowledge-base/legal/delegation-consent-side-letter-template.md` | **Conditional on the Phase 0 fork.** §1.3 says caps are "enforced automatically" and §3.3 allocates cap *configuration* to the Grantor, but nothing allocates the *cost of the turn that trips the cap*. Amend §3.3 only if a live arms-length pair exists — a version bump fail-closes every stale acceptance (ADR-045), so it is not free. |

**Not edited, deliberately:** `apps/web-platform/infra/sentry/issue-alerts.tf`
(standing instruction), `084_byok_delegation_withdrawals.sql` (forward-only;
never edit an applied migration in place).

## Implementation Phases

### Phase 0 — Preconditions (no writes). **This phase can re-plan the feature.**

0. **Settle the blocking premise, empirically, against dev.** This gates
   everything downstream. Two probes, both read-only apart from the deliberate
   RPC call, both against **dev** (`hr-dev-prd-distinct-supabase-projects`):
   - *Historical:* does the live table hold any refusal row at all?
     `SELECT attribution_shift_reason, count(*) FROM public.audit_byok_use
      WHERE attribution_shift_reason IS NOT NULL GROUP BY 1;`
     A zero row-count for `revoked_post_grace` / `consent_withdrawn` / `expired`
     on a database where those branches have fired is strong corroboration that
     the RAISE discards the INSERT. (Absence is only evidence if those branches
     have actually fired — check the Sentry history for `op=revoke-past-grace` /
     `op=expired` before treating a zero as decisive.)
   - *Direct, and decisive:* seed a delegation into a refusal state on dev, call
     the RPC so a sibling branch raises, then **from a separate connection and a
     new transaction** query for the row by `invocation_id`. Present ⇒ some
     mechanism saves it and 136 must reuse it. Absent ⇒ the premise is false,
     stop and re-plan around the architectural fork above.

   Do **not** run this probe as `BEGIN; SELECT rpc(...); ROLLBACK;` — that shape
   cannot distinguish "the RAISE rolled it back" from "the ROLLBACK rolled it
   back", which is the exact question being asked.
1. Read the comment block above `resource "sentry_alert" "byok_cap_exceeded"` in
   `apps/web-platform/infra/sentry/issue-alerts.tf` in full. It is the scope
   authority. Confirm nothing in this plan touches it.
2. Read the **live** function body and diff against 084's source, per the dev-drift
   learning:
   `doppler run -p soleur -c dev -- psql "$DATABASE_URL" -Atc "SELECT pg_get_functiondef('public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure)"`
   If the live body diverges from 084, **stop and re-plan** — 136 would silently
   overwrite an un-committed dev change.
3. Read the live CHECK constraint definition to confirm the current admitted set:
   `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'audit_byok_use_attribution_shift_reason_check';`
4. Confirm `136` is still the next free number against `origin/main`.
5. **Resolve the side-letter fork (a technical fact, not an operator question —
   `hr-technical-fork-is-not-an-operator-question`).** The question is whether a
   live arms-length grantor↔grantee pair exists. Resolve mechanically, all three:
   - `bash plugins/soleur/skills/flag-list/…` (or `/soleur:flag-list`) for the
     live Flagsmith + Doppler state of `byok-delegations`. `.env.example` carries
     `FLAG_BYOK_DELEGATIONS=0` and PA-23 (g)(7) says "default OFF", but the
     runtime flag is per-org in Flagsmith, so the env default proves nothing
     about prd.
   - Read-only against prd: `SELECT count(*) FROM public.byok_delegations WHERE
     revoked_at IS NULL AND grantor_user_id <> grantee_user_id;` and the same
     over `byok_delegation_acceptances`. **Read-only only** — no synthetic rows
     against prd (`hr-dev-prd-distinct-supabase-projects`).
   - `knowledge-base/legal/audits/2026-05-counsel-review-4625.md` names "first
     arms-length (non-jikigai) user accepts a delegation" as its own
     re-evaluation trigger; check whether it has fired.

   If zero live arms-length pairs: defer the side-letter version bump to the next
   scheduled bump and record the deferral in the PR body. If any exist: the bump
   is required before 136 ships, and this plan grows a phase.
6. **Reconcile the retention figure before writing the migration header.** The
   corpus is three-way contradictory for `audit_byok_use`: PA-13 limb (f) says a
   12-month sweep, PA-22 limb (f) says 90 days, PA-23 limb (f) and DPD §2.3(w)
   say 7 years — and `grep 'cron.schedule'` across every migration returns no
   sweep on this table at all, so effective retention today is indefinite and all
   three figures are unevidenced. Pick one, correct the other two, and do not let
   136's header assert a sweep that does not exist.

### Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

**The RED test must be behavioural, not textual.** A regex lint asserting "INSERT
precedes RAISE" passes green against a fix whose INSERT is rolled back — the exact
failure mode the blocking premise names. The offline lint is a cheap tripwire, not
the proof.

1. **Primary (behavioural, live).** Edit the tenant-isolation test to the post-136
   invariants (T5–T9). The load-bearing assertions are that after a cap refusal
   (a) the row is visible **from a fresh connection in a new transaction**, and
   (b) the next call's window SUM has grown by that turn's cost. Under
   `TENANT_INTEGRATION_TEST=1` these fail against the current RPC.
2. **Secondary (textual tripwire).** Create
   `136-byok-cap-breach-audit-row.test.ts` for the migration shape (T1–T4).
3. Record both failures. Do not proceed until they fail for the *right reason*
   (row genuinely absent / enum value missing), not a fixture error.

### Phase 2 — GREEN: the forward migration

1. Write `136_byok_cap_breach_audit_row.sql`:
   - Header with `#7829`, `LAWFUL_BASIS:` and `RETENTION:` lines (values per the
     CLO advisory folded into `## Domain Review`), and a note that it supersedes
     084's body for this function only.
   - `BEGIN;`
   - `DROP CONSTRAINT IF EXISTS` → `ADD CONSTRAINT` widening the enum with the two
     cap reasons added to the existing three.
   - `CREATE OR REPLACE FUNCTION public.check_and_record_byok_delegation_use(...)`
     — **the full 084 body, verbatim, with only the two cap branches changed.**
     Diff the result against 084 to prove no sibling clause was silently dropped
     (this exact class bit migration 085 before). Keep `SECURITY DEFINER` and
     `SET search_path = public, pg_temp`
     (`cq-pg-security-definer-search-path-pin-pg-temp`). Keep the `FOR UPDATE`.
   - Each cap branch: `INSERT INTO public.audit_byok_use (…) VALUES (…,
     p_caller_user_id, …, p_delegation_id, '<cap reason>') ON CONFLICT
     (invocation_id) DO NOTHING;` **then** the existing `RAISE EXCEPTION` with its
     `DETAIL` format string unchanged.
   - Re-issue the `REVOKE ALL` / `GRANT EXECUTE … TO service_role` pair verbatim.
   - `COMMIT;` + the tracking-row footer comment.
2. Write `136_…down.sql`: restore the 084 body verbatim, then narrow the enum back
   to the 084 set. A CHECK constraint cannot be *altered* to `NOT VALID`, so this
   is explicitly `ALTER TABLE … DROP CONSTRAINT IF EXISTS …;` followed by
   `ALTER TABLE … ADD CONSTRAINT … CHECK (…) NOT VALID;`, with a header comment
   explaining why (WORM table; 084's "null those rows first" approach is
   unrunnable because the `audit_byok_use_no_update` trigger rejects that UPDATE).
3. **Derive the body from the live definition, not from 084's source text.** Use
   the `pg_get_functiondef` output captured in Phase 0 as the base and apply only
   the cap-branch hunks to it. Add a test asserting 136's function body differs
   from 084's in **only** the two cap hunks (plus the header) — an allowed-diff
   assertion catches the silent-clause-drop class mechanically instead of relying
   on a careful reviewer.
4. Run the offline lint green.

### Phase 3 — Drift-probe coupling

1. Confirm `byok-rpc-body-markers.test.ts` now resolves the function body from
   `136` (it selects the highest-numbered defining migration) and that all three
   existing markers — `FOR UPDATE`, `hourly_cap_exceeded`, `daily_cap_exceeded` —
   are still present. They must not be dropped.
2. **Decide and record**: add a fourth marker asserting the INSERT is present in
   this RPC's body, so the live `dev-migration-drift-probe` detects a regression
   that keeps the RAISE but loses the INSERT. Default: add it. If added, update
   `byok-rpc-markers.json` and verify the live probe's `jq` read still parses.

### Phase 4 — Consumer and knowledge sweep

1. `git grep -n 'check_and_record_byok_delegation_use' -- apps/web-platform` and
   confirm every call site and test either seeds the new precondition or expects
   the new side effect (per the RPC-precondition-drift learning).
2. Rewrite the false comment in `cost-writer.ts`.
3. Amend the `audit == K` learning.
4. Amend ADR-045 per `## Architecture Decision (ADR/C4)`.

### Phase 4b — Legal corpus (CLO BLOCKING items)

1. **PA-23 amendment** in `knowledge-base/legal/article-30-register.md`: limb (c)
   gains the attribution-shift fact and the five reasons; limb (g) gains a
   sub-item recording that cap refusal is ledgered.
2. **DPD §2.3(w) generalisation** — paired edit across
   `docs/legal/data-protection-disclosure.md` (canonical) and
   `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (mirror,
   currently byte-identical at that anchor), then re-pin
   `apps/web-platform/lib/legal/legal-doc-shas.ts`. Fixing the two *currently*
   undisclosed reasons (`revoked_post_grace`, `expired`) in the same edit is free
   and correct — §2.3(w) already understates before 136.
3. `scripts/lint-legal-registers.sh` went **blocking on 2026-09-07 (#7881)**, so
   the PA-23 amendment must pass it. Run it locally before pushing.
4. **Advisory, carried as a decision not a silent skip:** the CLO asks that
   `attribution_shift_reason` be *rendered* alongside cost in the audit viewer
   and the DSAR bundle, so a grantee's Art. 15 export does not assert a cost the
   Anthropic invoice contradicts (Art. 5(1)(d) accuracy). The column already
   travels in the export payload — `dsar-export-allowlist.ts` maps
   `audit_byok_use` on `founder_id` with no `additionalOwnerFields`, so no
   allowlist edit is needed — but travelling is not rendering. Verify what the
   viewer shows; if it does not render the reason, either fix inline or file it
   with a tracking issue. Do not leave it unstated.

### Phase 5 — Scope call on `084.down.sql`

Decide, and record the disposition in the PR body: repair `084.down.sql`'s
unrunnable narrow (same `NOT VALID` fix) inline, or file it. **Default: fix
inline** — it is a two-line change in a file this feature is already reasoning
about, `rf-review-finding-default-fix-inline` applies, and leaving a known-broken
rollback path in place on a billing ledger is not a defensible deferral. If
deferred, it needs a tracking issue, not a comment.

### Phase 6 — Verify

Run the offline suite, the typecheck, and the live tenant-integration suite
against dev. Commands in `## Acceptance Criteria`.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `apps/web-platform/supabase/migrations/136_byok_cap_breach_audit_row.sql`
  and its `.down.sql` both exist and both wrap their body in `BEGIN;`/`COMMIT;`.
- **AC2** — the migration's `CREATE OR REPLACE FUNCTION
  public.check_and_record_byok_delegation_use` body contains exactly **six**
  `INSERT INTO public.audit_byok_use` statements — the three existing refusal
  siblings, the two new cap branches, and the pass path — each followed by
  `ON CONFLICT (invocation_id) DO NOTHING`. Verify by extracting the single
  function definition with the `CREATE OR REPLACE`-anchored extractor, never a
  bare `FUNCTION` match.
- **AC3** — in the extracted body, each of `byok_delegations:hourly_cap_exceeded`
  and `byok_delegations:daily_cap_exceeded` is **preceded** by an
  `INSERT INTO public.audit_byok_use` within its own `IF … THEN … END IF;` block.
  This is the assertion that would fail if the INSERT were added after the RAISE
  (where it is unreachable).
- **AC4** — the body retains `SECURITY DEFINER`, `SET search_path = public, pg_temp`,
  and `FOR UPDATE`; and the file re-issues `REVOKE ALL ON FUNCTION … FROM PUBLIC,
  anon, authenticated` and `GRANT EXECUTE ON FUNCTION … TO service_role`.
- **AC5** — the widened CHECK admits exactly
  `('revoked_post_grace','expired','consent_withdrawn','hourly_cap_exceeded','daily_cap_exceeded')`
  plus `IS NULL`. Assert the whole set, not just the two new members.
- **AC6** — the cap branches' SUM statements contain **no** filter on
  `attribution_shift_reason`. Grep the extracted body: between `-- Hourly cap SUM`
  and the `IF`, there is no `attribution_shift_reason` token. This is the
  mechanical encoding of the load-bearing decision.
- **AC7** — `136_…down.sql` restores the 084 body and re-adds the narrowed
  constraint with `NOT VALID`.
- **AC8** — `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/136-byok-cap-breach-audit-row.test.ts test/supabase-migrations/byok-rpc-body-markers.test.ts test/supabase-migrations/084-byok-delegation-withdrawals.test.ts --project unit`
  is green.
- **AC9** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- **AC10** — `git grep -c 'cap-exceeded raises WITHOUT' apps/web-platform/server/cost-writer.ts`
  returns 0, and the replacement comment names the post-136 behaviour.
- **AC11** — the `audit == K` learning file contains an amendment naming #7829 and
  migration 136, and no longer asserts `K` as the current invariant without
  qualification.
- **AC12** — ADR-045 carries an amendment section covering the cap branches.
- **AC13** — `git diff origin/main -- apps/web-platform/infra/sentry/` is **empty**.
  The scope boundary is mechanically verified, not asserted.
- **AC14** — `git diff origin/main -- apps/web-platform/supabase/migrations/084_byok_delegation_withdrawals.sql`
  is empty (no in-place edit of an applied migration). Note this does **not**
  cover `084_…down.sql`, which Phase 5 may deliberately change.
- **AC15L** — `bash scripts/lint-legal-registers.sh` is green (blocking since
  #7881), with PA-23's limb (c) naming the attribution shift and enumerating all
  five reasons, and limb (g) recording that cap refusal is ledgered.
- **AC16L** — DPD §2.3(w) no longer attributes the billing shift to withdrawal
  alone. Assert on the paired surfaces: the anchor text differs from the
  withdrawal-only sentence in **both** `docs/legal/data-protection-disclosure.md`
  and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`, the two
  files remain byte-identical at that anchor, and
  `apps/web-platform/lib/legal/legal-doc-shas.ts` is re-pinned (the legal-doc SHA
  gate is green).
- **AC17L** — the migration header's `RETENTION:` line does not assert a sweep
  that no migration implements, and the two contradicting register limbs (PA-13
  (f), PA-22 (f)) are either corrected in this PR or carry a tracking issue
  referenced from the header.
- **AC18L** — the side-letter fork is **resolved and recorded** in the PR body
  with the query output that resolved it — not left open. Either "no live
  arms-length pair; version bump deferred" or the bump landed.
- **AC15** — live suite green:
  `doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/byok-delegation.atomicity.tenant-isolation.test.ts --project unit`
  from `apps/web-platform`, with T5–T8 present.

### Post-merge

- **AC16** — migration 136 appears in `public._schema_migrations` on prd after the
  `#migrate` job runs. Verified by the existing release pipeline, not by an
  operator step.

## Test Scenarios

**Offline (migration-shape lint, `136-byok-cap-breach-audit-row.test.ts`)** —
follows the `084`/`121` idiom: read the `.sql`, strip line comments with
`sql.replace(/--[^\n]*/g, "")`, extract the one function with a
`CREATE OR REPLACE FUNCTION public.<fn>(`-anchored regex through the matching
dollar-quote close.

- **T1** — both cap branches INSERT before RAISE (AC3). *Fails today.*
- **T2** — the enum admits the full five-value set (AC5). *Fails today.*
- **T3** — neither cap SUM filters on `attribution_shift_reason` (AC6). This is the
  offline half of the load-bearing decision; it fails if someone later "fixes"
  double-counting by adding a filter.
- **T4** — the down migration narrows with `NOT VALID`.

**Live (`byok-delegation.atomicity.tenant-isolation.test.ts`, `TENANT_INTEGRATION_TEST=1`)**
— reuses the existing harness: synthetic `…@soleur.test` users, `grantDelegation`,
`COST_CENTS = 100`, `CAP_CENTS = 500`, `K = 5`, `expect(CAP_CENTS % COST_CENTS).toBe(0)`.

- **T5 — the discriminating test.** After the `N`-call concurrency battery,
  `audit_byok_use` rows for the delegation number `N` (not `K`), and their summed
  `token_count * unit_cost_cents` equals `N × COST_CENTS` (not `CAP_CENTS`).
  **Fails if the cap rows are excluded from the SUM, or not written at all.**
- **T6 — below / at / above the cap.** Calls 1..K−1 pass; the call landing at
  exactly `CAP_CENTS` cumulative **passes** (proves strict `>` did not drift to
  `>=`); call K+1 raises `byok_delegations:hourly_cap_exceeded` **and** leaves
  exactly one new row.
- **T7 — exactly one row per refusal.** Re-calling with the *same*
  `p_invocation_id` after a refusal raises again but adds **no** second row
  (`ON CONFLICT` idempotency). This is the anti-double-count proof.
- **T8 — the daily branch in isolation.** Pre-seed `audit_byok_use` rows at
  `ts = now() − 2h` (inside 24h, outside 1h) so the daily cap trips while the
  hourly does not, then assert the refusal writes one row carrying
  `attribution_shift_reason = 'daily_cap_exceeded'` and `founder_id` = the grantee.
- **T9 — attribution.** A cap-refused row carries `founder_id = grantee`, while the
  immediately preceding passing row carries `founder_id = grantor` and a NULL
  reason.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` was queried
and each planned path (`084_byok_delegation_withdrawals`,
`check_and_record_byok_delegation_use`, `audit_byok_use`, `cost-writer.ts`,
`084-byok-delegation-withdrawals.test.ts`, `byok-rpc-markers.json`) was matched
against every issue body with `jq --arg`. Zero matches.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-045**, do not create a new one. ADR-045's Decision §2 is titled "the
in-flight billing boundary (the load-bearing decision)" and establishes both the
insert-then-raise shape and the attribution rule for the consent/revoke/expiry
branches. Extending that boundary to the two cap branches is a change to *that*
decision's scope, not a new decision. The amendment records:

- that the cap branches were outside the boundary and why that cost the grantor
  money without a ledger entry;
- the SUM-inclusion ruling and its reasoning;
- the attribution ruling and the three named trade-offs (whole-overshoot, RLS
  visibility inversion, founder-cap contamination);
- that the `audit == K` invariant becomes `N`.

ADR-040 and ADR-041 are cross-referenced but not amended: 040's ledger substrate
and 041's three-layer model are unchanged by this fix.

### C4 views

Enumerate before concluding. This change adds **no** external human actor, **no**
external system or vendor, **no** container or data store, and **no**
actor↔surface access relationship — it changes which rows an existing SECURITY
DEFINER function writes to an existing table inside the existing boundary. The
grantor and grantee are both existing internal users of the existing web-platform
container; Anthropic is already modelled as the external system the BYOK key
addresses.

That conclusion is **not** final until it is backed by evidence, so these are
in-scope tasks, not assertions:

1. Read all three of `knowledge-base/engineering/architecture/diagrams/model.c4`,
   `views.c4`, `spec.c4` in full — not a keyword grep — and confirm the four
   categories above (external actor / external system / container-or-store /
   access relationship) are already modelled, citing what was checked.
2. Run `bash plugins/soleur/test/c4-count-parity.test.sh` green (path verified —
   it lives under `plugins/soleur/test/`, not under `apps/web-platform/test/`).
   The actor rubric does not reach the derived cardinalities embedded in
   `model.c4` edge prose, so a "no C4 impact" conclusion is only complete with
   this gate green. If any `.c4` file does change, also run
   `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`, which
   are where an undefined `view … include` reference fails (not at `tsc`).

### Sequencing

None. The decision is true the moment 136 applies.

## Observability

```yaml
liveness_signal:
  what: Sentry issue-alert rule `byok_cap_exceeded` (Rule 2), filtering
        feature=byok-delegations AND op IN {hourly-cap-exceeded, daily-cap-exceeded}
  cadence: on first_seen_event
  alert_target: unchanged — see the standing instruction in issue-alerts.tf; this
        plan deliberately does not alter routing
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (NOT modified)

error_reporting:
  destination: Sentry via `reportSilentFallback` in
        apps/web-platform/server/cost-writer.ts, plus the pino mirror
  fail_loud: false by design — the RPC call is fire-and-forget and the error is
        swallowed so a cap breach cannot break the turn. Named as a Non-Goal;
        changing it is a separate decision.

failure_modes:
  - mode: The widened CHECK is missing or wrong, so the cap-branch INSERT is
          rejected with SQLSTATE 23514 and the whole RPC raises a check-violation
          instead of the delegation marker.
    detection: cost-writer's message match falls through every
          `byok_delegations:*` branch into the else-arm.
    alert_route: Sentry, feature=byok-delegations, op=merged-rpc-failure — an
          existing, distinct slug, so this misconfiguration is visible and is not
          confusable with a genuine cap breach.
  - mode: The INSERT is written after the RAISE (unreachable), so the fix is inert
          and the ledger stays empty while everything looks shipped.
    detection: offline lint T1/AC3 (ordering-sensitive) plus live T5, which reads
          the row count rather than the code.
    alert_route: CI red on `vitest run test/supabase-migrations/…`.
  - mode: A later migration re-defines the RPC and silently drops the INSERT.
    detection: `byok-rpc-body-markers.test.ts` (source side, resolves the
          highest-numbered definer) and `.github/actions/dev-migration-drift-probe`
          (live side, `pg_get_functiondef`) — conditional on the Phase 3 marker
          decision.
    alert_route: CI red; scheduled probe emits a Sentry event.

logs:
  where: pino stdout (Better Stack) for the mirror; Sentry for the captured event.
  retention: unchanged by this plan.

discoverability_test:
  command: bash -c 'cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/136-byok-cap-breach-audit-row.test.ts test/supabase-migrations/byok-rpc-body-markers.test.ts --project unit'
  expected_output: "Test Files  2 passed"
```

## Encryption Posture

This plan introduces **no** persistent store and **no** new cross-component
connection. It writes additional rows to `public.audit_byok_use`, an existing
Supabase-Postgres table, through an existing SECURITY DEFINER RPC over the
existing application→Supabase connection.

```yaml
at_rest:
  - store: public.audit_byok_use (existing; Supabase-managed Postgres)
    mechanism: unchanged by this plan — provider-managed volume encryption on the
               existing project; this change adds no new store and no new column.
    evidence: no DDL beyond a CHECK-constraint predicate; column set unchanged.
    defends_against: loss of the underlying storage medium.
    does_not_defend: a compromised service-role credential, which can already read
               the table; and a compromised Postgres superuser.
    disclosed_as: covered by the existing BYOK/audit processing activity — see
               `## Domain Review` for the CLO's ruling on whether the Art. 30
               register entry needs amending.
    live_verification: not applicable — posture is unchanged; nothing new to verify.
in_transit:
  - connection: web-platform → Supabase Postgres (existing)
    tls: existing, unchanged
    cert_verification: unchanged
    does_not_defend: an attacker already inside the application process.
    disclosed_as: unchanged.
exception: none — no plaintext exception and no cert verification disabled.
```

## Non-Goals

- **Making a cap breach abort the run.** The RPC error is swallowed by a
  fire-and-forget caller today. **State this plainly in the PR body: the
  delegation cap enforces nothing before this PR and still enforces nothing after
  it. This is an accounting fix.** Reviewers will otherwise read "cap fix" and
  believe the brake now works. The pre-call gate (an estimate-based reserve, or a
  "last turn refused" flag read before the next call, mirroring ADR-041's Layer 1
  which *is* pre-call) must be **filed as a tracking issue in this PR**, not left
  as prose — `wg-when-deferring-a-capability-create-a`.
- **Backfill of pre-136 refused spend.** Unrecoverable: the rows were never
  written and `audit_byok_use` is WORM and append-only. State in the PR that both
  windows self-heal within the longest window (24h) with no operator action, so
  no remediation path is needed or possible. This mirrors ADR-041's 2026-09-03
  amendment, where "no backfill required" was a property of the fix rather than a
  deferral.
- **Grantor visibility of over-cap rows.** RLS is `auth.uid() = founder_id`, so
  grantee attribution leaves the grantor unable to see rows their key paid for.
  The CLO ruled this is *not* a GDPR defect — side letter §4.2 promises the
  Grantor no personal data beyond the §4.1 list, so grantor-blindness is the
  correct privacy outcome — but it is a **contractual transparency gap**: the
  Grantor is told caps are enforced automatically and has no way to observe one
  firing. A second RLS policy keyed on the delegation's grantor would close it
  cheaply. Scope call alongside Phase 5; if deferred, file it. Note this converges
  with what #7829 originally asked — the ledger fixes the record, the paging rule
  fixes the signal, and the grantor needs both.
- **Any change to Sentry routing or `fallthrough_type`.** Off limits by standing
  instruction.
- **A reconciliation flow** over the new rows. ADR-040 shipped the column as "the
  data substrate" and explicitly did not ship the flow; this plan restores the
  substrate's completeness, nothing more.
- **A guard, lint or drift-check as a deliverable.** The Phase 3 marker addition
  extends an existing guard's marker map rather than introducing a new guard, so
  no `## Guard Contract` section is required. If Phase 3 instead grows into a new
  guard, that section becomes mandatory.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `CREATE OR REPLACE` silently drops a clause from the 084 body — the exact class that bit migration 085, which lost 076's identity check. | Phase 2 requires a literal diff of the new body against 084's, and AC2/AC4 assert every surviving element (six INSERTs, `FOR UPDATE`, `SECURITY DEFINER`, the search_path pin, both REVOKE/GRANT lines). |
| The live dev body has drifted from the repo (precedent: the 2026-07-02 rogue dev migration). 136 would overwrite an un-committed change. | Phase 0.2 reads `pg_get_functiondef` and stops on divergence. |
| The daily branch is untestable from live calls alone and ships unverified. | T8 aged-seeds at `now() − 2h` per the committed learning. |
| The fix is written but unreachable (INSERT after RAISE), passing a naive "contains INSERT" test. | AC3/T1 assert *ordering* within each branch, not mere presence. |
| Rollback is impossible because the narrowed CHECK cannot validate WORM rows. | `NOT VALID` in the down migration; Phase 5 considers repairing 084's identical defect. |
| Attribution to the grantee is the wrong call. | Named explicitly with three trade-offs, routed to `data-integrity-guardian`, `user-impact-reviewer` and CPO sign-off rather than buried. |

## Domain Review

**Domains relevant:** Engineering, Legal.

### Engineering

**Status:** reviewed
**Assessment:** `data-integrity-guardian` returned six BLOCKING findings (B1–B6)
and five advisories, recorded in `## Other blocking findings` and folded through
the Load-Bearing Decision, the Attribution decision and the Rollback decision.
Verdict per decision: **Decision 1 (grantee attribution) — not ready**, blocked on
B1/B3/B6. **Decision 2 (include the rows in the SUM) — correct, keep it**, with
two of three supports rewritten. **Decision 3 (rollback) — diagnosis right, remedy
wrong**; `NOT VALID` replaced with "do not narrow". A strong-model advisor consult
independently raised B1 and the behavioural-vs-textual RED test point, both folded
into Phases 0 and 1.

### Legal

**Status:** reviewed
**Assessment:** CLO returned three BLOCKING items and one fork.
**BLOCKING-1** — Art. 30 register PA-23 must record the attribution shift (limb c,
all five reasons) and that cap refusal is ledgered (limb g); limb (g)(5) currently
asserts cap enforcement as a TOM with no record of it firing.
**BLOCKING-2** — retention for `audit_byok_use` is three-way contradictory
(PA-13 (f) 12 months, PA-22 (f) 90 days, PA-23 (f) and DPD §2.3(w) 7 years) and no
`pg_cron` sweep on the table exists in any migration, so all three are unevidenced.
Resolve before writing 136's header.
**BLOCKING-3** — DPD §2.3(w) becomes affirmatively false: it attributes the billing
shift to withdrawal alone (it already understates today at three triggers; 136
makes five). Paired edit across canonical + mirror, then re-pin the SHA.
**Fork** — the side-letter version bump is gated on whether a live arms-length
grantor↔grantee pair exists; resolved mechanically in Phase 0.5, not asked of the
operator. **Advisory** — ADR-045 does not actually pre-sanction the cap-breach
extension (a cap is a budget the counterparty sets, not an authority the grantee
outran); record it as a real extension. Also: render `attribution_shift_reason`
alongside cost in the audit viewer and DSAR bundle (Art. 5(1)(d) accuracy).
Art. 22 not engaged; DSAR allowlist and Art. 17 carve-out need no change.
`scripts/lint-legal-registers.sh` is blocking since #7881.

### Product/UX Gate

**Not applicable.** The mechanical UI-surface scan over `## Files to Create` and
`## Files to Edit` matches no `components/**/*.tsx`, `app/**/page.tsx` or
`app/**/layout.tsx` path. `byok-delegation-ui-resolver.ts` is a server resolver,
not a UI surface — it renders no new screen and changes no flow; the B6 fix
corrects figures an existing screen already displays. Tier: NONE.
