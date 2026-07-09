---
feature: invoice-skill
branch: feat-invoice-skill
issue: 6260
pr: 6259
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-09-feat-invoice-skill-plan.md
---

# Tasks: `/soleur:invoice` skill v1 (read + guarded send)

## Phase 0 — Runtime grounding (do FIRST, before writing SKILL.md)
- [ ] 0.1 Authenticate the Stripe MCP in a **test-mode** account; enumerate the actual post-OAuth tools.
- [ ] 0.2 Produce the **capability→tool binding table** for the 6 verbs (account-info, list, create-draft,
  retrieve, finalize, send, void) — exact tool name + call shape (named vs generic `stripe_api_read/write`).
- [ ] 0.3 **Idempotency-support probe:** does the write tool accept `Idempotency-Key`? Record yes/no.
  If NO → S4 uses the metadata-reconciliation fallback.
- [ ] 0.4 Confirm `get_stripe_account_info` returns account id + `livemode`.
- [ ] 0.5 Run `bun test plugins/soleur/test/components.test.ts` → confirm ≥ ~40 words of budget headroom.

## Phase 1 — Author `plugins/soleur/skills/invoice/SKILL.md`
- [ ] 1.1 Frontmatter: `name: invoice`; third-person `description` ("This skill should be used when…")
  ≤ 40 words / ≤ 1024 chars; `allowed-tools` = **only** Stripe MCP tools (NO Bash/Read/Doppler — AC4);
  `preconditions` = Stripe MCP authenticated. Mirror `linear-fetch` idiom.
- [ ] 1.2 S1 auth precondition + **re-entrant error table** (MCP-not-found/token-expired→re-auth,
  429→idempotency-gated retry, finalize-ok/send-failed→recovery).
- [ ] 1.3 S2 account+mode gate **before any read**: legible plain-language TEST/LIVE line + account id;
  **hard-STOP on `livemode==true`** → #6264 (no proceed path); test → single literal `yes`.
- [ ] 1.4 S3 list customers + overdue; empty-state → create-customer path.
- [ ] 1.5 S4 guarded create: resolve/create customer → duplicate guard → draft (idempotency/metadata) →
  pre-finalize computed-tax preview (STOP on `requires_location_inputs`) → `yes` → finalize → surface
  `hosted_invoice_url` → best-effort send → recovery (resend-same-id / void; never re-create).
- [ ] 1.6 S5 chase: re-trigger send behind the S2 mode gate + per-send `yes`; inherits livemode hard-stop.
- [ ] 1.7 S6 refuse-to-fabricate (tax/currency/entity; never mint number) + S7 no-plaintext-PII discipline.

## Phase 2 — Register the skill
- [ ] 2.1 `git grep -n "<old-skill-count>"` repo-wide (baseline).
- [ ] 2.2 Edit `plugin.json` description counts; add `docs/_data/skills.js` `SKILL_CATEGORIES` entry (finance/ops).
- [ ] 2.3 Run `bash scripts/sync-readme-counts.sh`; edit `plugins/soleur/README.md` skill listing.
- [ ] 2.4 Re-grep the old count across repo (plugin.json, both READMEs, brand-guide.md ×2, skills.js) → **zero stale** (AC6).

## Phase 3 — ADR + C4 + tests
- [ ] 3.1 Create `ADR-104-stripe-mcp-oauth-plane-vs-product-billing-key.md` (`status: adopting`; Decision;
  3 rejected alternatives incl. Stripe Connect; `## Consequences` = test-mode-until-#6264).
- [ ] 3.2 Add one `claude -> stripe` edge to `model.c4` citing ADR-104 (no `views.c4` change).
- [ ] 3.3 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 3.4 Run `bun test plugins/soleur/test/components.test.ts` (final budget/frontmatter/voice/kebab/backtick gate).

## Phase 4 — Verify against Acceptance Criteria
- [ ] 4.1 Walk AC1–AC11 (esp. AC3a livemode hard-stop grep, AC4 allowed-tools scope grep, AC5a idempotency/metadata,
  AC10 hosted-link + no post-finalize abort).
- [ ] 4.2 /work-time `/soleur:gdpr-gate` against the drafted SKILL.md (CG list).
- [ ] 4.3 Confirm test scenarios (livemode refusal, send-fails-after-finalize no-duplicate, empty account, chase gate).

## Notes
- Deferred to #6264 (v2): ledger reconcile, founder-side ledger, finance-write agent, **livemode enablement**
  + 6-location GDPR lockstep, legal threshold-catalog row. **ADR-104 ships in v1** (moved out of #6264).
- Stale C4 "61 skills"/"65 agents" count reconciliation tracked in #6268.
