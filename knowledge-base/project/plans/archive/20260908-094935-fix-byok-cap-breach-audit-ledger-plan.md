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

## Enhancement Summary

**Deepened on:** 2026-09-07. Seven review agents plus a strong-model advisor consult.

This plan was rewritten after review rather than amended. The first draft absorbed
each finding as a correction layered on top of the superseded prescription, and
ended up contradicting itself at six anchors — `code-simplicity-reviewer`,
`architecture-strategist`, `data-migration-expert` and `test-design-reviewer` all
independently flagged that an implementer following the checklists would ship the
*rejected* remedy. Corrections are now applied to the checklists, not narrated
above them.

### What review changed

1. **The architectural fork is resolved, in the plan.** Deferring it to `/work`
   was BLOCKING. The mechanism is **return a refusal reason instead of raising**.
2. **The scope is split into four PRs.** This is no longer one change.
3. **Three factual claims of mine were wrong and are corrected**: the RLS policy,
   the "sums it bare" reading of ADR-041, and "pre-existing for the siblings".
4. **`NOT VALID` is struck everywhere.** It re-breaks the Art. 17 cascade.
5. **The B3 arm is now decided** (fix the readers, not the writer) on evidence.

## The core finding

`public.check_and_record_byok_delegation_use` refuses a delegated turn on five
branches. Three append an `audit_byok_use` row before raising; the two cap
branches raise without appending. The function is a **post-hoc recorder, not a
pre-flight gate** — `persistTurnCost` calls it from `onResult` with the turn's
actual token counts, so the provider has already charged the grantor's key.

**But the fix is not "add the two missing INSERTs", because the three existing
ones do not work either.**

In plpgsql an unhandled `RAISE EXCEPTION` aborts the current (sub)transaction and
discards every data modification the function made. The function has **one**
`BEGIN`, **one** `END;`, **no `EXCEPTION WHEN` handler anywhere**, and six
unhandled `RAISE EXCEPTION`s; PostgREST runs the RPC as one transaction. The
INSERT that executes immediately before each RAISE is rolled back by that RAISE.

The repo already states this for a sibling function —
`048_precheck_jwt_mint_sqlstate.sql`: *"RAISE EXCEPTION rolls back the function's
effects (plpgsql atomic-volatile semantics)."* The same file family draws the
opposite conclusion here. **"Accounting is sacred" was stated but never in force
on any refusal branch.**

Corroboration: `grep -rn attribution_shift_reason apps/web-platform/test/` returns
exactly one live-data assertion — `expect(auditRows![0].attribution_shift_reason,
"normal attribution").toBeNull()` in `byok-delegations.tenant-isolation.test.ts`,
the **pass** path. No test anywhere asserts a refusal row persists.

**Consequences.** The defect is five branches, not two. ADR-045 §2 documents an
in-flight billing boundary the code cannot produce. And the obvious fix is inert:
adding INSERT-before-RAISE to the cap branches reproduces the shape that does not
work, and would ship green against a regex lint asserting textual ordering.

### The precise defect statement (for the PR body)

Not *"the window never advances"* — a smaller later turn can still fall under the
cap and pass. The exact defect is: **every refused turn's real spend is dropped
from the ledger permanently, so the delegation cap is enforced against a
systematic under-count**, and the refusal itself changes nothing because the
caller is fire-and-forget.

**Scope boundary — binding.** `apps/web-platform/infra/sentry/issue-alerts.tf` is
off limits. The comment block above `resource "sentry_alert" "byok_cap_exceeded"`
is the authority — it records that #7829 stays open against the enforcement gap,
and that flipping the fallthrough there would page on every breach without fixing
the missing ledger row. Do not flip `fallthrough_type`, do not touch the rule, and
do not restate that comment elsewhere.

## Decision 1 — the mechanism: return a refusal reason (was the deferred fork)

**Chosen. `RETURNS void` becomes a returned refusal reason; the function stops
signalling refusal by aborting its own transaction.**

`architecture-strategist` established the choice is forced, not open, and supplied
the decisive precedent the first draft missed: **the sibling cap RPC in the same
family already uses this shape.** `121_byok_cap_trip_from_found.sql` declares
`record_byok_use_and_check_cap(...) RETURNS TABLE(cumulative_cents int,
kill_tripped boolean)`, and ADR-041 Layer 1 enforces the founder cap by
*returning* `kill_tripped` for the caller to act on. This is convergence on the
established in-family shape, not a novel design.

**It preserves ADR-040 Decision #1 and strictly strengthens it.** `FOR UPDATE`,
both window SUMs and the audit INSERT stay in one transaction under one row lock;
only the refusal *signal* changes. Because the refusal row now commits inside the
lock, a concurrent caller's SUM sees it — which is exactly the TOCTOU close D1
exists for and which today's code silently fails to deliver.

**ADR-041's cost note does not veto this, and the first draft misread it.** At the
`Fork decision (CTO, 2026-07-03 — #5767 vs #5919)` anchor, rejected alternative
(C) was a return-type change *"for a guard the entry gate already provides"* — it
was rejected for **zero marginal benefit**, on a **different function**. Here the
benefit is the entire purpose of the PR.

**Real costs, named rather than hand-waved:** `DROP` + `CREATE` (a return-type
change cannot use `CREATE OR REPLACE`) on a live billing RPC — verify no view,
trigger or default depends on it; the runner uses `psql --single-transaction`, so
it is atomic. PostgREST schema-cache reload. `cost-writer.ts` moves from
`.then(({ error }) => …)` message-substring matching to reading `data`. The
ADR-040 D10 error classes get constructed from a typed discriminator rather than
`message.includes("byok_delegations:hourly_cap_exceeded")`.

