---
feature: feat-one-shot-record-resend-pro-expense-and-ledger-gate
plan: knowledge-base/project/plans/2026-06-16-feat-record-resend-pro-expense-and-ledger-gate-plan.md
lane: cross-domain
brand_survival_threshold: none
---

# Tasks — Record Resend Pro expense + recurring-vendor-cost ledger gate

## Phase 0 — Preconditions (work skill)
- [ ] 0.1 Re-confirm runtime sending domain is `outbound.soleur.ai` (`grep OUTBOUND_FROM apps/web-platform/server/email-triage/outbound.ts`) — NOT `mail.soleur.ai`.
- [ ] 0.2 Re-measure `B_ALWAYS` (`echo $(($(wc -c < AGENTS.md) + $(wc -c < AGENTS.core.md)))`) and the new pointer byte length; confirm a ≥64-byte core-body trim target.
- [ ] 0.3 Confirm Resend row exists once in expenses.md; confirm cost-model Product COGS subtotal = 121.08 (pre-edit baseline).
- [ ] 0.4 Open Question check: has Resend Pro been applied? (operator) — decides whether post-merge operator AC + follow-up issue is needed.

## Phase 1 — Record the Resend Pro expense (PART 1)
- [ ] 1.1 Edit `knowledge-base/operations/expenses.md`: flip Resend row → Amount `20.00`, Status `active`, Renewal `-`; rewrite Notes (outbound.soleur.ai / Pro 50K / invoice-verify caveat per plan).
- [ ] 1.2 Bump frontmatter `last_updated: 2026-06-16`.
- [ ] 1.3 Verify ACs: `grep '| Resend |'` shows the new values + `verify` caveat; no duplicate row.

## Phase 2 — Refresh cost-model (PART 1 downstream, >10%)
- [ ] 2.1 Edit `knowledge-base/finance/cost-model.md`: flip Resend Tier-Triggers current-cost cell (provenance `@2026-06-16`).
- [ ] 2.2 Add Resend Pro line to Product COGS table; re-derive subtotal 121.08 → 141.08; update Totals + R&D/COGS split + provenance tags.
- [ ] 2.3 Verify: no stale `121.08`; arithmetic re-derives; bump cost-model `last_updated` if present.

## Phase 3 — Workflow Gate rule (PART 2, the cause)
- [ ] 3.1 Free ≥64 bytes from a verbose core rule body in `AGENTS.core.md` (show before/after bytes). Do NOT demote-for-budget.
- [ ] 3.2 Add `wg-record-recurring-vendor-expense-before-ready` body to `AGENTS.rest.md` (≤600 bytes, `[skill-enforced: …]` tag).
- [ ] 3.3 Add matching pointer `→ rest` to `AGENTS.md` Workflow Gates.
- [ ] 3.4 Run `lint-rule-ids.py` + `lint-agents-rule-budget.py` (+ enforcement-tags lint if present); confirm B_ALWAYS ≤ 23000.
- [ ] 3.5 Cite loader-class-fit (`session-rules-loader.sh:88-126`) in PR body.

## Phase 4 — Wire enforcement into /ship Phase 5.5 (PART 2, teeth)
- [ ] 4.1 Add "Recurring-Vendor-Expense Gate (mandatory)" subsection after the Undeferred Operator-Step Gate (telemetry, detection, rule, 3-option halt, headless-abort, Why).
- [ ] 4.2 Detection reuses the sibling gate's fenced-code-strip + list-anchored conventions (no self-trip).
- [ ] 4.3 Add `- [ ] Recurring-vendor-expense gate passed (Phase 5.5 gate)` to Phase 5 Final Checklist.
- [ ] 4.4 `bun test plugins/soleur/test/components.test.ts` green.

## Phase 5 — Ship
- [ ] 5.1 Review → QA-not-applicable (no UI) → compound → ship; PR body uses `Ref #5325`, reports post-edit B_ALWAYS + COGS arithmetic.
- [ ] 5.2 (Operator, post-merge) Verify Resend Pro charge on next invoice; update recorded-actual; file/close `deferred-automation` follow-up per Open Question.
