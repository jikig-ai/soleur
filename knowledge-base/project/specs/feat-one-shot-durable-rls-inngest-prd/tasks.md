---
feature: feat-one-shot-durable-rls-inngest-prd
plan: knowledge-base/project/plans/2026-06-30-security-durable-rls-inngest-event-trigger-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
decision: cron-hourly (event trigger declined at requires_cpo_signoff gate, 2026-07-01)
---

# Tasks — bound the cosmetic RLS advisor-recurrence window on soleur-inngest-prd

**DECISION 2026-07-01 (CPO).** The `ddl_command_end` event-trigger plan was a **rejected alternative** — it adds a migration-abort failure mode inside Inngest's `CREATE TABLE` txn to remove a merely cosmetic advisor email. The data-exposure hole was already closed permanently by the 2026-06-29 lockdown (`ALTER DEFAULT PRIVILEGES … REVOKE` → new tables born ungranted). **Shipped scope:** tighten the existing self-heal cron from daily to hourly, bounding the cosmetic `rls_disabled_in_public` advisor window to ≤1h. See ADR-030 changelog 2026-07-01 and the ⛔ banner atop the plan file.

## Phase 1 — Cron cadence + documentation (shipped)

- [x] 1.1 `.github/workflows/apply-inngest-rls.yml`: schedule `17 4 * * *` (daily) → `17 * * * *` (hourly); inline comment updated.
- [x] 1.2 Same workflow: refresh the SELF-HEAL header comment — correct the "a new table re-opens the anon hole" overstatement (the default-priv revoke already closes it), state the hourly window (≤1h), and record the declined event-trigger alternative.
- [x] 1.3 `ADR-030-inngest-as-durable-trigger-layer.md`: update I8 "enforced by" line (daily→hourly + window framing) and add the dated 2026-07-01 amendment-log entry capturing the CPO decision and the rejected event-trigger alternative.
- [x] 1.4 Plan file: prepend the ⛔ DECISION banner marking it a rejected-alternative record.

## Phase 2 — Tracking issue + post-merge verification

- [x] 2.1 Tracking issue #5813 opened (labels `domain/engineering`, `priority/p2-medium`, `type/security`); PR body uses `Ref #5813` (not `Closes` — post-merge verification keeps it open).
- [ ] 2.2 Post-merge (automated): the apply workflow runs hourly (next `:17`); the authoritative catalog/grant gate stays `violations=0`; a security advisor check confirms `rls_disabled_in_public = 0`.
- [ ] 2.3 `gh issue close <tracking-issue>` after the first hourly run is a clean no-op.

## Notes
- No new SQL artifact (`0002_*.sql` was NOT created). No event trigger. No C4 change. No new secret/sub-processor.
- `inngest-rls.test.sh` does not assert cron cadence (verified), so the daily→hourly change needs no test update.
