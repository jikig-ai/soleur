---
date: 2026-07-09
topic: invoice-skill
status: brainstorm-complete
branch: feat-invoice-skill
pr: 6259
issue: 6260
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Brainstorm: `/soleur:invoice` — the first finance-execution skill

## Origin

This brainstorm began as a broad review of the Soleur skill/agent library ("which
skills could be added or improved?"). Three parallel research passes (full inventory,
prior-signal mining, product/user lens) converged on one headline finding:

> **Sales, Finance, and Support each have a deep advisory *agent* bench but ~zero
> executable *skills*.** A founder can get *advice* on revenue/deals/tickets, but there
> is no slash-command verb to actually run the money-and-customers loop.

The operator chose to go deep on the **money-and-customers loop**, then narrowed to its
#1 slice: **`invoice` / get-paid**. This document captures that slice. The other slices
(support/customer-reply, sales/pipeline, company-health digest) are filed as tracked
follow-up issues, not lost.

## What We're Building

A new `/soleur:invoice` skill — the finance domain's **first executable verb**. v1 scope:
**read + guarded send**, driven entirely by the wired Stripe MCP (`mcp.stripe.com`,
OAuth-gated). No net-new product code.

**v1 flow:**
1. Ensure Stripe MCP is authenticated (OAuth precondition).
2. **Resolve & echo the connected account id + livemode**, require a typed confirm.
3. Read verbs: `list_customers`, list open/overdue invoices ("who owes you").
4. Create draft invoice (line items from operator) → **human-approval preview** →
   `finalize` (Stripe mints the sequential number) → send hosted-invoice link.
5. Chase: resend/remind an existing overdue invoice (uses Stripe-native dunning; **no**
   custom scheduler).

**Explicitly OUT of v1:** ledger record/reconcile, auto-send (no un-gated send path),
tax-rate fabrication, PDF generation, multi-currency FX, credit notes/refunds, a
finance-write agent.

## Why This Approach

- **Skill-shaped with zero net-new product code** (CTO, verified). The Stripe MCP is
  Stripe's official hosted remote; post-OAuth it exposes `create_invoice` /
  `finalize_invoice` / `list_customers` / etc. Pattern to copy: `linear-fetch/SKILL.md`.
- **"Generic/both" is satisfied for free** — the transactional slice acts on whichever
  Stripe account completed the OAuth. The CFO's divergence tax (rev-rec, which-ledger)
  only bites at the *reconcile* step, which is v2 and deferred anyway.
- **Thinnest slice that actually gets money in** while banking all three leaders' guardrails.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | First slice = `invoice`/get-paid (not support/pipeline/digest) | CFO-ranked #1; company's oxygen; Stripe MCP already wired |
| 2 | v1 = read + guarded send; reconcile deferred to v2 | Reconcile has no target book — `knowledge-base/finance/` is empty; deferring dodges the "both" divergence tax |
| 3 | Token-agnostic via the MCP OAuth plane | Acts on whoever authed; skill must **never** touch product `STRIPE_SECRET_KEY` |
| 4 | Mandatory human-approval preview before any send/dunning — **no auto-send** | CLO #1 footgun guardrail; triple-convergent with CTO account-safety + CFO account gate |
| 5 | Echo account id + **livemode** + typed-confirm before any write | Sharp edge = acting on the wrong account (test vs live, Soleur's vs founder's) |
| 6 | **Stripe owns invoice numbering** — never agent-minted | Sequential-no-gaps is a statutory tax requirement (CLO) |
| 7 | Refuse-to-fabricate tax/VAT/currency; require operator fact or Stripe Tax | Invoice is a statutory instrument, not a message (CLO) |
| 8 | No plaintext customer PII in logs/artifacts (HMAC-hash pattern) | EU-residency-pinned estate; Stripe is US (DPF+SCCs) — avoid residency drift (CLO) |
| 9 | Buildable + usable in Stripe **test mode** now; first **livemode** send gated on 3-doc GDPR lockstep | Legal docs don't block building v1, only flipping it live |
| 10 | ADR required: "Stripe MCP OAuth plane vs product billing key" | Dual credential-plane boundary is an architectural choice (CTO) — plan deliverable |

## Non-Goals (v1)