**Side benefit worth recording:** coupling a TypeScript error hierarchy to a
plpgsql RAISE *message substring* is the leaky abstraction underneath this whole
bug — the refusal had no typed contract, so its only carrier was an exception, and
an exception is precisely what destroys the ledger row. This dissolves it.

### Rejected alternatives (on the record)

**Autonomous transaction (`dblink` / `pg_background`) — architecturally
disqualifying, four grounds.** (a) It breaks ADR-040 D1: the audit write executes
on a separate connection outside the `FOR UPDATE` lock, with non-deterministic
ordering against a concurrent caller's SUM — the split-write shape D1 exists to
reject. (b) **Unrepairable WORM corruption**: an autonomous write cannot be undone
when the outer transaction aborts for an unrelated reason (including a `23514` on
the widened enum), and `audit_byok_use` is append-only with the Art. 17 carve-out
narrowed by mig 066 to `founder_id → NULL` only. There is no repair path. (c)
Undeclared infrastructure: `grep -rn "CREATE EXTENSION" apps/web-platform/supabase/migrations/`
returns only `pg_cron`; adding an extension to a managed Supabase project needs
its own ADR, and a connection string inside a `SECURITY DEFINER` body is a new
in-database credential surface. (d) It falsifies this plan's own `## Encryption
Posture` and `### C4 views` conclusions, which are true only under the other
candidates.

**Caller-side record — rejected.** Loses D1's single-transaction atomicity, and
`persistTurnCost` is fire-and-forget: a process exit between RPC return and caller
write loses the row. A lost write on the billing ledger is the class being fixed.

## Decision 2 — the window SUM includes the new rows

**The newly-written cap rows are NOT excluded from the SUM that refused them.**
`data-integrity-guardian` attacked this directly and returned *"correct, keep it —
exclusion is never right here."* It is the one decision that survived review intact.

1. The cost is real and already charged. Excluding it means the ledger records
   money the cap arithmetic then pretends did not move — the same defect as writing
   no row, wearing an audit row as a costume.
2. Exclusion creates a **cap leak**: `v_hourly_spent` freezes at its last in-cap
   value and every turn small enough to fit under `cap − frozen` passes forever.
3. **Corrected support (the first draft was wrong):** double-counting is *not*
   prevented by `UNIQUE(invocation_id)` + `ON CONFLICT DO NOTHING`. `invocationId`
   is `randomUUID()` minted **inside** `persistTurnCost`, so two invocations for
   one provider call mint two uuids and the conflict never fires. It dedupes only a
   replay of an already-minted payload. **Open item this PR must close:** derive
   the key (conversation + turn index) or accept double-counting on the record.
4. **Corrected support:** a permanent wedge is bounded but not benign — because the
   run does not abort, each refused turn extends the over-cap state by a fresh
   window from its own `ts`. Rolling, but fed by the condition it refuses.

## Decision 3 — B3, the unit semantics: fix the readers, not the writer

**Confirmed, and larger than the first draft said.** In `cost-writer.ts`,
`const costDelta = … input.totalCostUsd` then `const unitCostCents =
Math.round(costDelta * 100)` — the column holds the **whole turn's cost in
cents**. Yet `084` computes `v_this_cost int := p_token_count * p_unit_cost_cents`
and both windows `SUM(au.token_count * au.unit_cost_cents)`.

**The arm is decided by evidence, not preference.** Two *production* consumers
already read the column bare, and correctly:

- `app/api/dashboard/today/[id]/cost/route.ts` — `.select("unit_cost_cents")` then
  a bare reduce.
- `server/inngest/functions/agent-on-spawn-requested.ts` — the
  `turn-${n}-precheck-cost-ceiling` step, bare reduce against
  `PER_SPAWN_COST_CEILING_CENTS = 260`.

That settles it: **the product readers are wrong, the writer is right.** Fixing
the writer instead would silently divide the fail-closed, user-facing per-spawn
ceiling by `token_count` so it never trips.

**Correction to my own first draft:** I wrote that "ADR-041 reads the column the
same way, summing it bare". Wrong — `061:128` and `121:93` both sum the *product*.
The corrected reading makes B3 **founder-wide, not delegation-scoped**: ADR-041
Layer 1's kill switch has been arithmetically wrong by a factor of `token_count`
for every BYOK user, solo and delegated.

**Therefore B3 leaves this PR and lands first, alone** — see `## PR sequencing`.

**Free decisive probe** (read-only, prd) that `data-migration-expert` supplied —
if B3 is right, Layer 1 should be tripping constantly today:

```sql
SELECT count(*) FILTER (WHERE runtime_paused_at IS NOT NULL) AS paused, count(*) AS total
FROM public.users;

SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY unit_cost_cents) AS median_cents,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY token_count)     AS median_tokens,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY token_count * unit_cost_cents) AS median_product
FROM public.audit_byok_use WHERE ts > now() - interval '30 days';
```

## Decision 4 — attribution: grantee, with the framing corrected

`founder_id = p_caller_user_id`, `attribution_shift_reason` = the cap reason.
ADR-045: *"cost follows the party who continued past the boundary"*; ADR-040
defines the column as marking rows "billed to the grantor's key but … shifted to
the caller".

