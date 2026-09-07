# Tasks — BYOK cap-breach audit ledger (#7829)

Plan: `knowledge-base/project/plans/2026-09-07-fix-byok-cap-breach-audit-ledger-plan.md`

Lane: cross-domain (no spec.md existed at plan time — fail-closed default, TR2).
Brand-survival threshold: single-user incident. CPO sign-off required before /work.

> **Phase 1 is a hard gate.** It can re-scope or invalidate the rest of this file.
> Do not start Phase 2 until 1.1 is settled empirically.

## Phase 1 — Preconditions and premise settlement (no writes)

- [ ] 1.1 Settle the blocking premise: does an unhandled `RAISE EXCEPTION` discard
      the preceding `INSERT` on the three sibling refusal branches? Probe dev with
      a real RPC call, then read the row from a **separate connection and new
      transaction**. Not `BEGIN; …; ROLLBACK;`.
- [ ] 1.2 Historical corroboration: `SELECT attribution_shift_reason, count(*)
      FROM public.audit_byok_use WHERE attribution_shift_reason IS NOT NULL
      GROUP BY 1;` — and check Sentry for `op=revoke-past-grace` / `op=expired`
      before treating a zero as decisive.
- [ ] 1.3 If the premise is confirmed false, STOP and re-plan around the
      architectural fork (return-a-refusal vs autonomous transaction vs
      caller-side record). Do not proceed with "INSERT before RAISE".
- [ ] 1.4 Settle B3: is `unit_cost_cents` a per-turn total or a per-token rate?
      Decide whether to fix the writer or the SUM expressions. Blocking.
- [ ] 1.5 Capture the live function body via `pg_get_functiondef` and diff against
      084's source. Stop on divergence (rogue dev-migration precedent).
- [ ] 1.6 Read the live CHECK constraint definition.
- [ ] 1.7 Read the scope-boundary comment in `infra/sentry/issue-alerts.tf`.
- [ ] 1.8 Resolve the side-letter fork mechanically (flag state + prd read-only
      count of live arms-length pairs + the counsel-review trigger).
- [ ] 1.9 Reconcile the three-way retention contradiction before writing headers.
- [ ] 1.10 Confirm 136 is still the next free migration number vs `origin/main`.

## Phase 2 — RED (failing tests first)

- [ ] 2.1 Primary/behavioural: edit
      `test/server/byok-delegation.atomicity.tenant-isolation.test.ts` to the
      post-fix invariants — row visible from a fresh connection; window SUM grown
      by the refused turn's cost; `audit == N` not `K`; summed spend
      `N x COST_CENTS` not `CAP_CENTS`.
- [ ] 2.2 Add T6 (below/at/above cap, strict `>` proof), T7 (one row per refusal),
      T8 (daily branch via `ts = now() - 2h` aged seed), T9 (attribution).
- [ ] 2.3 Secondary/textual tripwire: create
      `test/supabase-migrations/136-byok-cap-breach-audit-row.test.ts`.
- [ ] 2.4 Confirm both fail for the right reason, not a fixture error.

## Phase 3 — GREEN (the migration)

- [ ] 3.1 Write `136_byok_cap_breach_audit_row.sql` — header with #7829,
      LAWFUL_BASIS and RETENTION; widen the CHECK; redefine the RPC.
- [ ] 3.2 Derive the body from the Phase 1.5 `pg_get_functiondef` output, not from
      084 source text. Keep SECURITY DEFINER, `SET search_path = public, pg_temp`,
      `FOR UPDATE`; re-issue REVOKE/GRANT verbatim.
- [ ] 3.3 Cast the cost product to `bigint` (B4 overflow).
- [ ] 3.4 Add the `p_caller_user_id` vs `v_row.grantee_user_id` guard (A5).
- [ ] 3.5 Add the allowed-diff test: 136's body differs from 084's only in the
      intended hunks.
- [ ] 3.6 Write `136_..._down.sql` — restore the 084 body; **do not narrow the
      CHECK** (B5, Art. 17 cascade).
- [ ] 3.7 Decide on re-creating `audit_byok_use_delegation_ts_idx` (A6).

## Phase 4 — Coupled surfaces

- [ ] 4.1 Confirm `byok-rpc-body-markers.test.ts` resolves from 136 and all three
      markers survive; decide on a fourth INSERT-shaped marker.
- [ ] 4.2 `git grep -n 'check_and_record_byok_delegation_use' -- apps/web-platform`
      and sweep every call site and test.
- [ ] 4.3 Rewrite the false comment in `server/cost-writer.ts`.
- [ ] 4.4 Fix `server/byok-delegation-ui-resolver.ts` (`cost_cents` ->
      `unit_cost_cents`, mirror the discarded errors) (B6).
- [ ] 4.5 Fix `084_byok_delegation_withdrawals.down.sql` (A4).
- [ ] 4.6 Update the `066` column comment on `founder_id` (A8).
- [ ] 4.7 Amend the `audit == K` learning file.
- [ ] 4.8 Amend ADR-045 (correction + extension, per the CLO advisory).

## Phase 5 — Legal corpus

- [ ] 5.1 Amend Art. 30 register PA-23 limbs (c) and (g).
- [ ] 5.2 Generalise DPD 2.3(w) on canonical + mirror; re-pin
      `lib/legal/legal-doc-shas.ts`.
- [ ] 5.3 Run `bash scripts/lint-legal-registers.sh` green (blocking since #7881).
- [ ] 5.4 Side-letter amendment if Phase 1.8 found a live arms-length pair.
- [ ] 5.5 Run `/soleur:gdpr-gate` on the diff (A9, required gate).
- [ ] 5.6 Verify the audit viewer / DSAR bundle render `attribution_shift_reason`
      beside cost; fix inline or file.

## Phase 6 — Architecture artifacts

- [ ] 6.1 Read all three `.c4` files and record the actor/system/relationship
      enumeration behind the "no C4 impact" conclusion.
- [ ] 6.2 Run `bash plugins/soleur/test/c4-count-parity.test.sh` green.

## Phase 7 — Verify and ship

- [ ] 7.1 Offline suite + `./node_modules/.bin/tsc --noEmit` from
      `apps/web-platform`.
- [ ] 7.2 Live suite: `TENANT_INTEGRATION_TEST=1` against dev.
- [ ] 7.3 Verify AC13 (`git diff origin/main -- apps/web-platform/infra/sentry/`
      is empty) and AC14.
- [ ] 7.4 File tracking issues for every deferred item (pre-call enforcement gate;
      grantor RLS visibility; anything else deferred).
- [ ] 7.5 PR body states plainly: this is an accounting fix; the cap enforced
      nothing before and enforces nothing after. No backfill is possible.
