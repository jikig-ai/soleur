# Tasks — BYOK cap-breach audit ledger (#7829)

Plan: `knowledge-base/project/plans/2026-09-07-fix-byok-cap-breach-audit-ledger-plan.md`

Lane: cross-domain (no spec.md at plan time — fail-closed default, TR2).
Brand-survival threshold: single-user incident. CPO sign-off required before /work.

> **This is four PRs, not one.** Seven review agents converged on the split.
> PR-0 is a read-only spike whose output can still re-scope PR-3.
> Do not start PR-3 until PR-0 and PR-2 have landed.

## PR-0 — Spike (read-only, no merge)

- [ ] 0.1 Diff the live function body against 084's source:
      `pg_get_functiondef('public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure)`.
      Stop and re-plan on divergence (2026-07-02 rogue dev-migration precedent).
- [ ] 0.2 Confirm the plpgsql rollback finding empirically on dev: drive a sibling
      refusal branch, then read the row from a **separate connection and new
      transaction**. Never `BEGIN; SELECT rpc(...); ROLLBACK;` — that shape cannot
      distinguish which rollback discarded the row.
- [ ] 0.3 Read the live CHECK: `pg_get_constraintdef` for
      `audit_byok_use_attribution_shift_reason_check`.
- [ ] 0.4 Settle B3 against real data (read-only, prd) — the two distribution
      queries in the plan's Decision 3. If `median_cents` is tens and
      `median_tokens` thousands, the column is a turn total and the product readers
      are wrong.
- [ ] 0.5 Append the findings to the plan as a Phase-0 results paragraph.

## PR-1 — Grantor spend surface (ship first, independent)

- [ ] 1.1 `server/byok-delegation-ui-resolver.ts`: replace the non-existent
      `cost_cents` column. Derive the expression from the RPC's window expression,
      not a bare rename.
- [ ] 1.2 Sweep all **eight** unmirrored Supabase reads in that file (two
      `cost_cents`, two `error`-bound-then-discarded, four that never bind `error`).
      Route each through `reportSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`).
- [ ] 1.3 Add a degraded UI state — a Sentry mirror alone still shows the grantor a
      confident `$0.00` on a money surface.
- [ ] 1.4 Re-check `wg-ui-feature-requires-pen-wireframe` — this changes a
      user-visible billing figure on two components.

## PR-2 — Unit semantics (lands before PR-3)

- [ ] 2.1 Fix the **readers**, not the writer: `084`, `061`, `121` sum
      `token_count * unit_cost_cents` while two production consumers already read
      the column bare and correctly.
- [ ] 2.2 Fix all four B4 overflow sites (the `DECLARE` product, the product inside
      each `SUM`, each `::int` cast of the SUM result).
- [ ] 2.3 Add the T10 production-shaped-payload live test — the fixture's
      `COST_CENTS = 100 // 10 x 10` inverts production and is why B3 survived.
- [ ] 2.4 Amend ADR-041 (Layer 1 arithmetic).
- [ ] 2.5 State the 24h mixed-unit deploy window explicitly.

## PR-3 — #7829 proper

- [ ] 3.1 RED first: partition the live invariant (`IS NULL` rows == K summing to
      CAP_CENTS; reason rows == N-K), add T5b (heterogeneous cost — the only shape
      that discriminates include-vs-exclude), fix T7's positive control, add T8/T9.
- [ ] 3.2 RED: offline tripwire `137-byok-cap-breach-audit-row.test.ts`; anchor T3
      on `INTO v_hourly_spent`, not the comment the strip deletes.
- [ ] 3.3 `137_byok_cap_breach_audit_row.sql`: widen the CHECK; `DROP` + `CREATE`
      the RPC returning a refusal reason; all five refusal branches INSERT + return.
      Keep SECURITY DEFINER, `SET search_path = public, pg_temp`, `FOR UPDATE`.
- [ ] 3.4 Add the `p_caller_user_id` vs `v_row.grantee_user_id` guard.
- [ ] 3.5 `136_..._down.sql`: restore the 084 body; **do not narrow the CHECK**.
- [ ] 3.6 AC-DOWN: actually execute the down migration against dev.
- [ ] 3.7 `cost-writer.ts`: read `data` not `error.message`; add the missing
      `consent_withdrawn` branch; add the `ledger_row_written` tag; fix the comment.
- [ ] 3.8 Decide `121`'s SUM: add `AND delegation_id IS NULL`, or model the
      grantee-lockout as a tested accepted outcome. Not optional.
- [ ] 3.9 Reconcile `byok-rpc-markers.json` — the pinned markers include the RAISE
      strings and silently constrain the new shape.
- [ ] 3.10 Repair `084_byok_delegation_withdrawals.down.sql`.
- [ ] 3.11 Re-create `audit_byok_use_delegation_ts_idx` or record the measured scan
      cost (no `CONCURRENTLY` — the runner wraps each file in a transaction).
- [ ] 3.12 `066` column comment on `founder_id` (both sentences).
- [ ] 3.13 Write ADR-208 (re-derived `max + 1` on `origin/main`, which now tops out at ADR-206; was planned as ADR-205); re-verify the ordinal against `origin/main` before merge.
- [ ] 3.14 Amend the `audit == K` learning.
- [ ] 3.15 Art. 30 register PA-23 limbs (c) and (g).
- [ ] 3.16 `bash plugins/soleur/test/c4-count-parity.test.sh` green.
- [ ] 3.17 AC12: the comment-only correction to `issue-alerts.tf` (its claim
      becomes false when 137 lands). No routing change.
- [ ] 3.18 `git grep audit_byok_use_owner_select` — clear the stale live-policy
      comment in `app/(dashboard)/dashboard/audit/page.tsx`.

## PR-4 — Legal corpus (parallel, lands after PR-3)

- [ ] 4.1 DPD 2.3(w) paired edit (canonical + mirror); re-pin `legal-doc-shas.ts`.
- [ ] 4.2 Reconcile the three-way retention contradiction (PA-13 12mo / PA-22 90d /
      PA-23 + DPD 7y) and the absent `pg_cron` sweep.
- [ ] 4.3 `bash scripts/lint-legal-registers.sh` green (blocking since #7881).
- [ ] 4.4 Re-run the CLO GDPR question against the real mig-059 policy
      `audit_byok_use_workspace_member_select` — the original ruling assumed an
      owner-keyed policy that has not existed since mig 059.
- [ ] 4.5 Run `/soleur:gdpr-gate` on the diff.

## Cross-cutting

- [ ] X.1 File tracking issues (not prose): pre-call enforcement gate; grantor-facing
      breach signal; the derived `invocation_id` key; the dev-only drift probe's prd
      blind spot; side-letter version bump deferral.
- [ ] X.2 Re-run the Engineering and Legal domain reviews after PR-0 — both were
      conducted against the stale RLS premise and the unsettled B3 arm.
- [ ] X.3 PR bodies state plainly: this is an accounting fix; the delegation cap
      enforced nothing before and enforces nothing after. No backfill is possible.