**Correction — "pre-existing for the siblings" was false.** The first draft
defended two trade-offs by calling them inherited. Under this plan's own premise
**no sibling refusal row has ever persisted**, so these are *introduced* by this
change, not inherited, and each was understated by its entire magnitude:

- **Founder-cap contamination is a hard stop, not a nudge.** `121`'s SUM groups by
  `founder_id` with **no `delegation_id` filter** and flips
  `users.runtime_paused_at`. A grantee-attributed cap row enters the grantee's own
  Layer-1 accumulator against `runtime_cost_cap_cents DEFAULT 2000`. Net effect:
  **a grantee who exceeds someone else's cap has their own agent runtime paused**
  and must manually Resume. **This PR must either add `AND delegation_id IS NULL`
  to `121`'s SUM (defensible on its own terms — the personal cap governs the
  user's own key) or model the lockout as an accepted, tested outcome.** It cannot
  be left unstated.
- **RLS: my policy claim was stale, and it propagated into the CLO ruling.**
  `059_workspace_keyed_rls_sweep.sql` executes `DROP POLICY IF EXISTS
  audit_byok_use_owner_select` and creates `audit_byok_use_workspace_member_select
  … USING (public.is_workspace_member(workspace_id, auth.uid()))`. Verified
  directly (059 at the DROP and the CREATE). The live policy is
  workspace-membership-keyed, and delegations are workspace-scoped on both sides,
  so **the grantor is not blind at all.** The CLO's ruling — "grantor-blindness is
  the correct privacy outcome per side letter §4.2" — was reasoning about a policy
  that has not existed since mig 059, and the real question (workspace-wide read of
  a co-member's BYOK cost rows) has not been asked. **Re-run the CLO question.**
  Note `data-migration-expert` cited 037's policy as live and is wrong on that
  point; two other reviewers and my own grep agree with 059.

**Per-surface, the effect differs — state it per surface, not once:**

| Surface | Client | Effect of grantee attribution |
|---|---|---|
| `server/byok-delegation-ui-resolver.ts` (Funded pane) | `createServiceClient()`, filters `delegation_id` | RLS bypassed — rows **stay visible** to the grantor |
| `app/(dashboard)/dashboard/audit/page.tsx` | cookie client, `.eq("founder_id", user.id)` | rows **disappear** from the grantor's view |
| DSAR Art. 15 (`dsar-export-allowlist.ts`, `ownerField: "founder_id"`) | — | rows move to the **grantee's** export; grantor's becomes incomplete |

**Whole-overshoot attribution** stays an accepted trade-off (a 50c turn crossing a
99c/100c boundary debits the grantee all 50c) — splitting one invocation across
two `founder_id`s is forbidden by `UNIQUE(invocation_id)`.

**Corrected magnitude:** because the run does not abort, it is not one turn — it is
every turn from the crossing to the end of the run, plus the following window
(24h on the daily branch, not 1h). Either state that, or make the refusal abort
the run.

**Also required (was advisory, now in scope):** `p_caller_user_id` is never
validated against `v_row.grantee_user_id` — the consent re-gate reads withdrawals
by one and every INSERT writes the other. Once `founder_id` is a *billing*
assertion that pauses a user's runtime and enters their DSAR export, add
`IF p_caller_user_id IS DISTINCT FROM v_row.grantee_user_id THEN RAISE`.

## Decision 5 — rollback: the down migration does not narrow the CHECK

**`NOT VALID` was my remedy and it is wrong.** It skips the initial scan but still
enforces on subsequent **UPDATEs**, and `065_art17_cascade_deadlock_repair.sql`
makes `founder_id` `ON DELETE SET NULL`, so an account delete issues `UPDATE … SET
founder_id = NULL`. A cap-reason row plus a narrowed constraint aborts the cascade
and fails `auth.admin.deleteUser` — the exact incident 065/066 repaired.

**`137.down.sql` leaves the CHECK widened.** ADR-040 set this precedent for the
sibling constraint on the same table ("Down migration intentionally KEEPS this
constraint"). **`NOT VALID` appears nowhere in this plan's checklists.**

Two further reversibility facts, both previously unaddressed:

- **`.down.sql` is never executed** — `run-migrations.sh` skips it (`*.down.sql)
  continue ;;`) and it is not content-sha tracked. AC7/T4 asserting only its *text*
  do not evidence Property 5. **AC-DOWN below executes it against dev.**
- **Rolling back the code does not roll back its effects.** Cap rows written before
  rollback stay in both windows for up to 24h, and any `runtime_paused_at` stamped
  by a contaminated Layer-1 SUM clears only via the operator Resume route.

**`084_byok_delegation_withdrawals.down.sql` is already broken in production** —
any withdrawal that has ever fired makes its step-3 narrow unrunnable, and its
header remedy ("null those rows first in an operator step") is impossible because
the WORM trigger rejects that UPDATE (mig 066's carve-out is `founder_id → NULL`
with all other columns unchanged). Strictly it is not *impossible* —
`059_workspace_keyed_rls_sweep.sql` shows the `DISABLE TRIGGER` escape hatch — but
mig 037's header calls a trigger drop *"itself a forensic signal"*, so the honest
statement is that **the documented remedy requires disarming the WORM guarantee on
a billing ledger.** Fixed in PR-3 by leaving the enum widened.

## PR sequencing — four PRs, not one

Three reviewers independently reached this. The plan carried a migration, a
return-type conversion, a repo-wide billing-arithmetic defect, a live resolver bug
on another surface, an Art. 30 amendment, a paired legal edit plus SHA re-pin, a
retention contradiction predating the issue, a side-letter fork, a test-invariant
inversion, a learning amendment and ADR work.

| PR | Content | Why separate |
|---|---|---|
| **PR-0** (spike, no merge) | The Phase 0 probes: live-body `pg_get_functiondef` drift diff, the live CHECK definition, and the two B3 distribution queries. Output is a paragraph appended here. | Everything downstream is unwritable until B3's arm is confirmed against real data. |
| **PR-1** (ship first, independent) | `server/byok-delegation-ui-resolver.ts` — the non-existent `cost_cents` column and the discarded PostgREST errors. | ~15 lines, no migration, no fork dependency, and it is a **precondition** for the attribution shift: without it the charged party has no working spend surface at all. |
| **PR-2** (lands before PR-3) | B3 + B4: unit semantics across `084`, `061`, `121`, and an ADR-041 amendment. | Founder-wide cap-arithmetic decision. It changes what every existing cap test *means* and needs its own migration and test matrix. |
| **PR-3** (#7829 proper) | Migration 137 as the return-status conversion; A5 caller-id guard; A6 index; A8 column comment; the `084.down.sql` repair; **new ADR-207**; the `K → N` test inversion; the learning amendment; `cost-writer.ts`; PA-23 limbs (c)/(g). | The actual issue. |
| **PR-4** (parallel, lands after PR-3) | DPD §2.3(w) paired edit + SHA re-pin + the retention reconciliation. | Pre-existing corpus defects with an independent trigger; a blocking `lint-legal-registers.sh` should not red-gate a SQL migration. Same shape as #7881. |

**Cut from this plan entirely** (file, do not fold): the side-letter version-bump
fork — pre-commit to **defer**; a bump fail-closes every stale acceptance, and if a
live arms-length pair exists that is a reason for its own PR. The full read of all
three `.c4` files — the enumeration below is sound and
`bash plugins/soleur/test/c4-count-parity.test.sh` is the one gate that adds
information.

## Files

### PR-1

| Path | Change |
|---|---|
| `apps/web-platform/server/byok-delegation-ui-resolver.ts` | `cost_cents` does not exist (`037` declares `token_count`, `unit_cost_cents`) → 42703 on every read, `error` destructured away, so `todaySpentCents`/`mtdSpentCents`/`capRemainingCents` render 0/0/full-cap for everyone, always. **Eight** unmirrored reads, not the two first identified — also two `error`-bound-then-discarded sites and four that never bind `error`. Route each through `reportSilentFallback` (`pg_code` then discriminates 42703 from 42501). Add a degraded UI state, not only a Sentry mirror. **The replacement expression must be derived from the RPC's window expression**, not a bare rename — otherwise the grantor's figure disagrees with the cap that refused the turn. |

### PR-3

| Path | Change |
|---|---|
| `apps/web-platform/supabase/migrations/137_byok_cap_breach_audit_row.sql` | **new** — widen the CHECK; `DROP` + `CREATE` the RPC returning a refusal reason; all five refusal branches INSERT and return. |
| `apps/web-platform/supabase/migrations/137_byok_cap_breach_audit_row.down.sql` | **new** — restore the 084 body; **leave the CHECK widened**. |
| `apps/web-platform/test/supabase-migrations/137-byok-cap-breach-audit-row.test.ts` | **new** — offline shape tripwire. |
| `apps/web-platform/server/cost-writer.ts` | Read `data` instead of matching `error.message`; construct the ADR-040 D10 error classes from the typed discriminator. Rewrite the comment `cap-exceeded raises WITHOUT a row.` **Add the missing `consent_withdrawn` branch** — there is none today, so consent-withdrawal refusals already fall into the else-arm as `op=merged-rpc-failure`. |
| `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts` | Partition the invariant (below), add cases, re-anchor the line-number citations. |
| `apps/web-platform/supabase/migrations/121_byok_cap_trip_from_found.sql` *(or an accepted-outcome model)* | Add `AND delegation_id IS NULL` to the founder SUM, or document the grantee lockout as tested. |
| `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json` | The three pinned markers include the RAISE strings; under the return-status shape they survive only if the returned reason literals are spelled identically. **Phase 3 asserted this constraint without noticing it is one.** Reconcile, and add an INSERT-shaped marker. |
| `apps/web-platform/supabase/migrations/084_byok_delegation_withdrawals.down.sql` | Repair the unrunnable narrow. Safe: `.down.sql` is skipped by the runner and not sha-tracked. |
| `knowledge-base/engineering/architecture/decisions/ADR-207-*.md` | **new** — see below. |
| `knowledge-base/project/learnings/best-practices/2026-07-03-live-cap-rpc-test-aged-seed-daily-isolation-and-audit-equals-K.md` | Amend Key Insight #2. |
| `knowledge-base/legal/article-30-register.md` | PA-23 limbs (c) and (g). |
| `apps/web-platform/supabase/migrations/066_*.sql` comment | `founder_id` "Owner of the BYOK invocation" plus the "aggregate on `workspace_id`" guidance — both wrong for cap rows, where `workspace_id` is the grantor's and `founder_id` the grantee's. |

**Not edited:** `apps/web-platform/infra/sentry/issue-alerts.tf` (standing
instruction); `084_byok_delegation_withdrawals.sql` (forward-only).

## Architecture Decision (ADR/C4)

**New ADR-207** (was drafted here as ADR-205, when ADR-204 was the ceiling on
`origin/main`. Re-derived at authoring time with `max + 1` per `/ship`'s collision
gate, which is authoritative: `origin/main` now tops out at **ADR-206**, so this
is **ADR-207**. ADR-205 is left as an unfilled hole — "next free" is `max + 1`,
never the lowest unused ordinal. Re-verify again before merge).

Amending ADR-045 is insufficient. Under the chosen mechanism the change
**corrects a false factual claim** in ADR-045 §2 (*"the turn raises and the audit
row is written with `founder_id = grantee`"* — it is not written), **amends**
ADR-040 D1 (the refusal signal moves from exception to return value) and D10 (the
error taxonomy sourced from a return value, not a message substring), and
**overturns the disposition** of ADR-041's rejected alternative (C). Repo
precedent is decisive: ADR-045 is itself a *sibling* to ADR-040 for exactly this
shape — a new decision about the same RPC — not an amendment to it.

ADR-207 records: the plpgsql rollback finding; the return-status decision with the
mig-121 precedent; the two rejected alternatives with the reasons above; the
SUM-inclusion ruling; the attribution ruling with all four corrected trade-offs;
and that the `audit == K` invariant becomes a partition.

### C4 views

No external human actor, external system, container/data store, or actor↔surface
access relationship changes — the grantor and grantee are existing internal users
of the existing web-platform container, and Anthropic is already modelled as the
external system the BYOK key addresses. Backed by
`bash plugins/soleur/test/c4-count-parity.test.sh` green (the actor rubric does not
reach the derived cardinalities in `model.c4` edge prose). If any `.c4` changes,
also run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

## User-Brand Impact

*Rewritten role-by-role per `user-impact-reviewer`, and stating what each party
experiences when the change lands **correctly** — the first draft described only
the lands-broken and pre-fix states.*

**Grantor.** Today: a Funded pane showing `$0.00` / full-cap-remaining for every
delegation, permanently (PR-1). After PR-3: real figures, and over-cap rows still
visible in the Funded pane (service client) but absent from `/dashboard/audit`
(`founder_id`-filtered) and from their Art. 15 export. **There is still no path by
which they learn a cap was breached** — see the Non-Goal.

**Grantee.** Becomes the billed party mid-run, silently — no banner state exists
for "your last turn was refused" or "you are now the billed party".
`delegation-banner.tsx`'s enum is acceptance-only. And unless `121`'s SUM is
filtered, **their own agent runtime is paused** by a cap that is not theirs, under
a `failure_reason` naming a cap they did not exceed. This is a second single-user
incident that this change introduces.

**Workspace co-member.** `workspace_cost_aggregate` groups `a.founder_id AS
user_id` and is readable workspace-wide under the mig-059 policy, so every
co-member sees the grantee's cost line inflated by spend the grantee never funded.

**Solo BYOK founder.** Unaffected by PR-3; materially affected by PR-2 (B3 is
founder-wide).

**DSAR requester.** The grantee's bundle gains the over-cap spend; the grantor's
loses rows their key paid for. `attribution_shift_reason` travels (`.select("*")`)
but is not rendered — an export asserting a cost the Anthropic invoice contradicts
(Art. 5(1)(d)).

**If this leaks, the user's money is exposed via:** the grantor's key charged past
the ceiling they set, the overage absent from the ledger and every rollup, silent
by construction because the caller swallows the RPC error.

**Brand-survival threshold: single-user incident.** Matches ADR-040's stated
threshold for this surface ("an unauthorized invoice"). `requires_cpo_signoff:
true`. **Findings 3, 5 and 6 mean the Engineering and Legal domain reviews were
conducted against facts that do not hold; both must be re-run after PR-0.**

## Test Scenarios

**Offline (tripwire only, explicitly not the proof).** Read the `.sql`, strip line
comments, extract the one function with a `CREATE`-anchored regex.

- **T1** every refusal branch INSERTs and returns; no branch raises on a refusal.
- **T2** the enum admits the full five-value set.
- **T3** neither cap SUM filters on `attribution_shift_reason`. **Anchor on
  `INTO v_hourly_spent` / `INTO v_daily_spent`, not on the `-- Hourly cap SUM`
  comment** — the mandated comment-strip deletes that anchor, so T3 as first
  written could not run.
- **T4** the down migration does **not** narrow the CHECK.

**Live (`TENANT_INTEGRATION_TEST=1`).**

- **T5 — the discriminating test, corrected.** The first draft's `N` /
  `N × COST_CENTS` assertions are **forced by the fixture** (N calls, one row each,
  fixed cost) and hold even against an RPC that ignored caps entirely. The
  invariant does not become `N` — it **partitions**: `rows WHERE
  attribution_shift_reason IS NULL === K` summing to `CAP_CENTS` (the original
  no-double-spend/TOCTOU proof, preserved), plus `rows WHERE reason = '…' === N−K`.
  Total `=== N` is a derived consequence, not the load-bearing assertion.
- **T5b — the actual include-vs-exclude discriminator.** Uniform per-call cost
  cannot separate include from exclude: every post-breach call breaches either way.
  Requires **heterogeneous cost** — pass `K−1` calls (400), one at `2×COST` which
  trips and writes a 200 row, then one at `COST`. Include → `400+200+100 > 500`,
  refused. Exclude → `400+100 = 500`, **admitted**. That single refusal is the whole
  decision. Needs `recordUse` to take per-call cost arguments, which it hardcodes.
- **T6** below / at / above: the call landing at exactly `CAP_CENTS` **passes**
  (proves strict `>` did not drift to `>=`), with `cap % cost === 0`.
- **T7 — renamed and given a positive control.** It is *not* "the anti-double-count
  proof": `invocationId` is `randomUUID()` per call so the production double-count
  is unreachable by `ON CONFLICT`. As first written it also **passes green against
  the broken state** (no row either time), violating the RED gate. Assert
  `count === 1` after the first refusal, *then* `count === 1` after the duplicate,
  *and* that the second call still refused. Rename to "`ON CONFLICT` dedupes an
  identical replayed payload".
- **T8** the daily branch in isolation via `ts = now() − 2h` aged seed (inside 24h,
  outside 1h; `ts` is client-insertable because the WORM triggers are `BEFORE
  UPDATE/DELETE` only). Scope the assertion with `.eq("attribution_shift_reason",
  "daily_cap_exceeded")` — the fixture holds 4 seed + 1 pass + 1 refusal.
- **T9** attribution: the refused row carries `founder_id = grantee`; the preceding
  passing row carries the grantor and a NULL reason. Identify both by returned
  invocation id, not by `ts` ordering.
- **T10 — production-shaped payload (PR-2, and the gap that hid B3).** The fixture
  encodes `COST_CENTS = 100; // p_token_count=10 × p_unit_cost_cents=10` — a
  **per-token rate**, the inverse of what production writes. **No test has ever
  crossed the `cost-writer` → RPC unit boundary**, which is why B3 survived. Call
  with `p_token_count = 8000, p_unit_cost_cents = 3` against a realistic cap and
  assert the branch taken.

New scenarios must inherit the `willFail` → `diagBanner(pg_get_functiondef)`
self-diagnosis pattern; `auditRowsFor` must select `founder_id`,
`attribution_shift_reason` and `invocation_id`.

## Acceptance Criteria (PR-3)

- **AC1** the migration pair exists, both wrapped `BEGIN;`/`COMMIT;`.
- **AC2** the function returns a refusal reason and **no refusal branch raises**;
  every refusal path INSERTs before returning. *(Demoted to tripwire — presence,
  not reachability. Only the live tests prove the row exists.)*
- **AC3** the body retains `SECURITY DEFINER`, `SET search_path = public, pg_temp`
  (`cq-pg-security-definer-search-path-pin-pg-temp`), `FOR UPDATE`, and re-issues
  `REVOKE ALL … FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE … TO service_role`.
- **AC4** the CHECK admits exactly `('revoked_post_grace','expired',
  'consent_withdrawn','hourly_cap_exceeded','daily_cap_exceeded')` plus NULL.
  Underscores — **not** the hyphenated Sentry `op` slugs. Mig 064 establishes that
  only `cross-tenant` is hyphenated. Do not harmonise.
- **AC5** neither cap SUM filters on `attribution_shift_reason` (T3's anchor).
- **AC6** `137.down.sql` restores the 084 body and **contains no `NOT VALID`** and
  no narrowed CHECK.
- **AC-DOWN** `137.down.sql` is **executed** against dev and the resulting
  `pg_get_functiondef` matches the 084 body. Text assertions do not evidence
  rollback on a billing ledger at this threshold.
- **AC7** offline + `./node_modules/.bin/tsc --noEmit` green from `apps/web-platform`.
- **AC8** live suite green with T5, T5b, T6–T9 present.
- **AC9** `git grep -c 'cap-exceeded raises WITHOUT' apps/web-platform/server/cost-writer.ts`
  returns 0; a `consent_withdrawn` branch exists.
- **AC10** the `audit == K` learning carries an amendment naming #7829 and 137.
- **AC11** `ADR-207-*.md` exists; the ordinal is re-verified against `origin/main`.
- **AC12** `git diff origin/main -- apps/web-platform/infra/sentry/` is empty
  **except** a comment-only correction: the tf comment's *"So on a cap breach no
  audit row is written… the window numerator does not advance either"* becomes
  false when 137 lands. A comment fix is not a routing change and does not violate
  the standing instruction; leaving a known-false operator-facing claim pinned
  green is the `2026-07-19-false-comment-correction` class.
- **AC13** `git diff origin/main -- .../084_byok_delegation_withdrawals.sql` is
  empty (the `.down.sql` is deliberately changed).
- **AC14** `bash scripts/lint-legal-registers.sh` green with PA-23 (c)/(g) amended.
- **AC15** `git grep audit_byok_use_owner_select` has no live-policy claims left —
  it currently hits a stale comment in `app/(dashboard)/dashboard/audit/page.tsx`.

## Observability

```yaml
liveness_signal:
  what: Sentry issue-stream entry for `byok_cap_exceeded` (Rule 2), filtering
        feature=byok-delegations AND op IN {hourly-cap-exceeded, daily-cap-exceeded}
  cadence: first_seen_event only — no reappeared/regression, so one row for all time
  alert_target: none. `fallthrough_type = "NoOne"` and the project has no ownership
        rule (measured 2026-09-06, recorded in issue-alerts.tf), so `issue_owners`
        resolves to nobody. This is a PULL surface, not a delivery. Declaring it as
        a delivered alert would be false; the routing fix is out of scope by
        standing instruction and is filed instead.
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (NOT modified)

error_reporting:
  destination: Sentry via `reportSilentFallback` (server/cost-writer.ts) plus the
        pino mirror -> Better Stack (observability layer 2)
  fail_loud: false by design — the RPC call is fire-and-forget so a cap breach
        cannot break the turn. Named as a Non-Goal.

failure_modes:
  - mode: 137 applies but writes no row (the RAISE-rollback shape, or a regression
          that keeps the signal and drops the INSERT). THE HIGHEST-PROBABILITY
          POST-MERGE STATE, and today it is INVISIBLE in production — the Sentry
          event and the pino line are byte-identical whether or not the row landed,
          because both derive from the refusal, which fires either way.
    detection: REQUIRED NEW SIGNAL — in cost-writer.ts's cap branches, read back
          `select id from audit_byok_use where invocation_id = <invocationId>` and
          pass `tags: { ledger_row_written: "true"|"false" }` to
          reportSilentFallback. Turns an indistinguishable event into a decisive
          one with no issue-alerts.tf change.
    alert_route: Sentry tag + pino mirror -> Better Stack (layer 2)
  - mode: The widened CHECK is missing/wrong -> SQLSTATE 23514 -> the RPC fails and
          cost-writer falls to the else-arm.
    detection: `op=merged-rpc-failure` with `pg_code` discriminating 23514 from
          22003 (overflow) and 42703 (column drift). NOTE the slug is NOT unique —
          consent-withdrawal refusals already land there because cost-writer has no
          `consent_withdrawn` branch; PR-3 adds it, which restores the distinctness
          this detection assumes.
    alert_route: Sentry, feature=byok-delegations (layer 2 pino mirror)
  - mode: A later migration redefines the RPC and drops the INSERT.
    detection: byok-rpc-body-markers.test.ts (source, highest-numbered definer) and
          .github/actions/dev-migration-drift-probe (live pg_get_functiondef).
    alert_route: CI red; scheduled probe emits a Sentry event. LIMITATION: the live
          probe is dev-only (`doppler-config: dev_scheduled`), so a prd-side
          regression — including 137.down.sql, which by design restores the
          defective body — produces no signal. Filed.

logs:
  where: pino stdout -> Vector -> Better Stack (level >= 40); Sentry for the event.
  retention: unchanged by this plan.

discoverability_test:
  # CORRECTED at review. The originally-cited
  # `apps/web-platform/scripts/probe-byok-cap-ledger.sh` did not exist anywhere
  # in the repo — the whole string occurred only on this line, so Preflight
  # Check 10 would have executed it and got "No such file or directory", with a
  # credentials waiver reading as the reason it could not be verified. That is
  # the swap-live-verification-for-prose shape the gate treats as waiver abuse.
  command: psql "$DATABASE_URL_POOLER" -f apps/web-platform/supabase/verify/137_byok_cap_breach_audit_row.sql
  expected_output: "every row returns bad=0 (8 checks: return type, no cap RAISE,
        five-value CHECK, corrected window arithmetic, founder filter, and the
        three privilege assertions)"
  # INLINE, deliberately. Check 10 reads this sub-field with a flat awk over the
  # KEY LINE, so a multi-line value extracts as a truncated fragment and preflight
  # then prints that half-sentence to the operator as "the declared scope" — which
  # defeats the reviewability the SKIP-DECLARED terminal exists for. Measured: the
  # previous wrapped form extracted as `"Doppler soleur/<env> DATABASE_URL_POOLER. This is the`.
  credentials_required: "Doppler soleur/<env> DATABASE_URL_POOLER — the probe is psql against the deployed catalogue, and the RPC is service_role-only so no unauthenticated caller can read the function definition, the CHECK, or the window arithmetic it asserts. Same artifact the release pipeline's verify-migrations job runs post-apply, so the on-demand probe and the CI gate cannot drift apart."
```

**Why the discoverability_test changed.** The first draft declared a `vitest` run.
`observability-coverage-reviewer` *measured* it against Check 10's sandbox and it
dies before any test executes: `EROFS: read-only file system, open
'…/node_modules/.vite-temp/vitest.config.ts.timestamp-….mjs'` — Vite bundles the
config into a temp file inside the repo, which Check 10 binds read-only. It also
ran T1–T4, the textual lint this plan explicitly disqualifies as proof. A plan
cannot declare as its discoverability proof the artifact it elsewhere calls
not-the-proof.

## Encryption Posture

No persistent store and no new cross-component connection: additional rows to
`public.audit_byok_use`, an existing Supabase-Postgres table, via an existing
SECURITY DEFINER RPC over the existing application→Supabase connection.

```yaml
at_rest:
  - store: public.audit_byok_use (existing, Supabase-managed Postgres)
    mechanism: unchanged — provider-managed volume encryption on the existing
               project; no new store, no new column (the CHECK is a predicate).
    evidence: no DDL beyond a CHECK predicate and the function body; column set
               unchanged (verified against 037/055/064/084).
    defends_against: loss of the underlying storage medium.
    does_not_defend: a compromised service-role credential, which can already read
               and write the table; a compromised Postgres superuser; and any
               workspace co-member, who can SELECT these rows under
               audit_byok_use_workspace_member_select (mig 059).
    disclosed_as: Art. 30 register PA-23; DPD 2.3(w) after the PR-4 edit.
    live_verification: not applicable — posture unchanged; nothing new to verify.
in_transit:
  - connection: web-platform -> Supabase Postgres (existing)
    tls: existing, unchanged
    cert_verification: unchanged
    does_not_defend: an attacker already inside the application process.
    disclosed_as: unchanged.
exception: none — no plaintext exception, no cert verification disabled.
```

## Non-Goals (each needs a tracking issue, not prose)

- **Making a cap breach abort the run.** State plainly in the PR body: *the
  delegation cap enforces nothing before this PR and still enforces nothing after
  it; this is an accounting fix.* Under the return-status mechanism the caller
  receives the refusal as a value, which makes the pre-call gate substantially
  cheaper — frame the issue after PR-3.
- **A grantor-facing breach signal.** After PR-3 there is still **no path** by
  which the grantor learns a cap was breached: the Sentry rule reaches nobody and
  is Soleur's, not theirs; the Funded pane has no breach state, clamps
  `capRemaining` at zero (making "breached and still spending" pixel-identical to
  "spent exactly to cap"), and never renders the hourly figure at all — and the
  hourly branch is the one that fires first; `/dashboard/audit` filters the rows
  away and does not select the reason. **`attribution_shift_reason` is read by zero
  application consumers.** Either close this in PR-3 (the pane already has the rows
  via the service client — it needs one field and one state) or stop naming the
  dashboard as the remediation surface in `## User-Brand Impact`.
- **Backfill.** Impossible — the rows were never written and the table is WORM.
  Both windows self-heal within 24h with no operator action.
- **Re-running the Product/UX gate.** Tier NONE was mechanically true (no UI path
  in Files-to-Edit) but substantively wrong: `components/settings/delegation-funded-pane.tsx`
  and `components/chat/delegation-banner.tsx` display these figures, and going from
  a permanent `$0.00` to a real number on a billing surface is user-visible. The
  glob was true *because* the components are not in Files-to-Edit — which is the
  finding, not the exemption. **Re-check `wg-ui-feature-requires-pen-wireframe`
  against PR-1.**
- **A guard as a deliverable.** The marker addition extends an existing guard's
  map; no `## Guard Contract` section is required. If it grows into a new guard,
  that section becomes mandatory.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` was queried
and each planned path matched against every issue body with `jq --arg`. Zero hits.

## Domain Review

**Domains relevant:** Engineering, Legal. **Product:** re-open per the Non-Goal above.

### Engineering

**Status:** reviewed — seven agents. `data-integrity-guardian` (6 blocking),
`architecture-strategist` (6 blocking, forced the mechanism decision and the PR
split), `data-migration-expert` (5 blocking, decided the B3 arm on consumer
evidence), `test-design-reviewer` (5 blocking, score 6.6/10 C — T5 did not
discriminate, T7 passed green against the broken state),
`observability-coverage-reviewer` (4 blocking, *measured* the probe failure),
`code-simplicity-reviewer` (7→2 phases, the PR boundary), `spec-flow-analyzer`
(6 blocking, found the stale RLS policy and the grantee-lockout chain). A
strong-model advisor consult independently raised the plpgsql rollback finding and
the behavioural-vs-textual RED test point.

### Legal

**Status:** reviewed, **and must be re-run.** The CLO returned three BLOCKING
items — PA-23 (c)/(g) amendment; a three-way retention contradiction (PA-13 12
months vs PA-22 90 days vs PA-23/DPD 7 years, with no `pg_cron` sweep on the table
in any migration, so all three are unevidenced); and DPD §2.3(w) becoming
affirmatively false. It also correctly flagged that ADR-045 does **not**
pre-sanction the cap-breach extension. **But its GDPR ruling was derived from my
stale RLS claim** — it reasoned that grantor-blindness is the correct outcome per
side letter §4.2, when the live mig-059 policy makes every workspace co-member a
reader. Re-run the question against `audit_byok_use_workspace_member_select`.
`scripts/lint-legal-registers.sh` is blocking since #7881.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `DROP` + `CREATE` on a live billing RPC | Verify no view/trigger/default depends on it; the runner is `psql --single-transaction` so it is atomic; account for the PostgREST schema-cache reload. |
| The new body silently drops a clause from 084 — the class that bit mig 085, which lost 076's identity check | Derive the body from Phase 0's `pg_get_functiondef` output, not 084's source text; add an allowed-diff test asserting the difference is only the intended hunks. |
| The live dev body has drifted (2026-07-02 rogue dev migration precedent) | PR-0 reads `pg_get_functiondef` and stops on divergence. |
| The daily branch ships unverified (unreachable from live calls alone) | T8 aged-seeds at `now() − 2h` per the committed learning. |
| The fix is inert and every textual test passes | AC2 demoted to tripwire; T5b and the `ledger_row_written` tag are the real proofs. |
| B4 overflow left partly unfixed | There are **four** sites, not one: the `DECLARE` product, the product inside each `SUM`, and each `::int` cast of the SUM result. If B3 is fixed by correcting the readers, B4 largely evaporates — the two are coupled. |
| A6: `132_drop_unused_indexes.sql` dropped `audit_byok_use_delegation_ts_idx`, so both windows seq-scan under `FOR UPDATE` | PR-3 grows this table on paths that previously grew it not at all. Re-create the index — but note the runner forbids `CONCURRENTLY`, so weigh a blocking build in the `#migrate` job against the measured scan cost. |
| Attribution to the grantee is the wrong call | Named with four corrected trade-offs, routed to CPO sign-off and a re-run CLO question. |