- Ledger record/reconcile (→ v2, needs a founder-side ledger first).
- Any auto-send / unattended dunning.
- Tax computation, FX, PDF, credit notes/refunds.
- A new finance-write agent (decide standalone-skill vs agent at plan time).
- Reusing `apps/web-platform/lib/stripe.ts` (product-runtime Node, not skill-callable).

## Open Questions

1. **Standalone skill vs finance-write agent owner?** No agent currently owns live Stripe
   writes; finance agents are read/analysis only. Decide at plan time (CTO capability gap).
2. **Where does the founder-side ledger live** (blocks v2 reconcile)? `knowledge-base/finance/`
   is empty today.
3. **Post-OAuth tool names** — enumerate the exact `mcp__plugin_soleur_stripe__*` tool set by
   running `__authenticate` then listing tools *before* writing the SKILL (CTO could not
   enumerate from the repo; server-provided at runtime).
4. **Legal threshold catalog gap** — invoice *issuance* is a new outbound money-demand surface
   not in `knowledge-base/legal/recommended-tools.md`; add a row?

## User-Brand Impact

- **Artifact:** the `/soleur:invoice` skill (sends real money-demands to real people).
- **Vector:** a non-technical founder trusts an autonomous skill that sends a wrong-amount /
  wrong-tax / duplicate invoice, or acts on the wrong Stripe account (test vs live).
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). Guardrails in Decisions 4–9 are the mitigation;
the human-approval preview gate is load-bearing and must survive to the shipped skill.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Finance (CFO)

**Summary:** Smallest valuable slice is create→send→list-overdue→resend; do NOT stub
record/reconcile (a half-built reconcile silently corrupts books). "Generic/both" pays a
divergence tax (rev-rec, ledger target, dunning cadence) — recommend founder→customers path
first with an explicit account-identity gate. v1→v2 blocker is the absent founder-side ledger,
not Stripe wiring. This is the finance domain's first executable skill.

### Legal (CLO) — verdict: PROCEED-WITH-GUARDRAILS

**Summary:** An invoice is a statutory tax instrument. Ship only with (a) hard human-approval
gate before any send/dunning, (b) refuse-to-fabricate on tax/rate/currency/numbering,
(c) Stripe-owned sequential numbering, (d) no plaintext PII to logs, (e) three-doc GDPR
lockstep before first real send. Biggest footgun: autonomous send of a wrong/duplicate
money-demand by a trusting non-technical founder. Invoice issuance is a new surface absent
from the legal threshold catalog.

### Engineering (CTO)

**Summary:** Skill-shaped, no net-new product code. Stripe MCP = official hosted remote
(`mcp.stripe.com`), OAuth-gated; post-auth exposes create/finalize/list tools. Copy the
`linear-fetch/SKILL.md` idiom. `lib/stripe.ts` + the webhook route are product-runtime/inbound-only
— do not reuse. Credential model is the sharp edge (two disjoint planes); echo account+livemode
+ typed-confirm, never touch `STRIPE_SECRET_KEY`. Recommend read-only slice first, then one
guarded create→finalize behind typed-yes. Needs an ADR for the credential-plane boundary.

## Capability Gaps

- **No agent owns live Stripe writes.** Finance agents (`cfo`, `revenue-analyst`,
  `financial-reporter`, `budget-analyst`) are read/analysis only; `operations:service-automator`
  is the nearest fit but not finance-scoped. Evidence: agent roster under
  `plugins/soleur/agents/finance/` + `plugins/soleur/agents/operations/`. Decide at plan time
  whether `/soleur:invoice` runs standalone or a finance-write agent is added.
- **No founder-side finance ledger.** `knowledge-base/finance/` does not exist; blocks the v2
  reconcile step. Evidence: `git ls-files knowledge-base/finance/` returns empty.

## Deferred (filed as follow-up issues)

- #6261 — `support` / customer-reply skill (money-and-customers loop slice #2).
- #6262 — `sales` / pipeline verbs skill (slice #3).
- #6263 — company-health digest — re-anchor `operator-digest` around MRR/customers/runway (slice #4).
- #6264 — `invoice` v2 — record/reconcile + founder-side ledger + finance-write agent + 3-doc GDPR lockstep.
